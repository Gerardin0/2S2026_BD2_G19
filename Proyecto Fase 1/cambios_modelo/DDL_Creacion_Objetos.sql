/* ==========================================================================
   1. CREACION DE LA BASE DE DATOS
   ========================================================================== */
IF DB_ID('db_olimpiadas') IS NULL
BEGIN
    CREATE DATABASE db_olimpiadas;
END;
GO

USE db_olimpiadas;
GO

/* ==========================================================================
   2. LIMPIEZA PREVIA
   ========================================================================== */
IF OBJECT_ID('dbo.sp_obtener_info_atleta', 'P') IS NOT NULL DROP PROCEDURE dbo.sp_obtener_info_atleta;
IF OBJECT_ID('dbo.sp_obtener_info_pais', 'P')   IS NOT NULL DROP PROCEDURE dbo.sp_obtener_info_pais;

IF OBJECT_ID('dbo.resultado', 'U')            IS NOT NULL DROP TABLE dbo.resultado;
IF OBJECT_ID('dbo.atleta_roles', 'U')         IS NOT NULL DROP TABLE dbo.atleta_roles;
IF OBJECT_ID('dbo.participacion_roles', 'U')  IS NOT NULL DROP TABLE dbo.participacion_roles;
IF OBJECT_ID('dbo.participacion', 'U')        IS NOT NULL DROP TABLE dbo.participacion;
IF OBJECT_ID('dbo.roles', 'U')                IS NOT NULL DROP TABLE dbo.roles;
IF OBJECT_ID('dbo.atleta', 'U')               IS NOT NULL DROP TABLE dbo.atleta;
IF OBJECT_ID('dbo.disciplina', 'U')           IS NOT NULL DROP TABLE dbo.disciplina;
IF OBJECT_ID('dbo.edicion_juego', 'U')        IS NOT NULL DROP TABLE dbo.edicion_juego;
IF OBJECT_ID('dbo.poblacion', 'U')            IS NOT NULL DROP TABLE dbo.poblacion;
IF OBJECT_ID('dbo.pais_poblacion', 'U')       IS NOT NULL DROP TABLE dbo.pais_poblacion;
IF OBJECT_ID('dbo.region', 'U')               IS NOT NULL DROP TABLE dbo.region;

IF OBJECT_ID('stg.unificado', 'U')          IS NOT NULL DROP TABLE stg.unificado;
IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg;');
GO

/* ==========================================================================
   3. TABLA DE STAGING
   ========================================================================== */
CREATE TABLE stg.unificado (
    source_file        NVARCHAR(MAX) NULL,
    source_athlete_id  NVARCHAR(MAX) NULL,
    full_name          NVARCHAR(MAX) NULL,
    used_name          NVARCHAR(MAX) NULL,
    nombre_original    NVARCHAR(MAX) NULL,
    otros_nombres      NVARCHAR(MAX) NULL,
    orden_nombre       NVARCHAR(MAX) NULL,
    apodos             NVARCHAR(MAX) NULL,
    titulos            NVARCHAR(MAX) NULL,
    afiliaciones       NVARCHAR(MAX) NULL,
    nacionalidad       NVARCHAR(MAX) NULL,
    roles              NVARCHAR(MAX) NULL,
    sex                NVARCHAR(MAX) NULL,
    age                NVARCHAR(MAX) NULL,
    height_cm          NVARCHAR(MAX) NULL,
    weight_kg          NVARCHAR(MAX) NULL,
    born_date          NVARCHAR(MAX) NULL,
    born_city          NVARCHAR(MAX) NULL,
    born_region        NVARCHAR(MAX) NULL,
    born_country       NVARCHAR(MAX) NULL,
    born_lat           NVARCHAR(MAX) NULL,
    born_lon           NVARCHAR(MAX) NULL,
    died_date          NVARCHAR(MAX) NULL,
    noc                NVARCHAR(MAX) NULL,
    country_name       NVARCHAR(MAX) NULL,
    region             NVARCHAR(MAX) NULL,
    notas              NVARCHAR(MAX) NULL,
    team               NVARCHAR(MAX) NULL,
    presentado_como    NVARCHAR(MAX) NULL,
    games_name         NVARCHAR(MAX) NULL,
    year               NVARCHAR(MAX) NULL,
    season             NVARCHAR(MAX) NULL,
    city               NVARCHAR(MAX) NULL,
    sport              NVARCHAR(MAX) NULL,
    event_name         NVARCHAR(MAX) NULL,
    place              NVARCHAR(MAX) NULL,
    tied               NVARCHAR(MAX) NULL,
    medal              NVARCHAR(MAX) NULL
);
GO

/* ==========================================================================
   4. MODELO RELACIONAL FINAL
   ========================================================================== */

CREATE TABLE dbo.region (
    noc_code      NVARCHAR(10)  NOT NULL,
    country_name  NVARCHAR(200) NOT NULL,
    region        NVARCHAR(200) NULL,
    notas         NVARCHAR(MAX) NULL,
    CONSTRAINT pk_region PRIMARY KEY (noc_code)
);

CREATE TABLE dbo.edicion_juego (
    id          INT           IDENTITY(1,1) NOT NULL,
    [year]      INT           NULL,
    season      NVARCHAR(20)  NULL,
    games_name  NVARCHAR(200) NOT NULL,
    city        NVARCHAR(200) NULL,
    noc_code    NVARCHAR(10)  NULL,
    CONSTRAINT pk_edicion_juego     PRIMARY KEY (id),
    CONSTRAINT uq_edicion_juego     UNIQUE (games_name),
    CONSTRAINT fk_edicion_region    FOREIGN KEY (noc_code) REFERENCES dbo.region(noc_code)
);

CREATE TABLE dbo.disciplina (
    id          INT           IDENTITY(1,1) NOT NULL,
    sport       NVARCHAR(200) NOT NULL,
    event_name  NVARCHAR(300) NOT NULL,
    CONSTRAINT pk_disciplina        PRIMARY KEY (id),
    CONSTRAINT uq_disciplina_evento UNIQUE (sport, event_name)
);

CREATE TABLE dbo.atleta (
    id                 INT           IDENTITY(1,1) NOT NULL,
    source_athlete_id  NVARCHAR(50)  NULL,
    full_name          NVARCHAR(300) NOT NULL,
    used_name          NVARCHAR(300) NULL,
    nombre_original    NVARCHAR(300) NULL,
    otros_nombres      NVARCHAR(MAX) NULL,
    orden_nombre       NVARCHAR(50)  NULL,
    apodos             NVARCHAR(MAX) NULL,
    titulos            NVARCHAR(MAX) NULL,
    afiliaciones       NVARCHAR(MAX) NULL,
    nacionalidad       NVARCHAR(200) NULL,
    sex                NVARCHAR(10)  NULL,
    born_date          DATE          NULL,
    born_city          NVARCHAR(200) NULL,
    born_region        NVARCHAR(200) NULL,
    born_country       NVARCHAR(200) NULL,
    latitud            DECIMAL(9,6)  NULL,
    longitud           DECIMAL(9,6)  NULL,
    died_date          DATE          NULL,
    died_place         NVARCHAR(300) NULL,
    noc_code           NVARCHAR(10)  NULL,
    CONSTRAINT pk_atleta        PRIMARY KEY (id),
    CONSTRAINT fk_atleta_region FOREIGN KEY (noc_code) REFERENCES dbo.region(noc_code)
);

CREATE TABLE dbo.participacion (
    id               INT           IDENTITY(1,1) NOT NULL,
    id_atleta        INT           NOT NULL,
    id_edicion       INT           NOT NULL,
    id_disciplina    INT           NOT NULL,
    noc_code         NVARCHAR(10)  NULL,
    equipo           NVARCHAR(300) NULL,
    presentado_como  NVARCHAR(300) NULL,
    age              DECIMAL(5,2)  NULL,
    height_cm        DECIMAL(6,2)  NULL,
    weight_kg        DECIMAL(6,2)  NULL,
    CONSTRAINT pk_participacion            PRIMARY KEY (id),
    CONSTRAINT fk_participacion_atleta     FOREIGN KEY (id_atleta)     REFERENCES dbo.atleta(id),
    CONSTRAINT fk_participacion_edicion    FOREIGN KEY (id_edicion)    REFERENCES dbo.edicion_juego(id),
    CONSTRAINT fk_participacion_disciplina FOREIGN KEY (id_disciplina) REFERENCES dbo.disciplina(id),
    CONSTRAINT fk_participacion_region     FOREIGN KEY (noc_code)      REFERENCES dbo.region(noc_code)
);

CREATE TABLE dbo.resultado (
    id               INT           IDENTITY(1,1) NOT NULL,
    id_participacion INT           NOT NULL,
    place            NVARCHAR(20)  NULL,
    tied             BIT           NULL,
    medal            NVARCHAR(10)  NULL,
    CONSTRAINT pk_resultado           PRIMARY KEY (id),
    CONSTRAINT uq_resultado_particip  UNIQUE (id_participacion),
    CONSTRAINT fk_resultado_particip  FOREIGN KEY (id_participacion) REFERENCES dbo.participacion(id)
);

CREATE TABLE dbo.poblacion (
    noc_code   NVARCHAR(10) NOT NULL,
    anio       INT          NOT NULL,
    poblacion  BIGINT       NULL,
    CONSTRAINT pk_poblacion        PRIMARY KEY (noc_code, anio),
    CONSTRAINT fk_poblacion_region FOREIGN KEY (noc_code) REFERENCES dbo.region(noc_code)
);

CREATE TABLE dbo.roles (
    id          INT           IDENTITY(1,1) NOT NULL,
    nombre      NVARCHAR(100) NOT NULL,
    descripcion NVARCHAR(300) NULL,
    CONSTRAINT pk_roles        PRIMARY KEY (id),
    CONSTRAINT uq_roles_nombre UNIQUE (nombre)
);

CREATE TABLE dbo.atleta_roles (
    id_atleta INT NOT NULL,
    id_rol    INT NOT NULL,
    CONSTRAINT pk_atleta_roles     PRIMARY KEY (id_atleta, id_rol),
    CONSTRAINT fk_atrol_atleta     FOREIGN KEY (id_atleta) REFERENCES dbo.atleta(id),
    CONSTRAINT fk_atrol_rol        FOREIGN KEY (id_rol)    REFERENCES dbo.roles(id)
);
GO

/* ==========================================================================
   5. INDICES
   ========================================================================== */
CREATE NONCLUSTERED INDEX ix_atleta_names ON dbo.atleta(full_name, used_name);
CREATE NONCLUSTERED INDEX ix_participacion_busqueda ON dbo.participacion(id_atleta, id_edicion, id_disciplina);
CREATE NONCLUSTERED INDEX ix_participacion_noc ON dbo.participacion(noc_code);
CREATE NONCLUSTERED INDEX ix_edicion_noc ON dbo.edicion_juego(noc_code);
CREATE NONCLUSTERED INDEX ix_edicion_year ON dbo.edicion_juego([year]);
CREATE NONCLUSTERED INDEX ix_resultado_medal ON dbo.resultado(medal);
GO

/* ==========================================================================
   6. STORED PROCEDURES
   ========================================================================== */

-- STORED PROCEDURE 1: INFORMACION DE ATLETA
CREATE PROCEDURE dbo.sp_obtener_info_atleta
    @nombre_atleta NVARCHAR(300),
    @deporte       NVARCHAR(200) = NULL,
    @pais          NVARCHAR(200) = NULL,
    @anio          INT           = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Ficha del Atleta
    SELECT 
        a.id AS id_atleta,
        a.full_name AS nombre_atleta,
        a.used_name AS nombre_uso_comun,
        a.sex AS genero,
        a.born_date AS fecha_nacimiento,
        CONCAT_WS(', ', NULLIF(a.born_city, ''), NULLIF(a.born_region, ''), NULLIF(a.born_country, '')) AS lugar_nacimiento,
        a.nacionalidad,
        r_atleta.country_name AS pais_defecto,
        STRING_AGG(ro.nombre, ', ') AS roles
    FROM dbo.atleta a
    LEFT JOIN dbo.region r_atleta ON a.noc_code = r_atleta.noc_code
    LEFT JOIN dbo.atleta_roles ar ON a.id = ar.id_atleta
    LEFT JOIN dbo.roles ro ON ar.id_rol = ro.id
    WHERE a.full_name LIKE '%' + @nombre_atleta + '%'
       OR a.used_name LIKE '%' + @nombre_atleta + '%'
       OR a.otros_nombres LIKE '%' + @nombre_atleta + '%'
    GROUP BY 
        a.id, a.full_name, a.used_name, a.sex, a.born_date, a.born_city, 
        a.born_region, a.born_country, a.nacionalidad, r_atleta.country_name;

    -- 2. Historial de Participaciones y Resultados
    SELECT 
        a.full_name AS atleta,
        ej.games_name AS edicion_juegos,
        ej.year AS anio,
        ej.season AS temporada,
        ej.city AS ciudad_sede,
        d.sport AS deporte,
        d.event_name AS prueba_disciplina,
        p.noc_code AS codigo_noc,
        reg.country_name AS pais_representado,
        p.equipo,
        p.presentado_como,
        p.age AS edad,
        p.height_cm AS estatura_cm,
        p.weight_kg AS peso_kg,
        res.place AS posicion_final,
        -- NULL = empate no determinable (ediciones sin posicion final real)
        CASE WHEN res.tied = 1 THEN 'Sí' WHEN res.tied = 0 THEN 'No'
             ELSE 'Desconocido' END AS hubo_empate,
        ISNULL(res.medal, 'Sin Medalla') AS medalla
    FROM dbo.atleta a
    INNER JOIN dbo.participacion p ON a.id = p.id_atleta
    INNER JOIN dbo.edicion_juego ej ON p.id_edicion = ej.id
    INNER JOIN dbo.disciplina d ON p.id_disciplina = d.id
    LEFT JOIN dbo.region reg ON p.noc_code = reg.noc_code
    LEFT JOIN dbo.resultado res ON p.id = res.id_participacion
    WHERE (a.full_name LIKE '%' + @nombre_atleta + '%' OR a.used_name LIKE '%' + @nombre_atleta + '%')
      AND (@deporte IS NULL OR d.sport LIKE '%' + @deporte + '%')
      AND (@anio IS NULL OR ej.year = @anio)
      AND (@pais IS NULL OR reg.noc_code = UPPER(@pais) OR reg.country_name LIKE '%' + @pais + '%')
    ORDER BY ej.year DESC, d.sport, d.event_name;
END;
GO

-- STORED PROCEDURE 2: INFORMACION DE PAIS
CREATE PROCEDURE dbo.sp_obtener_info_pais
    @pais    NVARCHAR(200),
    @anio    INT           = NULL,
    @deporte NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Datos Generales de la Región / País
    SELECT 
        r.noc_code AS codigo_noc,
        r.country_name AS nombre_pais,
        r.region AS region_continente,
        r.notas
    FROM dbo.region r
    WHERE UPPER(r.noc_code) = UPPER(@pais) OR r.country_name LIKE '%' + @pais + '%';

    -- 2. Ediciones donde el País ha sido SEDE
    SELECT 
        ej.games_name AS edicion,
        ej.year AS anio_sede,
        ej.season AS temporada,
        ej.city AS ciudad_sede
    FROM dbo.edicion_juego ej
    INNER JOIN dbo.region r ON ej.noc_code = r.noc_code
    WHERE UPPER(r.noc_code) = UPPER(@pais) OR r.country_name LIKE '%' + @pais + '%'
    ORDER BY ej.year ASC;

    -- 3. Resumen de Medallas
    SELECT 
        r.country_name AS pais,
        COUNT(DISTINCT p.id) AS total_participaciones,
        COUNT(DISTINCT p.id_atleta) AS total_atletas,
        COUNT(CASE WHEN res.medal = 'Gold' THEN 1 END) AS medallas_oro,
        COUNT(CASE WHEN res.medal = 'Silver' THEN 1 END) AS medallas_plata,
        COUNT(CASE WHEN res.medal = 'Bronze' THEN 1 END) AS medallas_bronce,
        COUNT(res.medal) AS total_medallas
    FROM dbo.region r
    INNER JOIN dbo.participacion p ON r.noc_code = p.noc_code
    INNER JOIN dbo.edicion_juego ej ON p.id_edicion = ej.id
    INNER JOIN dbo.disciplina d ON p.id_disciplina = d.id
    LEFT JOIN dbo.resultado res ON p.id = res.id_participacion
    WHERE (UPPER(r.noc_code) = UPPER(@pais) OR r.country_name LIKE '%' + @pais + '%')
      AND (@anio IS NULL OR ej.year = @anio)
      AND (@deporte IS NULL OR d.sport LIKE '%' + @deporte + '%')
    GROUP BY r.country_name;

    -- 4. Detalle de Participaciones y Resultados
    SELECT 
        ej.year AS anio_participacion,
        ej.games_name AS edicion_juegos,
        ej.city AS ciudad_sede,
        a.full_name AS nombre_atleta,
        d.sport AS deporte,
        d.event_name AS prueba_disciplina,
        p.equipo,
        res.place AS posicion_final,
        ISNULL(res.medal, 'Sin Medalla') AS medalla
    FROM dbo.region r
    INNER JOIN dbo.participacion p ON r.noc_code = p.noc_code
    INNER JOIN dbo.atleta a ON p.id_atleta = a.id
    INNER JOIN dbo.edicion_juego ej ON p.id_edicion = ej.id
    INNER JOIN dbo.disciplina d ON p.id_disciplina = d.id
    LEFT JOIN dbo.resultado res ON p.id = res.id_participacion
    WHERE (UPPER(r.noc_code) = UPPER(@pais) OR r.country_name LIKE '%' + @pais + '%')
      AND (@anio IS NULL OR ej.year = @anio)
      AND (@deporte IS NULL OR d.sport LIKE '%' + @deporte + '%')
    ORDER BY ej.year DESC, d.sport, a.full_name;
END;
GO

PRINT 'DDL y Stored Procedures creados exitosamente.';