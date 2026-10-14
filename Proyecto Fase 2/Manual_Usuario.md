## MANUAL DE USUARIO
*Guía práctica paso a paso para operar el sistema de copias de seguridad, restauraciones y validación en SQL Server.*

### 1. Cómo realizar cada tipo de Backup
Las operaciones se ejecutan mediante consola usando la utilidad `sqlcmd` conectada al contenedor Docker, apuntando a scripts T-SQL predefinidos. Los archivos resultantes (`.bak`) se guardan en el volumen físico mapeado en `/var/opt/mssql/backups`.

**A. Backup Completo (Full)**
Crea una copia base de toda la base de datos. Debe ejecutarse obligatoriamente después de la carga inicial.
* **Ejecución en consola:**
  ```bash
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P 'Password123!' -C -i backup/01_full.sql > logs/01_full.log
  ```

* **Comando T-SQL interno:**
  ```sql
  BACKUP DATABASE db_olimpiadas TO DISK = '/var/opt/mssql/backups/full_base.bak' WITH INIT, STATS = 10;
  ```

**B. Backup Incremental (Diferencial)**
Captura únicamente los bloques de datos (páginas) que han cambiado desde el último Backup Completo. Es acumulativo (el Diferencial 3 contiene los cambios del 1 y del 2).
* **Ejecución en consola:**
  ```bash
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'Password123!' -C -i backup/02_diferencial.sql > logs/02_diferencial.log
  ```

* **Comando T-SQL interno:**
  ```sql
  BACKUP DATABASE db_olimpiadas TO DISK = '/var/opt/mssql/backups/diff_base_1.bak' WITH DIFFERENTIAL, STATS = 10;
  ```

### ### 2. Cómo restaurar desde respaldos
El proceso de restauración exige aplicar los archivos .bak en un orden estricto, manejando correctamente los estados de recuperación del motor.

**Escenario A: Restaurar solo el Backup Completo**
Si solo se necesita volver al punto inicial, la base de datos se restaura en estado funcional (RECOVERY).
  ```sql
  RESTORE DATABASE db_olimpiadas FROM DISK = '/var/opt/mssql/backups/full_base.bak' WITH RECOVERY, REPLACE;
  ```

**Escenario B: Restaurar Full + Diferencial**
Es obligatorio restaurar primero el Full dejándolo "en espera" (NORECOVERY), y luego aplicar el Diferencial más reciente cerrando la base de datos (RECOVERY). No es necesario restaurar los diferenciales intermedios.
  ```sql
  -- Paso 1: Restaurar el Full sin habilitar la base de datos
  RESTORE DATABASE db_olimpiadas FROM DISK = '/var/opt/mssql/backups/full_base.bak' WITH NORECOVERY, REPLACE;

  -- Paso 2: Aplicar el Diferencial más reciente y ponerla online
  RESTORE DATABASE db_olimpiadas FROM DISK = '/var/opt/mssql/backups/diff_base_3.bak' WITH RECOVERY;
  ```

### 3. Interpretación de registros de respaldo (Logs)
Al redireccionar la salida de consola hacia un archivo .log, SQL Server emite mensajes de auditoría:

  ```text
  10 percent processed.
  ...
  100 percent processed.
  Processed 15120 pages for database 'db_olimpiadas', file 'db_olimpiadas' on file 1.
  RESTORE DATABASE successfully processed 15122 pages in 0.366 seconds (322.777 MB/sec).
  ```

* **Progreso (percent processed):**
  Impreso gracias a la bandera STATS = 10. En bases muy pequeñas, puede saltar del 49% al 100% si los datos caben en un solo bloque de lectura.

* **Páginas procesadas:**
  Cada página en SQL Server mide 8 KB. Multiplicar las páginas por 8 KB permite auditar el tamaño real de los datos.

* **Velocidad (MB/sec):**
  Indica la tasa de transferencia del disco duro físico.

### 4. Procedimientos de validación post-restauración
Inmediatamente después de restaurar, se deben ejecutar tres pruebas:

* **Validación de Filas (Data Completeness):**
  Ejecutar un COUNT(*) contra las tablas transaccionales. El número devuelto debe coincidir matemáticamente con el registro tomado antes de la eliminación.

* **Validación de Estructura Relacional:**
  Realizar SELECT TOP 5 uniendo las tablas de hechos con sus dimensiones para confirmar que las llaves foráneas mantienen su integridad.
* **Auditoría Física de Archivos (msdb):**
  Consultar msdb.dbo.backupset para demostrar que el sistema reconoce los archivos .bak en su ruta física y verificar las fechas de creación.

## Preparación y ejecución
Despliegue de infraestructura, inicialización DDL y ejecución de las cargas masivas.

### Fase 1: Preparación del Entorno Físico y Permisos
Asegurar la estructura de directorios y los permisos de lectura/escritura (crítico en distribuciones con SELinux).

  ```bash
  # 1. Crear subcarpetas exclusivas para el alcance "por año"
  mkdir -p carga/anio backup/anio restauracion/anio docs/anio capturas logs

  # 2. Crear volumen local para backups y asignar permisos totales
  mkdir -p backups_fisicos
  chmod 777 backups_fisicos

  # 3. Asegurar permisos de lectura en la carpeta de datos crudos
  chmod -R 755 CSVs/
  ```

### Fase 2: Despliegue de Infraestructura (Docker)
Levantar el motor de base de datos mapeando los volúmenes locales. La bandera :z indica a SELinux que comparta el directorio.

  ```text
  docker run -e "ACCEPT_EULA=Y" -e "MSSQL_SA_PASSWORD=Password123!" \
  -e "MSSQL_COLLATION=Latin1_General_100_CI_AS_SC_UTF8" \
  -p 1433:1433 --name sqlserver_olimpiadas \
  -v "$(pwd)/CSVs:/var/opt/mssql/csv:ro,z" \
  -v "$(pwd)/backups_fisicos:/var/opt/mssql/backups:z" \
  -d [mcr.microsoft.com/mssql/server:2022-latest](https://mcr.microsoft.com/mssql/server:2022-latest)
  ```
  
### Fase 3: Inicialización DDL (Estructura de Base de Datos)
Se inyectan los scripts pasando la variable -v DbNombre=db_olimpiadas_anio para mantener el aislamiento.

  ```bash
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/01_crear_base_datos.sql > logs/01_crear_base_datos_anio.log
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/02_esquema_staging.sql > logs/02_esquema_staging_anio.log
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -v DbNombre=db_olimpiadas_anio -i /dev/stdin < ddl/03_modelo_relacional.sql > logs/03_modelo_relacional_anio.log
  ```

### Fase 4: Preparación del ETL y Carga Inicial (París 2024)
Carga cruda a memoria, compilación de lógica de negocio y primera carga (base para el Full Backup).

  ```bash
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/01_cargar_staging.sql > logs/01_cargar_staging_anio.log
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/02_proc_cargar_anio.sql > logs/02_proc_cargar_anio.log
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/03_carga_1_paris2024.sql > logs/03_carga_1_paris2024_anio.log
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/01_full_anio.sql > logs/01_full_anio.log
  ```

### Fase 5: Cargas Incrementales y Backups Diferenciales
Ciclos de ingesta para los años anteriores, respaldando de manera acumulativa inmediatamente después de cada carga.

  ```bash
  # CICLO 2: Tokio 2020 + Diferencial 1
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/04_carga_2_tokio_2020.sql > logs/04_carga_2_tokio_2020_anio.log
  
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/02_dif_anio_1.sql > logs/02_dif_anio_1.log

  # CICLO 3: Río 2016 + Diferencial 2
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/05_carga_3_rio_2016.sql > logs/05_carga_3_rio_2016_anio.log
  
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/03_dif_anio_2.sql > logs/03_dif_anio_2.log

  # CICLO 4: Londres 2012 + Diferencial 3
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < carga/anio/06_carga_4_londres_2012.sql > logs/06_carga_4_londres_2012_anio.log
  
  docker exec -i sqlserver_olimpiadas /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'Password123!' -C -i /dev/stdin < backup/anio/04_dif_anio_3.sql > logs/04_dif_anio_3.log
  ```

### Fase 6: Pruebas de Restauración y Auditoría de Tiempos
Ejecución del script automatizado que intercala eliminaciones completas (DROP DATABASE) con las combinaciones de restauración, capturando los tiempos en milisegundos.

  ```bash
  chmod +x docs/anio/medir_tiempos_restore.sh
  ./docs/anio/medir_tiempos_restore.sh
  cat docs/anio/tiempos_restore_anio.csv
  ```