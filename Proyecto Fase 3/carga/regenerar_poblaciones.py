#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
import sys
from pathlib import Path

def main():
    # 1. Definir rutas relativas desde el directorio raíz del proyecto
    raiz_repo = Path(__file__).resolve().parents[2]
    ruta_iso_noc = Path(__file__).resolve().parents[1] / "fuentes" / "iso3_noc.csv"
    
    ruta_pob_in = raiz_repo / "Proyecto Fase 1" / "worked_datasets" / "tabla_poblaciones.csv"
    ruta_pob_out = Path(__file__).resolve().parents[1] / "fuentes" / "tabla_poblaciones_mapeada.csv"
    
    # Validar que los archivos de entrada existan
    if not ruta_iso_noc.exists() or not ruta_pob_in.exists():
        print(f"Error: Faltan archivos de entrada.\nBuscando:\n - {ruta_iso_noc}\n - {ruta_pob_in}")
        sys.exit(1)

    # 2. Cargar el diccionario de mapeo ISO-3 -> NOC
    mapa_iso_noc = {}
    with open(ruta_iso_noc, mode='r', encoding='utf-8') as f_iso:
        lector_iso = csv.reader(f_iso)
        next(lector_iso, None)  # Saltar cabecera si la tiene (ISO,NOC)
        for fila in lector_iso:
            if len(fila) >= 2:
                iso3, noc = fila[0].strip(), fila[1].strip()
                mapa_iso_noc[iso3] = noc
                
    print(f"Diccionario cargado: {len(mapa_iso_noc)} mapeos ISO-3 a NOC encontrados.")

    # 3. Procesar poblaciones y generar el nuevo archivo
    filas_procesadas = 0
    filas_mapeadas = 0
    
    # Asegurar que el directorio de salida exista
    ruta_pob_out.parent.mkdir(parents=True, exist_ok=True)
    
    with open(ruta_pob_in, mode='r', encoding='utf-8') as f_in, \
         open(ruta_pob_out, mode='w', encoding='utf-8', newline='') as f_out:
        
        lector_pob = csv.reader(f_in)
        escritor_pob = csv.writer(f_out)
        
        # Leer y escribir cabecera, cambiando ISO-3 por noc_code
        cabecera = next(lector_pob)
        # Asumiendo que la cabecera original es algo como: [iso_code, anio, poblacion]
        # Forzamos el nombre de la primera columna para que sea 'noc_code'
        cabecera[0] = 'noc_code' 
        escritor_pob.writerow(cabecera)
        
        for fila in lector_pob:
            filas_procesadas += 1
            iso_origen = fila[0].strip()
            
            # Si el ISO existe en el diccionario (excepciones), lo reemplazamos. 
            # Si no, asumimos que el ISO-3 es igual al NOC (ej. USA == USA).
            if iso_origen in mapa_iso_noc:
                fila[0] = mapa_iso_noc[iso_origen]
            
            # Escribimos la fila (ya sea modificada o con el ISO original que sirve de NOC)
            escritor_pob.writerow(fila)
            filas_mapeadas += 1

    # 4. Imprimir reporte final de validación (P3 pide llegar a ~12,740)
    print("-" * 40)
    print("REPORTE DE EXPANSIÓN DE POBLACIONES")
    print("-" * 40)
    print(f"Filas originales procesadas : {filas_procesadas:,}")
    print(f"Filas mapeadas con NOC (Out): {filas_mapeadas:,}")
    print(f"Archivo generado con éxito en : {ruta_pob_out}")

if __name__ == "__main__":
    main()