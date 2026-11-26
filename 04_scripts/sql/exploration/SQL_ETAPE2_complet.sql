-- =============================================================================================
-- SMARTPORT PROJET 01 - ETAPE 2 : EXPLORATION SQL DES SOURCES (fichier unique, 18 requetes)
-- =============================================================================================
-- COMMENT UTILISER CE FICHIER DANS DB BROWSER FOR SQLITE
--   1. Ouvrir smartport_sources.db (dossier db/) : les 5 tables sont deja remplies.
--      (Sinon : creer une base, executer la PARTIE 0, puis importer les 5 CSV.)
--   2. Onglet 'Executer le SQL' > ouvrir ce fichier.
--   3. SELECTIONNER UNE SEULE requete (du WITH/SELECT jusqu'au ';') puis F5 ou Ctrl+Entree.
--      Sans selection, tout le fichier s'execute et seul le dernier resultat s'affiche.
--   Chaque requete a : un numero, une QUESTION en francais simple, la requete, puis la LECTURE du resultat.
--
-- SOMMAIRE
--   Requete  1 : Comptage de chaque table source
--   Requete  2 : JOIN 1 : evenements x clients (activite par type de client)
--   Requete  3 : JOIN 2 : evenements x navires (volumes par service)
--   Requete  4 : JOIN 3 : mouvements de cour x equipements (charge par type d'equipement)
--   Requete  5 : KPI 1 : evenements par jour (10 premiers jours les plus charges)
--   Requete  6 : KPI 2 : MOVE par zone Yard
--   Requete  7 : KPI 5 + 6 : poids moyen par type d'evenement et part FCL
--   Requete  8 : CTE : top 5 clients par activite avec leur part du total
--   Requete  9 : Sous-requete : jours dont l'activite depasse moyenne + 2 ecarts-types (pics)
--   Requete 10 : Unicite des cles primaires candidates (attendu : 0 doublon partout)
--   Requete 11 : Integrite referentielle (attendu : 0 orphelin partout)
--   Requete 12 : Anomalies metier a surveiller
--   Requete 13 : KPI 3a : volumes par navire (top 10) avec son service
--   Requete 14 : KPI 3b : volumes par service (avec part du total)
--   Requete 15 : KPI 3c : volumes par type de navire (Container vs Feeder)
--   Requete 16 : KPI 4a : activite par client (top 10)
--   Requete 17 : KPI 4b : activite par groupe client
--   Requete 18 : KPI 4c : concentration (part cumulee des 10 premiers clients, via CTE)
-- =============================================================================================


/* ##########################################################################################
   PARTIE 0 : CREATION DES TABLES ET IMPORT (inutile si vous ouvrez smartport_sources.db)
   ########################################################################################## */
-- =============================================================================================
-- PARTIE 0 - ETAPE 2 / A.1 : CREATION DES TABLES SOURCES (schema fourni par le prof)
-- =============================================================================================
-- Projet 01 SmartPort. Ouvrir DB Browser for SQLite : Fichier > Nouvelle base de donnees (ex.
-- smartport.db), puis onglet 'Executer le SQL' et lancer ce fichier en entier (F5 / Ctrl+Entree).
-- Si vous utilisez la base deja prete db/smartport_sources.db, cette etape est deja faite.
-- =============================================================================================

-- Les 5 tables sources : customers (clients), vessel_calls (navires/escales), container_events
-- (evenements conteneurs), yard_moves (mouvements de cour), equipment (engins).

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS customers;

CREATE TABLE customers (
    customer_id TEXT,
    customer_name TEXT,
    group_code TEXT,
    customer_type TEXT
);

DROP TABLE IF EXISTS vessel_calls;

CREATE TABLE vessel_calls (
    vessel_id TEXT,
    vessel_name TEXT,
    vessel_type TEXT,
    service_code TEXT
);

DROP TABLE IF EXISTS container_events;

CREATE TABLE container_events (
    event_id INTEGER,
    container_id TEXT,
    customer_id TEXT,
    vessel_id TEXT,
    event_type TEXT,
    event_ts TEXT,
    yard_area TEXT,
    freight_status TEXT,
    gross_weight_kg REAL
);

DROP TABLE IF EXISTS yard_moves;

CREATE TABLE yard_moves (
    move_id INTEGER,
    container_id TEXT,
    move_ts TEXT,
    from_area TEXT,
    to_area TEXT,
    equipment_id TEXT
);

DROP TABLE IF EXISTS equipment;

CREATE TABLE equipment (
    equipment_id TEXT,
    equipment_type TEXT,
    home_area TEXT
);

-- =============================================================================================
-- ETAPE 2 / A.2 : IMPORT DES CSV DANS LES TABLES (a faire dans l'interface)
-- =============================================================================================
-- Dans DB Browser : Fichier > Importer > Table depuis un fichier CSV.
-- 1) Choisir un CSV de 03_data/raw (ex. customers.csv).
-- 2) Nom de la table : EXACTEMENT le nom de la table (customers, vessel_calls, container_events,
-- yard_moves, equipment).
-- 3) Cocher 'Les noms des colonnes sont dans la premiere ligne', separateur = virgule.
-- 4) Si DB Browser dit que la table existe deja, repondre OUI pour ajouter les lignes dans la
-- table existante.
-- 5) Faire les 5 fichiers, puis Ctrl+S (Ecrire les modifications).
-- Alternative : ouvrir directement db/smartport_sources.db qui contient deja les donnees.
-- =============================================================================================

-- =============================================================================================
-- VERIFICATION DE L'IMPORT : le poids doit etre de type real (nombre), sinon les moyennes sont fausses
-- =============================================================================================

SELECT typeof(gross_weight_kg) AS type_poids, COUNT(*) AS nb
FROM container_events
GROUP BY 1;
-- Attendu : real | 9000


/* ##########################################################################################
   PARTIE : COMPTAGE DES TABLES SOURCES
   Consigne du prof (TODO 1) : compter chaque table source. Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 1 : Comptage de chaque table source
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Combien de lignes y a-t-il dans chacune des 5 tables ?
SELECT 'customers' AS table_name, COUNT(*) AS nb_lignes FROM customers
UNION ALL SELECT 'vessel_calls', COUNT(*) FROM vessel_calls
UNION ALL SELECT 'container_events', COUNT(*) FROM container_events
UNION ALL SELECT 'yard_moves', COUNT(*) FROM yard_moves
UNION ALL SELECT 'equipment', COUNT(*) FROM equipment;

-- RESULTAT / LECTURE : Les 5 tables contiennent bien 80, 120, 9 000, 4 500 et 40 lignes : l'import
-- est complet et conforme à l'énoncé.


/* ##########################################################################################
   PARTIE : JOINTURES
   Consigne du prof (TODO 2) : au moins 3 requetes avec JOIN. Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 2 : JOIN 1 : evenements x clients (activite par type de client)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quel type de client (importateur, exportateur...) génère le plus d'événements, et pour quel poids moyen ?
SELECT c.customer_type, COUNT(*) AS nb_evenements,
       ROUND(AVG(e.gross_weight_kg),0) AS poids_moyen_kg
FROM container_events e
JOIN customers c ON c.customer_id = e.customer_id
GROUP BY c.customer_type
ORDER BY nb_evenements DESC;

-- RESULTAT / LECTURE : Les importateurs totalisent le plus d'événements (3 290), parce qu'ils sont
-- les plus nombreux. Le poids moyen est quasi identique pour les 4 types de clients (18,5 à 18,7
-- tonnes).

-- ---------------------------------------------------------------------------------------------
-- REQUETE 3 : JOIN 2 : evenements x navires (volumes par service)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quel service maritime (GULF, REDSEA...) traite le plus d'événements et de tonnes ?
SELECT v.service_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT e.vessel_id) AS nb_navires,
       ROUND(SUM(e.gross_weight_kg)/1000.0,0) AS tonnes
FROM container_events e
JOIN vessel_calls v ON v.vessel_id = e.vessel_id
GROUP BY v.service_code
ORDER BY nb_evenements DESC;

-- RESULTAT / LECTURE : GULF domine (2 469 événements, 46 010 tonnes) devant REDSEA (1 959) et
-- DJJIB (1 801). ASIA est le plus faible (1 221). Cette requête donne le total par service ; les
-- requêtes 13 à 15 détaillent par navire.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 4 : JOIN 3 : mouvements de cour x equipements (charge par type d'equipement)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quelle charge de travail porte chaque type d'engin (RMG, TT...) ?
SELECT q.equipment_type, COUNT(DISTINCT q.equipment_id) AS nb_equipements,
       COUNT(*) AS nb_mouvements,
       ROUND(1.0*COUNT(*)/COUNT(DISTINCT q.equipment_id),1) AS mouvements_par_equipement
FROM yard_moves m
JOIN equipment q ON q.equipment_id = m.equipment_id
GROUP BY q.equipment_type
ORDER BY mouvements_par_equipement DESC;

-- RESULTAT / LECTURE : La charge par équipement est homogène : de 107,8 mouvements par équipement
-- (RMG) à 123,5 (RS). Les 2 équipements RS sont les plus sollicités, mais l'écart est modeste
-- (environ 14 % de plus que RMG) et ne repose que sur 2 machines : à ne pas surinterpréter.


/* ##########################################################################################
   PARTIE : AGREGATIONS (GROUP BY) = KPI DE BASE
   Consigne du prof (TODO 3) : au moins 2 requetes GROUP BY de type KPI. Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 5 : KPI 1 : evenements par jour (10 premiers jours les plus charges)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quels sont les 10 jours les plus chargés ?
SELECT DATE(event_ts) AS jour, COUNT(*) AS nb_evenements
FROM container_events
GROUP BY DATE(event_ts)
ORDER BY nb_evenements DESC, jour
LIMIT 10;

-- RESULTAT / LECTURE : Le jour le plus chargé est le 20/06/2026 (50 événements), suivi du 30/05
-- (47) et du 11/06 (45).

-- ---------------------------------------------------------------------------------------------
-- REQUETE 6 : KPI 2 : MOVE par zone Yard
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quelle zone de la cour (Y01, Y02...) reçoit le plus de MOVE ?
SELECT yard_area, COUNT(*) AS nb_move
FROM container_events
WHERE event_type = 'MOVE'
GROUP BY yard_area
ORDER BY nb_move DESC;

-- RESULTAT / LECTURE : Y04 est la zone la plus chargée (538 MOVE). Attention : Y08B est comptée
-- ici comme une zone séparée (456). Rattachée à Y08, celle-ci atteindrait 946 : c'est le sujet de
-- la standardisation dans la partie B.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 7 : KPI 5 + 6 : poids moyen par type d'evenement et part FCL
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quel est le poids moyen et la part de conteneurs pleins (FCL) pour chaque type d'événement ?
SELECT event_type, COUNT(*) AS nb,
       ROUND(AVG(gross_weight_kg),0) AS poids_moyen_kg,
       ROUND(100.0*SUM(freight_status='FCL')/COUNT(*),1) AS pct_fcl
FROM container_events
GROUP BY event_type
ORDER BY nb DESC;

-- RESULTAT / LECTURE : Le poids moyen est quasi identique pour tous les types d'événements (18,4 à
-- 18,8 tonnes) et la part de conteneurs pleins reste entre 74,0 % et 77,0 %.


/* ##########################################################################################
   PARTIE : CTE ET SOUS-REQUETES
   Consigne du prof (TODO 4) : au moins une CTE (clause WITH). Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 8 : CTE : top 5 clients par activite avec leur part du total
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quels sont les 5 clients les plus actifs et quelle part du total représentent-ils ?
WITH activite AS (
    SELECT customer_id, COUNT(*) AS nb_evenements,
           SUM(gross_weight_kg) AS poids_total
    FROM container_events
    GROUP BY customer_id
), total AS (SELECT SUM(nb_evenements) AS t FROM activite)
SELECT c.customer_name, c.customer_type, a.nb_evenements,
       ROUND(100.0*a.nb_evenements/t.t,2) AS pct_total
FROM activite a
JOIN customers c ON c.customer_id = a.customer_id
CROSS JOIN total t
ORDER BY a.nb_evenements DESC
LIMIT 5;

-- RESULTAT / LECTURE : Le premier client ne représente que 1,51 % de l'activité : aucune
-- dépendance à un gros client.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 9 : Sous-requete : jours dont l'activite depasse moyenne + 2 ecarts-types (pics)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quels jours sont exceptionnellement chargés (au-dessus de la moyenne + 2 écarts-types) ?
-- NOTE : Version adaptee pour DB Browser : le notebook utilise SQRT(variance), fonction absente de
-- certaines versions de SQLite. Ici on compare (n - moyenne)^2 a 4 x variance, ce qui est
-- mathematiquement identique a n > moyenne + 2 x ecart-type.
WITH par_jour AS (
    SELECT DATE(event_ts) AS jour, COUNT(*) AS n
    FROM container_events
    GROUP BY 1
), stats AS (
    SELECT AVG(n) AS moy,
           AVG(n*n) - AVG(n)*AVG(n) AS variance      -- variance = E[n^2] - E[n]^2
    FROM par_jour
)
SELECT p.jour, p.n, ROUND(s.moy,1) AS moyenne
FROM par_jour p, stats s
WHERE p.n > s.moy
  AND (p.n - s.moy)*(p.n - s.moy) > 4*s.variance     -- equivaut a n > moyenne + 2 ecarts-types
ORDER BY p.n DESC;

-- RESULTAT / LECTURE : 9 jours dépassent la moyenne + 2 écarts-types (environ 41 événements). 7
-- d'entre eux tombent entre début mai et début juillet : cette observation est discutée dans l'EDA
-- (partie B, section 9).


/* ##########################################################################################
   PARTIE : GRAIN, UNICITE DES CLES, INTEGRITE REFERENTIELLE, ANOMALIES
   Consigne du prof (TODO 5) : identifier le grain du Data Warehouse et valider l'unicite des cles sources. Grain valide : 1 ligne = 1 evenement conteneur (event_id) et 1 ligne = 1 mouvement de cour (move_id). Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 10 : Unicite des cles primaires candidates (attendu : 0 doublon partout)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Y a-t-il des doublons dans les identifiants (clés) de chaque table ? (attendu : 0)
SELECT 'container_events.event_id' AS cle, COUNT(*) - COUNT(DISTINCT event_id) AS doublons FROM container_events
UNION ALL SELECT 'yard_moves.move_id', COUNT(*) - COUNT(DISTINCT move_id) FROM yard_moves
UNION ALL SELECT 'customers.customer_id', COUNT(*) - COUNT(DISTINCT customer_id) FROM customers
UNION ALL SELECT 'vessel_calls.vessel_id', COUNT(*) - COUNT(DISTINCT vessel_id) FROM vessel_calls
UNION ALL SELECT 'equipment.equipment_id', COUNT(*) - COUNT(DISTINCT equipment_id) FROM equipment;

-- RESULTAT / LECTURE : Aucun doublon : chaque clé est unique. Le grain « 1 ligne = 1 événement »
-- (event_id) et « 1 ligne = 1 mouvement » (move_id) est validé.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 11 : Integrite referentielle (attendu : 0 orphelin partout)
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Y a-t-il des lignes « orphelines » qui pointent vers un client, navire, engin ou conteneur inexistant ? (attendu : 0)
SELECT 'events -> customers' AS controle, COUNT(*) AS orphelins FROM container_events e
  LEFT JOIN customers c ON c.customer_id=e.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'events -> vessel_calls', COUNT(*) FROM container_events e
  LEFT JOIN vessel_calls v ON v.vessel_id=e.vessel_id WHERE v.vessel_id IS NULL
UNION ALL SELECT 'yard_moves -> equipment', COUNT(*) FROM yard_moves m
  LEFT JOIN equipment q ON q.equipment_id=m.equipment_id WHERE q.equipment_id IS NULL
UNION ALL SELECT 'yard_moves -> events (container_id)', COUNT(*) FROM yard_moves m
  WHERE m.container_id NOT IN (SELECT container_id FROM container_events);

-- RESULTAT / LECTURE : Aucun orphelin : tous les clients, navires et équipements référencés
-- existent, et, dans cette version auditée des données, tous les conteneurs des mouvements
-- existent dans les événements.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 12 : Anomalies metier a surveiller
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quelles anomalies métier faut-il surveiller (mouvements départ = arrivée, zone Y08B) ?
SELECT 'mouvements from_area = to_area' AS anomalie, COUNT(*) AS valeur FROM yard_moves WHERE from_area = to_area
UNION ALL SELECT 'evenements en zone Y08B', COUNT(*) FROM container_events WHERE yard_area = 'Y08B'
UNION ALL SELECT 'mouvements arrivant en zone Y08B (to_area)', COUNT(*) FROM yard_moves WHERE to_area = 'Y08B'
UNION ALL SELECT 'mouvements partant de la zone Y08B (from_area)', COUNT(*) FROM yard_moves WHERE from_area = 'Y08B';

-- RESULTAT / LECTURE : 712 mouvements (15,8 %) ont une zone de départ identique à la zone
-- d'arrivée. Y08B apparaît dans 1 481 événements et 758 fois comme zone d'arrivée, jamais comme
-- zone de départ : cela suggère une sous-zone de Y08, hypothèse à valider avec le propriétaire
-- métier.


/* ##########################################################################################
   PARTIE : KPI COMPLETS (navires, services, clients)
   KPI 3 (volumes par navire / service) et KPI 4 (activite par client) du catalogue des KPI attendus. Astuce : selectionnez une requete (jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le fichier est execute et seul le dernier resultat s'affiche.
   ########################################################################################## */


-- ---------------------------------------------------------------------------------------------
-- REQUETE 13 : KPI 3a : volumes par navire (top 10) avec son service
-- ---------------------------------------------------------------------------------------------
-- QUESTION : Quels sont les 10 navires les plus actifs ?
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
-- QUESTION : Combien d'événements, de navires et de tonnes par service ?
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
-- QUESTION : Les navires Container sont-ils plus actifs que les Feeder ?
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
-- QUESTION : Quels sont les 10 clients les plus actifs ?
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
-- QUESTION : Quelle est l'activité de chaque groupe de clients ?
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
-- QUESTION : Les 10 premiers clients concentrent-ils beaucoup de l'activité ?
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
