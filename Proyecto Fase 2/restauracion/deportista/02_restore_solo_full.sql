/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt)

   restauracion/02_restore_solo_full.sql
   RESTAURACION 1/4 - unicamente el backup completo.

   Estado que se espera recuperar: el de DESPUES de la carga 1 (Atenas 2004),
   es decir, ANTES de las cargas de Pekin 2008, Londres 2012 y Rio 2016.

   WITH RECOVERY deja la base utilizable (modo simple, sin cola de restore).
   Con WITH REPLACE se sobrescribe la base si por error ya existiera.

   El tiempo de restauracion se mide desde PowerShell con Get-Date, porque el
   enunciado pide tiempos y no solo el resultado. Ver:
     docs/medir_tiempos_restore.ps1

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -i 02_restore_solo_full.sql
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'RESTAURACION 1/4 - SOLO FULL (estado tras la carga 1)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

RESTORE DATABASE db_olimpiadas_deportista
    FROM DISK = '/var/opt/mssql/backups/full_deportista.bak'
    WITH RECOVERY, REPLACE, STATS = 10;
GO

/* --- Validacion: que lote se restauro y cuando --- */
SELECT
    bs.database_name,
    bs.backup_start_date,
    bs.backup_finish_date,
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_backup_s,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
         ELSE 'DIFERENCIAL' END AS tipo,
    bfm.physical_device_name AS archivo
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%deportista%'
ORDER BY bs.backup_finish_date;
GO

PRINT '--- Conteos restaurados (solo FULL) ---';
GO

USE db_olimpiadas_deportista;
GO

SELECT 'dbo.region'        AS tabla, COUNT(*) AS filas FROM dbo.region
UNION ALL SELECT 'dbo.edicion_juego', COUNT(*) FROM dbo.edicion_juego
UNION ALL SELECT 'dbo.disciplina',    COUNT(*) FROM dbo.disciplina
UNION ALL SELECT 'dbo.atleta',        COUNT(*) FROM dbo.atleta
UNION ALL SELECT 'dbo.roles',         COUNT(*) FROM dbo.roles
UNION ALL SELECT 'dbo.atleta_roles',  COUNT(*) FROM dbo.atleta_roles
UNION ALL SELECT 'dbo.participacion', COUNT(*) FROM dbo.participacion
UNION ALL SELECT 'dbo.resultado',     COUNT(*) FROM dbo.resultado
UNION ALL SELECT 'dbo.poblacion',     COUNT(*) FROM dbo.poblacion
ORDER BY tabla;
GO

PRINT 'Solo deben aparecer las participaciones de ATENAS 2004.';
GO

SELECT ej.[year] AS anio, ej.games_name AS edicion, d.sport, d.event_name,
       res.place AS posicion, res.medal
FROM dbo.participacion p
INNER JOIN dbo.edicion_juego ej ON ej.id = p.id_edicion
INNER JOIN dbo.disciplina    d  ON d.id  = p.id_disciplina
INNER JOIN dbo.atleta        a  ON a.id  = p.id_atleta
LEFT JOIN dbo.resultado     res ON res.id_participacion = p.id
WHERE a.full_name LIKE '%Usain Bolt%'
ORDER BY ej.[year], d.event_name;
GO

PRINT 'Restauracion 1/4 completada.';
GO