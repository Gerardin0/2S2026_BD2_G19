/* ==========================================================================
   PROYECTO 2 - FASE 2 (Respaldo y Restauracion)
   GRUPO 19 - Pablo, Jose y Gerardo

   ddl/01_crear_base_datos.sql          <-- SCRIPT COMPARTIDO por los tres
   Crea la base de datos desde cero, con la collation UTF-8.

   POR QUE EL NOMBRE DE LA BASE ES UN PARAMETRO
   Cada integrante trabaja sobre SU PROPIA base de datos, porque las tres
   entregas se hacen sobre el mismo esquema:

       Pablo    ->  db_olimpiadas_anio        (carga por AÑO)
       Jose     ->  db_olimpiadas_deporte     (carga por DEPORTE)
       Gerardo  ->  db_olimpiadas_deportista  (carga por DEPORTISTA)

   Con bases separadas nadie pisa el DROP DATABASE, el TRUNCATE del staging
   ni los .bak del otro. El enunciado lo pide asi ademas: hay que "eliminar
   la base de datos completa" y medir tiempos POR TIPO DE CARGA.

   El parametro $(DbNombre) lo resuelve sqlcmd (sustitucion de variables).
   OBLIGATORIO pasar -v o el script falla:

     sqlcmd ... -v DbNombre=db_olimpiadas_anio        -i 01_crear_base_datos.sql
     sqlcmd ... -v DbNombre=db_olimpiadas_deporte     -i 01_crear_base_datos.sql
     sqlcmd ... -v DbNombre=db_olimpiadas_deportista  -i 01_crear_base_datos.sql
   ========================================================================== */

IF DB_ID('$(DbNombre)') IS NOT NULL
BEGIN
    PRINT 'La base $(DbNombre) ya existe. Se procede a recrearla.';
    -- El restore del enunciado exige "eliminar la base de datos completa",
    -- por eso aqui se deja siempre en estado limpio.
    ALTER DATABASE $(DbNombre) SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE $(DbNombre);
END;
GO

/* COLLATE UTF-8 a nivel de BASE DE DATOS.
   Sin esto, los caracteres multibyte de los CSV (acentos, la "z" con
   virgulilla de "Boltizar", el punto separador de "Usain St. Leo-Bolt")
   llegan corruptos a las tablas dbo.*.
   OJO: esto NO alcanza para arreglar el problema (ver la seccion 3 del
   README_deportista.md); BULK INSERT en Linux lee con CP437 y no admite
   CODEPAGE. Se deja igualmente porque es la configuracion correcta.
   No modifica el DDL de la Fase 1: solo la collation con la que se crean
   las tablas. */
CREATE DATABASE $(DbNombre)
    COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

/* Se repite el COLLATE como ALTER por si el motor lo hubiera dejado en la
   collation del servidor (MSSQL_COLLATION del contenedor). Es idempotente y
   evita el Msg 468 "Cannot resolve the collation conflict" mas adelante:
   las columnas de stg.* llevan la collation UTF-8 EXPLICITA y las de dbo.*
   heredan la de la base; si difieren, toda comparacion entre ambas falla. */
ALTER DATABASE $(DbNombre) COLLATE Latin1_General_100_CI_AS_SC_UTF8;
GO

/* DATABASEPROPERTYEX devuelve sql_variant: hay que convertirlo a NVARCHAR
   antes de concatenarlo con PRINT. */
DECLARE @coll_db NVARCHAR(128) =
    CONVERT(NVARCHAR(128), DATABASEPROPERTYEX('$(DbNombre)', 'Collation'));

IF @coll_db <> 'Latin1_General_100_CI_AS_SC_UTF8'
    PRINT 'AVISO: la collation de la base no es UTF-8. Las cargas fallaran con Msg 468.';
ELSE
    PRINT 'Collation de la base: ' + @coll_db;
GO

PRINT 'Base de datos $(DbNombre) creada.';
GO