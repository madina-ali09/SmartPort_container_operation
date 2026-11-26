# HDFS sous Docker : archive brute et ingestion

Cluster : 1 NameNode et 3 DataNodes, réplication 3 (`docker-compose.yml`, `config`).
Toutes les commandes se lancent depuis `04_scripts/hdfs/`.

## 1. Démarrer
```bash
docker compose up -d namenode          # attendre environ 45 secondes
docker compose up -d --scale datanode=3
docker compose ps                      # 4 conteneurs « Up »
```
Interface du NameNode : http://localhost:9870. Le dossier `03_data/raw/` est monté en lecture seule sous `/raw`.

## 2. Démonstration des commandes
`hdfs_demo.ps1` (PowerShell) ou `hdfs_demo.sh` (bash) : `dfsadmin -report`, `mkdir`, `put`, `ls`, `head`, `du`, `fsck`, `md5sum`.

Preuves déjà enregistrées dans `06_results/hdfs_captures/` :

| Capture | Contenu |
|---|---|
| `hdfs_capture_01.png` | 3 DataNodes actifs |
| `hdfs_capture_ls.png` | `ls` : fichier de 611 Ko, réplication 3 |
| `hdfs_capture_02.png` | `du` : 611 Ko, 1,8 Mo occupés |
| `hdfs_capture_03.png` | `fsck` : 1 bloc, 3 copies, HEALTHY |
| `hdfs_capture_04.png` | empreintes MD5 identiques |

Il n'y a pas encore de capture pour `mkdir`, `put` et `head`.

## 3. Ingestion du Data Warehouse depuis HDFS
Le sujet demande d'archiver `container_events.csv` **avant** son chargement. Depuis la racine du projet :
```bash
python 04_scripts/hdfs/ingestion_depuis_hdfs.py
```
Le script enchaîne `mkdir`, `put`, `ls`, `head`, relit le fichier depuis HDFS, compare les empreintes MD5, puis lance le pipeline sur la copie relue.
L'archive est datée (`input/ingest_date=AAAA-MM-JJ/`) et n'est jamais écrasée. Si les empreintes diffèrent, le script s'arrête avant de toucher à l'entrepôt.
En cas de succès, il écrit `06_results/ingestion_hdfs_manifest.json`.

**État de la validation :** la logique du script a été testée avec des commandes HDFS **simulées** (chargement, relance, archive altérée).
Il reste à l'exécuter sur le vrai cluster et à capturer la sortie.

## 4. Difficultés rencontrées
1. **NameNode arrêté au démarrage** : les CSV étaient montés dans `/data`, utilisé par l'image. Montage déplacé dans `/raw`.
2. **`Incompatible clusterIDs`** après recréation du seul NameNode : `docker compose down`, puis redémarrage complet.

## 5. Limites
Une seule machine ; fichier très petit pour HDFS ; seul `container_events.csv` est archivé. Les notebooks lisent les CSV locaux : la chaîne par HDFS passe par le script ci-dessus.
La démonstration utilise `put -f` (écrase) dans `input/` ; le script d'ingestion utilise un dossier daté sans écrasement.
