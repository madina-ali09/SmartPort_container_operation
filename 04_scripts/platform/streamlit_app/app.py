"""
SmartPort - Plateforme analytique (Streamlit).
Interface Python qui interroge le Data Warehouse produit par le pipeline ETL
(couche CORE, base 03_data/warehouse/smartport_complet.db) et suit les operations conteneurs de bout en bout.

Lancement :  streamlit run app.py        (depuis le dossier 04_scripts/platform/streamlit_app)
Base : par defaut ../../../03_data/warehouse/smartport_complet.db ; autre chemin avec la variable SMARTPORT_DB.
"""
import os
import sqlite3
from pathlib import Path

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import streamlit as st

# ----------------------------------------------------------------------------- configuration
st.set_page_config(page_title="SmartPort Plateforme", page_icon=":material/directions_boat:", layout="wide")

HERE = Path(__file__).resolve().parent
DB_PATH = Path(os.environ.get("SMARTPORT_DB", HERE / ".." / ".." / ".." / "03_data" / "warehouse" / "smartport_complet.db")).resolve()
S1, S2 = "#2a78d6", "#eb6834"          # bleu = identite principale, orange = second signal (MTY, pics)
JOURS = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

# Preuve des regles de rejet : resultat de 04_scripts/etl/test_rejets.py (13 erreurs injectees dans une copie des CSV)
PREUVE_REJETS = pd.DataFrame(
    [("EV02", "event_id en double", 1), ("EV03", "date d'événement illisible", 1), ("EV04", "type d'événement hors domaine", 1),
     ("EV05", "statut hors FCL/MTY", 1), ("EV06", "poids hors 0..40 000 kg", 2), ("EV07", "client inconnu", 1),
     ("EV08", "navire inconnu", 1), ("EV09", "zone manquante", 1), ("MV02", "move_id en double", 1),
     ("MV03", "date de mouvement illisible", 1), ("MV04", "équipement inconnu", 1), ("MV06", "conteneur inconnu", 1)],
    columns=["Règle", "Erreur injectée", "Rejetée"])

if not DB_PATH.exists():
    st.error(f"Base introuvable : {DB_PATH}\n\nLancez d'abord le pipeline : `python 04_scripts/etl/etl_pipeline.py`, "
             "ou indiquez la base avec la variable d'environnement SMARTPORT_DB.")
    st.stop()


def fmt(n, d=0):
    return f"{n:,.{d}f}".replace(",", " ").replace(".", ",")


# ----------------------------------------------------------------------------- donnees (Data Warehouse)
@st.cache_data(show_spinner="Lecture du Data Warehouse…")
def charger(db: str):
    con = sqlite3.connect(db)
    q = lambda sql: pd.read_sql(sql, con)
    ev = q("""
        SELECT e.event_id, e.container_id, d.full_date AS date, e.hour_key AS heure,
               c.customer_name AS client, c.customer_type AS type_client, c.group_code AS groupe,
               v.vessel_name AS navire, v.vessel_type AS type_navire, v.service_code AS service,
               a.area_code AS zone, t.event_type AS type_evenement, f.freight_status AS statut, e.gross_weight_kg AS poids_kg
        FROM fact_container_event e
        JOIN dim_date d ON d.date_key = e.date_key
        JOIN dim_customer c ON c.customer_key = e.customer_key
        JOIN dim_vessel v ON v.vessel_key = e.vessel_key
        JOIN dim_yard_area a ON a.area_key = e.area_key
        JOIN dim_event_type t ON t.event_type_key = e.event_type_key
        JOIN dim_freight_status f ON f.freight_key = e.freight_key""")
    mv = q("""
        SELECT m.move_id, m.container_id, d.full_date AS date, m.hour_key AS heure, fa.area_code AS depart, ta.area_code AS arrivee,
               q.equipment_id AS engin, q.equipment_type AS type_engin, m.is_same_area AS meme_zone
        FROM fact_yard_move m
        JOIN dim_date d ON d.date_key = m.date_key
        JOIN dim_yard_area fa ON fa.area_key = m.from_area_key
        JOIN dim_yard_area ta ON ta.area_key = m.to_area_key
        JOIN dim_equipment q ON q.equipment_key = m.equipment_key""")
    ev["date"] = pd.to_datetime(ev["date"])
    mv["date"] = pd.to_datetime(mv["date"])
    dims = {
        "clients": q("SELECT customer_name AS client, customer_type AS type_client, group_code AS groupe FROM dim_customer"),
        "navires": q("SELECT vessel_name AS navire, vessel_type AS type_navire, service_code AS service FROM dim_vessel"),
        "engins": q("SELECT equipment_id AS engin, equipment_type AS type_engin, home_area AS zone_base FROM dim_equipment"),
        "zones": q("SELECT area_code FROM dim_yard_area ORDER BY area_key")["area_code"].tolist(),
        "types_evt": q("SELECT event_type FROM dim_event_type ORDER BY event_type_key")["event_type"].tolist(),
    }
    qualite = {
        "checks": q("SELECT check_id AS controle, layer AS couche, description, observed AS observé, expected AS attendu, status AS statut FROM etl_quality_checks"),
        "recon": q("""SELECT 'container_events' AS source, (SELECT COUNT(*) FROM raw_container_events) AS raw, (SELECT COUNT(*) FROM fact_container_event) AS chargé,
                      (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='container_events') AS rejeté
                      UNION ALL SELECT 'yard_moves', (SELECT COUNT(*) FROM raw_yard_moves), (SELECT COUNT(*) FROM fact_yard_move),
                      (SELECT COUNT(DISTINCT raw_rowid) FROM etl_rejects WHERE source_table='yard_moves')"""),
    }
    qualite["recon"]["écart"] = qualite["recon"]["raw"] - qualite["recon"]["chargé"] - qualite["recon"]["rejeté"]
    last = q("SELECT MAX(run_id) AS r FROM etl_run_metrics")["r"][0]
    qualite["run_id"] = last
    qualite["nruns"] = int(q("SELECT COUNT(DISTINCT run_id) AS n FROM etl_run_metrics")["n"][0])
    qualite["metrics"] = q(f"""SELECT layer AS couche, COUNT(*) AS étapes, SUM(rows_affected) AS lignes, ROUND(SUM(duration_s)*1000, 1) AS durée_ms
                               FROM etl_run_metrics WHERE run_id = '{last}' GROUP BY layer ORDER BY MIN(logged_at)""")

    def nb(prefix):
        names = q(f"SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '{prefix}%' ORDER BY name")["name"]
        return [(n, int(con.execute(f"SELECT COUNT(*) FROM {n}").fetchone()[0])) for n in names]
    qualite["lineage"] = {
        "Sources": [(n, int(con.execute(f"SELECT COUNT(*) FROM raw_{n}").fetchone()[0])) for n in
                    ["customers", "vessel_calls", "container_events", "yard_moves", "equipment"]],   # = lignes des CSV (RAW est une copie)
        "RAW": nb("raw_"), "STAGING": nb("stg_") + [("etl_rejects", int(con.execute("SELECT COUNT(*) FROM etl_rejects").fetchone()[0]))],
        "CORE": nb("fact_") + nb("dim_"), "MART": nb("mart_"),
    }
    con.close()
    return ev, mv, dims, qualite


EV, MV, DIMS, QUAL = charger(str(DB_PATH))
DMIN, DMAX = EV["date"].min().date(), EV["date"].max().date()

# ----------------------------------------------------------------------------- filtres (barre laterale)
FILTRES = {"f_dates": (DMIN, DMAX), "f_ctype": [], "f_service": [], "f_etype": [], "f_zone": []}
for k, v in FILTRES.items():
    st.session_state.setdefault(k, v)


def reinitialiser():
    for k, v in FILTRES.items():
        st.session_state[k] = v


with st.sidebar:
    st.header("Filtres")
    st.date_input("Période", min_value=DMIN, max_value=DMAX, key="f_dates", format="DD/MM/YYYY")
    st.multiselect("Type de client", sorted(DIMS["clients"]["type_client"].unique()), key="f_ctype", placeholder="Tous")
    st.multiselect("Service", sorted(DIMS["navires"]["service"].unique()), key="f_service", placeholder="Tous")
    st.multiselect("Type d'événement", DIMS["types_evt"], key="f_etype", placeholder="Tous")
    st.multiselect("Zone", DIMS["zones"], key="f_zone", placeholder="Toutes")
    st.button("Réinitialiser", on_click=reinitialiser, width="stretch")

dates = st.session_state["f_dates"]
if not isinstance(dates, (tuple, list)) or len(dates) < 2:
    st.info("Choisissez une date de fin pour la période.")
    st.stop()
d0, d1 = pd.Timestamp(dates[0]), pd.Timestamp(dates[1])
ndays = (d1 - d0).days + 1

ev = EV[(EV["date"] >= d0) & (EV["date"] <= d1)]
mv = MV[(MV["date"] >= d0) & (MV["date"] <= d1)]
if st.session_state["f_ctype"]:
    ev = ev[ev["type_client"].isin(st.session_state["f_ctype"])]
if st.session_state["f_service"]:
    ev = ev[ev["service"].isin(st.session_state["f_service"])]
if st.session_state["f_etype"]:
    ev = ev[ev["type_evenement"].isin(st.session_state["f_etype"])]
if st.session_state["f_zone"]:
    ev = ev[ev["zone"].isin(st.session_state["f_zone"])]
    mv = mv[mv["depart"].isin(st.session_state["f_zone"]) | mv["arrivee"].isin(st.session_state["f_zone"])]

with st.sidebar:
    st.caption(f"{fmt(len(ev))} / {fmt(len(EV))} événements · {fmt(len(mv))} / {fmt(len(MV))} mouvements")
    st.download_button("Exporter les événements filtrés (CSV)", ev.to_csv(index=False).encode("utf-8"),
                       file_name="smartport_evenements_filtres.csv", mime="text/csv", width="stretch",
                       disabled=ev.empty)

# ----------------------------------------------------------------------------- en-tete
st.title("SmartPort · Plateforme analytique")
st.caption(f"Terminal conteneurs · {EV['date'].min():%d/%m/%Y} au {EV['date'].max():%d/%m/%Y} · {fmt(len(EV))} événements · "
           f"{fmt(len(MV))} mouvements de cour · source : Data Warehouse (couche CORE)")


def barres(df, x, y, titre_x="", fmt_txt=":,.0f", couleur=S1, hover=None, xmax=None):
    """barres horizontales triees, valeur au bout de la barre"""
    df = df.sort_values(x)
    fig = px.bar(df, x=x, y=y, orientation="h", text=x, hover_data=hover)
    fig.update_traces(marker_color=couleur, texttemplate="%{text" + fmt_txt + "}", textposition="outside", cliponaxis=False)
    fig.update_layout(height=max(220, 38 * len(df) + 60), margin=dict(l=0, r=30, t=10, b=0), xaxis_title=titre_x, yaxis_title="",
                      xaxis_range=[0, xmax] if xmax else None)
    fig.update_yaxes(type="category")
    return fig


def graphique(fig, **kw):
    st.plotly_chart(fig, width="stretch", config={"displayModeBar": False}, **kw)


def vide(msg="Aucune donnée pour ces filtres."):
    st.info(msg)


def carte_kpi(col, label, valeur, sous):
    with col, st.container(border=True):
        st.metric(label, valeur)
        st.caption(sous)


tab1, tab2, tab3, tab4 = st.tabs(["Synthèse", "Cour et équipements", "Clients et navires", "Qualité et lineage"])

# ============================================================================= SYNTHESE
with tab1:
    if ev.empty:
        vide()
    else:
        N = len(ev)
        par_jour = ev.groupby("date").size().reindex(pd.date_range(d0, d1), fill_value=0)
        move_zone = ev[ev["type_evenement"] == "MOVE"].groupby("zone").size()
        svc = ev.groupby("service").size().sort_values(ascending=False)
        cli = ev.groupby("client").size().sort_values(ascending=False)
        poids_type = ev.groupby("type_evenement")["poids_kg"].mean() / 1000
        fcl = (ev["statut"] == "FCL").mean() * 100
        pic = par_jour.idxmax()
        cols = st.columns(6)
        carte_kpi(cols[0], "Événements par jour", fmt(N / ndays, 1), f"Maximum {par_jour.max()} le {pic:%d/%m}")
        carte_kpi(cols[1], "MOVE par zone", move_zone.idxmax() if len(move_zone) else "–",
                  f"{fmt(move_zone.max())} MOVE sur {fmt(move_zone.sum())}" if len(move_zone) else "Aucun MOVE")
        carte_kpi(cols[2], "Volumes par service", svc.index[0], f"{fmt(svc.iloc[0])} événements ({fmt(svc.iloc[0] / N * 100, 1)} %)")
        carte_kpi(cols[3], "Activité par client", cli.index[0].replace("Customer_", "C-"),
                  f"{cli.index[0].replace('Customer_', 'Client ')} : {cli.iloc[0]} événements · top 10 = {fmt(cli.head(10).sum() / N * 100, 1)} %")
        carte_kpi(cols[4], "Poids moyen (t)", fmt(ev["poids_kg"].mean() / 1000, 1),
                  f"de {fmt(poids_type.min(), 1)} à {fmt(poids_type.max(), 1)} t selon le type")
        carte_kpi(cols[5], "Part FCL (plein)", f"{fmt(fcl, 1)} %", f"{fmt(100 - fcl, 1)} % MTY (vide)")

        # --- courbe quotidienne
        with st.container(border=True):
            st.subheader("Événements par jour")
            st.caption("Un point par jour du calendrier. Les jours au-dessus de la moyenne + 2 écarts-types sont signalés.")
            moy, seuil = par_jour.mean(), par_jour.mean() + 2 * par_jour.std(ddof=1)
            ma = par_jour.rolling(7, center=True).mean()
            pics = par_jour[par_jour > seuil] if len(par_jour) > 1 else par_jour.iloc[0:0]
            fig = go.Figure()
            fig.add_trace(go.Scatter(x=par_jour.index, y=par_jour.values, name="Par jour", mode="lines", line=dict(color=S1, width=1), opacity=.4))
            fig.add_trace(go.Scatter(x=ma.index, y=ma.values, name="Moyenne sur 7 jours", mode="lines", line=dict(color=S1, width=3)))
            fig.add_trace(go.Scatter(x=pics.index, y=pics.values, name="Jour de pic", mode="markers", marker=dict(color=S2, size=9, line=dict(color="white", width=1.5))))
            fig.add_hline(y=moy, line_dash="dash", line_color="gray", annotation_text=f"moy. {fmt(moy, 1)}", annotation_position="right")
            fig.add_hline(y=seuil, line_dash="dot", line_color=S2, annotation_text=f"seuil {fmt(seuil, 1)}", annotation_position="right")
            fig.update_layout(height=340, hovermode="x unified", margin=dict(l=0, r=70, t=10, b=0), yaxis_title="Événements",
                              yaxis_rangemode="tozero", legend=dict(orientation="h", y=1.12, x=0))
            graphique(fig)
            if len(pics):
                st.caption(f"{len(pics)} jours de pic : " + ", ".join(f"{d:%d/%m} ({v})" for d, v in pics.items()))

        c1, c2 = st.columns(2)
        with c1, st.container(border=True):
            st.subheader("MOVE par zone Yard")
            st.caption("Événements de type MOVE, par zone d'enregistrement. Y08B est une sous-zone de Y08 : elle est comptée à part, comme dans le Data Warehouse.")
            if len(move_zone):
                graphique(barres(move_zone.rename("MOVE").reset_index().rename(columns={"zone": "Zone"}), "MOVE", "Zone"))
            else:
                vide("Aucun événement MOVE.")
        with c2, st.container(border=True):
            st.subheader("Volumes par service")
            st.caption("Nombre d'événements par service maritime.")
            graphique(barres(svc.rename("Événements").reset_index().rename(columns={"service": "Service"}), "Événements", "Service"))
        c3, c4 = st.columns(2)
        with c3, st.container(border=True):
            st.subheader("Poids moyen par type d'événement")
            st.caption("En tonnes brutes par conteneur.")
            graphique(barres(poids_type.rename("Tonnes").reset_index().rename(columns={"type_evenement": "Type"}), "Tonnes", "Type",
                             fmt_txt=":,.1f", xmax=max(25, float(poids_type.max()))))
        with c4, st.container(border=True):
            st.subheader("Part FCL / MTY par type d'événement")
            st.caption("FCL = conteneur plein, MTY = conteneur vide.")
            ct = pd.crosstab(ev["type_evenement"], ev["statut"]).reindex(columns=["FCL", "MTY"], fill_value=0)
            pct = ct.div(ct.sum(axis=1), axis=0) * 100
            pct = pct.sort_values("FCL")
            fig = go.Figure()
            fig.add_trace(go.Bar(y=pct.index, x=pct["FCL"], orientation="h", name="FCL (plein)", marker_color=S1,
                                 text=[f"{fmt(v, 1)} %" for v in pct["FCL"]], textposition="inside", insidetextanchor="start",
                                 textfont_color="white"))
            fig.add_trace(go.Bar(y=pct.index, x=pct["MTY"], orientation="h", name="MTY (vide)", marker_color=S2))
            fig.update_layout(barmode="stack", height=max(220, 38 * len(pct) + 80), margin=dict(l=0, r=0, t=10, b=0),
                              xaxis=dict(range=[0, 100], title="% des événements"), legend=dict(orientation="h", y=1.15, x=0))
            fig.update_yaxes(type="category")
            graphique(fig)

# ============================================================================= COUR
with tab2:
    st.caption("Les filtres Client, Service et Type d'événement ne s'appliquent pas aux mouvements de cour. "
               "La zone retient les mouvements dont le départ ou l'arrivée est dans la zone.")
    if mv.empty:
        vide("Aucun mouvement ne correspond aux filtres.")
    else:
        nm = len(mv)
        mem = int(mv["meme_zone"].sum())
        par_engin = mv.groupby("engin").size()
        engin_top = par_engin.idxmax()
        heures = ev.groupby("heure").size() if len(ev) else pd.Series(dtype=int)
        cols = st.columns(4)
        carte_kpi(cols[0], "Mouvements de cour", fmt(nm), f"{fmt(nm / ndays, 1)} par jour")
        carte_kpi(cols[1], "Départ = arrivée", f"{fmt(mem / nm * 100, 1)} %", f"{fmt(mem)} mouvements à vérifier")
        carte_kpi(cols[2], "Engin le plus sollicité", engin_top,
                  f"{mv.loc[mv['engin'] == engin_top, 'type_engin'].iloc[0]} · {par_engin.max()} mouvements")
        carte_kpi(cols[3], "Heure la plus chargée", f"{heures.idxmax()} h" if len(heures) else "–",
                  f"{fmt(heures.max())} événements" if len(heures) else "")

        with st.container(border=True):
            st.subheader("Rythme de la journée")
            st.caption("Événements conteneurs par jour de semaine et par heure.")
            if ev.empty:
                vide()
            else:
                g = (ev.assign(jour=ev["date"].dt.dayofweek).groupby(["jour", "heure"]).size().unstack(fill_value=0)
                       .reindex(index=range(7), columns=range(24), fill_value=0))
                fig = go.Figure(go.Heatmap(z=g.values, x=[f"{h} h" for h in g.columns], y=JOURS, colorscale="Blues",
                                           xgap=2, ygap=2, colorbar=dict(title="Événements"),
                                           hovertemplate="%{y} %{x}<br>%{z} événements<extra></extra>"))
                fig.update_yaxes(autorange="reversed")
                fig.update_layout(height=330, margin=dict(l=0, r=0, t=10, b=0))
                graphique(fig)

        c1, c2 = st.columns(2)
        with c1, st.container(border=True):
            st.subheader("Flux entre zones")
            st.caption("Mouvements de cour : zone de départ (ligne) vers zone d'arrivée (colonne). Les cases encadrées : départ = arrivée.")
            zs = DIMS["zones"]
            m = pd.crosstab(mv["depart"], mv["arrivee"]).reindex(index=zs, columns=zs, fill_value=0)
            fig = go.Figure(go.Heatmap(z=m.values, x=zs, y=zs, colorscale="Blues", xgap=2, ygap=2, text=m.values, texttemplate="%{text}",
                                       showscale=False, hovertemplate="%{y} → %{x}<br>%{z} mouvements<extra></extra>"))
            for i in range(len(zs)):
                fig.add_shape(type="rect", x0=i - .5, x1=i + .5, y0=i - .5, y1=i + .5, line=dict(color=S2, width=2, dash="dot"))
            fig.update_yaxes(autorange="reversed", title="Départ")
            fig.update_xaxes(side="top", title="Arrivée")
            fig.update_layout(height=400, margin=dict(l=0, r=0, t=40, b=0))
            graphique(fig)
        with c2, st.container(border=True):
            st.subheader("Charge par type d'engin")
            st.caption("Mouvements par engin, en moyenne sur chaque type.")
            eq = DIMS["engins"].merge(par_engin.rename("mouvements"), left_on="engin", right_index=True, how="left").fillna({"mouvements": 0})
            t = eq.groupby("type_engin").agg(engins=("engin", "count"), total=("mouvements", "sum"))
            t["moy"] = t["total"] / t["engins"]
            t = t.reset_index()
            t["Type"] = t["type_engin"] + " (" + t["engins"].astype(str) + " engins)"
            graphique(barres(t.rename(columns={"moy": "Mouvements par engin"}), "Mouvements par engin", "Type", fmt_txt=":,.1f"))

        with st.container(border=True):
            st.subheader("Engins")
            st.caption("Charge de chaque engin sur la période. Cliquer sur un en-tête trie le tableau.")
            tab = eq.assign(part=lambda d: d["mouvements"] / nm * 100).rename(
                columns={"engin": "Engin", "type_engin": "Type", "zone_base": "Zone de base", "mouvements": "Mouvements", "part": "Part (%)"})
            st.dataframe(tab.sort_values("Mouvements", ascending=False), hide_index=True, width="stretch", height=380,
                         column_config={"Mouvements": st.column_config.ProgressColumn("Mouvements", format="%d", min_value=0, max_value=int(tab["Mouvements"].max()) or 1),
                                        "Part (%)": st.column_config.NumberColumn(format="%.1f %%")})

# ============================================================================= CLIENTS ET NAVIRES
with tab3:
    if ev.empty:
        vide()
    else:
        N = len(ev)
        cl = DIMS["clients"].merge(ev.groupby("client").agg(evenements=("event_id", "count"), conteneurs=("container_id", "nunique"),
                                                          tonnes=("poids_kg", lambda s: s.sum() / 1000),
                                                          pct_fcl=("statut", lambda s: (s == "FCL").mean() * 100)),
                                   left_on="client", right_index=True, how="left").fillna({"evenements": 0, "conteneurs": 0, "tonnes": 0, "pct_fcl": 0})
        nv = DIMS["navires"].merge(ev.groupby("navire").agg(evenements=("event_id", "count"), conteneurs=("container_id", "nunique"),
                                                          tonnes=("poids_kg", lambda s: s.sum() / 1000)),
                                   left_on="navire", right_index=True, how="left").fillna({"evenements": 0, "conteneurs": 0, "tonnes": 0})
        c1, c2 = st.columns(2)
        with c1, st.container(border=True):
            st.subheader("Les 10 clients les plus actifs")
            st.caption("Nombre d'événements.")
            top = cl.sort_values("evenements", ascending=False).head(10)
            graphique(barres(top.rename(columns={"client": "Client", "evenements": "Événements"}), "Événements", "Client",
                             hover=["type_client", "groupe"]))
        with c2, st.container(border=True):
            st.subheader("Concentration de l'activité")
            st.caption("Part cumulée de l'activité, clients classés du plus au moins actif. La diagonale = activité répartie à l'identique.")
            act = cl["evenements"][cl["evenements"] > 0].sort_values(ascending=False).to_numpy()
            if len(act) > 1:
                cum = act.cumsum() / act.sum() * 100
                x = [0] + [(i + 1) / len(act) * 100 for i in range(len(act))]
                fig = go.Figure()
                fig.add_trace(go.Scatter(x=[0, 100], y=[0, 100], mode="lines", name="Répartition égale", line=dict(color="gray", dash="dash")))
                fig.add_trace(go.Scatter(x=x, y=[0, *cum], mode="lines", name="Activité réelle", line=dict(color=S1, width=3),
                                         hovertemplate="%{x:.0f} % des clients → %{y:.1f} % de l'activité<extra></extra>"))
                fig.update_layout(height=max(260, 38 * 10 + 60), margin=dict(l=0, r=0, t=10, b=0), xaxis_title="% des clients (du plus actif au moins actif)",
                                  yaxis_title="% cumulé de l'activité", legend=dict(orientation="h", y=1.12, x=0))
                graphique(fig)
                moitie = int((cum < 50).sum()) + 1
                st.caption(f"Les 10 premiers clients font {fmt(act[:10].sum() / N * 100, 1)} % de l'activité ; il faut {moitie} clients sur {len(act)} pour atteindre la moitié.")
        c3, c4 = st.columns(2)
        with c3, st.container(border=True):
            st.subheader("Activité par type de client")
            st.caption("Événements par client en moyenne, pour chaque type.")
            g = cl.groupby("type_client")["evenements"].mean().rename("Événements par client").reset_index().rename(columns={"type_client": "Type"})
            graphique(barres(g, "Événements par client", "Type", fmt_txt=":,.1f"))
        with c4, st.container(border=True):
            st.subheader("Activité par type de navire")
            st.caption("Événements par navire en moyenne, pour chaque type.")
            g = nv.groupby("type_navire")["evenements"].mean().rename("Événements par navire").reset_index().rename(columns={"type_navire": "Type"})
            graphique(barres(g, "Événements par navire", "Type", fmt_txt=":,.1f"))

        def tableau(df, titre, cle, config):
            with st.container(border=True):
                st.subheader(titre)
                rech = st.text_input("Rechercher", key=cle, placeholder="Nom, type, groupe…", label_visibility="collapsed")
                if rech:
                    df = df[df.apply(lambda r: rech.lower() in " ".join(map(str, r.values)).lower(), axis=1)]
                st.dataframe(df.sort_values("evenements", ascending=False), hide_index=True, width="stretch", height=380, column_config=config)
        mx = lambda d: max(1, int(d["evenements"].max()))
        tableau(cl, "Clients", "r_cli", {
            "client": "Client", "type_client": "Type", "groupe": "Groupe",
            "evenements": st.column_config.ProgressColumn("Événements", format="%d", min_value=0, max_value=mx(cl)),
            "conteneurs": st.column_config.NumberColumn("Conteneurs", format="%d"),
            "tonnes": st.column_config.NumberColumn("Tonnes", format="%.1f"), "pct_fcl": st.column_config.NumberColumn("% FCL", format="%.1f")})
        tableau(nv, "Navires", "r_nav", {
            "navire": "Navire", "type_navire": "Type", "service": "Service",
            "evenements": st.column_config.ProgressColumn("Événements", format="%d", min_value=0, max_value=mx(nv)),
            "conteneurs": st.column_config.NumberColumn("Conteneurs", format="%d"),
            "tonnes": st.column_config.NumberColumn("Tonnes", format="%.1f")})

# ============================================================================= QUALITE ET LINEAGE
with tab4:
    st.caption("Cette vue décrit le dernier run du pipeline ETL : elle ne dépend pas des filtres.")
    with st.container(border=True):
        st.subheader("Lineage : de la source au KPI")
        st.caption("Flux principal : Sources → RAW → STAGING → CORE → MART. HDFS archive container_events ; le script ingestion_depuis_hdfs.py permet de charger RAW depuis cette archive. Cette plateforme calcule ses KPI depuis le CORE ; le MART alimente l'EDA. Nombre de lignes de chaque couche.")
        L = QUAL["lineage"]
        etapes = [("Sources", "5 fichiers CSV", L["Sources"]),
                  ("HDFS", "Archive de la source", [("container_events.csv", dict(L["Sources"])["container_events"])]),
                  ("RAW", "Copie brute, texte", [(n.replace("raw_", ""), v) for n, v in L["RAW"]]),
                  ("STAGING", "Typage, nettoyage, rejets", [(n.replace("stg_", ""), v) for n, v in L["STAGING"]]),
                  ("CORE", "Étoile : dimensions et faits",
                   [(n, v) for n, v in L["CORE"] if n.startswith("fact")] + [(f"{sum(n.startswith('dim') for n, _ in L['CORE'])} dimensions", sum(v for n, v in L["CORE"] if n.startswith("dim")))]),
                  ("MART", "Une table par KPI", [(n.replace("mart_kpi_", ""), v) for n, v in L["MART"]]),
                  ("Usages", "Cette plateforme, EDA Python", [("6 KPI du sujet", None)])]
        for rang in (etapes[:4], etapes[4:]):
            for col, (titre, desc, items) in zip(st.columns(len(rang)), rang):
                with col, st.container(border=True):
                    st.markdown(f"**{titre}**")
                    st.caption(desc)
                    st.markdown("\n".join(f"- `{n}` : {fmt(v) if v is not None else ''}".rstrip(" :") for n, v in items))

    c1, c2 = st.columns(2)
    with c1, st.container(border=True):
        st.subheader("Réconciliation des volumes")
        st.caption("Chaque ligne brute est soit chargée, soit rejetée : l'écart doit être 0.")
        st.dataframe(QUAL["recon"], hide_index=True, width="stretch")
    with c2, st.container(border=True):
        st.subheader("Les règles de rejet fonctionnent")
        st.caption("13 erreurs injectées volontairement dans une copie des données : toutes sont rejetées par la bonne règle.")
        st.dataframe(PREUVE_REJETS, hide_index=True, width="stretch", height=250)

    with st.container(border=True):
        st.subheader("Contrôles qualité")
        st.caption("15 contrôles du pipeline et les 17 règles du prof, calculés à chaque exécution.")
        ck = QUAL["checks"].copy()
        icones = {"PASS": "✓ PASS", "WARN": "▲ WARN", "INFO": "i INFO", "FAIL": "✕ FAIL"}
        cnt = ck["statut"].value_counts()
        choix = st.segmented_control("Statut", ["Tous"] + [f"{icones[s]} ({n})" for s, n in cnt.items()], default="Tous",
                                     label_visibility="collapsed")
        if choix and choix != "Tous":
            ck = ck[ck["statut"] == choix.split(" ")[1]]
        ck["statut"] = ck["statut"].map(icones)
        st.dataframe(ck, hide_index=True, width="stretch", height=380)

    c3, c4 = st.columns(2)
    with c3, st.container(border=True):
        st.subheader("Monitoring du dernier run")
        st.caption(f"Run {QUAL['run_id']} · {QUAL['nruns']} exécutions au journal etl_run_metrics (idempotence : mêmes résultats à chaque run).")
        mt = QUAL["metrics"]
        fig = px.bar(mt, x="durée_ms", y="couche", orientation="h", text="durée_ms")
        fig.update_traces(marker_color=S1, texttemplate="%{text:.1f} ms", textposition="outside", cliponaxis=False)
        fig.update_yaxes(autorange="reversed", title="")
        fig.update_layout(height=260, margin=dict(l=0, r=40, t=10, b=0), xaxis_title="Durée (ms)")
        graphique(fig)
    with c4, st.container(border=True):
        st.subheader("Modèle en étoile")
        st.caption("Grain et dimensions du Data Warehouse.")
        st.markdown("**fact_container_event** : 1 ligne = 1 événement conteneur.  \n"
                    "Dimensions : date, heure, client, navire, zone, type d'événement, statut FCL/MTY. Mesures : nombre d'événements, poids brut.")
        st.markdown("**fact_yard_move** : 1 ligne = 1 mouvement de cour.  \n"
                    "Dimensions : date, heure, zone de départ, zone d'arrivée, engin. Mesure : nombre de mouvements.")
