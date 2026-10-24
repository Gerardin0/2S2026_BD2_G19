# Documentación Técnica: Despliegue y ETL a MongoDB (Fase 3)

**Autor:** Pablo (Responsable de Carga y ETL)
**Fecha de validación:** 20 de octubre de 2026

Este documento detalla la arquitectura de despliegue local, la secuencia de ejecución de los procesos de transformación de datos (ETL) y las validaciones de integridad aplicadas para migrar el modelo relacional a colecciones de documentos BSON bajo validación estricta de `$jsonSchema`.

## 1. Despliegue de Infraestructura (Contenedor MongoDB)
Para garantizar un entorno reproducible, aislado e independiente del sistema operativo anfitrión, el motor de base de datos se despliega mediante Docker, implementando persistencia de volúmenes con reetiquetado de seguridad (SELinux) para evitar bloqueos de I/O.

```bash
# 1.1 Crear directorio local para persistencia de datos (ignorado en git)
mkdir -p mongodata
chmod 777 mongodata

# 1.2 Ejecutar instancia de MongoDB con credenciales inyectadas
docker run -d \
  --name mongodb_olimpiadas \
  -p 27017:27017 \
  -e MONGO_INITDB_ROOT_USERNAME=admin \
  -e MONGO_INITDB_ROOT_PASSWORD=admin123 \
  -v "$PWD/mongodata:/data/db:z" \
  mongo:9.0.4

```

## 2. Preparación y Curación de Fuentes

Previo a la ingesta masiva, se requiere normalizar los *datasets* generados en la Fase 1 para resolver incompatibilidades de llaves foráneas y datos faltantes históricos.

* **Generación de sedes:** `python3 carga/generar_sedes.py`
* Cruza las 63 ediciones originales inyectando los metadatos faltantes (`noc_sede` y `categoria`), distinguiendo eventos *Youth* y *Special* de los *Olympics* regulares.


* **Expansión de poblaciones:** `python3 carga/regenerar_poblaciones.py`
* Transpila las métricas poblacionales del Banco Mundial mapeando los códigos estándar ISO-3 hacia la nomenclatura NOC del Comité Olímpico, habilitando los cruces documentales $O(1)$.



## 3. Inicialización del Esquema de Base de Datos (DDL)

Se define la estructura de las colecciones aplicando esquemas de validación moderada y generando los índices B-Tree/Text para optimizar los tiempos de búsqueda de los scripts de consulta.

```bash
python3 ddl/crear_colecciones_indices.py --uri "mongodb://admin:admin123@localhost:27017/"

```

## 4. Ejecución del Pipeline ETL Principal

El motor de carga es idempotente: usa `ReplaceOne` con `upsert=True` por `_id`, ejecutado con `bulk_write` en lotes de 10,000 documentos. Lee los CSV de `fuentes/` y, para el NOC de los atletas sin participaciones, `Proyecto Fase 1/datasets/bios.csv`.

```bash
# todo en un paso (levanta el contenedor, crea índices y carga; --limpio borra la base antes)
bash carga/cargar_todo.sh --limpio

# o el ETL solo (requiere pandas y pymongo)
python3 carga/cargar_mongo.py --uri "mongodb://admin:admin123@localhost:27017/"
```

> En Windows con Control de aplicaciones puede estar bloqueada la DLL de numpy. `cargar_todo.sh` corre el ETL dentro de un contenedor `python:3.12-slim` conectado a la red del contenedor de Mongo, así que no necesita pandas local.

### 4.1 Correcciones aplicadas (trazadas en la bitácora `docs/logs/carga_mongo_<fecha>.log`)

| # | Corrección | Resultado en la carga del 2026-10-20 21:42 |
| --- | --- | --- |
| C1 | `ROC` → `RUS` y `COR` → `KOR`, en el NOC del atleta **y** en `participaciones.pais`. Antes solo se corregía el del atleta, y quedaban participaciones con un país que no existe en `paises` | 1,154 participaciones |
| C2 | NOC de los atletas sin participaciones: se toma de `bios.csv` (columna NOC con el nombre del país, cruzada con `tabla_nocs.region`). Si no cruza, se usa `born_country` cuando es un NOC válido. Si no, queda `null`. **Reemplaza la asignación fija a `SWE`**: 106 de esos atletas son de USA | 238 atletas: 219 con NOC, 19 `null` |
| C3 | **IDs de atletas nuevos de París 2024.** En la Fase 1 los atletas nuevos (ids 149815–157639) se numeraron en orden alfabético en `tabla_atletas.csv`, pero en orden de aparición en `tabla_participacion.csv` y `resultados_2024.csv`. El athlete_id se reasigna buscando `presentado_como` por nombre normalizado (y por `noc_2024` si hay homónimos). Ejemplo: el bronce de Pierre Brol (GUA, Trap) estaba asignado a "Shayna Jack" | 10,178 participaciones reasignadas, 0 sin resolver |
| C4 | Nombres sin viñetas (`•`), comillas ni paréntesis. `busqueda_nombre` y `palabras_nombre` van en minúsculas y **sin tildes** (nombre completo + nombre de uso), para buscar con índice | 153,325 atletas |
| C5 | Medallero del país **por evento** (una medalla de equipo cuenta una vez), por año y por deporte. Se conserva también el conteo por atleta | `paises.medallero.por_anio` y `por_deporte` |
| — | Participaciones embebidas con `temporada`, `ciudad`, `categoria` (Olympics/Youth/Special), `equipo`, `edad`, `posicion`, `empate` y `medalla`. El atleta incluye `nacimiento`, `fecha_fallecimiento`, `afiliaciones` y `resumen_medallas` | 323,143 participaciones |
| — | `limpiar_nan()` convierte NaN en `null` BSON, para evitar fallos de `$jsonSchema` | — |

## 5. Auditoría e Integridad de Resultados

Tras la ejecución del pipeline (40 segundos, 2026-10-20 21:42 sobre una base vacía), los conteos transaccionales concuerdan al 100% con los modelos de la Fase 1:

| Colección | Volumen BSON | Fuente de Verificación (Fase 1) | Estado |
| --- | --- | --- | --- |
| **atletas** | 153,325 | `worked_datasets/tabla_atletas.csv` | OK |
| **paises** | 234 | `worked_datasets/tabla_nocs.csv` | OK |
| **disciplinas** | 2,087 | `worked_datasets/tabla_disciplina.csv` | OK |
| **ediciones** | 63 | `worked_datasets/tabla_edicion_juego.csv` | OK |
| **roles** | 11 | `worked_datasets/tabla_rol.csv` | OK |


