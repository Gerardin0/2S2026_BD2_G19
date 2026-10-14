/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Jose - Carga por DEPORTE (100 m planos femeninos)

   restauracion/03_restore_full_diff1.sql
   RESTAURACION 2/4 - backup completo + DIFERENCIAL 1.

   Estado que se espera recuperar: el de DESPUES de la carga 2 (Tokio 2020),
   es decir, con las ediciones Paris 2024 ya cargadas.

   SECUENCIA OBLIGATORIA DE UNA RESTAURACION DIFERENCIAL:
     1. RESTORE del FULL con WITH NORECOVERY  -> deja la base "en espera",
        todavia no consultable.
     2. RESTORE del DIFERENCIAL con WITH RECOVERY -> aplica las paginas
        cambiadas desde el ultimo FULL y cierra la base.
   Si el FULL se restaura con WITH RECOVERY, la base queda online y el
   diferencial ya no se puede aplicar: por eso NORECOVERY en el paso 1.

   El diferencial 1 es ACUMULATIVO: contiene todo lo modificado desde el
   ultimo FULL. No hace falta restaurar diff_deporte_1..0,
   y por eso el tiempo de esta restauracion crece solo con el volumen de la
   edicion 2020, no con el numero de diferenciales previos.

   El tiempo de restauracion se mide desde PowerShell con Get-Date, porque el
   enunciado pide tiempos y no solo el resultado. Ver:
     docs/medir_tiempos_restore.ps1

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -i 03_restore_full_diff1.sql
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'RESTAURACION 2/4 - FULL + DIFERENCIAL 1 (estado tras la carga 2)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME(), 120);
PRINT '===============================================================';
GO

/* Paso 1: el FULL se deja en NORECOVERY para poder encadenar el diferencial. */
RESTORE DATABASE db_olimpiadas_deporte
    FROM DISK = '/var/opt/mssql/backups/full_deporte.bak'
    WITH NORECOVERY, REPLACE, STATS = 10;
GO

/* Paso 2: el diferencial cierra la restauracion y deja la base online. */
RESTORE DATABASE db_olimpiadas_deporte
    FROM DISK = '/var/opt/mssql/backups/diff_deporte_1.bak'
    WITH RECOVERY, STATS = 10;
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
WHERE bfm.physical_device_name LIKE '%deporte%'
ORDER BY bs.backup_finish_date;
GO

PRINT '--- Conteos restaurados (FULL + DIFERENCIAL 1) ---';
GO

USE db_olimpiadas_deporte;
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

PRINT 'Debe aparecer el podio de cada edicion hasta Tokio 2020 inclusive.';
GO

SELECT ej.[year] AS anio, ej.games_name AS edicion, d.sport, d.event_name,
       res.place AS posicion, res.medal
FROM dbo.participacion p
INNER JOIN dbo.edicion_juego ej ON ej.id = p.id_edicion
INNER JOIN dbo.disciplina    d  ON d.id  = p.id_disciplina
INNER JOIN dbo.atleta        a  ON a.id  = p.id_atleta
LEFT JOIN dbo.resultado     res ON res.id_participacion = p.id
WHERE d.id = 237 AND res.medal IS NOT NULL
ORDER BY ej.[year], res.place;
GO

PRINT 'Restauracion 2/4 completada.';
GO