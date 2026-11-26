# 07 · Hypothèses, limites et décisions à valider

| Sujet | Hypothèse ou décision | Effet |
|---|---|---|
| Y08B | sous-zone de Y08 | change le classement des zones (Y08 : 946 MOVE) ; les deux lectures sont conservées |
| Familles d'événements | regroupement par nature d'opération | aucun sur les six KPI |
| Poids | rejet hors de ]0 ; 40 000] kg | maximum observé : 35 000 kg |
| Zone identique | 712 mouvements conservés | signalés par Q13 |
| Gouvernance | rôles, classes, accès, fraîcheur | propositions non appliquées techniquement |

## Limites
- Données synthétiques de petit volume : maquette.
- Reconstruction complète à chaque exécution.
- HDFS sur une seule machine ; ingestion depuis l'archive scriptée mais à valider sur le cluster ; la démonstration utilise `-put -f`, le script d'ingestion un dossier daté sans écrasement.
- Seul `container_events.csv` est archivé dans HDFS.
- Lineage : voir les limites dans [04 · Lineage](04_lineage.md).
