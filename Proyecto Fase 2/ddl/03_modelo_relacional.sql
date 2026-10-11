/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)

   03_modelo_relacional.sql

   SCRIPT COMPARTIDO por los tres: hay que pasar el nombre de la base.
   Ver ddl/01_crear_base_datos.sql para la convencion de nombres.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -v DbNombre=<SU_BASE> \
            -i 03_modelo_relacional.sql
   ========================================================================== */

USE $(DbNombre);
GO

/* --------------------------------------------------------------------------
   Limpieza previa del modelo final.
   Orden inverso al de las dependencias para que los DROP de FK no fallen.
   -------------------------------------------------------------------------- */
IF OBJECT_ID('dbo.resultado',      'U') IS NOT NULL DROP TABLE dbo.resultado;
IF OBJECT_ID('dbo.atleta_roles',   'U') IS NOT NULL DROP TABLE dbo.atleta_roles;
IF OBJECT_ID('dbo.participacion',  'U') IS NOT NULL DROP TABLE dbo.participacion;
IF OBJECT_ID('dbo.roles',          'U') IS NOT NULL DROP TABLE dbo.roles;
IF OBJECT_ID('dbo.atleta',         'U') IS NOT NULL DROP TABLE dbo.atleta;
IF OBJECT_ID('dbo.disciplina',     'U') IS NOT NULL DROP TABLE dbo.disciplina;
IF OBJECT_ID('dbo.edicion_juego',  'U') IS NOT NULL DROP TABLE dbo.edicion_juego;
IF OBJECT_ID('dbo.poblacion',      'U') IS NOT NULL DROP TABLE dbo.poblacion;
GO

/* ==========================================================================
   MODELO RELACIONAL FINAL (identico al de la Fase 1)
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
    nacionalidad        NVARCHAR(200) NULL,
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
   INDICES (identicos a los de la Fase 1)
   Estos indices son los que se van a medir con
   sys.dm_db_index_physical_stats despues de cada carga.
   ========================================================================== */
CREATE NONCLUSTERED INDEX ix_atleta_names         ON dbo.atleta(full_name, used_name);
CREATE NONCLUSTERED INDEX ix_participacion_busqueda ON dbo.participacion(id_atleta, id_edicion, id_disciplina);
CREATE NONCLUSTERED INDEX ix_participacion_noc     ON dbo.participacion(noc_code);
CREATE NONCLUSTERED INDEX ix_edicion_noc          ON dbo.edicion_juego(noc_code);
CREATE NONCLUSTERED INDEX ix_edicion_year         ON dbo.edicion_juego([year]);
CREATE NONCLUSTERED INDEX ix_resultado_medal       ON dbo.resultado(medal);
GO

PRINT 'Modelo relacional dbo.* creado (identico al DDL de la Fase 1).';
GO