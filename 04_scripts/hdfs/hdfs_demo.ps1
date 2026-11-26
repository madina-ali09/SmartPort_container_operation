# Commandes HDFS du projet 01 - PowerShell
# A lancer depuis 04_scripts/hdfs/ (dossier qui contient docker-compose.yml et config).
# Conseil : copiez-collez les blocs UN PAR UN pour lire chaque resultat.

# Raccourci : hx <commande> equivaut a (H est deja un alias PowerShell de Get-History)
# hx <commande> equivaut a "docker compose exec namenode <commande>"
function hx { docker compose exec namenode @args }

Write-Host "== 0. Etat du cluster (attendu : Live datanodes (3)) =="
hx hdfs dfsadmin -report | Select-Object -First 25

Write-Host "== 1. Creer le dossier d'archive =="
hx hdfs dfs -mkdir -p /port_exam/project_01/input

Write-Host "== 2. Deposer le fichier brut =="
hx hdfs dfs -put -f /raw/container_events.csv /port_exam/project_01/input/

Write-Host "== 3. Lister =="
hx hdfs dfs -ls -h /port_exam/project_01/input

Write-Host "== 4. Apercu des premieres lignes =="
hx hdfs dfs -head /port_exam/project_01/input/container_events.csv

Write-Host "== 5. Taille =="
hx hdfs dfs -du -h /port_exam/project_01/input

Write-Host "== 6. Blocs, replication et emplacements =="
hx hdfs fsck /port_exam/project_01/input/container_events.csv -files -blocks -locations

Write-Host "== 7. Integrite : les deux empreintes doivent etre identiques =="
hx bash -c "md5sum /raw/container_events.csv; hdfs dfs -cat /port_exam/project_01/input/container_events.csv | md5sum"
