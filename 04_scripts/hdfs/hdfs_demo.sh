#!/usr/bin/env bash
# Commandes HDFS du projet 01 (a lancer depuis 04_scripts/hdfs/, cluster demarre).
# Sous Windows : copiez-collez les commandes une par une dans PowerShell.
H="docker compose exec namenode"

echo "== 0. Etat du cluster (attendu : 3 DataNodes vivants) =="
$H hdfs dfsadmin -report | head -n 20

echo "== 1. Creer le dossier d'archive =="
$H hdfs dfs -mkdir -p /port_exam/project_01/input

echo "== 2. Deposer le fichier brut =="
$H hdfs dfs -put -f /raw/container_events.csv /port_exam/project_01/input/

echo "== 3. Lister =="
$H hdfs dfs -ls -h /port_exam/project_01/input

echo "== 4. Apercu des premieres lignes =="
$H hdfs dfs -head /port_exam/project_01/input/container_events.csv

echo "== 5. Taille =="
$H hdfs dfs -du -h /port_exam/project_01/input

echo "== 6. Blocs, replication et emplacements =="
$H hdfs fsck /port_exam/project_01/input/container_events.csv -files -blocks -locations

echo "== 7. Integrite : empreinte du fichier source vs fichier relu depuis HDFS (doivent etre identiques) =="
$H bash -c "md5sum /raw/container_events.csv; hdfs dfs -cat /port_exam/project_01/input/container_events.csv | md5sum"
