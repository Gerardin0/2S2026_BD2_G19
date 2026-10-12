/* ==========================================================================
   PROYECTO 2 - FASE 2
   Pablo - Carga por AÑO

   backup/01_full_anio.sql
   PRIMER RESPALDO COMPLETO (FULL), tomado DESPUES de la carga 1 (Paris 2024).
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

/* Obtener auditoría de tamaño y fecha desde msdb */
SELECT
    bs.database_name,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL' ELSE 'DIFERENCIAL' END AS tipo,
    bfm.physical_device_name AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%full_anio%'
ORDER BY bs.backup_finish_date;
GO

/* Verificación de integridad */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/full_anio.bak';
GO

PRINT 'FULL creado: /var/opt/mssql/backups/full_anio.bak';
GO