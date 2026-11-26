# 01 · Rôles et responsabilités — [Proposition]

| Rôle | Responsabilités | Décide de |
|---|---|---|
| Propriétaire métier (exploitation du terminal) | sens des données et des KPI | règles métier, rattachement de Y08B, familles d'événements |
| Propriétaire technique (data engineer) | pipeline, entrepôt, archive HDFS | corrections techniques, publication |
| Responsable qualité | contrôles, rejets, réconciliation | alerte et suivi des anomalies |
| Utilisateurs métier | consultation des KPI | aucune écriture |

## Matrice RACI
R réalise · A approuve · C consulté · I informé

| Activité | Métier | Technique | Qualité | Utilisateurs |
|---|:-:|:-:|:-:|:-:|
| Définir un KPI | A | R | C | C |
| Modifier une règle de rejet | A | R | C | I |
| Traiter un contrôle en échec | I | R / A | C | I |
| Instruire les 712 mouvements de zone identique | A | C | R | I |
| Modifier une colonne source | C | A / R | C | I (après analyse d'impact) |

Aucune personne nommée n'est affectée à ces rôles dans la maquette.
