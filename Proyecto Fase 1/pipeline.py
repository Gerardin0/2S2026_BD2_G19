"""
pipeline.py

Ejecuta todo el pipeline en el orden correcto y deja listos los CSV de
worked_datasets/ para la carga en SQL Server.

    python3 pipeline.py
    python3 carga/ETL_Limpieza_Carga.py --data-dir worked_datasets --dry-run
    python3 carga/ETL_Limpieza_Carga.py --data-dir worked_datasets --password '...'

Orden (las dependencias importan):

    roles.py            normaliza biosComplejo -> biosNormalizado1 + tabla_rol
    resultados_2024.py  2024 desde olympics_dataset + atletas nuevos + NOC nuevos
    results.py          results.csv -> resultsFull.csv
    resultsUnificado.py consolida todo -> resultsUnificado.csv
    disciplina.py       -> tabla_disciplina.csv
    edicion_juego.py    -> tabla_edicion_juego.csv
    participacion.py    -> tabla_participacion.csv + tabla_resultado.csv
    atletas.py          -> tabla_atletas.csv + tabla_atleta_rol.csv
    poblaciones.py      -> tabla_poblaciones.csv (incluye 2024 estimado)
"""

import runpy
import sys
import time

PASOS = [
    "pandas/roles.py",
    "pandas/resultados_2024.py",
    "pandas/results.py",
    "pandas/resultsUnificado.py",
    "pandas/disciplina.py",
    "pandas/edicion_juego.py",
    "pandas/participacion.py",
    "pandas/atletas.py",
    "pandas/poblaciones.py",
]


def main():
    t0 = time.time()
    for paso in PASOS:
        print(f"\n{'=' * 70}\n>>> {paso}\n{'=' * 70}")
        inicio = time.time()
        runpy.run_path(paso, run_name="__main__")
        print(f"--- {paso}: {time.time() - inicio:.1f}s")
    print(f"\nPipeline completo en {time.time() - t0:.1f}s")
    print("Siguiente paso: carga/ETL_Limpieza_Carga.py")


if __name__ == "__main__":
    sys.exit(main())