# 03 · Qualité des données

## Trois niveaux de protection
1. **Rejet** (STAGING) : 15 règles, EV01–EV09 pour les événements, MV01–MV06 pour les mouvements. La ligne écartée est inscrite dans `etl_rejects` avec son numéro de ligne RAW.
2. **Contrôle** (toutes couches) : 32 contrôles dans `etl_quality_checks` = 17 règles de l'enseignant + 15 contrôles du projet (Q01–Q15).
3. **Réconciliation** : RAW = CORE + rejets (Q09, Q10).

## Dimensions de qualité
| Dimension | Contrôles |
|---|---|
| Complétude | ROW_COUNT, NULL_RATE, Q01, Q04 |
| Unicité | DUPLICATE_CHECK, Q02, Q03 |
| Intégrité référentielle | FK_CONTAINER, FK_EQUIPMENT, Q05, Q06, Q14 |
| Validité | Q07, Q08 |
| Cohérence entre couches | Q09, Q10, Q11, Q12 |
| Cohérence métier | Q13, Q15 |

## Statuts et réaction
| Statut | Signification | Réaction — [Proposition] |
|---|---|---|
| PASS | conforme | publier |
| INFO | transformation à connaître | documenter |
| WARN | anomalie métier conservée | instruire avec le métier |
| FAIL | anomalie bloquante | ne pas publier, alerter le propriétaire technique |

Le blocage de la publication n'est **pas encore codé** : le pipeline enregistre les statuts sans s'arrêter.

## Résultats — [Mesuré]
- **30 PASS, 1 WARN, 1 INFO, 0 FAIL** ; 0 ligne rejetée.
- Q13 (WARN) : 712 mouvements (15,8 %) avec zone de départ = zone d'arrivée.
- Q15 (INFO) : 1 481 événements Y08B rattachés à Y08.
- Test des rejets : 13 lignes défectueuses injectées, 13 rejetées par la règle attendue.

## Anomalie non couverte par une règle
La distribution du poids des conteneurs vides est la même que celle des pleins (médianes : 18,6 t et 18,5 t ; Mann-Whitney p = 0,78). **[Proposition]** ajouter une règle bornant le poids d'un conteneur vide à partir de sa tare, après validation du seuil avec le métier.
