"""Schéma de lineage au niveau table, généré à partir de la description vérifiée de lineage.py.
Usage : python diagramme.py  -> 06_results/figures/lineage_tables.png et .svg (nécessite Graphviz : commande `dot`)."""
import os, subprocess
import lineage as L

OUT = os.path.join(L.ROOT, "06_results", "figures", "lineage_tables")
COUL = {"CSV": "#E8EBF0", "RAW": "#FCEBD5", "STAGING": "#FFF5CC", "CORE": "#D9E8FA", "MART": "#DCF2E3", "USAGE": "#EDE3F7"}

noeuds = {c: [] for c in COUL}
aretes = set()
for t, cols in L.M.items():
    noeuds[L.LAYER[t.split("_")[0]]].append(t)
    for srcs, _ in cols.values():
        for s in srcs:
            if s == L.GEN:
                continue
            if ".csv." in s:
                aretes.add((s.split(".csv.")[0] + ".csv", t))
            else:
                src = s.split(".")[0]
                if src != t:
                    aretes.add((src, t))
noeuds["CSV"] = [f"{s}.csv" for s in L.SOURCES]
noeuds["USAGE"] = ["EDA (notebook 02)", "Plateforme Streamlit"]
aretes |= {(t, "EDA (notebook 02)") for t in noeuds["MART"]}
aretes |= {("fact_container_event", "EDA (notebook 02)"), ("fact_container_event", "Plateforme Streamlit"),
           ("fact_yard_move", "Plateforme Streamlit")}

dot = ['digraph G { rankdir=LR; nodesep=0.28; ranksep=0.32; splines=true;',
       'node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=19, color="#44546A", height=0.55];',
       'edge [color="#8492A6", arrowsize=0.55, penwidth=0.8];']
for couche, ns in noeuds.items():
    dot += [f'"{n}" [fillcolor="{COUL[couche]}"];' for n in ns]
dot += ['"HDFS (archive)" [fillcolor="#FFFFFF", color="#D9631E"];',
        '"etl_rejects" [fillcolor="#FBE0DE", color="#B03A2E"];',
        '"container_events.csv" -> "HDFS (archive)" [style=dashed, color="#D9631E"];',
        '"HDFS (archive)" -> "raw_container_events" [style=dashed, color="#D9631E"];',
        '"raw_container_events" -> "etl_rejects" [style=dashed, color="#B03A2E"];',
        '"raw_yard_moves" -> "etl_rejects" [style=dashed, color="#B03A2E"];']
dot += [f'"{a}" -> "{b}";' for a, b in sorted(aretes)]
dot.append("}")
for fmt, extra in (("png", ["-Gdpi=170"]), ("svg", [])):
    subprocess.run(["dot", f"-T{fmt}", *extra, "-o", f"{OUT}.{fmt}"], input="\n".join(dot), text=True, check=True)
print("Schéma écrit :", os.path.normpath(OUT) + ".png / .svg")
