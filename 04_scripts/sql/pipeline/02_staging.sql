-- =============================================================================================
-- ETL / 02 : COUCHE STAGING (nettoyage, typage, regles de rejet)
-- =============================================================================================
-- STAGING = donnees nettoyees et typees. Les lignes qui violent une regle sont COPIEES dans
-- etl_rejects (avec l'identifiant de la regle) puis exclues des tables stg_*.
-- Ordre important : dimensions -> table des rejets -> regles EV/MV -> stg_container_events et
-- stg_yard_moves.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_customers
-- Nettoie les clients : TRIM des textes et suppression des doublons sur customer_id (on garde la
-- 1ere ligne).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_customers;
CREATE TABLE stg_customers AS
SELECT TRIM(customer_id) AS customer_id, TRIM(customer_name) AS customer_name,
       TRIM(group_code) AS group_code, TRIM(customer_type) AS customer_type
FROM raw_customers
WHERE TRIM(customer_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_customers GROUP BY TRIM(customer_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_vessels
-- Nettoie les navires : TRIM des textes et suppression des doublons sur vessel_id.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_vessels;
CREATE TABLE stg_vessels AS
SELECT TRIM(vessel_id) AS vessel_id, TRIM(vessel_name) AS vessel_name,
       TRIM(vessel_type) AS vessel_type, TRIM(service_code) AS service_code
FROM raw_vessel_calls
WHERE TRIM(vessel_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_vessel_calls GROUP BY TRIM(vessel_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_equipment
-- Nettoie les equipements : TRIM des textes et suppression des doublons sur equipment_id.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_equipment;
CREATE TABLE stg_equipment AS
SELECT TRIM(equipment_id) AS equipment_id, TRIM(equipment_type) AS equipment_type,
       TRIM(home_area) AS home_area
FROM raw_equipment
WHERE TRIM(equipment_id) <> ''
  AND rowid IN (SELECT MIN(rowid) FROM raw_equipment GROUP BY TRIM(equipment_id));

-- ---------------------------------------------------------------------------------------------
-- [STAGING] create etl_rejects
-- Table des rejets : chaque ligne refusee est ecrite ici avec la regle et la raison du rejet.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS etl_rejects;
CREATE TABLE etl_rejects (
    reject_id INTEGER PRIMARY KEY AUTOINCREMENT,
    source_table TEXT, raw_rowid INTEGER, business_key TEXT,
    rule_id TEXT, rule_description TEXT);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV01 event_id manquant
-- Regle de rejet EV01 : event_id manquant.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV01', 'event_id manquant'
FROM raw_container_events WHERE event_id IS NULL OR TRIM(event_id) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV02 event_id en double
-- Regle de rejet EV02 : event_id en double (on garde la 1ere occurrence).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV02', 'event_id en double (on garde la 1re ligne)'
FROM raw_container_events WHERE TRIM(event_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_container_events GROUP BY event_id);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV03 date invalide
-- Regle de rejet EV03 : date d'evenement illisible.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV03', 'event_ts illisible'
FROM raw_container_events WHERE datetime(event_ts) IS NULL;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV04 type hors domaine
-- Regle de rejet EV04 : event_type hors du domaine autorise.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV04', 'event_type hors domaine'
FROM raw_container_events WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV05 statut FCL/MTY invalide
-- Regle de rejet EV05 : freight_status different de FCL / MTY.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV05', 'freight_status hors FCL/MTY'
FROM raw_container_events WHERE freight_status NOT IN ('FCL','MTY');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV06 poids hors plage
-- Regle de rejet EV06 : poids hors de la plage 0 a 40000 kg.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV06', 'poids non numerique ou hors 0..40000 kg'
FROM raw_container_events WHERE CAST(gross_weight_kg AS REAL) <= 0 OR CAST(gross_weight_kg AS REAL) > 40000;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV07 client inconnu
-- Regle de rejet EV07 : client inconnu (customer_id absent de customers).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV07', 'customer_id absent du referentiel'
FROM raw_container_events WHERE customer_id NOT IN (SELECT customer_id FROM stg_customers);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV08 navire inconnu
-- Regle de rejet EV08 : navire inconnu (vessel_id absent de vessel_calls).
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV08', 'vessel_id absent du referentiel'
FROM raw_container_events WHERE vessel_id NOT IN (SELECT vessel_id FROM stg_vessels);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] EV09 zone manquante
-- Regle de rejet EV09 : zone yard_area manquante.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'container_events', rowid, event_id, 'EV09', 'yard_area manquante'
FROM raw_container_events WHERE yard_area IS NULL OR TRIM(yard_area) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV01 move_id manquant
-- Regle de rejet MV01 : move_id manquant.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV01', 'move_id manquant'
FROM raw_yard_moves WHERE move_id IS NULL OR TRIM(move_id) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV02 move_id en double
-- Regle de rejet MV02 : move_id en double.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV02', 'move_id en double (on garde la 1re ligne)'
FROM raw_yard_moves WHERE TRIM(move_id) <> '' AND rowid NOT IN (SELECT MIN(rowid) FROM raw_yard_moves GROUP BY move_id);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV03 date invalide
-- Regle de rejet MV03 : date de mouvement illisible.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV03', 'move_ts illisible'
FROM raw_yard_moves WHERE datetime(move_ts) IS NULL;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV04 equipement inconnu
-- Regle de rejet MV04 : equipement inconnu.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV04', 'equipment_id absent du referentiel'
FROM raw_yard_moves WHERE equipment_id NOT IN (SELECT equipment_id FROM stg_equipment);

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV05 zone manquante
-- Regle de rejet MV05 : zone de depart ou d'arrivee manquante.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV05', 'from_area ou to_area manquante'
FROM raw_yard_moves WHERE from_area IS NULL OR TRIM(from_area) = '' OR to_area IS NULL OR TRIM(to_area) = '';

-- ---------------------------------------------------------------------------------------------
-- [STAGING] MV06 conteneur inconnu
-- Regle de rejet MV06 : conteneur absent des evenements.
-- ---------------------------------------------------------------------------------------------
INSERT INTO etl_rejects (source_table, raw_rowid, business_key, rule_id, rule_description)
SELECT 'yard_moves', rowid, move_id, 'MV06', 'container_id absent de container_events'
FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events);

-- ---------------------------------------------------------------------------------------------
-- Resultat des regles de rejet (tableau vide = aucune ligne rejetee, attendu sur ces donnees propres)
-- ---------------------------------------------------------------------------------------------
SELECT rule_id, rule_description, COUNT(*) AS nb
FROM etl_rejects
GROUP BY rule_id, rule_description;

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_container_events
-- Evenements conteneurs types (INTEGER, REAL, date normalisee). Zone standardisee Y08B -> Y08
-- (yard_area_std), zone d'origine conservee (yard_area_raw). Les lignes rejetees sont exclues.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_container_events;
CREATE TABLE stg_container_events AS
SELECT rowid AS raw_rowid,
       CAST(event_id AS INTEGER)        AS event_id,
       TRIM(container_id)               AS container_id,
       TRIM(customer_id)                AS customer_id,
       TRIM(vessel_id)                  AS vessel_id,
       TRIM(event_type)                 AS event_type,
       datetime(event_ts)               AS event_ts,
       TRIM(yard_area)                  AS yard_area_raw,
       SUBSTR(TRIM(yard_area), 1, 3)    AS yard_area_std,   -- Y08B -> Y08
       TRIM(freight_status)             AS freight_status,
       CAST(gross_weight_kg AS REAL)    AS gross_weight_kg
FROM raw_container_events
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'container_events');

-- ---------------------------------------------------------------------------------------------
-- [STAGING] stg_yard_moves
-- Mouvements de cour types, sans les lignes rejetees.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS stg_yard_moves;
CREATE TABLE stg_yard_moves AS
SELECT rowid AS raw_rowid,
       CAST(move_id AS INTEGER) AS move_id, TRIM(container_id) AS container_id,
       datetime(move_ts) AS move_ts, TRIM(from_area) AS from_area, TRIM(to_area) AS to_area,
       TRIM(equipment_id) AS equipment_id
FROM raw_yard_moves
WHERE rowid NOT IN (SELECT raw_rowid FROM etl_rejects WHERE source_table = 'yard_moves');

-- ---------------------------------------------------------------------------------------------
-- Controle : zone d'origine vs zone standardisee (Y08B -> Y08)
-- ---------------------------------------------------------------------------------------------
SELECT yard_area_raw, yard_area_std, COUNT(*) AS nb
FROM stg_container_events
GROUP BY 1, 2
ORDER BY 1;
