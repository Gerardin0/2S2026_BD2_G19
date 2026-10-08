import pandas as pd
 
res = pd.read_csv('worked_datasets/resultsUnificado.csv', low_memory=False)
 
def ciudad_representativa(s):
    s = s.dropna()
    if s.empty:
        return pd.NA
    return s.mode().iloc[0]
 
edicion_juego = (
    res.groupby(["year", "type"], as_index=False)
       .agg(ciudad=("City", ciudad_representativa))
       .sort_values(["year", "type"])
       .reset_index(drop=True)
)
 
edicion_juego.insert(0, "id_edicion_juego", range(1, len(edicion_juego) + 1))
edicion_juego = edicion_juego.rename(columns={"year": "year", "type": "season", "ciudad": "city"})
 
print(edicion_juego.head(10))

edicion_juego.to_csv('worked_datasets/tabla_edicion_juego.csv', index=False)
