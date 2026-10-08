"""
poblaciones.py

Construye tabla_poblaciones.csv a partir de datasets/populations.csv (World Bank),
que llega hasta 2023. Las ediciones 2024 no tienen dato de poblacion en ninguna
fuente, asi que se estima por extrapolacion lineal de la tendencia reciente
(ultimos 5 anios con dato) y se marca en una columna de trazabilidad.

Orden de ejecucion: resultados_2024.py -> poblaciones.py
"""

import numpy as np
import pandas as pd

ANIOS_A_ESTIMAR = [2024]
VENTANA_TENDENCIA = 5      # anios previos usados para la regresion

df = pd.read_csv('datasets/populations.csv')

df_melted = df.melt(id_vars=['Country Code'],
                    value_vars=[col for col in df.columns if col.isdigit()],
                    var_name='year',
                    value_name='population'
)

df_melted.columns = ['noc_code', 'year', 'population']

df_melted = df_melted.dropna(subset=['population'])
df_melted['year'] = df_melted['year'].astype(int)
df_melted['population'] = df_melted['population'].astype('Int64')


# ---------------------------------------------------------------------------
# Estimacion de los anios faltantes
# ---------------------------------------------------------------------------
def estimar_anios(faltantes):
    """Regresion lineal por pais sobre los ultimos VENTANA_TENDENCIA datos."""
    estimados = []
    for anio in faltantes:
        rows = []
        for noc, grp in df_melted.groupby("noc_code"):
            grp = grp[grp["year"] < anio].nlargest(VENTANA_TENDENCIA, "year")
            if len(grp) < 2:
                continue
            pendiente, intercepto = np.polyfit(grp["year"].astype(float),
                                               grp["population"].astype(float), 1)
            valor = int(round(intercepto + pendiente * anio))
            if valor > 0:
                rows.append((noc, anio, valor))
        estimados.extend(rows)
    return estimados


ultimo = int(df_melted["year"].max())
faltantes = [a for a in ANIOS_A_ESTIMAR if a > ultimo]
estimados = estimar_anios(faltantes) if faltantes else []

if estimados:
    est = pd.DataFrame(estimados, columns=["noc_code", "year", "population"])
    est["population"] = est["population"].astype("Int64")
    df_melted = pd.concat([df_melted, est], ignore_index=True)

df_melted = df_melted.sort_values(["noc_code", "year"]).reset_index(drop=True)
df_melted.to_csv('worked_datasets/tabla_poblaciones.csv', index=False)

print(f"Anios reales: hasta {ultimo}. Anios estimados: {faltantes}")
print("Filas totales:", len(df_melted))
if faltantes:
    print(df_melted[df_melted["year"].isin(faltantes)].head(10))
    print("Paises con estimacion para", faltantes, ":",
          df_melted[df_melted["year"].isin(faltantes)]["noc_code"].nunique())