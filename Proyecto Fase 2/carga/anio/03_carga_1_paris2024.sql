USE db_olimpiadas_anio;
GO
PRINT '===============================================================';
PRINT 'CARGA 1 / 4 - Por Año - PARIS 2024';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

-- 1. Ejecutar el procedimiento para París 2024
EXEC dbo.sp_cargar_anio @anio = 2024;
GO

-- 2. Evidencias de Conteos
SELECT 'dbo.region'        AS tabla, COUNT(*) AS filas FROM dbo.region
UNION ALL SELECT 'dbo.edicion_juego', COUNT(*) FROM dbo.edicion_juego
UNION ALL SELECT 'dbo.disciplina',    COUNT(*) FROM dbo.disciplina
UNION ALL SELECT 'dbo.atleta',        COUNT(*) FROM dbo.atleta
UNION ALL SELECT 'dbo.participacion', COUNT(*) FROM dbo.participacion
UNION ALL SELECT 'dbo.resultado',     COUNT(*) FROM dbo.resultado
ORDER BY tabla;
GO

-- 3. Evidencia de Fragmentación
SELECT OBJECT_NAME(ips.object_id) AS tabla, i.name AS indice, ips.avg_fragmentation_in_percent AS fragmentacion_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.tables t ON i.object_id = t.object_id WHERE t.is_ms_shipped = 0;
GO