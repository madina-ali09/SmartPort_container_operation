-- =============================================================================================
-- ETL / 00 : REINITIALISATION (idempotence)
-- =============================================================================================
-- Supprime toutes les tables reconstruites par le pipeline (RAW, STAGING, CORE, MART, rejets,
-- controles). Les tables sources (customers, ...) et le journal etl_run_metrics ne sont pas
-- touches. Relancer le pipeline apres ce fichier donne toujours le meme resultat : pas de
-- doublons.
-- =============================================================================================

DROP TABLE IF EXISTS raw_customers;
DROP TABLE IF EXISTS raw_vessel_calls;
DROP TABLE IF EXISTS raw_container_events;
DROP TABLE IF EXISTS raw_yard_moves;
DROP TABLE IF EXISTS raw_equipment;
DROP TABLE IF EXISTS stg_customers;
DROP TABLE IF EXISTS stg_vessels;
DROP TABLE IF EXISTS stg_equipment;
DROP TABLE IF EXISTS stg_container_events;
DROP TABLE IF EXISTS stg_yard_moves;
DROP TABLE IF EXISTS fact_yard_move;
DROP TABLE IF EXISTS fact_container_event;
DROP TABLE IF EXISTS dim_equipment;
DROP TABLE IF EXISTS dim_freight_status;
DROP TABLE IF EXISTS dim_event_type;
DROP TABLE IF EXISTS dim_yard_area;
DROP TABLE IF EXISTS dim_vessel;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_hour;
DROP TABLE IF EXISTS dim_date;
DROP TABLE IF EXISTS mart_kpi_events_per_day;
DROP TABLE IF EXISTS mart_kpi_move_by_area;
DROP TABLE IF EXISTS mart_kpi_vessel;
DROP TABLE IF EXISTS mart_kpi_service;
DROP TABLE IF EXISTS mart_kpi_customer;
DROP TABLE IF EXISTS mart_kpi_event_type;
DROP TABLE IF EXISTS mart_kpi_freight;
DROP TABLE IF EXISTS etl_rejects;
DROP TABLE IF EXISTS etl_quality_checks;
