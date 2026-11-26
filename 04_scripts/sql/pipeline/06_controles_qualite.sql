-- =============================================================================================
-- ETL / 06 : CONTROLES QUALITE (15 controles du pipeline + 17 regles du prof)
-- =============================================================================================
-- Chaque controle calcule une valeur observee et la compare a la valeur attendue (0 en general).
-- Statut : PASS si observe = attendu, sinon FAIL (ou WARN pour les alertes non bloquantes).
-- Resultats dans la table etl_quality_checks. A lancer APRES les etapes 01 a 05.
-- =============================================================================================

DROP TABLE IF EXISTS etl_quality_checks;
CREATE TABLE etl_quality_checks (check_id TEXT, layer TEXT, description TEXT,
    observed REAL, expected REAL, status TEXT);

-- ---------------------------------------------------------------------------------------------
-- A. Les 15 controles du pipeline (Q01 a Q15)
-- ---------------------------------------------------------------------------------------------

-- Q01 [RAW] Volume : 1 si raw_container_events est vide (attendu 0)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q01', 'RAW', 'Volume : 1 si raw_container_events est vide (attendu 0)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_container_events
) AS obs);

-- Q02 [CORE] Unicite de event_id dans fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q02', 'CORE', 'Unicite de event_id dans fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM fact_container_event
) AS obs);

-- Q03 [CORE] Unicite de move_id dans fact_yard_move
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q03', 'CORE', 'Unicite de move_id dans fact_yard_move', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT move_id) FROM fact_yard_move
) AS obs);

-- Q04 [STAGING] Valeurs nulles dans les colonnes cles de stg_container_events
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q04', 'STAGING', 'Valeurs nulles dans les colonnes cles de stg_container_events', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events WHERE event_id IS NULL OR container_id IS NULL OR customer_id IS NULL
     OR vessel_id IS NULL OR event_type IS NULL OR event_ts IS NULL OR yard_area_raw IS NULL OR gross_weight_kg IS NULL
) AS obs);

-- Q05 [CORE] Integrite referentielle : cles de fact_container_event absentes des dimensions
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q05', 'CORE', 'Integrite referentielle : cles de fact_container_event absentes des dimensions', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM fact_container_event WHERE customer_key NOT IN (SELECT customer_key FROM dim_customer))
          + (SELECT COUNT(*) FROM fact_container_event WHERE vessel_key NOT IN (SELECT vessel_key FROM dim_vessel))
          + (SELECT COUNT(*) FROM fact_container_event WHERE area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_container_event WHERE event_type_key NOT IN (SELECT event_type_key FROM dim_event_type))
          + (SELECT COUNT(*) FROM fact_container_event WHERE freight_key NOT IN (SELECT freight_key FROM dim_freight_status))
          + (SELECT COUNT(*) FROM fact_container_event WHERE date_key NOT IN (SELECT date_key FROM dim_date))
) AS obs);

-- Q06 [CORE] Integrite referentielle : cles de fact_yard_move absentes des dimensions
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q06', 'CORE', 'Integrite referentielle : cles de fact_yard_move absentes des dimensions', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM fact_yard_move WHERE from_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE to_area_key NOT IN (SELECT area_key FROM dim_yard_area))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE equipment_key NOT IN (SELECT equipment_key FROM dim_equipment))
          + (SELECT COUNT(*) FROM fact_yard_move WHERE date_key NOT IN (SELECT date_key FROM dim_date))
) AS obs);

-- Q07 [STAGING] Domaine des valeurs : event_type et freight_status hors referentiel
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q07', 'STAGING', 'Domaine des valeurs : event_type et freight_status hors referentiel', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events
      WHERE event_type NOT IN ('DISCHARGE','LOAD','MOVE','DELIVER','RECEIVE','STUFF','SEAL') OR freight_status NOT IN ('FCL','MTY')
) AS obs);

-- Q08 [CORE] Plage du poids : valeurs hors 0..40000 kg dans fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q08', 'CORE', 'Plage du poids : valeurs hors 0..40000 kg dans fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_container_event WHERE gross_weight_kg <= 0 OR gross_weight_kg > 40000
) AS obs);

-- Q09 [CORE] Reconciliation evenements : RAW - (CORE + rejets)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q09', 'CORE', 'Reconciliation evenements : RAW - (CORE + rejets)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM raw_container_events) - (SELECT COUNT(*) FROM fact_container_event)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'container_events')
) AS obs);

-- Q10 [CORE] Reconciliation mouvements : RAW - (CORE + rejets)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q10', 'CORE', 'Reconciliation mouvements : RAW - (CORE + rejets)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT COUNT(*) FROM raw_yard_moves) - (SELECT COUNT(*) FROM fact_yard_move)
          - (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table = 'yard_moves')
) AS obs);

-- Q11 [CORE] Conservation de la mesure : poids total STAGING - poids total CORE (kg)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q11', 'CORE', 'Conservation de la mesure : poids total STAGING - poids total CORE (kg)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT ROUND((SELECT SUM(gross_weight_kg) FROM stg_container_events) - (SELECT SUM(gross_weight_kg) FROM fact_container_event), 3)
) AS obs);

-- Q12 [MART] Coherence MART : somme des evenements par jour - lignes de fact_container_event
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q12', 'MART', 'Coherence MART : somme des evenements par jour - lignes de fact_container_event', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT (SELECT SUM(nb_evenements) FROM mart_kpi_events_per_day) - (SELECT COUNT(*) FROM fact_container_event)
) AS obs);

-- Q13 [CORE] Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q13', 'CORE', 'Coherence metier : mouvements de cour avec from_area = to_area (signales, conserves)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_yard_move WHERE is_same_area = 1
) AS obs);

-- Q14 [CORE] Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q14', 'CORE', 'Integrite : mouvements portant sur un conteneur absent des evenements (regle FK_CONTAINER)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM fact_yard_move WHERE container_id NOT IN (SELECT container_id FROM fact_container_event)
) AS obs);

-- Q15 [STAGING] Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'Q15', 'STAGING', 'Standardisation : evenements dont la zone a ete rattachee a sa zone parente (Y08B -> Y08)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'INFO' END
FROM (SELECT (
SELECT COUNT(*) FROM stg_container_events WHERE yard_area_raw <> yard_area_std
) AS obs);

-- ---------------------------------------------------------------------------------------------
-- B. Les 17 regles qualite du prof (05_governance/data_quality_rules.csv)
--    ROW_COUNT, DUPLICATE_CHECK, NULL_RATE sur les 5 tables + FK_CONTAINER + FK_EQUIPMENT
-- ---------------------------------------------------------------------------------------------

-- ROW_COUNT customers : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_customers', 'RAW', 'ROW_COUNT customers : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_customers
) AS obs);

-- ROW_COUNT vessel_calls : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_vessel_calls', 'RAW', 'ROW_COUNT vessel_calls : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_vessel_calls
) AS obs);

-- ROW_COUNT container_events : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_container_events', 'RAW', 'ROW_COUNT container_events : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_container_events
) AS obs);

-- ROW_COUNT yard_moves : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_yard_moves', 'RAW', 'ROW_COUNT yard_moves : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_yard_moves
) AS obs);

-- ROW_COUNT equipment : la table n'est pas vide (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_ROW_COUNT_equipment', 'RAW', 'ROW_COUNT equipment : table vide ? (0 = non vide)', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT CASE WHEN COUNT(*) > 0 THEN 0 ELSE 1 END FROM raw_equipment
) AS obs);

-- DUPLICATE_CHECK customers : la cle metier customer_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_customers', 'RAW', 'DUPLICATE_CHECK customers : doublons sur customer_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(customer_id)) FROM raw_customers
) AS obs);

-- DUPLICATE_CHECK vessel_calls : la cle metier vessel_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_vessel_calls', 'RAW', 'DUPLICATE_CHECK vessel_calls : doublons sur vessel_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(vessel_id)) FROM raw_vessel_calls
) AS obs);

-- DUPLICATE_CHECK container_events : la cle metier event_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_container_events', 'RAW', 'DUPLICATE_CHECK container_events : doublons sur event_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(event_id)) FROM raw_container_events
) AS obs);

-- DUPLICATE_CHECK yard_moves : la cle metier move_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_yard_moves', 'RAW', 'DUPLICATE_CHECK yard_moves : doublons sur move_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(move_id)) FROM raw_yard_moves
) AS obs);

-- DUPLICATE_CHECK equipment : la cle metier equipment_id est unique (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_DUPLICATE_CHECK_equipment', 'RAW', 'DUPLICATE_CHECK equipment : doublons sur equipment_id', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) - COUNT(DISTINCT TRIM(equipment_id)) FROM raw_equipment
) AS obs);

-- NULL_RATE customers : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_customers', 'RAW', 'NULL_RATE customers : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_name IS NULL OR TRIM(customer_name) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN group_code IS NULL OR TRIM(group_code) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_type IS NULL OR TRIM(customer_type) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 4), 2) FROM raw_customers
) AS obs);

-- NULL_RATE vessel_calls : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_vessel_calls', 'RAW', 'NULL_RATE vessel_calls : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN vessel_id IS NULL OR TRIM(vessel_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_name IS NULL OR TRIM(vessel_name) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_type IS NULL OR TRIM(vessel_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN service_code IS NULL OR TRIM(service_code) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 4), 2) FROM raw_vessel_calls
) AS obs);

-- NULL_RATE container_events : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_container_events', 'RAW', 'NULL_RATE container_events : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN event_id IS NULL OR TRIM(event_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN container_id IS NULL OR TRIM(container_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN customer_id IS NULL OR TRIM(customer_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN vessel_id IS NULL OR TRIM(vessel_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN event_type IS NULL OR TRIM(event_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN event_ts IS NULL OR TRIM(event_ts) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN yard_area IS NULL OR TRIM(yard_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN freight_status IS NULL OR TRIM(freight_status) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN gross_weight_kg IS NULL OR TRIM(gross_weight_kg) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 9), 2) FROM raw_container_events
) AS obs);

-- NULL_RATE yard_moves : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_yard_moves', 'RAW', 'NULL_RATE yard_moves : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN move_id IS NULL OR TRIM(move_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN container_id IS NULL OR TRIM(container_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN move_ts IS NULL OR TRIM(move_ts) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN from_area IS NULL OR TRIM(from_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN to_area IS NULL OR TRIM(to_area) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN equipment_id IS NULL OR TRIM(equipment_id) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 6), 2) FROM raw_yard_moves
) AS obs);

-- NULL_RATE equipment : % de cellules vides (gravite MEDIUM, alerte WARN)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'DQ_NULL_RATE_equipment', 'RAW', 'NULL_RATE equipment : % de cellules vides', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'WARN' END
FROM (SELECT (
SELECT ROUND(100.0 * (SUM(CASE WHEN equipment_id IS NULL OR TRIM(equipment_id) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN equipment_type IS NULL OR TRIM(equipment_type) = '' THEN 1 ELSE 0 END) + SUM(CASE WHEN home_area IS NULL OR TRIM(home_area) = '' THEN 1 ELSE 0 END)) / (COUNT(*) * 3), 2) FROM raw_equipment
) AS obs);

-- FK_CONTAINER (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'FK_CONTAINER', 'RAW', 'FK_CONTAINER : mouvements dont le container_id est absent de container_events', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(container_id) NOT IN (SELECT TRIM(container_id) FROM raw_container_events)
) AS obs);

-- FK_EQUIPMENT (gravite HIGH)
INSERT INTO etl_quality_checks (check_id, layer, description, observed, expected, status)
SELECT 'FK_EQUIPMENT', 'RAW', 'FK_EQUIPMENT : mouvements dont l''equipment_id est absent de equipment', obs, 0, CASE WHEN obs = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (SELECT (
SELECT COUNT(*) FROM raw_yard_moves WHERE TRIM(equipment_id) NOT IN (SELECT TRIM(equipment_id) FROM raw_equipment)
) AS obs);

-- ---------------------------------------------------------------------------------------------
-- C. Synthese
-- ---------------------------------------------------------------------------------------------
SELECT status, COUNT(*) AS nb FROM etl_quality_checks GROUP BY status ORDER BY status;

SELECT * FROM etl_quality_checks;
