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
  mongo:latest

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

El motor de carga está diseñado para ser idempotente, permitiendo reejecuciones sin duplicidad de datos mediante operaciones `UpdateOne` con directiva `upsert=True` ejecutadas en la API `bulk_write` por lotes de 10,000 registros para evitar cuellos de botella en la RAM.

```bash
python3 carga/cargar_mongo.py

```

### 4.1 Transformaciones y Correcciones de Limpieza (Data Wrangling)

Durante el proceso de carga en memoria (Pandas), el script aplica dinámicamente las siguientes correcciones sobre anomalías detectadas en los datos de origen:

* **Mapeo de Atletas Nulos:** Se identificaron 237 perfiles de atletas en `bios.csv` carentes de participaciones formales. Se les asignó por defecto el código NOC `SWE` para preservar la integridad referencial.
* **Normalización Geopolítica:** Se homologaron los códigos NOC anómalos interceptados en origen: `ROC` migrado a `RUS` y `COR` migrado a `KOR`.
* **Evasión de Tipos Híbridos:** Las tuplas con atributos ausentes (ej. año de edición o deporte) se trataron mediante `limpiar_nan()` para convertirlas a `null` nativo BSON o valores por defecto (`"Desconocido"`), evitando fallos de aserción del `$jsonSchema` (evitando cruces de `double` a `string`).

## 5. Auditoría e Integridad de Resultados

Tras la ejecución del pipeline (140.40 segundos), los conteos transaccionales concuerdan al 100% con los modelos de la Fase 1:

| Colección | Volumen BSON | Fuente de Verificación (Fase 1) | Estado |
| --- | --- | --- | --- |
| **atletas** | 153,325 | `worked_datasets/tabla_atletas.csv` | OK |
| **paises** | 234 | `worked_datasets/tabla_nocs.csv` | OK |
| **disciplinas** | 2,087 | `worked_datasets/tabla_disciplina.csv` | OK |
| **ediciones** | 63 | `worked_datasets/tabla_edicion_juego.csv` | OK |
| **roles** | 11 | `worked_datasets/tabla_rol.csv` | OK |


