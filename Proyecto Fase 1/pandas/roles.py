import pandas as pd

df = pd.read_csv('datasets/biosComplejo.csv')

df['Roles'] = df['Roles'].fillna('').astype(str).str.split('•')

df['Died'] = df['Died'].fillna('').astype(str)

df_exploded = df.explode('Roles').copy()

df_exploded = df_exploded.join(df_exploded['Died'].str.split(",", n=1, expand=True).rename(columns={0:"died_date",1:"died_in"}))

df_exploded['Roles'] = df_exploded['Roles'].str.strip()

df_exploded = df_exploded[df_exploded['Roles'] != '']

roles_unicos = df_exploded['Roles'].unique()
tabla_rol = pd.DataFrame({
    'rol_id': range(1, len(roles_unicos) + 1),
    'nombre_rol': roles_unicos
})

df_final = df_exploded.merge(
    tabla_rol, 
    left_on='Roles', 
    right_on='nombre_rol', 
    how='left'
)

df_final = df_final.drop(columns=['Roles', 'nombre_rol', 'Died'])

print("--- TABLA CATÁLOGO: ROL ---")
print(tabla_rol)

print("\n--- TABLA PRINCIPAL NORMALIZADA (Primeros registros) ---")
print(df_final.head(10))

#Exportar a csv
tabla_rol.to_csv('worked_datasets/tabla_rol.csv', index=False)
df_final.to_csv('worked_datasets/biosNormalizado1.csv', index=False)