# Proyecto Fase 3 — Olimpiadas en MongoDB

En esta fase se carga en MongoDB la información de la Fase 1 con sus correcciones. Incluye dos consultas: una por
**atleta** (requisito c) y otra por **país** (requisito d).

## Estructura

```
Proyecto Fase 3/
├── ddl/crear_colecciones_indices.py   colecciones, validadores $jsonSchema e índices (idempotente)
├── carga/
│   ├── cargar_todo.sh                 regenera la base de cero: contenedor + DDL + ETL
│   ├── cargar_mongo.py                ETL fuentes/*.csv → 5 colecciones (correcciones C1–C5)
│   ├── generar_sedes.py               genera fuentes/ediciones_sede.csv (ciudad, NOC sede, categoría)
│   └── regenerar_poblaciones.py       genera fuentes/tabla_poblaciones_mapeada.csv (ISO-3 → NOC)
├── fuentes/                           archivos fuente de la carga (tablas de la Fase 1 + curados)
├── consulta/
│   ├── atleta.py                      (c) toda la información de un atleta
│   ├── pais.py                        (d) toda la información de un país
│   ├── comun.py                       conexión, filtros, explain y tablas
│   ├── ejecutar_pruebas.py            casos de prueba automáticos (ver pruebas.md)
│   ├── medir_rendimiento.py           tiempos + explain("executionStats")
│   └── pruebas.md                     casos de prueba documentados
├── docs/
│   ├── Documentacion_Tecnica.md       despliegue, ETL y correcciones
│   ├── rendimiento_consultas.md       tiempos e índices usados por cada consulta
│   └── logs/                          bitácoras con fecha y hora de cada ejecución
└── capturas/
```

## 1. Requisitos

- Docker Desktop (MongoDB corre en el contenedor `mongodb_olimpiadas`, usuario `admin` / `admin123`)
- Python 3.10 o superior con `pip install pymongo` para el DDL y las consultas
- Para correr el ETL fuera de Docker también se necesita `pip install pandas`. `cargar_todo.sh` ya lo corre en un
  contenedor.

## 2. Crear y cargar la base (desde cero)

```bash
bash "Proyecto Fase 3/carga/cargar_todo.sh" --limpio
```

Este script:
1. Crea o arranca `mongodb_olimpiadas` (`mongo:9.0.4`, puerto 27017, volumen `mongodata_olimpiadas`).
2. Ejecuta `ddl/crear_colecciones_indices.py`: 5 colecciones y 20 índices.
3. Ejecuta `carga/cargar_mongo.py` en un contenedor `python:3.12-slim`. Tarda unos 40 s.

Sin `--limpio`, la carga se vuelve a aplicar sobre la base existente: es idempotente porque usa `ReplaceOne` con
upsert. Cada paso deja su bitácora en `docs/logs/`.

Resultado esperado: `atletas 153,325 · paises 234 · disciplinas 2,087 · ediciones 63 · roles 11` y
`participaciones embebidas: 323,143`. Las mismas cifras que las tablas de la Fase 1.

Paso a paso, en lugar del script:

```bash
docker run -d --name mongodb_olimpiadas -p 27017:27017 -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 -v mongodata_olimpiadas:/data/db mongo:9.0.4
cd "Proyecto Fase 3"
python ddl/crear_colecciones_indices.py --uri "mongodb://admin:admin123@localhost:27017/"
python carga/cargar_mongo.py --uri "mongodb://admin:admin123@localhost:27017/"
```

## 3. Modelo documental

| Colección | `_id` | Contenido |
| --- | --- | --- |
| `atletas` | athlete_id | Ficha (nombre, sexo, NOC, nacimiento, roles), `resumen_medallas` y `participaciones[]` embebidas: año, temporada, ciudad, categoría, deporte, evento, país, equipo, edad, **posición**, empate y **medalla**. Para buscar: `busqueda_nombre` y `palabras_nombre` (sin tildes) |
| `paises` | NOC | Nombre, `resumen`, `medallero` (total, `por_anio`, `por_deporte`, contado por evento), `anios_participacion`, `participaciones[]` por edición (atletas y participaciones), `poblaciones[]` y `ediciones_sede[]` |
| `ediciones` | id_edicion | Año, temporada, categoría (Olympics/Youth/Special), ciudad, NOC sede y total de participaciones |
| `disciplinas` | id_disciplina | Deporte + evento |
| `roles` | rol_id | Catálogo de roles |

## 4. Consultas

Se ejecutan desde `Proyecto Fase 3`. La conexión se toma de `--uri`/`--base` o de las variables `MONGO_URI` y
`MONGO_BASE`. Por defecto es `mongodb://admin:admin123@localhost:27017/` y la base `olimpiadas`.

### (c) Atleta — `consulta/atleta.py`

```bash
python consulta/atleta.py "Michael Phelps"
python consulta/atleta.py "erick barrondo"                     # sin tildes, en cualquier orden, parcial
python consulta/atleta.py Phelps --anio 2008 --medalla oro
python consulta/atleta.py "Usain Bolt" --pais JAM --desde 2008 --hasta 2016
python consulta/atleta.py "John Smith" --max-atletas 0         # solo la lista de homónimos
python consulta/atleta.py --id 123159
```

Muestra la ficha del atleta (nombre completo, sexo, país, nacimiento, fallecimiento, afiliaciones, roles), sus
medallas, las ediciones en que participó y una tabla con cada participación: año, temporada, ciudad, deporte,
evento, NOC, equipo, edad, **posición** y **medalla**. Si varios atletas coinciden, primero lista las
coincidencias (las exactas marcadas `← exacto`, ordenadas por medallas) y luego muestra la ficha de las primeras
`--max-atletas`.

| Parámetro | Descripción |
| --- | --- |
| `nombre` | Nombre o parte del nombre. Cada palabra se busca como inicio de palabra, sin importar mayúsculas ni tildes |
| `--id N` | athlete_id exacto |
| `--pais NOC` · `--anio A` · `--desde A --hasta A` · `--temporada Summer/Winter` | Filtran las participaciones |
| `--deporte X` · `--evento X` | Texto parcial, por ejemplo `--deporte swim` |
| `--medalla oro/plata/bronce/todas` | También acepta Gold/Silver/Bronze |
| `--max-atletas N` (3) · `--limite N` (100) | Fichas a mostrar si hay varias coincidencias · participaciones por ficha |
| `--explain` | Muestra el plan de ejecución (índice, keys y docs examinados, ms) |

### (d) País — `consulta/pais.py`

```bash
python consulta/pais.py GUA
python consulta/pais.py "Guatemala"                            # también por nombre
python consulta/pais.py USA --anio 2008
python consulta/pais.py MEX --desde 2000 --hasta 2020 --deporte Diving
python consulta/pais.py JAM --medalla oro --limite 50
python consulta/pais.py GUA --anio 2024 --atletas --resultados
```

Muestra el resumen del país (atletas, participaciones, ediciones y población) y su medallero. Indica **si ha sido
sede y en qué años** (con ciudad y categoría) y lista los **años de participación**. Incluye tres tablas:
participación y medallas por edición (marcando las ediciones en que fue `SEDE`, con su población de ese año), el
medallero por deporte y las **medallas ganadas** con sus atletas. Con `--atletas` agrega la lista de atletas y con
`--resultados` todas las participaciones con su posición. Los filtros (`--anio`, `--desde/--hasta`, `--deporte`,
`--evento`, `--temporada`, `--medalla`) recalculan todas las tablas. `ROC` y `COR` se redirigen a `RUS` y `KOR`.

### Pruebas y rendimiento

```bash
python consulta/ejecutar_pruebas.py     # 22 casos (consulta/pruebas.md) → docs/logs/pruebas_consultas_<fecha>.log
python consulta/medir_rendimiento.py    # tabla de tiempos + explain → docs/logs/rendimiento_consultas_<fecha>.log
```

Todas las consultas usan índice y ninguna hace `COLLSCAN`. La búsqueda de un atleta tarda entre 3 y 25 ms y la de un
país entre 4 y 60 ms. El caso más pesado (USA + atletismo + listas completas) tarda unos 145 ms. El detalle está en
[`docs/rendimiento_consultas.md`](docs/rendimiento_consultas.md).

## 5. Problemas comunes

| Síntoma | Solución |
| --- | --- |
| `No se pudo conectar a MongoDB` | `docker start mongodb_olimpiadas` |
| `ImportError: DLL load failed … Control de aplicaciones` al importar pandas | Usar `carga/cargar_todo.sh`, que corre el ETL en Docker. Las consultas solo necesitan pymongo |
| Caracteres raros en la consola de Windows | Los scripts fuerzan UTF-8. En `cmd` antiguo, ejecutar `chcp 65001` |
