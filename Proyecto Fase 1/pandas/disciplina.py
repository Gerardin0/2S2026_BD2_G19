import pandas as pd

res = pd.read_csv('worked_datasets/resultsUnificado.csv', low_memory=False)

disciplina = (
    res[["discipline","event"]]
    .drop_duplicates()
    .sort_values(["discipline","event"])
    .reset_index(drop=True)
)

disciplina.insert(0, "id_disciplina", range(1, len(disciplina) + 1))
disciplina = disciplina.rename(columns={"discipline":"sport","event":"event_name"})

print(disciplina.head(10))

disciplina.to_csv('worked_datasets/tabla_disciplina.csv', index=False)