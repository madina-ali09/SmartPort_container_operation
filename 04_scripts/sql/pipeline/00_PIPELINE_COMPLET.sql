-- =============================================================================================
-- ETL : PIPELINE COMPLET (RAW -> STAGING -> CORE -> MART + controles) en un seul fichier
-- =============================================================================================
-- Equivalent a executer dans l'ordre 00_reset, 01_raw, 02_staging, 03_core_dimensions,
-- 04_core_faits, 05_mart_kpi, 06_controles_qualite, 07_reconciliation. Pre-requis : tables sources
-- remplies. Executer en entier : F5 / Ctrl+Entree.
-- =============================================================================================


-- =============================================================================================
-- ETL / 00 : REINITIALISATION (idempotence)
-- =============================================================================================
-- Supprime toutes les tables reconstruites par le pipeline (RAW, STAGING, CORE, MART, rejets,
-- controles). Les tables sources (customers, ...) et le journal etl_run_metrics ne sont pas
-- touches. Relancer le pipeline apres ce fichier donne toujours le meme resultat : pas de
-- doublons.
-- =============================================================================================

DROP TABLE IF EXISTS raw_customers;
DROP TABLE IF EXISTS raw_vessel_calls;
DROP TABLE IF EXISTS raw_container_events;
DROP TABLE IF EXISTS raw_yard_moves;
DROP TABLE IF EXISTS raw_equipment;
DROP TABLE IF EXISTS stg_customers;
DROP TABLE IF EXISTS stg_vessels;
DROP TABLE IF EXISTS stg_equipment;
DROP TABLE IF EXISTS stg_container_events;
DROP TABLE IF EXISTS stg_yard_moves;
DROP TABLE IF EXISTS fact_yard_move;
DROP TABLE IF EXISTS fact_container_event;
DROP TABLE IF EXISTS dim_equipment;
DROP TABLE IF EXISTS dim_freight_status;
DROP TABLE IF EXISTS dim_event_type;
DROP TABLE IF EXISTS dim_yard_area;
DROP TABLE IF EXISTS dim_vessel;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_hour;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS mart_kpi_events_per_day;
DROP TABLE IF EXISTS mart_kpi_move_by_area;
DROP TABLE IF EXISTS mart_kpi_vessel;
DROP TABLE IF EXISTS mart_kpi_service;
DROP TABLE IF EXISTS mart_kpi_customer;
DROP TABLE IF EXISTS mart_kpi_event_type;
DROP TABLE IF EXISTS mart_kpi_freight;
DROP TABLE IF EXISTS etl_rejects;
DROP TABLE IF EXISTS etl_quality_checks;


-- =============================================================================================
-- ETL / 01 : COUCHE RAW (copie brute, tout en texte)
-- =============================================================================================
-- Pre-requis : les 5 tables sources sont remplies (voir 04_scripts/sql/exploration/par_theme/01_creation_et_import_tables.sql).
-- RAW = copie fidele des sources, AUCUNE transformation. Toutes les colonnes sont en TEXT, les
-- valeurs vides deviennent '' et on ajoute 2 colonnes de tracabilite : _source_file et _loaded_at.
-- (Dans le notebook, cette etape est faite par load_raw() en Python ; ici c'est l'equivalent en
-- SQL pur.)
-- =============================================================================================

DROP TABLE IF EXISTS raw_customers;
CREATE TABLE raw_customers (
    customer_id TEXT,
    customer_name TEXT,
    group_code TEXT,
    customer_type TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_customers
SELECT COALESCE(CAST(customer_id AS TEXT), ''), COALESCE(CAST(customer_name AS TEXT), ''), COALESCE(CAST(group_code AS TEXT), ''), COALESCE(CAST(customer_type AS TEXT), ''), 'customers.csv', datetime('now')
FROM customers;

DROP TABLE IF EXISTS raw_vessel_calls;
CREATE TABLE raw_vessel_calls (
    vessel_id TEXT,
    vessel_name TEXT,
    vessel_type TEXT,
    service_code TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_vessel_calls
SELECT COALESCE(CAST(vessel_id AS TEXT), ''), COALESCE(CAST(vessel_name AS TEXT), ''), COALESCE(CAST(vessel_type AS TEXT), ''), COALESCE(CAST(service_code AS TEXT), ''), 'vessel_calls.csv', datetime('now')
FROM vessel_calls;

DROP TABLE IF EXISTS raw_container_events;
CREATE TABLE raw_container_events (
    event_id TEXT,
    container_id TEXT,
    customer_id TEXT,
    vessel_id TEXT,
    event_type TEXT,
    event_ts TEXT,
    yard_area TEXT,
    freight_status TEXT,
    gross_weight_kg TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_container_events
SELECT COALESCE(CAST(event_id AS TEXT), ''), COALESCE(CAST(container_id AS TEXT), ''), COALESCE(CAST(customer_id AS TEXT), ''), COALESCE(CAST(vessel_id AS TEXT), ''), COALESCE(CAST(event_type AS TEXT), ''), COALESCE(CAST(event_ts AS TEXT), ''), COALESCE(CAST(yard_area AS TEXT), ''), COALESCE(CAST(freight_status AS TEXT), ''), COALESCE(CAST(gross_weight_kg AS TEXT), ''), 'container_events.csv', datetime('now')
FROM container_events;

DROP TABLE IF EXISTS raw_yard_moves;
CREATE TABLE raw_yard_moves (
    move_id TEXT,
    container_id TEXT,
    move_ts TEXT,
    from_area TEXT,
    to_area TEXT,
    equipment_id TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_yard_moves
SELECT COALESCE(CAST(move_id AS TEXT), ''), COALESCE(CAST(container_id AS TEXT), ''), COALESCE(CAST(move_ts AS TEXT), ''), COALESCE(CAST(from_area AS TEXT), ''), COALESCE(CAST(to_area AS TEXT), ''), COALESCE(CAST(equipment_id AS TEXT), ''), 'yard_moves.csv', datetime('now')
FROM yard_moves;

DROP TABLE IF EXISTS raw_equipment;
CREATE TABLE raw_equipment (
    equipment_id TEXT,
    equipment_type TEXT,
    home_area TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_equipment
SELECT COALESCE(CAST(equipment_id AS TEXT), ''), COALESCE(CAST(equipment_type AS TEXT), ''), COALESCE(CAST(home_area AS TEXT), ''), 'equipment.csv', datetime('now')
FROM equipment;

-- Verification : volumes RAW (attendu 80 / 120 / 9000 / 4500 / 40)
SELECT 'raw_customers' AS table_raw, COUNT(*) AS nb FROM raw_customers
UNION ALL SELECT 'raw_vessel_calls', COUNT(*) FROM raw_vessel_calls
UNION ALL SELECT 'raw_container_events', COUNT(*) FROM raw_container_events
UNION ALL SELECT 'raw_yard_moves', COUNT(*) FROM raw_yard_moves
UNION ALL SELECT 'raw_equipment', COUNT(*) FROM raw_equipment;


-- =============================================================================================
-- ETL / 02 : COUCHE STAGING (nettoyage, typage, regles de rejet)
-- =============================================================================================
-- STAGING = donnees nettoyees et typees. Les lignes qui violent une regle sont COPIEES dans
-- etl_rejects (avec l'identifiant de la regle) puis exclues des tables stg_*.
-- Ordre important : dimensions -> table des rejets -> regles EV/MV -> stg_container_events et
-- stg_yard_moves.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_customers
-- Nettoie les clients : TRIM des textes et suppression des doublons sur customer_id (on garde la
-- 1ere ligne).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers AS
SELECT TRIM(customer_id) AS customer_id, TRIM(customer_name) AS customer_name,
       TRIM(group_code) AS group_code, TRIM(customer_type) AS customer_type
FROM raw_customers
WHERE TRIM(customer_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_customers GROUP BY TRIM(customer_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_vessels
-- Nettoie les navires : TRIM des textes et suppression des doublons sur vessel_id.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_vessels;
CREATE TABLE stg_vessels AS
SELECT TRIM(vessel_id) AS vessel_id, TRIM(vessel_name) AS vessel_name,
       TRIM(vessel_type) AS vessel_type, TRIM(service_code) AS service_code
FROM raw_vessel_calls
WHERE TRIM(vessel_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_vessel_calls GROUP BY TRIM(vessel_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_equipment
-- Nettoie les equipements : TRIM des textes et suppression des doublons sur equipment_id.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_equipment;
CREATE TABLE stg_equipment AS
SELECT TRIM(equipment_id) AS equipment_id, TRIM(equipment_type) AS equipment_type,
       TRIM(home_area) AS home_area
FROM raw_equipment
WHERE TRIM(equipment_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_equipment GROUP BY TRIM(equipment_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] create etl_rejects
-- Table des rejets : chaque ligne refusee est ecrite ici avec la regle et la raison du rejet.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS etl_rejects;
CREATE TABLE etl_rejects (
    reject_id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_table TEXT, raw_rowid INTEGER, business_key TEXT,
    rule_id TEXT, rule_description TEXT);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV01 event_id manquant
-- Regle de rejet EV01 : event_id manquant.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV01', 'event_id manquant'
FROM raw_container_events WHERE event_id IS NULL OR TRIM(event_id) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV02 event_id en double
-- Regle de rejet EV02 : event_id en double (on garde la 1ere occurrence).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV02', 'event_id en double (on garde la 1re ligne)'
FROM raw_container_events WHERE TRIM(event_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_container_events GROUP BY event_id);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV03 date invalide
-- Regle de rejet EV03 : date d'evenement illisible.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV03', 'event_ts illisible'
FROM raw_container_events WHERE datetime(event_ts) IS NULL;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV04 type hors domaine
-- Regle de rejet EV04 : event_type hors du domaine autorise.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV04', 'event_type hors domaine'
FROM raw_container_events WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV05 statut FCL/MTY invalide
-- Regle de rejet EV05 : freight_status different de FCL / MTY.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV05', 'freight_status hors FCL/MTY'
FROM raw_container_events WHERE freight_status NOT IN ('FCL','MTY');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV06 poids hors plage
-- Regle de rejet EV06 : poids hors de la plage 0 a 40000 kg.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV06', 'poids non numerique ou hors 0..40000 kg'
FROM raw_container_events WHERE CAST(gross_weight_kg AS REAL) <= 0 OR CAST(gross_weight_kg AS REAL) > 40000;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV07 client inconnu
-- Regle de rejet EV07 : client inconnu (customer_id absent de customers).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV07', 'customer_id absent du referentiel'
FROM raw_container_events WHERE customer_id NOT IN (SELECT customer_id FROM stg_customers);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV08 navire inconnu
-- Regle de rejet EV08 : navire inconnu (vessel_id absent de vessel_calls).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV08', 'vessel_id absent du referentiel'
FROM raw_container_events WHERE vessel_id NOT IN (SELECT vessel_id FROM stg_vessels);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV09 zone manquante
-- Regle de rejet EV09 : zone yard_area manquante.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV09', 'yard_area manquante'
FROM raw_container_events WHERE yard_area IS NULL OR TRIM(yard_area) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV01 move_id manquant
-- Regle de rejet MV01 : move_id manquant.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV01', 'move_id manquant'
FROM raw_yard_moves WHERE move_id IS NULL OR TRIM(move_id) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV02 move_id en double
-- Regle de rejet MV02 : move_id en double.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV02', 'move_id en double (on garde la 1re ligne)'
FROM raw_yard_moves WHERE TRIM(move_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_yard_moves GROUP BY move_id);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV03 date invalide
-- Regle de rejet MV03 : date de mouvement illisible.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV03', 'move_ts illisible'
FROM raw_yard_moves WHERE datetime(move_ts) IS NULL;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV04 equipement inconnu
-- Regle de rejet MV04 : equipement inconnu.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV04', 'equipment_id absent du referentiel'
FROM raw_yard_moves WHERE equipment_id NOT IN (SELECT equipment_id FROM stg_equipment);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV05 zone manquante
-- Regle de rejet MV05 : zone de depart ou d'arrivee manquante.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV05', 'from_area ou to_area manquante'
FROM raw_yard_moves WHERE from_area IS NULL OR TRIM(from_area) = '' OR to_area IS NULL OR TRIM(to_area) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV06 conteneur inconnu
-- Regle de rejet MV06 : conteneur absent des evenements.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV06', 'container_id absent de container_events'
FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events);

-- ---------------------------------------------------------------------------------------------
-- Resultat des regles de rejet (tableau vide = aucune ligne rejetee, attendu sur ces donnees propres)
-- ---------------------------------------------------------------------------------------------
SELECT rule_id, rule_description, COUNT(*) AS nb
FROM etl_rejects
GROUP BY rule_id, rule_description;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_container_events
-- Evenements conteneurs types (INTEGER, REAL, date normalisee). Zone standardisee Y08B -> Y08
-- (yard_area_std), zone d'origine conservee (yard_area_raw). Les lignes rejetees sont exclues.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_container_events;
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
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'container_events');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_yard_moves
-- Mouvements de cour types, sans les lignes rejetees.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_yard_moves;
CREATE TABLE stg_yard_moves AS
SELECT rowid AS raw_rowid,
       CAST(move_id AS INTEGER) AS move_id, TRIM(container_id) AS container_id,
       datetime(move_ts) AS move_ts, TRIM(from_area) AS from_area, TRIM(to_area) AS to_area,
       TRIM(equipment_id) AS equipment_id
FROM raw_yard_moves
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'yard_moves');

-- ---------------------------------------------------------------------------------------------
-- Controle : zone d'origine vs zone standardisee (Y08B -> Y08)
-- ---------------------------------------------------------------------------------------------
SELECT yard_area_raw, yard_area_std, COUNT(*) AS nb
FROM stg_container_events
GROUP BY 1, 2
ORDER BY 1;


-- =============================================================================================
-- ETL / 03 : COUCHE CORE - DIMENSIONS (Data Warehouse en etoile)
-- =============================================================================================
-- Chaque dimension : creation de la table puis chargement. dim_date et dim_hour permettent
-- d'analyser par jour / heure ; les autres dimensions portent une cle de substitution (..._key).
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_date
-- CORE : creation de la dimension dim_date (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (date_key INTEGER PRIMARY KEY, full_date TEXT NOT NULL, year INTEGER, month INTEGER, day INTEGER,
    year_month TEXT, week_of_year INTEGER, day_of_week INTEGER, is_weekend INTEGER);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_hour
-- CORE : creation de la dimension dim_hour (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_hour;
CREATE TABLE dim_hour (hour_key INTEGER PRIMARY KEY, period TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_customer
-- CORE : creation de la dimension dim_customer (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (customer_key INTEGER PRIMARY KEY AUTOINCREMENT, customer_id TEXT NOT NULL UNIQUE,
    customer_name TEXT, group_code TEXT, customer_type TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_vessel
-- CORE : creation de la dimension dim_vessel (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_vessel;
CREATE TABLE dim_vessel (vessel_key INTEGER PRIMARY KEY AUTOINCREMENT, vessel_id TEXT NOT NULL UNIQUE,
    vessel_name TEXT, vessel_type TEXT, service_code TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_yard_area
-- CORE : creation de la dimension dim_yard_area (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_yard_area;
CREATE TABLE dim_yard_area (area_key INTEGER PRIMARY KEY AUTOINCREMENT, area_code TEXT NOT NULL UNIQUE,
    parent_area TEXT NOT NULL, is_subarea INTEGER NOT NULL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_event_type
-- CORE : creation de la dimension dim_event_type (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_event_type;
CREATE TABLE dim_event_type (event_type_key INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT NOT NULL UNIQUE, event_family TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_freight_status
-- CORE : creation de la dimension dim_freight_status (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_freight_status;
CREATE TABLE dim_freight_status (freight_key INTEGER PRIMARY KEY AUTOINCREMENT, freight_status TEXT NOT NULL UNIQUE, freight_label TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_equipment
-- CORE : creation de la dimension dim_equipment (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_equipment;
CREATE TABLE dim_equipment (equipment_key INTEGER PRIMARY KEY AUTOINCREMENT, equipment_id TEXT NOT NULL UNIQUE,
    equipment_type TEXT, home_area TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_date
-- CORE : chargement de la dimension dim_date depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_date
SELECT CAST(strftime('%Y%m%d', d) AS INTEGER), d, CAST(strftime('%Y', d) AS INTEGER), CAST(strftime('%m', d) AS INTEGER),
       CAST(strftime('%d', d) AS INTEGER), strftime('%Y-%m', d), CAST(strftime('%W', d) AS INTEGER),
       CAST(strftime('%w', d) AS INTEGER), CASE WHEN strftime('%w', d) IN ('0','6') THEN 1 ELSE 0 END
FROM (SELECT DISTINCT DATE(event_ts) AS d FROM stg_container_events
      UNION SELECT DISTINCT DATE(move_ts) FROM stg_yard_moves);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_hour
-- CORE : chargement de la dimension dim_hour depuis STAGING.
-- ---------------------------------------------------------------------------------------------
WITH RECURSIVE h(n) AS (SELECT 0 UNION ALL SELECT n+1 FROM h WHERE n < 23)
INSERT INTO dim_hour
SELECT n, CASE WHEN n < 6 THEN 'Nuit' WHEN n < 12 THEN 'Matin' WHEN n < 18 THEN 'Apres-midi' ELSE 'Soir' END FROM h;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_customer
-- CORE : chargement de la dimension dim_customer depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_customer (customer_id, customer_name, group_code, customer_type)
SELECT customer_id, customer_name, group_code, customer_type FROM stg_customers ORDER BY customer_id;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_vessel
-- CORE : chargement de la dimension dim_vessel depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_vessel (vessel_id, vessel_name, vessel_type, service_code)
SELECT vessel_id, vessel_name, vessel_type, service_code FROM stg_vessels ORDER BY vessel_id;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_yard_area
-- CORE : chargement de la dimension dim_yard_area depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_yard_area (area_code, parent_area, is_subarea)
SELECT a, SUBSTR(a, 1, 3), CASE WHEN LENGTH(a) > 3 THEN 1 ELSE 0 END   -- regle : suffixe lettre = sous-zone
FROM (SELECT yard_area_raw AS a FROM stg_container_events
      UNION SELECT from_area FROM stg_yard_moves UNION SELECT to_area FROM stg_yard_moves) ORDER BY a;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_event_type
-- CORE : chargement de la dimension dim_event_type depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_event_type (event_type, event_family)
SELECT DISTINCT event_type,
       CASE event_type WHEN 'DISCHARGE' THEN 'Operations navire' WHEN 'LOAD' THEN 'Operations navire'
                       WHEN 'RECEIVE' THEN 'Gate' WHEN 'DELIVER' THEN 'Gate' WHEN 'MOVE' THEN 'Cour'
                       WHEN 'STUFF' THEN 'Manutention' WHEN 'SEAL' THEN 'Manutention' ELSE 'Autre' END
FROM stg_container_events ORDER BY event_type;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_freight_status
-- CORE : chargement de la dimension dim_freight_status depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_freight_status (freight_status, freight_label)
SELECT DISTINCT freight_status, CASE freight_status WHEN 'FCL' THEN 'Plein' WHEN 'MTY' THEN 'Vide' ELSE 'Inconnu' END
FROM stg_container_events ORDER BY freight_status;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_equipment
-- CORE : chargement de la dimension dim_equipment depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_equipment (equipment_id, equipment_type, home_area)
SELECT equipment_id, equipment_type, home_area FROM stg_equipment ORDER BY equipment_id;



-- =============================================================================================
-- ETL / 04 : COUCHE CORE - TABLES DE FAITS
-- =============================================================================================
-- Grain : fact_container_event = 1 ligne par evenement conteneur ; fact_yard_move = 1 ligne par
-- mouvement de cour. Les faits referencent les dimensions par leurs cles de substitution.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [CORE] create fact_container_event
-- CORE : creation de la table de faits fact_container_event (cles etrangeres vers les dimensions).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_container_event;
CREATE TABLE fact_container_event (
    event_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    customer_key INTEGER NOT NULL REFERENCES dim_customer(customer_key), vessel_key INTEGER NOT NULL REFERENCES dim_vessel(vessel_key),
    area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), event_type_key INTEGER NOT NULL REFERENCES dim_event_type(event_type_key),
    freight_key INTEGER NOT NULL REFERENCES dim_freight_status(freight_key),
    event_ts TEXT NOT NULL, event_count INTEGER NOT NULL DEFAULT 1, gross_weight_kg REAL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create fact_yard_move
-- CORE : creation de la table de faits fact_yard_move (cles etrangeres vers les dimensions).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_yard_move;
CREATE TABLE fact_yard_move (
    move_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    from_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), to_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key),
    equipment_key INTEGER NOT NULL REFERENCES dim_equipment(equipment_key),
    move_ts TEXT NOT NULL, move_count INTEGER NOT NULL DEFAULT 1, is_same_area INTEGER NOT NULL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load fact_container_event
-- CORE : chargement de la table de faits fact_container_event (jointures sur les dimensions).
-- ---------------------------------------------------------------------------------------------
INSERT INTO fact_container_event
SELECT e.event_id, e.container_id, CAST(strftime('%Y%m%d', e.event_ts) AS INTEGER), CAST(strftime('%H', e.event_ts) AS INTEGER),
       c.customer_key, v.vessel_key, a.area_key, t.event_type_key, f.freight_key, e.event_ts, 1, e.gross_weight_kg
FROM stg_container_events e
JOIN dim_customer c       ON c.customer_id = e.customer_id
JOIN dim_vessel v         ON v.vessel_id = e.vessel_id
JOIN dim_yard_area a      ON a.area_code = e.yard_area_raw
JOIN dim_event_type t     ON t.event_type = e.event_type
JOIN dim_freight_status f ON f.freight_status = e.freight_status;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load fact_yard_move
-- CORE : chargement de la table de faits fact_yard_move (jointures sur les dimensions).
-- ---------------------------------------------------------------------------------------------
INSERT INTO fact_yard_move
SELECT m.move_id, m.container_id, CAST(strftime('%Y%m%d', m.move_ts) AS INTEGER), CAST(strftime('%H', m.move_ts) AS INTEGER),
       af.area_key, at.area_key, q.equipment_key, m.move_ts, 1, CASE WHEN m.from_area = m.to_area THEN 1 ELSE 0 END
FROM stg_yard_moves m
JOIN dim_yard_area af ON af.area_code = m.from_area
JOIN dim_yard_area at ON at.area_code = m.to_area
JOIN dim_equipment q  ON q.equipment_id = m.equipment_id;

-- ---------------------------------------------------------------------------------------------
-- Apercu du fait principal
-- ---------------------------------------------------------------------------------------------
SELECT * FROM fact_container_event LIMIT 5;


-- =============================================================================================
-- ETL / 05 : COUCHE MART (une table par KPI)
-- =============================================================================================
-- Les 6 KPI du catalogue (10_EXPECTED_KPIS) : evenements par jour, MOVE par zone, volumes par
-- navire/service, activite par client, poids moyen par type d'evenement, part FCL/MTY.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_events_per_day
-- MART : une table par KPI mart_kpi_events_per_day.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_events_per_day;
CREATE TABLE mart_kpi_events_per_day AS
SELECT d.full_date, d.year_month, COUNT(*) AS nb_evenements, COUNT(DISTINCT f.container_id) AS nb_conteneurs,
       ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, d.year_month;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_move_by_area
-- MART : une table par KPI mart_kpi_move_by_area.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_move_by_area;
CREATE TABLE mart_kpi_move_by_area AS
SELECT a.area_code, a.parent_area, a.is_subarea, COUNT(*) AS nb_move
FROM fact_container_event f
JOIN dim_event_type t ON t.event_type_key = f.event_type_key
JOIN dim_yard_area a  ON a.area_key = f.area_key
WHERE t.event_type = 'MOVE'
GROUP BY a.area_code, a.parent_area, a.is_subarea;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_vessel
-- MART : une table par KPI mart_kpi_vessel.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_vessel;
CREATE TABLE mart_kpi_vessel AS
SELECT v.vessel_id, v.vessel_name, v.vessel_type, v.service_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.vessel_id, v.vessel_name, v.vessel_type, v.service_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_service
-- MART : une table par KPI mart_kpi_service.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_service;
CREATE TABLE mart_kpi_service AS
SELECT service_code, COUNT(*) AS nb_navires, SUM(nb_evenements) AS nb_evenements,
       ROUND(1.0*SUM(nb_evenements)/COUNT(*), 1) AS evenements_par_navire,
       ROUND(SUM(tonnes), 0) AS tonnes,
       ROUND(100.0*SUM(nb_evenements)/(SELECT SUM(nb_evenements) FROM mart_kpi_vessel), 1) AS pct_evenements
FROM mart_kpi_vessel GROUP BY service_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_customer
-- MART : une table par KPI mart_kpi_customer.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_customer;
CREATE TABLE mart_kpi_customer AS
SELECT c.customer_id, c.customer_name, c.customer_type, c.group_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_customer c        ON c.customer_key = f.customer_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY c.customer_id, c.customer_name, c.customer_type, c.group_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_event_type
-- MART : une table par KPI mart_kpi_event_type.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_event_type;
CREATE TABLE mart_kpi_event_type AS
SELECT t.event_type, t.event_family, COUNT(*) AS nb_evenements, ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_event_type t      ON t.event_type_key = f.event_type_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY t.event_type, t.event_family;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_freight
-- MART : une table par KPI mart_kpi_freight.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_freight;
CREATE TABLE mart_kpi_freight AS
SELECT fs.freight_status, fs.freight_label, COUNT(*) AS nb_evenements,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM fact_container_event), 1) AS pct_evenements,
       ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg
FROM fact_container_event f JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY fs.freight_status, fs.freight_label;

-- Pour consulter un KPI : SELECT * FROM mart_kpi_move_by_area ORDER BY nb_move DESC;


-- =============================================================================================
-- ETL / 06 : CONTROLES QUALITE (15 controles du pipeline + 17 regles du prof)
-- =============================================================================================
-- Chaque controle calcule une valeur observee et la compare a la valeur attendue (0 en general).
-- Statut : PASS si observe = attendu, sinon FAIL (ou WARN pour les alertes non bloquantes).
-- Resultats dans la table etl_quality_checks. A lancer APRES les etapes 01 a 05.
-- =============================================================================================

DROP TABLE IF EXISTS etl_quality_checks;
CREATE TABLE etl_quality_checks (check_id TEXT, layer TEXT, description TEXT,
    observed REAL, expected REAL, status TEXT);

-- ---------------------------------------------------------------------------------------------
-- A. Les 15 controles du pipeline (Q01 a Q15)
-- ---------------------------------------------------------------------------------------------

-- Q01 [RAW] Volume : 1 si raw_container_events est vide (attendu 0)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q01', 'RAW', 'Volume : 1 si raw_container_events est vide (attendu 0)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_container_events
) AS obs);

-- Q02 [CORE] Unicite de event_id dans fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q02', 'CORE', 'Unicite de event_id dans fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM fact_container_event
) AS obs);

-- Q03 [CORE] Unicite de move_id dans fact_yard_move
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q03', 'CORE', 'Unicite de move_id dans fact_yard_move', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT move_id) FROM fact_yard_move
) AS obs);

-- Q04 [STAGING] Valeurs nulles dans les colonnes cles de stg_container_events
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q04', 'STAGING', 'Valeurs nulles dans les colonnes cles de stg_container_events', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events WHERE event_id IS NULL OR container_id IS NULL OR customer_id IS NULL
     OR vessel_id IS NULL OR event_type IS NULL OR event_ts IS NULL OR yard_area_raw IS NULL OR gross_weight_kg IS NULL
) AS obs);

-- Q05 [CORE] Integrite referentielle : cles de fact_container_event absentes des dimensions
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q05', 'CORE', 'Integrite referentielle : cles de fact_container_event absentes des dimensions', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM fact_container_event WHERE customer_key NOT IN (SELECT customer_key FROM dim_customer))
          + (SELECT COUNT(*) FROM fact_container_event WHERE vessel_key NOT IN (SELECT vessel_key FROM dim_vessel))
          + (SELECT COUNT(*) FROM fact_container_event WHERE area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_container_event WHERE event_type_key NOT IN (SELECT event_type_key FROM dim_event_type))
          + (SELECT COUNT(*) FROM fact_container_event WHERE freight_key NOT IN (SELECT freight_key FROM dim_freight_status))
          + (SELECT COUNT(*) FROM fact_container_event WHERE date_key NOT IN (SELECT date_key FROM dim_date))
) AS obs);

-- Q06 [CORE] Integrite referentielle : cles de fact_yard_move absentes des dimensions
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q06', 'CORE', 'Integrite referentielle : cles de fact_yard_move absentes des dimensions', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM fact_yard_move WHERE from_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE to_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE equipment_key NOT IN (SELECT equipment_key FROM dim_equipment))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE date_key NOT IN (SELECT date_key FROM dim_date))
) AS obs);

-- Q07 [STAGING] Domaine des valeurs : event_type et freight_status hors referentiel
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q07', 'STAGING', 'Domaine des valeurs : event_type et freight_status hors referentiel', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events
      WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL') OR freight_status NOT IN ('FCL','MTY')
) AS obs);

-- Q08 [CORE] Plage du poids : valeurs hors 0..40000 kg dans fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q08', 'CORE', 'Plage du poids : valeurs hors 0..40000 kg dans fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_container_event WHERE gross_weight_kg <= 0 OR gross_weight_kg > 40000
) AS obs);

-- Q09 [CORE] Reconciliation evenements : RAW - (CORE + rejets)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q09', 'CORE', 'Reconciliation evenements : RAW - (CORE + rejets)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM raw_container_events) - (SELECT COUNT(*) FROM fact_container_event)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'container_events')
) AS obs);

-- Q10 [CORE] Reconciliation mouvements : RAW - (CORE + rejets)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q10', 'CORE', 'Reconciliation mouvements : RAW - (CORE + rejets)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM raw_yard_moves) - (SELECT COUNT(*) FROM fact_yard_move)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'yard_moves')
) AS obs);

-- Q11 [CORE] Conservation de la mesure : poids total STAGING - poids total CORE (kg)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q11', 'CORE', 'Conservation de la mesure : poids total STAGING - poids total CORE (kg)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT ROUND((SELECT SUM(gross_weight_kg) FROM stg_container_events) - (SELECT SUM(gross_weight_kg) FROM fact_container_event), 3)
) AS obs);

-- Q12 [MART] Coherence MART : somme des evenements par jour - lignes de fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q12', 'MART', 'Coherence MART : somme des evenements par jour - lignes de fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT SUM(nb_evenements) FROM mart_kpi_events_per_day) - (SELECT COUNT(*) FROM fact_container_event)
) AS obs);

-- Q13 [CORE] Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q13', 'CORE', 'Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_yard_move WHERE is_same_area = 1
) AS obs);

-- Q14 [CORE] Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q14', 'CORE', 'Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_yard_move WHERE container_id NOT IN (SELECT container_id FROM fact_container_event)
) AS obs);

-- Q15 [STAGING] Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q15', 'STAGING', 'Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'INFO' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events WHERE yard_area_raw <> yard_area_std
) AS obs);

-- ---------------------------------------------------------------------------------------------
-- B. Les 17 regles qualite du prof (05_governance/data_quality_rules.csv)
--    ROW_COUNT, DUPLICATE_CHECK, NULL_RATE sur les 5 tables + FK_CONTAINER + FK_EQUIPMENT
-- ---------------------------------------------------------------------------------------------

-- ROW_COUNT customers : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_customers', 'RAW', 'ROW_COUNT customers : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_customers
) AS obs);

-- ROW_COUNT vessel_calls : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_vessel_calls', 'RAW', 'ROW_COUNT vessel_calls : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_vessel_calls
) AS obs);

-- ROW_COUNT container_events : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_container_events', 'RAW', 'ROW_COUNT container_events : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_container_events
) AS obs);

-- ROW_COUNT yard_moves : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_yard_moves', 'RAW', 'ROW_COUNT yard_moves : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_yard_moves
) AS obs);

-- ROW_COUNT equipment : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_equipment', 'RAW', 'ROW_COUNT equipment : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_equipment
) AS obs);

-- DUPLICATE_CHECK customers : la cle metier customer_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_customers', 'RAW', 'DUPLICATE_CHECK customers : doublons sur customer_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(customer_id)) FROM raw_customers
) AS obs);

-- DUPLICATE_CHECK vessel_calls : la cle metier vessel_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_vessel_calls', 'RAW', 'DUPLICATE_CHECK vessel_calls : doublons sur vessel_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(vessel_id)) FROM raw_vessel_calls
) AS obs);

-- DUPLICATE_CHECK container_events : la cle metier event_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_container_events', 'RAW', 'DUPLICATE_CHECK container_events : doublons sur event_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(event_id)) FROM raw_container_events
) AS obs);

-- DUPLICATE_CHECK yard_moves : la cle metier move_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_yard_moves', 'RAW', 'DUPLICATE_CHECK yard_moves : doublons sur move_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(move_id)) FROM raw_yard_moves
) AS obs);

-- DUPLICATE_CHECK equipment : la cle metier equipment_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_equipment', 'RAW', 'DUPLICATE_CHECK equipment : doublons sur equipment_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(equipment_id)) FROM raw_equipment
) AS obs);

-- NULL_RATE customers : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_customers', 'RAW', 'NULL_RATE customers : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_name IS NULL OR TRIM(customer_name) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN group_code IS NULL OR TRIM(group_code) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_type IS NULL OR TRIM(customer_type) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 4), 2) FROM raw_customers
) AS obs);

-- NULL_RATE vessel_calls : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_vessel_calls', 'RAW', 'NULL_RATE vessel_calls : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN vessel_id IS NULL OR TRIM(vessel_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_name IS NULL OR TRIM(vessel_name) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_type IS NULL OR TRIM(vessel_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN service_code IS NULL OR TRIM(service_code) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 4), 2) FROM raw_vessel_calls
) AS obs);

-- NULL_RATE container_events : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_container_events', 'RAW', 'NULL_RATE container_events : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN event_id IS NULL OR TRIM(event_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN container_id IS NULL OR TRIM(container_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_id IS NULL OR TRIM(vessel_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN event_type IS NULL OR TRIM(event_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN event_ts IS NULL OR TRIM(event_ts) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN yard_area IS NULL OR TRIM(yard_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN freight_status IS NULL OR TRIM(freight_status) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN gross_weight_kg IS NULL OR TRIM(gross_weight_kg) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 9), 2) FROM raw_container_events
) AS obs);

-- NULL_RATE yard_moves : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_yard_moves', 'RAW', 'NULL_RATE yard_moves : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN move_id IS NULL OR TRIM(move_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN container_id IS NULL OR TRIM(container_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN move_ts IS NULL OR TRIM(move_ts) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN from_area IS NULL OR TRIM(from_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN to_area IS NULL OR TRIM(to_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN equipment_id IS NULL OR TRIM(equipment_id) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 6), 2) FROM raw_yard_moves
) AS obs);

-- NULL_RATE equipment : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_equipment', 'RAW', 'NULL_RATE equipment : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN equipment_id IS NULL OR TRIM(equipment_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN equipment_type IS NULL OR TRIM(equipment_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN home_area IS NULL OR TRIM(home_area) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 3), 2) FROM raw_equipment
) AS obs);

-- FK_CONTAINER (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'FK_CONTAINER', 'RAW', 'FK_CONTAINER : mouvements dont le container_id est absent de container_events', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events)
) AS obs);

-- FK_EQUIPMENT (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'FK_EQUIPMENT', 'RAW', 'FK_EQUIPMENT : mouvements dont l''equipment_id est absent de equipment', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(equipment_id) NOT IN (SELECT TRIM(equipment_id) FROM raw_equipment)
) AS obs);

-- ---------------------------------------------------------------------------------------------
-- C. Synthese
-- ---------------------------------------------------------------------------------------------
SELECT status, COUNT(*) AS nb FROM etl_quality_checks GROUP BY status ORDER BY status;

SELECT * FROM etl_quality_checks;


-- =============================================================================================
-- ETL / 07 : RECONCILIATION DES VOLUMES
-- =============================================================================================
-- RAW = charge dans le CORE + rejete. Ecart attendu : 0 (aucune ligne perdue ni inventee).
-- =============================================================================================

SELECT 'container_events' AS source,
       (SELECT COUNT(*) FROM raw_container_events) AS raw,
       (SELECT COUNT(*) FROM fact_container_event) AS charge,
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='container_events') AS rejete
UNION ALL
SELECT 'yard_moves',
       (SELECT COUNT(*) FROM raw_yard_moves),
       (SELECT COUNT(*) FROM fact_yard_move),
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='yard_moves');

-- Note : le journal de monitoring (table etl_run_metrics : duree et volume de chaque etape) est
-- alimente par le script Python 04_scripts/etl/etl_pipeline.py ; il n'est pas reproductible en SQL
-- pur. Pour le consulter dans DB Browser : SELECT * FROM etl_run_metrics; (base
-- 03_data/warehouse/smartport_complet.db).

