/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO - Paris 2024

   backup/anio/01_full_anio.sql
   PRIMER RESPALDO COMPLETO (FULL), tomado DESPUES de la carga 1 (Paris 2024).

   Es el punto de referencia de toda la cadena: los diferenciales posteriores
   solo registran cambios respecto a ESTE backup.

   Opciones de BACKUP y por que estan puestas:
     WITH INIT        -> sobrescribe el archivo si ya existe (indispensable para
                         poder repetir la corrida).
     WITH STATS=10    -> imprime el porcentaje de avance cada 10%. Esa salida
                         es la que se guarda en logs/ y la que el enunciado pide
                         adjuntar como evidencia de ejecucion por consola.
     Sin COMPRESSION  -> el backup queda sin comprimir para que la comparacion
                         de tamanos entre full y diferencial sea directa. La
                         compresion es un extra opcional del checklist.
   ========================================================================== */

USE db_olimpiadas_anio;
GO

PRINT '===============================================================';
PRINT 'BACKUP COMPLETO (FULL) - Por Año (Paris 2024)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_anio
    TO DISK = '/var/opt/mssql/backups/full_anio.bak'
    WITH INIT, STATS = 10;
GO

/* Tamaño real del archivo generado, para la tabla de tiempos del checklist. */
SELECT TOP 1
    CAST(bs.database_name AS VARCHAR(22)) AS database_name,
    CAST(CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
              ELSE 'DIFERENCIAL' END AS VARCHAR(12)) AS tipo,
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(10, 2)) AS tamano_mb,
    DATEDIFF(MILLISECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_ms,
    CAST(bfm.physical_device_name AS VARCHAR(42)) AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%full_anio%'
ORDER BY bs.backup_finish_date DESC;
GO

/* Verificacion de integridad */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/full_anio.bak';
GO

PRINT 'FULL creado: /var/opt/mssql/backups/full_anio.bak';
GO