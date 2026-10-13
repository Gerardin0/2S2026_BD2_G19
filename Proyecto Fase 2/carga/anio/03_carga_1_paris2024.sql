/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO (Paris 2024)

   carga/anio/03_carga_1_paris2024.sql
   CARGA INICIAL (Edicion 1: Paris 2024)
   ========================================================================== */

USE db_olimpiadas_anio;
GO

/* --- 1. MARCA DE TIEMPO --- */
PRINT '===============================================================';
PRINT 'CARGA 1 / 4 - Por Año - PARIS 2024';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

/* --- 2. CARGA --- */
EXEC dbo.sp_cargar_anio @anio = 2024;
GO

/* --- 3. EVIDENCIA: contenido de cada tabla (SELECT de muestra) --- */
SELECT TOP 10 'dbo.region' AS tabla, noc_code, CAST(country_name AS VARCHAR(25)) AS country_name, CAST(region AS VARCHAR(25)) AS region FROM dbo.region ORDER BY noc_code;
SELECT 'dbo.edicion_juego' AS tabla, id, [year], season, games_name, city FROM dbo.edicion_juego ORDER BY [year];
SELECT TOP 10 'dbo.disciplina' AS tabla, id, CAST(sport AS VARCHAR(25)) AS sport, CAST(event_name AS VARCHAR(35)) AS event_name FROM dbo.disciplina ORDER BY id;
SELECT TOP 10 'dbo.atleta' AS tabla, id, source_athlete_id, CAST(full_name AS VARCHAR(30)) AS full_name, sex, born_date, noc_code FROM dbo.atleta ORDER BY id;
SELECT 'dbo.roles' AS tabla, id, CAST(nombre AS VARCHAR(30)) AS nombre FROM dbo.roles ORDER BY id;
SELECT TOP 10 'dbo.atleta_roles' AS tabla, id_atleta, id_rol FROM dbo.atleta_roles ORDER BY id_atleta;
SELECT TOP 10 'dbo.participacion' AS tabla, id, id_atleta, id_edicion, id_disciplina, noc_code, age, height_cm, weight_kg FROM dbo.participacion ORDER BY id;
SELECT TOP 10 'dbo.resultado' AS tabla, id_participacion, place, tied, medal FROM dbo.resultado ORDER BY id_participacion;
SELECT TOP 10 'dbo.poblacion' AS tabla, noc_code, anio, poblacion FROM dbo.poblacion ORDER BY noc_code, anio;
GO

/* --- 4. EVIDENCIA: conteos (9 tablas) --- */
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

/* --- 5. EVIDENCIA: fragmentacion de indices --- */
SELECT
    CAST(OBJECT_NAME(ips.object_id) AS VARCHAR(22)) AS tabla,
    CAST(i.name AS VARCHAR(28))                     AS indice,
    CAST(i.type_desc AS VARCHAR(18))                AS tipo_indice,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(6,2)) AS fragmentacion_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.tables t  ON i.object_id = t.object_id
WHERE t.is_ms_shipped = 0
ORDER BY tabla, indice;
GO

/* --- 6. TAMAÑO DE LA BASE ANTES DEL BACKUP --- */
SELECT
    CAST(name AS VARCHAR(28))          AS archivo_logico,
    CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(10,2)) AS tamano_mb,
    CAST(physical_name AS VARCHAR(48)) AS archivo_fisico
FROM sys.database_files
GROUP BY name, physical_name;
GO

PRINT 'Carga 1 completada. Continuar con backup/anio/01_full_anio.sql';
GO