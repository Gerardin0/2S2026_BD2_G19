/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt)

   carga/deportista/01_cargar_staging.sql
   Carga los 9 CSV crudos de CSVs/ en el esquema stg.

   RUTA DE LOS CSV DENTRO DEL CONTENEDOR:
   Los CSV deben estar montados en el contenedor antes de correr este script:
     docker run -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD='Password123!' \
       -p 1433:1433 --name sqlserver_olimpiadas \
       -v /ruta/host/ProyectoFase2/CSVs:/var/opt/mssql/csv:ro \
       -v /ruta/host/backups:/var/opt/mssql/backups \
       -d mcr.microsoft.com/mssql/server:2022-latest

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -d db_olimpiadas_deportista \
            -i 01_cargar_staging.sql
   ========================================================================== */

USE db_olimpiadas_deportista;
GO

/* Los CSV traen cabecera; FIRSTROW = 2 la omite.                  */
/* FIELDQUOTE = '"' porque los CSV usan comillas dobles.            */
/* NO se usa CODEPAGE: esa opcion no esta soportada en Linux        */
/* (error 16202). En el contenedor de SQL Server el default ya es  */
/* UTF-8, necesario por los acentos y caracteres especiales de los  */
/* nombres (St. Leo, Boltizar, etc.).                               */

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
   revisar la ruta del CSV antes de seguir con la carga de Gerardo.
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

PRINT '--- Staging cargado. Continuar con 02_proc_cargar_deportista.sql ---';
GO