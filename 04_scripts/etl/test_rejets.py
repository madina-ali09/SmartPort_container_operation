"""
SmartPort Projet 01 - Preuve que les regles de rejet fonctionnent (section 8 du notebook).
Injecte 13 lignes defectueuses dans une COPIE des CSV (dossier temporaire), rejoue le pipeline et affiche les rejets.
Usage : python test_rejets.py      (a lancer depuis 04_scripts/etl)
"""
import os, sys, shutil, sqlite3, io, contextlib, tempfile
import pandas as pd
HERE = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(HERE, "..", "..", "03_data", "raw")
WORK = tempfile.mkdtemp(prefix="smartport_test_")
sys.path.insert(0, HERE)
# etl_pipeline s'execute a l'import (pipeline normal, base temporaire) : on masque sa sortie
with contextlib.redirect_stdout(io.StringIO()):
    sys.argv = ["etl_pipeline.py", DATA_DIR, os.path.join(WORK, "normal.db")]
    import etl_pipeline as E
rejouer_pipeline, SOURCES = E.rejouer_pipeline, E.SOURCES
os.chdir(WORK)
def display(x): print(x.to_string(index=False) if hasattr(x, "to_string") else x)

os.makedirs("bad", exist_ok=True)
for s in SOURCES:
    shutil.copy(f"{DATA_DIR}/{s}.csv", f"bad/{s}.csv")

e = pd.read_csv("bad/container_events.csv")
m = pd.read_csv("bad/yard_moves.csv")
b = e.iloc[0].to_dict()
def ev(**kw): d = dict(b); d.update(kw); return d

mauvais_events = [
    ev(event_id=e.event_id.iloc[1]),                 # EV02 : identifiant en double
    ev(event_id=99001, event_ts="pas-une-date"),     # EV03 : date illisible
    ev(event_id=99002, event_type="TELEPORT"),       # EV04 : type inconnu
    ev(event_id=99003, freight_status="XXX"),        # EV05 : statut invalide
    ev(event_id=99004, gross_weight_kg=-50),         # EV06 : poids négatif
    ev(event_id=99005, gross_weight_kg=99999),       # EV06 : poids trop grand
    ev(event_id=99006, customer_id="C_INCONNU"),     # EV07 : client inexistant
    ev(event_id=99007, vessel_id="V_INCONNU"),       # EV08 : navire inexistant
    ev(event_id=99008, yard_area=""),                # EV09 : zone vide
]
mb = m.iloc[0].to_dict()
mauvais_moves = [
    dict(mb, move_id=m.move_id.iloc[1]),                    # MV02 : identifiant en double
    dict(mb, move_id=88001, move_ts="31/31/2026"),          # MV03 : date illisible
    dict(mb, move_id=88002, equipment_id="EQ_INCONNU"),     # MV04 : équipement inexistant
    dict(mb, move_id=88003, container_id="CONT_INCONNU"),   # MV06 : conteneur inexistant
]
pd.concat([e, pd.DataFrame(mauvais_events)]).to_csv("bad/container_events.csv", index=False)
pd.concat([m, pd.DataFrame(mauvais_moves)]).to_csv("bad/yard_moves.csv", index=False)

if os.path.exists("smartport_test.db"): os.remove("smartport_test.db")
statuts = rejouer_pipeline("bad", "smartport_test.db")
print("Contrôles en échec (FAIL) sur les données défectueuses :", statuts.count("FAIL"), "(attendu : ils détectent les erreurs injectées)")

tc = sqlite3.connect("smartport_test.db")
print("Lignes rejetées, par règle :")
display(pd.read_sql("SELECT rule_id, rule_description, COUNT(*) AS nb FROM etl_rejects GROUP BY 1, 2 ORDER BY 1", tc))
print("Faits chargés malgré les 13 erreurs injectées :")
display(pd.read_sql("""SELECT (SELECT COUNT(*) FROM fact_container_event) AS evenements,
                       (SELECT COUNT(*) FROM fact_yard_move) AS mouvements""", tc))
print("Contrôles qui détectent les erreurs injectées (donnée source) :")
display(pd.read_sql("SELECT check_id, layer, status, observed FROM etl_quality_checks WHERE status <> 'PASS' ORDER BY layer, check_id", tc))
print("Réconciliation (écart attendu 0) :")
display(pd.read_sql("SELECT check_id, status, observed FROM etl_quality_checks WHERE check_id IN ('Q09','Q10')", tc))
