"""
SmartPort Projet 01 - Construction de la plateforme analytique (page HTML autonome).
Lit le Data Warehouse (03_data/warehouse/smartport_complet.db, produit par etl_pipeline.py), exporte les faits et dimensions
en JSON compact, et les injecte dans plateforme_template.html -> smartport_plateforme.html
Usage : python build_plateforme.py
"""
import json, os, sqlite3
HERE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(HERE, "..", "..", "03_data", "warehouse", "smartport_complet.db")
con = sqlite3.connect(DB)
q = lambda s: con.execute(s).fetchall()

dates = [r[0] for r in q("SELECT full_date FROM dim_date ORDER BY date_key")]
didx = {r[0]: i for i, r in enumerate(q("SELECT date_key FROM dim_date ORDER BY date_key"))}
cust = q("SELECT customer_id, customer_name, customer_type, group_code FROM dim_customer ORDER BY customer_key")
ves = q("SELECT vessel_id, vessel_name, vessel_type, service_code FROM dim_vessel ORDER BY vessel_key")
areas = q("SELECT area_code, parent_area FROM dim_yard_area ORDER BY area_key")
types = q("SELECT event_type, event_family FROM dim_event_type ORDER BY event_type_key")
eq = q("SELECT equipment_id, equipment_type, home_area FROM dim_equipment ORDER BY equipment_key")

ev = q("SELECT date_key, hour_key, customer_key, vessel_key, area_key, event_type_key, freight_key, gross_weight_kg, container_id FROM fact_container_event ORDER BY event_id")
mv = q("SELECT date_key, hour_key, from_area_key, to_area_key, equipment_key FROM fact_yard_move ORDER BY move_id")
cont = {}
def cid(c): return cont.setdefault(c, len(cont))
data = {
    "dates": dates, "cust": cust, "ves": ves, "areas": areas, "types": types, "eq": eq,
    "ev": {"d": [didx[r[0]] for r in ev], "h": [r[1] for r in ev], "c": [r[2]-1 for r in ev], "v": [r[3]-1 for r in ev],
           "a": [r[4]-1 for r in ev], "t": [r[5]-1 for r in ev], "f": [r[6]-1 for r in ev], "w": [round(r[7], 1) for r in ev],
           "k": [cid(r[8]) for r in ev]},
    "mv": {"d": [didx[r[0]] for r in mv], "h": [r[1] for r in mv], "f": [r[2]-1 for r in mv], "t": [r[3]-1 for r in mv], "e": [r[4]-1 for r in mv]},
}
assert len(dates) == (__import__("datetime").date.fromisoformat(dates[-1]) - __import__("datetime").date.fromisoformat(dates[0])).days + 1

# qualite
data["checks"] = [list(r) for r in q("SELECT check_id, layer, description, observed, expected, status FROM etl_quality_checks")]
data["recon"] = [list(r) for r in q("""SELECT 'container_events', (SELECT COUNT(*) FROM raw_container_events), (SELECT COUNT(*) FROM fact_container_event),
    (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='container_events')
    UNION ALL SELECT 'yard_moves', (SELECT COUNT(*) FROM raw_yard_moves), (SELECT COUNT(*) FROM fact_yard_move),
    (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='yard_moves')""")]
def tables(prefix):
    names = [r[0] for r in q(f"SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '{prefix}%' ORDER BY name")]
    return [[n, q(f"SELECT COUNT(*) FROM {n}")[0][0]] for n in names]
data["lineage"] = {
    "sources": [[n, q(f"SELECT COUNT(*) FROM raw_{n}")[0][0]] for n in ["customers", "vessel_calls", "container_events", "yard_moves", "equipment"]],
    "raw": tables("raw_"), "staging": tables("stg_") + [["etl_rejects", q("SELECT COUNT(*) FROM etl_rejects")[0][0]]],
    "core": tables("dim_") + tables("fact_"), "mart": tables("mart_"),
}
last = q("SELECT MAX(run_id) FROM etl_run_metrics")[0][0]
data["run_id"] = last
data["metrics"] = [list(r) for r in q(f"SELECT layer, COUNT(*), SUM(rows_affected), ROUND(SUM(duration_s)*1000,1) FROM etl_run_metrics WHERE run_id='{last}' GROUP BY layer ORDER BY MIN(logged_at)")]
data["nruns"] = q("SELECT COUNT(DISTINCT run_id) FROM etl_run_metrics")[0][0]
data["same_area_moves"] = q("SELECT SUM(is_same_area) FROM fact_yard_move")[0][0]
# preuve des regles de rejet (resultat de 04_scripts/etl/test_rejets.py : 13 erreurs injectees)
data["reject_proof"] = [["EV02", "event_id en double", 1], ["EV03", "date d'événement illisible", 1], ["EV04", "type d'événement hors domaine", 1],
    ["EV05", "statut hors FCL/MTY", 1], ["EV06", "poids hors 0..40 000 kg", 2], ["EV07", "client inconnu", 1], ["EV08", "navire inconnu", 1],
    ["EV09", "zone manquante", 1], ["MV02", "move_id en double", 1], ["MV03", "date de mouvement illisible", 1],
    ["MV04", "équipement inconnu", 1], ["MV06", "conteneur inconnu", 1]]

tpl = open(os.path.join(HERE, "plateforme_template.html"), encoding="utf-8").read()
out = tpl.replace("/*__DATA__*/null", json.dumps(data, ensure_ascii=False, separators=(",", ":")))
open(os.path.join(HERE, "smartport_plateforme.html"), "w", encoding="utf-8").write(out)
print("OK", round(len(out) / 1024), "Ko")
