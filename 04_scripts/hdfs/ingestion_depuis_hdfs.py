"""
SmartPort - Ingestion du Data Warehouse DEPUIS l'archive HDFS.

Ordre imposé par le sujet : container_events.csv est archivé dans HDFS AVANT son chargement.
  1. mkdir  : dossier daté de l'archive
  2. put    : dépôt du fichier brut (sans -f : une archive existante n'est jamais écrasée)
  3. head   : aperçu du fichier archivé
  4. cat    : relecture du fichier depuis HDFS vers la zone d'atterrissage
  5. md5    : la copie relue doit être identique à la source, sinon arrêt
  6. ETL    : le pipeline charge container_events depuis la copie relue

Prérequis : cluster démarré (voir README_HDFS_Docker.md), Docker et Python avec pandas.
Usage (depuis n'importe quel dossier) :
    python 04_scripts/hdfs/ingestion_depuis_hdfs.py [--date AAAA-MM-JJ]
Les 4 référentiels et yard_moves ne sont pas concernés par la consigne : ils viennent de 03_data/raw.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RAW_DIR = ROOT / "03_data" / "raw"
EVENTS = "container_events.csv"
OTHERS = ["customers.csv", "vessel_calls.csv", "yard_moves.csv", "equipment.csv"]
HDFS_BASE = "/port_exam/project_01/input"


def hdfs(*args, check=True):
    """Exécute une commande dans le conteneur NameNode et renvoie le résultat (octets bruts)."""
    cmd = ["docker", "compose", "exec", "-T", "namenode", "hdfs", *args]
    print("$", " ".join(["hdfs", *args]))
    res = subprocess.run(cmd, cwd=HERE, capture_output=True)
    if check and res.returncode != 0:
        sys.exit("Échec de la commande HDFS :\n" + res.stderr.decode(errors="replace"))
    return res


def md5(data: bytes) -> str:
    return hashlib.md5(data).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", default=date.today().isoformat(), help="date de livraison (dossier d'archive)")
    ap.add_argument("--db", default=str(ROOT / "03_data" / "warehouse" / "smartport_complet.db"))
    a = ap.parse_args()
    try:
        day = date.fromisoformat(a.date).isoformat()
    except ValueError:
        sys.exit("Date invalide : utilisez AAAA-MM-JJ.")

    source_md5 = md5((RAW_DIR / EVENTS).read_bytes())
    folder = f"{HDFS_BASE}/ingest_date={day}"
    target = f"{folder}/{EVENTS}"

    hdfs("dfs", "-mkdir", "-p", folder)
    if hdfs("dfs", "-test", "-e", target, check=False).returncode == 0:
        print("Archive déjà présente : elle n'est pas écrasée, son contenu sera vérifié.")
    else:
        hdfs("dfs", "-put", f"/raw/{EVENTS}", target)
    print(hdfs("dfs", "-ls", "-h", folder).stdout.decode(errors="replace"))
    print(hdfs("dfs", "-head", target).stdout.decode(errors="replace"))

    data = hdfs("dfs", "-cat", target).stdout
    read_md5 = md5(data)
    print(f"MD5 source : {source_md5}\nMD5 HDFS   : {read_md5}")
    if read_md5 != source_md5:
        sys.exit("ARRÊT : la copie relue depuis HDFS diffère de la source. Le Data Warehouse n'est pas modifié.")

    landing = ROOT / "03_data" / "landing_hdfs" / f"ingest_date={day}"
    landing.mkdir(parents=True, exist_ok=True)
    (landing / EVENTS).write_bytes(data)
    for name in OTHERS:
        shutil.copy(RAW_DIR / name, landing / name)

    print("Chargement du Data Warehouse depuis la copie relue de HDFS...")
    etl = ROOT / "04_scripts" / "etl" / "etl_pipeline.py"
    subprocess.run([sys.executable, str(etl), str(landing), a.db], check=True)

    manifest = {
        "executed_at": datetime.now().isoformat(timespec="seconds"),
        "hdfs_path": target,
        "md5_source": source_md5,
        "md5_read_from_hdfs": read_md5,
        "landing_file": (landing / EVENTS).relative_to(ROOT).as_posix(),
        "status": "OK",
    }
    out = ROOT / "06_results" / "ingestion_hdfs_manifest.json"
    out.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"Terminé. Preuve enregistrée dans {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
