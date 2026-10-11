/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)

   02_esquema_staging.sql
   Crea el esquema stg con una tabla por cada CSV de CSVs/.

   POR QUE EXISTE EL STAGING:
   Los CSV de la Fase 2 (heredados del pipeline de la Fase 1) NO tienen los
   mismos nombres de columna que el modelo relacional final dbo.*, y dos campos
   del modelo final son NOT NULL pero no tienen columna equivalente en el CSV:

     - dbo.region.country_name        <- el CSV tabla_nocs.csv solo trae NOC,
                                         region, notes
     - dbo.edicion_juego.games_name   <- el CSV tabla_edicion_juego.csv solo
                                         trae id, year, season, city

   SCRIPT COMPARTIDO por los tres: hay que pasar el nombre de la base.
   Ver ddl/01_crear_base_datos.sql para la convencion de nombres.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -v DbNombre=<SU_BASE> \
            -i 02_esquema_staging.sql
   ========================================================================== */

USE $(DbNombre);
GO

/* --------------------------------------------------------------------------
   Limpieza previa: permite re-ejecutar el script sin errores.
   Se usa DROP TABLE y no TRUNCATE porque TRUNCATE falla sobre tablas con FK.
   -------------------------------------------------------------------------- */
IF OBJECT_ID('stg.atleta_rol',      'U') IS NOT NULL DROP TABLE stg.atleta_rol;
IF OBJECT_ID('stg.resultado',       'U') IS NOT NULL DROP TABLE stg.resultado;
IF OBJECT_ID('stg.participacion',   'U') IS NOT NULL DROP TABLE stg.participacion;
IF OBJECT_ID('stg.rol',             'U') IS NOT NULL DROP TABLE stg.rol;
IF OBJECT_ID('stg.atleta',          'U') IS NOT NULL DROP TABLE stg.atleta;
IF OBJECT_ID('stg.poblacion',       'U') IS NOT NULL DROP TABLE stg.poblacion;
IF OBJECT_ID('stg.disciplina',      'U') IS NOT NULL DROP TABLE stg.disciplina;
IF OBJECT_ID('stg.edicion_juego',   'U') IS NOT NULL DROP TABLE stg.edicion_juego;
IF OBJECT_ID('stg.region',          'U') IS NOT NULL DROP TABLE stg.region;
IF OBJECT_ID('stg.unificado',       'U') IS NOT NULL DROP TABLE stg.unificado;
GO

IF SCHEMA_ID('stg') IS NULL
    EXEC('CREATE SCHEMA stg;');
GO

/* ==========================================================================
   1. stg.region  <-  CSVs/tabla_nocs.csv
   ========================================================================== */
CREATE TABLE stg.region (
    NOC        NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,   -- -> dbo.region.noc_code
    region     NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,   -- -> dbo.region.region
    notes      NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL    -- -> dbo.region.notas
);
GO

/* ==========================================================================
   2. stg.poblacion  <-  CSVs/tabla_poblaciones.csv
   ========================================================================== */
CREATE TABLE stg.poblacion (
    noc_code   NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,   -- -> dbo.poblacion.noc_code
    [year]     NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,   -- -> dbo.poblacion.anio
    population NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL    -- -> dbo.poblacion.poblacion
);
GO

/* ==========================================================================
   3. stg.disciplina  <-  CSVs/tabla_disciplina.csv
   Nota: los ids se conservan con SET IDENTITY_INSERT para que
   tabla_participacion.id_disciplina siga apuntando al mismo evento.
   ========================================================================== */
CREATE TABLE stg.disciplina (
    id_disciplina NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.disciplina.id  (IDENTITY INSERT)
    sport         NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.disciplina.sport
    event_name    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.disciplina.event_name
);
GO

/* ==========================================================================
   4. stg.edicion_juego  <-  CSVs/tabla_edicion_juego.csv
   games_name NO existe en el CSV: se deriva en la carga como
   CONCAT(year, ' ', season) para respetar el NOT NULL del modelo final.
   ========================================================================== */
CREATE TABLE stg.edicion_juego (
    id_edicion_juego NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.edicion_juego.id (IDENTITY INSERT)
    [year]           NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.edicion_juego.[year]
    season           NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.edicion_juego.season
    city             NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.edicion_juego.city
);
GO

/* ==========================================================================
   5. stg.atleta  <-  CSVs/tabla_atletas.csv
   Los nombres de columna del CSV llevan espacios y parentesis ("Full name",
   "Title(s)", "Nick/petnames"), por eso van entre corchetes.
   ========================================================================== */
CREATE TABLE stg.atleta (
    athlete_id     NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.id (IDENTITY INSERT)
    [Sex]          NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.sex
    [Full name]    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.used_name
    died_in        NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.died_place
    Affiliations   NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.afiliaciones
    [Nick/petnames] NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL, -- -> dbo.atleta.apodos
    [Title(s)]     NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.titulos
    [Other names]  NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.otros_nombres
    Nationality    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.nacionalidad
    [Original name] NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL, -- -> dbo.atleta.nombre_original
    [Name order]   NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.orden_nombre
    name           NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.full_name
    born_date      NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.born_date
    born_city      NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.born_city
    born_region    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.born_region
    born_country   NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.born_country
    died_date      NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.died_date
    lat            NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.latitud
    [long]         NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta.longitud
    rol_id         NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- no se carga: la relacion
                                        -- atleta/rol va en stg.atleta_rol
);
GO

/* ==========================================================================
   6. stg.rol  <-  CSVs/tabla_rol.csv
   ========================================================================== */
CREATE TABLE stg.rol (
    rol_id     NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.roles.id (IDENTITY INSERT)
    nombre_rol NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.roles.nombre
);
GO

/* ==========================================================================
   7. stg.atleta_rol  <-  CSVs/tabla_atleta_rol.csv
   El id_atleta_rol del CSV es un correlativo sin uso: la PK compuesta del
   modelo final es (id_atleta, id_rol), asi que se descarta.
   ========================================================================== */
CREATE TABLE stg.atleta_rol (
    id_atleta_rol NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- se descarta
    athlete_id    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.atleta_roles.id_atleta
    rol_id        NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.atleta_roles.id_rol
);
GO

/* ==========================================================================
   8. stg.participacion  <-  CSVs/tabla_participacion.csv
   IMPORTANTE: athlete_id viene en el CSV como decimal ("105512.0").
   El casteo a INT se hace en la carga.
   ========================================================================== */
CREATE TABLE stg.participacion (
    id_participacion NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.id (IDENTITY INSERT)
    athlete_id       NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.id_atleta
    id_edicion_juego NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.id_edicion
    id_disciplina    NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.id_disciplina
    noc_code         NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.noc_code
    team             NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.equipo
    presentado_como  NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.presentado_como
    age              NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.age
    height_cm        NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.participacion.height_cm
    weight_kg        NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.participacion.weight_kg
);
GO

/* ==========================================================================
   9. stg.resultado  <-  CSVs/tabla_resultado.csv
   id_resultado es un correlativo que el modelo final no usa (la PK es
   id_participacion, con UNIQUE), por eso se descarta en la carga.
   ========================================================================== */
CREATE TABLE stg.resultado (
    id_resultado      NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- se descarta
    id_participacion  NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.resultado.id_participacion
    place             NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.resultado.place
    tied              NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL,  -- -> dbo.resultado.tied
    medal             NVARCHAR(MAX) COLLATE Latin1_General_100_CI_AS_SC_UTF8 NULL   -- -> dbo.resultado.medal
);
GO

PRINT 'Esquema stg creado con 9 tablas de staging.';
GO