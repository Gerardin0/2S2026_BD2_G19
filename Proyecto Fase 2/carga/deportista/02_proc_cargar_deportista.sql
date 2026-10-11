/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt)

   carga/deportista/02_proc_cargar_deportista.sql
   Procedimiento reutilizable que carga, desde stg, TODAS las filas de Usain
   Bolt correspondientes a una edicion determinada.

   Se centraliza en un procedimiento porque las 4 cargas de Gerardo son
   exactamente el mismo proceso con un parametro distinto (2004, 2008, 2012,
   2016). Evita 4 copias del mismo codigo y deja el criterio de seleccion
   (deportista + edicion) declarado en un solo lugar.

   Es idempotente: se puede re-ejecutar sin duplicar filas.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deportista \
            -i 02_proc_cargar_deportista.sql
   ========================================================================== */

USE db_olimpiadas_deportista;
GO

IF OBJECT_ID('dbo.sp_cargar_deportista', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_deportista;
GO

CREATE PROCEDURE dbo.sp_cargar_deportista
    @anio       INT,          -- edicion a cargar (2004, 2008, 2012, 2016)
    @atleta_id  INT = 105512  -- Usain Bolt en tabla_atletas.csv
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_edicion INT;
    DECLARE @n INT;   -- filas afectadas por la ultima sentencia

    /* ---------------------------------------------------------------
       0. Localizar la edicion en el staging.
       El id del CSV (47 = Atenas 2004, 49 = Pekin 2008, 52 = Londres 2012,
       56 = Rio 2016) es el mismo que se conserva en dbo.edicion_juego
       mediante SET IDENTITY_INSERT.
       --------------------------------------------------------------- */
    SELECT @id_edicion = TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT)
    FROM stg.edicion_juego
    WHERE TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT) = @anio
      AND LTRIM(RTRIM(season)) = 'Summer';

    IF @id_edicion IS NULL
    BEGIN
        PRINT 'ERROR: no se encontro la edicion de verano ' + CAST(@anio AS VARCHAR(10)) + ' en stg.edicion_juego.';
        RETURN 1;
    END

    PRINT '=== Carga del deportista ' + CAST(@atleta_id AS VARCHAR(20))
        + ' para la edicion ' + CAST(@anio AS VARCHAR(10))
        + ' (id_edicion ' + CAST(@id_edicion AS VARCHAR(10)) + ') ===';

    /* ---------------------------------------------------------------
       1. dbo.region
       El CSV no trae country_name, que en el modelo final es NOT NULL.
       Se deriva del campo region del CSV (mismo criterio que el ETL de la
       Fase 1). Solo se insertan los NOC que realmente usa este atleta.
       --------------------------------------------------------------- */
    INSERT INTO dbo.region (noc_code, country_name, region, notas)
    SELECT DISTINCT
        LTRIM(RTRIM(p.noc_code)),
        LTRIM(RTRIM(r.region)),
        LTRIM(RTRIM(r.region)),
        LTRIM(RTRIM(r.notes))
    FROM stg.participacion p
    INNER JOIN stg.region r ON r.NOC = p.noc_code
    WHERE TRY_CAST(LTRIM(RTRIM(p.athlete_id)) AS FLOAT) = @atleta_id
      AND TRY_CAST(LTRIM(RTRIM(p.id_edicion_juego)) AS INT) = @id_edicion
      AND p.noc_code IS NOT NULL AND LTRIM(RTRIM(p.noc_code)) <> ''
      AND NOT EXISTS (SELECT 1 FROM dbo.region d
                      WHERE d.noc_code = LTRIM(RTRIM(p.noc_code)));
    SET @n = @@ROWCOUNT;
    PRINT '  region        -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       2. dbo.edicion_juego
       games_name tampoco viene en el CSV. Se deriva como
       "<anio> <season>", que es unico en las 63 ediciones del dataset
       (verificado: no hay colisiones).
       --------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.edicion_juego ON;
    INSERT INTO dbo.edicion_juego (id, [year], season, games_name, city, noc_code)
    SELECT
        TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT),
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT)),
        LTRIM(RTRIM(season)),
        /* CONCAT (y no el operador +) porque en T-SQL el operador + propaga
           NULL: "NULL + ' ' + 'Summer'" daria NULL y el modelo final exige
           games_name NOT NULL. CONCAT trata el NULL como cadena vacia. */
        CONCAT(TRY_CONVERT(VARCHAR(10), TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT))), ' ', LTRIM(RTRIM(season))),
        NULLIF(LTRIM(RTRIM(city)), ''),
        NULL    -- el CSV no dice que pais fue sede; se deja NULL
    FROM stg.edicion_juego
    WHERE TRY_CAST(LTRIM(RTRIM([year])) AS FLOAT) = @anio
      AND LTRIM(RTRIM(season)) = 'Summer'
      AND NOT EXISTS (SELECT 1 FROM dbo.edicion_juego d
                      WHERE d.id = TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.edicion_juego OFF;
    PRINT '  edicion_juego -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       3. dbo.disciplina
       Solo las disciplinas en las que compite el atleta en esa edicion.
       Se conservan los ids del CSV para no romper la FK de participacion.
       --------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.disciplina ON;
    INSERT INTO dbo.disciplina (id, sport, event_name)
    SELECT DISTINCT
        TRY_CAST(LTRIM(RTRIM(d.id_disciplina)) AS INT),
        LTRIM(RTRIM(d.sport)),
        LTRIM(RTRIM(d.event_name))
    FROM stg.participacion p
    INNER JOIN stg.disciplina d
        ON LTRIM(RTRIM(d.id_disciplina)) = LTRIM(RTRIM(p.id_disciplina))
    WHERE TRY_CAST(LTRIM(RTRIM(p.athlete_id)) AS FLOAT) = @atleta_id
      AND TRY_CAST(LTRIM(RTRIM(p.id_edicion_juego)) AS INT) = @id_edicion
      AND NOT EXISTS (SELECT 1 FROM dbo.disciplina x
                      WHERE x.id = TRY_CAST(LTRIM(RTRIM(d.id_disciplina)) AS INT));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.disciplina OFF;
    PRINT '  disciplina    -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       4. dbo.atleta
       El CSV llama "name" a lo que el modelo final guarda en full_name, y
       "Full name" a used_name (mismo mapeo que el ETL de la Fase 1).
       noc_code se toma del NOC con el que compito, para respetar la FK.
       --------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.atleta ON;
    INSERT INTO dbo.atleta (
        id, source_athlete_id, full_name, used_name, nombre_original,
        otros_nombres, orden_nombre, apodos, titulos, afiliaciones,
        nacionalidad, sex, born_date, born_city, born_region, born_country,
        latitud, longitud, died_date, died_place, noc_code)
    SELECT
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)),
        LTRIM(RTRIM(a.athlete_id)),
        COALESCE(NULLIF(LTRIM(RTRIM(a.name)), ''),
                 NULLIF(LTRIM(RTRIM(a.[Full name])), ''),
                 'Atleta ' + LTRIM(RTRIM(a.athlete_id))),
        NULLIF(LTRIM(RTRIM(a.[Full name])), ''),
        NULLIF(LTRIM(RTRIM(a.[Original name])), ''),
        NULLIF(LTRIM(RTRIM(a.[Other names])), ''),
        NULLIF(LTRIM(RTRIM(a.[Name order])), ''),
        NULLIF(LTRIM(RTRIM(a.[Nick/petnames])), ''),
        NULLIF(LTRIM(RTRIM(a.[Title(s)])), ''),
        NULLIF(LTRIM(RTRIM(a.Affiliations)), ''),
        NULLIF(LTRIM(RTRIM(a.Nationality)), ''),
        NULLIF(LTRIM(RTRIM(a.Sex)), ''),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(a.born_date)), '')),
        NULLIF(LTRIM(RTRIM(a.born_city)), ''),
        NULLIF(LTRIM(RTRIM(a.born_region)), ''),
        NULLIF(LTRIM(RTRIM(a.born_country)), ''),
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(a.lat)), '')),
        TRY_CONVERT(DECIMAL(9,6), NULLIF(LTRIM(RTRIM(a.[long])), '')),
        TRY_CONVERT(DATE, NULLIF(LTRIM(RTRIM(a.died_date)), '')),
        NULLIF(LTRIM(RTRIM(a.died_in)), ''),
        (SELECT TOP 1 LTRIM(RTRIM(p2.noc_code))
           FROM stg.participacion p2
          WHERE TRY_CAST(LTRIM(RTRIM(p2.athlete_id)) AS FLOAT) = @atleta_id
            AND TRY_CAST(LTRIM(RTRIM(p2.id_edicion_juego)) AS INT) = @id_edicion
            AND LTRIM(RTRIM(p2.noc_code)) <> ''
          ORDER BY LTRIM(RTRIM(p2.noc_code)))
    FROM stg.atleta a
    WHERE TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT) = @atleta_id
      AND NOT EXISTS (SELECT 1 FROM dbo.atleta x
                      WHERE x.id = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT)));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.atleta OFF;
    PRINT '  atleta        -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       5. dbo.roles y dbo.atleta_roles
       El CSV de roles es global (11 filas). Se carga completo la primera
       vez y no se vuelve a insertar en las cargas siguientes.
       --------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.roles ON;
    INSERT INTO dbo.roles (id, nombre, descripcion)
    SELECT TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT),
           LTRIM(RTRIM(nombre_rol)),
           NULL
    FROM stg.rol
    WHERE NOT EXISTS (SELECT 1 FROM dbo.roles x
                      WHERE x.id = TRY_CAST(LTRIM(RTRIM(rol_id)) AS INT));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.roles OFF;
    PRINT '  roles         -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    INSERT INTO dbo.atleta_roles (id_atleta, id_rol)
    SELECT DISTINCT
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT)),
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS INT))
    FROM stg.atleta_rol ar
    WHERE TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT) = @atleta_id
      AND NOT EXISTS (
            SELECT 1 FROM dbo.atleta_roles x
            WHERE x.id_atleta = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT))
              AND x.id_rol    = TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS INT));
    SET @n = @@ROWCOUNT;
    PRINT '  atleta_roles  -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       6. dbo.participacion
       athlete_id viene como decimal en el CSV ("105512.0"); el TRY_CAST
       a INT es lo que permite que la FK contra dbo.atleta se cumpla.
       --------------------------------------------------------------- */
    SET IDENTITY_INSERT dbo.participacion ON;
    INSERT INTO dbo.participacion (
        id, id_atleta, id_edicion, id_disciplina, noc_code,
        equipo, presentado_como, age, height_cm, weight_kg)
    SELECT
        TRY_CAST(LTRIM(RTRIM(p.id_participacion)) AS INT),
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(p.athlete_id)) AS FLOAT)),
        TRY_CAST(LTRIM(RTRIM(p.id_edicion_juego)) AS INT),
        TRY_CAST(LTRIM(RTRIM(p.id_disciplina)) AS INT),
        NULLIF(LTRIM(RTRIM(p.noc_code)), ''),
        NULLIF(LTRIM(RTRIM(p.team)), ''),
        NULLIF(LTRIM(RTRIM(p.presentado_como)), ''),
        TRY_CONVERT(DECIMAL(5,2), NULLIF(LTRIM(RTRIM(p.age)), '')),
        TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(p.height_cm)), '')),
        TRY_CONVERT(DECIMAL(6,2), NULLIF(LTRIM(RTRIM(p.weight_kg)), ''))
    FROM stg.participacion p
    WHERE TRY_CAST(LTRIM(RTRIM(p.athlete_id)) AS FLOAT) = @atleta_id
      AND TRY_CAST(LTRIM(RTRIM(p.id_edicion_juego)) AS INT) = @id_edicion
      AND NOT EXISTS (SELECT 1 FROM dbo.participacion x
                      WHERE x.id = TRY_CAST(LTRIM(RTRIM(p.id_participacion)) AS INT));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.participacion OFF;
    PRINT '  participacion -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       7. dbo.resultado
       Solo para las participaciones que se acaban de cargar, respetando
       el UNIQUE(id_participacion) del modelo final.
       place llega como "5.0" o como cadena vacia; tied como 0.0/1.0.
       --------------------------------------------------------------- */
    INSERT INTO dbo.resultado (id_participacion, place, tied, medal)
    SELECT
        TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT),
        CASE WHEN LTRIM(RTRIM(r.place)) = '' THEN NULL
             WHEN TRY_CAST(r.place AS FLOAT) = FLOOR(TRY_CAST(r.place AS FLOAT))
                  THEN CAST(CAST(TRY_CAST(r.place AS FLOAT) AS INT) AS VARCHAR(20))
             ELSE LTRIM(RTRIM(r.place)) END,
        CASE WHEN LTRIM(RTRIM(r.tied)) = '' THEN NULL
             ELSE CAST(TRY_CAST(r.tied AS FLOAT) AS BIT) END,
        NULLIF(LTRIM(RTRIM(r.medal)), '')
    FROM stg.resultado r
    INNER JOIN dbo.participacion pp
        ON pp.id = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT)
       AND pp.id_atleta = @atleta_id
       AND pp.id_edicion = @id_edicion
    WHERE NOT EXISTS (SELECT 1 FROM dbo.resultado x
                      WHERE x.id_participacion = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT));
    SET @n = @@ROWCOUNT;
    PRINT '  resultado     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       8. dbo.poblacion
       Solo el NOC del atleta (JAM), para que la tabla tenga contenido que
       mostrar en las capturas sin inflar el respaldo.
       --------------------------------------------------------------- */
    INSERT INTO dbo.poblacion (noc_code, anio, poblacion)
    SELECT
        LTRIM(RTRIM(pb.noc_code)),
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)),
        TRY_CAST(LTRIM(RTRIM(pb.population)) AS BIGINT)
    FROM stg.poblacion pb
    INNER JOIN dbo.region rg ON rg.noc_code = LTRIM(RTRIM(pb.noc_code))
    WHERE EXISTS (SELECT 1 FROM dbo.participacion pp
                   WHERE pp.id_atleta = @atleta_id
                     AND pp.id_edicion = @id_edicion
                     AND pp.noc_code = rg.noc_code)
      AND NOT EXISTS (SELECT 1 FROM dbo.poblacion x
                      WHERE x.noc_code = LTRIM(RTRIM(pb.noc_code))
                        AND x.anio    = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)));
    SET @n = @@ROWCOUNT;
    PRINT '  poblacion     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       9. Purga de staging.
       Tras el backup diferencial anterior ya se tiene lo que interesaba,
       asi que se eliminan de stg las filas que NO pertenecen a esta
       edicion. Motivo PRACTICO: si stg se quedara con los 153 mil atletas
       y las 323 mil participaciones en el momento del FULL, cada
       diferencial posterior seria practicamente vacio y las mediciones de
       tiempo no significarian nada.

       OJO con el tipo del casteo: athlete_id llega como "105512.0".
       TRY_CAST('7.0' AS INT) devuelve NULL (no error, NULL), y una
       comparacion con NULL nunca es verdadera, asi que castear a INT
       aqui dejaba filas sin purgar. Se castea a FLOAT, que si acepta el
       decimal, y se agrega "IS NULL" para no dejar filas huerfanas.
       --------------------------------------------------------------- */
    /* Se conservan TODAS las participaciones del atleta (las 10, de las 4
       ediciones), no solo las de la edicion actual: las cargas 2, 3 y 4
       necesitan encontrar su propia edicion dentro de stg.participacion. */
    DELETE FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) <> @atleta_id;

    DELETE FROM stg.resultado
    WHERE TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT) NOT IN (
        SELECT TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT)
        FROM stg.participacion);

    DELETE FROM stg.atleta
    WHERE TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) <> @atleta_id;

    DELETE FROM stg.atleta_rol
    WHERE TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) <> @atleta_id;

    /* Se conservan las disciplinas que usa el atleta en alguna de sus
       ediciones, mas las que ya estan en dbo.disciplina. */
    DELETE FROM stg.disciplina
    WHERE TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) NOT IN (
        SELECT TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT)
        FROM stg.participacion)
      AND TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT)
          NOT IN (SELECT id FROM dbo.disciplina);

    /* stg.edicion_juego NO se purga: son solo 63 filas y las necesitan
       las cargas siguientes para resolver su edicion. Purgarla hacia que
       la carga 2 abortara con "no se encontro la edicion de verano 2008". */

    DELETE FROM stg.poblacion
    WHERE LTRIM(RTRIM(noc_code)) NOT IN (SELECT noc_code FROM dbo.region);

    DELETE FROM stg.region
    WHERE LTRIM(RTRIM(NOC)) NOT IN (SELECT noc_code FROM dbo.region);

    PRINT '--- Carga de ' + CAST(@anio AS VARCHAR(10)) + ' finalizada. ---';
    RETURN 0;
END;
GO

PRINT 'Procedimiento dbo.sp_cargar_deportista creado.';
GO