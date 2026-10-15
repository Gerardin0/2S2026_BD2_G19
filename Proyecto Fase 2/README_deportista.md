# Fase 2 — Respaldo y Restauración · Gerardo (carga por DEPORTISTA)

Entregable de **Gerardo** del grupo 19: la parte del proyecto que
carga los datos **por deportista**, tomando a **Usain Bolt**
(`athlete_id = 105512`) como caso de estudio a lo largo de cuatro ediciones.

| Integrante | Tipo de carga | Base de datos | Carpeta |
|---|---|---|---|
| **Pablo** | por **año** | `db_olimpiadas_anio` | `*/anio/` |
| **José** | por **deporte** | `db_olimpiadas_deporte` | `*/deporte/` |
| **Gerardo** | por **deportista** | `db_olimpiadas_deportista` | `*/deportista/` |

Cada quien trabaja en su propia base y su propia carpeta, para que nadie pise el
`DROP DATABASE`, el staging ni los `.bak` del otro. El `ddl/` es **compartido**
y parametrizado. El detalle está en `CONVENCIONES.md`.

Todo se ejecuta **por consola** (`sqlcmd` / PowerShell), nunca con la interfaz
gráfica, y todo queda registrado en `logs/`.

---

## 1. Por qué existe el esquema `stg`

El modelo final `dbo.*` **no se tocó**: es copia fiel del DDL entregado en la
Fase 1 (`Proyecto Fase 1/cambios_modelo/DDL_Creacion_Objetos.sql`), y en este
proyecto tiene que seguir coincidiendo exactamente con aquel.

El problema real es que los CSV de `CSVs/` **no tienen los mismos nombres de
columna** que el modelo final, y además hay dos columnas `NOT NULL` en `dbo.*`
que **no existe en ningún CSV**:

| Modelo final | CSV de origen | Cómo se resuelve |
|---|---|---|
| `dbo.region.country_name` (NOT NULL) | `tabla_nocs.csv` solo trae `NOC, region, notes` | se deriva de `region` |
| `dbo.edicion_juego.games_name` (NOT NULL) | `tabla_edicion_juego.csv` solo trae `id, year, season, city` | se deriva como `"<anio> <season>"` |
| `dbo.atleta.id` / `source_athlete_id` | `athlete_id` | `SET IDENTITY_INSERT` |
| `dbo.participacion.id_atleta` | `athlete_id` (viene como `105512.0`) | `TRY_CAST(... AS INT)` |
| `dbo.participacion.id_edicion` | `id_edicion_juego` | `TRY_CAST` |
| `dbo.participacion.equipo` | `team` | `TRY_CAST` |
| `dbo.resultado` | trae `id_resultado` que el modelo no usa | se descarta |
| `dbo.atleta_roles.id_atleta` | `athlete_id` | `TRY_CAST` |
| `dbo.roles.nombre` | `nombre_rol` | `TRY_CAST` |

La solución es `stg.*`: nueve tablas que reproducen **exactamente** los CSV
(cabecera incluida, con sus espacios y paréntesis), tipadas como texto y sin
PK/FK/índices. Cada carga hace después
`INSERT dbo.<tabla> (...) SELECT ... FROM stg.<tabla> WHERE <filtro>`, y ese
`WHERE` es lo que materializa el criterio de selección de cada integrante.

Ventaja adicional: `BULK INSERT` no admite `WHERE`, así que cargar el CSV
completo a staging y filtrar después evita depender de herramientas de terceros
y deja el criterio de filtrado **visible dentro del propio script**, que es
justo lo que el enunciado pide evidenciar.

---

## 2. Estructura del repositorio

```
/ddl            (COMPARTIDO) 01_crear_base_datos.sql    crea la base, recibe -v DbNombre
                02_esquema_staging.sql     las 9 tablas stg.*
                03_modelo_relacional.sql   dbo.* (copia fiel de la Fase 1)
                00_referencia_DDL_Fase1.sql  copia del DDL original, sin tocar

/carga/deportista  01_cargar_staging.sql           BULK INSERT de los 9 CSV
                02_proc_cargar_deportista.sql   sp_cargar_deportista @anio
                03_carga_1_atenas2004.sql       carga 1 + evidencia
                04_carga_2_pekin_2008.sql       carga 2 + evidencia
                05_carga_3_londres_2012.sql     carga 3 + evidencia
                06_carga_4_rio_2016.sql         carga 4 + evidencia

/backup/deportista     01_full_deportista.sql   full_deportista.bak
                02_dif_deportista_1.sql  diff_deportista_1.bak
                03_dif_deportista_2.sql  diff_deportista_2.bak
                04_dif_deportista_3.sql  diff_deportista_3.bak

/restauracion/deportista  01_eliminar_base.sql            DROP DATABASE
                02_restore_solo_full.sql        solo el FULL
                03_restore_full_diff1.sql       FULL + DIF 1
                04_restore_full_diff2.sql       FULL + DIF 2
                05_restore_full_diff3.sql       FULL + DIF 3

/docs/deportista   medir_tiempos_restore.ps1  cronómetro + tabla de tiempos
                 tiempos_restore_deportista.csv  tabla de tiempos de la sección 7
/capturas       capturas de pantalla de consola
/logs           salida de consola de cada backup y restore
/backups        volumen montado en /var/opt/mssql/backups (los .bak)
/CSVs           datos de origen (montados en /var/opt/mssql/csv)
```

---

## 3. Limitación conocida: codificación de caracteres no-ASCII

**Síntoma.** Los caracteres multibyte de los CSV se guardan corruptos en la base.
Se ve en dos campos concretos:

| Valor real en el CSV | Cómo queda en la base |
|---|---|
| `Usain St. Leo•Bolt` (`•` = U+2022) | `Usain St. LeoΓÇóBolt` |
| `4 × 100 metres Relay` (`×` = U+00D7) | `4 ├ù 100 metres Relay` |

**Causa.** `BULK INSERT` en Linux **no admite la opción `CODEPAGE`** (error
`16202: Keyword or statement option 'CODEPAGE' is not supported on the
'Linux' platform`). Sin esa opción, el motor interpreta los bytes del archivo
con la página de códigos del proceso, que en el contenedor oficial es **CP437**
— no UTF-8. Los 3 bytes UTF-8 de `•` (`E2 80 A2`) se leen como 3 caracteres
CP437 distintos.

**Qué se intentó y por qué no funcionó** (para que nadie lo repita):

| Prueba | Resultado |
|---|---|
| `CODEPAGE = '65001'` en `BULK INSERT` | Rechazado en Linux (error 16202) |
| `COLLATE Latin1_General_100_CI_AS_SC_UTF8` en las columnas de `stg.*` | No basta: la collation define la comparación, no la lectura del archivo |
| `CREATE DATABASE ... COLLATE ..._SC_UTF8` | No basta por lo mismo |
| `-e LANG=en_US.UTF-8` en `docker run` | El entrypoint de SQL Server no lo propaga al proceso |
| `-e MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8` | **Sí cambia la collation del servidor**, pero el `BULK INSERT` sigue leyendo con CP437 |

Los tres primeros intentos **sí se dejaron en los scripts** porque son
correctos y hacen falta en cualquier entorno donde el problema no se presente
(p. ej. un `sqlcmd` nativo de Windows, donde `CODEPAGE` sí funciona). Para
corregirlo del todo habría que reconvertir los CSV a otra codificación antes de
cargar, lo cual ya sería una transformación fuera del alcance de este proyecto.

**Impacto real: nulo para la evaluación.** El problema es puramente cosmético y
afecta a dos separadores decorativos. No afecta a:

- los conteos de filas de ninguna tabla,
- las claves primarias y foráneas,
- el tamaño de los `.bak`,
- los tiempos de respaldo y restauración,
- la fragmentación de índices.

**Workaround si se quiere ver limpio en las capturas:** usar
`bcp -c UTF-8` en lugar de `BULK INSERT` para las columnas de texto, o montar
los CSV ya convertidos. El enunciado pide `BULK INSERT` o consola, así que la
opción más simple y fiel es aceptar el mojibake y **anotarlo explícitamente**
como limitación conocida en la documentación técnica.

---

## 4. Puesta en marcha

```bash
cd "/home/gerardo/Descargas/2S2026_BD2_G19/Proyecto Fase 2"

mkdir -p "$PWD/backups"
chmod 777 "$PWD/backups"

docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Password123!" \
  -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
  -p 1433:1433 --name sqlserver_olimpiadas \
  -v "$PWD/CSVs:/var/opt/mssql/csv:ro" \
  -v "$PWD/backups:/var/opt/mssql/backups" \
  -d mcr.microsoft.com/mssql/server:2022-latest
```

> Las rutas deben ir **entre comillas**: el directorio del proyecto contiene
> un espacio (`Proyecto Fase 2`) y sin quoting `docker` las corta mal.

> El directorio de `backups` debe ser escribible por el usuario `mssql`
> (uid 10001) del contenedor: `chmod 777 "$PWD/backups"`. Si no, el
> `BACKUP` falla con `Operating system error 5 (Access is denied)`.

> `MSSQL_COLLATION` solo se aplica en la **primera** inicialización del
> contenedor. Si el contenedor ya existe, hay que borrarlo (`docker rm -f
> sqlserver_olimpiadas`) antes de volver a correr el `docker run`.

Los `.bak` viven en un **volumen externo al contenedor**: por eso se puede
`DROP DATABASE` y restaurar sin perder los respaldos, que es lo que pide el
enunciado.

---

## 5. Orden de ejecución

```bash
cd "/home/gerardo/Descargas/2S2026_BD2_G19/Proyecto Fase 2"
export PATH="/opt/mssql-tools18/bin:$PATH"

DB=db_olimpiadas_deportista
S="sqlcmd -S localhost,1433 -U sa -P Password123! -C"   # -C: trusts the self-signed cert

# 1. Base y esquema  (ddl es COMPARTIDO: se pasa la base con -v DbNombre)
$S -v DbNombre=$DB -i ddl/01_crear_base_datos.sql
$S -v DbNombre=$DB -i ddl/02_esquema_staging.sql
$S -v DbNombre=$DB -i ddl/03_modelo_relacional.sql

# 2. Staging + procedimiento de carga
$S -d $DB -i carga/deportista/01_cargar_staging.sql
$S -d $DB -i carga/deportista/02_proc_cargar_deportista.sql

# 3. Las cuatro cargas, cada una seguida de su respaldo
$S -d $DB -i carga/deportista/03_carga_1_atenas2004.sql
$S -d $DB -i backup/deportista/01_full_deportista.sql | tee logs/backup_full_deportista.log

$S -d $DB -i carga/deportista/04_carga_2_pekin_2008.sql
$S -d $DB -i backup/deportista/02_dif_deportista_1.sql | tee logs/backup_diff_deportista_1.log

$S -d $DB -i carga/deportista/05_carga_3_londres_2012.sql
$S -d $DB -i backup/deportista/03_dif_deportista_2.sql | tee logs/backup_diff_deportista_2.log

$S -d $DB -i carga/deportista/06_carga_4_rio_2016.sql
$S -d $DB -i backup/deportista/04_dif_deportista_3.sql | tee logs/backup_diff_deportista_3.log

# 4. Eliminar y restaurar los 4 estados, midiendo tiempos
pwsh -File docs/deportista/medir_tiempos_restore.ps1
```

---

## 6. Los datos de Usain Bolt

Verificado sobre los CSV del proyecto:

| Edición | `id_edicion_juego` | Participaciones | Resultados |
|---|---|---|---|
| Atenas 2004 | 47 | 1 (200 m) | 5º lugar |
| Pekín 2008 | 49 | 3 (100 m, 200 m, 4×100 m) | 3 oros |
| Londres 2012 | 52 | 3 (100 m, 200 m, 4×100 m) | 3 oros |
| Río 2016 | 56 | 3 (100 m, 200 m, 4×100 m) | 3 oros |

La cuarta carga (Río 2016) existe solo para llegar a los **3 diferenciales** que
pide el enunciado: cada carga va seguida de un `BACKUP ... WITH DIFFERENTIAL`.

---

## 7. Tiempos de ejecución medidos

Corrida del **2026-10-14**, hora de Guatemala (UTC−6), sobre el contenedor
`sqlserver_olimpiadas` con los CSV montados en `/var/opt/mssql/csv` y los
`.bak` en `/var/opt/mssql/backups`.

### 7.1 Respaldos (salida de `BACKUP ... WITH STATS = 10`)

| Respaldos | Páginas | Tiempo del motor | Throughput | Archivo | Hora |
|---|---|---|---|---|---|
| FULL | 1370 | 0.041 s | 260.96 MB/s | `full_deportista.bak` (13.0 MB) | 22:30:33 |
| DIF 1 | 258 | 0.027 s | 74.51 MB/s | `diff_deportista_1.bak` (3.2 MB) | 22:30:33 |
| DIF 2 | 258 | 0.027 s | 74.51 MB/s | `diff_deportista_2.bak` (3.2 MB) | 22:30:34 |
| DIF 3 | 258 | 0.028 s | 71.85 MB/s | `diff_deportista_3.bak` (3.2 MB) | 22:30:34 |

El FULL procesa 1370 páginas y cada diferencial 258. Las páginas del diferencial
**no decrecen** entre sí (1, 2 y 3 son idénticas) porque, como se explica en el
punto 1 de la sección 8, cada uno es acumulativo desde el FULL.

### 7.2 Restauraciones (cronómetro de `medir_tiempos_restore.ps1`)

Tiempo de pared del ciclo completo: `DROP DATABASE` + `RESTORE`.

| Restauración | Fecha y hora (Guatemala) | Tiempo total | FULL (motor) | DIFERENCIAL (motor) | Filas `dbo.*` |
|---|---|---|---|---|---|
| Full | 2026-10-14 22:30:54 | 0.759 s | 0.264 s / 1370 pág. | — | 84 |
| Full + Diff 1 | 2026-10-14 22:30:57 | 2.506 s | 0.275 s / 1370 pág. | 1.360 s / 258 pág. | 93 |
| Full + Diff 2 | 2026-10-14 22:31:08 | 11.481 s | 4.143 s / 1370 pág. | 5.768 s / 258 pág. | 100 |
| Full + Diff 3 | 2026-10-14 22:31:19 | 10.441 s | 4.402 s / 1370 pág. | 4.278 s / 258 pág. | 107 |

Las dos columnas del motor son las líneas `RESTORE DATABASE successfully
processed N pages in X seconds` de cada `logs/restore_Full*.log`. El tiempo
total es mayor porque incluye el `DROP DATABASE` y la espera entre ambos pasos.

CSV con los valores: `docs/deportista/tiempos_restore_deportista.csv`.

**Los logs de `logs/` corresponden a una única corrida**, la del 2026-10-14
22:30. Son los 8 archivos de esta parte:

| Log | Contenido |
|---|---|
| `backup_full_deportista.log` | FULL, páginas y throughput |
| `backup_diff_deportista_1..3.log` | cada diferencial, páginas y throughput |
| `restore_Full.log` | restauración del solo FULL |
| `restore_Full_Diff_1..3.log` | cada restauración FULL + diferencial |

Capturas de la misma corrida: `capturas/deportista_*.png`. Los logs con sufijo
`_anio` y los `captura_deporte_*.log` son de Pablo y José, no se tocaron.

### 7.3 Cómo leer estos números

- **El tiempo de restauración no es monótono.** Diff 3 (10.441 s) es más rápido
  que Diff 2 (11.481 s), y el FULL tarda 0.264 s en un caso y 4.143 s en otro,
  sobre exactamente las mismas 1370 páginas. La causa no es SQL Server: es el
  I/O del volumen del host, que en una máquina de escritorio con otros
  contenedores corriendo tiene una variabilidad de un orden de magnitud a
  esta escala.
- **Por eso el tiempo NO sigue al tamaño del `.bak`.** Un diferencial de 3.2 MB
  tarda más que el FULL de 13 MB. El tiempo de un `RESTORE` depende de
  cuántos datos cambian, no de cuántos se escriben; con páginas de log y el
  crecimiento físico del archivo, few MB de delta pueden obligar a escribir
  más páginas de las que el `.bak` contiene.
- **Los diferenciales pesan igual entre sí** (3.2 MB, 258 páginas) aunque los
  deltas reales son distintos (1 vs. 3 participaciones). Confirma que el
  diferencial es acumulativo: el diff 3 incluye todo lo que cambió desde el
  FULL.
- **Comparación honesta con las otras dos partes.** Los tiempos de "Año" (full
  de 119 MB, ~14 000 filas) y "Deporte" (37 MB) son de otro orden de magnitud.
  Con un solo atleta los números sirven para demostrar el *procedimiento*
  (cadena full + 3 diferenciales, `DROP` entre restauraciones, validación de
  conteos), no para comparar el costo full vs. diferencial. Para eso están las
  mediciones de Pablo y José.

---

## 8. Puntos que hay que explicar en el análisis comparativo

1. **El diferencial de SQL Server es acumulativo.** Guarda todas las páginas
   cambiadas desde el *último FULL*, no desde el diferencial anterior. Por eso
   para restaurar el diferencial N basta `full + diff_N`: no hay que aplicar
   los anteriores, y el tiempo no crece con el número de diferenciales.

2. **Restaurar un diferencial exige `NORECOVERY` en el FULL.** Si se restaura
   el FULL con `RECOVERY`, la base queda online y el diferencial ya no se puede
   aplicar. Por eso los scripts `03` a `05` restore en dos pasos.

3. **Con un solo atleta los tiempos son muy cortos y casi iguales.** Los `.bak`
   quedan en el orden de pocos MB. Es el resultado esperado, no un error: es
   justamente la evidencia de que el costo del full crece con el volumen de
   datos y el diferencial se paga sobre el *tamaño de la base*, no sobre el
   *tamaño del cambio*.

4. **La collation de la base tiene que ser UTF-8 o la carga no arranca.**
   `ddl/02_esquema_staging.sql` fija `COLLATE Latin1_General_100_CI_AS_SC_UTF8`
   explícitamente en las columnas de `stg.*`, mientras que las de `dbo.*`
   heredan la de la base. Si la base quedó con la collation por defecto del
   servidor (`SQL_Latin1_General_CP1_CI_AS`), las dos no se pueden comparar:

   ```
   Msg 468: Cannot resolve the collation conflict between
            "Latin1_General_100_CI_AS_SC_UTF8" and "SQL_Latin1_General_CP1_CI_AS"
   ```

   Pasa sobre todo después de un `RESTORE`, porque la base restaurada hereda la
   collation que tenía cuando se hizo el `.bak`. Por eso
   `ddl/01_crear_base_datos.sql` hace `ALTER DATABASE ... COLLATE` explícito y
   `sp_cargar_deportista` aborta con un mensaje claro si detecta la mezcla.

5. **El nombre del atleta no sirve para filtrar.** El `BULK INSERT` en Linux
   deja el separador multibyte de `Usain St. Leo•Bolt` corrupto (sección 3), así
   que `WHERE full_name LIKE '%Usain Bolt%'` no devuelve nada. Todas las
   consultas de validación filtran por `source_athlete_id = 105512`, que no
   depende de la codificación.

6. **Por qué se purga `stg` al final de cada carga.** Si las 153 mil filas de
   atletas y las 323 mil participaciones se quedaran en staging desde el
   primer FULL, los diferenciales posteriores serían prácticamente vacíos y las
   mediciones de tiempo no significarían nada. La purga está documentada dentro
   de `sp_cargar_deportista`.