/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt) - Rio 2016

   backup/04_dif_deportista_3.sql
   RESPALDO DIFERENCIAL 3, tomado DESPUES de la carga 4 (Rio 2016).

   IMPORTANTE - NATURALEZA DEL DIFERENCIAL EN SQL SERVER:
   El diferencial es ACUMULATIVO. Cada uno guarda TODAS las paginas que
   cambiaron desde el ULTIMO FULL, no solo lo que cambio desde el
   diferencial anterior. Por eso:
     - para restaurar el estado tras la carga 4, alcanza con
       full_deportista.bak + diff_deportista_3.bak;
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
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deportista \
            -i 04_dif_deportista_3.sql | tee ../logs/backup_full_deportista.log
   ========================================================================== */

USE db_olimpiadas_deportista;
GO

PRINT '===============================================================';
PRINT 'BACKUP DIFERENCIAL 3 - Deportista (tras carga 4, Rio 2016)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120);
PRINT '===============================================================';
GO

BACKUP DATABASE db_olimpiadas_deportista
    TO DISK = '/var/opt/mssql/backups/diff_deportista_3.bak'
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
    CONVERT(VARCHAR(20), bs.backup_finish_date AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%diff_deportista_3%'
ORDER BY bs.backup_finish_date;
GO

/* Verificacion de integridad: es lo primero que hay que hacer si el backup
   llegara a corromperse. Opcional, pero deja constancia del procedimiento. */
RESTORE VERIFYONLY FROM DISK = '/var/opt/mssql/backups/diff_deportista_3.bak';
GO

PRINT 'Diferencial 3 creado: /var/opt/mssql/backups/diff_deportista_3.bak';
GO