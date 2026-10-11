# Convenciones del equipo — Grupo 19

Este documento es la referencia común de los tres integrantes. **Léelo antes de
correr cualquier script.**

---

## 1. Quién es quién

| Integrante | Tipo de carga | Base de datos | Subcarpetas |
|---|---|---|---|
| **Pablo** | por **año** | `db_olimpiadas_anio` | `carga/anio/`, `backup/anio/`, `restauracion/anio/` |
| **José** | por **deporte** | `db_olimpiadas_deporte` | `carga/deporte/`, `backup/deporte/`, `restauracion/deporte/` |
| **Gerardo** | por **deportista** | `db_olimpiadas_deportista` | `carga/deportista/`, `backup/deportista/`, `restauracion/deportista/` |

Datos de cada carga:

| Integrante | Selección |
|---|---|
| Pablo | París 2024 → Tokio 2020 → Río 2016 → Londres 2012 |
| José | 100 m planos femeninos, mismas ediciones |
| Gerardo | Usain Bolt (`athlete_id = 105512`): Atenas 2004 → Pekín 2008 → Londres 2012 → Río 2016 |

---

## 2. Por qué cada quien tiene su propia base de datos

El enunciado pide tres entregas —carga por año, por deporte y por deportista—
sobre **el mismo esquema**, y en cada una hay que "eliminar la base de datos
completa", hacer 3 respaldos completos y 3 diferenciales, y medir tiempos.

Si los tres usáramos `db_olimpiadas`, los scripts se pisarían en silencio:

| Conflicto | Dónde | Qué pasa |
|---|---|---|
| `DROP DATABASE` | `ddl/01` y `restauracion/01` | Borra la base del compañero a medio ciclo |
| `TRUNCATE stg.*` | `carga/01_cargar_staging.sql` | Le vacía el staging ya cargado |
| `DELETE` de staging | `carga/02_proc_*` | **Falla en silencio**: su `INSERT...SELECT` devuelve 0 filas y la carga "termina bien" sin cargar nada |
| `DROP TABLE dbo.*` | `ddl/03_modelo_relacional.sql` | Le borra el modelo |

El peor es el tercero, porque **no da error**: parece que todo salió bien.
Por eso cada persona tiene su base.

---

## 3. Estructura del repositorio

```
/ddl                 COMPARTIDO — el modelo es el mismo para los tres
                     01_crear_base_datos.sql     (recibe -v DbNombre)
                     02_esquema_staging.sql      (recibe -v DbNombre)
                     03_modelo_relacional.sql    (recibe -v DbNombre)
                     00_referencia_DDL_Fase1.sql copia intacta de la Fase 1

/carga/anio/         solo Pablo
/carga/deporte/      solo José
/carga/deportista/   solo Gerardo
/backup/…            igual, una subcarpeta por persona
/restauracion/…      igual, una subcarpeta por persona
/docs/…              igual, una subcarpeta por persona
/logs/               salidas de consola (revisar .gitignore si pesan mucho)
/capturas/           capturas de pantalla

README_anio.md · README_deporte.md · README_deportista.md   uno por persona
CONVENCIONES.md      este archivo
```

---

## 4. Nombres de los respaldos

Son disjuntos por diseño, así que los tres pueden escribir en el mismo volumen:

```
Pablo    →  full_anio.bak        diff_anio_1.bak   diff_anio_2.bak   diff_anio_3.bak
José     →  full_deporte.bak     diff_deporte_1.bak …
Gerardo  →  full_deportista.bak  diff_deportista_1.bak …
```

**Ojo:** si los tres usan el **mismo directorio de backups**, `RESTORE VERIFYONLY`
y los tamaños van a mostrar los 12 archivos mezclados. Eso está bien para el
análisis comparativo, pero cada quien debe dejar claras sus propias filas en la
tabla de tiempos del Checklist (sección 5).

---

## 5. Cómo correr el `ddl` compartido

El nombre de la base se pasa como variable de `sqlcmd`:

```bash
# Pablo
sqlcmd -S localhost,1433 -U sa -P 'Password123!' \
  -v DbNombre=db_olimpiadas_anio  -i ddl/01_crear_base_datos.sql

# José
sqlcmd ... -v DbNombre=db_olimpiadas_deporte   -i ddl/01_crear_base_datos.sql

# Gerardo
sqlcmd ... -v DbNombre=db_olimpiadas_deportista -i ddl/01_crear_base_datos.sql
```

Si se olvida el `-v`, el script falla. Es intencional: es preferible un error
visible a crear la base equivocada.

---

## 6. Levantar el contenedor

```bash
docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Password123!" \
  -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
  -p 1433:1433 --name sqlserver_olimpiadas \
  -v /ruta/CSVs:/var/opt/mssql/csv:ro \
  -v /ruta/backups:/var/opt/mssql/backups \
  -d mcr.microsoft.com/mssql/server:2022-latest
```

Dos avisos que ya costarían tiempo si no se saben:

- El directorio de `backups` debe ser escribible por el usuario `mssql`
  (uid 10001). Si no: `chmod 777 /ruta/backups`. Sin esto el `BACKUP` falla con
  `Operating system error 5 (Access is denied)`.
- `-e MSSQL_COLLATION=..._UTF8` es necesario para que los acentos y los
  caracteres especiales se guarden bien.

---

## 7. Limitación conocida que hay que mencionar en la documentación

Los caracteres multibyte de los CSV se guardan corruptos: `•` sale como `ΓÇó` y
`×` como `├ù`.

**Causa:** `BULK INSERT` en Linux no admite la opción `CODEPAGE` (error 16202),
así que lee el archivo con CP437 en lugar de UTF-8. Se probó todo lo posible
(collation UTF-8 en columnas, en la base, `LANG` en el contenedor,
`MSSQL_COLLATION`) y ninguna lo arregla.

**No afecta** a los conteos, las PK/FK, los tamaños de los `.bak`, los tiempos
ni la fragmentación. Es cosmético. El detalle completo está en la sección 3 de
`README_deportista.md`.

Conviene que **los tres lo mencionen** en la documentación técnica, aunque solo
uno lo haya investigated a fondo: es el mismo problema para los tres, y si lo
documenta una sola persona se lee como un descuido de esa persona.

---

## 8. Reglas para no pisarse

1. **Nunca editar un archivo de otro.** Cada quien trabaja en su subcarpeta.
2. **Los `logs/` y `capturas/` son de todos**, pero suban su propio sufijo:
   `logs/backup_full_deportista.log`, no `logs/backup_full.log`.
3. **Antes de hacer `git pull`, commitear lo propio**, porque el `ddl/` es
   compartido y va a cambiar.
4. Si alguien cambia `ddl/02` o `ddl/03`, **avisar por el grupo**: los tres
   dependen de ese esquema.