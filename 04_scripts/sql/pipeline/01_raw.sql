-- =============================================================================================
-- ETL / 01 : COUCHE RAW (copie brute, tout en texte)
-- =============================================================================================
-- Pre-requis : les 5 tables sources sont remplies (voir 04_scripts/sql/exploration/par_theme/01_creation_et_import_tables.sql).
-- RAW = copie fidele des sources, AUCUNE transformation. Toutes les colonnes sont en TEXT, les
-- valeurs vides deviennent '' et on ajoute 2 colonnes de tracabilite : _source_file et _loaded_at.
-- (Dans le notebook, cette etape est faite par load_raw() en Python ; ici c'est l'equivalent en
-- SQL pur.)
-- =============================================================================================

DROP TABLE IF EXISTS raw_customers;
CREATE TABLE raw_customers (
    customer_id TEXT,
    customer_name TEXT,
    group_code TEXT,
    customer_type TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_customers
SELECT COALESCE(CAST(customer_id AS TEXT), ''), COALESCE(CAST(customer_name AS TEXT), ''), COALESCE(CAST(group_code AS TEXT), ''), COALESCE(CAST(customer_type AS TEXT), ''), 'customers.csv', datetime('now')
FROM customers;

DROP TABLE IF EXISTS raw_vessel_calls;
CREATE TABLE raw_vessel_calls (
    vessel_id TEXT,
    vessel_name TEXT,
    vessel_type TEXT,
    service_code TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_vessel_calls
SELECT COALESCE(CAST(vessel_id AS TEXT), ''), COALESCE(CAST(vessel_name AS TEXT), ''), COALESCE(CAST(vessel_type AS TEXT), ''), COALESCE(CAST(service_code AS TEXT), ''), 'vessel_calls.csv', datetime('now')
FROM vessel_calls;

DROP TABLE IF EXISTS raw_container_events;
CREATE TABLE raw_container_events (
    event_id TEXT,
    container_id TEXT,
    customer_id TEXT,
    vessel_id TEXT,
    event_type TEXT,
    event_ts TEXT,
    yard_area TEXT,
    freight_status TEXT,
    gross_weight_kg TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_container_events
SELECT COALESCE(CAST(event_id AS TEXT), ''), COALESCE(CAST(container_id AS TEXT), ''), COALESCE(CAST(customer_id AS TEXT), ''), COALESCE(CAST(vessel_id AS TEXT), ''), COALESCE(CAST(event_type AS TEXT), ''), COALESCE(CAST(event_ts AS TEXT), ''), COALESCE(CAST(yard_area AS TEXT), ''), COALESCE(CAST(freight_status AS TEXT), ''), COALESCE(CAST(gross_weight_kg AS TEXT), ''), 'container_events.csv', datetime('now')
FROM container_events;

DROP TABLE IF EXISTS raw_yard_moves;
CREATE TABLE raw_yard_moves (
    move_id TEXT,
    container_id TEXT,
    move_ts TEXT,
    from_area TEXT,
    to_area TEXT,
    equipment_id TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_yard_moves
SELECT COALESCE(CAST(move_id AS TEXT), ''), COALESCE(CAST(container_id AS TEXT), ''), COALESCE(CAST(move_ts AS TEXT), ''), COALESCE(CAST(from_area AS TEXT), ''), COALESCE(CAST(to_area AS TEXT), ''), COALESCE(CAST(equipment_id AS TEXT), ''), 'yard_moves.csv', datetime('now')
FROM yard_moves;

DROP TABLE IF EXISTS raw_equipment;
CREATE TABLE raw_equipment (
    equipment_id TEXT,
    equipment_type TEXT,
    home_area TEXT,
    _source_file TEXT,
    _loaded_at TEXT
);
INSERT INTO raw_equipment
SELECT COALESCE(CAST(equipment_id AS TEXT), ''), COALESCE(CAST(equipment_type AS TEXT), ''), COALESCE(CAST(home_area AS TEXT), ''), 'equipment.csv', datetime('now')
FROM equipment;

-- Verification : volumes RAW (attendu 80 / 120 / 9000 / 4500 / 40)
SELECT 'raw_customers' AS table_raw, COUNT(*) AS nb FROM raw_customers
UNION ALL SELECT 'raw_vessel_calls', COUNT(*) FROM raw_vessel_calls
UNION ALL SELECT 'raw_container_events', COUNT(*) FROM raw_container_events
UNION ALL SELECT 'raw_yard_moves', COUNT(*) FROM raw_yard_moves
UNION ALL SELECT 'raw_equipment', COUNT(*) FROM raw_equipment;
