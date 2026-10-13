/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Pablo - Carga por AÑO

   restauracion/anio/01_eliminar_base.sql
   Elimina la base de datos completa, tal como pide el enunciado.

   IMPORTANTE: este script se ejecuta desde master y sobre un contenedor
   donde el volumen /var/opt/mssql/backups esta montado por fuera. Borrar la
   base NO borra los .bak, demostrando que los respaldos sobreviven a la
   eliminacion de la base de datos.

   Antes de eliminar se imprimen los conteos definitivos, que despues se
   comparan contra los obtenidos tras cada restauracion para validar que la
   restauracion fue integra.
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'ELIMINACION DE LA BASE DE DATOS (db_olimpiadas_anio)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

/* --- Conteos finales antes de borrar (referencia de validacion) --- */
IF DB_ID('db_olimpiadas_anio') IS NOT NULL
BEGIN
    SELECT 'dbo.region'        AS tabla, COUNT(*) AS filas FROM db_olimpiadas_anio.dbo.region
    UNION ALL SELECT 'dbo.edicion_juego', COUNT(*) FROM db_olimpiadas_anio.dbo.edicion_juego
    UNION ALL SELECT 'dbo.disciplina',    COUNT(*) FROM db_olimpiadas_anio.dbo.disciplina
    UNION ALL SELECT 'dbo.atleta',        COUNT(*) FROM db_olimpiadas_anio.dbo.atleta
    UNION ALL SELECT 'dbo.roles',         COUNT(*) FROM db_olimpiadas_anio.dbo.roles
    UNION ALL SELECT 'dbo.atleta_roles',  COUNT(*) FROM db_olimpiadas_anio.dbo.atleta_roles
    UNION ALL SELECT 'dbo.participacion', COUNT(*) FROM db_olimpiadas_anio.dbo.participacion
    UNION ALL SELECT 'dbo.resultado',     COUNT(*) FROM db_olimpiadas_anio.dbo.resultado
    UNION ALL SELECT 'dbo.poblacion',     COUNT(*) FROM db_olimpiadas_anio.dbo.poblacion
    ORDER BY tabla;
END
GO

/* --- Listado de los respaldos que sobreviven a la eliminacion --- */
PRINT 'Respaldos disponibles en el volumen externo:';
GO
SELECT
    CAST(bs.database_name AS VARCHAR(22)) AS database_name,
    CAST(CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
              ELSE 'DIFERENCIAL' END AS VARCHAR(12)) AS tipo,
    CAST(bs.backup_size / 1048576.0 AS DECIMAL(10, 2)) AS tamano_mb,
    CAST(bfm.physical_device_name AS VARCHAR(42)) AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date, 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bs.database_name = 'db_olimpiadas_anio'
ORDER BY bs.backup_finish_date;
GO

/* --- Eliminacion --- */
IF DB_ID('db_olimpiadas_anio') IS NOT NULL
BEGIN
    ALTER DATABASE db_olimpiadas_anio SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE db_olimpiadas_anio;
END
GO

/* --- Confirmacion --- */
IF DB_ID('db_olimpiadas_anio') IS NULL
    PRINT 'Base de datos db_olimpiadas_anio eliminada correctamente.';
ELSE
    PRINT 'ERROR: la base de datos sigue existiendo.';
GO

PRINT 'Verificar que los .bak siguen en /var/opt/mssql/backups:';
PRINT '  docker exec -it sqlserver_olimpiadas ls -lh /var/opt/mssql/backups';
GO