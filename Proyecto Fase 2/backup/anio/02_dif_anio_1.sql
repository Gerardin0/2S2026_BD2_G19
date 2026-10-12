/* ==========================================================================
   PROYECTO 2 - FASE 2
   Pablo - Carga por AÑO

   backup/02_dif_anio_1.sql
   RESPALDO DIFERENCIAL 1, tomado DESPUES de la carga 2 (Tokio 2020).
   ========================================================================== */

USE db_olimpiadas_anio;
GO

PRINT '===============================================================';
PRINT 'BACKUP DIFERENCIAL 1 - Por Año (tras carga 2, Tokio 2020)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_anio
    TO DISK = '/var/opt/mssql/backups/diff_anio_1.bak'
    WITH INIT, DIFFERENTIAL, STATS = 10;
GO

/* Obtener auditoría de tamaño y fecha desde msdb */
SELECT
    bs.database_name,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL' ELSE 'DIFERENCIAL' END AS tipo,
    bfm.physical_device_name AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%diff_anio_1%'
ORDER BY bs.backup_finish_date;
GO

/* Verificación de integridad */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/diff_anio_1.bak';
GO

PRINT 'Diferencial 1 creado: /var/opt/mssql/backups/diff_anio_1.bak';
GO