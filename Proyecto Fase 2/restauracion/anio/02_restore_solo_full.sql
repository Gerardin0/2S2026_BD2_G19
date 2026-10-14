/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO

   restauracion/anio/02_restore_solo_full.sql
   RESTAURACION 1/4 - unicamente el backup completo.

   Estado que se espera recuperar: el de DESPUES de la carga 1 (Paris 2024),
   es decir, ANTES de las cargas de Tokio 2020, Rio 2016 y Londres 2012.

   WITH RECOVERY deja la base utilizable (modo simple, sin cola de restore).
   Con WITH REPLACE se sobrescribe la base si por error ya existiera.
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'RESTAURACION 1/4 - SOLO FULL (estado tras carga 1: Paris 2024)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

DECLARE @t0 DATETIME2 = SYSDATETIME();

RESTORE DATABASE db_olimpiadas_anio
    FROM DISK = '/var/opt/mssql/backups/full_anio.bak'
    WITH RECOVERY, REPLACE, STATS = 10;

DECLARE @ms INT = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT '>>> TIEMPO_MOTOR_RESTORE_MS: ' + CAST(@ms AS VARCHAR(20)) + ' ms (' + CAST(CAST(@ms / 1000.0 AS DECIMAL(10,3)) AS VARCHAR(20)) + ' s)';
GO

/* --- Validacion: historial de respaldos en msdb --- */
SELECT
    CAST(bs.database_name AS VARCHAR(22)) AS database_name,
    CAST(CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
              ELSE 'DIFERENCIAL' END AS VARCHAR(12)) AS tipo,
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(10, 2)) AS tamano_mb,
    CAST(bfm.physical_device_name AS VARCHAR(42)) AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%anio%'
ORDER BY bs.backup_finish_date;
GO

USE db_olimpiadas_anio;
GO

PRINT '--- Conteos restaurados (solo FULL) ---';
SELECT 'dbo.region'        AS tabla, COUNT(*) AS filas FROM dbo.region
UNION ALL SELECT 'dbo.edicion_juego', COUNT(*) FROM dbo.edicion_juego
UNION ALL SELECT 'dbo.disciplina',    COUNT(*) FROM dbo.disciplina
UNION ALL SELECT 'dbo.atleta',        COUNT(*) FROM dbo.atleta
UNION ALL SELECT 'dbo.roles',         COUNT(*) FROM dbo.roles
UNION ALL SELECT 'dbo.atleta_roles',  COUNT(*) FROM dbo.atleta_roles
UNION ALL SELECT 'dbo.participacion', COUNT(*) FROM dbo.participacion
UNION ALL SELECT 'dbo.resultado',     COUNT(*) FROM dbo.resultado
UNION ALL SELECT 'dbo.poblacion',     COUNT(*) FROM dbo.poblacion
ORDER BY tabla;
GO

PRINT 'Solo debe aparecer la edicion de PARIS 2024:';
SELECT ej.id, ej.[year] AS anio, ej.games_name AS edicion, ej.city,
       COUNT(p.id) AS total_participaciones
FROM dbo.edicion_juego ej
LEFT JOIN dbo.participacion p ON p.id_edicion = ej.id
GROUP BY ej.id, ej.[year], ej.games_name, ej.city
ORDER BY ej.[year] DESC;
GO

PRINT '--- Muestra de datos restaurados (SELECT de validacion) ---';
SELECT TOP 5 'dbo.region' AS tabla, noc_code, CAST(country_name AS VARCHAR(25)) AS country_name FROM dbo.region ORDER BY noc_code;
SELECT TOP 5 'dbo.disciplina' AS tabla, id, CAST(sport AS VARCHAR(22)) AS sport, CAST(event_name AS VARCHAR(30)) AS event_name FROM dbo.disciplina ORDER BY id;
SELECT TOP 5 'dbo.atleta' AS tabla, id, CAST(full_name AS VARCHAR(30)) AS full_name, sex, noc_code FROM dbo.atleta ORDER BY id;
SELECT TOP 5 'dbo.participacion' AS tabla, id, id_atleta, id_edicion, id_disciplina, noc_code FROM dbo.participacion ORDER BY id;
SELECT TOP 5 'dbo.resultado' AS tabla, id_participacion, place, tied, medal FROM dbo.resultado ORDER BY id_participacion;
GO

PRINT 'Restauracion 1/4 completada.';
GO