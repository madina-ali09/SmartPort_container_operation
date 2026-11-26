-- =============================================================================================
-- ETAPE 2 / A.3 : KPI COMPLETS (navires, services, clients)
-- =============================================================================================
-- KPI 3 (volumes par navire / service) et KPI 4 (activite par client) du catalogue des KPI
-- attendus.
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 13 : KPI 3a : volumes par navire (top 10) avec son service
-- ---------------------------------------------------------------------------------------------
SELECT v.vessel_id, v.vessel_name, v.vessel_type, v.service_code,
       COUNT(*) AS nb_evenements,
       COUNT(DISTINCT e.container_id) AS nb_conteneurs,
       ROUND(SUM(e.gross_weight_kg)/1000.0,1) AS tonnes
FROM container_events e
JOIN vessel_calls v ON v.vessel_id = e.vessel_id
GROUP BY v.vessel_id, v.vessel_name, v.vessel_type, v.service_code
ORDER BY nb_evenements DESC
LIMIT 10;

-- RESULTAT / LECTURE : Les trois navires les plus actifs (V020, V039, V068) totalisent 100
-- événements chacun.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 14 : KPI 3b : volumes par service (avec part du total)
-- ---------------------------------------------------------------------------------------------
SELECT v.service_code,
       COUNT(DISTINCT v.vessel_id) AS nb_navires,
       COUNT(*) AS nb_evenements,
       COUNT(DISTINCT e.container_id) AS nb_conteneurs,
       ROUND(SUM(e.gross_weight_kg)/1000.0,0) AS tonnes,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM container_events),1) AS pct_evenements
FROM container_events e
JOIN vessel_calls v ON v.vessel_id = e.vessel_id
GROUP BY v.service_code
ORDER BY nb_evenements DESC;

-- RESULTAT / LECTURE : GULF concentre 27,4 % des événements avec 32 navires. Par navire, les
-- services sont comparables (voir l'EDA, partie B).

-- ---------------------------------------------------------------------------------------------
-- REQUETE 15 : KPI 3c : volumes par type de navire (Container vs Feeder)
-- ---------------------------------------------------------------------------------------------
SELECT v.vessel_type, COUNT(DISTINCT v.vessel_id) AS nb_navires, COUNT(*) AS nb_evenements,
       ROUND(1.0*COUNT(*)/COUNT(DISTINCT v.vessel_id),1) AS evenements_par_navire
FROM container_events e
JOIN vessel_calls v ON v.vessel_id = e.vessel_id
GROUP BY v.vessel_type;

-- RESULTAT / LECTURE : Les navires Container traitent en moyenne 75,8 événements par navire, les
-- Feeder 73,0 : l'écart est faible.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 16 : KPI 4a : activite par client (top 10)
-- ---------------------------------------------------------------------------------------------
SELECT c.customer_id, c.customer_name, c.customer_type, c.group_code,
       COUNT(*) AS nb_evenements,
       COUNT(DISTINCT e.container_id) AS nb_conteneurs,
       ROUND(SUM(e.gross_weight_kg)/1000.0,1) AS tonnes,
       ROUND(100.0*SUM(e.freight_status='FCL')/COUNT(*),1) AS pct_fcl
FROM container_events e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY c.customer_id, c.customer_name, c.customer_type, c.group_code
ORDER BY nb_evenements DESC
LIMIT 10;

-- RESULTAT / LECTURE : Customer_067 (Forwarder) est le client le plus actif avec 136 événements,
-- devant Customer_029 et Customer_077 (134 chacun).

-- ---------------------------------------------------------------------------------------------
-- REQUETE 17 : KPI 4b : activite par groupe client
-- ---------------------------------------------------------------------------------------------
SELECT c.group_code, COUNT(DISTINCT c.customer_id) AS nb_clients, COUNT(*) AS nb_evenements,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM container_events),1) AS pct_evenements
FROM container_events e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY c.group_code
ORDER BY nb_evenements DESC;

-- RESULTAT / LECTURE : Les parts des groupes (ETH 32,9 %, DJ 28,6 %, FZ 22,3 %, ETH_MTL 16,2 %)
-- sont proportionnelles à leur nombre de clients (26, 23, 18 et 13 sur 80).

-- ---------------------------------------------------------------------------------------------
-- REQUETE 18 : KPI 4c : concentration (part cumulee des 10 premiers clients, via CTE)
-- ---------------------------------------------------------------------------------------------
WITH par_client AS (
    SELECT customer_id, COUNT(*) AS n FROM container_events GROUP BY customer_id
), top10 AS (
    SELECT n FROM par_client ORDER BY n DESC LIMIT 10
)
SELECT SUM(n) AS evenements_top10,
       ROUND(100.0*SUM(n)/(SELECT COUNT(*) FROM container_events),1) AS pct_top10,
       (SELECT MIN(n) FROM par_client) AS min_client,
       (SELECT MAX(n) FROM par_client) AS max_client
FROM top10;

-- RESULTAT / LECTURE : Les 10 premiers clients représentent 14,3 % de l'activité (1 284 événements
-- sur 9 000), et les clients vont de 91 à 136 événements : l'activité est très dispersée.
