# 02 · Classification, sécurité et accès

Les données du projet sont **synthétiques** : aucune donnée personnelle réelle. La classification ci-dessous s'appliquerait à des données réelles.

## Classification — [Proposition]
Trois niveaux : **Public**, **Interne**, **Confidentiel**.

| Objet | Classe | Raison |
|---|---|---|
| `customers.csv`, `raw_customers`, `stg_customers`, `dim_customer` | Confidentiel | information commerciale |
| `mart_kpi_customer` | Confidentiel | **contient le nom et l'activité de chaque client** : ce n'est pas un agrégat anonyme |
| Événements, mouvements, escales, équipements et tables dérivées | Interne | données d'exploitation |
| Autres tables du MART | Interne | agrégats sans client |
| Aucun jeu à ce stade | Public | une diffusion externe demanderait l'accord du propriétaire métier sur des agrégats sans client |

La classe suit la donnée le long du [lineage](04_lineage.md) : toute table qui reprend le nom d'un client reste confidentielle.

## Accès (moindre privilège) — [Proposition]
| Couche | Pipeline | Data engineer | Analyste | Utilisateur métier |
|---|---|---|---|---|
| CSV et archive HDFS | écriture | lecture | — | — |
| RAW, STAGING, rejets | écriture | lecture | — | — |
| CORE | écriture | lecture | lecture | — |
| MART et plateforme | écriture | lecture | lecture | lecture (`mart_kpi_customer` : habilitation) |

Aucun humain ne modifie les couches à la main. La plateforme Streamlit lit le CORE : en production, elle utiliserait un compte de service en lecture seule et authentifierait ses utilisateurs.

## État réel de la maquette — [Mesuré]
- Fichier HDFS en `-rw-r--r--` (propriétaire `hadoop`, groupe `supergroup`) : lisible par tous.
- Base SQLite : aucun contrôle d'accès interne.
- Plateforme : sans authentification.

La matrice d'accès n'est donc **pas appliquée** techniquement.

## À mettre en place avant des données réelles — [Proposition]
Pseudonymiser les clients dès le CORE, chiffrer l'archive, restreindre les permissions HDFS, journaliser les accès, fixer une durée de conservation.
