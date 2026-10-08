"""
PROYECTO 1 - BASE DE DATOS DE OLIMPIADAS
Script: ETL_Limpieza_Carga.py

Carga los CSV ya normalizados por tabla (worked_datasets/tabla_*.csv) hacia el
modelo final creado por DDL_Creacion_Objetos.sql.

Uso:
    python3 ETL_Limpieza_Carga.py --data-dir /ruta/a/worked_datasets \
        --server localhost --port 1433 --user sa --password 'admin321!' --database db_olimpiadas
"""

import argparse
import math
import time
import pandas as pd


def to_int(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    try:
        return int(float(v))
    except (ValueError, TypeError):
        return None


def to_float(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    try:
        return float(v)
    except (ValueError, TypeError):
        return None


def to_date(v):
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    s = str(v).strip()
    return s if s else None


def nn(v):
    """None-if-empty: normaliza NaN / '' / espacios a None."""
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return None
    s = str(v).strip()
    return s if s else None


def chunked_insert(cur, table, columns, rows, chunksize=5000):
    if not rows:
        return 0
    placeholders = ",".join(["%s"] * len(columns))
    sql = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({placeholders})"
    for i in range(0, len(rows), chunksize):
        cur.executemany(sql, rows[i:i + chunksize])
    return len(rows)


def log(table, n, t0, extra=""):
    print(f"  -> {table}: {n} filas procesadas/insertadas en {time.time() - t0:.1f}s {extra}")


# ------------------------------------------------------------------ region ---
def load_region(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_nocs.csv")
    rows = []
    for _, r in df.iterrows():
        noc = nn(r["NOC"])
        if noc is None:
            continue
        rows.append((noc, nn(r["region"]) or noc, None, nn(r["notes"])))
    n = chunked_insert(cur, "dbo.region", ["noc_code", "country_name", "region", "notas"], rows)
    log("region", n, t0, "(incluye 'UNK', ya viene en tabla_nocs.csv)")


# --------------------------------------------------------------- poblacion ---
def load_poblacion(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_poblaciones.csv")
    cur.execute("SELECT noc_code FROM dbo.region")
    valid = {row[0] for row in cur.fetchall()}
    rows, skipped = [], 0
    for _, r in df.iterrows():
        noc = nn(r["noc_code"])
        if noc not in valid:
            skipped += 1
            continue
        anio = to_int(r["year"])
        if anio is None:
            skipped += 1
            continue
        rows.append((noc, anio, to_int(r["population"])))
    n = chunked_insert(cur, "dbo.poblacion", ["noc_code", "anio", "poblacion"], rows)
    log("poblacion", n, t0, f"({skipped} omitidas: noc_code no existe en region)")


# --------------------------------------------------------------- disciplina --
def load_disciplina(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_disciplina.csv")
    cur.execute("SET IDENTITY_INSERT dbo.disciplina ON")
    rows = [(to_int(r["id_disciplina"]), nn(r["sport"]) or "Unknown", nn(r["event_name"]) or "Unknown") for _, r in df.iterrows()]
    n = chunked_insert(cur, "dbo.disciplina", ["id", "sport", "event_name"], rows)
    cur.execute("SET IDENTITY_INSERT dbo.disciplina OFF")
    log("disciplina", n, t0)


# ------------------------------------------------------------ edicion_juego --
def load_edicion_juego(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_edicion_juego.csv")
    cur.execute("SET IDENTITY_INSERT dbo.edicion_juego ON")
    rows = []
    for _, r in df.iterrows():
        eid = to_int(r["id_edicion_juego"])
        year = to_int(r["year"])
        season = nn(r["season"])
        city = nn(r["city"])
        partes = [str(year) if year is not None else None, season]
        games_name = " ".join(p for p in partes if p) or f"Edicion {eid}"
        rows.append((eid, year, season, games_name, city, None))
    n = chunked_insert(cur, "dbo.edicion_juego", ["id", "year", "season", "games_name", "city", "noc_code"], rows)
    cur.execute("SET IDENTITY_INSERT dbo.edicion_juego OFF")
    log("edicion_juego", n, t0)


# ----------------------------------------------------------------- atleta ----
def load_atleta(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_atletas.csv")
    cur.execute("SET IDENTITY_INSERT dbo.atleta ON")
    rows = []
    for _, r in df.iterrows():
        aid = to_int(r["athlete_id"])
        if aid is None:
            continue
        sex_raw = nn(r["Sex"])
        sex = sex_raw[0].upper() if sex_raw else None
        
        # Mapeo correcto de nombres para evitar NULLs en búsquedas
        full_name = nn(r["name"]) or nn(r["Full name"]) or f"Atleta {aid}"
        used_name = nn(r["Full name"])  # POBLADO: antes era None
        otros_nombres = nn(r["Other names"])
        
        rows.append((
            aid, str(aid), full_name, used_name, nn(r["Original name"]), otros_nombres,
            nn(r["Name order"]), nn(r["Nick/petnames"]), nn(r["Title(s)"]), nn(r["Affiliations"]),
            nn(r["Nationality"]), sex, to_date(r["born_date"]), nn(r["born_city"]), nn(r["born_region"]),
            nn(r["born_country"]), to_float(r["lat"]), to_float(r["long"]), to_date(r["died_date"]),
            nn(r["died_in"]), None  # noc_code se actualiza despues de cargar participaciones
        ))
    cols = ["id", "source_athlete_id", "full_name", "used_name", "nombre_original", "otros_nombres",
            "orden_nombre", "apodos", "titulos", "afiliaciones", "nacionalidad", "sex", "born_date",
            "born_city", "born_region", "born_country", "latitud", "longitud", "died_date", "died_place",
            "noc_code"]
    n = chunked_insert(cur, "dbo.atleta", cols, rows)
    cur.execute("SET IDENTITY_INSERT dbo.atleta OFF")
    log("atleta", n, t0)


# ------------------------------------------------------------------- roles ---
def load_roles(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_rol.csv")
    cur.execute("SET IDENTITY_INSERT dbo.roles ON")
    rows = [(to_int(r["rol_id"]), nn(r["nombre_rol"]), None) for _, r in df.iterrows()]
    n = chunked_insert(cur, "dbo.roles", ["id", "nombre", "descripcion"], rows)
    cur.execute("SET IDENTITY_INSERT dbo.roles OFF")
    log("roles", n, t0)


# ------------------------------------------------------------ participacion --
def load_participacion(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_participacion.csv")
    cur.execute("SELECT noc_code FROM dbo.region")
    valid = {row[0] for row in cur.fetchall()}
    cur.execute("SET IDENTITY_INSERT dbo.participacion ON")
    rows, fallback = [], 0
    
    # Para actualizar noc_code en atleta con su código más frecuente
    atleta_nocs = {}

    for _, r in df.iterrows():
        aid = to_int(r["athlete_id"])
        noc = nn(r["noc_code"])
        if noc not in valid:
            noc = "UNK"
            fallback += 1
        
        if aid and noc != "UNK":
            atleta_nocs[aid] = noc

        rows.append((
            to_int(r["id_participacion"]), aid, to_int(r["id_edicion_juego"]),
            to_int(r["id_disciplina"]), noc, nn(r["team"]), nn(r["presentado_como"]),
            to_float(r["age"]), to_float(r["height_cm"]), to_float(r["weight_kg"]),
        ))
    cols = ["id", "id_atleta", "id_edicion", "id_disciplina", "noc_code", "equipo",
            "presentado_como", "age", "height_cm", "weight_kg"]
    n = chunked_insert(cur, "dbo.participacion", cols, rows)
    cur.execute("SET IDENTITY_INSERT dbo.participacion OFF")
    log("participacion", n, t0, f"({fallback} con noc_code huerfano -> 'UNK')")

    # POBLADO DE ATLETA.NOC_CODE: Actualizar el país por defecto del atleta
    t_up = time.time()
    update_rows = [(noc, aid) for aid, noc in atleta_nocs.items()]
    cur.executemany("UPDATE dbo.atleta SET noc_code = %s WHERE id = %d", update_rows)
    log("atleta (actualización de noc_code)", len(update_rows), t_up)


# ----------------------------------------------------------------- resultado -
def load_resultado(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_resultado.csv")
    rows = []
    desconocidos = 0
    for _, r in df.iterrows():
        place_v = r["place"]
        if pd.isna(place_v):
            place_s = None
        else:
            try:
                f = float(place_v)
                place_s = str(int(f)) if f.is_integer() else str(f)
            except (ValueError, TypeError):
                place_s = str(place_v).strip()
        # tied admite True/False, "True"/"False" y vacio/NULL (indeterminado:
        # las ediciones sin posicion final en la fuente quedan en NULL).
        tied_raw = r["tied"]
        if pd.isna(tied_raw):
            tied = None
            desconocidos += 1
        elif isinstance(tied_raw, str) and tied_raw.strip():
            tied = 1 if tied_raw.strip().lower() == "true" else 0
        else:
            tied = 1 if bool(tied_raw) else 0
        rows.append((to_int(r["id_participacion"]), place_s, tied, nn(r["medal"])))
    n = chunked_insert(cur, "dbo.resultado", ["id_participacion", "place", "tied", "medal"], rows)
    log("resultado", n, t0, f"({desconocidos} con 'tied' NULL: empate no determinable)")


# -------------------------------------------------------------- atleta_roles -
def load_atleta_roles(cur, data_dir):
    t0 = time.time()
    df = pd.read_csv(f"{data_dir}/tabla_atleta_rol.csv")
    rows = list({(to_int(r["athlete_id"]), to_int(r["rol_id"])) for _, r in df.iterrows()})
    n = chunked_insert(cur, "dbo.atleta_roles", ["id_atleta", "id_rol"], rows)
    log("atleta_roles", n, t0)


LOADERS = [
    ("region", load_region),
    ("poblacion", load_poblacion),
    ("disciplina", load_disciplina),
    ("edicion_juego", load_edicion_juego),
    ("atleta", load_atleta),
    ("roles", load_roles),
    ("participacion", load_participacion),
    ("resultado", load_resultado),
    ("atleta_roles", load_atleta_roles),
]


class DryRunCursor:
    """
    Cursor falso que registra lo que se insertaria, para validar el ETL sin
    necesidad de un servidor SQL Server. Responde con un conjunto vacio a las
    consultas de validacion (SELECT noc_code FROM dbo.region, etc.).
    """

    def __init__(self, region_nocs=()):
        self.stmts = []
        self.filas = {}
        self.region_nocs = list(region_nocs)
        self._last = []

    def execute(self, sql, params=None):
        self.stmts.append(sql)
        if sql.strip().upper().startswith("SELECT"):
            # Responde el set de NOC validos para que los validadores de FK
            # se comporten igual que contra la base real.
            self._last = [(n,) for n in self.region_nocs]
        return self

    def executemany(self, sql, rows):
        filas = list(rows)
        if "INSERT INTO" in sql.upper():
            tabla = sql.upper().split("INSERT INTO")[1].split("(")[0].strip()
        else:
            tabla = sql
        self.filas[tabla] = self.filas.get(tabla, 0) + len(filas)

    def fetchall(self):
        return self._last

    def close(self):
        pass


def dry_run(data_dir):
    nocs = pd.read_csv(f"{data_dir}/tabla_nocs.csv")
    cur = DryRunCursor(nocs["NOC"].tolist())
    print(f"[dry-run] data-dir={data_dir}")
    for name, loader in LOADERS:
        loader(cur, data_dir)
    print("\n[ dry-run ] Filas a insertar por tabla:")
    for tabla, n in cur.filas.items():
        print(f"  {tabla:15s} {n}")


def main():
    ap = argparse.ArgumentParser(description="Carga worked_datasets/tabla_*.csv a db_olimpiadas")
    ap.add_argument("--data-dir", required=True, help="Carpeta con los tabla_*.csv")
    ap.add_argument("--server", default="localhost")
    ap.add_argument("--port", type=int, default=1433)
    ap.add_argument("--user", default="sa")
    ap.add_argument("--password")
    ap.add_argument("--database", default="db_olimpiadas")
    ap.add_argument("--dry-run", action="store_true",
                    help="Valida y muestra los INSERT sin conectar a la base")
    args = ap.parse_args()

    if args.dry_run:
        dry_run(args.data_dir)
        return

    if not args.password:
        ap.error("--password es obligatorio salvo que se use --dry-run")

    import pymssql  # se importa aca para que --dry-run no lo requiera

    conn = pymssql.connect(
        server=args.server, port=args.port, user=args.user,
        password=args.password, database=args.database, autocommit=False,
    )
    cur = conn.cursor()
    print(f"Conectado a {args.server}:{args.port}/{args.database}")

    for name, loader in LOADERS:
        try:
            loader(cur, args.data_dir)
            conn.commit()
        except Exception as exc:
            conn.rollback()
            print(f"ERROR cargando {name}: {exc}")
            raise

    cur.close()
    conn.close()
    print("Carga completa.")


if __name__ == "__main__":
    main()