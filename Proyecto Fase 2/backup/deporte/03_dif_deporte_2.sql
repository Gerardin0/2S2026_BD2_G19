/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Jose - Carga por DEPORTE (100 m planos femeninos) - Rio 2016

   backup/03_dif_deporte_2.sql
   RESPALDO DIFERENCIAL 2, tomado DESPUES de la carga 3 (Rio 2016).

   IMPORTANTE - NATURALEZA DEL DIFERENCIAL EN SQL SERVER:
   El diferencial es ACUMULATIVO. Cada uno guarda TODAS las paginas que
   cambiaron desde el ULTIMO FULL, no solo lo que cambio desde el
   diferencial anterior. Por eso:
     - para restaurar el estado tras la carga 3, alcanza con
       full_deporte.bak + diff_deporte_2.bak;
     - NO hace falta aplicar los diferenciales anteriores.
   Esto es justamente lo que se explica en el analisis comparativo final.

   Opciones de BACKUP y por que estan puestas:
     WITH INIT      -> sobrescribe el archivo si ya existe (indispensable para
                       poder repetir la corrida).
     WITH DIFFERENTIAL -> solo las paginas modificadas desde el ultimo FULL.
     WITH STATS=10  -> imprime el porcentaje de avance cada 10%. Esa salida
                       es la que se guarda en logs/ y la que el enunciado pide
                       adjuntar como evidencia de ejecucion por consola.
     Sin COMPRESSION-> el backup queda sin comprimir para que la comparacion
                       de tamanos entre full y diferencial sea directa. La
                       compresion es un extra opcional del checklist.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deporte \
            -i 03_dif_deporte_2.sql | tee ../logs/backup_diff_deporte_2.log
   ========================================================================== */

USE db_olimpiadas_deporte;
GO

PRINT '===============================================================';
PRINT 'BACKUP DIFERENCIAL 2 - Deporte (tras carga 3, Rio 2016)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_deporte
    TO DISK = '/var/opt/mssql/backups/diff_deporte_2.bak'
    WITH INIT, DIFFERENTIAL, STATS = 10;
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
WHERE bfm.physical_device_name LIKE '%diff_deporte_2%'
ORDER BY bs.backup_finish_date;
GO

/* Verificacion de integridad: es lo primero que hay que hacer si el backup
   llegara a corromperse. Opcional, pero deja constancia del procedimiento. */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/diff_deporte_2.bak';
GO

PRINT 'Diferencial 2 creado: /var/opt/mssql/backups/diff_deporte_2.bak';
GO