-- =============================================================================================
-- ETAPE 2 / A.3 : JOINTURES
-- =============================================================================================
-- Consigne du prof (TODO 2) : au moins 3 requetes avec JOIN.
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 2 : JOIN 1 : evenements x clients (activite par type de client)
-- ---------------------------------------------------------------------------------------------
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
