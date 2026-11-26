-- =============================================================================================
-- ETAPE 2 / A.1 : CREATION DES TABLES SOURCES (schema fourni par le prof)
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
