-- =============================================================================================
-- ETAPE 2 / A.3 : CTE ET SOUS-REQUETES
-- =============================================================================================
-- Consigne du prof (TODO 4) : au moins une CTE (clause WITH).
-- Mode d'emploi DB Browser : onglet 'Executer le SQL'. Selectionner UNE requete (de WITH/SELECT
-- jusqu'au ';') puis F5 / Ctrl+Entree (execute la selection). Si rien n'est selectionne, tout le
-- fichier est execute et seul le dernier resultat s'affiche.
-- =============================================================================================


-- ---------------------------------------------------------------------------------------------
-- REQUETE 8 : CTE : top 5 clients par activite avec leur part du total
-- ---------------------------------------------------------------------------------------------
WITH activite AS (
    SELECT customer_id, COUNT(*) AS nb_evenements,
           SUM(gross_weight_kg) AS poids_total
    FROM container_events
    GROUP BY customer_id
), total AS (SELECT SUM(nb_evenements) AS t FROM activite)
SELECT c.customer_name, c.customer_type, a.nb_evenements,
       ROUND(100.0*a.nb_evenements/t.t,2) AS pct_total
FROM activite a
JOIN customers c ON c.customer_id = a.customer_id
CROSS JOIN total t
ORDER BY a.nb_evenements DESC
LIMIT 5;

-- RESULTAT / LECTURE : Le premier client ne représente que 1,51 % de l'activité : aucune
-- dépendance à un gros client.

-- ---------------------------------------------------------------------------------------------
-- REQUETE 9 : Sous-requete : jours dont l'activite depasse moyenne + 2 ecarts-types (pics)
-- ---------------------------------------------------------------------------------------------
-- NOTE : Version adaptee pour DB Browser : le notebook utilise SQRT(variance), fonction absente de
-- certaines versions de SQLite. Ici on compare (n - moyenne)^2 a 4 x variance, ce qui est
-- mathematiquement identique a n > moyenne + 2 x ecart-type.
WITH par_jour AS (
    SELECT DATE(event_ts) AS jour, COUNT(*) AS n
    FROM container_events
    GROUP BY 1
), stats AS (
    SELECT AVG(n) AS moy,
           AVG(n*n) - AVG(n)*AVG(n) AS variance      -- variance = E[n^2] - E[n]^2
    FROM par_jour
)
SELECT p.jour, p.n, ROUND(s.moy,1) AS moyenne
FROM par_jour p, stats s
WHERE p.n > s.moy
  AND (p.n - s.moy)*(p.n - s.moy) > 4*s.variance     -- equivaut a n > moyenne + 2 ecarts-types
ORDER BY p.n DESC;

-- RESULTAT / LECTURE : 9 jours dépassent la moyenne + 2 écarts-types (environ 41 événements). 7
-- d'entre eux tombent entre début mai et début juillet : cette observation est discutée dans l'EDA
-- (partie B, section 9).
