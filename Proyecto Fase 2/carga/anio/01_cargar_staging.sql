USE db_olimpiadas_anio;
GO

PRINT '--- Cargando CSVs en stg ---';
GO

TRUNCATE TABLE stg.region;
GO
BULK INSERT stg.region
FROM '/var/opt/mssql/csv/tabla_nocs.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.poblacion;
GO
BULK INSERT stg.poblacion
FROM '/var/opt/mssql/csv/tabla_poblaciones.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.disciplina;
GO
BULK INSERT stg.disciplina
FROM '/var/opt/mssql/csv/tabla_disciplina.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.edicion_juego;
GO
BULK INSERT stg.edicion_juego
FROM '/var/opt/mssql/csv/tabla_edicion_juego.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.atleta;
GO
BULK INSERT stg.atleta
FROM '/var/opt/mssql/csv/tabla_atletas.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.rol;
GO
BULK INSERT stg.rol
FROM '/var/opt/mssql/csv/tabla_rol.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.atleta_rol;
GO
BULK INSERT stg.atleta_rol
FROM '/var/opt/mssql/csv/tabla_atleta_rol.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.participacion;
GO
BULK INSERT stg.participacion
FROM '/var/opt/mssql/csv/tabla_participacion.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

TRUNCATE TABLE stg.resultado;
GO
BULK INSERT stg.resultado
FROM '/var/opt/mssql/csv/tabla_resultado.csv'
WITH (FIELDTERMINATOR = ',', FIELDQUOTE = '"',
      FIRSTROW = 2, DATAFILETYPE = 'char');
GO

/* --------------------------------------------------------------------------
   Verificacion: si alguna tabla quedo vacia, el BULK INSERT fallo y hay que
   revisar la ruta del CSV antes de seguir con la carga.
   -------------------------------------------------------------------------- */
SELECT 'stg.region'        AS tabla_staging, COUNT(*) AS filas FROM stg.region
UNION ALL SELECT 'stg.poblacion',     COUNT(*) FROM stg.poblacion
UNION ALL SELECT 'stg.disciplina',    COUNT(*) FROM stg.disciplina
UNION ALL SELECT 'stg.edicion_juego', COUNT(*) FROM stg.edicion_juego
UNION ALL SELECT 'stg.atleta',        COUNT(*) FROM stg.atleta
UNION ALL SELECT 'stg.rol',           COUNT(*) FROM stg.rol
UNION ALL SELECT 'stg.atleta_rol',    COUNT(*) FROM stg.atleta_rol
UNION ALL SELECT 'stg.participacion', COUNT(*) FROM stg.participacion
UNION ALL SELECT 'stg.resultado',     COUNT(*) FROM stg.resultado
ORDER BY tabla_staging;
GO

PRINT '--- Staging cargado. ---';
GO