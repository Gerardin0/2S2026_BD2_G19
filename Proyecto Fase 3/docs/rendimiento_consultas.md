# Rendimiento de las consultas (C3)

| | |
| --- | --- |
| Fecha de medición | 2026-10-20 21:46:57 |
| Entorno | MongoDB 9.0.4 (Docker `mongo:9.0.4`), Windows 11, base `olimpiadas` recién cargada |
| Script | `python consulta/medir_rendimiento.py` (5 repeticiones por caso) |
| Bitácora | `docs/logs/rendimiento_consultas_20261020_214657.log` |

El tiempo es la suma de las consultas que el script hace a MongoDB, que el propio script muestra como
`consulta resuelta en X ms`. No incluye el arranque de Python, que tarda unos 0.8 s. El plan sale de
`explain` con verbosidad `executionStats` sobre cada `aggregate`. Cualquier consulta puede repetir esta
medición con `--explain`:

```bash
python consulta/atleta.py "erick barrondo" --explain
python consulta/pais.py USA --anio 2008 --explain
```

## Resultados

| Comando | Mín ms | Prom ms | Máx ms | Índices usados | keys / docs examinados (por etapa) | COLLSCAN |
| --- | ---: | ---: | ---: | --- | --- | --- |
| `atleta.py "Michael Phelps"` | 4 | 5 | 8 | _id_, ix_atletas_palabras | 15 / 14; 1 / 1 | no |
| `atleta.py "erick barrondo"` | 3 | 6 | 14 | _id_, ix_atletas_palabras | 6 / 5; 1 / 1 | no |
| `atleta.py Phelps --deporte swim --anio 2008 --medalla oro` | 4 | 5 | 10 | _id_, ix_atletas_palabras | 15 / 14; 1 / 1 | no |
| `atleta.py "usain bolt" --pais JAM --desde 2008 --hasta 2016` | 3 | 6 | 10 | _id_, ix_atletas_palabras | 2 / 1; 1 / 1 | no |
| `atleta.py maria --max-atletas 1` | 21 | 22 | 24 | _id_, ix_atletas_palabras | 1,856 / 1,850; 1 / 1 | no |
| `atleta.py "john smith"` | 6 | 8 | 9 | _id_, ix_atletas_palabras | 403 / 402; 6 / 3 | no |
| `pais.py GUA` | 3 | 4 | 6 | ix_atletas_part_pais | 267 / 267 | no |
| `pais.py Guatemala` | 4 | 6 | 11 | ix_atletas_part_pais | 267 / 267 | no |
| `pais.py USA` | 55 | 60 | 68 | ix_atletas_part_pais | 10,466 / 10,466 | no |
| `pais.py USA --anio 2008` | 35 | 40 | 48 | ix_atletas_part_anio | 10,956 / 10,956; 10,956 / 10,956 | no |
| `pais.py MEX --desde 2000 --hasta 2020 --deporte Diving` | 10 | 13 | 18 | ix_atletas_part_pais | 1,750 / 1,750; 1,750 / 1,750 | no |
| `pais.py USA --deporte Athletics --atletas --resultados` | 139 | 143 | 147 | ix_atletas_part_pais | 10,466 / 10,466 (×4 etapas) | no |
| `pais.py GBR --medalla oro` | 33 | 35 | 36 | ix_atletas_part_pais | 6,659 / 6,659; 6,659 / 6,659 | no |

**Criterio de aceptación cumplido:** ninguna consulta usa `COLLSCAN` sobre `atletas` ni sobre `paises`, y todas
tardan menos de 200 ms. En las búsquedas por índice `totalKeysExamined ≈ totalDocsExamined`.

## Decisiones que explican los tiempos

1. **Búsqueda por nombre con `palabras_nombre` (índice multikey `ix_atletas_palabras`).** La carga guarda cada
   palabra del nombre completo y del nombre de uso en minúsculas y sin tildes. La consulta convierte cada palabra
   buscada en un prefijo anclado (`^barrondo`) dentro de `$all`, y así el índice recorre un rango acotado.
   - Antes, con una regex sin anclar sobre `busqueda_nombre`, se examinaban las **153,325** claves y tardaba
     unos 170 ms.
   - Con un `re.compile` de Python se examinaban **430,998** claves y tardaba unos 520 ms: pymongo envía la bandera
     `u` y con ella Mongo no usa límites de prefijo. Por eso se usa `bson.Regex` sin banderas.
   - Ahora se examinan entre 6 y 15 claves y tarda unos 5 ms.
2. **La ficha del atleta se lee por `_id` (`IDHACK`).** Primero se obtiene la lista ligera de coincidencias y
   después se trae el detalle solo de los elegidos. Las participaciones se recortan con `$filter` en el servidor,
   sin `$unwind` previo.
3. **El resumen del país está precalculado en `paises`.** Contiene el medallero total, por año y por deporte, las
   ediciones con atletas y participaciones, los años de participación y las sedes. `pais.py GUA` sin filtros solo
   lee un documento de 6 KB (el mayor, USA, pesa 21 KB). Únicamente la lista de medallas ganadas se agrega sobre
   `atletas`.
4. **Con filtros, el `$match` va sobre el arreglo embebido con `$elemMatch`.** Usa `ix_atletas_part_pais` o
   `ix_atletas_part_anio` según lo que elija el planificador, y luego hace un `$filter`/`$unwind` solo de los
   documentos ya seleccionados.
5. **El caso más pesado** (USA + Athletics + lista de atletas + todas las participaciones) hace 4 agregaciones
   de unos 35 ms cada una y se mantiene por debajo de 150 ms.

## Tamaño de las colecciones

| Colección | Documentos | Datos | Promedio por documento | Índices |
| --- | ---: | ---: | ---: | ---: |
| atletas | 153,325 | 176.9 MiB | 1,209 B (máx. 14 KB) | 22.3 MiB |
| paises | 234 | 1.4 MiB | 6,298 B (máx. USA 21 KB) | 0.2 MiB |
| disciplinas | 2,087 | 0.2 MiB | 88 B | 0.1 MiB |
| ediciones | 63 | < 0.1 MiB | 202 B | 0.1 MiB |
| roles | 11 | < 0.1 MiB | 59 B | < 0.1 MiB |
