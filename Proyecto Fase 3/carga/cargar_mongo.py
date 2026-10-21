#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
from pymongo import MongoClient, UpdateOne
from pathlib import Path
from datetime import datetime
import sys

def limpiar_nan(valor):
    """Convierte NaN de pandas a None para compatibilidad con BSON de MongoDB"""
    if pd.isna(valor):
        return None
    return valor

def main():
    inicio = datetime.now()
    raiz = Path(__file__).resolve().parents[1]
    dir_fase1 = raiz.parent / "Proyecto Fase 1" / "worked_datasets"
    dir_fuentes = raiz / "fuentes"
    dir_logs = raiz / "docs" / "logs"
    dir_logs.mkdir(parents=True, exist_ok=True)
    
    log_file = dir_logs / f"carga_mongo_{inicio.strftime('%Y%m%d_%H%M%S')}.log"
    
    def log(mensaje):
        out = f"[{datetime.now().strftime('%H:%M:%S')}] {mensaje}"
        print(out)
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(out + "\n")

    log("=== INICIANDO ETL A MONGODB ===")

    # ---------------------------------------------------------
    # 1. EXTRACCIÓN (Lectura de CSVs)
    # ---------------------------------------------------------
    log("Extrayendo datasets...")
    try:
        df_atletas = pd.read_csv(dir_fase1 / "tabla_atletas.csv")
        df_participacion = pd.read_csv(dir_fase1 / "tabla_participacion.csv")
        df_resultado = pd.read_csv(dir_fase1 / "tabla_resultado.csv")
        df_disciplina = pd.read_csv(dir_fase1 / "tabla_disciplina.csv")
        df_edicion = pd.read_csv(dir_fase1 / "tabla_edicion_juego.csv")
        df_nocs = pd.read_csv(dir_fase1 / "tabla_nocs.csv")
        df_rol = pd.read_csv(dir_fase1 / "tabla_rol.csv")
        df_atleta_rol = pd.read_csv(dir_fase1 / "tabla_atleta_rol.csv")
        
        df_poblaciones = pd.read_csv(dir_fuentes / "tabla_poblaciones_mapeada.csv")
        df_sedes = pd.read_csv(dir_fuentes / "ediciones_sede.csv")
    except Exception as e:
        log(f"Error al leer archivos: {e}")
        sys.exit(1)

    # ---------------------------------------------------------
    # 2. TRANSFORMACIÓN
    # ---------------------------------------------------------
    log("Transformando datos y aplicando correcciones...")

    # Extraer el NOC base para cada atleta desde sus participaciones
    nocs_de_participacion = df_participacion.groupby('athlete_id')['noc_code'].last().reset_index()
    df_atletas = df_atletas.merge(nocs_de_participacion, on="athlete_id", how="left")

    # P4: Corrección de NOCs faltantes y mapeos especiales
    def corregir_noc(noc):
        if pd.isna(noc) or str(noc).strip() == "":
            return "SWE" # Por defecto los 237 sin participaciones
        if noc == "ROC": return "RUS"
        if noc == "COR": return "KOR"
        return noc
    
    df_atletas['noc_code'] = df_atletas['noc_code'].apply(corregir_noc)

    # Limpieza técnica: Remover viñetas reemplazando por espacio
    df_atletas['Full name'] = df_atletas['Full name'].str.replace(r'[•·]', ' ', regex=True)
    df_atletas['name'] = df_atletas['name'].str.replace(r'[•·]', ' ', regex=True)
    
    # Remover comillas (dobles/simples) y paréntesis que ensucian la búsqueda
    df_atletas['Full name'] = df_atletas['Full name'].str.replace(r'["\'\(\)]', '', regex=True)
    df_atletas['name'] = df_atletas['name'].str.replace(r'["\'\(\)]', '', regex=True)
    
    # Limpiar posibles espacios dobles generados por los reemplazos
    df_atletas['Full name'] = df_atletas['Full name'].str.replace(r'\s+', ' ', regex=True).str.strip()
    df_atletas['name'] = df_atletas['name'].str.replace(r'\s+', ' ', regex=True).str.strip()

    # Preparar participaciones con datos embebidos
    df_part_full = df_participacion.merge(df_resultado, on="id_participacion", how="left")
    df_part_full = df_part_full.merge(df_edicion, on="id_edicion_juego", how="left")
    df_part_full = df_part_full.merge(df_disciplina, on="id_disciplina", how="left")
    
    # Agrupamientos en memoria para inyección rápida O(1)
    log("Agrupando roles por atleta...")
    df_roles_full = df_atleta_rol.merge(df_rol, left_on="rol_id", right_on="rol_id")
    roles_por_atleta = df_roles_full.groupby("athlete_id")["nombre_rol"].apply(list).to_dict()

    log("Agrupando participaciones por atleta y país...")
    parts_agrupadas = df_part_full.groupby('athlete_id')
    pob_por_pais = df_poblaciones.groupby("noc_code")[["year", "population"]].apply(lambda x: x.to_dict('records')).to_dict()
    sedes_por_pais = df_sedes.groupby("noc_sede")[["anio", "temporada", "ciudad", "categoria"]].apply(lambda x: x.to_dict('records')).to_dict()
    parts_por_pais = df_part_full.groupby('noc_code')[['year', 'sport', 'medal']].apply(lambda x: x.dropna(subset=['medal']).to_dict('records')).to_dict()

    # ---------------------------------------------------------
    # 3. CONSTRUCCIÓN DE DOCUMENTOS BSON
    # ---------------------------------------------------------
    docs_roles = [{"_id": r["rol_id"], "nombre": r["nombre_rol"], "descripcion": None} for _, r in df_rol.iterrows()]
    docs_disciplinas = [{
        "_id": r["id_disciplina"], 
        "deporte": str(r["sport"]) if pd.notna(r["sport"]) and str(r["sport"]).strip() != "" else "Desconocido", 
        "evento": str(r["event_name"]) if pd.notna(r["event_name"]) and str(r["event_name"]).strip() != "" else "Desconocido"
    } for _, r in df_disciplina.iterrows()]
    
    docs_ediciones = []
    df_ediciones_merge = df_edicion.merge(df_sedes, on="id_edicion_juego")
    for _, r in df_ediciones_merge.iterrows():
        # Casteo seguro del año a entero (int)
        try:
            anio_int = int(r["year"]) if pd.notna(r["year"]) else 0
        except ValueError:
            anio_int = 0
            
        # Generar nombre de juegos si viene vacío (ej. "1888 Special")
        juegos_str = str(r.get("games_name", ""))
        if juegos_str == "nan" or juegos_str.strip() == "":
            juegos_str = f"{anio_int} {r['categoria']}"

        docs_ediciones.append({
            "_id": int(r["id_edicion_juego"]),
            "anio": anio_int,
            "temporada": str(r["season"]) if pd.notna(r["season"]) else "Desconocida",
            "juegos": juegos_str,
            "ciudad": str(r["ciudad"]) if pd.notna(r["ciudad"]) else "Desconocida",
            "noc_sede": str(r["noc_sede"]) if pd.notna(r["noc_sede"]) else "",
            "pais_sede": None,
            "sede_confirmada": True,
            "total_participaciones": int(df_participacion[df_participacion["id_edicion_juego"] == r["id_edicion_juego"]].shape[0])
        })

    docs_paises = []
    for _, r in df_nocs.iterrows():
        noc = r["NOC"]
        medallas_pais = parts_por_pais.get(noc, [])
        oro = sum(1 for m in medallas_pais if m.get("medal") == "Gold")
        plata = sum(1 for m in medallas_pais if m.get("medal") == "Silver")
        bronce = sum(1 for m in medallas_pais if m.get("medal") == "Bronze")
        
        docs_paises.append({
            "_id": noc,
            "nombre": limpiar_nan(r["region"]),
            "notas": limpiar_nan(r["notes"]),
            "resumen": {"total_medallas": oro + plata + bronce},
            "medallero": {"oro": oro, "plata": plata, "bronce": bronce, "por_anio": []},
            "participaciones": [], 
            "poblaciones": [{"anio": p["year"], "poblacion": p["population"]} for p in pob_por_pais.get(noc, [])],
            "ediciones_sede": sedes_por_pais.get(noc, [])
        })

    log(f"Construyendo documentos de atletas (~{len(df_atletas)})...")
    docs_atletas = []
    for _, r in df_atletas.iterrows():
        a_id = r["athlete_id"]
        
        parts = []
        if a_id in parts_agrupadas.groups:
            for _, p in parts_agrupadas.get_group(a_id).iterrows():
                parts.append({
                    "id_participacion": p["id_participacion"],
                    "id_edicion": p["id_edicion_juego"],
                    "id_disciplina": p["id_disciplina"],
                    "anio": limpiar_nan(p["year"]),
                    "deporte": limpiar_nan(p["sport"]),
                    "evento": limpiar_nan(p["event_name"]),
                    "pais": limpiar_nan(p["noc_code"]),
                    "medalla": limpiar_nan(p["medal"]) if "medal" in p else None
                })
        
        docs_atletas.append({
            "_id": a_id,
            "source_athlete_id": None,
            "nombre_completo": limpiar_nan(r["Full name"]),
            "nombre_uso": limpiar_nan(r["name"]),
            "busqueda_nombre": str(r["Full name"]).lower() if pd.notna(r["Full name"]) else "",
            "sexo": limpiar_nan(r["Sex"]),
            "noc_code": limpiar_nan(r["noc_code"]),
            "roles": roles_por_atleta.get(a_id, ["Competitor"]),
            "participaciones": parts
        })

    # ---------------------------------------------------------
    # 4. CARGA A MONGODB (Idempotente)
    # ---------------------------------------------------------
    log("Conectando a MongoDB y aplicando Bulk Writes...")
    cliente = MongoClient("mongodb://admin:admin123@localhost:27017/")
    db = cliente["olimpiadas"]

    def bulk_upsert(coleccion, documentos):
        if not documentos: return
        ops = [UpdateOne({"_id": d["_id"]}, {"$set": d}, upsert=True) for d in documentos]
        res = db[coleccion].bulk_write(ops)
        log(f"  -> {coleccion}: Insertados/Modificados {res.upserted_count + res.modified_count}")

    bulk_upsert("roles", docs_roles)
    bulk_upsert("disciplinas", docs_disciplinas)
    bulk_upsert("ediciones", docs_ediciones)
    bulk_upsert("paises", docs_paises)
    
    lote_size = 10000
    for i in range(0, len(docs_atletas), lote_size):
        bulk_upsert("atletas", docs_atletas[i:i+lote_size])
        log(f"     Lote atletas procesado ({min(i+lote_size, len(docs_atletas))}/{len(docs_atletas)})")

    log("=== CARGA FINALIZADA ===")
    log(f"Tiempo total: {(datetime.now() - inicio).total_seconds():.2f} segundos")

if __name__ == "__main__":
    main()