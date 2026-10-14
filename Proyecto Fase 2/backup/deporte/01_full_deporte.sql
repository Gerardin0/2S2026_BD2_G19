/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)

   backup/01_full_deporte.sql
   PRIMER RESPALDO COMPLETO (FULL), tomado DESPUES de la carga 1 (Paris 2024).

   Es el punto de referencia de toda la cadena: los diferenciales posteriores
   solo registran cambios respecto a ESTE backup.

   Opciones de BACKUP y por que estan puestas:
     WITH INIT      -> sobrescribe el archivo si ya existe (indispensable para
                       poder repetir la corrida).
     WITH STATS=10  -> imprime el porcentaje de avance cada 10%. Esa salida
                       es la que se guarda en logs/ y la que el enunciado pide
                       adjuntar como evidencia de ejecucion por consola.
     Sin COMPRESSION-> el backup queda sin comprimir para que la comparacion
                       de tamanos entre full y diferencial sea directa. La
                       compresion es un extra opcional del checklist.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deporte \
            -i 01_full_deporte.sql | tee ../logs/backup_full_deporte.log
   ========================================================================== */

USE db_olimpiadas_deporte;
GO

PRINT '===============================================================';
PRINT 'BACKUP COMPLETO (FULL) - Deporte';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_deporte
    TO DISK = '/var/opt/mssql/backups/full_deporte.bak'
    WITH INIT, STATS = 10;
GO

/* Tamano real del archivo generado, para la tabla de tiempos del checklist.
   Se consulta msdb (NO sys.dm_os_database_backups: esa vista es propia de
   Azure SQL y no existe en SQL Server on-premise). */
SELECT
    bs.database_name,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
         ELSE 'DIFERENCIAL' END              AS tipo,
    bfm.physical_device_name                  AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%full_deporte%'
ORDER BY bs.backup_finish_date;
GO

/* Verificacion de integridad: es lo primero que hay que hacer si el backup
   llegara a corromperse. Opcional, pero deja constancia del procedimiento. */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/full_deporte.bak';
GO

PRINT 'FULL creado: /var/opt/mssql/backups/full_deporte.bak';
GO