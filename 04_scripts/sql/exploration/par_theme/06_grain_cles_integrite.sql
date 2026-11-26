-- =============================================================================================
-- ETAPE 2 / A.3 : GRAIN, UNICITE DES CLES, INTEGRITE REFERENTIELLE, ANOMALIES
-- =============================================================================================
-- Consigne du prof (TODO 5) : identifier le grain du Data Warehouse et valider l'unicite des cles
-- sources.
-- Grain valide : 1 ligne = 1 evenement conteneur (event_id) et 1 ligne = 1 mouvement de cour
-- (move_id).
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 10 : Unicite des cles primaires candidates (attendu : 0 doublon partout)
-- ---------------------------------------------------------------------------------------------
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
SELECT 'mouvements from_area = to_area' AS anomalie, COUNT(*) AS valeur FROM yard_moves WHERE from_area = to_area
UNION ALL SELECT 'evenements en zone Y08B', COUNT(*) FROM container_events WHERE yard_area = 'Y08B'
UNION ALL SELECT 'mouvements arrivant en zone Y08B (to_area)', COUNT(*) FROM yard_moves WHERE to_area = 'Y08B'
UNION ALL SELECT 'mouvements partant de la zone Y08B (from_area)', COUNT(*) FROM yard_moves WHERE from_area = 'Y08B';

-- RESULTAT / LECTURE : 712 mouvements (15,8 %) ont une zone de départ identique à la zone
-- d'arrivée. Y08B apparaît dans 1 481 événements et 758 fois comme zone d'arrivée, jamais comme
-- zone de départ : cela suggère une sous-zone de Y08, hypothèse à valider avec le propriétaire
-- métier.
