import pandas as pd

"""
resultsUnificado.py

Consolida results.csv (1896-2022) con las ediciones que solo existen en
olympics_dataset.csv (2024 en adelante, generadas por resultados_2024.py) y
enriquece con las variables medidas (Age, Height, Weight, City, team).

Orden de ejecucion del pipeline:
    roles.py -> resultados_2024.py -> results.py -> resultsUnificado.py
             -> disciplina.py -> edicion_juego.py -> participacion.py
             -> atletas.py -> poblaciones.py -> carga/ETL_Limpieza_Carga.py
"""

import os

import pandas as pd

R24 = "worked_datasets/resultados_2024.csv"

rf = pd.read_csv("worked_datasets/resultsFull.csv", low_memory=False)
ae = pd.read_csv("datasets/athlete_events.csv", low_memory=False)
de = pd.read_csv("datasets/datalab_export_2026-08-31 18_07_14.csv", low_memory=False)
od = pd.read_csv("datasets/olympics_dataset.csv", low_memory=False)
bios = pd.read_csv("datasets/bios.csv", low_memory=False)

# datalab_export usa "null" como string y nombres de columnas en minúscula
de = de.replace("null", pd.NA)
de = de.rename(columns={
    "id": "ID", "name": "Name", "sex": "Sex", "age": "Age", "height": "Height",
    "weight": "Weight", "team": "Team", "noc": "NOC", "games": "Games",
    "year": "Year", "season": "Season", "city": "City", "sport": "Sport",
    "event": "Event", "medal": "Medal",
})
de["Age"] = pd.to_numeric(de["Age"], errors="coerce")
de["Height"] = pd.to_numeric(de["Height"], errors="coerce")
de["Weight"] = pd.to_numeric(de["Weight"], errors="coerce")

# olympics_dataset usa "No medal" en vez de NaN
od["Medal"] = od["Medal"].replace("No medal", pd.NA)

# normalizar nombres (espacios extra) para mejorar el match por nombre
for df, col in [(rf, "as"), (ae, "Name"), (de, "Name"), (od, "Name")]:
    df[col] = df[col].astype(str).str.strip()


#    datalab_export es un subconjunto de athlete_events
cols_comunes = ["ID", "Name", "Age", "Team", "NOC", "Year", "Season", "City"]
ae_consolidado = (
    pd.concat([ae[cols_comunes], de[cols_comunes]], ignore_index=True)
    .drop_duplicates(subset=["Name", "Year", "NOC", "Age", "City"])
)

# tabla de enriquecimiento por (Name, Year, NOC): toma el primer valor no nulo
enrich_ae = (
    ae_consolidado
    .groupby(["Name", "Year", "NOC", "Season"], as_index=False)
    .agg({"Age": "first", "City": "first"})
)


resultado = rf.merge(
    enrich_ae,
    left_on=["as", "year", "noc", "type"],
    right_on=["Name", "Year", "NOC", "Season"],
    how="left",
).drop(columns=["Name", "Year", "NOC", "Season"])
 

bios_hw = (
    bios[["athlete_id", "height_cm", "weight_kg"]]
    .rename(columns={"height_cm": "Height", "weight_kg": "Weight"})
    .drop_duplicates(subset=["athlete_id"])
)
resultado = resultado.merge(bios_hw, on="athlete_id", how="left")

enrich_hw = (
    pd.concat([ae[["Name", "NOC", "Height", "Weight"]],
               de[["Name", "NOC", "Height", "Weight"]]], ignore_index=True)
    .dropna(subset=["Height", "Weight"], how="all")
    .groupby(["Name", "NOC"], as_index=False)
    .agg({"Height": "first", "Weight": "first"})
    .rename(columns={"Height": "Height_fb", "Weight": "Weight_fb"})
)
resultado = resultado.merge(
    enrich_hw, left_on=["as", "noc"], right_on=["Name", "NOC"], how="left"
).drop(columns=["Name", "NOC"])
resultado["Height"] = resultado["Height"].fillna(resultado["Height_fb"])
resultado["Weight"] = resultado["Weight"].fillna(resultado["Weight_fb"])
resultado = resultado.drop(columns=["Height_fb", "Weight_fb"])


enrich_od = (
    od.groupby(["Name", "Year", "NOC", "Season"], as_index=False)
    .agg({"City": "first", "Team": "first"})
    .rename(columns={"City": "City_od", "Team": "Team_od"})
)
resultado = resultado.merge(
    enrich_od, left_on=["as", "year", "noc", "type"],
    right_on=["Name", "Year", "NOC", "Season"], how="left"
).drop(columns=["Name", "Year", "NOC", "Season"])
resultado["City"] = resultado["City"].fillna(resultado["City_od"])
resultado["team"] = resultado["team"].fillna(resultado["Team_od"])
resultado = resultado.drop(columns=["City_od", "Team_od"])


# ---------------------------------------------------------------------------
# 2024 en adelante:-olympics_dataset.csv es la unica fuente con estas ediciones
# ---------------------------------------------------------------------------
if os.path.exists(R24):
    r24 = pd.read_csv(R24, low_memory=False)
    r24 = r24.rename(columns={"city": "City"})
    print(f"resultados_2024.csv: {len(r24)} filas, anios {sorted(r24['year'].dropna().unique())}")
    resultado = pd.concat([resultado, r24], ignore_index=True, sort=False)
else:
    print("AVISO: no existe worked_datasets/resultados_2024.csv "
          "(correr antes pandas/resultados_2024.py); el pipeline quedara sin 2024.")

columnas_finales = [
    "athlete_id", "as", "year", "type", "discipline", "event", "noc", "team",
    "place", "tied", "medal", "Age", "Height", "Weight", "City",
]
resultado = resultado[columnas_finales]
resultado.to_csv("worked_datasets/resultsUnificado.csv", index=False)

print("Filas totales:", len(resultado))
print(resultado[["Age", "Height", "Weight", "City"]].notna().sum())
print("\nParticipaciones por anio (ultimos 10):")
print(resultado.groupby("year").size().tail(10))