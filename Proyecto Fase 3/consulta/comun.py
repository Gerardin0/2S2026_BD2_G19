# -*- coding: utf-8 -*-
"""Utilidades compartidas por consulta/atleta.py y consulta/pais.py."""

import os
import re
import sys
import time
import unicodedata

try:
    from bson.regex import Regex
    from pymongo import MongoClient
    from pymongo.errors import PyMongoError
except ImportError:  # pragma: no cover
    sys.exit("Falta pymongo. Instalar con:  pip install pymongo")

URI_DEFECTO = os.environ.get("MONGO_URI", "mongodb://admin:admin123@localhost:27017/")
BASE_DEFECTO = os.environ.get("MONGO_BASE", "olimpiadas")

MEDALLAS = {"gold": "Gold", "oro": "Gold", "silver": "Silver", "plata": "Silver",
            "bronze": "Bronze", "bronce": "Bronze"}
NOMBRE_MEDALLA = {"Gold": "Oro", "Silver": "Plata", "Bronze": "Bronce"}

# Salida UTF-8 también en la consola de Windows
for flujo in (sys.stdout, sys.stderr):
    if hasattr(flujo, "reconfigure"):
        flujo.reconfigure(encoding="utf-8", errors="replace")


def normalizar(texto):
    """Minúsculas, sin tildes y sin espacios duplicados (igual que la carga)."""
    texto = unicodedata.normalize("NFKD", str(texto or ""))
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", texto.replace("•", " ").strip().lower())


def filtro_nombre(texto):
    """Filtro por palabras del nombre: cada palabra buscada es prefijo de alguna palabra
    de `palabras_nombre` (índice multikey ix_atletas_palabras)."""
    palabras = sorted({p for p in re.split(r"[^a-z0-9]+", normalizar(texto)) if p}, key=len, reverse=True)
    if not palabras:
        sys.exit("El nombre buscado no tiene letras ni números")
    return {"palabras_nombre": {"$all": [Regex("^" + re.escape(p)) for p in palabras]}}


def args_conexion(ap):
    ap.add_argument("--uri", default=URI_DEFECTO, help="URI de MongoDB (o variable MONGO_URI)")
    ap.add_argument("--base", default=BASE_DEFECTO, help="Base de datos (o variable MONGO_BASE)")
    ap.add_argument("--explain", action="store_true",
                    help="Muestra el plan de ejecución (executionStats) de las consultas")


def conectar(args):
    try:
        cliente = MongoClient(args.uri, serverSelectionTimeoutMS=5000)
        cliente.admin.command("ping")
    except PyMongoError as exc:
        sys.exit(f"No se pudo conectar a MongoDB ({args.uri}): {exc}\n"
                 "¿Está levantado el contenedor? docker start mongodb_olimpiadas")
    return cliente[args.base]


def medalla_param(valor):
    if valor is None:
        return None
    if valor.lower() in ("todas", "any", "si", "cualquiera"):
        return ["Gold", "Silver", "Bronze"]
    try:
        return [MEDALLAS[valor.lower()]]
    except KeyError:
        sys.exit(f"Medalla no válida: {valor} (use Gold/Silver/Bronze, oro/plata/bronce o 'todas')")


def filtro_participacion(args, pais=None):
    """Condición sobre un elemento de `participaciones` a partir de los parámetros."""
    cond = {}
    if pais:
        cond["pais"] = pais
    if getattr(args, "anio", None):
        cond["anio"] = args.anio
    elif getattr(args, "desde", None) or getattr(args, "hasta", None):
        cond["anio"] = {k: v for k, v in (("$gte", args.desde), ("$lte", args.hasta)) if v}
    if getattr(args, "deporte", None):
        cond["deporte"] = {"$regex": re.escape(args.deporte), "$options": "i"}
    if getattr(args, "evento", None):
        cond["evento"] = {"$regex": re.escape(args.evento), "$options": "i"}
    if getattr(args, "temporada", None):
        cond["temporada"] = {"$regex": f"^{re.escape(args.temporada)}", "$options": "i"}
    medallas = medalla_param(getattr(args, "medalla", None))
    if medallas:
        cond["medalla"] = {"$in": medallas}
    return cond


def cond_expr(cond, var="$$p"):
    """Traduce la condición de `filtro_participacion` a expresión de $filter."""
    expr = []
    for campo, valor in cond.items():
        ref = f"{var}.{campo}"
        if isinstance(valor, dict) and "$regex" in valor:
            expr.append({"$regexMatch": {"input": {"$ifNull": [ref, ""]},
                                         "regex": valor["$regex"], "options": valor.get("$options", "")}})
        elif isinstance(valor, dict) and "$in" in valor:
            expr.append({"$in": [ref, valor["$in"]]})
        elif isinstance(valor, dict):
            expr.extend({op: [ref, v]} for op, v in valor.items())
        else:
            expr.append({"$eq": [ref, valor]})
    return {"$and": expr} if expr else True


class Cronometro:
    def __init__(self):
        self.ms = 0.0

    def __call__(self, funcion, *a, **kw):
        t = time.perf_counter()
        r = funcion(*a, **kw)
        if hasattr(r, "__iter__") and not isinstance(r, (dict, list, str)):
            r = list(r)
        self.ms += (time.perf_counter() - t) * 1000
        return r


def explicar(db, coleccion, pipeline, titulo):
    """Imprime el resumen de explain('executionStats') de un aggregate."""
    plan = db.command({"explain": {"aggregate": coleccion, "pipeline": pipeline, "cursor": {}},
                       "verbosity": "executionStats"})
    stats = plan.get("executionStats") or plan["stages"][0]["$cursor"]["executionStats"]
    ganador = plan.get("queryPlanner") or plan["stages"][0]["$cursor"]["queryPlanner"]
    etapas, indices = [], []

    def recorrer(nodo):
        if not isinstance(nodo, dict):
            return
        if "stage" in nodo:
            etapas.append(nodo["stage"])
        if "indexName" in nodo:
            indices.append(nodo["indexName"])
        if nodo.get("stage") in ("IDHACK", "EXPRESS_IXSCAN"):
            indices.append("_id_")
        for k in ("inputStage", "queryPlan"):
            recorrer(nodo.get(k))
        for hijo in nodo.get("inputStages", []):
            recorrer(hijo)

    recorrer(ganador.get("winningPlan"))
    print(f"\n[explain] {titulo} sobre '{coleccion}'")
    print(f"  plan: {' <- '.join(etapas)} | índice(s): {', '.join(indices) or 'NINGUNO (COLLSCAN)'}")
    print(f"  docs devueltos: {stats.get('nReturned'):,} | keys examinadas: {stats.get('totalKeysExamined'):,} "
          f"| docs examinados: {stats.get('totalDocsExamined'):,} | tiempo: {stats.get('executionTimeMillis')} ms")


def tabla(filas, columnas, ancho_max=None):
    """Imprime una tabla de texto. columnas = [(titulo, clave)]."""
    ancho_max = ancho_max or {}
    if not filas:
        print("  (sin registros)")
        return
    celdas = [[("" if f.get(k) is None else str(f.get(k))) for _, k in columnas] for f in filas]
    anchos = []
    for i, (titulo, clave) in enumerate(columnas):
        w = max([len(titulo)] + [len(c[i]) for c in celdas])
        anchos.append(min(w, ancho_max.get(clave, 60)))

    def corta(t, w):
        return t if len(t) <= w else t[: w - 1] + "…"

    print("  " + " | ".join(corta(t, w).ljust(w) for (t, _), w in zip(columnas, anchos)))
    print("  " + "-+-".join("-" * w for w in anchos))
    for c in celdas:
        print("  " + " | ".join(corta(t, w).ljust(w) for t, w in zip(c, anchos)))


def titulo(texto, car="="):
    print(f"\n{car * 78}\n{texto}\n{car * 78}")


def medallas_texto(m):
    return f"Oro {m.get('oro', 0)} | Plata {m.get('plata', 0)} | Bronce {m.get('bronce', 0)} | Total {m.get('total', 0)}"
