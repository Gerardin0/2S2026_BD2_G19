/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Jose - Carga por DEPORTE (100 m planos femeninos)

   carga/deporte/02_proc_cargar_deporte.sql
   Procedimiento reutilizable que carga, desde stg, TODAS las filas de los
   100 m planos femeninos correspondientes a una edicion determinada.

   Se centraliza en un procedimiento porque las 4 cargas de Jose son
   exactamente el mismo proceso con un parametro distinto (2024, 2020, 2016,
   2012). Evita 4 copias del mismo codigo y deja el criterio de seleccion
   (deporte + edicion) declarado en un solo lugar.

   Es el mismo procedimiento que carga/deportista/02_proc_cargar_deportista.sql
   con el filtro cambiado: alla es athlete_id = @atleta_id, aqui es
   id_disciplina = @id_disciplina. Los 9 pasos y su orden son los mismos.

   Es idempotente: se puede re-ejecutar sin duplicar filas.

   OPTIMIZACION (version con #atl):
   Los pasos 4 (dbo.atleta) y 5 (dbo.atleta_roles) recorrian, por cada una
   de las ~153 mil filas de stg.atleta / stg.atleta_rol, las ~323 mil filas
   de stg.participacion para saber si esa persona corre el evento. En la
   carga 1, con el staging completo, eso tomaba varios minutos.
   Ahora la lista de atletas del evento en la edicion se calcula UNA vez en
   la tabla temporal #atl (con PK) y ambos pasos filtran contra ella.
   La purga del paso 9 usa el mismo recurso (#keep_*), porque sus NOT IN
   eran el verdadero cuello de botella (~4.5 de los ~6 minutos).
   El resultado es identico; solo cambia el plan de ejecucion.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deporte \
            -i 02_proc_cargar_deporte.sql
   ========================================================================== */

USE db_olimpiadas_deporte;
GO

IF OBJECT_ID('dbo.sp_cargar_deporte', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_cargar_deporte;
GO

CREATE PROCEDURE dbo.sp_cargar_deporte
    @anio           INT,        -- edicion a cargar (2024, 2020, 2016, 2012)
    @id_disciplina  INT = 237   -- "100 metres, Women (Olympic)" en tabla_disciplina.csv
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id_edicion INT;
    DECLARE @n INT;   -- filas afectadas por la ultima sentencia

    /* ---------------------------------------------------------------
       0. Localizar la edicion en el staging.
       El id del CSV (63 = Paris 2024, 60 = Tokio 2020, 56 = Rio 2016,
       52 = Londres 2012) es el mismo que se conserva en dbo.edicion_juego
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

    PRINT '=== Carga del deporte (disciplina ' + CAST(@id_disciplina AS VARCHAR(20))
        + ') para la edicion ' + CAST(@anio AS VARCHAR(10))
        + ' (id_edicion ' + CAST(@id_edicion AS VARCHAR(10)) + ') ===';

    /* ---------------------------------------------------------------
       Atletas que corren el evento en esta edicion, calculados UNA vez.
       Los pasos 4 y 5 filtran contra esta tabla en lugar de recorrer
       stg.participacion completa por cada fila de stg.atleta.
       noc_code: el NOC con el que compite (el menor si hubiera varios),
       mismo criterio que el TOP 1 ... ORDER BY de la version anterior.
       --------------------------------------------------------------- */
    CREATE TABLE #atl (
        id        FLOAT        NOT NULL PRIMARY KEY,
        noc_code  NVARCHAR(10) COLLATE DATABASE_DEFAULT NULL
    );
    INSERT INTO #atl (id, noc_code)
    SELECT TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT),
           MIN(NULLIF(LTRIM(RTRIM(noc_code)), ''))
    FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) = @id_disciplina
      AND TRY_CAST(LTRIM(RTRIM(id_edicion_juego)) AS INT) = @id_edicion
      AND TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) IS NOT NULL
    GROUP BY TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT);

    /* ---------------------------------------------------------------
       1. dbo.region
       El CSV no trae country_name, que en el modelo final es NOT NULL.
       Se deriva del campo region del CSV (mismo criterio que el ETL de la
       Fase 1). Solo se insertan los NOC que compiten en esta disciplina
       y edicion.
       --------------------------------------------------------------- */
    INSERT INTO dbo.region (noc_code, country_name, region, notas)
    SELECT DISTINCT
        LTRIM(RTRIM(p.noc_code)),
        /* COALESCE: tabla_nocs.csv trae region vacia para TUV, ROT y UNK, y
           Tuvalu compite en este evento. Sin el, country_name (NOT NULL)
           recibe NULL y falla el INSERT completo. */
        COALESCE(LTRIM(RTRIM(r.region)), LTRIM(RTRIM(p.noc_code))),
        LTRIM(RTRIM(r.region)),
        LTRIM(RTRIM(r.notes))
    FROM stg.participacion p
    INNER JOIN stg.region r ON r.NOC = p.noc_code
    WHERE TRY_CAST(LTRIM(RTRIM(p.id_disciplina)) AS INT) = @id_disciplina
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
       Solo la disciplina de esta carga (se inserta en la carga 1 y las
       siguientes ya la encuentran). Se conserva el id del CSV para no
       romper la FK de participacion.
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
    WHERE TRY_CAST(LTRIM(RTRIM(p.id_disciplina)) AS INT) = @id_disciplina
      AND TRY_CAST(LTRIM(RTRIM(p.id_edicion_juego)) AS INT) = @id_edicion
      AND NOT EXISTS (SELECT 1 FROM dbo.disciplina x
                      WHERE x.id = TRY_CAST(LTRIM(RTRIM(d.id_disciplina)) AS INT));
    SET @n = @@ROWCOUNT;
    SET IDENTITY_INSERT dbo.disciplina OFF;
    PRINT '  disciplina    -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       4. dbo.atleta
       Las atletas que compiten en la disciplina en esta edicion y que
       todavia no estan cargadas (muchas repiten entre ediciones).
       El CSV llama "name" a lo que el modelo final guarda en full_name, y
       "Full name" a used_name (mismo mapeo que el ETL de la Fase 1).
       noc_code se toma del NOC con el que compite, para respetar la FK.
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
        /* LEFT(..., 50): el staging no interpreta las comillas del CSV, asi
           que un campo con coma corre la fila una columna y aqui puede
           llegar un texto mas largo que orden_nombre NVARCHAR(50). Pasa en
           6 de las 261 atletas; sin el recorte el INSERT completo falla. */
        LEFT(NULLIF(LTRIM(RTRIM(a.[Name order])), ''), 50),
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
        (SELECT t.noc_code FROM #atl t
          WHERE t.id = TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT))
    FROM stg.atleta a
    WHERE TRY_CAST(LTRIM(RTRIM(a.athlete_id)) AS FLOAT) IN (SELECT id FROM #atl)
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
    WHERE TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT) IN (SELECT id FROM #atl)
      AND NOT EXISTS (
            SELECT 1 FROM dbo.atleta_roles x
            WHERE x.id_atleta = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(ar.athlete_id)) AS FLOAT))
              AND x.id_rol    = TRY_CAST(LTRIM(RTRIM(ar.rol_id)) AS INT));
    SET @n = @@ROWCOUNT;
    PRINT '  atleta_roles  -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       6. dbo.participacion
       athlete_id viene como decimal en el CSV ("64991.0"); el TRY_CAST
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
    WHERE TRY_CAST(LTRIM(RTRIM(p.id_disciplina)) AS INT) = @id_disciplina
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
       AND pp.id_disciplina = @id_disciplina
       AND pp.id_edicion = @id_edicion
    WHERE NOT EXISTS (SELECT 1 FROM dbo.resultado x
                      WHERE x.id_participacion = TRY_CAST(LTRIM(RTRIM(r.id_participacion)) AS INT));
    SET @n = @@ROWCOUNT;
    PRINT '  resultado     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       8. dbo.poblacion
       Solo los NOC que compiten en la disciplina en esta edicion, para
       que la tabla tenga contenido que mostrar en las capturas sin
       inflar el respaldo.
       --------------------------------------------------------------- */
    INSERT INTO dbo.poblacion (noc_code, anio, poblacion)
    SELECT
        LTRIM(RTRIM(pb.noc_code)),
        TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)),
        TRY_CAST(LTRIM(RTRIM(pb.population)) AS BIGINT)
    FROM stg.poblacion pb
    INNER JOIN dbo.region rg ON rg.noc_code = LTRIM(RTRIM(pb.noc_code))
    WHERE EXISTS (SELECT 1 FROM dbo.participacion pp
                   WHERE pp.id_disciplina = @id_disciplina
                     AND pp.id_edicion = @id_edicion
                     AND pp.noc_code = rg.noc_code)
      AND NOT EXISTS (SELECT 1 FROM dbo.poblacion x
                      WHERE x.noc_code = LTRIM(RTRIM(pb.noc_code))
                        AND x.anio    = TRY_CONVERT(INT, TRY_CAST(LTRIM(RTRIM(pb.[year])) AS FLOAT)));
    SET @n = @@ROWCOUNT;
    PRINT '  poblacion     -> ' + CAST(@n AS VARCHAR(20)) + ' filas';

    /* ---------------------------------------------------------------
       9. Purga de staging.
       Se eliminan de stg las filas que NO pertenecen a esta disciplina.
       Motivo PRACTICO: si stg se quedara con los 153 mil atletas y las
       323 mil participaciones en el momento del FULL, cada diferencial
       posterior seria practicamente vacio y las mediciones de tiempo no
       significarian nada.

       OJO con el tipo del casteo: athlete_id llega como "64991.0".
       TRY_CAST('7.0' AS INT) devuelve NULL (no error, NULL), y una
       comparacion con NULL nunca es verdadera, asi que castear a INT
       aqui dejaba filas sin purgar. Se castea a FLOAT, que si acepta el
       decimal, y se agrega "IS NULL" para no dejar filas huerfanas.

       WITH (TABLOCK): stg.* son heaps; con bloqueo de tabla, SQL Server
       libera las paginas que el DELETE deja vacias en lugar de dejarlas
       reservadas (y dentro del respaldo FULL).
       --------------------------------------------------------------- */
    /* Se conservan TODAS las participaciones de la disciplina (todas sus
       ediciones), no solo las de la edicion actual: las cargas 2, 3 y 4
       necesitan encontrar su propia edicion dentro de stg.participacion. */
    DELETE FROM stg.participacion WITH (TABLOCK)
    WHERE TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) IS NULL
       OR TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) <> @id_disciplina;

    /* Lo que sobrevive en stg.participacion define que se conserva en el
       resto del staging. Se guarda UNA vez en tablas temporales con PK.

       OPTIMIZACION: la version anterior usaba NOT IN (subconsulta sobre
       stg.participacion) en cada DELETE. Como se compara una expresion
       (TRY_CAST(...)) contra otra, sin indices, el motor resolvia el NOT IN
       con un bucle anidado: ~153 mil filas de stg.atleta por ~1 200 de
       stg.participacion, y lo mismo en stg.atleta_rol. Esa purga sola
       tomaba ~4.5 minutos de la carga 1; con #keep_* toma segundos.
       NOT EXISTS (en vez de NOT IN) tambien evita que un NULL en la
       subconsulta anule el borrado. */
    CREATE TABLE #keep_part (id INT   NOT NULL PRIMARY KEY);
    CREATE TABLE #keep_atl  (id FLOAT NOT NULL PRIMARY KEY);
    CREATE TABLE #keep_disc (id INT   NOT NULL PRIMARY KEY);
    CREATE TABLE #keep_noc  (noc_code NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY);

    INSERT INTO #keep_part (id)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT)
    FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(id_participacion)) AS INT) IS NOT NULL;

    /* UNICA DIFERENCIA DE FONDO con la purga de la carga por deportista:
       alla el atleta y su NOC son siempre los mismos, asi que basta con
       conservar lo que ya esta en dbo. Aqui cada edicion trae atletas y
       NOC nuevos, por lo que se conservan los de TODAS las participaciones
       que quedan en stg; si no, la carga 2 no encontraria sus atletas ni
       sus regiones. */
    INSERT INTO #keep_atl (id)
    SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT)
    FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(athlete_id)) AS FLOAT) IS NOT NULL;

    /* Se conservan las disciplinas que quedan en stg.participacion, mas
       las que ya estan en dbo.disciplina. */
    INSERT INTO #keep_disc (id)
    SELECT TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) FROM stg.participacion
    WHERE TRY_CAST(LTRIM(RTRIM(id_disciplina)) AS INT) IS NOT NULL
    UNION
    SELECT id FROM dbo.disciplina;

    INSERT INTO #keep_noc (noc_code)
    SELECT LTRIM(RTRIM(noc_code)) FROM stg.participacion
    WHERE noc_code IS NOT NULL AND LTRIM(RTRIM(noc_code)) <> ''
    UNION
    SELECT noc_code FROM dbo.region;

    DELETE x FROM stg.resultado AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_part k
                      WHERE k.id = TRY_CAST(LTRIM(RTRIM(x.id_participacion)) AS INT));

    DELETE x FROM stg.atleta AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_atl k
                      WHERE k.id = TRY_CAST(LTRIM(RTRIM(x.athlete_id)) AS FLOAT));

    DELETE x FROM stg.atleta_rol AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_atl k
                      WHERE k.id = TRY_CAST(LTRIM(RTRIM(x.athlete_id)) AS FLOAT));

    DELETE x FROM stg.disciplina AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_disc k
                      WHERE k.id = TRY_CAST(LTRIM(RTRIM(x.id_disciplina)) AS INT));

    /* stg.edicion_juego NO se purga: son solo 63 filas y las necesitan
       las cargas siguientes para resolver su edicion. */

    DELETE x FROM stg.poblacion AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_noc k WHERE k.noc_code = LTRIM(RTRIM(x.noc_code)));

    DELETE x FROM stg.region AS x WITH (TABLOCK)
    WHERE NOT EXISTS (SELECT 1 FROM #keep_noc k WHERE k.noc_code = LTRIM(RTRIM(x.NOC)));

    PRINT '--- Carga de ' + CAST(@anio AS VARCHAR(10)) + ' finalizada. ---';
    RETURN 0;
END;
GO

PRINT 'Procedimiento dbo.sp_cargar_deporte creado.';
GO
