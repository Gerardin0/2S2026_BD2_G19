# Manual de usuario

Guía de extremo a extremo para preparar SQL Server, crear las tres bases de
datos independientes, cargar los datos por **año**, **deporte** y
**deportista**, generar los respaldos y ejecutar las pruebas de restauración.
Los comandos de esta guía se pegan directamente en una terminal Bash; no hay
que crear un script `.sh`.

## 1. Antes de empezar

Abra una terminal y sitúese en la carpeta `Proyecto Fase 2`:

```bash
cd "~/2S2026_BD2_G19/Proyecto Fase 2"
```

Compruebe que existen las carpetas `CSVs/`, `ddl/`, `carga/`, `backup/`,
`restauracion/` y `docs/`. Prepare los directorios que usan los respaldos,
capturas y logs:

```bash
mkdir -p backups logs capturas
chmod 777 backups
chmod -R 755 CSVs
```

> **Atención:** los scripts `ddl/01_crear_base_datos.sql` recrean la base si
> ya existe. Esto elimina los datos actuales de esa base. Los scripts de
> restauración también reemplazan o eliminan bases. No continúe si necesita
> conservar sus datos.

## 2. Iniciar SQL Server en Docker

Este paso solo se realiza si todavía no existe el contenedor
`sqlserver_olimpiadas`. El volumen `backups` del host debe ser el mismo
directorio usado durante los respaldos y restauraciones.

```bash
sudo docker run -e "ACCEPT_EULA=Y" \
  -e "MSSQL_SA_PASSWORD=Password123!" \
  -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
  -p 1433:1433 --name sqlserver_olimpiadas \
  -v "$PWD/CSVs:/var/opt/mssql/csv:ro" \
  -v "$PWD/backups:/var/opt/mssql/backups" \
  -d mcr.microsoft.com/mssql/server:2022-latest
```

Si el contenedor ya está creado y activo, **no vuelva a ejecutar `docker run`**.
Verifique su estado y que SQL Server responda:

```bash
sudo docker ps --filter name=sqlserver_olimpiadas
sudo docker inspect sqlserver_olimpiadas \
  --format '{{range .Mounts}}{{println .Source "->" .Destination}}{{end}}'
```

Confirme que el directorio local montado en `/var/opt/mssql/backups` es el que
quiere usar para los `.bak`. Si aparece, por ejemplo, `backups_fisicos` en vez
de `backups`, dé los permisos a ese directorio y use esa ruta local para
consultar los archivos en la sección 9. No es necesario recrear un contenedor
que ya funciona.

Espere a que SQL Server termine de iniciar y prepare `sqlcmd`:

```bash
export PATH="/opt/mssql-tools18/bin:$PATH"
export MSSQL_SA_PASSWORD='Password123!'
SQLCMD=(sqlcmd -S localhost,1433 -U sa -P "$MSSQL_SA_PASSWORD" -C -b)
```

Compruebe la conexión:

```bash
"${SQLCMD[@]}" -d master -Q "SELECT @@VERSION AS version_sql_server;"
```

En las siguientes instrucciones, `|& tee` muestra la salida en pantalla y
también la guarda en el log. `pipefail` permite que Bash detecte un error de
`sqlcmd` aunque su salida pase por `tee`.

```bash
set -o pipefail
```

## 3. Crear las tres bases y sus esquemas

Las tres bases comparten los archivos DDL, pero se mantienen separadas para que
cada flujo tenga sus propias tablas staging, datos y restauraciones. Ejecute
estos comandos **en orden**:

```bash
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_anio \
  -i ddl/01_crear_base_datos.sql |& tee logs/01_crear_base_datos_anio.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_anio \
  -i ddl/02_esquema_staging.sql |& tee logs/02_esquema_staging_anio.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_anio \
  -i ddl/03_modelo_relacional.sql |& tee logs/03_modelo_relacional_anio.log

"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deporte \
  -i ddl/01_crear_base_datos.sql |& tee logs/01_crear_base_datos_deporte.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deporte \
  -i ddl/02_esquema_staging.sql |& tee logs/02_esquema_staging_deporte.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deporte \
  -i ddl/03_modelo_relacional.sql |& tee logs/03_modelo_relacional_deporte.log

"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deportista \
  -i ddl/01_crear_base_datos.sql |& tee logs/01_crear_base_datos_deportista.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deportista \
  -i ddl/02_esquema_staging.sql |& tee logs/02_esquema_staging_deportista.log
"${SQLCMD[@]}" -d master -v DbNombre=db_olimpiadas_deportista \
  -i ddl/03_modelo_relacional.sql |& tee logs/03_modelo_relacional_deportista.log
```

## 4. Cargar CSV en staging y crear los procedimientos

Los comandos `01_cargar_staging.sql` leen los CSV montados en
`/var/opt/mssql/csv` dentro del contenedor. Esta carga puede tardar debido al
tamaño de los archivos; deje que cada comando termine antes de iniciar el
siguiente.

```bash
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/01_cargar_staging.sql |& tee logs/01_cargar_staging_anio.log
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/02_proc_cargar_anio.sql |& tee logs/02_proc_cargar_anio.log

"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/01_cargar_staging.sql |& tee logs/01_cargar_staging_deporte.log
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/02_proc_cargar_deporte.sql |& tee logs/02_proc_cargar_deporte.log

"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/01_cargar_staging.sql |& tee logs/01_cargar_staging_deportista.log
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/02_proc_cargar_deportista.sql |& tee logs/02_proc_cargar_deportista.log
```

El procedimiento de deportista usa una purga optimizada de staging
(`TRUNCATE + INSERT` del subconjunto necesario). Si actualizó el archivo del
procedimiento mientras el contenedor ya estaba activo, vuelva a ejecutar su
comando de creación anterior a la carga. No lo haga mientras una carga siga
ejecutándose; la versión nueva solo afecta las ejecuciones posteriores.

## 5. Ejecutar carga por año y sus respaldos

Cada carga debe finalizar antes de ejecutar el respaldo que le sigue. El Full
se toma después de la primera edición; cada diferencial se toma después de la
carga siguiente.

```bash
# Año: París 2024 + Full
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/03_carga_1_paris2024.sql |& tee logs/03_carga_1_paris2024_anio.log
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i backup/anio/01_full_anio.sql |& tee logs/01_full_anio.log

# Año: Tokio 2020 + Diferencial 1
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/04_carga_2_tokio_2020.sql |& tee logs/04_carga_2_tokio_2020_anio.log
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i backup/anio/02_dif_anio_1.sql |& tee logs/02_dif_anio_1.log

# Año: Río 2016 + Diferencial 2
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/05_carga_3_rio_2016.sql |& tee logs/05_carga_3_rio_2016_anio.log
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i backup/anio/03_dif_anio_2.sql |& tee logs/03_dif_anio_2.log

# Año: Londres 2012 + Diferencial 3
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i carga/anio/06_carga_4_londres_2012.sql |& tee logs/06_carga_4_londres_2012_anio.log
"${SQLCMD[@]}" -d db_olimpiadas_anio \
  -i backup/anio/04_dif_anio_3.sql |& tee logs/04_dif_anio_3.log
```

## 6. Ejecutar carga por deporte y sus respaldos

Esta carga corresponde a la disciplina `237` (100 metros planos femeninos).

```bash
# Deporte: París 2024 + Full
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/03_carga_1_paris_2024.sql |& tee logs/03_carga_1_paris_2024_deporte.log
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i backup/deporte/01_full_deporte.sql |& tee logs/backup_full_deporte.log

# Deporte: Tokio 2020 + Diferencial 1
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/04_carga_2_tokio_2020.sql |& tee logs/04_carga_2_tokio_2020_deporte.log
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i backup/deporte/02_dif_deporte_1.sql |& tee logs/backup_diff_deporte_1.log

# Deporte: Río 2016 + Diferencial 2
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/05_carga_3_rio_2016.sql |& tee logs/05_carga_3_rio_2016_deporte.log
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i backup/deporte/03_dif_deporte_2.sql |& tee logs/backup_diff_deporte_2.log

# Deporte: Londres 2012 + Diferencial 3
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i carga/deporte/06_carga_4_londres_2012.sql |& tee logs/06_carga_4_londres_2012_deporte.log
"${SQLCMD[@]}" -d db_olimpiadas_deporte \
  -i backup/deporte/04_dif_deporte_3.sql |& tee logs/backup_diff_deporte_3.log
```

## 7. Ejecutar carga por deportista y sus respaldos

Esta carga usa a Usain Bolt (`athlete_id = 105512`) y las ediciones de 2004,
2008, 2012 y 2016.

```bash
# Deportista: Atenas 2004 + Full
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/03_carga_1_atenas2004.sql |& tee logs/03_carga_1_atenas2004_deportista.log
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i backup/deportista/01_full_deportista.sql |& tee logs/backup_full_deportista.log

# Deportista: Pekín 2008 + Diferencial 1
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/04_carga_2_pekin_2008.sql |& tee logs/04_carga_2_pekin_2008_deportista.log
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i backup/deportista/02_dif_deportista_1.sql |& tee logs/backup_diff_deportista_1.log

# Deportista: Londres 2012 + Diferencial 2
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/05_carga_3_londres_2012.sql |& tee logs/05_carga_3_londres_2012_deportista.log
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i backup/deportista/03_dif_deportista_2.sql |& tee logs/backup_diff_deportista_2.log

# Deportista: Río 2016 + Diferencial 3
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i carga/deportista/06_carga_4_rio_2016.sql |& tee logs/06_carga_4_rio_2016_deportista.log
"${SQLCMD[@]}" -d db_olimpiadas_deportista \
  -i backup/deportista/04_dif_deportista_3.sql |& tee logs/backup_diff_deportista_3.log
```

## 8. Qué respaldar y cómo interpretar el resultado

Cada flujo produce cuatro archivos: un respaldo **Full** después de su primera
carga y tres **diferenciales**, uno después de cada carga posterior. Los
comandos anteriores ejecutan los scripts SQL específicos de cada flujo, de
modo que el nombre de la base y el archivo `.bak` sean los correspondientes:

| Flujo | Base de datos | Full | Diferenciales |
|---|---|---|---|
| Año | `db_olimpiadas_anio` | `full_anio.bak` | `diff_anio_1.bak` a `diff_anio_3.bak` |
| Deporte | `db_olimpiadas_deporte` | `full_deporte.bak` | `diff_deporte_1.bak` a `diff_deporte_3.bak` |
| Deportista | `db_olimpiadas_deportista` | `full_deportista.bak` | `diff_deportista_1.bak` a `diff_deportista_3.bak` |

Los archivos se escriben **dentro del contenedor** en
`/var/opt/mssql/backups/`; el volumen Docker los persiste en la carpeta local
montada en ese destino. Mantenga el mismo volumen durante respaldo y
restauración.

El Full es la base de la cadena. Cada diferencial es **acumulativo desde el
último Full**, no desde el diferencial anterior. Por ejemplo, para volver al
estado después de la segunda carga se restaura `full_*.bak` y luego
`diff_*_2.bak`; no se aplican `diff_*_1.bak` ni el diferencial 2 encima del 1.
`WITH INIT` sobrescribe el archivo del mismo nombre si ya existía, lo cual
permite repetir la corrida, pero reemplaza ese respaldo previo.

En el log de un backup, la secuencia habitual es:

1. `BACKUP ... successfully processed ... pages in ... seconds`: SQL Server
   terminó de escribir el respaldo. Las páginas son unidades de 8 KiB; el
   tiempo y el throughput corresponden al motor.
2. La fila de `msdb` muestra la base, el tipo, la ruta del archivo y la fecha
   final del respaldo.
3. `The backup set on file 1 is valid.`: `RESTORE VERIFYONLY` pudo leer y
   validar el conjunto de backup. Es una verificación de legibilidad, no una
   restauración de prueba.
4. `FULL creado: ...` o `Diferencial N creado: ...`: mensaje final del script.

`STATS = 10` muestra porcentajes de avance. En archivos pequeños algunos
porcentajes pueden no aparecer; lo importante es que aparezca el mensaje de
éxito y que `VERIFYONLY` confirme la validez.

## 9. Ejecutar pruebas de restauración

Ejecute estas pruebas **después de terminar y verificar todos los backups**.
Cada herramienta elimina la base entre restauraciones y ejecuta cuatro
escenarios: solo Full, Full + Diferencial 1, Full + Diferencial 2 y Full +
Diferencial 3. Al terminar, la base queda restaurada al estado del último
diferencial.

**Precaución:** estas pruebas son destructivas para la base indicada. Antes de
cada escenario eliminan la base existente y luego la reemplazan con el backup.
No escriba ni cargue datos en esas bases mientras el medidor está corriendo.

La restauración solo Full aplica `WITH RECOVERY` y deja la base disponible.
Para restaurar un Full seguido de un diferencial, el script hace dos pasos:

1. Restaura el Full con `NORECOVERY`. La base queda en estado `RESTORING` y no
   acepta consultas todavía.
2. Restaura el diferencial elegido con `RECOVERY`. Esto completa el escenario
   y vuelve a dejar la base en línea.

No cambie el `NORECOVERY` del primer paso por `RECOVERY`: al recuperar la base
después del Full, SQL Server ya no permite aplicar el diferencial encima.
Tampoco aplique todos los diferenciales en cadena; cada diferencial corresponde
a un escenario independiente, siempre junto al Full.

```bash
# Restauraciones y medición para la carga por año
chmod +x docs/anio/medir_tiempos_restore.sh
./docs/anio/medir_tiempos_restore.sh
cat docs/anio/tiempos_restore_anio.csv

# Restauraciones y medición para la carga por deporte
pwsh -File docs/deporte/medir_tiempos_restore.ps1 \
  -Password "$MSSQL_SA_PASSWORD"
cat docs/deporte/tiempos_restore_deporte.csv

# Restauraciones y medición para la carga por deportista
pwsh -File docs/deportista/medir_tiempos_restore.ps1 \
  -Password "$MSSQL_SA_PASSWORD"
cat docs/deportista/tiempos_restore_deportista.csv
```

La prueba de año ejecuta `sqlcmd` dentro del contenedor y sus parámetros de
conexión usan la contraseña `Password123!`; si configuró otra clave, ajuste el
parámetro `-P` en `docs/anio/medir_tiempos_restore.sh` antes de ejecutarlo.
Las pruebas de deporte y deportista necesitan PowerShell (`pwsh`) y el
`sqlcmd` nativo disponible en el `PATH`.

El CSV de restauración por deportista incluye `filas_restauradas`: el conteo
de las filas devueltas por `participacion JOIN edicion_juego` en cada estado
restaurado. Al volver a ejecutar el medidor, el CSV se regenera con tiempos y
conteos de esa nueva corrida. Para los respaldos descritos en este proyecto,
los conteos esperados son 1 (Full), 4 (Full + Diff 1), 7 (Full + Diff 2) y 10
(Full + Diff 3).

## 10. Validar resultados y logs

Los respaldos deben terminar con un mensaje de éxito de `BACKUP DATABASE` y
`The backup set ... is valid.` Los archivos `.bak` se encuentran en el
directorio del host montado como `/var/opt/mssql/backups`:

```bash
ls -lh backups
```

Para revisar errores de las cargas o backups:

```bash
grep -n -E "Msg [0-9]+|Error|ERROR|failed|terminating abnormally" logs/*.log
```

### Cómo leer los logs de carga, backup y restore

`tee` guarda en `logs/` lo que muestra `sqlcmd` en pantalla. La opción `-b` de
`SQLCMD` hace que SQLCMD retorne un código distinto de cero si SQL Server
devuelve un error de severidad suficiente. Como los comandos usan `|& tee`,
Bash conserva ese resultado gracias a `set -o pipefail`. Por eso, si un comando
falla, no ejecute el paso siguiente aunque el prompt haya regresado.

| Mensaje o síntoma | Interpretación y qué revisar |
|---|---|
| `... successfully processed N pages in ... seconds` | Operación completada por el motor. En backup/restore, `N` es el número de páginas procesadas. |
| `The backup set ... is valid.` | La verificación del archivo de backup terminó correctamente. |
| `Msg <número>, Level ...` | Error de SQL Server. Lea también las líneas siguientes: normalmente contienen la causa concreta y el objeto/archivo afectado. |
| `BACKUP DATABASE is terminating abnormally` o `RESTORE DATABASE is terminating abnormally` | La operación no se completó; el mensaje anterior suele explicar la causa. No considere creado/restaurado el backup/base. |
| `Operating system error 5 (Access is denied.)` | El usuario `mssql` del contenedor no puede escribir o leer la carpeta/archivo montado. Revise permisos del host y el volumen Docker. |
| `Operating system error 2 (The system cannot find the file specified.)` | El archivo `.bak` no está en la ruta del contenedor, o el volumen/ruta de backup no coincide. Compruebe el montaje y `ls -lh` en su ruta local. |
| `Database '...' does not exist` / `Cannot open database ... requested by the login` | La base no fue creada, se eliminó o se especificó un nombre/base inicial incorrectos. Confirme que DDL finalizó y conecte con `-d` a la base correcta. |
| `Changed database context to ...` | Mensaje informativo; confirma el cambio de contexto, no el éxito de todo el script. |
| El comando sigue activo, no imprime líneas por un tiempo | Puede estar procesando un `BULK INSERT`, un `DELETE` o una consulta de evidencia. Revise solicitudes activas en SQL Server desde otra terminal; no lance otra copia de la misma carga. |

Un mensaje `Carga ... completada` o `... finalizada` indica el final de la
etapa de carga, pero verifique también que no haya un `Msg ...` más arriba.
Cuando un script genera tablas de resultados, valide que los conteos coincidan
con el escenario restaurado. Para deportista, el medidor escribe el total del
JOIN `participacion`–`edicion_juego` en `filas_restauradas`: se esperan 1, 4, 7
y 10 para Full, Full + Diff 1, Full + Diff 2 y Full + Diff 3, respectivamente.

No continúe al siguiente ciclo si un comando termina con error. Las tres cargas
de staging procesan CSV grandes y pueden tardar; mientras corren se puede ver
el progreso directamente en la terminal y guardarlo simultáneamente en su
archivo de log.

El backup diferencial de SQL Server es acumulativo desde el Full: para
restaurar el estado N se aplica el Full y solo el Diferencial N, no los
diferenciales anteriores.
