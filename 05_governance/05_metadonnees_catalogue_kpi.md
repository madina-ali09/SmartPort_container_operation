# 05 · Métadonnées et catalogue des KPI

## Métadonnées disponibles
| Type | Où |
|---|---|
| Sources, par colonne | `03_data/dictionary/data_dictionary.csv` : type, description, exemple, clé, unité, valeurs distinctes et nulles, domaine, règles qualité, cible dans l'entrepôt |
| Entrepôt, par table | `03_data/dictionary/data_dictionary_dwh.csv` : couche, grain, volume observé, description, origine (volumes relevés sur la base livrée ; celui de `etl_run_metrics` augmente à chaque exécution) |
| Traçabilité | `_source_file`, `_loaded_at` (RAW) ; `raw_rowid` (STAGING, rejets) |
| Exécution | `etl_run_metrics` (`run_id`, couche, étape, lignes, durée, statut) |
| Qualité | `etl_quality_checks`, `etl_rejects` |
| Lineage | `05_governance/lineage_colonnes.csv` |

## Catalogue des KPI
Version complète (définition, grain, source, formule, unité, table MART, résultat, limites) : `03_data/dictionary/kpi_catalog.csv`. Les fichiers de départ sont conservés (`*_enonce.csv`). `fct` = `fact_container_event`.

| KPI | Définition | Grain | Table MART | Formule | Valeur mesurée |
|---|---|---|---|---|---|
| Événements par jour | événements d'un jour calendaire | jour | `mart_kpi_events_per_day` | `COUNT(*)` sur `fct` | moyenne 29,9 (14 à 50) |
| MOVE par zone | événements de type MOVE | zone saisie | `mart_kpi_move_by_area` | `COUNT(*)` où `event_type = 'MOVE'` | Y04 : 538 |
| Volumes par navire / service | événements, conteneurs, tonnes | navire, puis service | `mart_kpi_vessel`, `mart_kpi_service` | `COUNT`, `COUNT DISTINCT`, `SUM(poids)/1000` | GULF : 2 469 (27,4 %) |
| Activité par client | événements d'un client | client | `mart_kpi_customer` | `COUNT(*)` | 91 à 136 ; 10 premiers : 14,3 % |
| Poids moyen par type | poids brut moyen | type d'événement | `mart_kpi_event_type` | `AVG(gross_weight_kg)` | 18,4 à 18,8 t |
| Part FCL / MTY | part des **événements** (et non des conteneurs) | statut | `mart_kpi_freight` | `COUNT(statut) / COUNT(*)` | 75,8 % / 24,2 % |

**Précautions.** Le KPI « MOVE par zone » compte des événements, et non les lignes de `yard_moves`. Les tonnes par service additionnent des valeurs déjà arrondies par navire. Les KPI de poids sont à lire avec l'anomalie des conteneurs vides.

**Calcul à deux endroits.** L'EDA lit le MART ; la plateforme Streamlit recalcule les KPI depuis le CORE pour permettre les filtres. Une modification de formule doit être faite aux deux endroits.
