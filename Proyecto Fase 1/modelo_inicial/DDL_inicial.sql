CREATE DATABASE db_olimpiadas;
GO

USE db_olimpiadas;
GO

-- Paises / regiones
CREATE TABLE region (
    noc_code NVARCHAR(10) NOT NULL PRIMARY KEY,
    country_name NVARCHAR(200) NOT NULL,
    region NVARCHAR(200) NULL
);
GO

-- Ediciones olimpicas
CREATE TABLE edicion_juego (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    year INT NULL,
    season NVARCHAR(20) NULL,
    games_name NVARCHAR(200) NOT NULL,
    city NVARCHAR(200) NOT NULL,
    noc_code NVARCHAR(10) NULL,
    CONSTRAINT fk_edicion_region FOREIGN KEY (noc_code) REFERENCES region(noc_code)
);
GO

-- Disciplinas y eventos
CREATE TABLE disciplina (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    sport NVARCHAR(200) NOT NULL,
    event_name NVARCHAR(300) NOT NULL,
    CONSTRAINT uq_disciplina_evento UNIQUE (sport, event_name)
);
GO

-- Atletas
CREATE TABLE atleta (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    source_athlete_id INT NULL,
    full_name NVARCHAR(300) NOT NULL,
    sex NVARCHAR(10) NULL,
    born_date DATE NULL,
    born_city NVARCHAR(200) NULL,
    born_region NVARCHAR(200) NULL,
    born_country NVARCHAR(200) NULL,
    height_cm DECIMAL(5,2) NULL,
    weight_kg DECIMAL(5,2) NULL,
    died_date DATE NULL,
    noc_code NVARCHAR(10) NULL,
    CONSTRAINT fk_atleta_region FOREIGN KEY (noc_code) REFERENCES region(noc_code)
);
GO

-- Participacion
CREATE TABLE participacion (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_atleta INT NOT NULL,
    id_edicion INT NOT NULL,
    id_disciplina INT NOT NULL,
    noc_code NVARCHAR(10) NULL,
    team_name NVARCHAR(200) NULL,
    age INT NULL,
    CONSTRAINT fk_part_atleta FOREIGN KEY (id_atleta) REFERENCES atleta(id),
    CONSTRAINT fk_part_edicion FOREIGN KEY (id_edicion) REFERENCES edicion_juego(id),
    CONSTRAINT fk_part_disciplina FOREIGN KEY (id_disciplina) REFERENCES disciplina(id),
    CONSTRAINT fk_part_region FOREIGN KEY (noc_code) REFERENCES region(noc_code)
);
GO

-- Resultados
CREATE TABLE resultado (
    id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    id_participacion INT NOT NULL,
    place INT NULL,
    tied BIT DEFAULT 0,
    medal NVARCHAR(20) NOT NULL DEFAULT 'No medal',
    CONSTRAINT fk_resultado_participacion FOREIGN KEY (id_participacion) REFERENCES participacion(id),
    CONSTRAINT uq_resultado_participacion UNIQUE (id_participacion)
);
GO


-- Para desconocidos
INSERT INTO region (noc_code, country_name, region)
VALUES ('UNK', 'Unknown Country', 'Unknown');
GO