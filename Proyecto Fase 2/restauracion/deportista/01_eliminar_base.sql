/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)

   restauracion/01_eliminar_base.sql
   Elimina la base de datos completa, tal como pide el enunciado.

   IMPORTANTE: este script se ejecuta sin especificar base de datos con -d, y
   sobre un contenedor donde el volumen /var/opt/mssql/backups esta montado
   por fuera. Borrar la base NO borra los .bak, que es justamente lo que hay
   que demostrar: los respaldos sobreviven a la eliminacion del motor.

   Antes de eliminar se imprimen los conteos definitivos, que despues se
   comparan contra los obtenidos tras cada restauracion para validar que la
   restauracion fue integra.

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -i 01_eliminar_base.sql
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'ELIMINACION DE LA BASE DE DATOS';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120);
PRINT '===============================================================';
GO

/* --- Conteos finales antes de borrar (referencia de validacion) --- */
SELECT
    'dbo.region'        AS tabla, COUNT(*) AS filas FROM db_olimpiadas_deportista.dbo.region
UNION ALL SELECT 'dbo.edicion_juego', COUNT(*) FROM db_olimpiadas_deportista.dbo.edicion_juego
UNION ALL SELECT 'dbo.disciplina',    COUNT(*) FROM db_olimpiadas_deportista.dbo.disciplina
UNION ALL SELECT 'dbo.atleta',        COUNT(*) FROM db_olimpiadas_deportista.dbo.atleta
UNION ALL SELECT 'dbo.roles',         COUNT(*) FROM db_olimpiadas_deportista.dbo.roles
UNION ALL SELECT 'dbo.atleta_roles',  COUNT(*) FROM db_olimpiadas_deportista.dbo.atleta_roles
UNION ALL SELECT 'dbo.participacion', COUNT(*) FROM db_olimpiadas_deportista.dbo.participacion
UNION ALL SELECT 'dbo.resultado',     COUNT(*) FROM db_olimpiadas_deportista.dbo.resultado
UNION ALL SELECT 'dbo.poblacion',     COUNT(*) FROM db_olimpiadas_deportista.dbo.poblacion
ORDER BY tabla;
GO

/* --- Listado de los respaldos que sobreviven a la eliminacion ---
   El tamano NO esta en msdb.dbo.backupset: hay que unirlo con
   msdb.dbo.backupmediafamily, que es quien tiene el archivo y su tamano. */
PRINT 'Respaldos disponibles en el volumen externo:';
GO
SELECT
    bs.database_name,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
         ELSE 'DIFERENCIAL' END AS tipo,
    bfm.physical_device_name AS archivo,
    CONVERT(VARCHAR(20), bs.backup_finish_date AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120) AS finalizado
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bs.database_name = 'db_olimpiadas_deportista'
ORDER BY bs.backup_finish_date;
GO

/* --- Eliminacion --- */
ALTER DATABASE db_olimpiadas_deportista SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO
DROP DATABASE db_olimpiadas_deportista;
GO

/* --- Confirmacion --- */
IF DB_ID('db_olimpiadas_deportista') IS NULL
    PRINT 'Base de datos db_olimpiadas_deportista eliminada correctamente.';
ELSE
    PRINT 'ERROR: la base de datos sigue existiendo.';
GO

/* Los .bak siguen en disco: se comprueba desde el shell del contenedor. */
PRINT 'Verificar que los .bak siguen en /var/opt/mssql/backups:';
PRINT '  docker exec -it sqlserver_olimpiadas ls -lh /var/opt/mssql/backups';
GO