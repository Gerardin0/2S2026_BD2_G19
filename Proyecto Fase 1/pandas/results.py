import pandas as pd

df_results = pd.read_csv('datasets/results.csv', low_memory=False)
df_complejo = pd.read_csv('datasets/resultsComplejo.csv', low_memory=False)

df_results['games_name'] = df_complejo['Games']

column_order = [
    'year', 'type', 'games_name', 'discipline', 
    'event', 'as', 'athlete_id', 'noc', 
    'team', 'place', 'tied', 'medal'
]
df_final = df_results[column_order]

mask_missing = df_final['year'].isna() | df_final['type'].isna()

splitted = df_final.loc[mask_missing, 'games_name'].str.split(' ', n=1, expand = True)

df_final.loc[mask_missing, 'year'] = splitted[0].str[:4].astype('Int64')
df_final.loc[mask_missing, 'type'] = splitted[1]
df_final = df_final.drop(columns=['games_name'])

df_final.to_csv('worked_datasets/resultsFull.csv', index=False)