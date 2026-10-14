/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO - Rio 2016

   backup/anio/03_dif_anio_2.sql
   RESPALDO DIFERENCIAL 2, tomado DESPUES de la carga 3 (Rio 2016).

   IMPORTANTE - NATURALEZA DEL DIFERENCIAL EN SQL SERVER:
   El diferencial es ACUMULATIVO. Cada uno guarda TODAS las paginas que
   cambiaron desde el ULTIMO FULL, no solo lo que cambio desde el
   diferencial anterior. Por eso:
     - para restaurar el estado tras la carga 3, alcanza con
       full_anio.bak + diff_anio_2.bak;
     - NO hace falta aplicar los diferenciales anteriores.
   Esto es justamente lo que se explica en el analisis comparativo final.

   Opciones de BACKUP y por que estan puestas:
     WITH INIT         -> sobrescribe el archivo si ya existe (indispensable para
                          poder repetir la corrida).
     WITH DIFFERENTIAL -> solo las paginas modificadas desde el ultimo FULL.
     WITH STATS=10     -> imprime el porcentaje de avance cada 10%. Esa salida
                          es la que se guarda en logs/ y la que el enunciado pide
                          adjuntar como evidencia de ejecucion por consola.
     Sin COMPRESSION   -> el backup queda sin comprimir para que la comparacion
                          de tamanos entre full y diferencial sea directa.
   ========================================================================== */

USE db_olimpiadas_anio;
GO

PRINT '===============================================================';
PRINT 'BACKUP DIFERENCIAL 2 - Por Año (tras carga 3, Rio 2016)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_anio
    TO DISK = '/var/opt/mssql/backups/diff_anio_2.bak'
    WITH INIT, DIFFERENTIAL, STATS = 10;
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
WHERE bfm.physical_device_name LIKE '%diff_anio_2%'
ORDER BY bs.backup_finish_date DESC;
GO

/* Verificacion de integridad */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/diff_anio_2.bak';
GO

PRINT 'Diferencial 2 creado: /var/opt/mssql/backups/diff_anio_2.bak';
GO