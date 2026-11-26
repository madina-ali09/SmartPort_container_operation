-- =============================================================================================
-- ETL / 04 : COUCHE CORE - TABLES DE FAITS
-- =============================================================================================
-- Grain : fact_container_event = 1 ligne par evenement conteneur ; fact_yard_move = 1 ligne par
-- mouvement de cour. Les faits referencent les dimensions par leurs cles de substitution.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [CORE] create fact_container_event
-- CORE : creation de la table de faits fact_container_event (cles etrangeres vers les dimensions).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_container_event;
CREATE TABLE fact_container_event (
    event_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    customer_key INTEGER NOT NULL REFERENCES dim_customer(customer_key), vessel_key INTEGER NOT NULL REFERENCES dim_vessel(vessel_key),
    area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), event_type_key INTEGER NOT NULL REFERENCES dim_event_type(event_type_key),
    freight_key INTEGER NOT NULL REFERENCES dim_freight_status(freight_key),
    event_ts TEXT NOT NULL, event_count INTEGER NOT NULL DEFAULT 1, gross_weight_kg REAL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] create fact_yard_move
-- CORE : creation de la table de faits fact_yard_move (cles etrangeres vers les dimensions).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS fact_yard_move;
CREATE TABLE fact_yard_move (
    move_id INTEGER PRIMARY KEY, container_id TEXT NOT NULL,
    date_key INTEGER NOT NULL REFERENCES dim_date(date_key), hour_key INTEGER NOT NULL REFERENCES dim_hour(hour_key),
    from_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key), to_area_key INTEGER NOT NULL REFERENCES dim_yard_area(area_key),
    equipment_key INTEGER NOT NULL REFERENCES dim_equipment(equipment_key),
    move_ts TEXT NOT NULL, move_count INTEGER NOT NULL DEFAULT 1, is_same_area INTEGER NOT NULL);

-- ---------------------------------------------------------------------------------------------
-- [CORE] load fact_container_event
-- CORE : chargement de la table de faits fact_container_event (jointures sur les dimensions).
-- ---------------------------------------------------------------------------------------------
INSERT INTO fact_container_event
SELECT e.event_id, e.container_id, CAST(strftime('%Y%m%d', e.event_ts) AS INTEGER), CAST(strftime('%H', e.event_ts) AS INTEGER),
       c.customer_key, v.vessel_key, a.area_key, t.event_type_key, f.freight_key, e.event_ts, 1, e.gross_weight_kg
FROM stg_container_events e
JOIN dim_customer c       ON c.customer_id = e.customer_id
JOIN dim_vessel v         ON v.vessel_id = e.vessel_id
JOIN dim_yard_area a      ON a.area_code = e.yard_area_raw
JOIN dim_event_type t     ON t.event_type = e.event_type
JOIN dim_freight_status f ON f.freight_status = e.freight_status;

-- ---------------------------------------------------------------------------------------------
-- [CORE] load fact_yard_move
-- CORE : chargement de la table de faits fact_yard_move (jointures sur les dimensions).
-- ---------------------------------------------------------------------------------------------
INSERT INTO fact_yard_move
SELECT m.move_id, m.container_id, CAST(strftime('%Y%m%d', m.move_ts) AS INTEGER), CAST(strftime('%H', m.move_ts) AS INTEGER),
       af.area_key, at.area_key, q.equipment_key, m.move_ts, 1, CASE WHEN m.from_area = m.to_area THEN 1 ELSE 0 END
FROM stg_yard_moves m
JOIN dim_yard_area af ON af.area_code = m.from_area
JOIN dim_yard_area at ON at.area_code = m.to_area
JOIN dim_equipment q  ON q.equipment_id = m.equipment_id;

-- ---------------------------------------------------------------------------------------------
-- Apercu du fait principal
-- ---------------------------------------------------------------------------------------------
SELECT * FROM fact_container_event LIMIT 5;
