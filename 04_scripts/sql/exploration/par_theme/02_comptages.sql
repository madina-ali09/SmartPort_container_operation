-- =============================================================================================
-- ETAPE 2 / A.3 : COMPTAGE DES TABLES SOURCES
-- =============================================================================================
-- Consigne du prof (TODO 1) : compter chaque table source.
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 1 : Comptage de chaque table source
-- ---------------------------------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS nb_lignes FROM customers
UNION ALL SELECT 'vessel_calls', COUNT(*) FROM vessel_calls
UNION ALL SELECT 'container_events', COUNT(*) FROM container_events
UNION ALL SELECT 'yard_moves', COUNT(*) FROM yard_moves
UNION ALL SELECT 'equipment', COUNT(*) FROM equipment;

-- RESULTAT / LECTURE : Les 5 tables contiennent bien 80, 120, 9 000, 4 500 et 40 lignes : l'import
-- est complet et conforme à l'énoncé.
