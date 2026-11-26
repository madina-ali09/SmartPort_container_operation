"""
SmartPort Projet 01 - Pipeline ETL complet (Python + SQLite)
SOURCES -> RAW -> STAGING -> CORE (etoile) -> MART, rejets, controles qualite, monitoring, idempotence.

Usage :   python etl_pipeline.py [dossier_csv] [fichier_base.db]
Par defaut : CSV dans ../../03_data/raw et base ../../03_data/warehouse/smartport_complet.db
Code extrait tel quel du notebook SmartPort_Projet01_Complet.ipynb (sections 0 a 7).
"""
import sys

# ---------------------------------------------------------------- 0. Boite a outils
import re, os, math, shutil, sqlite3, time
from datetime import datetime
import pandas as pd

pd.set_option("display.width", 200)
pd.set_option("display.max_colwidth", 90)
pd.set_option("display.max_rows", 60)

SOURCES = ["customers", "vessel_calls", "container_events", "yard_moves", "equipment"]

# Tables reconstruites à chaque exécution (le journal etl_run_metrics, lui, est conservé)
REBUILT = [
    "raw_customers", "raw_vessel_calls", "raw_container_events", "raw_yard_moves",
    "raw_equipment", "stg_customers", "stg_vessels", "stg_equipment",
    "stg_container_events", "stg_yard_moves", "fact_yard_move", "fact_container_event",
    "dim_equipment", "dim_freight_status", "dim_event_type", "dim_yard_area",
    "dim_vessel", "dim_customer", "dim_hour", "dim_date",
    "mart_kpi_events_per_day", "mart_kpi_move_by_area", "mart_kpi_vessel", "mart_kpi_service",
    "mart_kpi_customer", "mart_kpi_event_type", "mart_kpi_freight", "etl_rejects",
    "etl_quality_checks",
]

STEPS = []    # mémoire des étapes SQL exécutées
CHECKS = []   # mémoire des contrôles qualité exécutés

def connect(db_path="smartport_etl.db"):
    con = sqlite3.connect(db_path)
    con.execute("""CREATE TABLE IF NOT EXISTS etl_run_metrics (
        run_id TEXT, layer TEXT, step TEXT, rows_affected INTEGER,
        duration_s REAL, status TEXT, logged_at TEXT)""")
    con.commit()
    return con

def reset_layers(con):
    for t in REBUILT:
        con.execute(f"DROP TABLE IF EXISTS {t}")
    con.commit()

def new_run_id():
    return datetime.now().strftime("%Y%m%d-%H%M%S")

def log_metric(con, run_id, layer, step, rows, duration, status="OK"):
    con.execute("INSERT INTO etl_run_metrics VALUES (?,?,?,?,?,?,?)",
                (run_id, layer, step, rows, round(duration, 4), status,
                 datetime.now().isoformat(timespec="seconds")))
    con.commit()

def run_step(con, run_id, layer, step, sql, register=True, verbose=True):
    t0 = time.perf_counter()
    before = con.total_changes
    con.execute(sql)
    con.commit()
    m = re.match(r"\s*CREATE TABLE (\w+) AS", sql, re.I)
    if m:                                    # CREATE TABLE ... AS SELECT : on compte les lignes créées
        rows = con.execute(f"SELECT COUNT(*) FROM {m.group(1)}").fetchone()[0]
    elif re.match(r"\s*(WITH|INSERT)", sql, re.I):
        rows = con.total_changes - before
    else:                                    # CREATE TABLE vide, DROP...
        rows = None
    dt = time.perf_counter() - t0
    log_metric(con, run_id, layer, step, rows, dt)
    if register and not any(s[1] == step for s in STEPS):
        STEPS.append((layer, step, sql))
    if verbose:
        print(f"[{layer:<7}] {step:<36} lignes={rows if rows is not None else '-':>6}   {dt*1000:7.1f} ms")
    return rows

def load_raw(con, run_id, data_dir=".", verbose=True):
    for s in SOURCES:
        t0 = time.perf_counter()
        df = pd.read_csv(f"{data_dir}/{s}.csv", dtype=str, keep_default_na=False)
        df["_source_file"] = f"{s}.csv"
        df["_loaded_at"] = datetime.now().isoformat(timespec="seconds")
        df.to_sql(f"raw_{s}", con, if_exists="replace", index=False)
        log_metric(con, run_id, "RAW", f"load raw_{s}", len(df), time.perf_counter() - t0)
        if verbose:
            print(f"[RAW    ] load raw_{s:<30} lignes={len(df):>6}")


# ---------------------------------------------------------------- Demarrage
DATA_DIR = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "03_data", "raw")
DB_PATH = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "03_data", "warehouse", "smartport_complet.db")

con = connect(DB_PATH)
con.create_function("SQRT", 1, math.sqrt)
reset_layers(con)
run_id = new_run_id()
print("run_id =", run_id)

def q(sql):
    return pd.read_sql(sql, con)

# ---------------------------------------------------------------- 1. RAW
load_raw(con, run_id, DATA_DIR)

# ---------------------------------------------------------------- 2. STAGING
# stg_customers
run_step(con, run_id, "STAGING", "stg_customers", """
CREATE TABLE stg_customers AS
SELECT TRIM(customer_id) AS customer_id, TRIM(customer_name) AS customer_name,
       TRIM(group_code) AS group_code, TRIM(customer_type) AS customer_type
FROM raw_customers
WHERE TRIM(customer_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_customers GROUP BY TRIM(customer_id))
""")
# stg_vessels
run_step(con, run_id, "STAGING", "stg_vessels", """
CREATE TABLE stg_vessels AS
SELECT TRIM(vessel_id) AS vessel_id, TRIM(vessel_name) AS vessel_name,
       TRIM(vessel_type) AS vessel_type, TRIM(service_code) AS service_code
FROM raw_vessel_calls
WHERE TRIM(vessel_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_vessel_calls GROUP BY TRIM(vessel_id))
""")
# stg_equipment
run_step(con, run_id, "STAGING", "stg_equipment", """
CREATE TABLE stg_equipment AS
SELECT TRIM(equipment_id) AS equipment_id, TRIM(equipment_type) AS equipment_type,
       TRIM(home_area) AS home_area
FROM raw_equipment
WHERE TRIM(equipment_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_equipment GROUP BY TRIM(equipment_id))
""")
# create etl_rejects
run_step(con, run_id, "STAGING", "create etl_rejects", """
CREATE TABLE etl_rejects (
    reject_id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_table TEXT, raw_rowid INTEGER, business_key TEXT,
    rule_id TEXT, rule_description TEXT)
""")
# EV01 event_id manquant
run_step(con, run_id, "STAGING", "EV01 event_id manquant", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV01', 'event_id manquant'
FROM raw_container_events WHERE event_id IS NULL OR TRIM(event_id) = ''
""")
# EV02 event_id en double
run_step(con, run_id, "STAGING", "EV02 event_id en double", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV02', 'event_id en double (on garde la 1re ligne)'
FROM raw_container_events WHERE TRIM(event_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_container_events GROUP BY event_id)
""")
# EV03 date invalide
run_step(con, run_id, "STAGING", "EV03 date invalide", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV03', 'event_ts illisible'
FROM raw_container_events WHERE datetime(event_ts) IS NULL
""")
# EV04 type hors domaine
run_step(con, run_id, "STAGING", "EV04 type hors domaine", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV04', 'event_type hors domaine'
FROM raw_container_events WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL')
""")
# EV05 statut FCL/MTY invalide
run_step(con, run_id, "STAGING", "EV05 statut FCL/MTY invalide", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV05', 'freight_status hors FCL/MTY'
FROM raw_container_events WHERE freight_status NOT IN ('FCL','MTY')
""")
# EV06 poids hors plage
run_step(con, run_id, "STAGING", "EV06 poids hors plage", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV06', 'poids non numerique ou hors 0..40000 kg'
FROM raw_container_events WHERE CAST(gross_weight_kg AS REAL) <= 0 OR CAST(gross_weight_kg AS REAL) > 40000
""")
# EV07 client inconnu
run_step(con, run_id, "STAGING", "EV07 client inconnu", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV07', 'customer_id absent du referentiel'
FROM raw_container_events WHERE customer_id NOT IN (SELECT customer_id FROM stg_customers)
""")
# EV08 navire inconnu
run_step(con, run_id, "STAGING", "EV08 navire inconnu", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV08', 'vessel_id absent du referentiel'
FROM raw_container_events WHERE vessel_id NOT IN (SELECT vessel_id FROM stg_vessels)
""")
# EV09 zone manquante
run_step(con, run_id, "STAGING", "EV09 zone manquante", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV09', 'yard_area manquante'
FROM raw_container_events WHERE yard_area IS NULL OR TRIM(yard_area) = ''
""")
# MV01 move_id manquant
run_step(con, run_id, "STAGING", "MV01 move_id manquant", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV01', 'move_id manquant'
FROM raw_yard_moves WHERE move_id IS NULL OR TRIM(move_id) = ''
""")
# MV02 move_id en double
run_step(con, run_id, "STAGING", "MV02 move_id en double", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV02', 'move_id en double (on garde la 1re ligne)'
FROM raw_yard_moves WHERE TRIM(move_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_yard_moves GROUP BY move_id)
""")
# MV03 date invalide
run_step(con, run_id, "STAGING", "MV03 date invalide", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV03', 'move_ts illisible'
FROM raw_yard_moves WHERE datetime(move_ts) IS NULL
""")
# MV04 equipement inconnu
run_step(con, run_id, "STAGING", "MV04 equipement inconnu", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV04', 'equipment_id absent du referentiel'
FROM raw_yard_moves WHERE equipment_id NOT IN (SELECT equipment_id FROM stg_equipment)
""")
# MV05 zone manquante
run_step(con, run_id, "STAGING", "MV05 zone manquante", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV05', 'from_area ou to_area manquante'
FROM raw_yard_moves WHERE from_area IS NULL OR TRIM(from_area) = '' OR to_area IS NULL OR TRIM(to_area) = ''
""")
# MV06 conteneur inconnu
run_step(con, run_id, "STAGING", "MV06 conteneur inconnu", """
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV06', 'container_id absent de container_events'
FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events)
""")
# Un tableau vide signifie qu'aucune ligne n'est rejetée. C'est attendu sur ces données très propres : la section 8 prouve que les règles fonctionnent en injectant volontairement des erreurs.
# stg_container_events
run_step(con, run_id, "STAGING", "stg_container_events", """
CREATE TABLE stg_container_events AS
SELECT rowid AS raw_rowid,
       CAST(event_id AS INTEGER)        AS event_id,
       TRIM(container_id)               AS container_id,
       TRIM(customer_id)                AS customer_id,
       TRIM(vessel_id)                  AS vessel_id,
       TRIM(event_type)                 AS event_type,
       datetime(event_ts)               AS event_ts,
       TRIM(yard_area)                  AS yard_area_raw,
       SUBSTR(TRIM(yard_area), 1, 3)    AS yard_area_std,   -- Y08B -> Y08
       TRIM(freight_status)             AS freight_status,
       CAST(gross_weight_kg AS REAL)    AS gross_weight_kg
FROM raw_container_events
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'container_events')
""")
# stg_yard_moves
run_step(con, run_id, "STAGING", "stg_yard_moves", """
CREATE TABLE stg_yard_moves AS
SELECT rowid AS raw_rowid,
       CAST(move_id AS INTEGER) AS move_id, TRIM(container_id) AS container_id,
       datetime(move_ts) AS move_ts, TRIM(from_area) AS from_area, TRIM(to_area) AS to_area,
       TRIM(equipment_id) AS equipment_id
FROM raw_yard_moves
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'yard_moves')
""")

# ---------------------------------------------------------------- 3. CORE
# create dim_date
run_step(con, run_id, "CORE", "create dim_date", """
CREATE TABLE dim_date (date_key INTEGER PRIMARY KEY, full_date TEXT NOT NULL, year INTEGER, month INTEGER, day INTEGER,
    year_month TEXT, week_of_year INTEGER, day_of_week INTEGER, is_weekend INTEGER)
""")
# create dim_hour
run_step(con, run_id, "CORE", "create dim_hour", """
CREATE TABLE dim_hour (hour_key INTEGER PRIMARY KEY, period TEXT)
""")
# create dim_customer
run_step(con, run_id, "CORE", "create dim_customer", """
CREATE TABLE dim_customer (customer_key INTEGER PRIMARY KEY AUTOINCREMENT, customer_id TEXT NOT NULL UNIQUE,
    customer_name TEXT, group_code TEXT, customer_type TEXT)
""")
# create dim_vessel
run_step(con, run_id, "CORE", "create dim_vessel", """
CREATE TABLE dim_vessel (vessel_key INTEGER PRIMARY KEY AUTOINCREMENT, vessel_id TEXT NOT NULL UNIQUE,
    vessel_name TEXT, vessel_type TEXT, service_code TEXT)
""")
# create dim_yard_area
run_step(con, run_id, "CORE", "create dim_yard_area", """
CREATE TABLE dim_yard_area (area_key INTEGER PRIMARY KEY AUTOINCREMENT, area_code TEXT NOT NULL UNIQUE,
    parent_area TEXT NOT NULL, is_subarea INTEGER NOT NULL)
""")
# create dim_event_type
run_step(con, run_id, "CORE", "create dim_event_type", """
CREATE TABLE dim_event_type (event_type_key INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT NOT NULL UNIQUE, event_family TEXT)
""")
# create dim_freight_status
run_step(con, run_id, "CORE", "create dim_freight_status", """
CREATE TABLE dim_freight_status (freight_key INTEGER PRIMARY KEY AUTOINCREMENT, freight_status TEXT NOT NULL UNIQUE, freight_label TEXT)
""")
# create dim_equipment
run_step(con, run_id, "CORE", "create dim_equipment", """
CREATE TABLE dim_equipment (equipment_key INTEGER PRIMARY KEY AUTOINCREMENT, equipment_id TEXT NOT NULL UNIQUE,
    equipment_type TEXT, home_area TEXT)
""")
# load dim_date
run_step(con, run_id, "CORE", "load dim_date", """
INSERT INTO dim_date
SELECT CAST(strftime('%Y%m%d', d) AS INTEGER), d, CAST(strftime('%Y', d) AS INTEGER), CAST(strftime('%m', d) AS INTEGER),
       CAST(strftime('%d', d) AS INTEGER), strftime('%Y-%m', d), CAST(strftime('%W', d) AS INTEGER),
       CAST(strftime('%w', d) AS INTEGER), CASE WHEN strftime('%w', d) IN ('0','6') THEN 1 ELSE 0 END
FROM (SELECT DISTINCT DATE(event_ts) AS d FROM stg_container_events
      UNION SELECT DISTINCT DATE(move_ts) FROM stg_yard_moves)
""")
# load dim_hour
run_step(con, run_id, "CORE", "load dim_hour", """
WITH RECURSIVE h(n) AS (SELECT 0 UNION ALL SELECT n+1 FROM h WHERE n < 23)
INSERT INTO dim_hour
SELECT n, CASE WHEN n < 6 THEN 'Nuit' WHEN n < 12 THEN 'Matin' WHEN n < 18 THEN 'Apres-midi' ELSE 'Soir' END FROM h
""")
# load dim_customer
run_step(con, run_id, "CORE", "load dim_customer", """
INSERT INTO dim_customer (customer_id, customer_name, group_code, customer_type)
SELECT customer_id, customer_name, group_code, customer_type FROM stg_customers ORDER BY customer_id
""")
# load dim_vessel
run_step(con, run_id, "CORE", "load dim_vessel", """
INSERT INTO dim_vessel (vessel_id, vessel_name, vessel_type, service_code)
SELECT vessel_id, vessel_name, vessel_type, service_code FROM stg_vessels ORDER BY vessel_id
""")
# load dim_yard_area
run_step(con, run_id, "CORE", "load dim_yard_area", """
INSERT INTO dim_yard_area (area_code, parent_area, is_subarea)
SELECT a, SUBSTR(a, 1, 3), CASE WHEN LENGTH(a) > 3 THEN 1 ELSE 0 END   -- regle : suffixe lettre = sous-zone
FROM (SELECT yard_area_raw AS a FROM stg_container_events
      UNION SELECT from_area FROM stg_yard_moves UNION SELECT to_area FROM stg_yard_moves) ORDER BY a
""")
# load dim_event_type
run_step(con, run_id, "CORE", "load dim_event_type", """
INSERT INTO dim_event_type (event_type, event_family)
SELECT DISTINCT event_type,
       CASE event_type WHEN 'DISCHARGE' THEN 'Operations navire' WHEN 'LOAD' THEN 'Operations navire'
                       WHEN 'RECEIVE' THEN 'Gate' WHEN 'DELIVER' THEN 'Gate' WHEN 'MOVE' THEN 'Cour'
                       WHEN 'STUFF' THEN 'Manutention' WHEN 'SEAL' THEN 'Manutention' ELSE 'Autre' END
FROM stg_container_events ORDER BY event_type
""")
# load dim_freight_status
run_step(con, run_id, "CORE", "load dim_freight_status", """
INSERT INTO dim_freight_status (freight_status, freight_label)
SELECT DISTINCT freight_status, CASE freight_status WHEN 'FCL' THEN 'Plein' WHEN 'MTY' THEN 'Vide' ELSE 'Inconnu' END
FROM stg_container_events ORDER BY freight_status
""")
# load dim_equipment
run_step(con, run_id, "CORE", "load dim_equipment", """
INSERT INTO dim_equipment (equipment_id, equipment_type, home_area)
SELECT equipment_id, equipment_type, home_area FROM stg_equipment ORDER BY equipment_id
""")
# create fact_container_event
run_step(con, run_id, "CORE", "create fact_container_event", """
CREATE TABLE fact_container_event (
    event_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    customer_key INTEGER NOT NULL REFERENCES dim_customer(customer_key), vessel_key INTEGER NOT NULL REFERENCES dim_vessel(vessel_key),
    area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), event_type_key INTEGER NOT NULL REFERENCES dim_event_type(event_type_key),
    freight_key INTEGER NOT NULL REFERENCES dim_freight_status(freight_key),
    event_ts TEXT NOT NULL, event_count INTEGER NOT NULL DEFAULT 1, gross_weight_kg REAL)
""")
# create fact_yard_move
run_step(con, run_id, "CORE", "create fact_yard_move", """
CREATE TABLE fact_yard_move (
    move_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    from_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), to_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key),
    equipment_key INTEGER NOT NULL REFERENCES dim_equipment(equipment_key),
    move_ts TEXT NOT NULL, move_count INTEGER NOT NULL DEFAULT 1, is_same_area INTEGER NOT NULL)
""")
# load fact_container_event
run_step(con, run_id, "CORE", "load fact_container_event", """
INSERT INTO fact_container_event
SELECT e.event_id, e.container_id, CAST(strftime('%Y%m%d', e.event_ts) AS INTEGER), CAST(strftime('%H', e.event_ts) AS INTEGER),
       c.customer_key, v.vessel_key, a.area_key, t.event_type_key, f.freight_key, e.event_ts, 1, e.gross_weight_kg
FROM stg_container_events e
JOIN dim_customer c       ON c.customer_id = e.customer_id
JOIN dim_vessel v         ON v.vessel_id = e.vessel_id
JOIN dim_yard_area a      ON a.area_code = e.yard_area_raw
JOIN dim_event_type t     ON t.event_type = e.event_type
JOIN dim_freight_status f ON f.freight_status = e.freight_status
""")
# load fact_yard_move
run_step(con, run_id, "CORE", "load fact_yard_move", """
INSERT INTO fact_yard_move
SELECT m.move_id, m.container_id, CAST(strftime('%Y%m%d', m.move_ts) AS INTEGER), CAST(strftime('%H', m.move_ts) AS INTEGER),
       af.area_key, at.area_key, q.equipment_key, m.move_ts, 1, CASE WHEN m.from_area = m.to_area THEN 1 ELSE 0 END
FROM stg_yard_moves m
JOIN dim_yard_area af ON af.area_code = m.from_area
JOIN dim_yard_area at ON at.area_code = m.to_area
JOIN dim_equipment q  ON q.equipment_id = m.equipment_id
""")

# ---------------------------------------------------------------- 4. MART
# mart_kpi_events_per_day
run_step(con, run_id, "MART", "mart_kpi_events_per_day", """
CREATE TABLE mart_kpi_events_per_day AS
SELECT d.full_date, d.year_month, COUNT(*) AS nb_evenements, COUNT(DISTINCT f.container_id) AS nb_conteneurs,
       ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, d.year_month
""")
# mart_kpi_move_by_area
run_step(con, run_id, "MART", "mart_kpi_move_by_area", """
CREATE TABLE mart_kpi_move_by_area AS
SELECT a.area_code, a.parent_area, a.is_subarea, COUNT(*) AS nb_move
FROM fact_container_event f
JOIN dim_event_type t ON t.event_type_key = f.event_type_key
JOIN dim_yard_area a  ON a.area_key = f.area_key
WHERE t.event_type = 'MOVE'
GROUP BY a.area_code, a.parent_area, a.is_subarea
""")
# mart_kpi_vessel
run_step(con, run_id, "MART", "mart_kpi_vessel", """
CREATE TABLE mart_kpi_vessel AS
SELECT v.vessel_id, v.vessel_name, v.vessel_type, v.service_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.vessel_id, v.vessel_name, v.vessel_type, v.service_code
""")
# mart_kpi_service
run_step(con, run_id, "MART", "mart_kpi_service", """
CREATE TABLE mart_kpi_service AS
SELECT service_code, COUNT(*) AS nb_navires, SUM(nb_evenements) AS nb_evenements,
       ROUND(1.0*SUM(nb_evenements)/COUNT(*), 1) AS evenements_par_navire,
       ROUND(SUM(tonnes), 0) AS tonnes,
       ROUND(100.0*SUM(nb_evenements)/(SELECT SUM(nb_evenements) FROM mart_kpi_vessel), 1) AS pct_evenements
FROM mart_kpi_vessel GROUP BY service_code
""")
# mart_kpi_customer
run_step(con, run_id, "MART", "mart_kpi_customer", """
CREATE TABLE mart_kpi_customer AS
SELECT c.customer_id, c.customer_name, c.customer_type, c.group_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_customer c        ON c.customer_key = f.customer_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY c.customer_id, c.customer_name, c.customer_type, c.group_code
""")
# mart_kpi_event_type
run_step(con, run_id, "MART", "mart_kpi_event_type", """
CREATE TABLE mart_kpi_event_type AS
SELECT t.event_type, t.event_family, COUNT(*) AS nb_evenements, ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_event_type t      ON t.event_type_key = f.event_type_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY t.event_type, t.event_family
""")
# mart_kpi_freight
run_step(con, run_id, "MART", "mart_kpi_freight", """
CREATE TABLE mart_kpi_freight AS
SELECT fs.freight_status, fs.freight_label, COUNT(*) AS nb_evenements,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM fact_container_event), 1) AS pct_evenements,
       ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg
FROM fact_container_event f JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY fs.freight_status, fs.freight_label
""")

# ---------------------------------------------------------------- 5. CONTROLES QUALITE
def init_quality_table(con):
    con.execute("DROP TABLE IF EXISTS etl_quality_checks")
    con.execute("""CREATE TABLE etl_quality_checks (check_id TEXT, layer TEXT, description TEXT,
                   observed REAL, expected REAL, status TEXT)""")
    con.commit()

def controle(con, check_id, layer, description, sql, expected=0, severity="FAIL", register=True, verbose=True):
    observed = con.execute(sql).fetchone()[0]
    status = "PASS" if observed == expected else severity
    con.execute("INSERT INTO etl_quality_checks VALUES (?,?,?,?,?,?)",
                (check_id, layer, description, observed, expected, status))
    con.commit()
    if register and not any(c[0] == check_id for c in CHECKS):
        CHECKS.append((check_id, layer, description, sql, expected, severity))
    if verbose:
        print(f"{status:<5} {check_id} [{layer}] {description} -> observé = {observed:g}")
    return status

init_quality_table(con)

# ### 5.2 Les contrôles, un par cellule

# Q01 · Volume : 1 si raw_container_events est vide (attendu 0)
controle(con, "Q01", "RAW", "Volume : 1 si raw_container_events est vide (attendu 0)", """
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_container_events
""", 0, "FAIL")

# Q02 · Unicite de event_id dans fact_container_event
controle(con, "Q02", "CORE", "Unicite de event_id dans fact_container_event", """
SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM fact_container_event
""", 0, "FAIL")

# Q03 · Unicite de move_id dans fact_yard_move
controle(con, "Q03", "CORE", "Unicite de move_id dans fact_yard_move", """
SELECT COUNT(*) - COUNT(DISTINCT move_id) FROM fact_yard_move
""", 0, "FAIL")

# Q04 · Valeurs nulles dans les colonnes cles de stg_container_events
controle(con, "Q04", "STAGING", "Valeurs nulles dans les colonnes cles de stg_container_events", """
SELECT COUNT(*) FROM stg_container_events WHERE event_id IS NULL OR container_id IS NULL OR customer_id IS NULL
     OR vessel_id IS NULL OR event_type IS NULL OR event_ts IS NULL OR yard_area_raw IS NULL OR gross_weight_kg IS NULL
""", 0, "FAIL")

# Q05 · Integrite referentielle : cles de fact_container_event absentes des dimensions
controle(con, "Q05", "CORE", "Integrite referentielle : cles de fact_container_event absentes des dimensions", """
SELECT (SELECT COUNT(*) FROM fact_container_event WHERE customer_key NOT IN (SELECT customer_key FROM dim_customer))
          + (SELECT COUNT(*) FROM fact_container_event WHERE vessel_key NOT IN (SELECT vessel_key FROM dim_vessel))
          + (SELECT COUNT(*) FROM fact_container_event WHERE area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_container_event WHERE event_type_key NOT IN (SELECT event_type_key FROM dim_event_type))
          + (SELECT COUNT(*) FROM fact_container_event WHERE freight_key NOT IN (SELECT freight_key FROM dim_freight_status))
          + (SELECT COUNT(*) FROM fact_container_event WHERE date_key NOT IN (SELECT date_key FROM dim_date))
""", 0, "FAIL")

# Q06 · Integrite referentielle : cles de fact_yard_move absentes des dimensions
controle(con, "Q06", "CORE", "Integrite referentielle : cles de fact_yard_move absentes des dimensions", """
SELECT (SELECT COUNT(*) FROM fact_yard_move WHERE from_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE to_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE equipment_key NOT IN (SELECT equipment_key FROM dim_equipment))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE date_key NOT IN (SELECT date_key FROM dim_date))
""", 0, "FAIL")

# Q07 · Domaine des valeurs : event_type et freight_status hors referentiel
controle(con, "Q07", "STAGING", "Domaine des valeurs : event_type et freight_status hors referentiel", """
SELECT COUNT(*) FROM stg_container_events
      WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL') OR freight_status NOT IN ('FCL','MTY')
""", 0, "FAIL")

# Q08 · Plage du poids : valeurs hors 0..40000 kg dans fact_container_event
controle(con, "Q08", "CORE", "Plage du poids : valeurs hors 0..40000 kg dans fact_container_event", """
SELECT COUNT(*) FROM fact_container_event WHERE gross_weight_kg <= 0 OR gross_weight_kg > 40000
""", 0, "FAIL")

# Q09 · Reconciliation evenements : RAW - (CORE + rejets)
controle(con, "Q09", "CORE", "Reconciliation evenements : RAW - (CORE + rejets)", """
SELECT (SELECT COUNT(*) FROM raw_container_events) - (SELECT COUNT(*) FROM fact_container_event)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'container_events')
""", 0, "FAIL")

# Q10 · Reconciliation mouvements : RAW - (CORE + rejets)
controle(con, "Q10", "CORE", "Reconciliation mouvements : RAW - (CORE + rejets)", """
SELECT (SELECT COUNT(*) FROM raw_yard_moves) - (SELECT COUNT(*) FROM fact_yard_move)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'yard_moves')
""", 0, "FAIL")

# Q11 · Conservation de la mesure : poids total STAGING - poids total CORE (kg)
controle(con, "Q11", "CORE", "Conservation de la mesure : poids total STAGING - poids total CORE (kg)", """
SELECT ROUND((SELECT SUM(gross_weight_kg) FROM stg_container_events) - (SELECT SUM(gross_weight_kg) FROM fact_container_event), 3)
""", 0, "FAIL")

# Q12 · Coherence MART : somme des evenements par jour - lignes de fact_container_event
controle(con, "Q12", "MART", "Coherence MART : somme des evenements par jour - lignes de fact_container_event", """
SELECT (SELECT SUM(nb_evenements) FROM mart_kpi_events_per_day) - (SELECT COUNT(*) FROM fact_container_event)
""", 0, "FAIL")

# Q13 · Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)
controle(con, "Q13", "CORE", "Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)", """
SELECT COUNT(*) FROM fact_yard_move WHERE is_same_area = 1
""", 0, "WARN")

# Q14 · Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)
controle(con, "Q14", "CORE", "Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)", """
SELECT COUNT(*) FROM fact_yard_move WHERE container_id NOT IN (SELECT container_id FROM fact_container_event)
""", 0, "FAIL")

# Q15 · Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)
controle(con, "Q15", "STAGING", "Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)", """
SELECT COUNT(*) FROM stg_container_events WHERE yard_area_raw <> yard_area_std
""", 0, "INFO")

# ### 5.3 Les 17 règles qualité du prof

# ROW_COUNT · la table n'est pas vide (gravité HIGH)
TABLES_CLES = {"customers": "customer_id", "vessel_calls": "vessel_id", "container_events": "event_id",
              "yard_moves": "move_id", "equipment": "equipment_id"}

for t in TABLES_CLES:
    controle(con, f"DQ_ROW_COUNT_{t}", "RAW", f"ROW_COUNT {t} : table vide ? (0 = non vide)",
             f"SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_{t}", 0, "FAIL")

# Les volumes attendus, pour expliquer l'« évolution » demandée par la règle :

# DUPLICATE_CHECK · la clé métier est unique (gravité HIGH)
for t, cle in TABLES_CLES.items():
    controle(con, f"DQ_DUPLICATE_CHECK_{t}", "RAW", f"DUPLICATE_CHECK {t} : doublons sur {cle}",
             f"SELECT COUNT(*) - COUNT(DISTINCT TRIM({cle})) FROM raw_{t}", 0, "FAIL")

# NULL_RATE · pourcentage de cellules vides dans la table (gravité MEDIUM)
for t in TABLES_CLES:
    cols = [r[1] for r in con.execute(f"PRAGMA table_info(raw_{t})") if not r[1].startswith("_")]
    vides = " + ".join(f"SUM(CASE WHEN {c} IS NULL OR TRIM({c}) = '' THEN 1 ELSE 0 END)" for c in cols)
    sql = f"SELECT ROUND(100.0 * ({vides}) / (COUNT(*) * {len(cols)}), 2) FROM raw_{t}"
    controle(con, f"DQ_NULL_RATE_{t}", "RAW", f"NULL_RATE {t} : % de cellules vides", sql, 0, "WARN")

# FK_CONTAINER et FK_EQUIPMENT · les clés des mouvements existent dans les tables de référence (gravité HIGH)
controle(con, "FK_CONTAINER", "RAW", "FK_CONTAINER : mouvements dont le container_id est absent de container_events",
         "SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events)", 0, "FAIL")

controle(con, "FK_EQUIPMENT", "RAW", "FK_EQUIPMENT : mouvements dont l'equipment_id est absent de equipment",
         "SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(equipment_id) NOT IN (SELECT TRIM(equipment_id) FROM raw_equipment)", 0, "FAIL")

print("\n=== Synthese des controles qualite ===")
print(q('SELECT status, COUNT(*) AS nb FROM etl_quality_checks GROUP BY status ORDER BY status'))
print("\n=== Reconciliation (RAW = charge + rejete) ===")
print(q('''
SELECT 'container_events' AS source,
       (SELECT COUNT(*) FROM raw_container_events) AS raw,
       (SELECT COUNT(*) FROM fact_container_event) AS charge,
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='container_events') AS rejete
UNION ALL
SELECT 'yard_moves',
       (SELECT COUNT(*) FROM raw_yard_moves),
       (SELECT COUNT(*) FROM fact_yard_move),
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='yard_moves')
'''))

# ---------------------------------------------------------------- 6. MONITORING
print("\n=== Monitoring : duree et volume par couche ===")
print(q(f"SELECT layer, COUNT(*) AS nb_etapes, ROUND(SUM(duration_s), 3) AS duree_s FROM etl_run_metrics WHERE run_id = '{run_id}' GROUP BY layer"))

# ---------------------------------------------------------------- 7. IDEMPOTENCE
def rejouer_pipeline(data_dir=".", db_path="smartport_etl.db"):
    c = connect(db_path)
    reset_layers(c)
    rid = new_run_id()
    load_raw(c, rid, data_dir, verbose=False)
    for layer, name, sql in STEPS:
        run_step(c, rid, layer, name, sql, register=False, verbose=False)
    init_quality_table(c)
    statuts = [controle(c, *chk, register=False, verbose=False) for chk in CHECKS]
    c.close()
    return statuts

print(len(STEPS), "étapes SQL et", len(CHECKS), "contrôles mémorisés")


if __name__ == "__main__":
    def etat():
        return {t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
                for t in ["fact_container_event", "fact_yard_move", "dim_customer", "etl_rejects"]}
    avant = etat()
    time.sleep(1.1)
    rejouer_pipeline(DATA_DIR, DB_PATH)
    apres = etat()
    print("\nIdempotence - avant :", avant, " apres :", apres, " identique :", avant == apres)
