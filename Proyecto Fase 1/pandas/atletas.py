"""
atletas.py

Construye tabla_atletas.csv (fichas de bios.csv + biosComplejo.csv) y la tabla
intermedia tabla_atleta_rol.csv.

Ademas incorpora los atletas que unicamente compiten en las ediciones que no
estan en results.csv (2024). Esos no tienen ficha en bios.csv, asi que se
agregan con los campos disponibles desde resultados_2024.py.

Orden de ejecucion: roles.py -> resultados_2024.py -> atletas.py
"""

import os

import pandas as pd

ATLETAS_NUEVAS_2024 = "worked_datasets/tabla_atletas_nuevas_2024.csv"

bios = pd.read_csv('datasets/bios.csv', low_memory=False)
bios_locs = pd.read_csv('datasets/bios_locs.csv', low_memory=False)
bios_norm = pd.read_csv('worked_datasets/biosNormalizado1.csv', low_memory=False)

df_bios_sel = bios[[
    'athlete_id', 'name', 'born_date', 'born_city',
    'born_region', 'born_country', 'died_date'
]]

df_locs_sel = bios_locs[[
    'athlete_id', 'lat', 'long'
]]

df_norm_sel = bios_norm[[
    'athlete_id', 'Sex', 'Full name', 'died_in', 'Affiliations',
    'Nick/petnames', 'Title(s)', 'Other names', 'Nationality',
    'Original name', 'Name order', 'rol_id'
]]

tabla_roles = ['athlete_id', 'rol_id']

df_roles = df_norm_sel[tabla_roles]
df_roles = df_roles.drop_duplicates()
df_roles.insert(0, "id_atleta_rol", range(1, len(df_roles) + 1))

df_cruzado = df_norm_sel.merge(df_bios_sel, on='athlete_id', how='left').merge(df_locs_sel, on='athlete_id', how='left')
df_cruzado = df_cruzado.drop(columns=['rol_id'])
df_cruzado = df_cruzado.drop_duplicates()

print("Dataset info:")
print("Filas totales:", len(df_cruzado))
print("\nDataset cruzado:")
print(df_cruzado.head(10))

# ---------------------------------------------------------------------------
# Atletas que solo aparecen en 2024 (sin ficha en bios.csv)
# ---------------------------------------------------------------------------
if os.path.exists(ATLETAS_NUEVAS_2024):
        # athlete_id ya es unico (incluso entre homonimos de paises distintos),
    # asi que no hace falta deduplicar por nombre.
    nuevas = pd.read_csv(ATLETAS_NUEVAS_2024, low_memory=False)

    comunes = [c for c in df_cruzado.columns if c in nuevas.columns]
    nuevas = nuevas[comunes + [c for c in nuevas.columns if c not in comunes]]
    nuevas = nuevas.reindex(columns=df_cruzado.columns)
    # Sin roles en la fuente: se deja vacio y el ETL no inserta en atleta_roles.
    nuevas["rol_id"] = pd.NA

    df_cruzado = pd.concat([df_cruzado, nuevas], ignore_index=True, sort=False)
    print(f"\nAtletas agregados desde 2024: {len(nuevas)}")
else:
    print("\nAVISO: no existe worked_datasets/tabla_atletas_nuevas_2024.csv "
          "(correr antes pandas/resultados_2024.py); el pipeline quedara sin "
          "los atletas que solo compitieron en 2024.")

print("Filas totales (final):", len(df_cruzado))

df_cruzado.to_csv('worked_datasets/tabla_atletas.csv', index=False)
df_roles.to_csv('worked_datasets/tabla_atleta_rol.csv', index=False)