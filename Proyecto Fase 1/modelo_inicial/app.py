import pandas as pd

files = {
    # Fuente 1
    'Fuente 1 - results': 'Fuente1/Olympics-Dataset/clean-data/results.csv',
    'Fuente 1 - noc_regions': 'Fuente1/Olympics-Dataset/clean-data/noc_regions.csv',
    'Fuente 1 - populations': 'Fuente1/Olympics-Dataset/clean-data/populations.csv',
    'Fuente 1 - bios': 'Fuente1/Olympics-Dataset/clean-data/bios.csv',
    # Fuente 2
    'Fuente 2 - athlete_events': 'Fuente2/athlete_events.csv',
    # Fuente 3
    'Fuente 3 - olympics_dataset': 'Fuente3/olympics_dataset.csv',
    # Fuente 4
    'Fuente 4 - athlete_events': 'Fuente4/athlete_events.csv'
}


for name, path in files.items():
    print(f"\n*********** ANALIZANDO: {name} ***********")
    print(f"Ruta: {path}")
    
    try:
        df = pd.read_csv(path, encoding='utf-8', keep_default_na=True)
    except UnicodeDecodeError:
        df = pd.read_csv(path, encoding='latin-1', keep_default_na=True)
    except FileNotFoundError:
        print(f"ERROR: Archivo no encontrado en la ruta especificada.\n")
        continue

    total_filas = len(df)
    total_cols = len(df.columns)
    print(f"Dimensiones: {total_filas:,} filas | {total_cols} columnas")
    print(f"Columnas: {list(df.columns)}")

    print("\n--- 1. Conteo y Porcentaje de Valores Nulos ---")
    null_counts = df.isnull().sum()
    null_pct = (df.isnull().mean() * 100).round(2)
    null_summary = pd.DataFrame({
        'Nulos': null_counts,
        'Porcentaje (%)': null_pct
    })
    
    nulos_existentes = null_summary[null_summary['Nulos'] > 0]
    if not nulos_existentes.empty:
        print(nulos_existentes)
    else:
        print("No se encontraron valores nulos (NaN).")

    print("-" * 80)