#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
medir_rendimiento.py — Tarea C3: mide las consultas (c) y (d) con explain("executionStats").

Ejecuta cada caso `--repeticiones` veces (defecto 5), toma el tiempo de base de datos que
reporta el script ("consulta resuelta en X ms") y el plan de cada aggregate, y escribe una
tabla Markdown en pantalla y en docs/logs/rendimiento_consultas_<fecha>.log.

    python consulta/medir_rendimiento.py [--repeticiones 5]
"""

import argparse
import re
import statistics
import subprocess
import sys
from datetime import datetime
from pathlib import Path

AQUI = Path(__file__).resolve().parent
CASOS = [
    ("atleta", ["Michael Phelps"]),
    ("atleta", ["erick barrondo"]),
    ("atleta", ["Phelps", "--deporte", "swim", "--anio", "2008", "--medalla", "oro"]),
    ("atleta", ["usain bolt", "--pais", "JAM", "--desde", "2008", "--hasta", "2016"]),
    ("atleta", ["maria", "--max-atletas", "1"]),
    ("atleta", ["john smith"]),
    ("pais", ["GUA"]),
    ("pais", ["Guatemala"]),
    ("pais", ["USA"]),
    ("pais", ["USA", "--anio", "2008"]),
    ("pais", ["MEX", "--desde", "2000", "--hasta", "2020", "--deporte", "Diving"]),
    ("pais", ["USA", "--deporte", "Athletics", "--atletas", "--resultados"]),
    ("pais", ["GBR", "--medalla", "oro"]),
]


def correr(script, argumentos):
    r = subprocess.run([sys.executable, str(AQUI / f"{script}.py"), *argumentos, "--explain"],
                       capture_output=True, text=True, encoding="utf-8")
    salida = r.stdout + r.stderr
    ms = re.search(r"consulta(?: resuelta en|:) (\d+) ms", salida)
    planes = re.findall(r"índice\(s\): ([^\n]+)\n\s+docs devueltos: ([\d,]+) \| keys examinadas: ([\d,]+) "
                        r"\| docs examinados: ([\d,]+)", salida)
    return (int(ms.group(1)) if ms else None), planes, salida


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repeticiones", type=int, default=5)
    args = ap.parse_args()

    inicio = datetime.now()
    lineas = [f"# Rendimiento de consultas — {inicio:%Y-%m-%d %H:%M:%S}", "",
              f"Repeticiones por caso: {args.repeticiones} (tiempo = suma de las consultas a MongoDB del script)", "",
              "| Comando | Mín ms | Prom ms | Máx ms | Índices usados | keys / docs examinados (por etapa) | COLLSCAN |",
              "| --- | ---: | ---: | ---: | --- | --- | --- |"]
    for script, argumentos in CASOS:
        tiempos, planes = [], []
        for _ in range(args.repeticiones):
            ms, planes, salida = correr(script, argumentos)
            if ms is None:
                print(salida)
                sys.exit(f"Falló: {script} {argumentos}")
            tiempos.append(ms)
        indices = sorted({p[0] for p in planes})
        examinados = "; ".join(f"{p[2]} / {p[3]}" for p in planes)
        collscan = "SÍ" if any("COLLSCAN" in p[0] for p in planes) else "no"
        cmd = f"`{script}.py " + " ".join(f'"{a}"' if " " in a else a for a in argumentos) + "`"
        lineas.append(f"| {cmd} | {min(tiempos)} | {statistics.mean(tiempos):.0f} | {max(tiempos)} | "
                      f"{', '.join(indices)} | {examinados} | {collscan} |")
        print(lineas[-1])

    destino = AQUI.parent / "docs" / "logs" / f"rendimiento_consultas_{inicio:%Y%m%d_%H%M%S}.log"
    destino.parent.mkdir(parents=True, exist_ok=True)
    destino.write_text("\n".join(lineas) + "\n", encoding="utf-8")
    print(f"\nBitácora: {destino}")


if __name__ == "__main__":
    main()
