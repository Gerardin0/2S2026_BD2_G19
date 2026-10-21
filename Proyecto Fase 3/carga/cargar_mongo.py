#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cargar_mongo.py — Proyecto Fase 3 (MongoDB)

ETL que lee las tablas de la Fase 1 (copiadas en `fuentes/`) y genera las 5
colecciones del modelo documental: roles, disciplinas, ediciones, paises y
atletas (con participaciones, resultados y medallas embebidos).

Uso (desde `Proyecto Fase 3`):

    python3 ddl/crear_colecciones_indices.py --uri "mongodb://admin:admin123@localhost:27017/"
    python3 carga/cargar_mongo.py [--uri mongodb://admin:admin123@localhost:27017/] [--base olimpiadas]

Correcciones aplicadas sobre las fuentes (quedan trazadas en la bitácora):

  C1  ROC -> RUS y COR -> KOR, tanto en el NOC del atleta como en el país de
      cada participación (antes solo se corregía el del atleta).
  C2  NOC de los 237 atletas sin participaciones: se toma de `bios.csv`
      (columna NOC = nombre del país) cruzado con `tabla_nocs.region`; si no
      cruza se usa `born_country` cuando es un NOC válido; si no, queda null.
  C3  IDs de atletas nuevos de París 2024: en la Fase 1 los atletas nuevos
      (ids 149815+) se numeraron en orden alfabético en `tabla_atletas.csv`,
      pero en orden de aparición en `tabla_participacion.csv`, por lo que
      ~10 mil participaciones de 2024 apuntaban a otra persona. Se reasigna el
      athlete_id buscando `presentado_como` por nombre normalizado (y por NOC
      del 2024 cuando hay homónimos).
  C4  Nombres: se quitan viñetas (•), comillas y paréntesis; `busqueda_nombre`
      se guarda en minúsculas y SIN tildes (nombre completo + nombre de uso), y
      `palabras_nombre` con cada palabra para buscar por prefijo con índice.
  C5  Medallero del país por EVENTO (una medalla de equipo cuenta una vez),
      además del conteo por atleta.

La carga es idempotente (ReplaceOne + upsert por _id) y la bitácora con fecha y
hora queda en `docs/logs/carga_mongo_<fecha>.log`.
"""

import argparse
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

import pandas as pd
from pymongo import MongoClient, ReplaceOne

URI_DEFECTO = "mongodb://admin:admin123@localhost:27017/"
BASE_DEFECTO = "olimpiadas"
CORRECCION_NOC = {"ROC": "RUS", "COR": "KOR"}
ORDEN_MEDALLA = {"Gold": 1, "Silver": 2, "Bronze": 3}


def limpiar_nan(valor):
    """Convierte NaN de pandas a None para compatibilidad con BSON de MongoDB"""
    if valor is None or (not isinstance(valor, (list, dict)) and pd.isna(valor)):
        return None
    return valor


def entero(valor):
    valor = limpiar_nan(valor)
    return None if valor is None else int(valor)


def normalizar(texto):
    """Minúsculas, sin tildes y sin espacios duplicados (para buscar por nombre)."""
    if texto is None or (not isinstance(texto, str) and pd.isna(texto)):
        return ""
    texto = unicodedata.normalize("NFKD", str(texto))
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", texto.replace("•", " ").strip().lower())


def limpiar_nombre(serie):
    return (serie.str.replace(r"[•·]", " ", regex=True)
                 .str.replace(r"[\"'\(\)]", "", regex=True)
                 .str.replace(r"\s+", " ", regex=True).str.strip())


def main():
    inicio = datetime.now()
    raiz = Path(__file__).resolve().parents[1]
    dir_fuentes = raiz / "fuentes"
    ruta_bios = raiz.parent / "Proyecto Fase 1" / "datasets" / "bios.csv"
    dir_logs = raiz / "docs" / "logs"
    dir_logs.mkdir(parents=True, exist_ok=True)

    ap = argparse.ArgumentParser(description="Carga de la Fase 3 a MongoDB")
    ap.add_argument("--uri", default=URI_DEFECTO)
    ap.add_argument("--base", default=BASE_DEFECTO)
    args = ap.parse_args()

    log_file = dir_logs / f"carga_mongo_{inicio.strftime('%Y%m%d_%H%M%S')}.log"

    def log(mensaje):
        out = f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {mensaje}"
        print(out)
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(out + "\n")

    log("=== INICIANDO ETL A MONGODB ===")
    log(f"Fuentes: {dir_fuentes} | Base: {args.base}")

    # ---------------------------------------------------------
    # 1. EXTRACCIÓN (Lectura de CSVs)
    # ---------------------------------------------------------
    log("Extrayendo datasets...")
    try:
        df_atletas = pd.read_csv(dir_fuentes / "tabla_atletas.csv")
        df_participacion = pd.read_csv(dir_fuentes / "tabla_participacion.csv")
        df_resultado = pd.read_csv(dir_fuentes / "tabla_resultado.csv")
        df_disciplina = pd.read_csv(dir_fuentes / "tabla_disciplina.csv")
        df_edicion = pd.read_csv(dir_fuentes / "tabla_edicion_juego.csv")
        df_nocs = pd.read_csv(dir_fuentes / "tabla_nocs.csv", keep_default_na=False, na_values=[""])
        df_rol = pd.read_csv(dir_fuentes / "tabla_rol.csv")
        df_atleta_rol = pd.read_csv(dir_fuentes / "tabla_atleta_rol.csv")
        df_poblaciones = pd.read_csv(dir_fuentes / "tabla_poblaciones_mapeada.csv")
        df_sedes = pd.read_csv(dir_fuentes / "ediciones_sede.csv", keep_default_na=False, na_values=[""])
        df_bios = pd.read_csv(ruta_bios, usecols=["athlete_id", "NOC"])
        nuevas = pd.read_csv(dir_fuentes / "tabla_atletas_nuevas_2024.csv", usecols=["athlete_id", "noc_2024"])
    except Exception as e:
        log(f"Error al leer archivos: {e}")
        sys.exit(1)
    for nombre, df in [("tabla_atletas", df_atletas), ("tabla_participacion", df_participacion),
                       ("tabla_resultado", df_resultado), ("tabla_disciplina", df_disciplina),
                       ("tabla_edicion_juego", df_edicion), ("tabla_nocs", df_nocs),
                       ("tabla_poblaciones_mapeada", df_poblaciones), ("ediciones_sede", df_sedes)]:
        log(f"  {nombre}: {len(df):,} filas")

    # ---------------------------------------------------------
    # 2. TRANSFORMACIÓN
    # ---------------------------------------------------------
    log("Transformando datos y aplicando correcciones...")
    df_participacion["athlete_id"] = df_participacion["athlete_id"].astype(int)
    nocs_validos = set(df_nocs["NOC"])
    nombre_noc = dict(zip(df_nocs["NOC"], df_nocs["region"]))

    # C3: reasignar athlete_id de las participaciones 2024 mal enlazadas
    # (se compara con el nombre original, antes de la limpieza C4)
    nombre_norm = dict(zip(df_atletas["athlete_id"], df_atletas["name"].map(normalizar)))
    ids_por_nombre = df_atletas.groupby(df_atletas["name"].map(normalizar))["athlete_id"].apply(list).to_dict()
    noc_2024 = dict(zip(nuevas["athlete_id"], nuevas["noc_2024"]))
    id_min_nuevo = min(noc_2024)
    reasignadas = sin_resolver = 0
    nuevos_ids = []
    for aid, como, noc in zip(df_participacion["athlete_id"], df_participacion["presentado_como"],
                              df_participacion["noc_code"]):
        como_n = normalizar(como)
        if aid >= id_min_nuevo and como_n and nombre_norm.get(aid) != como_n:
            candidatos = ids_por_nombre.get(como_n, [])
            if len(candidatos) > 1:
                candidatos = [c for c in candidatos if noc_2024.get(c) == noc] or candidatos
            if len(candidatos) == 1:
                nuevos_ids.append(candidatos[0])
                reasignadas += 1
                continue
            sin_resolver += 1
        nuevos_ids.append(aid)
    df_participacion["athlete_id"] = nuevos_ids
    log(f"  C3 participaciones 2024 reasignadas a su atleta correcto: {reasignadas:,} (sin resolver: {sin_resolver})")

    # C4: limpieza de nombres
    df_atletas["Full name"] = limpiar_nombre(df_atletas["Full name"])
    df_atletas["name"] = limpiar_nombre(df_atletas["name"])

    # C1: ROC->RUS, COR->KOR en las participaciones
    antes = df_participacion["noc_code"].isin(CORRECCION_NOC.keys()).sum()
    df_participacion["noc_code"] = df_participacion["noc_code"].replace(CORRECCION_NOC)
    log(f"  C1 participaciones con NOC corregido (ROC->RUS, COR->KOR): {antes:,}")

    # NOC del atleta = el más frecuente de sus participaciones
    noc_frecuente = (df_participacion.dropna(subset=["noc_code"])
                     .groupby("athlete_id")["noc_code"].agg(lambda s: s.value_counts().index[0]))
    df_atletas["noc_code"] = df_atletas["athlete_id"].map(noc_frecuente)

    # C2: NOC de los atletas sin participaciones desde bios.csv
    region_a_noc = {}
    for noc, region in zip(df_nocs["NOC"], df_nocs["region"]):
        if pd.notna(region):
            region_a_noc.setdefault(normalizar(region), noc)
    bios_noc = dict(zip(df_bios["athlete_id"], df_bios["NOC"]))
    sin_noc = df_atletas["noc_code"].isna()
    asignados = 0
    for idx in df_atletas.index[sin_noc]:
        aid = df_atletas.at[idx, "athlete_id"]
        noc = region_a_noc.get(normalizar(bios_noc.get(aid)))
        if noc is None and df_atletas.at[idx, "born_country"] in nocs_validos:
            noc = df_atletas.at[idx, "born_country"]
        if noc:
            df_atletas.at[idx, "noc_code"] = CORRECCION_NOC.get(noc, noc)
            asignados += 1
    log(f"  C2 atletas sin participaciones: {int(sin_noc.sum())} -> NOC asignado a {asignados}, "
        f"null: {int(sin_noc.sum()) - asignados}")

    # Preparar participaciones con datos embebidos
    df_part_full = (df_participacion
                    .merge(df_resultado, on="id_participacion", how="left")
                    .merge(df_sedes[["id_edicion_juego", "anio", "temporada", "ciudad", "categoria"]],
                           on="id_edicion_juego", how="left")
                    .merge(df_disciplina, on="id_disciplina", how="left")
                    .sort_values(["athlete_id", "anio", "id_participacion"]))

    log("Agrupando roles por atleta...")
    df_roles_full = df_atleta_rol.merge(df_rol, on="rol_id")
    roles_por_atleta = df_roles_full.groupby("athlete_id")["nombre_rol"].apply(list).to_dict()

    log("Agrupando participaciones por atleta y país...")
    parts_por_atleta = {}
    for p in df_part_full.itertuples(index=False):
        parts_por_atleta.setdefault(p.athlete_id, []).append({
            "id_participacion": int(p.id_participacion),
            "id_edicion": int(p.id_edicion_juego),
            "id_disciplina": int(p.id_disciplina),
            "anio": entero(p.anio),
            "temporada": limpiar_nan(p.temporada),
            "ciudad": limpiar_nan(p.ciudad),
            "categoria": limpiar_nan(p.categoria),
            "deporte": limpiar_nan(p.sport),
            "evento": limpiar_nan(p.event_name),
            "pais": limpiar_nan(p.noc_code),
            "equipo": limpiar_nan(p.team),
            "presentado_como": limpiar_nan(p.presentado_como),
            "edad": entero(p.age),
            "posicion": entero(p.place),
            "empate": bool(p.tied) if pd.notna(p.tied) else False,
            "medalla": limpiar_nan(p.medal),
        })

    pob_por_pais = df_poblaciones.groupby("noc_code")[["year", "population"]] \
        .apply(lambda x: x.to_dict("records")).to_dict()
    sedes_por_pais = df_sedes.dropna(subset=["noc_sede"]).groupby("noc_sede")[["anio", "temporada", "ciudad", "categoria"]] \
        .apply(lambda x: x.sort_values("anio").to_dict("records")).to_dict()

    # C5: medallero por evento (una medalla de equipo cuenta una vez)
    df_med = df_part_full.dropna(subset=["medal", "noc_code"])
    df_med_evento = df_med.drop_duplicates(["noc_code", "id_edicion_juego", "id_disciplina", "medal"])

    def conteo(df):
        c = df["medal"].value_counts()
        oro, plata, bronce = int(c.get("Gold", 0)), int(c.get("Silver", 0)), int(c.get("Bronze", 0))
        return {"oro": oro, "plata": plata, "bronce": bronce, "total": oro + plata + bronce}

    medallero_pais = {}
    for noc, g in df_med_evento.groupby("noc_code"):
        por_anio = [{"anio": int(a), "temporada": t, **conteo(gg)}
                    for (a, t), gg in g.groupby(["anio", "temporada"])]
        por_deporte = sorted(({"deporte": d, **conteo(gg)} for d, gg in g.groupby("sport")),
                             key=lambda x: (-x["oro"], -x["plata"], -x["bronce"]))
        medallero_pais[noc] = {**conteo(g), "por_anio": por_anio, "por_deporte": por_deporte}
    medallas_atleta_pais = {noc: conteo(g) for noc, g in df_med.groupby("noc_code")}

    ediciones_pais = {}
    for (noc, a, t, c, cat), g in df_part_full.dropna(subset=["noc_code"]).groupby(
            ["noc_code", "anio", "temporada", "ciudad", "categoria"]):
        ediciones_pais.setdefault(noc, []).append({
            "anio": int(a), "temporada": t, "ciudad": c, "categoria": cat,
            "atletas": int(g["athlete_id"].nunique()), "participaciones": int(len(g))})

    # ---------------------------------------------------------
    # 3. CONSTRUCCIÓN DE DOCUMENTOS BSON
    # ---------------------------------------------------------
    docs_roles = [{"_id": int(r["rol_id"]), "nombre": r["nombre_rol"], "descripcion": None} for _, r in df_rol.iterrows()]
    docs_disciplinas = [{
        "_id": int(r["id_disciplina"]),
        "deporte": str(r["sport"]) if pd.notna(r["sport"]) and str(r["sport"]).strip() != "" else "Desconocido",
        "evento": str(r["event_name"]) if pd.notna(r["event_name"]) and str(r["event_name"]).strip() != "" else "Desconocido"
    } for _, r in df_disciplina.iterrows()]

    parts_por_edicion = df_participacion["id_edicion_juego"].value_counts().to_dict()
    docs_ediciones = []
    for _, r in df_sedes.iterrows():
        anio_int = int(r["anio"]) if pd.notna(r["anio"]) else None
        noc_sede = limpiar_nan(r["noc_sede"])
        docs_ediciones.append({
            "_id": int(r["id_edicion_juego"]),
            "anio": anio_int,
            "temporada": limpiar_nan(r["temporada"]),
            "categoria": limpiar_nan(r["categoria"]),
            "juegos": f"{anio_int} {r['temporada']}" if r["categoria"] == "Olympics"
                      else f"{anio_int} {r['temporada']} ({r['categoria']})",
            "ciudad": limpiar_nan(r["ciudad"]),
            "noc_sede": noc_sede,
            "pais_sede": limpiar_nan(nombre_noc.get(noc_sede)),
            "sede_confirmada": noc_sede is not None,
            "total_participaciones": int(parts_por_edicion.get(r["id_edicion_juego"], 0)),
        })

    atletas_por_pais = df_part_full.dropna(subset=["noc_code"]).groupby("noc_code")["athlete_id"].nunique().to_dict()
    parts_por_pais = df_part_full["noc_code"].value_counts().to_dict()
    docs_paises = []
    for _, r in df_nocs.iterrows():
        noc = r["NOC"]
        medallero = medallero_pais.get(noc, {"oro": 0, "plata": 0, "bronce": 0, "total": 0,
                                             "por_anio": [], "por_deporte": []})
        ediciones = ediciones_pais.get(noc, [])
        anios = sorted({e["anio"] for e in ediciones})
        docs_paises.append({
            "_id": noc,
            "nombre": limpiar_nan(r["region"]),
            "busqueda_nombre": normalizar(r["region"]),
            "notas": limpiar_nan(r["notes"]),
            "resumen": {
                "total_atletas": int(atletas_por_pais.get(noc, 0)),
                "total_participaciones": int(parts_por_pais.get(noc, 0)),
                "total_medallas": medallero["total"],
                "ediciones_participadas": len(ediciones),
                "primera_participacion": anios[0] if anios else None,
                "ultima_participacion": anios[-1] if anios else None,
                "medallas_por_atleta": medallas_atleta_pais.get(noc, {"oro": 0, "plata": 0, "bronce": 0, "total": 0}),
            },
            "medallero": medallero,
            "anios_participacion": anios,
            "participaciones": ediciones,
            "poblaciones": [{"anio": int(p["year"]), "poblacion": int(p["population"])} for p in pob_por_pais.get(noc, [])],
            "ediciones_sede": [{k: (int(v) if k == "anio" else v) for k, v in s.items()}
                               for s in sedes_por_pais.get(noc, [])],
        })

    log(f"Construyendo documentos de atletas (~{len(df_atletas):,})...")
    docs_atletas = []
    for r in df_atletas.to_dict("records"):
        a_id = int(r["athlete_id"])
        parts = parts_por_atleta.get(a_id, [])
        medallas = {"oro": 0, "plata": 0, "bronce": 0}
        for p in parts:
            if p["medalla"] in ORDEN_MEDALLA:
                medallas[{"Gold": "oro", "Silver": "plata", "Bronze": "bronce"}[p["medalla"]]] += 1
        medallas["total"] = sum(medallas.values())
        busqueda = normalizar(r["Full name"])
        uso = normalizar(r["name"])
        if uso and uso not in busqueda:
            busqueda = f"{busqueda} / {uso}" if busqueda else uso
        docs_atletas.append({
            "_id": a_id,
            "source_athlete_id": None,
            "nombre_completo": limpiar_nan(r["Full name"]),
            "nombre_uso": limpiar_nan(r["name"]),
            "busqueda_nombre": busqueda,
            "palabras_nombre": sorted(set(re.split(r"[^a-z0-9]+", busqueda)) - {""}),
            "sexo": limpiar_nan(r["Sex"]),
            "noc_code": limpiar_nan(r["noc_code"]),
            "nacimiento": {"fecha": limpiar_nan(r["born_date"]), "ciudad": limpiar_nan(r["born_city"]),
                           "region": limpiar_nan(r["born_region"]), "pais": limpiar_nan(r["born_country"])},
            "fecha_fallecimiento": limpiar_nan(r["died_date"]),
            "afiliaciones": limpiar_nan(r["Affiliations"]),
            "roles": roles_por_atleta.get(a_id, ["Competitor"]),
            "resumen_medallas": medallas,
            "participaciones": parts,
        })

    # ---------------------------------------------------------
    # 4. CARGA A MONGODB (Idempotente)
    # ---------------------------------------------------------
    log("Conectando a MongoDB y aplicando Bulk Writes...")
    cliente = MongoClient(args.uri)
    db = cliente[args.base]

    def bulk_upsert(coleccion, documentos):
        if not documentos:
            return
        ops = [ReplaceOne({"_id": d["_id"]}, d, upsert=True) for d in documentos]
        res = db[coleccion].bulk_write(ops, ordered=False)
        log(f"  -> {coleccion}: insertados {res.upserted_count:,}, reemplazados {res.modified_count:,}")

    bulk_upsert("roles", docs_roles)
    bulk_upsert("disciplinas", docs_disciplinas)
    bulk_upsert("ediciones", docs_ediciones)
    bulk_upsert("paises", docs_paises)

    lote_size = 10000
    for i in range(0, len(docs_atletas), lote_size):
        bulk_upsert("atletas", docs_atletas[i:i + lote_size])

    log("Conteos finales:")
    for col in ["roles", "disciplinas", "ediciones", "paises", "atletas"]:
        log(f"  {col}: {db[col].count_documents({}):,} documentos")
    total_parts = next(db.atletas.aggregate([{"$group": {"_id": None, "n": {"$sum": {"$size": "$participaciones"}}}}]))["n"]
    log(f"  participaciones embebidas: {total_parts:,} (fuente: {len(df_participacion):,})")

    log("=== CARGA FINALIZADA ===")
    log(f"Tiempo total: {(datetime.now() - inicio).total_seconds():.2f} segundos")


if __name__ == "__main__":
    main()
