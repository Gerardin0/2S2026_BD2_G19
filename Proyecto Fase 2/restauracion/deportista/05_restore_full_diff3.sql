/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   Gerardo - Carga por DEPORTISTA (Usain Bolt)

   restauracion/05_restore_full_diff3.sql
   RESTAURACION 4/4 - backup completo + DIFERENCIAL 3.

   Estado que se espera recuperar: el de DESPUES de la carga 4 (Rio 2016),
   es decir, con las ediciones Atenas 2004, Pekin 2008 y Londres 2012 ya cargadas.

   SECUENCIA OBLIGATORIA DE UNA RESTAURACION DIFERENCIAL:
     1. RESTORE del FULL con WITH NORECOVERY  -> deja la base "en espera",
        todavia no consultable.
     2. RESTORE del DIFERENCIAL con WITH RECOVERY -> aplica las paginas
        cambiadas desde el ultimo FULL y cierra la base.
   Si el FULL se restaura con WITH RECOVERY, la base queda online y el
   diferencial ya no se puede aplicar: por eso NORECOVERY en el paso 1.

   El diferencial 3 es ACUMULATIVO: contiene todo lo modificado desde el
   ultimo FULL. No hace falta restaurar diff_deportista_1..2,
   y por eso el tiempo de esta restauracion crece solo con el volumen de la
   edicion 2016, no con el numero de diferenciales previos.

   El tiempo de restauracion se mide desde PowerShell con Get-Date, porque el
   enunciado pide tiempos y no solo el resultado. Ver:
     docs/medir_tiempos_restore.ps1

   Ejecutar por consola:
     sqlcmd -S localhost,1433 -U sa -P 'Password123!' -i 05_restore_full_diff3.sql
   ========================================================================== */

USE master;
GO

PRINT '===============================================================';
PRINT 'RESTAURACION 4/4 - FULL + DIFERENCIAL 3 (estado tras la carga 4)';
PRINT 'Ejecutado: ' + CONVERT(VARCHAR(20), SYSDATETIME() AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120);
PRINT '===============================================================';
GO

/* Paso 1: el FULL se deja en NORECOVERY para poder encadenar el diferencial. */
RESTORE DATABASE db_olimpiadas_deportista
    FROM DISK = '/var/opt/mssql/backups/full_deportista.bak'
    WITH NORECOVERY, REPLACE, STATS = 10;
GO

/* Paso 2: el diferencial cierra la restauracion y deja la base online. */
RESTORE DATABASE db_olimpiadas_deportista
    FROM DISK = '/var/opt/mssql/backups/diff_deportista_3.bak'
    WITH RECOVERY, STATS = 10;
GO

/* --- Validacion: que lote se restauro y cuando --- */
SELECT
    bs.database_name,
    CONVERT(VARCHAR(20), bs.backup_start_date AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120),
    CONVERT(VARCHAR(20), bs.backup_finish_date AT TIME ZONE 'UTC' AT TIME ZONE 'Central America Standard Time', 120),
    DATEDIFF(SECOND, bs.backup_start_date, bs.backup_finish_date) AS duracion_backup_s,
    CASE WHEN bs.differential_base_lsn IS NULL THEN 'FULL'
         ELSE 'DIFERENCIAL' END AS tipo,
    bfm.physical_device_name AS archivo
FROM msdb.dbo.backupmediafamily bfm
INNER JOIN msdb.dbo.backupset bs ON bs.media_set_id = bfm.media_set_id
WHERE bfm.physical_device_name LIKE '%deportista%'
ORDER BY bs.backup_finish_date;
GO

PRINT '--- Conteos restaurados (FULL + DIFERENCIAL 3) ---';
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

PRINT 'Deben aparecer las participaciones hasta Rio 2016 inclusive.';
GO

/* Se filtra por athlete_id (105512 = Usain Bolt) y no por LIKE '%Usain Bolt%':
   el nombre viene del CSV como "Usain St. Leo<BULLET>Bolt" y el caracter
   multibyte queda corrupto por el tema de codificacion (ver README seccion 3),
   asi que el LIKE sobre el nombre no encuentra nada. El id no depende de la
   codificacion. */
SELECT ej.[year] AS anio, ej.games_name AS edicion, d.sport, d.event_name,
       res.place AS posicion, res.medal
FROM dbo.participacion p
INNER JOIN dbo.edicion_juego ej ON ej.id = p.id_edicion
INNER JOIN dbo.disciplina    d  ON d.id  = p.id_disciplina
INNER JOIN dbo.atleta        a  ON a.id  = p.id_atleta
LEFT JOIN dbo.resultado     res ON res.id_participacion = p.id
WHERE a.source_athlete_id = 105512
ORDER BY ej.[year], d.event_name;
GO

PRINT 'Restauracion 4/4 completada.';
GO