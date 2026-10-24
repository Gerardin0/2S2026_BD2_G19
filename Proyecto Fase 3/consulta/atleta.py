#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
atleta.py — Consulta (c) de la Fase 3: toda la información de un atleta.

Uso (desde `Proyecto Fase 3`):

    python consulta/atleta.py "Michael Phelps"
    python consulta/atleta.py "erick barrondo"                 # sin tildes, palabras en cualquier orden
    python consulta/atleta.py "Phelps" --deporte swim --anio 2008 --medalla oro
    python consulta/atleta.py "Bolt" --pais JAM --desde 2008 --hasta 2016
    python consulta/atleta.py --id 123159                       # por athlete_id
    python consulta/atleta.py "Smith" --max-atletas 0           # solo la lista de coincidencias

Busca por nombre completo o nombre de uso (parcial, sin importar mayúsculas ni
tildes). Si hay varias coincidencias muestra la lista y la ficha de las primeras
`--max-atletas` (una coincidencia exacta del nombre va siempre primero).
"""

import argparse
import sys

from comun import (NOMBRE_MEDALLA, Cronometro, args_conexion, conectar, cond_expr, explicar,
                   filtro_nombre, filtro_participacion, medallas_texto, normalizar, tabla, titulo)


def parsear():
    ap = argparse.ArgumentParser(description="Consulta toda la información de un atleta (Fase 3).")
    ap.add_argument("nombre", nargs="?", help="Nombre (o parte) del atleta")
    ap.add_argument("--id", type=int, help="athlete_id exacto")
    ap.add_argument("--pais", help="Código NOC con el que participó (ej. USA)")
    ap.add_argument("--anio", type=int, help="Año de la edición")
    ap.add_argument("--desde", type=int, help="Año inicial (rango)")
    ap.add_argument("--hasta", type=int, help="Año final (rango)")
    ap.add_argument("--deporte", help="Deporte/disciplina (texto parcial, ej. Swimming)")
    ap.add_argument("--evento", help="Evento (texto parcial, ej. '100 metres')")
    ap.add_argument("--temporada", help="Summer / Winter")
    ap.add_argument("--medalla", help="Gold/Silver/Bronze, oro/plata/bronce o 'todas'")
    ap.add_argument("--max-atletas", type=int, default=3, help="Fichas a desplegar si hay varias coincidencias (defecto 3)")
    ap.add_argument("--limite", type=int, default=100, help="Máximo de participaciones por ficha (defecto 100)")
    args_conexion(ap)
    args = ap.parse_args()
    if not args.nombre and args.id is None:
        ap.error("indique el nombre del atleta o --id")
    if args.pais:
        args.pais = args.pais.upper()
    return args


def main():
    args = parsear()
    db = conectar(args)
    crono = Cronometro()

    cond = filtro_participacion(args, args.pais)
    filtro = {"_id": args.id} if args.id is not None else filtro_nombre(args.nombre)
    if cond:
        filtro["participaciones"] = {"$elemMatch": cond}
    buscado = normalizar(args.nombre) if args.nombre else ""

    # 1) Coincidencias (ligero: sin el detalle de participaciones)
    pipeline_lista = [
        {"$match": filtro},
        {"$project": {
            "nombre_uso": 1, "nombre_completo": 1, "noc_code": 1, "sexo": 1,
            "nacido": "$nacimiento.fecha", "resumen_medallas": 1,
            "anios": {"$setUnion": ["$participaciones.anio", []]},
            "deportes": {"$setUnion": ["$participaciones.deporte", []]},
            # nombre completo o de uso idéntico al buscado
            "exacto": {"$in": [buscado, {"$split": ["$busqueda_nombre", " / "]}]},
        }},
        {"$sort": {"resumen_medallas.total": -1, "_id": 1}},
        {"$limit": 500},
    ]
    candidatos = crono(db.atletas.aggregate, pipeline_lista)
    candidatos.sort(key=lambda c: (not c["exacto"], -c.get("resumen_medallas", {}).get("total", 0), c["_id"]))

    criterio = f"id={args.id}" if args.id is not None else f'"{args.nombre}"'
    filtros_txt = ", ".join(f"{k}={v}" for k, v in vars(args).items()
                            if k in ("pais", "anio", "desde", "hasta", "deporte", "evento", "temporada", "medalla") and v)
    if not candidatos:
        print(f"No se encontró ningún atleta para {criterio}" + (f" con filtros ({filtros_txt})" if filtros_txt else "") + ".")
        print(f"(consulta: {crono.ms:.0f} ms)")
        return 1

    nombres_pais = {p["_id"]: p.get("nombre") for p in crono(db.paises.find, {}, {"nombre": 1})}

    if len(candidatos) > 1:
        titulo(f"{len(candidatos)}{'+' if len(candidatos) == 500 else ''} atletas coinciden con {criterio}"
               + (f" | filtros: {filtros_txt}" if filtros_txt else ""))
        filas = [{
            "id": c["_id"], "nombre": c.get("nombre_uso") or c.get("nombre_completo"),
            "pais": c.get("noc_code"), "sexo": (c.get("sexo") or "")[:1], "nacido": c.get("nacido"),
            "anios": ", ".join(str(a) for a in sorted(x for x in c.get("anios", []) if x)),
            "deportes": ", ".join(sorted(d for d in c.get("deportes", []) if d)),
            "med": medallas_texto(c.get("resumen_medallas", {})).replace("Oro ", "O:").replace(" | Plata ", " P:")
                   .replace(" | Bronce ", " B:").replace(" | Total ", " T:"),
            "": "← exacto" if c["exacto"] else "",
        } for c in candidatos[:max(args.limite, 25)]]
        tabla(filas, [("ID", "id"), ("Nombre", "nombre"), ("NOC", "pais"), ("S", "sexo"), ("Nacido", "nacido"),
                      ("Años", "anios"), ("Deportes", "deportes"), ("Medallas", "med"), ("", "")],
              {"nombre": 32, "anios": 30, "deportes": 30})
        if len(candidatos) > len(filas):
            print(f"  … y {len(candidatos) - len(filas)} más (refine el nombre o use filtros / --id)")
        if args.max_atletas <= 0:
            print(f"\n(consulta: {crono.ms:.0f} ms)")
            return 0

    # 2) Ficha completa de los elegidos, con participaciones filtradas
    elegidos = [c["_id"] for c in candidatos[:max(1, args.max_atletas)]]
    pipeline_ficha = [
        {"$match": {"_id": {"$in": elegidos}}},
        {"$project": {
            "nombre_completo": 1, "nombre_uso": 1, "sexo": 1, "noc_code": 1, "nacimiento": 1,
            "fecha_fallecimiento": 1, "afiliaciones": 1, "roles": 1, "resumen_medallas": 1,
            "total_participaciones": {"$size": "$participaciones"},
            "participaciones": {"$filter": {"input": "$participaciones", "as": "p", "cond": cond_expr(cond)}},
        }},
    ]
    fichas = {f["_id"]: f for f in crono(db.atletas.aggregate, pipeline_ficha)}

    for aid in elegidos:
        imprimir_ficha(fichas[aid], nombres_pais, args, filtros_txt)

    print(f"\n(consulta resuelta en {crono.ms:.0f} ms)")
    if args.explain:
        explicar(db, "atletas", pipeline_lista, "búsqueda de coincidencias")
        explicar(db, "atletas", pipeline_ficha, "ficha del atleta")
    return 0


def imprimir_ficha(a, nombres_pais, args, filtros_txt):
    titulo(f"{a.get('nombre_uso') or a.get('nombre_completo')}  (athlete_id {a['_id']})")
    nac = a.get("nacimiento") or {}
    lugar = ", ".join(x for x in (nac.get("ciudad"), nac.get("region"), nac.get("pais")) if x)
    print(f"  Nombre completo : {a.get('nombre_completo')}")
    print(f"  Sexo            : {a.get('sexo') or '-'}")
    print(f"  País (NOC)      : {a.get('noc_code') or '-'} - {nombres_pais.get(a.get('noc_code')) or ''}")
    print(f"  Nacimiento      : {nac.get('fecha') or '-'}{(' en ' + lugar) if lugar else ''}")
    if a.get("fecha_fallecimiento"):
        print(f"  Fallecimiento   : {a['fecha_fallecimiento']}")
    if a.get("afiliaciones"):
        print(f"  Afiliaciones    : {a['afiliaciones']}")
    print(f"  Roles           : {', '.join(a.get('roles') or [])}")
    print(f"  Medallas (total): {medallas_texto(a.get('resumen_medallas', {}))}")

    parts = sorted(a["participaciones"], key=lambda p: (p.get("anio") or 0, p.get("temporada") or "",
                                                        p.get("deporte") or "", p.get("evento") or ""))
    paises = sorted({p["pais"] for p in parts if p.get("pais")})
    ediciones = sorted({(p.get("anio"), p.get("temporada"), p.get("ciudad"), p.get("categoria")) for p in parts},
                       key=lambda e: (e[0] or 0, e[1] or ""))
    print(f"  Participaciones : {len(parts)}" + (f" de {a['total_participaciones']} (filtros: {filtros_txt})"
                                                  if filtros_txt else "")
          + f" en {len(ediciones)} edición(es) | países: {', '.join(paises) or '-'}")
    print(f"  Ediciones       : " + "; ".join(f"{e[0]} {e[1]} ({e[2]}" + (f", {e[3]})" if e[3] and e[3] != "Olympics" else ")")
                                             for e in ediciones))

    if filtros_txt:
        m = {"oro": 0, "plata": 0, "bronce": 0}
        for p in parts:
            if p.get("medalla") in NOMBRE_MEDALLA:
                m[NOMBRE_MEDALLA[p["medalla"]].lower()] += 1
        m["total"] = sum(m.values())
        print(f"  Medallas (filtro): {medallas_texto(m)}")

    print("\n  Participaciones y resultados:")
    filas = [{
        "anio": p.get("anio"), "temp": p.get("temporada"), "ciudad": p.get("ciudad"),
        "deporte": p.get("deporte"), "evento": p.get("evento"), "pais": p.get("pais"),
        "equipo": p.get("equipo") if p.get("equipo") and p.get("equipo") != nombres_pais.get(p.get("pais")) else "",
        "edad": p.get("edad"),
        "pos": (("=" if p.get("empate") else "") + str(p["posicion"])) if p.get("posicion") else "-",
        "medalla": NOMBRE_MEDALLA.get(p.get("medalla"), ""),
    } for p in parts[: args.limite]]
    tabla(filas, [("Año", "anio"), ("Temp.", "temp"), ("Ciudad", "ciudad"), ("Deporte", "deporte"),
                  ("Evento", "evento"), ("NOC", "pais"), ("Equipo", "equipo"), ("Edad", "edad"),
                  ("Pos.", "pos"), ("Medalla", "medalla")],
          {"ciudad": 16, "deporte": 26, "evento": 42, "equipo": 18})
    if len(parts) > args.limite:
        print(f"  … {len(parts) - args.limite} participaciones más (use --limite N o filtros)")


if __name__ == "__main__":
    sys.exit(main())
