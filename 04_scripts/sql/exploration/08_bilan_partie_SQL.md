# Bilan de la partie SQL (étape 2)

- Les 5 sources sont **complètes** et leurs clés sont **uniques** : le grain est validé.
- Les données sont **cohérentes** : aucune clé orpheline, y compris entre mouvements et événements dans cette version auditée.
- Deux points d'attention sont repérés et traités dans la partie B : la zone **`Y08B`** (à rattacher ou non à Y08) et les **712 mouvements** dont la zone de départ est identique à la zone d'arrivée.
- Les valeurs sont **très homogènes** (poids, clients, équipements) : ce sera le fil conducteur de l'EDA.

Les requêtes de cette partie travaillent sur les données **brutes**. La partie B construit le pipeline qui les nettoie, les contrôle et les charge dans le Data Warehouse.
