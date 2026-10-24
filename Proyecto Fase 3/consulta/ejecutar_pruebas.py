#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ejecutar_pruebas.py — Tarea C4: corre los casos de prueba de consulta/pruebas.md.

Cada caso ejecuta atleta.py o pais.py, verifica que la salida contenga (o no) los textos
esperados y guarda la salida completa con fecha y hora en
docs/logs/pruebas_consultas_<fecha>.log.

    python consulta/ejecutar_pruebas.py            # todos los casos
    python consulta/ejecutar_pruebas.py P05 P14    # solo algunos
"""

import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

AQUI = Path(__file__).resolve().parent

# (id, descripción, script, argumentos, debe contener, no debe contener)
CASOS = [
    ("P01", "Atleta por nombre exacto con tildes", "atleta", ["Érick Barrondo"],
     ["athlete_id 123159", "20 kilometres Race Walk", "Plata"], []),
    ("P02", "Sin tildes y palabras en otro orden", "atleta", ["barrondo erick"],
     ["Érick Barrondo  (athlete_id 123159)"], []),
    ("P03", "Nombre parcial (prefijo de palabra)", "atleta", ["phelp", "--max-atletas", "1"],
     ["atletas coinciden", "Michael Phelps  (athlete_id 93860)", "Oro 23 | Plata 3 | Bronce 2"], []),
    ("P04", "Atleta inexistente", "atleta", ["Zzyzx Qwerty"],
     ["No se encontró ningún atleta"], []),
    ("P05", "Nombre repetido (varios homónimos)", "atleta", ["John Smith", "--max-atletas", "1"],
     ["atletas coinciden", "← exacto", "(athlete_id 60764)"], []),
    ("P06", "Filtros año + medalla", "atleta", ["Michael Phelps", "--anio", "2008", "--medalla", "oro"],
     ["Participaciones : 8 de 30", "Medallas (filtro): Oro 8 | Plata 0 | Bronce 0"], []),
    ("P07", "Filtro sin coincidencias", "atleta", ["Michael Phelps", "--anio", "1990"],
     ["No se encontró ningún atleta", "con filtros"], []),
    ("P08", "Edición especial 1906 (Intercalated Games)", "atleta", ["Archie Hahn", "--anio", "1906"],
     ["1906 Intercalated Games (Athina, Special)", "100 metres, Men (Intercalated)"], []),
    ("P09", "Juegos Olímpicos de la Juventud (Youth)", "atleta", ["Alejandra Orozco"],
     ["2014 Summer (Nanjing, Youth)"], []),
    ("P10", "Corrección C3: atleta 2024 con su medalla", "atleta", ["Pierre Brol"],
     ["Trap, Men (Olympic)", "Bronce", "GUA - Guatemala"], []),
    ("P11", "Corrección C3: medalla ya no asignada a otra persona", "atleta", ["Shayna Jack"],
     ["AUS"], ["Trap, Men"]),
    ("P12", "País por código NOC", "pais", ["GUA"],
     ["Guatemala  (GUA)", "¿Ha sido sede?        : NO", "Oro 1 | Plata 1 | Bronce 1 | Total 3", "Adriana Ruano"], []),
    ("P13", "País por nombre (minúsculas)", "pais", ["guatemala"], ["Guatemala  (GUA)"], []),
    ("P14", "País inexistente", "pais", ["XYZ"], ["No existe ningún país"], []),
    ("P15", "País sin datos de población", "pais", ["URS", "--limite", "3"],
     ["Población             : sin datos", "SÍ, 1 vez", "Moskva"], []),
    ("P16", "País sede varias veces", "pais", ["USA", "--limite", "3"],
     ["SÍ, 8 veces", "St. Louis", "Salt Lake City"], []),
    ("P17", "Nombre de país ambiguo", "pais", ["Germany", "--limite", "2"],
     ["países coinciden", "FRG", "GDR"], []),
    ("P18", "Corrección C1: ROC unificado con RUS", "pais", ["ROC", "--anio", "2020", "--limite", "3"],
     ["unificado con RUS", "Russia  (RUS)", "Tokyo"], []),
    ("P19", "País en Juegos de la Juventud", "pais", ["GUA", "--anio", "2010"],
     ["Singapore", "Youth"], []),
    ("P20", "País + edición 1906", "pais", ["GRE", "--anio", "1906", "--limite", "3"],
     ["Intercalated Games", "Athina"], []),
    ("P21", "País con resultados y atletas filtrados", "pais", ["GUA", "--anio", "2024", "--atletas", "--resultados"],
     ["Participaciones y resultados (16)", "Atletas (16)", "Adriana Ruano"], []),
    ("P22", "País + rango + deporte", "pais", ["MEX", "--desde", "2000", "--hasta", "2020", "--deporte", "Diving"],
     ["Medallero con filtros", "Diving (Aquatics)"], []),
]


def main():
    seleccion = set(sys.argv[1:])
    inicio = datetime.now()
    destino = AQUI.parent / "docs" / "logs" / f"pruebas_consultas_{inicio:%Y%m%d_%H%M%S}.log"
    destino.parent.mkdir(parents=True, exist_ok=True)
    resultados = []
    with destino.open("w", encoding="utf-8") as log:
        log.write(f"PRUEBAS DE CONSULTAS — Fase 3 — inicio {inicio:%Y-%m-%d %H:%M:%S}\n")
        for cid, desc, script, argumentos, contiene, no_contiene in CASOS:
            if seleccion and cid not in seleccion:
                continue
            cmd = [sys.executable, str(AQUI / f"{script}.py"), *argumentos]
            t = time.perf_counter()
            r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
            seg = time.perf_counter() - t
            salida = r.stdout + r.stderr
            faltan = [c for c in contiene if c not in salida]
            sobran = [c for c in no_contiene if c in salida]
            ok = not faltan and not sobran
            resultados.append((cid, desc, ok))
            texto_cmd = f"python consulta/{script}.py " + " ".join(f'"{a}"' if " " in a else a for a in argumentos)
            print(f"{'OK   ' if ok else 'FALLA'} {cid} {desc}  ({seg:.1f}s)")
            if not ok:
                print(f"      faltan: {faltan}  no esperados: {sobran}")
            log.write(f"\n{'#' * 78}\n# {cid} — {desc}\n# [{datetime.now():%Y-%m-%d %H:%M:%S}] $ {texto_cmd}\n"
                      f"# resultado: {'OK' if ok else 'FALLA'} (espera: {contiene}"
                      f"{'; no debe contener: ' + str(no_contiene) if no_contiene else ''})\n{'#' * 78}\n{salida}")
        total_ok = sum(ok for *_, ok in resultados)
        resumen = f"\nRESUMEN: {total_ok}/{len(resultados)} casos OK — fin {datetime.now():%Y-%m-%d %H:%M:%S}\n"
        log.write(resumen)
    print(resumen + f"Bitácora: {destino}")
    return 0 if total_ok == len(resultados) else 1


if __name__ == "__main__":
    sys.exit(main())
