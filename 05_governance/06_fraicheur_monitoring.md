# 06 · Fraîcheur, monitoring et incidents

## Fraîcheur — [Proposition]
| Élément | Cible |
|---|---|
| Actualisation | quotidienne, traitement de nuit |
| Disponibilité | données du jour J avant l'exploitation de J+1 |
| Publication | seulement sans contrôle FAIL |

Aucune planification n'est en place : le pipeline est lancé à la main.

## Monitoring — [Mesuré]
`etl_run_metrics` enregistre 53 étapes par exécution (5 chargements RAW, 48 étapes SQL). Il est conservé d'une exécution à l'autre.

```sql
SELECT run_id, layer, COUNT(*) AS etapes, SUM(rows_affected) AS lignes, ROUND(SUM(duration_s), 3) AS duree_s
FROM etl_run_metrics GROUP BY run_id, layer ORDER BY run_id, MIN(rowid);
```
Limite : le statut d'une étape vaut `OK` quand elle se termine ; une étape en erreur interrompt le script sans ligne d'échec dans le journal.

## Procédure en cas d'anomalie — [Proposition]
1. Lire `etl_quality_checks` (statuts autres que PASS) et `etl_rejects`.
2. Remonter à la ligne d'origine avec `raw_rowid`.
3. Utiliser le [lineage](04_lineage.md) pour lister les tables et KPI touchés.
4. Corriger à la source ou faire évoluer la règle (accord du propriétaire métier).
5. Relancer le pipeline : il est idempotent.
