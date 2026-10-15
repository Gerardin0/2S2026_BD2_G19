/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt)

   carga/deportista/06_carga_4_rio_2016.sql
   CARGA 4 + DIFERENCIAL 3

   El diferencial de SQL Server es ACUMULATIVO: guarda todo lo cambiado
   desde el ULTIMO FULL, por eso la carga 4 se respalda con un solo
   BACKUP ... WITH DIFFERENTIAL, sin encadenar los diferenciales anteriores.

   Secuencia del checklist:
     1. Cargar la edicion 4 (Rio 2016).
     2. Capturar SELECT * de cada tabla.
     3. Capturar COUNT(*) de cada tabla.
     4. Capturar la fragmentacion de indices.
     5. BACKUP DATABASE ... WITH DIFFERENTIAL -> diff_deportista_3.bak

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deportista \
            -i 06_carga_4_rio_2016.sql
   ========================================================================== */

USE db_olimpiadas_deportista;
GO

/* --- 1. MARCA DE TIEMPO (el checklist exige fecha/hora del SO visible) --- */
PRINT '===============================================================';
PRINT 'CARGA 4 / 4 - Deportista - RIO 2016';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120);
PRINT '===============================================================';
GO

/* --- 2. CARGA --- */
EXEC dbo.sp_cargar_deportista @anio = 2016, @atleta_id = 105512;
GO

/* --- 3. EVIDENCIA: contenido de cada tabla --- */
SELECT 'dbo.region' AS tabla, noc_code, country_name, region, notas FROM dbo.region;
SELECT 'dbo.edicion_juego' AS tabla, id, [year], season, games_name, city FROM dbo.edicion_juego;
SELECT 'dbo.disciplina' AS tabla, id, sport, event_name FROM dbo.disciplina;
SELECT 'dbo.atleta' AS tabla, id, source_athlete_id, full_name, used_name, sex,
       born_date, born_city, nacionalidad, noc_code FROM dbo.atleta;
SELECT 'dbo.roles' AS tabla, id, nombre FROM dbo.roles;
SELECT 'dbo.atleta_roles' AS tabla, id_atleta, id_rol FROM dbo.atleta_roles;
SELECT 'dbo.participacion' AS tabla, id, id_atleta, id_edicion, id_disciplina,
       noc_code, age, height_cm, weight_kg FROM dbo.participacion;
SELECT 'dbo.resultado' AS tabla, id_participacion, place, tied, medal FROM dbo.resultado;
SELECT TOP 20 'dbo.poblacion' AS tabla, noc_code, anio, poblacion
FROM dbo.poblacion ORDER BY anio;
GO

/* --- 4. EVIDENCIA: conteos --- */
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

/* --- 5. EVIDENCIA: fragmentacion de indices (criterio del enunciado) --- */
SELECT
    OBJECT_NAME(ips.object_id)              AS tabla,
    i.name                                  AS indice,
    i.type_desc                             AS tipo_indice,
    ips.avg_fragmentation_in_percent        AS fragmentacion_pct
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
INNER JOIN sys.indexes i
    ON ips.object_id = i.object_id AND ips.index_id = i.index_id
INNER JOIN sys.tables t
    ON i.object_id = t.object_id
WHERE t.is_ms_shipped = 0
ORDER BY tabla, indice;
GO

/* --- 6. TAMAÑO DE LA BASE ANTES DEL DIFERENCIAL --- */
SELECT
    name                                            AS archivo_logico,
    SUM(size) * 8.0 / 1024                          AS tamano_mb,
    physical_name                                   AS archivo_fisico
FROM sys.database_files
GROUP BY name, physical_name;
GO

PRINT 'Carga 4 completada. Continuar con backup/04_dif_deportista_3.sql';
GO