# fuentes/ — archivos fuente de apoyo de la Fase 3

Archivos que alimentan las correcciones de la carga a MongoDB (ver `../docs/revision_fuentes_fase3.md`
y `../docs/plan_trabajo_fase3.md`):

| Archivo | Responsable | Contenido |
| --- | --- | --- |
| `ediciones_sede.csv` | Pablo (P2) | `id_edicion_juego,anio,temporada,ciudad,noc_sede,categoria` para las 63 ediciones; completa las 11 ciudades y 6 sedes que faltan y marca *Olympics / Youth / Special* |
| `iso3_noc.csv` | Pablo (P3) | Mapeo código ISO-3 del Banco Mundial → código NOC (`DEU,GER`, `CHE,SUI`, `GTM,GUA`, …) usado para cargar `paises.poblaciones[]` |

Nada de estos archivos se genera con pandas del repositorio: son datos curados, por eso viven
separados de `datasets/` (Fase 1) y de `worked_datasets/`.
