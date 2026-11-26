-- =============================================================================================
-- ETL / 05 : COUCHE MART (une table par KPI)
-- =============================================================================================
-- Les 6 KPI du catalogue (10_EXPECTED_KPIS) : evenements par jour, MOVE par zone, volumes par
-- navire/service, activite par client, poids moyen par type d'evenement, part FCL/MTY.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_events_per_day
-- MART : une table par KPI mart_kpi_events_per_day.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_events_per_day;
CREATE TABLE mart_kpi_events_per_day AS
SELECT d.full_date, d.year_month, COUNT(*) AS nb_evenements, COUNT(DISTINCT f.container_id) AS nb_conteneurs,
       ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_date d ON d.date_key = f.date_key
GROUP BY d.full_date, d.year_month;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_move_by_area
-- MART : une table par KPI mart_kpi_move_by_area.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_move_by_area;
CREATE TABLE mart_kpi_move_by_area AS
SELECT a.area_code, a.parent_area, a.is_subarea, COUNT(*) AS nb_move
FROM fact_container_event f
JOIN dim_event_type t ON t.event_type_key = f.event_type_key
JOIN dim_yard_area a  ON a.area_key = f.area_key
WHERE t.event_type = 'MOVE'
GROUP BY a.area_code, a.parent_area, a.is_subarea;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_vessel
-- MART : une table par KPI mart_kpi_vessel.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_vessel;
CREATE TABLE mart_kpi_vessel AS
SELECT v.vessel_id, v.vessel_name, v.vessel_type, v.service_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes
FROM fact_container_event f JOIN dim_vessel v ON v.vessel_key = f.vessel_key
GROUP BY v.vessel_id, v.vessel_name, v.vessel_type, v.service_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_service
-- MART : une table par KPI mart_kpi_service.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_service;
CREATE TABLE mart_kpi_service AS
SELECT service_code, COUNT(*) AS nb_navires, SUM(nb_evenements) AS nb_evenements,
       ROUND(1.0*SUM(nb_evenements)/COUNT(*), 1) AS evenements_par_navire,
       ROUND(SUM(tonnes), 0) AS tonnes,
       ROUND(100.0*SUM(nb_evenements)/(SELECT SUM(nb_evenements) FROM mart_kpi_vessel), 1) AS pct_evenements
FROM mart_kpi_vessel GROUP BY service_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_customer
-- MART : une table par KPI mart_kpi_customer.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_customer;
CREATE TABLE mart_kpi_customer AS
SELECT c.customer_id, c.customer_name, c.customer_type, c.group_code, COUNT(*) AS nb_evenements,
       COUNT(DISTINCT f.container_id) AS nb_conteneurs, ROUND(SUM(f.gross_weight_kg)/1000.0, 1) AS tonnes,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_customer c        ON c.customer_key = f.customer_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY c.customer_id, c.customer_name, c.customer_type, c.group_code;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_event_type
-- MART : une table par KPI mart_kpi_event_type.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_event_type;
CREATE TABLE mart_kpi_event_type AS
SELECT t.event_type, t.event_family, COUNT(*) AS nb_evenements, ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg,
       ROUND(100.0*SUM(fs.freight_status = 'FCL')/COUNT(*), 1) AS pct_fcl
FROM fact_container_event f
JOIN dim_event_type t      ON t.event_type_key = f.event_type_key
JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY t.event_type, t.event_family;

-- ---------------------------------------------------------------------------------------------
-- [MART] mart_kpi_freight
-- MART : une table par KPI mart_kpi_freight.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS mart_kpi_freight;
CREATE TABLE mart_kpi_freight AS
SELECT fs.freight_status, fs.freight_label, COUNT(*) AS nb_evenements,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM fact_container_event), 1) AS pct_evenements,
       ROUND(AVG(f.gross_weight_kg), 0) AS poids_moyen_kg
FROM fact_container_event f JOIN dim_freight_status fs ON fs.freight_key = f.freight_key
GROUP BY fs.freight_status, fs.freight_label;

-- Pour consulter un KPI : SELECT * FROM mart_kpi_move_by_area ORDER BY nb_move DESC;
