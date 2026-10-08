import pandas as pd

res = pd.read_csv('worked_datasets/resultsUnificado.csv', low_memory=False)
disciplina = pd.read_csv('worked_datasets/tabla_disciplina.csv', low_memory=False)
edicion = pd.read_csv('worked_datasets/tabla_edicion_juego.csv', low_memory=False)

participacion = res.merge(edicion, left_on=["year","type"], right_on=["year","season"], how='left')

participacion = participacion.merge(disciplina, left_on=["discipline","event"], right_on=["sport","event_name"], how="left")
participacion.insert(0, "id_participacion", range(1, len(participacion) + 1))

columnas_finales = ['id_participacion','athlete_id','id_edicion_juego','id_disciplina','noc','team','as','Age', 'Height', 'Weight']
columnas_resultado = ['id_participacion', 'place', 'tied', 'medal']

resultado = participacion[columnas_resultado]
resultado.insert(0, "id_resultado", range(1, len(resultado) + 1))

participacion = participacion[columnas_finales]

participacion = participacion.rename(columns={"noc":"noc_code", "Age":"age", "as":"presentado_como", "Height": "height_cm", "Weight": "weight_kg"})

print(participacion.head(10))
print(resultado.head(10))

participacion.to_csv('worked_datasets/tabla_participacion.csv', index=False)
resultado.to_csv('worked_datasets/tabla_resultado.csv', index=False)
