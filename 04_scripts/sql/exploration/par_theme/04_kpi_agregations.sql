-- =============================================================================================
-- ETAPE 2 / A.3 : AGREGATIONS (GROUP BY) = KPI DE BASE
-- =============================================================================================
-- Consigne du prof (TODO 3) : au moins 2 requetes GROUP BY de type KPI.
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 5 : KPI 1 : evenements par jour (10 premiers jours les plus charges)
-- ---------------------------------------------------------------------------------------------
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
SELECT event_type, COUNT(*) AS nb,
       ROUND(AVG(gross_weight_kg),0) AS poids_moyen_kg,
       ROUND(100.0*SUM(freight_status='FCL')/COUNT(*),1) AS pct_fcl
FROM container_events
GROUP BY event_type
ORDER BY nb DESC;

-- RESULTAT / LECTURE : Le poids moyen est quasi identique pour tous les types d'événements (18,4 à
-- 18,8 tonnes) et la part de conteneurs pleins reste entre 74,0 % et 77,0 %.
