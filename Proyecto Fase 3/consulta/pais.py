#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pais.py — Consulta (d) de la Fase 3: toda la información de un país.

Uso (desde `Proyecto Fase 3`):

    python consulta/pais.py GUA
    python consulta/pais.py "Guatemala"                         # por nombre (sin importar tildes)
    python consulta/pais.py USA --anio 2008                     # una edición
    python consulta/pais.py MEX --desde 2000 --hasta 2020 --deporte Diving
    python consulta/pais.py JAM --medalla oro --limite 50
    python consulta/pais.py GUA --atletas                       # lista de atletas del país
    python consulta/pais.py GUA --anio 2024 --resultados        # todas las participaciones y posiciones

Despliega: resumen, si ha sido sede y en qué años, años de participación,
medallero (total, por año y por deporte), medallas ganadas (resultados) y,
opcionalmente, atletas y todas las participaciones. Las medallas se cuentan
por evento (una medalla de equipo cuenta una sola vez).
"""

import argparse
import re
import sys

from comun import (NOMBRE_MEDALLA, Cronometro, args_conexion, conectar, cond_expr, explicar,
                   filtro_participacion, medallas_texto, normalizar, tabla, titulo)


def parsear():
    ap = argparse.ArgumentParser(description="Consulta toda la información de un país (Fase 3).")
    ap.add_argument("pais", help="Código NOC (GUA) o nombre del país (Guatemala)")
    ap.add_argument("--anio", type=int, help="Año de la edición")
    ap.add_argument("--desde", type=int, help="Año inicial (rango)")
    ap.add_argument("--hasta", type=int, help="Año final (rango)")
    ap.add_argument("--deporte", help="Deporte/disciplina (texto parcial)")
    ap.add_argument("--evento", help="Evento (texto parcial)")
    ap.add_argument("--temporada", help="Summer / Winter")
    ap.add_argument("--medalla", help="Gold/Silver/Bronze, oro/plata/bronce o 'todas'")
    ap.add_argument("--atletas", action="store_true", help="Lista los atletas del país (con los filtros)")
    ap.add_argument("--resultados", action="store_true", help="Lista todas las participaciones con su posición")
    ap.add_argument("--limite", type=int, default=40, help="Máximo de filas por listado (defecto 40)")
    args_conexion(ap)
    return ap.parse_args()


# Códigos que la carga unificó (corrección C1 de cargar_mongo.py)
ALIAS_NOC = {"ROC": "RUS", "COR": "KOR"}


def resolver_pais(db, texto, crono):
    """Busca por código NOC; si no existe, por nombre del país o notas."""
    campos = {"poblaciones": 0}
    codigo = texto.upper()
    if codigo in ALIAS_NOC:
        print(f"Nota: {codigo} se cargó unificado con {ALIAS_NOC[codigo]}.")
        codigo = ALIAS_NOC[codigo]
    doc = crono(db.paises.find_one, {"_id": codigo}, campos)
    if doc:
        return [doc]
    buscado = normalizar(texto)
    exactos = crono(db.paises.find, {"busqueda_nombre": buscado}, campos)
    if exactos:
        return exactos
    patron = re.escape(buscado)
    return crono(db.paises.find, {"$or": [{"busqueda_nombre": {"$regex": patron}},
                                          {"notas": {"$regex": patron, "$options": "i"}}]}, campos)


def main():
    args = parsear()
    db = conectar(args)
    crono = Cronometro()

    candidatos = resolver_pais(db, args.pais, crono)
    if not candidatos:
        print(f'No existe ningún país con código o nombre "{args.pais}". (consulta: {crono.ms:.0f} ms)')
        return 1
    if len(candidatos) > 1:
        titulo(f'{len(candidatos)} países coinciden con "{args.pais}" — se despliegan todos')
        tabla([{"noc": c["_id"], "nombre": c.get("nombre"), "notas": c.get("notas"),
                "anios": f"{c['resumen'].get('primera_participacion') or '-'}–{c['resumen'].get('ultima_participacion') or '-'}",
                "med": c["medallero"].get("total", 0)} for c in candidatos],
              [("NOC", "noc"), ("Nombre", "nombre"), ("Notas", "notas"), ("Participó", "anios"), ("Medallas", "med")])

    planes = []
    for pais in candidatos:
        planes += desplegar(db, pais, args, crono)

    print(f"\n(consulta resuelta en {crono.ms:.0f} ms)")
    if args.explain:
        for coleccion, pipeline, nombre in planes:
            explicar(db, coleccion, pipeline, nombre)
    return 0


def desplegar(db, pais, args, crono):
    noc = pais["_id"]
    cond = filtro_participacion(args, noc)
    hay_filtro = len(cond) > 1
    filtros_txt = ", ".join(f"{k}={v}" for k, v in vars(args).items()
                            if k in ("anio", "desde", "hasta", "deporte", "evento", "temporada", "medalla") and v)
    pob = {p["anio"]: p["poblacion"] for p in
           (crono(db.paises.find_one, {"_id": noc}, {"poblaciones": 1}) or {}).get("poblaciones", [])}
    planes = []

    titulo(f"{pais.get('nombre') or noc}  ({noc})" + (f"  —  filtros: {filtros_txt}" if filtros_txt else ""))
    r = pais["resumen"]
    if pais.get("notas"):
        print(f"  Notas                 : {pais['notas']}")
    print(f"  Atletas / particip.   : {r.get('total_atletas', 0):,} atletas, {r.get('total_participaciones', 0):,} participaciones")
    print(f"  Ediciones             : {r.get('ediciones_participadas', 0)} "
          f"(primera {r.get('primera_participacion') or '-'}, última {r.get('ultima_participacion') or '-'})")
    if pob:
        ultimo = max(pob)
        print(f"  Población             : {pob[ultimo]:,} ({ultimo})")
    else:
        print("  Población             : sin datos")
    print(f"  Medallero (por evento): {medallas_texto(pais['medallero'])}")
    ma = r.get("medallas_por_atleta") or {}
    if ma.get("total", 0) != pais["medallero"].get("total", 0):
        print(f"  Medallas por atleta   : {medallas_texto(ma)}  (cada integrante de un equipo cuenta)")

    # --- Sede ---------------------------------------------------------------
    sedes = pais.get("ediciones_sede") or []
    print(f"\n  ¿Ha sido sede?        : {f"SÍ, {len(sedes)} {'vez' if len(sedes) == 1 else 'veces'}" if sedes else 'NO'}")
    if sedes:
        tabla([{"anio": s["anio"], "temp": s.get("temporada"), "ciudad": s.get("ciudad"), "cat": s.get("categoria")}
               for s in sedes], [("Año", "anio"), ("Temporada", "temp"), ("Ciudad", "ciudad"), ("Categoría", "cat")])

    # --- Años de participación ---------------------------------------------
    print(f"\n  Años de participación : {', '.join(str(a) for a in pais.get('anios_participacion', [])) or '-'}")

    if not hay_filtro:
        ediciones, por_deporte = resumen_precalculado(pais)
    else:
        ediciones, por_deporte, plan = resumen_filtrado(db, noc, cond, crono)
        planes.append(("atletas", plan, f"medallero filtrado de {noc}"))

    # --- Participación y medallero por edición -----------------------------
    print(f"\n  Participación y medallas por edición{' (filtrado)' if hay_filtro else ''}:")
    for e in ediciones:
        e["pob"] = f"{pob[e['anio']]:,}" if e["anio"] in pob else ""
        e["sede"] = "SEDE" if any(s["anio"] == e["anio"] and s.get("temporada") == e["temporada"] for s in sedes) else ""
    tabla(ediciones, [("Año", "anio"), ("Temp.", "temporada"), ("Ciudad", "ciudad"), ("Categoría", "categoria"),
                      ("", "sede"), ("Atletas", "atletas"), ("Partic.", "participaciones"), ("Oro", "oro"),
                      ("Plata", "plata"), ("Bronce", "bronce"), ("Total", "total"), ("Población", "pob")],
          {"ciudad": 18})
    if hay_filtro:
        tot = {k: sum(e[k] for e in ediciones) for k in ("oro", "plata", "bronce", "total")}
        print(f"  Medallero con filtros: {medallas_texto(tot)}")

    print(f"\n  Medallero por deporte{' (filtrado)' if hay_filtro else ''}:")
    tabla(por_deporte[: args.limite], [("Deporte", "deporte"), ("Oro", "oro"), ("Plata", "plata"),
                                       ("Bronce", "bronce"), ("Total", "total")])
    if len(por_deporte) > args.limite:
        print(f"  … {len(por_deporte) - args.limite} deportes más")

    # --- Medallas ganadas (resultados) ------------------------------------
    cond_med = dict(cond)
    cond_med.setdefault("medalla", {"$in": ["Gold", "Silver", "Bronze"]})
    pipeline_med = [
        {"$match": {"participaciones": {"$elemMatch": cond_med}}},
        {"$project": {"nombre_uso": 1, "p": {"$filter": {"input": "$participaciones", "as": "p",
                                                          "cond": cond_expr(cond_med)}}}},
        {"$unwind": "$p"},
        {"$group": {"_id": {"anio": "$p.anio", "temporada": "$p.temporada", "deporte": "$p.deporte",
                            "evento": "$p.evento", "medalla": "$p.medalla"},
                    "atletas": {"$addToSet": "$nombre_uso"}}},
        {"$addFields": {"orden": {"$indexOfArray": [["Gold", "Silver", "Bronze"], "$_id.medalla"]}}},
        {"$sort": {"_id.anio": -1, "orden": 1, "_id.deporte": 1, "_id.evento": 1}},
    ]
    medallas = crono(db.atletas.aggregate, pipeline_med)
    planes.append(("atletas", pipeline_med, f"medallas ganadas por {noc}"))
    print(f"\n  Medallas ganadas ({len(medallas)}), más recientes primero:")
    tabla([{"anio": m["_id"]["anio"], "temp": m["_id"]["temporada"], "deporte": m["_id"]["deporte"],
            "evento": m["_id"]["evento"], "medalla": NOMBRE_MEDALLA.get(m["_id"]["medalla"]),
            "atletas": ", ".join(sorted(a for a in m["atletas"] if a))} for m in medallas[: args.limite]],
          [("Año", "anio"), ("Temp.", "temp"), ("Deporte", "deporte"), ("Evento", "evento"),
           ("Medalla", "medalla"), ("Atleta(s)", "atletas")],
          {"deporte": 24, "evento": 40, "atletas": 50})
    if len(medallas) > args.limite:
        print(f"  … {len(medallas) - args.limite} medallas más (use --limite N o filtros)")

    if args.atletas:
        planes.append(listar_atletas(db, noc, cond, args, crono))
    if args.resultados:
        planes.append(listar_resultados(db, noc, cond, args, crono))
    return planes


def resumen_precalculado(pais):
    """Sin filtros: todo sale del documento del país (calculado en la carga)."""
    medallas = {(m["anio"], m["temporada"]): m for m in pais["medallero"].get("por_anio", [])}
    ediciones = []
    for e in pais.get("participaciones", []):
        m = medallas.get((e["anio"], e["temporada"]), {})
        ediciones.append({**e, **{k: m.get(k, 0) for k in ("oro", "plata", "bronce", "total")}})
    ediciones.sort(key=lambda e: (e["anio"], e["temporada"]))
    return ediciones, pais["medallero"].get("por_deporte", [])


def resumen_filtrado(db, noc, cond, crono):
    """Con filtros: se agrega sobre las participaciones embebidas en `atletas`."""
    pipeline = [
        {"$match": {"participaciones": {"$elemMatch": cond}}},
        {"$project": {"p": {"$filter": {"input": "$participaciones", "as": "p", "cond": cond_expr(cond)}}}},
        {"$unwind": "$p"},
        {"$facet": {
            "ediciones": [
                {"$group": {"_id": {"anio": "$p.anio", "temporada": "$p.temporada", "ciudad": "$p.ciudad",
                                    "categoria": "$p.categoria"},
                            "atletas": {"$addToSet": "$_id"}, "participaciones": {"$sum": 1},
                            "medallas": {"$addToSet": {"$cond": [{"$ifNull": ["$p.medalla", False]},
                                                                 {"d": "$p.id_disciplina", "m": "$p.medalla"},
                                                                 "$$REMOVE"]}}}},
                {"$sort": {"_id.anio": 1, "_id.temporada": 1}},
            ],
            "deportes": [
                {"$match": {"p.medalla": {"$ne": None}}},
                {"$group": {"_id": {"deporte": "$p.deporte", "anio": "$p.anio", "ed": "$p.id_edicion",
                                    "d": "$p.id_disciplina", "m": "$p.medalla"}}},
                {"$group": {"_id": "$_id.deporte", "medallas": {"$push": "$_id.m"}}},
            ],
        }},
    ]
    res = crono(db.atletas.aggregate, pipeline)[0]

    def conteo(lista):
        c = {"oro": lista.count("Gold"), "plata": lista.count("Silver"), "bronce": lista.count("Bronze")}
        c["total"] = sum(c.values())
        return c

    ediciones = [{**e["_id"], "atletas": len(e["atletas"]), "participaciones": e["participaciones"],
                  **conteo([m["m"] for m in e["medallas"]])} for e in res["ediciones"]]
    deportes = sorted(({"deporte": d["_id"], **conteo(d["medallas"])} for d in res["deportes"]),
                      key=lambda x: (-x["oro"], -x["plata"], -x["bronce"]))
    return ediciones, deportes, pipeline


def listar_atletas(db, noc, cond, args, crono):
    pipeline = [
        {"$match": {"participaciones": {"$elemMatch": cond}}},
        {"$project": {"nombre_uso": 1, "sexo": 1,
                      "p": {"$filter": {"input": "$participaciones", "as": "p", "cond": cond_expr(cond)}}}},
        {"$project": {"nombre_uso": 1, "sexo": 1, "n": {"$size": "$p"},
                      "anios": {"$setUnion": ["$p.anio", []]}, "deportes": {"$setUnion": ["$p.deporte", []]},
                      "oro": {"$size": {"$filter": {"input": "$p", "cond": {"$eq": ["$$this.medalla", "Gold"]}}}},
                      "plata": {"$size": {"$filter": {"input": "$p", "cond": {"$eq": ["$$this.medalla", "Silver"]}}}},
                      "bronce": {"$size": {"$filter": {"input": "$p", "cond": {"$eq": ["$$this.medalla", "Bronze"]}}}}}},
        {"$sort": {"oro": -1, "plata": -1, "bronce": -1, "n": -1, "nombre_uso": 1}},
    ]
    filas = crono(db.atletas.aggregate, pipeline)
    print(f"\n  Atletas ({len(filas)}), ordenados por medallas:")
    tabla([{"id": a["_id"], "nombre": a.get("nombre_uso"), "s": (a.get("sexo") or "")[:1], "n": a["n"],
            "anios": ", ".join(str(x) for x in sorted(y for y in a["anios"] if y)),
            "deportes": ", ".join(sorted(d for d in a["deportes"] if d)),
            "oro": a["oro"], "plata": a["plata"], "bronce": a["bronce"]} for a in filas[: args.limite]],
          [("ID", "id"), ("Atleta", "nombre"), ("S", "s"), ("Partic.", "n"), ("Años", "anios"),
           ("Deportes", "deportes"), ("Oro", "oro"), ("Plata", "plata"), ("Bronce", "bronce")],
          {"nombre": 30, "anios": 30, "deportes": 34})
    if len(filas) > args.limite:
        print(f"  … {len(filas) - args.limite} atletas más (use --limite N o filtros)")
    return ("atletas", pipeline, f"atletas de {noc}")


def listar_resultados(db, noc, cond, args, crono):
    pipeline = [
        {"$match": {"participaciones": {"$elemMatch": cond}}},
        {"$project": {"nombre_uso": 1, "p": {"$filter": {"input": "$participaciones", "as": "p",
                                                          "cond": cond_expr(cond)}}}},
        {"$unwind": "$p"},
        {"$sort": {"p.anio": -1, "p.deporte": 1, "p.evento": 1, "p.posicion": 1}},
        {"$facet": {"total": [{"$count": "n"}], "filas": [{"$limit": args.limite}]}},
    ]
    res = crono(db.atletas.aggregate, pipeline)[0]
    total = res["total"][0]["n"] if res["total"] else 0
    print(f"\n  Participaciones y resultados ({total:,}):")
    tabla([{"anio": f["p"].get("anio"), "temp": f["p"].get("temporada"), "deporte": f["p"].get("deporte"),
            "evento": f["p"].get("evento"), "atleta": f.get("nombre_uso"),
            "pos": (("=" if f["p"].get("empate") else "") + str(f["p"]["posicion"])) if f["p"].get("posicion") else "-",
            "medalla": NOMBRE_MEDALLA.get(f["p"].get("medalla"), "")} for f in res["filas"]],
          [("Año", "anio"), ("Temp.", "temp"), ("Deporte", "deporte"), ("Evento", "evento"),
           ("Atleta", "atleta"), ("Pos.", "pos"), ("Medalla", "medalla")],
          {"deporte": 24, "evento": 40, "atleta": 30})
    if total > args.limite:
        print(f"  … {total - args.limite:,} participaciones más (use --limite N o filtros)")
    return ("atletas", pipeline, f"participaciones de {noc}")


if __name__ == "__main__":
    sys.exit(main())
