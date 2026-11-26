-- =============================================================================================
-- ETL / 07 : RECONCILIATION DES VOLUMES
-- =============================================================================================
-- RAW = charge dans le CORE + rejete. Ecart attendu : 0 (aucune ligne perdue ni inventee).
-- =============================================================================================

SELECT 'container_events' AS source,
       (SELECT COUNT(*) FROM raw_container_events) AS raw,
       (SELECT COUNT(*) FROM fact_container_event) AS charge,
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='container_events') AS rejete
UNION ALL
SELECT 'yard_moves',
       (SELECT COUNT(*) FROM raw_yard_moves),
       (SELECT COUNT(*) FROM fact_yard_move),
       (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='yard_moves');

-- Note : le journal de monitoring (table etl_run_metrics : duree et volume de chaque etape) est
-- alimente par le script Python 04_scripts/etl/etl_pipeline.py ; il n'est pas reproductible en SQL
-- pur. Pour le consulter dans DB Browser : SELECT * FROM etl_run_metrics; (base
-- 03_data/warehouse/smartport_complet.db).
