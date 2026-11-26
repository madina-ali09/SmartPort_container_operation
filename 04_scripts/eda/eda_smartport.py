"""
SmartPort Projet 01 - Python / EDA : statistiques, graphiques et interpretation (section 9 du notebook).
Pre-requis : base 03_data/warehouse/smartport_complet.db (creee par 04_scripts/etl/etl_pipeline.py) et 03_data/raw/container_events.csv.
Usage : python eda_smartport.py      -> les 7 graphiques sont enregistres dans 06_results/figures/
"""
import os, shutil, sqlite3
import matplotlib
matplotlib.use("Agg")              # pas de fenetre : on enregistre seulement les PNG
import pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))
DB_PATH = os.path.join(HERE, "..", "..", "03_data", "warehouse", "smartport_complet.db")
CSV_PATH = os.path.join(HERE, "..", "..", "03_data", "raw", "container_events.csv")
FIG_DIR = os.path.join(HERE, "..", "..", "06_results", "figures")
pd.set_option("display.width", 200)
display = print

con = sqlite3.connect(DB_PATH)
def q(sql):
    return pd.read_sql(sql, con)

import matplotlib.pyplot as plt
import numpy as np
from scipy import stats

os.makedirs(FIG_DIR, exist_ok=True)
plt.rcParams.update({"figure.dpi": 110, "axes.spines.top": False, "axes.spines.right": False,
                     "axes.grid": True, "grid.alpha": 0.25, "font.size": 10,
                     "axes.titlesize": 11.5, "axes.titleweight": "bold"})
BLEU, ORANGE, GRIS, ROUGE, VERT = "#2E6FBA", "#E08A1E", "#8A8F98", "#C8423B", "#2F9E6E"

def sauver(nom):
    plt.tight_layout()
    plt.savefig(os.path.join(FIG_DIR, f"{nom}.png"), dpi=150, bbox_inches="tight")
    plt.show()


# ---------------------------------------------------------------- 9.1 Aperçu du jeu de données principal
df = pd.read_csv(CSV_PATH)
print(df.shape)
display(df.head())
display(df.describe(include="all").transpose())


# ---------------------------------------------------------------- 9.2 Statistiques sur l'activité quotidienne
jour = q("SELECT * FROM mart_kpi_events_per_day ORDER BY full_date")
jour["full_date"] = pd.to_datetime(jour["full_date"])
moy, ecart = jour.nb_evenements.mean(), jour.nb_evenements.std()
seuil = moy + 2 * ecart
pics = jour[jour.nb_evenements > seuil]

print(f"Jours d'activité        : {len(jour)}")
print(f"Moyenne par jour        : {moy:.1f}   écart-type : {ecart:.1f}   min : {jour.nb_evenements.min()}   max : {jour.nb_evenements.max()}")
print(f"Indice de dispersion    : {jour.nb_evenements.var() / moy:.2f}   (≈ 1 = hasard pur)")
print(f"Seuil moyenne + 2 écarts-types : {seuil:.1f}  ->  {len(pics)} jours au-dessus (environ 7 attendus par pur hasard)")
print(f"95 % des jours sont <= {jour.nb_evenements.quantile(.95):.0f} événements, 99 % sont <= {jour.nb_evenements.quantile(.99):.0f}")

# Les jours chargés sont-ils répartis au hasard dans l'année ?
dans = jour.full_date.between("2026-05-01", "2026-07-10")
n_dans = pics.full_date.between("2026-05-01", "2026-07-10").sum()
print(f"\nJours chargés entre le 1er mai et le 10 juillet : {n_dans} sur {len(pics)}  (cette période = {100 * dans.mean():.0f} % du calendrier)")
print(f"Moyenne par jour : {jour[dans].nb_evenements.mean():.1f} dans la période, {jour[~dans].nb_evenements.mean():.1f} en dehors (test t : p = {stats.ttest_ind(jour[dans].nb_evenements, jour[~dans].nb_evenements).pvalue:.3f})")
print("Attention : cette période a été choisie après avoir regardé les données, donc ce p est trop optimiste.")
mensuel = [x.nb_evenements.values for _, x in jour.groupby(jour.full_date.dt.to_period("M"))]
print(f"Comparaison des 10 mois entre eux (ANOVA) : p = {stats.f_oneway(*mensuel).pvalue:.2f}  (pas de mois significativement différent)")


# ---------------------------------------------------------------- 9.3 KPI « Nombre d'événements par jour »
fig, ax = plt.subplots(figsize=(11, 4.4))
ax.plot(jour.full_date, jour.nb_evenements, color=GRIS, lw=0.8, alpha=0.85, label="Événements par jour")
ax.plot(jour.full_date, jour.nb_evenements.rolling(7, center=True).mean(), color=BLEU, lw=2.2, label="Moyenne glissante sur 7 jours")
ax.axhline(moy, color=BLEU, ls="--", lw=1, label=f"Moyenne ({moy:.1f})")
ax.axhline(seuil, color=ROUGE, ls=":", lw=1.3, label=f"Seuil moyenne + 2 écarts-types ({seuil:.1f})")
ax.axvspan(pd.Timestamp("2026-05-01"), pd.Timestamp("2026-07-10"), color=ORANGE, alpha=0.10, label=f"1er mai - 10 juil. : {n_dans} des {len(pics)} jours chargés")
ax.scatter(pics.full_date, pics.nb_evenements, color=ROUGE, zorder=3, s=30, label=f"{len(pics)} jours au-dessus du seuil")
ax.set_title("Activité stable autour de 30 événements par jour, avec des jours chargés surtout en mai-juin")
ax.set_ylabel("Événements par jour")
ax.legend(loc="upper center", ncol=3, fontsize=8, frameon=False, bbox_to_anchor=(0.5, -0.1))
sauver("g1_evenements_par_jour")


# ---------------------------------------------------------------- 9.4 Rythme de la journée et de la semaine
heure = q("SELECT hour_key AS heure, COUNT(*) AS n FROM fact_container_event GROUP BY 1 ORDER BY 1")
jour["jour_sem"] = jour.full_date.dt.dayofweek
sem = jour.groupby("jour_sem").nb_evenements.mean()
p_h = stats.chisquare(heure.n).pvalue
p_s = stats.f_oneway(*[x.nb_evenements.values for _, x in jour.groupby("jour_sem")]).pvalue
noms = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4))
a1.bar(heure.heure, heure.n, color=BLEU)
a1.axhline(heure.n.mean(), color=ORANGE, ls="--", label=f"Moyenne ({heure.n.mean():.0f})")
a1.set_title(f"Aucune heure ne se détache (test d'uniformité p = {p_h:.2f})")
a1.set_xlabel("Heure de la journée"); a1.set_ylabel("Événements sur 10 mois"); a1.set_ylim(0, heure.n.max() * 1.15); a1.legend(frameon=False)
a2.bar(noms, sem.values, color=BLEU)
a2.axhline(sem.mean(), color=ORANGE, ls="--", label=f"Moyenne ({sem.mean():.1f})")
a2.set_title(f"Aucun jour de semaine ne se détache (p = {p_s:.2f})")
a2.set_ylabel("Événements par jour (moyenne)"); a2.set_ylim(0, sem.max() * 1.25); a2.legend(frameon=False)
sauver("g2_heure_et_semaine")


# ---------------------------------------------------------------- 9.5 KPI « MOVE par zone Yard »
zone = q("SELECT area_code, parent_area, nb_move FROM mart_kpi_move_by_area ORDER BY area_code")
base = zone[zone.area_code == zone.parent_area].set_index("parent_area").nb_move
total = zone.groupby("parent_area").nb_move.sum()
sous = (total - base.reindex(total.index)).fillna(0)
p_z = stats.chisquare(zone.nb_move).pvalue

fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.2), gridspec_kw={"width_ratios": [1.25, 1]})
a1.bar(zone.area_code, zone.nb_move, color=[ORANGE if c == "Y08B" else BLEU for c in zone.area_code])
for i, v in enumerate(zone.nb_move):
    a1.text(i, v + 6, str(v), ha="center", fontsize=9)
a1.set_title(f"Zone telle que saisie : de {zone.nb_move.min()} à {zone.nb_move.max()} MOVE")
a1.set_ylabel("Événements MOVE"); a1.set_ylim(0, zone.nb_move.max() * 1.18)
a2.bar(total.index, base.reindex(total.index), color=BLEU, label="Zone principale")
a2.bar(total.index, sous, bottom=base.reindex(total.index), color=ORANGE, label="Sous-zone Y08B rattachée")
for i, v in enumerate(total.values):
    a2.text(i, v + 12, str(v), ha="center", fontsize=9, fontweight="bold")
a2.set_title("Y08B rattachée à Y08 : Y08 paraît deux fois plus chargée")
a2.set_ylim(0, total.max() * 1.18); a2.legend(frameon=False, fontsize=8, loc="upper left")
sauver("g3_move_par_zone")
print(f"Test d'uniformité des 6 zones saisies : p = {p_z:.3f}")


# ---------------------------------------------------------------- 9.6 KPI « Volumes par navire et par service »
srv = q("SELECT * FROM mart_kpi_service ORDER BY nb_evenements DESC")
fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.2))
a1.bar(srv.service_code, srv.nb_evenements, color=BLEU)
for i, (n, nav) in enumerate(zip(srv.nb_evenements, srv.nb_navires)):
    a1.text(i, n + 30, f"{n}\n({nav} navires)", ha="center", fontsize=8.5)
a1.set_title(f"{srv.service_code.iloc[0]} domine en volume ({srv.pct_evenements.iloc[0]:.0f} % des événements)")
a1.set_ylabel("Événements"); a1.set_ylim(0, srv.nb_evenements.max() * 1.2)
a2.bar(srv.service_code, srv.evenements_par_navire, color=VERT)
for i, v in enumerate(srv.evenements_par_navire):
    a2.text(i, v + 1, f"{v:.1f}", ha="center", fontsize=9)
a2.set_title("... mais chaque navire pèse à peu près pareil")
a2.set_ylabel("Événements par navire"); a2.set_ylim(0, 95)
sauver("g4_volumes_par_service")


# ---------------------------------------------------------------- 9.7 KPI « Activité par client »
cli = q("SELECT customer_name, customer_type, nb_evenements FROM mart_kpi_customer ORDER BY nb_evenements DESC")
couleur_type = {"Importer": BLEU, "Forwarder": ORANGE, "Shipping": VERT, "Exporter": ROUGE}
top = cli.head(10).iloc[::-1]
pct_top10 = 100 * cli.nb_evenements.head(10).sum() / cli.nb_evenements.sum()

fig, ax = plt.subplots(figsize=(9, 4.6))
ax.barh(top.customer_name, top.nb_evenements, color=[couleur_type[t] for t in top.customer_type])
ax.axvline(cli.nb_evenements.mean(), color=GRIS, ls="--", label=f"Moyenne de tous les clients ({cli.nb_evenements.mean():.0f})")
for y, v in enumerate(top.nb_evenements):
    ax.text(v + 1, y, str(v), va="center", fontsize=9)
ax.set_title(f"Aucun client ne domine : le top 10 pèse {pct_top10:.0f} % de l'activité")
ax.set_xlabel("Événements"); ax.set_xlim(0, cli.nb_evenements.max() * 1.12)
handles = [plt.Rectangle((0, 0), 1, 1, color=c) for c in couleur_type.values()]
ax.legend(handles + [ax.lines[0]], list(couleur_type) + [ax.lines[0].get_label()], frameon=False, fontsize=8, ncol=5, loc="upper center", bbox_to_anchor=(0.5, -0.14))
sauver("g5_activite_par_client")
display(cli.groupby("customer_type").nb_evenements.agg(nb_clients="count", evenements="sum", moyenne_par_client="mean").round(1))


# ---------------------------------------------------------------- 9.8 KPI « Poids moyen par type d'événement »
typ = q("SELECT event_type, poids_moyen_kg FROM mart_kpi_event_type ORDER BY poids_moyen_kg DESC")
poids = q("SELECT fs.freight_status AS statut, f.gross_weight_kg AS poids FROM fact_container_event f JOIN dim_freight_status fs ON fs.freight_key = f.freight_key")
moy_globale = poids.poids.mean() / 1000

fig, (a1, a2) = plt.subplots(1, 2, figsize=(11, 4.4), gridspec_kw={"width_ratios": [1.2, 1]})
a1.bar(typ.event_type, typ.poids_moyen_kg / 1000, color=BLEU)
a1.axhline(moy_globale, color=ORANGE, ls="--", label=f"Moyenne globale ({moy_globale:.1f} t)")
for i, v in enumerate(typ.poids_moyen_kg / 1000):
    a1.text(i, v + 0.3, f"{v:.1f}", ha="center", fontsize=8.5)
a1.set_title("Poids moyen quasi identique pour tous les types")
a1.set_ylabel("Poids brut moyen (tonnes)"); a1.set_ylim(0, 26); a1.legend(frameon=False, loc="upper right")
a1.tick_params(axis="x", labelrotation=30)
a2.boxplot([poids[poids.statut == s].poids / 1000 for s in ["FCL", "MTY"]], widths=0.5, showmeans=True)
a2.set_xticks([1, 2]); a2.set_xticklabels(["FCL (plein)", "MTY (vide)"])
a2.set_title("Un conteneur vide aussi lourd qu'un plein :\nincohérence des données")
a2.set_ylabel("Poids brut (tonnes)")
sauver("g6_poids")
print("Médiane FCL :", round(poids[poids.statut == "FCL"].poids.median()), "kg | Médiane MTY :", round(poids[poids.statut == "MTY"].poids.median()), "kg")
print("Test FCL vs MTY (Mann-Whitney) : p =", round(stats.mannwhitneyu(poids[poids.statut == "FCL"].poids, poids[poids.statut == "MTY"].poids).pvalue, 3))


# ---------------------------------------------------------------- 9.9 KPI « Part FCL / MTY »
fcl = q("SELECT event_type, pct_fcl FROM mart_kpi_event_type ORDER BY pct_fcl")
glob = q("SELECT pct_evenements FROM mart_kpi_freight WHERE freight_status = 'FCL'").iloc[0, 0]
lignes = pd.concat([pd.DataFrame({"event_type": ["TOUS"], "pct_fcl": [glob]}), fcl], ignore_index=True)

fig, ax = plt.subplots(figsize=(9, 4.4))
ax.barh(lignes.event_type, lignes.pct_fcl, color=[ORANGE if t == "TOUS" else BLEU for t in lignes.event_type], label="FCL (plein)")
ax.barh(lignes.event_type, 100 - lignes.pct_fcl, left=lignes.pct_fcl, color="#D5D9DF", label="MTY (vide)")
for y, v in enumerate(lignes.pct_fcl):
    ax.text(v / 2, y, f"{v:.1f} %", va="center", ha="center", color="white", fontsize=9, fontweight="bold")
ax.set_title(f"Environ {glob:.0f} % de conteneurs pleins, quel que soit le type d'événement")
ax.set_xlabel("Part des événements (%)"); ax.set_xlim(0, 100); ax.invert_yaxis()
ax.legend(frameon=False, ncol=2, loc="upper center", bbox_to_anchor=(0.5, -0.14))
sauver("g7_part_fcl_mty")


# ---------------------------------------------------------------- 9.10 Récapitulatif des 6 KPI
recap = pd.DataFrame([
    ("Événements par jour",        "Moyenne",                   f"{moy:.1f} (min {jour.nb_evenements.min()}, max {jour.nb_evenements.max()})"),
    ("MOVE par zone Yard",         "Zone la plus chargée",      f"{zone.sort_values('nb_move').iloc[-1].area_code} : {zone.nb_move.max()} MOVE"),
    ("Volumes par service",        "Service le plus actif",     f"{srv.service_code.iloc[0]} : {srv.nb_evenements.iloc[0]} événements ({srv.pct_evenements.iloc[0]:.1f} %)"),
    ("Activité par client",        "Part du top 10",            f"{pct_top10:.1f} % de l'activité"),
    ("Poids moyen par événement",  "Moyenne globale",           f"{moy_globale:.1f} tonnes"),
    ("Part FCL / MTY",             "Part de conteneurs pleins", f"{glob:.1f} % FCL / {100 - glob:.1f} % MTY"),
], columns=["KPI", "Indicateur", "Valeur"])
recap
print(recap.to_string(index=False))

print("Figures enregistrees :", sorted(os.listdir(FIG_DIR)))
