"""
resultados_2024.py

Genera las participaciones de las ediciones OLIMPICAS QUE NO ESTAN en
datasets/results.csv (2020 en adelante: Paris 2024) usando como unica fuente
datasets/olympics_dataset.csv, que es el unico dataset que llega hasta 2024.

Responsabilidades:
  1. Normalizar Sport/Event de olympics_dataset.csv al formato de
     results.csv  ->  discipline = "Swimming (Aquatics)"
                      event      = "100 metres Freestyle, Men (Olympic)"
  2. Resolver athlete_id contra datasets/bios.csv (match por nombre normalizado).
     Los que NO matchean se convierten en atletas NUEVOS con id sintetico.
  3. Derivar place y tied a partir del ranking dentro de cada prueba.
  4. Emitir, en el mismo esquema que worked_datasets/resultsFull.csv:
        worked_datasets/resultados_2024.csv
     y los atletas nuevos en:
        worked_datasets/tabla_atletas_nuevas_2024.csv
  5. Agregar a worked_datasets/tabla_nocs.csv los NOC que aparecen en 2024
     pero no existian en la dimensional de paises.

Este script corre ANTES de results.py / resultsUnificado.py / atletas.py.
"""

import re
import unicodedata

import pandas as pd

RAW_OD = "datasets/olympics_dataset.csv"
RAW_BIOS = "datasets/bios.csv"
OUT_RESULTADOS = "worked_datasets/resultados_2024.csv"
OUT_ATLETAS_NUEVAS = "worked_datasets/tabla_atletas_nuevas_2024.csv"
NOCS_FILE = "worked_datasets/tabla_nocs.csv"

# Solo procesamos las ediciones que results.csv no cubre.
ANIOS_A_COMPLETAR = [2024]

# --------------------------------------------------------------------------
# 1. NORMALIZACION DE DISCIPLINA (Sport -> discipline)
# --------------------------------------------------------------------------
# results.csv usa "<Disciplina> (<Familia>)". olympics_dataset.csv usa el
# nombre "limpio" del deporte. Este mapa traduce al formato de la base.
SPORT_A_DISCIPLINA = {
    "3x3 Basketball": "3x3 Basketball (Basketball)",
    "Archery": "Archery",
    "Art Competitions": "Art Competitions",
    "Artistic Gymnastics": "Artistic Gymnastics (Gymnastics)",
    "Artistic Swimming": "Artistic Swimming (Aquatics)",
    "Athletics": "Athletics",
    "Badminton": "Badminton",
    "Basketball": "Basketball (Basketball)",
    "Beach Volleyball": "Beach Volleyball (Volleyball)",
    "Boxing": "Boxing",
    "Breaking": "Breaking (Skateboarding)",
    "Canoe Slalom": "Canoe Slalom (Canoeing)",
    "Canoe Sprint": "Canoe Sprint (Canoeing)",
    "Cycling BMX Freestyle": "Cycling BMX Freestyle (Cycling)",
    "Cycling BMX Racing": "Cycling BMX Racing (Cycling)",
    "Cycling Mountain Bike": "Cycling Mountain Bike (Cycling)",
    "Cycling Road": "Cycling Road (Cycling)",
    "Cycling Track": "Cycling Track (Cycling)",
    "Diving": "Diving (Aquatics)",
    "Fencing": "Fencing",
    "Football": "Football (Football)",
    "Golf": "Golf",
    "Handball": "Handball",
    "Hockey": "Hockey",
    "Judo": "Judo",
    "Marathon Swimming": "Marathon Swimming (Aquatics)",
    "Modern Pentathlon": "Modern Pentathlon",
    "Rhythmic Gymnastics": "Rhythmic Gymnastics (Gymnastics)",
    "Rowing": "Rowing",
    "Rugby Sevens": "Rugby Sevens (Rugby)",
    "Sailing": "Sailing",
    "Shooting": "Shooting",
    "Skateboarding": "Skateboarding (Roller Sports)",
    "Sport Climbing": "Sport Climbing",
    "Surfing": "Surfing",
    "Swimming": "Swimming (Aquatics)",
    "Table Tennis": "Table Tennis",
    "Taekwondo": "Taekwondo",
    "Tennis": "Tennis",
    "Trampoline Gymnastics": "Trampolining (Gymnastics)",
    "Triathlon": "Triathlon",
    "Volleyball": "Volleyball (Volleyball)",
    "Water Polo": "Water Polo (Aquatics)",
    "Weightlifting": "Weightlifting",
    "Wrestling": "Wrestling",
}

# "Equestrian" en results.csv se desdobla por especialidad; el specialty se
# deduce del texto del evento.
EQUESTRIAN_ESPECIALIDADES = ["Dressage", "Eventing", "Jumping", "Vaulting", "Driving"]

MEDAL_A_RANK = {"Gold": 0, "Silver": 1, "Bronze": 2}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def norm_nombre(s):
    """Minúsculas, sin tildes y sin espacios duplicados, para comparar nombres."""
    if pd.isna(s):
        return ""
    s = unicodedata.normalize("NFKD", str(s))
    s = "".join(c for c in s if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", s.strip().lower())


def discipline_de(sport, event):
    """Traduce el Sport de olympics_dataset.csv al discipline de results.csv."""
    # Algunos Sports vienen compuestos: "Cycling Road, Triathlon" -> primero.
    sport = str(sport).split(",")[0].strip()
    event_txt = str(event)

    if sport == "Equestrian":
        for esp in EQUESTRIAN_ESPECIALIDADES:
            if event_txt.lower().startswith(esp.lower()):
                return f"Equestrian {esp} (Equestrian)"
        return "Equestrian Jumping (Equestrian)"

    return SPORT_A_DISCIPLINA.get(sport, sport)


def _base_disciplina(discipline):
    """'Swimming (Aquatics)' -> 'Swimming' (para no repetir la familia)."""
    return re.sub(r"\s*\([^)]*\)$", "", discipline).strip()


def _unidades(texto):
    """'100m' / '10,000m' / '4 x 100m Relay' -> notacion de results.csv."""
    # "x" -> "x" solo en relevos: en "3x3 Basketball" es parte del nombre.
    if re.search(r"\d\s*x\s*\d", texto) and "relay" in texto.lower():
        texto = re.sub(r"(\d)\s*x\s*(\d)", r"\1 × \2", texto)
    texto = re.sub(r"(\d)\s*km\b", r"\1 kilometres", texto)
    texto = re.sub(r"(\d)\s*m\b", r"\1 metres", texto)
    return texto


def event_normalizado(event, discipline, sex=None):
    """
    Convierte el Event de olympics_dataset.csv al formato de results.csv:

        "Men's 100m Freestyle"   -> "100 metres Freestyle, Men (Olympic)"
        "Women's 4 x 100m Relay"-> "4 x 100 metres Relay, Women (Olympic)"
        "Men" (deporte de equipo)-> "Basketball, Men (Olympic)"
        "Duet"                   -> "Duet, Women (Olympic)"  (genero desde Sex)

    Cuando el evento no trae genero explicito se usa la columna Sex, que en
    competencias mixtas por equipos produce 'Mixed'.
    """
    ev = re.sub(r"\s+", " ", str(event).strip())

    # Equestrian: "Jumping Individual" -> el "Jumping" ya va en la disciplina.
    m_eq = re.match(r"^(Dressage|Eventing|Jumping|Vaulting|Driving)\s+(.*)$", ev)
    if m_eq:
        ev = m_eq.group(2).strip()

    genero_default = {"M": "Men", "F": "Women", "Male": "Men", "Female": "Women",
                      "O": "Mixed"}.get(str(sex).strip() if sex is not None else "", None)


    # Etiquetas de rol que en results.csv forman parte del nombre de la prueba.
    equivalencias = {
        "Mixed Team": ("Team", "Mixed"),
        "B-Boys": ("", "Men"),
        "B-Girls": ("", "Women"),
        "Men": ("", "Men"),
        "Women": ("", "Women"),
        "Mixed": ("", "Mixed"),
    }
    if ev in equivalencias:
        base, gen = equivalencias[ev]
        base = base or _base_disciplina(discipline)
        return f"{_unidades(base)}, {gen} (Olympic)"

    # "Men's 100m Freestyle" / "Women's 4 x 100m Relay" / "Men -60 kg"
    m = re.match(r"^(?P<base>.*?)\s*[,]?\s*"
                 r"(?P<gen>Men|Women|Boys|Girls|Mixed)(?:'s)?(?:\s+(?P<extra>.*))?$",
                 ev)
    if m:
        base = (m.group("base") or "").strip(" ,")
        gen = m.group("gen")
        extra = (m.group("extra") or "").strip(" ,")
    else:
        # "10m Air Rifle Men" / "50m Rifle 3 Positions Women" / "Men +80kg"
        m2 = re.match(r"^(?P<base>.*?)\s*[,]?\s*"
                      r"(?P<gen>Men|Women|Mixed)(?:\s+(?P<extra>.*))?$", ev)
        if not m2:
            # Sin genero explicito: "Duet", "Jumping Individual", "Boulder & Lead"
            gen = genero_default or "Open"
            partes = [p for p in (ev,) if p]
            return f"{_unidades(', '.join(partes))}, {gen} (Olympic)"
        base = (m2.group("base") or "").strip(" ,")
        gen = m2.group("gen")
        extra = (m2.group("extra") or "").strip(" ,")

    if not base:
        base = extra or _base_disciplina(discipline)
        extra = ""
    if extra and extra.lower() == base.lower():
        extra = ""

        # "Lightweight Double Sculls": un solo adjetivo se pega, no se separa por coma.
    if extra and " " not in base and " " in extra:
        nombre = f"{base} {extra}"
    else:
        nombre = ", ".join(p for p in (base, extra) if p)

    # Tiro: OD "10m Air Rifle Men" -> results.csv "Air Rifle, 10 metres, Men"
    if discipline == "Shooting":
        m_sh = re.match(r"^(?P<dist>\d+\s*m)\s+(?P<arma>.+)$", nombre)
        if m_sh:
            nombre = f"{m_sh.group('arma').strip()}, {m_sh.group('dist').strip()}"

    return f"{_unidades(nombre)}, {gen} (Olympic)"


# --------------------------------------------------------------------------
# 2. CARGA Y FILTRADO
# --------------------------------------------------------------------------
def cargar_od(anios):
    od = pd.read_csv(RAW_OD, low_memory=False)
    od = od[od["Year"].isin(anios)].copy()
    od["Medal"] = od["Medal"].replace("No medal", pd.NA)
    # biosComplejo.csv usa "Male"/"Female"; OD usa "M"/"F".
    od["Sex"] = od["Sex"].replace({"M": "Male", "F": "Female", "O": "Other"})
    for c in ("Name", "Team", "NOC", "City", "Sport", "Event", "Season"):
        od[c] = od[c].astype(str).str.strip()
    return od


# --------------------------------------------------------------------------
# 3. ATLETAS: match contra bios.csv, y creation de los que no matchean
# --------------------------------------------------------------------------
def resolver_atletas(od):
    """
    Devuelve (od_con_athlete_id, atletas_nuevos).

    Match por nombre normalizado contra bios.csv. Cuando el mismo nombre
    aparece varias veces en bios se elige el registro con fecha de nacimiento
    mas reciente (el atleta vigente en 2024).
    """
    bios = pd.read_csv(RAW_BIOS, low_memory=False)
    bios["key"] = bios["name"].map(norm_nombre)

    # Un nombre -> el athlete_id con born_date mas reciente.
    bios = bios.sort_values(["key", "born_date"], na_position="first")
    mejor = bios.drop_duplicates("key", keep="last").set_index("key")

    od["key"] = od["Name"].map(norm_nombre)
    od["athlete_id"] = od["key"].map(mejor["athlete_id"])

    # Datos biometricos de los atletas ya conocidos (para Age/Height/Weight).
    bios_hw = mejor[["athlete_id", "born_date", "height_cm", "weight_kg"]]

    matcheados = od[od["athlete_id"].notna()].copy()
    nuevos = od[od["athlete_id"].isna()].copy()
    print(f"Atletas 2024 matcheados con bios.csv: {matcheados['key'].nunique()}")
    print(f"Atletas 2024 SIN ficha en bios.csv   : {nuevos['key'].nunique()}")

    # ---- id sintetico para los nuevos (por encima de todos los ids existentes)
    ids_existentes = set(pd.read_csv(RAW_BIOS, usecols=["athlete_id"])["athlete_id"].dropna())
    try:
        res_previas = pd.read_csv("worked_datasets/resultsFull.csv", usecols=["athlete_id"])
        ids_existentes |= set(res_previas["athlete_id"].dropna())
    except FileNotFoundError:
        pass
    next_id = int(max(ids_existentes)) + 1

    # Llave de identidad: nombre + NOC (evita fusionar homonimos de paises distintos).
    nuevos["llave"] = nuevos["key"] + "|" + nuevos["NOC"]
    llaves_unicas = list(dict.fromkeys(nuevos["llave"].dropna()))
    mapa_id = {llave: next_id + i for i, llave in enumerate(llaves_unicas)}
    nuevos["athlete_id"] = nuevos["llave"].map(mapa_id)

    print(f"IDs sinteticos asignados: {len(mapa_id)} (desde {next_id})")

    # ---- tabla de atletas nuevos, en el mismo esquema que tabla_atletas.csv
    col_bios = ["Sex", "Full name", "died_in", "Affiliations", "Nick/petnames",
                "Title(s)", "Other names", "Nationality", "Original name",
                "Name order", "name", "born_date", "born_city", "born_region",
                "born_country", "died_date", "lat", "long"]

    info = (
        nuevos.sort_values("llave")
        .drop_duplicates("llave")
        .set_index("llave")
    )
    nuevas = pd.DataFrame(index=pd.Index(llaves_unicas, name="llave"))
    nuevas["athlete_id"] = [mapa_id[k] for k in llaves_unicas]
    nuevas["Sex"] = info["Sex"].values
    nuevas["Full name"] = info["Name"].values
    nuevas["name"] = info["Name"].values
    nuevas["noc_2024"] = info["NOC"].values
    for c in col_bios:
        if c not in nuevas.columns:
            nuevas[c] = pd.NA
    # Orden de columnas igual que tabla_atletas.csv, con noc_2024 al final
    # (el ETL no lo carga; queda como trazabilidad).
    nuevas = nuevas[["athlete_id"] + col_bios + ["noc_2024"]]

    od = pd.concat([matcheados, nuevos.drop(columns=["llave"])], ignore_index=True)
    return od, nuevas, bios_hw


# --------------------------------------------------------------------------
# 4. PLACE / TIED DERIVADOS DEL RANKING
# --------------------------------------------------------------------------
def derivar_place(od):
    """
    No hay columna de posicion final en olympics_dataset.csv, asi que el place
    se deriva del ranking dentro de cada prueba (year, discipline, event):

      * orden: medalla (Gold, Silver, Bronze, sin medalla) -> NOC
      * un solo place por delegacion (criterio de results.csv: las 12 filas de
        USA en Basket 2016 comparten place=1)
      * tied queda NULL (desconocido): ver nota abajo
    """
    od["_rank_medal"] = od["medal"].map(MEDAL_A_RANK).fillna(99).astype(int)

    # Ranking por NOC dentro de la prueba: un solo lugar por delegacion, que es
    # el criterio de results.csv (las 12 filas de USA en Basket 2016 comparten
    # place=1). En pruebas individuales cada atleta es su propia delegacion.
    nocs_prueba = (
        od.groupby(["year", "discipline", "event", "noc"], as_index=False)
        .agg(_rank_medal=("_rank_medal", "min"))
        .sort_values(["year", "discipline", "event", "_rank_medal", "noc"],
                     kind="mergesort")
    )
    nocs_prueba["place"] = (
        nocs_prueba.groupby(["year", "discipline", "event"]).cumcount() + 1
    )
    od = od.merge(
        nocs_prueba[["year", "discipline", "event", "noc", "place"]],
        on=["year", "discipline", "event", "noc"],
        how="left",
    )

    # tied queda DESCONOCIDO (NULL), no False.
    #
    # El place de arriba se construye con un ranking secuencial por delegacion,
    # asi que por definicion ningun lugar puede quedar compartido: calcular
    # "tied" aca devolveria siempre False, que affirmaria "no hubo empate" sin
    # que el dato lo sustente. En results.csv el place viene de la posicion
    # final real y si se repite (100 metres Rio 2016: 8 de 9 lugares
    # compartidos) tied marca el empate. Para 2024 no hay tiempos ni posiciones
    # finales en la fuente, asi que NULL es la representacion honesta.
    od["tied"] = pd.NA
    return od.drop(columns=["_rank_medal"])


# --------------------------------------------------------------------------
# 5. NOCS NUEVOS
# --------------------------------------------------------------------------
NOC_NUEVOS_2024 = {
    # code: (nombre legible, notas)
    "AIN": ("Individual Neutral Athletes", "Atletas individuales neutrales (Olimpiadas 2024)"),
    "EOR": ("Refugee Olympic Team", "Equipo olimpico de refugiados (Olimpiadas 2024)"),
    "LBN": ("Lebanon", "L Lebanon"),
    "SGP": ("Singapore", "Singapore"),
}


def actualizar_nocs(od):
    nocs = pd.read_csv(NOCS_FILE)
    existentes = set(nocs["NOC"])
    faltantes = sorted(set(od["noc"]) - existentes)
    agregados = []
    for code in faltantes:
        nombre, nota = NOC_NUEVOS_2024.get(code, (code, "Alta automatica 2024"))
        agregados.append({"NOC": code, "region": nombre, "notes": nota})
    if agregados:
        nocs = pd.concat([nocs, pd.DataFrame(agregados)], ignore_index=True)
        nocs.to_csv(NOCS_FILE, index=False)
    print(f"NOC agregados a tabla_nocs.csv: {len(agregados)} {agregados and [a['NOC'] for a in agregados]}")


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------
def main():
    od = cargar_od(ANIOS_A_COMPLETAR)
    print(f"Filas crudas 2024 en olympics_dataset.csv: {len(od)}")

    # 'Relay Only Athlete' es una fila tecnica de natacion, no un atleta.
    od = od[od["Event"] != "Relay Only Athlete"].copy()

    od["discipline"] = [discipline_de(s, e) for s, e in zip(od["Sport"], od["Event"])]
    od["event"] = [event_normalizado(e, d, x)
                    for e, d, x in zip(od["Event"], od["discipline"], od["Sex"])]
    od["noc"] = od["NOC"]
    od, nuevas, bios_hw = resolver_atletas(od)

    od = od.rename(columns={"Season": "type", "Name": "as",
                           "Team": "team", "Medal": "medal"})
    od["year"] = od["Year"]
    od["city"] = od["City"]

    # Age / Height / Weight: solo para los atletas ya conocidos en bios.csv.
    od = od.merge(bios_hw.rename(columns={"athlete_id": "_aid"}), left_on="athlete_id",
                  right_on="_aid", how="left")
    od["born_year"] = pd.to_datetime(od["born_date"], errors="coerce").dt.year
    od["Age"] = od["year"] - od["born_year"]
    od.loc[(od["Age"] < 10) | (od["Age"] > 90), "Age"] = pd.NA
    od["Height"] = pd.to_numeric(od["height_cm"], errors="coerce")
    od["Weight"] = pd.to_numeric(od["weight_kg"], errors="coerce")
    od = od.drop(columns=["_aid", "born_date", "born_year", "height_cm", "weight_kg"])

    od = derivar_place(od)
    actualizar_nocs(od)

    columnas = ["athlete_id", "as", "year", "type", "discipline", "event", "noc",
                "team", "place", "tied", "medal", "Age", "Height", "Weight", "city"]
    od[columnas].to_csv(OUT_RESULTADOS, index=False)
    nuevas.to_csv(OUT_ATLETAS_NUEVAS, index=False)

    print(f"\n{OUT_RESULTADOS}: {len(od)} filas, {od['discipline'].nunique()} disciplinas")
    print(od.groupby(["year", "type", "city"]).size())
    print(f"{OUT_ATLETAS_NUEVAS}: {len(nuevas)} atletas nuevos")
    print("\nMuestra 2024:")
    print(od[["as", "noc", "discipline", "event", "place", "tied", "medal"]].head(10))


if __name__ == "__main__":
    main()