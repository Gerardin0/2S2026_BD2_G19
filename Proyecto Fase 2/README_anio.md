# Manual de Ejecución End-to-End: Carga, Respaldo y Restauración (Estrategia por Año)

Este documento detalla el proceso completo para desplegar la infraestructura, inicializar el esquema de base de datos, ejecutar las cargas masivas por año e implementar la estrategia de copias de seguridad (Full + Diferenciales) junto con sus pruebas de restauración.

## Fase 1: Preparación del Entorno Físico y Permisos

Antes de levantar la infraestructura, es necesario asegurar la estructura de directorios y los permisos de lectura/escritura (especialmente crítico en distribuciones con SELinux como Fedora).

```bash
# 1. Crear subcarpetas exclusivas para el alcance "por año"
mkdir -p carga/anio backup/anio restauracion/anio docs/anio capturas logs

# 2. Crear volumen local para backups y asignar permisos totales (requerido por el usuario mssql)
mkdir -p backups_fisicos
chmod 777 backups_fisicos

# 3. Asegurar permisos de lectura en la carpeta de datos crudos
chmod -R 755 CSVs/
```

## Fase 2: Despliegue de Infraestructura

Se levanta el motor de base de datos mapeando los volúmenes locales. La bandera :z indica a SELinux que comparta el directorio con el contenedor Docker.

```bash
sudo docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Password123!" \
  -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
  -p 1433:1433 --name sqlserver_olimpiadas \
  -v "$PWD/CSVs:/var/opt/mssql/csv:ro" \
  -v "$PWD/backups:/var/opt/mssql/backups" \
  -d mcr.microsoft.com/mssql/server:2022-latest

# Nota: Esperar ~15 segundos antes de avanzar al siguiente paso para que el motor SQL Server inicie correctamente.
```

## Fase 3: Inicialización DDL

Se inyectan los scripts compartidos pasando la variable *-v DbNombre=db_olimpiadas_anio* para mantener el aislamiento de las bases de datos respecto al resto del equipo.

```bash
# 1. Creación de la Base de Datos
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/01_crear_base_datos.sql > logs/01_crear_base_datos_anio.log

# 2. Creación del esquema Staging
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/02_esquema_staging.sql > logs/02_esquema_staging_anio.log

# 3. Creación del Modelo Relacional (DBO)
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/03_modelo_relacional.sql > logs/03_modelo_relacional_anio.log
```

## Fase 4: Preparación del ETL y Carga Inicial (París 2024)

Se cargan los datos crudos a memoria, se compila la lógica de negocio y se ejecuta la primera carga que servirá como base para el Full Backup.

```bash
# 1. Volcado masivo (BULK INSERT) a esquema Staging
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/01_cargar_staging.sql > logs/01_cargar_staging_anio.log

# 2. Compilación del Procedimiento Almacenado optimizado
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/02_proc_cargar_anio.sql > logs/02_proc_cargar_anio.log

# 3. Ejecución de Carga 1 (París 2024)
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/03_carga_1_paris2024.sql > logs/03_carga_1_paris2024_anio.log

# 4. Creación del Respaldo Completo (Full Backup)
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/01_full_anio.sql > logs/01_full_anio.log
```

## Fase 5: Cargas Incrementales y Backups Diferenciales

Se ejecutan los ciclos de ingesta para los años anteriores, respaldando la base de datos de manera acumulativa inmediatamente después de cada carga.

```bash
# CICLO 2: Tokio 2020 + Diferencial 1
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/04_carga_2_tokio_2020.sql > logs/04_carga_2_tokio_2020_anio.log
# Diferencial 1
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/02_dif_anio_1.sql > logs/02_dif_anio_1.log

# CICLO 3: Río 2016 + Diferencial 2
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/05_carga_3_rio_2016.sql > logs/05_carga_3_rio_2016_anio.log
# Diferencial 2
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/03_dif_anio_2.sql > logs/03_dif_anio_2.log

# CICLO 4: Londres 2012 + Diferencial 3
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/06_carga_4_londres_2012.sql > logs/06_carga_4_londres_2012_anio.log
# Diferencial 3
docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/04_dif_anio_3.sql > logs/04_dif_anio_3.log
```

## Fase 6: Pruebas de Restauración y Auditoría de Tiempos

Se ejecuta el script automatizado que intercala eliminaciones completas de la base de datos (DROP DATABASE) con las 4 combinaciones de restauración (Full, Full+Diff1, Full+Diff2, Full+Diff3), capturando los tiempos en milisegundos y registrando la evidencia.

```bash
# 1. Asignar permisos de ejecución al script
chmod +x docs/anio/medir_tiempos_restore.sh

# 2. Ejecutar la batería de restauraciones
./docs/anio/medir_tiempos_restore.sh

# 3. Validar resultados en el archivo consolidado
cat docs/anio/tiempos_restore_anio.csv
```