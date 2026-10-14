/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO

   carga/anio/02_proc_cargar_anio.sql
   Procedimiento almacenado optimizado y blindado para cargar una edicion
   olimpica completa desde el esquema stg hacia el modelo relacional dbo,
   incorporando las reglas de limpieza de ETL_Limpieza_Carga.py (Fase 1).
   ========================================================================== */

USE db_olimpiadas_anio;
GO

IF OBJECT_ID('dbo.sp_cargar_anio', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_anio;
GO

CREATE PROCEDURE dbo.sp_cargar_anio
    @anio INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_edicion INT;
    DECLARE @n INT;

    -- 0. Localizar el id_edicion correspondiente al año de verano
    SELECT TOP 1 @id_edicion = TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT)
    FROM stg.edicion_juego
    WHERE TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT) = @anio
      AND LTRIM(RTRIM(season)) = 'Summer';

    IF @id_edicion IS NULL
    BEGIN
        PRINT 'ERROR: no se encontró la edición de verano ' + CAST(@anio AS VARCHAR(10));
        RETURN 1;
    END

    PRINT '=== Carga masiva para la edición ' + CAST(@anio AS VARCHAR(10)) + ' (id_edicion ' + CAST(@id_edicion AS VARCHAR(10)) + ') ===';

    /* ===============================================================
       FASE A: TABLAS TEMPORALES INDEXADAS Y SANEADAS EN RAM
       =============================================================== */
    PRINT '--- Preparando datos en RAM ---';

    -- 1. Participaciones del año deduplicadas por id_participacion
    ;WITH cte_p AS (
        SELECT
            TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT) AS id_part,
            TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT)) AS id_atl,
            TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) AS id_disc,
            UPPER(LEFT(NULLIF(LTRIM(RTRIM(noc_code)), ''), 3)) AS noc_code,
            LEFT(NULLIF(LTRIM(RTRIM(team)), ''), 150) AS team,
            LEFT(NULLIF(LTRIM(RTRIM(presentado_como)), ''), 150) AS presentado_como,
            TRY_CONVERT(DECIMAL(5,2), NULLIF(LTRIM(RTRIM(age)), '')) AS age,
            TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(height_cm)), '')) AS height_cm,
            TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(weight_kg)), '')) AS weight_kg,
            ROW_NUMBER() OVER (
                PARTITION BY TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT)
                ORDER BY (SELECT NULL)
            ) AS rn
        FROM stg.participacion
        WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion
    )
    SELECT
        id_part,
        id_atl,
        id_disc,
        COALESCE(noc_code, 'UNK') AS noc_code,
        team,
        presentado_como,
        age,
        height_cm,
        weight_kg
    INTO #tp
    FROM cte_p
    WHERE rn = 1
      AND id_part IS NOT NULL
      AND id_atl IS NOT NULL
      AND id_disc IS NOT NULL;

    CREATE UNIQUE CLUSTERED INDEX CIX_tp ON #tp(id_part);
    CREATE NONCLUSTERED INDEX IX_tp_atl ON #tp(id_atl);
    CREATE NONCLUSTERED INDEX IX_tp_disc ON #tp(id_disc);

    -- 2. Mapa de NOC por atleta (prefiriendo códigos distintos de 'UNK' igual que en Fase 1)
    SELECT
        id_atl,
        COALESCE(
            MAX(CASE WHEN noc_code <> 'UNK' THEN noc_code END),
            MAX(noc_code),
            'UNK'
        ) AS noc_code
    INTO #t_noc
    FROM #tp
    GROUP BY id_atl;

    CREATE UNIQUE CLUSTERED INDEX CIX_tnoc ON #t_noc(id_atl);

    -- 3. Atletas de la edición deduplicados por athlete_id
    ;WITH cte_a AS (
        SELECT
            a.*,
            TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)) AS id_clean,
            ROW_NUMBER() OVER (
                PARTITION BY TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT))
                ORDER BY (SELECT NULL)
            ) AS rn
        FROM stg.atleta a
        WHERE EXISTS (
            SELECT 1 FROM #tp
            WHERE #tp.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT))
        )
    )
    SELECT *
    INTO #ta
    FROM cte_a
    WHERE rn = 1 AND id_clean IS NOT NULL;

    CREATE UNIQUE CLUSTERED INDEX CIX_ta ON #ta(id_clean);

    /* ===============================================================
       FASE B: MIGRACIÓN RELACIONAL A DBO (CON INTEGRIDAD REFERENCIAL)
       =============================================================== */
    PRINT '--- Migrando a DBO ---';

    -- 1. Región: Garantizar todos los NOCs usados en #tp y #t_noc (incluyendo 'UNK', 'ROC', 'EOR', etc.)
    ;WITH nocs_requeridos AS (
        SELECT DISTINCT noc_code FROM #tp WHERE noc_code IS NOT NULL
        UNION
        SELECT DISTINCT noc_code FROM #t_noc WHERE noc_code IS NOT NULL
        UNION
        SELECT 'UNK' AS noc_code
    )
    INSERT INTO dbo.region (noc_code, country_name, region, notas)
    SELECT
        nr.noc_code,
        LEFT(COALESCE(NULLIF(LTRIM(RTRIM(MAX(r.region))), ''), nr.noc_code), 100),
        LEFT(COALESCE(NULLIF(LTRIM(RTRIM(MAX(r.region))), ''), nr.noc_code), 100),
        LEFT(NULLIF(LTRIM(RTRIM(MAX(r.notes))), ''), 255)
    FROM nocs_requeridos nr
    LEFT JOIN stg.region r ON UPPER(LEFT(LTRIM(RTRIM(r.NOC)), 3)) = nr.noc_code
    WHERE NOT EXISTS (SELECT 1 FROM dbo.region d WHERE d.noc_code = nr.noc_code)
    GROUP BY nr.noc_code;
    SET @n = @@ROWCOUNT;
    PRINT '  region        -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 2. Edición Juego
    SET IDENTITY_INSERT dbo.edicion_juego ON;
    INSERT INTO dbo.edicion_juego (id, [year], season, games_name, city, noc_code)
    SELECT TOP 1
        @id_edicion,
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT)),
        LEFT(LTRIM(RTRIM(season)), 20),
        CONCAT(
            TRY_CONVERT(VARCHAR(10), TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT))),
            ' ',
            LEFT(LTRIM(RTRIM(season)), 20)
        ),
        LEFT(NULLIF(LTRIM(RTRIM(city)), ''), 100),
        NULL
    FROM stg.edicion_juego
    WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion
      AND NOT EXISTS (SELECT 1 FROM dbo.edicion_juego d WHERE d.id = @id_edicion);
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.edicion_juego OFF;
    PRINT '  edicion_juego -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 3. Disciplina: Deduplicar por (sport, event_name) y remapear #tp.id_disc
    ;WITH cte_disc AS (
        SELECT
            tp.id_disc,
            LEFT(COALESCE(NULLIF(LTRIM(RTRIM(d.sport)), ''), 'Unknown'), 100) AS sport_clean,
            LEFT(COALESCE(NULLIF(LTRIM(RTRIM(d.event_name)), ''), 'Unknown'), 150) AS event_clean
        FROM (SELECT DISTINCT id_disc FROM #tp) tp
        INNER JOIN stg.disciplina d
            ON TRY_CAST(LTRIM(RTRIM(d.id_disciplina)) AS INT) = tp.id_disc
    )
    SELECT
        MIN(id_disc) AS id_disc,
        sport_clean,
        event_clean
    INTO #t_disc
    FROM cte_disc
    GROUP BY sport_clean, event_clean;

    SET IDENTITY_INSERT dbo.disciplina ON;
    INSERT INTO dbo.disciplina (id, sport, event_name)
    SELECT
        td.id_disc,
        td.sport_clean,
        td.event_clean
    FROM #t_disc td
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.disciplina x
        WHERE x.id = td.id_disc
           OR (x.sport = td.sport_clean AND x.event_name = td.event_clean)
    );
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.disciplina OFF;
    PRINT '  disciplina    -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- Remapear #tp.id_disc al id canónico en dbo.disciplina si la tupla (sport, event_name) tenía otro ID
    UPDATE tp
    SET tp.id_disc = dx.id
    FROM #tp tp
    INNER JOIN stg.disciplina ds
        ON TRY_CAST(LTRIM(RTRIM(ds.id_disciplina)) AS INT) = tp.id_disc
    INNER JOIN dbo.disciplina dx
        ON dx.sport = LEFT(COALESCE(NULLIF(LTRIM(RTRIM(ds.sport)), ''), 'Unknown'), 100)
       AND dx.event_name = LEFT(COALESCE(NULLIF(LTRIM(RTRIM(ds.event_name)), ''), 'Unknown'), 150)
    WHERE tp.id_disc <> dx.id;

    -- 4. Atleta (incluyendo fallback por si un athlete_id en participacion no viniera en stg.atleta)
    SET IDENTITY_INSERT dbo.atleta ON;
    INSERT INTO dbo.atleta (
        id, source_athlete_id, full_name, used_name, nombre_original, otros_nombres, orden_nombre, apodos, titulos,
        afiliaciones, nacionalidad, sex, born_date, born_city, born_region, born_country, latitud, longitud, died_date, died_place, noc_code
    )
    SELECT
        ta.id_clean,
        LEFT(CAST(ta.id_clean AS VARCHAR(50)), 50),
        LEFT(COALESCE(NULLIF(LTRIM(RTRIM(ta.name)), ''), NULLIF(LTRIM(RTRIM(ta.[Full name])), ''), 'Atleta ' + CAST(ta.id_clean AS VARCHAR(20))), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Full name])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Original name])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Other names])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Name order])), ''), 50),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Nick/petnames])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.[Title(s)])), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.Affiliations)), ''), 255),
        LEFT(NULLIF(LTRIM(RTRIM(ta.Nationality)), ''), 150),
        UPPER(LEFT(NULLIF(LTRIM(RTRIM(ta.Sex)), ''), 1)),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(ta.born_date)), '')),
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_city)), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_region)), ''), 150),
        LEFT(NULLIF(LTRIM(RTRIM(ta.born_country)), ''), 150),
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(ta.lat)), '')),
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(ta.[long])), '')),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(ta.died_date)), '')),
        LEFT(NULLIF(LTRIM(RTRIM(ta.died_in)), ''), 150),
        COALESCE(tn.noc_code, 'UNK')
    FROM #ta ta
    LEFT JOIN #t_noc tn ON tn.id_atl = ta.id_clean
    WHERE NOT EXISTS (SELECT 1 FROM dbo.atleta x WHERE x.id = ta.id_clean);
    SET @n = @@ROWCOUNT;

    -- Fallback: atletas referenciados en #tp que no existían en stg.atleta
    INSERT INTO dbo.atleta (id, source_athlete_id, full_name, noc_code)
    SELECT
        tp.id_atl,
        CAST(tp.id_atl AS VARCHAR(50)),
        LEFT(COALESCE(MAX(tp.presentado_como), 'Atleta ' + CAST(tp.id_atl AS VARCHAR(20))), 150),
        COALESCE(MAX(tn.noc_code), 'UNK')
    FROM #tp tp
    LEFT JOIN #t_noc tn ON tn.id_atl = tp.id_atl
    WHERE NOT EXISTS (SELECT 1 FROM dbo.atleta x WHERE x.id = tp.id_atl)
    GROUP BY tp.id_atl;
    SET @n = @n + @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.atleta OFF;
    PRINT '  atleta        -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 5. Roles y Atleta_roles
    SET IDENTITY_INSERT dbo.roles ON;
    INSERT INTO dbo.roles (id, nombre, descripcion)
    SELECT
        MIN(TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT)),
        LEFT(LTRIM(RTRIM(nombre_rol)), 100),
        NULL
    FROM stg.rol
    WHERE TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT) IS NOT NULL
      AND NULLIF(LTRIM(RTRIM(nombre_rol)), '') IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM dbo.roles x
          WHERE x.id = TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT)
             OR x.nombre = LEFT(LTRIM(RTRIM(nombre_rol)), 100)
      )
    GROUP BY LEFT(LTRIM(RTRIM(nombre_rol)), 100);
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.roles OFF;
    PRINT '  roles         -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    INSERT INTO dbo.atleta_roles (id_atleta, id_rol)
    SELECT DISTINCT
        ta.id_clean,
        dr.id
    FROM stg.atleta_rol ar
    INNER JOIN #ta ta
        ON TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT)) = ta.id_clean
    INNER JOIN dbo.atleta da ON da.id = ta.id_clean
    INNER JOIN dbo.roles dr
        ON dr.id = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS FLOAT))
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.atleta_roles x
        WHERE x.id_atleta = ta.id_clean AND x.id_rol = dr.id
    );
    SET @n = @@ROWCOUNT;
    PRINT '  atleta_roles  -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 6. Participación
    SET IDENTITY_INSERT dbo.participacion ON;
    INSERT INTO dbo.participacion (id, id_atleta, id_edicion, id_disciplina, noc_code, equipo, presentado_como, age, height_cm, weight_kg)
    SELECT
        tp.id_part, tp.id_atl, @id_edicion, tp.id_disc, tp.noc_code,
        tp.team, tp.presentado_como, tp.age, tp.height_cm, tp.weight_kg
    FROM #tp tp
    INNER JOIN dbo.atleta da ON da.id = tp.id_atl
    INNER JOIN dbo.disciplina dd ON dd.id = tp.id_disc
    INNER JOIN dbo.region dr ON dr.noc_code = tp.noc_code
    WHERE NOT EXISTS (SELECT 1 FROM dbo.participacion x WHERE x.id = tp.id_part);
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.participacion OFF;
    PRINT '  participacion -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 7. Resultado
    ;WITH cte_res AS (
        SELECT
            tp.id_part,
            CASE WHEN LTRIM(RTRIM(r.place)) = '' THEN NULL
                 WHEN TRY_CAST(r.place AS FLOAT) = FLOOR(TRY_CAST(r.place AS FLOAT))
                      THEN CAST(CAST(TRY_CAST(r.place AS FLOAT) AS INT) AS VARCHAR(20))
                 ELSE LEFT(LTRIM(RTRIM(r.place)), 20) END AS place_clean,
            CASE WHEN LTRIM(RTRIM(r.tied)) = '' THEN NULL
                 WHEN LOWER(LTRIM(RTRIM(r.tied))) IN ('true', '1', '1.0') THEN CAST(1 AS BIT)
                 WHEN LOWER(LTRIM(RTRIM(r.tied))) IN ('false', '0', '0.0') THEN CAST(0 AS BIT)
                 ELSE CAST(TRY_CAST(r.tied AS FLOAT) AS BIT) END AS tied_clean,
            LEFT(NULLIF(LTRIM(RTRIM(r.medal)), ''), 20) AS medal_clean,
            ROW_NUMBER() OVER (PARTITION BY tp.id_part ORDER BY (SELECT NULL)) AS rn
        FROM stg.resultado r
        INNER JOIN #tp tp ON tp.id_part = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT)
        INNER JOIN dbo.participacion dp ON dp.id = tp.id_part
    )
    INSERT INTO dbo.resultado (id_participacion, place, tied, medal)
    SELECT id_part, place_clean, tied_clean, medal_clean
    FROM cte_res
    WHERE rn = 1
      AND NOT EXISTS (SELECT 1 FROM dbo.resultado x WHERE x.id_participacion = cte_res.id_part);
    SET @n = @@ROWCOUNT;
    PRINT '  resultado     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    -- 8. Población
    INSERT INTO dbo.poblacion (noc_code, anio, poblacion)
    SELECT
        UPPER(LEFT(LTRIM(RTRIM(pb.noc_code)), 3)) AS noc_code,
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)) AS anio,
        MAX(TRY_CAST(TRY_CAST(LTRIM(RTRIM(pb.population)) AS FLOAT) AS BIGINT)) AS poblacion
    FROM stg.poblacion pb
    INNER JOIN dbo.region rg ON rg.noc_code = UPPER(LEFT(LTRIM(RTRIM(pb.noc_code)), 3))
    WHERE TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)) IS NOT NULL
      AND EXISTS (SELECT 1 FROM #tp tp WHERE tp.noc_code = rg.noc_code)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.poblacion x
          WHERE x.noc_code = rg.noc_code
            AND x.anio = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT))
      )
    GROUP BY UPPER(LEFT(LTRIM(RTRIM(pb.noc_code)), 3)), TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT));
    SET @n = @@ROWCOUNT;
    PRINT '  poblacion     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ===============================================================
       FASE C: PURGA OPTIMIZADA DE STAGING
       =============================================================== */
    PRINT '--- Purgando staging ---';
    DELETE r
    FROM stg.resultado r
    INNER JOIN #tp tp ON tp.id_part = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT);

    DELETE FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion;

    SELECT DISTINCT TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT)) AS id_atl
    INTO #activos
    FROM stg.participacion;
    CREATE UNIQUE CLUSTERED INDEX CIX_act ON #activos(id_atl);

    DELETE ar
    FROM stg.atleta_rol ar
    WHERE NOT EXISTS (
        SELECT 1 FROM #activos a
        WHERE a.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT))
    );

    DELETE a
    FROM stg.atleta a
    WHERE NOT EXISTS (
        SELECT 1 FROM #activos aa
        WHERE aa.id_atl = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT))
    );

    DROP TABLE #tp;
    DROP TABLE #t_noc;
    DROP TABLE #ta;
    DROP TABLE #t_disc;
    DROP TABLE #activos;

    PRINT '--- Carga de ' + CAST(@anio AS VARCHAR(10)) + ' finalizada y Staging purgado ---';
END;
GO
PRINT 'Procedimiento dbo.sp_cargar_anio creado.';
GO