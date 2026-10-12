USE db_olimpiadas_anio;
GO

IF OBJECT_ID('dbo.sp_cargar_anio', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_cargar_anio;
GO

CREATE PROCEDURE dbo.sp_cargar_anio @anio INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_edicion INT;
    DECLARE @n INT;

    -- 0. Localizar la edición
    SELECT @id_edicion = TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT)
    FROM stg.edicion_juego
    WHERE TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT) = @anio AND LTRIM(RTRIM(season)) = 'Summer';

    IF @id_edicion IS NULL
    BEGIN
        PRINT 'ERROR: no se encontró la edición de verano ' + CAST(@anio AS VARCHAR(10));
        RETURN 1;
    END

    PRINT '=== Carga masiva para la edición ' + CAST(@anio AS VARCHAR(10)) + ' ===';

    /* ===============================================================
       FASE A: TABLAS TEMPORALES INDEXADAS (100x Más rápido)
       =============================================================== */
    PRINT '--- Preparando datos en RAM ---';
    
    -- 1. Participaciones de esta edición (Ya convertidas a enteros)
    SELECT 
        TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT) as id_part,
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT)) as id_atl,
        TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) as id_disc,
        LTRIM(RTRIM(noc_code)) as noc_code,
        NULLIF(LTRIM(RTRIM(team)), '') as team,
        NULLIF(LTRIM(RTRIM(presentado_como)), '') as presentado_como,
        TRY_CONVERT(DECIMAL(5,2), NULLIF(LTRIM(RTRIM(age)), '')) as age,
        TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(height_cm)), '')) as height_cm,
        TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(weight_kg)), '')) as weight_kg
    INTO #tp FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion;

    CREATE UNIQUE CLUSTERED INDEX CIX_tp ON #tp(id_part);
    CREATE NONCLUSTERED INDEX IX_tp_atl ON #tp(id_atl);

    -- 2. Pre-calcular el NOC del atleta para evitar la subconsulta anidada
    SELECT id_atl, MIN(noc_code) as noc_code
    INTO #t_noc FROM #tp WHERE noc_code IS NOT NULL AND noc_code <> '' GROUP BY id_atl;
    CREATE UNIQUE CLUSTERED INDEX CIX_tnoc ON #t_noc(id_atl);

    -- 3. Filtrar solo los atletas que participan este año
    SELECT a.*, TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)) as id_clean
    INTO #ta FROM stg.atleta a
    WHERE EXISTS (SELECT 1 FROM #tp WHERE #tp.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)));
    CREATE CLUSTERED INDEX CIX_ta ON #ta(id_clean);

    /* ===============================================================
       FASE B: MIGRACIÓN RELACIONAL (Sobre temporales limpias)
       =============================================================== */
    PRINT '--- Migrando a DBO ---';
    -- 1. Región
    INSERT INTO dbo.region (noc_code, country_name, region, notas)
    SELECT DISTINCT tp.noc_code, COALESCE(NULLIF(LTRIM(RTRIM(r.region)), ''), tp.noc_code),
        COALESCE(NULLIF(LTRIM(RTRIM(r.region)), ''), tp.noc_code), LTRIM(RTRIM(r.notes))
    FROM #tp tp INNER JOIN stg.region r ON LTRIM(RTRIM(r.NOC)) = tp.noc_code
    WHERE NOT EXISTS (SELECT 1 FROM dbo.region d WHERE d.noc_code = tp.noc_code);
    PRINT '  region        -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 2. Edición
    SET IDENTITY_INSERT dbo.edicion_juego ON;
    INSERT INTO dbo.edicion_juego (id, [year], season, games_name, city, noc_code)
    SELECT @id_edicion, TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT)), LTRIM(RTRIM(season)),
        CONCAT(TRY_CONVERT(VARCHAR(10), TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT))), ' ', LTRIM(RTRIM(season))),
        NULLIF(LTRIM(RTRIM(city)), ''), NULL
    FROM stg.edicion_juego WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion
      AND NOT EXISTS (SELECT 1 FROM dbo.edicion_juego d WHERE d.id = @id_edicion);
    SET IDENTITY_INSERT dbo.edicion_juego OFF;
    PRINT '  edicion_juego -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 3. Disciplina
    SET IDENTITY_INSERT dbo.disciplina ON;
    INSERT INTO dbo.disciplina (id, sport, event_name)
    SELECT DISTINCT tp.id_disc, LTRIM(RTRIM(d.sport)), LTRIM(RTRIM(d.event_name))
    FROM #tp tp INNER JOIN stg.disciplina d ON LTRIM(RTRIM(d.id_disciplina)) = CAST(tp.id_disc AS VARCHAR(20))
    WHERE NOT EXISTS (SELECT 1 FROM dbo.disciplina x WHERE x.id = tp.id_disc);
    SET IDENTITY_INSERT dbo.disciplina OFF;
    PRINT '  disciplina    -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 4. Atleta (Con truncamiento seguro LEFT para evitar error 2628)
    SET IDENTITY_INSERT dbo.atleta ON;
    INSERT INTO dbo.atleta (
        id, source_athlete_id, full_name, used_name, nombre_original, otros_nombres, orden_nombre, apodos, titulos, 
        afiliaciones, nacionalidad, sex, born_date, born_city, born_region, born_country, latitud, longitud, died_date, died_place, noc_code
    )
    SELECT DISTINCT ta.id_clean, LTRIM(RTRIM(ta.athlete_id)),
        LEFT(COALESCE(NULLIF(LTRIM(RTRIM(ta.name)), ''), NULLIF(LTRIM(RTRIM(ta.[Full name])), ''), 'Atleta ' + LTRIM(RTRIM(ta.athlete_id))), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Full name])), ''), 150), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Original name])), ''), 150), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Other names])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Name order])), ''), 50), -- Corta a 50 chars para evitar el error exacto
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Nick/petnames])), ''), 150), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Title(s)])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.Affiliations)), ''), 255), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.Nationality)), ''), 150), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.Sex)), ''), 20),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(ta.born_date)), '')), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_city)), ''), 150), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_region)), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_country)), ''), 150), 
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(ta.lat)), '')), 
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(ta.[long])), '')),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(ta.died_date)), '')), 
        LEFT(NULLIF(LTRIM(RTRIM(ta.died_in)), ''), 150),
        tn.noc_code
    FROM #ta ta LEFT JOIN #t_noc tn ON tn.id_atl = ta.id_clean
    WHERE NOT EXISTS (SELECT 1 FROM dbo.atleta x WHERE x.id = ta.id_clean);
    SET IDENTITY_INSERT dbo.atleta OFF;
    PRINT '  atleta        -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 5. Roles
    SET IDENTITY_INSERT dbo.roles ON;
    INSERT INTO dbo.roles (id, nombre, descripcion)
    SELECT TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT), LTRIM(RTRIM(nombre_rol)), NULL FROM stg.rol
    WHERE NOT EXISTS (SELECT 1 FROM dbo.roles x WHERE x.id = TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT));
    SET IDENTITY_INSERT dbo.roles OFF;
    
    INSERT INTO dbo.atleta_roles (id_atleta, id_rol)
    SELECT DISTINCT ta.id_clean, TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS INT))
    FROM stg.atleta_rol ar INNER JOIN #ta ta ON TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT)) = ta.id_clean
    WHERE NOT EXISTS (SELECT 1 FROM dbo.atleta_roles x WHERE x.id_atleta = ta.id_clean AND x.id_rol = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS INT)));
    PRINT '  roles_atleta  -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 6. Participación
    SET IDENTITY_INSERT dbo.participacion ON;
    INSERT INTO dbo.participacion (id, id_atleta, id_edicion, id_disciplina, noc_code, equipo, presentado_como, age, height_cm, weight_kg)
    SELECT tp.id_part, tp.id_atl, @id_edicion, tp.id_disc, tp.noc_code, tp.team, tp.presentado_como, tp.age, tp.height_cm, tp.weight_kg
    FROM #tp tp WHERE NOT EXISTS (SELECT 1 FROM dbo.participacion x WHERE x.id = tp.id_part);
    SET IDENTITY_INSERT dbo.participacion OFF;
    PRINT '  participacion -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 7. Resultado
    INSERT INTO dbo.resultado (id_participacion, place, tied, medal)
    SELECT tp.id_part,
        CASE WHEN LTRIM(RTRIM(r.place)) = '' THEN NULL
             WHEN TRY_CAST(r.place AS FLOAT) = FLOOR(TRY_CAST(r.place AS FLOAT)) THEN CAST(CAST(TRY_CAST(r.place AS FLOAT) AS INT) AS VARCHAR(20))
             ELSE LTRIM(RTRIM(r.place)) END,
        CASE WHEN LTRIM(RTRIM(r.tied)) = '' THEN NULL ELSE CAST(TRY_CAST(r.tied AS FLOAT) AS BIT) END, NULLIF(LTRIM(RTRIM(r.medal)), '')
    FROM stg.resultado r INNER JOIN #tp tp ON tp.id_part = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.resultado x WHERE x.id_participacion = tp.id_part);
    PRINT '  resultado     -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    -- 8. Población
    INSERT INTO dbo.poblacion (noc_code, anio, poblacion)
    SELECT DISTINCT LTRIM(RTRIM(pb.noc_code)), TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)), TRY_CAST(LTRIM(RTRIM(pb.population)) AS BIGINT)
    FROM stg.poblacion pb INNER JOIN dbo.region rg ON rg.noc_code = LTRIM(RTRIM(pb.noc_code))
    WHERE EXISTS (SELECT 1 FROM #tp tp WHERE tp.noc_code = rg.noc_code)
      AND NOT EXISTS (SELECT 1 FROM dbo.poblacion x WHERE x.noc_code = LTRIM(RTRIM(pb.noc_code)) AND x.anio = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)));
    PRINT '  poblacion     -> ' + CAST(@@ROWCOUNT AS VARCHAR(20)) + ' filas';

    /* ===============================================================
       FASE C: PURGA OPTIMIZADA DE STAGING
       =============================================================== */
    PRINT '--- Purgando staging ---';
    DELETE r FROM stg.resultado r INNER JOIN #tp tp ON tp.id_part = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT);
    DELETE FROM stg.participacion WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion;
    
    -- Listar IDs que aún siguen activos para no borrar atletas útiles
    SELECT DISTINCT TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT)) as id_atl INTO #activos FROM stg.participacion;
    CREATE UNIQUE CLUSTERED INDEX CIX_act ON #activos(id_atl);

    DELETE ar FROM stg.atleta_rol ar WHERE NOT EXISTS (SELECT 1 FROM #activos a WHERE a.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT)));
    DELETE a FROM stg.atleta a WHERE NOT EXISTS (SELECT 1 FROM #activos aa WHERE aa.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)));

    DELETE FROM stg.edicion_juego WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion;

    DROP TABLE #tp; DROP TABLE #t_noc; DROP TABLE #ta; DROP TABLE #activos;

    PRINT '--- Carga de ' + CAST(@anio AS VARCHAR(10)) + ' finalizada y Staging purgado ---';
END;
GO