/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO

   restauracion/anio/05_restore_full_diff3.sql
   RESTAURACION 4/4 - FULL + DIFERENCIAL 3 (hasta Londres 2012).

   Recupera el estado final con las 4 ediciones cargadas (Paris 2024,
   Tokio 2020, Rio 2016 y Londres 2012). Los conteos deben coincidir
   exactamente con los registrados antes de eliminar la base de datos.
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'RESTAURACION 4/4 - FULL + DIFF 3 (hasta Londres 2012)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

DECLARE @t0 DATETIME2 = SYSDATETIME();

RESTORE DATABASE db_olimpiadas_anio
    FROM DISK = '/var/opt/mssql/backups/full_anio.bak'
    WITH NORECOVERY, REPLACE, STATS = 10;

RESTORE DATABASE db_olimpiadas_anio
    FROM DISK = '/var/opt/mssql/backups/diff_anio_3.bak'
    WITH RECOVERY, STATS = 10;

DECLARE @ms INT = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT '>>> TIEMPO_MOTOR_RESTORE_MS: ' + CAST(@ms AS VARCHAR(20)) + ' ms (' + CAST(CAST(@ms / 1000.0 AS DECIMAL(10,3)) AS VARCHAR(20)) + ' s)';
GO

USE db_olimpiadas_anio;
GO

PRINT '--- Conteos restaurados (FULL + DIFF 3) ---';
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

PRINT 'Deben aparecer las 4 ediciones (2024, 2020, 2016 y 2012):';
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

PRINT 'Restauracion 4/4 completada.';
GO