-- =============================================================================================
-- ETL / 03 : COUCHE CORE - DIMENSIONS (Data Warehouse en etoile)
-- =============================================================================================
-- Chaque dimension : creation de la table puis chargement. dim_date et dim_hour permettent
-- d'analyser par jour / heure ; les autres dimensions portent une cle de substitution (..._key).
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_date
-- CORE : creation de la dimension dim_date (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date (date_key INTEGER PRIMARY KEY, full_date TEXT NOT NULL, year INTEGER, month INTEGER, day INTEGER,
    year_month TEXT, week_of_year INTEGER, day_of_week INTEGER, is_weekend INTEGER);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_hour
-- CORE : creation de la dimension dim_hour (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_hour;
CREATE TABLE dim_hour (hour_key INTEGER PRIMARY KEY, period TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_customer
-- CORE : creation de la dimension dim_customer (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_customer;
CREATE TABLE dim_customer (customer_key INTEGER PRIMARY KEY AUTOINCREMENT, customer_id TEXT NOT NULL UNIQUE,
    customer_name TEXT, group_code TEXT, customer_type TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_vessel
-- CORE : creation de la dimension dim_vessel (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_vessel;
CREATE TABLE dim_vessel (vessel_key INTEGER PRIMARY KEY AUTOINCREMENT, vessel_id TEXT NOT NULL UNIQUE,
    vessel_name TEXT, vessel_type TEXT, service_code TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_yard_area
-- CORE : creation de la dimension dim_yard_area (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_yard_area;
CREATE TABLE dim_yard_area (area_key INTEGER PRIMARY KEY AUTOINCREMENT, area_code TEXT NOT NULL UNIQUE,
    parent_area TEXT NOT NULL, is_subarea INTEGER NOT NULL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_event_type
-- CORE : creation de la dimension dim_event_type (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_event_type;
CREATE TABLE dim_event_type (event_type_key INTEGER PRIMARY KEY AUTOINCREMENT, event_type TEXT NOT NULL UNIQUE, event_family TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_freight_status
-- CORE : creation de la dimension dim_freight_status (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_freight_status;
CREATE TABLE dim_freight_status (freight_key INTEGER PRIMARY KEY AUTOINCREMENT, freight_status TEXT NOT NULL UNIQUE, freight_label TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create dim_equipment
-- CORE : creation de la dimension dim_equipment (cle de substitution).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS dim_equipment;
CREATE TABLE dim_equipment (equipment_key INTEGER PRIMARY KEY AUTOINCREMENT, equipment_id TEXT NOT NULL UNIQUE,
    equipment_type TEXT, home_area TEXT);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_date
-- CORE : chargement de la dimension dim_date depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_date
SELECT CAST(strftime('%Y%m%d', d) AS INTEGER), d, CAST(strftime('%Y', d) AS INTEGER), CAST(strftime('%m', d) AS INTEGER),
       CAST(strftime('%d', d) AS INTEGER), strftime('%Y-%m', d), CAST(strftime('%W', d) AS INTEGER),
       CAST(strftime('%w', d) AS INTEGER), CASE WHEN strftime('%w', d) IN ('0','6') THEN 1 ELSE 0 END
FROM (SELECT DISTINCT DATE(event_ts) AS d FROM stg_container_events
      UNION SELECT DISTINCT DATE(move_ts) FROM stg_yard_moves);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_hour
-- CORE : chargement de la dimension dim_hour depuis STAGING.
-- ---------------------------------------------------------------------------------------------
WITH RECURSIVE h(n) AS (SELECT 0 UNION ALL SELECT n+1 FROM h WHERE n < 23)
INSERT INTO dim_hour
SELECT n, CASE WHEN n < 6 THEN 'Nuit' WHEN n < 12 THEN 'Matin' WHEN n < 18 THEN 'Apres-midi' ELSE 'Soir' END FROM h;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_customer
-- CORE : chargement de la dimension dim_customer depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_customer (customer_id, customer_name, group_code, customer_type)
SELECT customer_id, customer_name, group_code, customer_type FROM stg_customers ORDER BY customer_id;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_vessel
-- CORE : chargement de la dimension dim_vessel depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_vessel (vessel_id, vessel_name, vessel_type, service_code)
SELECT vessel_id, vessel_name, vessel_type, service_code FROM stg_vessels ORDER BY vessel_id;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_yard_area
-- CORE : chargement de la dimension dim_yard_area depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_yard_area (area_code, parent_area, is_subarea)
SELECT a, SUBSTR(a, 1, 3), CASE WHEN LENGTH(a) > 3 THEN 1 ELSE 0 END   -- regle : suffixe lettre = sous-zone
FROM (SELECT yard_area_raw AS a FROM stg_container_events
      UNION SELECT from_area FROM stg_yard_moves UNION SELECT to_area FROM stg_yard_moves) ORDER BY a;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_event_type
-- CORE : chargement de la dimension dim_event_type depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_event_type (event_type, event_family)
SELECT DISTINCT event_type,
       CASE event_type WHEN 'DISCHARGE' THEN 'Operations navire' WHEN 'LOAD' THEN 'Operations navire'
                       WHEN 'RECEIVE' THEN 'Gate' WHEN 'DELIVER' THEN 'Gate' WHEN 'MOVE' THEN 'Cour'
                       WHEN 'STUFF' THEN 'Manutention' WHEN 'SEAL' THEN 'Manutention' ELSE 'Autre' END
FROM stg_container_events ORDER BY event_type;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_freight_status
-- CORE : chargement de la dimension dim_freight_status depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_freight_status (freight_status, freight_label)
SELECT DISTINCT freight_status, CASE freight_status WHEN 'FCL' THEN 'Plein' WHEN 'MTY' THEN 'Vide' ELSE 'Inconnu' END
FROM stg_container_events ORDER BY freight_status;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load dim_equipment
-- CORE : chargement de la dimension dim_equipment depuis STAGING.
-- ---------------------------------------------------------------------------------------------
INSERT INTO dim_equipment (equipment_id, equipment_type, home_area)
SELECT equipment_id, equipment_type, home_area FROM stg_equipment ORDER BY equipment_id;

