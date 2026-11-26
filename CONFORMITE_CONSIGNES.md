# Conformité aux consignes du projet 01

## Éléments demandés
| Exigence | Où | État |
|---|---|---|
| Rapport de 20 à 30 pages | `07_deliverables/rapport/rapport_smartport.pdf` | fait (26 pages) |
| 10 à 12 diapositives, 25 minutes | `07_deliverables/presentation/` | fait (12 diapositives et notes orales) |
| Problématique et 5V | rapport, diapos 2 et 3 | fait |
| SQL : comptages, jointures, KPI, CTE, grain | `04_scripts/sql/exploration/`, rapport (requêtes clés), diapo 5 | fait (18 requêtes) |
| Data Warehouse | rapport, diapo 6, `03_data/warehouse/` | fait |
| ETL/ELT, rejets et qualité | notebook 01, `04_scripts/etl/`, diapo 7 | fait (32 contrôles) |
| Code, base et reconstruction | `01_ETL_Pipeline/`, `04_scripts/`, `README.md` | fait |
| Au moins 5 KPI | `03_data/dictionary/kpi_catalog.csv` | fait (6) |
| Au moins 3 graphiques interprétés | notebook 02, rapport | fait (7) |
| HDFS : commandes et preuves | `04_scripts/hdfs/`, `06_results/hdfs_captures/` | **partiel** : pas de capture de `mkdir`, `put`, `head` |
| Archivage HDFS avant ingestion | `04_scripts/hdfs/ingestion_depuis_hdfs.py` | **à valider** : testé en simulation, pas sur le cluster |
| Gouvernance, sécurité, lineage | `05_governance/`, diapo 10 | fait (règles proposées, non appliquées) |
| Dictionnaire de données enrichi | `03_data/dictionary/` | fait |
| Architecture finale | rapport, `06_results/figures/architecture_finale.png` | fait |
| Démonstration | application Streamlit, diapo 11 | prête, à répéter |

## Reste à faire avant le rendu
1. Exécuter la chaîne HDFS sur le vrai cluster (ci-dessous) et capturer la sortie.
2. Mettre à jour les phrases « à valider sur le cluster » une fois la preuve obtenue.
3. Vérifier avec l'enseignant la date de soutenance : le sujet indiquait le 14 novembre 2026.
4. Répéter la soutenance et la démonstration.

## Valider HDFS (Windows, PowerShell, Docker Desktop démarré)
Depuis la racine du projet, après `pip install -r requirements.txt` :
```powershell
cd 04_scripts\hdfs
docker compose up -d namenode
Start-Sleep -Seconds 45
docker compose up -d --scale datanode=3
cd ..\..
python 04_scripts\hdfs\ingestion_depuis_hdfs.py
```
Succès attendu : deux empreintes MD5 identiques, puis « Terminé » et le fichier `06_results/ingestion_hdfs_manifest.json`.
Si les conteneurs d'un ancien dossier tournent encore, les arrêter d'abord (`docker compose down` dans cet ancien dossier) : le port 9870 doit être libre.
