/* =========================================================================
   PROYECTO OCN - DIAGNOSTICO Y OPTIMIZACION DE CONSULTAS CRITICAS
   Bases de Datos Avanzadas - Unidad II
   Entrega 1: Script de preparacion y optimizacion  (VERSION DETALLADA)

   MAPEO RESPECTO AL ENUNCIADO (los nombres reales de la base difieren):
       RegistrosOCN  -> OCN.deteccion
       Zonas         -> OCN.zona
       Problematicas -> OCN.problematica

   COMO USAR ESTE SCRIPT
     1. Ejecuta los bloques EN ORDEN, de uno en uno (seleccionar + F5).
     2. Activa "Incluir plan de ejecucion real" (Ctrl+M) ANTES de cada
        bloque de medicion y captura el plan (Entrega 2).
     3. Todas las mediciones se hacen en la misma sesion, con cache fria
        (CHECKPOINT + DBCC DROPCLEANBUFFERS). Solo usar en entorno de
        desarrollo, nunca en produccion.
     4. Los datos sinteticos se marcan con descripcion_anonima = 'SINTETICO'
        para poder borrarlos al final (BLOQUE 9).

   INDICES PROPUESTOS (3 consultas, 3 patrones de acceso)
     Q1  Igualdad exacta + orden  -> nonclustered compuesto y cubriente
     Q2  Filtro sobre subconjunto -> nonclustered FILTRADO
     Q3  Valor derivado           -> nonclustered sobre COLUMNA CALCULADA

   NOTA SOBRE LAS DOS VERSIONES DEL SCRIPT
     El codigo SQL de este archivo y el de la version corta es el mismo;
     solo cambian los comentarios. Esta version explica cada funcion y cada
     decision con detalle, para estudiar el script.
   ========================================================================= */

USE OCN_DB;
GO

/* Opciones de sesion.
   SET NOCOUNT ON : evita el mensaje "(N rows affected)" despues de cada
                    instruccion; deja la salida mas limpia.
   Las demas son las opciones que SQL Server EXIGE tener activadas para poder
   crear o usar indices filtrados y columnas calculadas con indice. Si alguna
   estuviera apagada, el CREATE INDEX o el INSERT fallaria con un error del
   tipo "SET options have incorrect settings". SSMS ya las trae encendidas,
   pero se declaran aqui para que el script funcione desde cualquier cliente
   (sqlcmd, Azure Data Studio, etc.). */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO


/* =========================================================================
   BLOQUE 0. REINICIO (permite re-ejecutar el script desde cero)
   Quita los indices y la columna calculada propuestos en este trabajo.
   ========================================================================= */

-- DROP INDEX IF EXISTS: borra el indice solo si existe; si no existe no
-- marca error (sin el IF EXISTS fallaria la primera vez que se corre).
DROP INDEX IF EXISTS IX_deteccion_lev_fecha     ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_alta_fecha    ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_anio_mes      ON OCN.deteccion;
DROP INDEX IF EXISTS IX_tmp_intensidad_fecha    ON OCN.deteccion;
DROP INDEX IF EXISTS IX_tmp_fecha_registro      ON OCN.deteccion;

-- COL_LENGTH(tabla, columna): devuelve el tamano en bytes de la columna, o
-- NULL si la columna no existe. Se usa como "existe la columna?" antes de
-- borrarla. Los indices que dependen de la columna ya se borraron arriba;
-- SQL Server no deja borrar una columna que tenga un indice encima.
IF COL_LENGTH('OCN.deteccion', 'anio_mes') IS NOT NULL
    ALTER TABLE OCN.deteccion DROP COLUMN anio_mes;
GO


/* =========================================================================
   BLOQUE 1. GENERACION MASIVA DE DATOS (>= 50,000 filas en OCN.deteccion)

   Metodo (set-based, sin cursores ni WHILE: una sola instruccion inserta
   todas las filas, que es muchisimo mas rapido):
     - 18 problematicas y 200 levantamientos sinteticos (para tener
       cardinalidad en las llaves foraneas; con 2 problematicas y 3
       levantamientos un indice no seria selectivo).
     - 100,000 detecciones. Una tabla de numeros (CROSS JOIN de
       sys.all_objects) + CHECKSUM(NEWID()) da valores aleatorios distintos
       por fila, guardados primero en una tabla temporal (#rnd).
     - Distribucion SESGADA a proposito, para que el histograma tenga
       algo que mostrar:
         * intensidad : 3% 'alta', 37% 'media', 60% 'baja'
         * levantamiento: 15% de las filas en un solo levantamiento
                          ("caliente"); el resto repartido parejo.
         * fecha_registro: aleatoria entre 2023-01-01 y ~2026-10.
   Idempotente: si ya existen filas SINTETICO, no vuelve a generar.
   ========================================================================= */

-- Cuenta cuantas detecciones sinteticas hay ya. Se guarda en una variable
-- para decidir abajo si se genera o no (evita duplicar 100,000 filas al
-- volver a ejecutar el script).
DECLARE @existentes INT =
    (SELECT COUNT(*) FROM OCN.deteccion WHERE descripcion_anonima = 'SINTETICO');

IF @existentes = 0
BEGIN
    -- Si una corrida anterior se interrumpio, pudieron quedar levantamientos
    -- y problematicas sinteticas sin detecciones. Se borran para empezar
    -- limpio (no hay detecciones que las referencien, asi que no hay
    -- conflicto con las llaves foraneas).
    DELETE FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO';
    DELETE FROM OCN.problematica  WHERE descripcion_problematica  = 'SINTETICO';

    -- 1.1 Problematicas sinteticas
    -- ";WITH": el punto y coma anterior es obligatorio porque WITH (CTE) debe
    -- ser la primera instruccion de su lote.
    -- CTE "n" = una tabla de numeros 1..18 construida al vuelo:
    --   ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) numera las filas 1,2,3...
    --   Se pide ORDER BY porque la funcion lo exige, pero (SELECT NULL) es un
    --   orden "falso": no nos importa el orden, solo la numeracion.
    --   TOP (18) corta a 18 filas; sys.all_objects solo es una tabla que
    --   siempre tiene muchas filas disponibles.
    ;WITH n AS (
        SELECT TOP (18) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO OCN.problematica (nombre_problematica, categoria, nivel_prioridad, descripcion_problematica)
    -- CONCAT(a, b): une textos; a diferencia de a + b, convierte numeros a
    --   texto solo y trata NULL como cadena vacia.
    -- CHOOSE(indice, v1, v2, v3): devuelve el valor numero "indice" (empieza
    --   en 1). n % 3 es el RESIDUO de dividir entre 3 (0,1,2); se le suma 1
    --   para que quede 1,2,3 y asi reparte las categorias de forma ciclica.
    SELECT CONCAT('Problematica sintetica ', n),
           CHOOSE(n % 3 + 1, 'Infraestructura', 'Salubridad', 'Seguridad'),
           CHOOSE(n % 3 + 1, 'Alta', 'Media', 'Baja'),
           'SINTETICO'
    FROM n;

    -- 1.2 Levantamientos sinteticos (repartidos entre las zonas existentes)
    -- Se numeran las zonas existentes 0..tot-1 en una tabla temporal (#zona)
    -- para poder asignarlas por turnos sin depender de que sus ids sean
    -- consecutivos.
    --   ROW_NUMBER() - 1       : numeracion que empieza en 0.
    --   COUNT(*) OVER ()       : funcion de ventana; pone en CADA fila el
    --                            total de filas de la tabla (sin agrupar).
    --   SELECT ... INTO #zona  : crea la tabla temporal #zona con el resultado
    --                            (el # la hace temporal; desaparece al cerrar
    --                            la sesion o con DROP TABLE).
    SELECT id_zona,
           ROW_NUMBER() OVER (ORDER BY id_zona) - 1 AS rn,
           COUNT(*) OVER ()                         AS tot
    INTO #zona
    FROM OCN.zona;

    ;WITH n AS (
        SELECT TOP (200) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO OCN.levantamiento (fecha, descripcion_levantamiento, nombre_equipo, id_zona, num_integrantes)
    -- CAST('20230101' AS DATETIME): convierte el texto a fecha. El formato
    --   yyyymmdd es el unico que SQL Server interpreta igual sin importar el
    --   idioma de la sesion (otros formatos pueden confundir dia y mes).
    -- DATEADD(DAY, k, fecha): suma k dias a la fecha.
    -- 3 + n % 4 : numero de integrantes entre 3 y 6.
    SELECT DATEADD(DAY, n.n, CAST('20230101' AS DATETIME)),
           'SINTETICO',
           CONCAT('Equipo sintetico ', n.n),
           z.id_zona,
           3 + n.n % 4
    FROM n
    -- n.n % z.tot da un numero entre 0 y tot-1, que coincide con una zona
    -- de #zona: asi los 200 levantamientos se reparten por turnos.
    JOIN #zona z ON z.rn = n.n % z.tot;

    -- 1.3 Tablas auxiliares con los ids disponibles (rn = 0..tot-1)
    -- Mismo truco de #zona: cada tabla lista los ids reales numerados desde 0.
    -- Luego se elige un id aleatorio escogiendo un numero aleatorio entre 0 y
    -- (total - 1) y buscandolo en la columna rn.
    SELECT id_levantamiento, ROW_NUMBER() OVER (ORDER BY id_levantamiento) - 1 AS rn
    INTO #lev FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO';

    SELECT id_problematica, ROW_NUMBER() OVER (ORDER BY id_problematica) - 1 AS rn
    INTO #prob FROM OCN.problematica;

    SELECT id_fuente, ROW_NUMBER() OVER (ORDER BY id_fuente) - 1 AS rn
    INTO #fuente FROM OCN.fuente;

    SELECT id_grupoetario, ROW_NUMBER() OVER (ORDER BY id_grupoetario) - 1 AS rn
    INTO #grupo FROM OCN.grupo_etario;

    -- Cuantos ids hay en cada tabla auxiliar (el "modulo" del aleatorio).
    DECLARE @lev_n   INT = (SELECT COUNT(*) FROM #lev);
    DECLARE @prob_n  INT = (SELECT COUNT(*) FROM #prob);
    DECLARE @fuente_n INT = (SELECT COUNT(*) FROM #fuente);
    DECLARE @grupo_n INT = (SELECT COUNT(*) FROM #grupo);

    -- 1.4 Numeros aleatorios MATERIALIZADOS (una sola evaluacion por fila).
    --     Si NEWID() queda dentro de un JOIN se reevalua en cada comparacion:
    --     el insert se vuelve lentisimo y la distribucion sale incorrecta.
    --     (Esto paso en la primera version: el INSERT tardo mas de 12 minutos.)
    --
    -- NEWID()    : genera un GUID nuevo y distinto en cada llamada
    --              (ej. 6F9619FF-8B86-D011-B42D-00C04FC964FF).
    -- CHECKSUM() : convierte ese GUID en un numero entero (puede salir
    --              negativo). Es la forma comun de obtener un entero
    --              aleatorio distinto por fila.
    -- & 2147483647 : operacion AND bit a bit con 0x7FFFFFFF (el entero
    --              positivo mas grande). Apaga el bit del signo, asi el
    --              resultado siempre es >= 0. Es mas seguro que ABS(), porque
    --              ABS del entero minimo causa desbordamiento.
    -- CROSS JOIN : combina cada fila con todas las demas (producto cartesiano).
    --              Con sys.all_objects (miles de filas) consigo mas de 100,000
    --              combinaciones; TOP (100000) se queda con las primeras.
    SELECT TOP (100000)
           ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n,
           CHECKSUM(NEWID()) & 2147483647 AS r1,
           CHECKSUM(NEWID()) & 2147483647 AS r2,
           CHECKSUM(NEWID()) & 2147483647 AS r3,
           CHECKSUM(NEWID()) & 2147483647 AS r4,
           CHECKSUM(NEWID()) & 2147483647 AS r5,
           CHECKSUM(NEWID()) & 2147483647 AS r6,
           CHECKSUM(NEWID()) & 2147483647 AS r7,
           CHECKSUM(NEWID()) & 2147483647 AS r8
    INTO #rnd
    FROM sys.all_objects a CROSS JOIN sys.all_objects b;

    -- Ids ya resueltos por fila (join por igualdad simple contra tablas de ids)
    -- Aqui se convierte cada aleatorio en la posicion (rn) del id que le toca:
    --   r % total  -> numero entre 0 y total-1.
    --   lev_rn: el CASE manda el 15% de las filas (r4 % 100 < 15) siempre al
    --   levantamiento 0 (el "caliente"); el otro 85% se reparte parejo.
    --   Eso crea el sesgo de datos que hace interesante al histograma.
    SELECT n, r1, r2, r3,
           CASE WHEN r4 % 100 < 15 THEN 0 ELSE r5 % @lev_n END AS lev_rn,
           r6 % @prob_n   AS prob_rn,
           r7 % @fuente_n AS fuente_rn,
           r8 % @grupo_n  AS grupo_rn
    INTO #rnd2
    FROM #rnd;

    -- 1.5 Detecciones sinteticas
    INSERT INTO OCN.deteccion
        (fecha_registro, frecuencia, intensidad, observaciones_generales,
         descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
    -- fecha_registro: r1 % (86400 * 1400) es un numero de segundos entre 0 y
    --   1400 dias (86,400 segundos tiene un dia); se suma a 2023-01-01, lo que
    --   da fechas al azar entre enero 2023 y octubre 2026.
    -- frecuencia: CHOOSE elige 1 de 4 textos segun r2 % 4 + 1 (1..4).
    -- intensidad: r3 % 100 es un numero entre 0 y 99:
    --   0-2   -> 'alta'  (3%)   |  3-39 -> 'media' (37%)  |  40-99 -> 'baja' (60%)
    SELECT DATEADD(SECOND, x.r1 % (86400 * 1400), CAST('20230101' AS DATETIME)),
           CHOOSE(x.r2 % 4 + 1, 'Diaria', 'Semanal', 'Mensual', 'Ocasional'),
           CASE WHEN x.r3 % 100 < 3  THEN 'alta'
                WHEN x.r3 % 100 < 40 THEN 'media'
                ELSE 'baja' END,
           CONCAT('SINTETICO obs ', x.n),
           'SINTETICO',
           l.id_levantamiento,
           p.id_problematica,
           f.id_fuente,
           g.id_grupoetario
    FROM #rnd2 x
    -- Cada JOIN traduce la posicion aleatoria (rn) al id real de esa tabla.
    JOIN #lev    l ON l.rn = x.lev_rn
    JOIN #prob   p ON p.rn = x.prob_rn
    JOIN #fuente f ON f.rn = x.fuente_rn
    JOIN #grupo  g ON g.rn = x.grupo_rn;

    -- Se eliminan las tablas temporales (tambien se borrarian solas al cerrar
    -- la sesion, pero asi no ocupan espacio en tempdb mientras se trabaja).
    DROP TABLE #zona, #lev, #prob, #fuente, #grupo, #rnd, #rnd2;
END
GO

-- 1.6 Verificacion: cuantas filas resultaron y como quedo la distribucion
-- SUM(CASE WHEN ... THEN 1 END): cuenta solo las filas que cumplen la
-- condicion (las demas devuelven NULL y SUM las ignora).
SELECT COUNT(*)                                                    AS total_filas_deteccion,
       SUM(CASE WHEN descripcion_anonima = 'SINTETICO' THEN 1 END) AS filas_sinteticas
FROM OCN.deteccion;

-- SUM(COUNT(*)) OVER (): suma de todos los conteos = total de filas; sirve
-- de denominador para el porcentaje. 100.0 (con decimal) evita que la
-- division se haga entre enteros y de 0.
SELECT intensidad, COUNT(*) AS filas,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS porcentaje
FROM OCN.deteccion
GROUP BY intensidad ORDER BY filas DESC;

SELECT TOP (5) id_levantamiento, COUNT(*) AS filas
FROM OCN.deteccion
GROUP BY id_levantamiento ORDER BY filas DESC;   -- el primero es el "caliente"
GO


/* =========================================================================
   BLOQUE 2. LINEA BASE: estadisticas e indices existentes
   (solo existe el indice clustered de la PK sobre id_deteccion)
   ========================================================================= */

-- ALTER INDEX ALL ... REBUILD: reconstruye todos los indices de la tabla y la
-- deja compacta. Es necesario porque los ROLLBACK de las pruebas de escritura
-- (BLOQUES 3 y 8) dejan paginas reservadas en la tabla; sin esto la linea base
-- (lecturas de paginas) crece cada vez que se vuelve a correr el script.
ALTER INDEX ALL ON OCN.deteccion REBUILD;
GO

-- WITH FULLSCAN: recalcula las estadisticas leyendo TODAS las filas (no una
-- muestra). Asi el histograma es exacto y las mediciones son reproducibles.
UPDATE STATISTICS OCN.deteccion WITH FULLSCAN;
GO

-- Indices actuales de la tabla (debe salir solo el clustered de la PK).
SELECT i.index_id, i.name, i.type_desc, i.is_primary_key, i.has_filter
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('OCN.deteccion');

-- Estadisticas existentes (sys.stats) con su frescura
-- sys.dm_db_stats_properties: DMV que da propiedades de cada estadistica
--   (ultima actualizacion, filas, filas muestreadas, y cuantas filas han
--   cambiado desde entonces: modification_counter).
-- CROSS APPLY: ejecuta la funcion una vez por cada fila de sys.stats.
-- STRING_AGG(col, ', ') WITHIN GROUP (ORDER BY ...): junta en un solo texto
--   los nombres de las columnas de la estadistica, separados por coma y en
--   su orden. La subconsulta lo calcula por cada estadistica.
SELECT s.name AS estadistica, s.stats_id, s.auto_created, s.user_created,
       sp.last_updated, sp.rows, sp.rows_sampled, sp.modification_counter,
       (SELECT STRING_AGG(c.name, ', ') WITHIN GROUP (ORDER BY sc.stats_column_id)
        FROM sys.stats_columns sc
        JOIN sys.columns c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
        WHERE sc.object_id = s.object_id AND sc.stats_id = s.stats_id) AS columnas
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE s.object_id = OBJECT_ID('OCN.deteccion');
GO


/* =========================================================================
   BLOQUE 3. COSTO DE ESCRITURA - ANTES DE LOS INDICES
   Inserta 10,000 filas dentro de una transaccion y hace ROLLBACK, asi la
   tabla queda igual. Se registra tiempo y bytes de log generados.
   Se repite igual en el BLOQUE 8 (despues de crear los 3 indices).
   En el plan real, los indices extra aparecen como operadores
   "Index Insert" adicionales.
   ========================================================================= */

-- STATISTICS IO : muestra por tabla las lecturas de paginas (logicas =
--                 desde memoria, fisicas = desde disco).
-- STATISTICS TIME: muestra el tiempo de CPU y el tiempo transcurrido.
-- Ambos se ven en la pestana "Mensajes" de SSMS.
SET STATISTICS IO, TIME ON;

-- BEGIN TRAN ... ROLLBACK: la transaccion se abre, se hace la prueba y se
-- DESHACE, por lo que los 10,000 inserts no quedan guardados. Dentro de la
-- transaccion, el log registra todo lo que se hizo, y eso es lo que se mide.
BEGIN TRAN;
    -- SYSDATETIME(): fecha y hora actual con alta precision (DATETIME2);
    -- se guarda al inicio para calcular cuanto tardo el INSERT.
    DECLARE @t0 DATETIME2 = SYSDATETIME();

    -- Se copian 10,000 filas existentes (con un dia mas de fecha) para que
    -- el insert pase por todos los indices que tenga la tabla.
    INSERT INTO OCN.deteccion
        (fecha_registro, frecuencia, intensidad, observaciones_generales,
         descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
    SELECT TOP (10000) DATEADD(DAY, 1, fecha_registro), frecuencia, intensidad,
           'SINTETICO prueba escritura', 'SINTETICO_ESCRITURA',
           id_levantamiento, id_problematica, id_fuente, id_grupoetario
    FROM OCN.deteccion
    WHERE descripcion_anonima = 'SINTETICO';

    -- DATEDIFF(MILLISECOND, inicio, fin): milisegundos transcurridos.
    -- sys.dm_tran_database_transactions.database_transaction_log_bytes_used:
    --   bytes que esta transaccion ha escrito en el log de transacciones.
    -- sys.dm_tran_current_transaction: identifica la transaccion ACTUAL; el
    --   JOIN deja solo la fila de esta sesion en esta base.
    SELECT 'ANTES de indices' AS momento,
           DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS ms_insert_10000_filas,
           dt.database_transaction_log_bytes_used    AS bytes_de_log
    FROM sys.dm_tran_database_transactions dt
    JOIN sys.dm_tran_current_transaction ct ON ct.transaction_id = dt.transaction_id
    WHERE dt.database_id = DB_ID();
ROLLBACK;
SET STATISTICS IO, TIME OFF;
GO


/* =========================================================================
   CONSULTA 1 - IGUALDAD EXACTA CON ORDEN
   "Las 50 detecciones mas recientes de un levantamiento"
   Patron: WHERE columna = valor ORDER BY otra_columna DESC
   Indice: nonclustered compuesto (id_levantamiento, fecha_registro DESC)
           con INCLUDE de las columnas del SELECT => cubriente.
   Se mide un levantamiento "frio" (~400 filas) y el "caliente" (~15,000).
   OPTION (RECOMPILE) hace que el optimizador use el valor de la variable
   contra el histograma (sin eso usaria la densidad promedio).
   ========================================================================= */

-- ---- Q1-A. MEDICION INICIAL ------------------------------------------------
-- CHECKPOINT                : obliga a escribir a disco las paginas modificadas
--                             que estan en memoria.
-- DBCC DROPCLEANBUFFERS     : vacia la cache de datos (solo paginas limpias,
--                             por eso va despues del CHECKPOINT). Fuerza una
--                             lectura "en frio" desde disco, para que antes y
--                             despues se midan en las mismas condiciones.
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

-- El levantamiento "caliente" es el primero de los sinteticos (el que
-- recibio el 15% de las filas). El "frio" es otro 100 posiciones despues,
-- con ~400 filas. Se usan variables para no escribir los ids a mano.
DECLARE @caliente INT = (SELECT MIN(id_levantamiento) FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO');
DECLARE @frio     INT = @caliente + 100;

-- TOP (50) + ORDER BY ... DESC: las 50 filas mas recientes.
-- Sin indice, SQL Server lee TODA la tabla, filtra y ordena.
-- OPTION (RECOMPILE): recompila la consulta con el valor real de la variable.
--   Sin esto, con variables locales el optimizador no "ve" el valor y usa un
--   estimado promedio en lugar del histograma.
SELECT TOP (50) fecha_registro, id_problematica, intensidad, frecuencia
FROM OCN.deteccion
WHERE id_levantamiento = @frio
ORDER BY fecha_registro DESC
OPTION (RECOMPILE);

SELECT TOP (50) fecha_registro, id_problematica, intensidad, frecuencia
FROM OCN.deteccion
WHERE id_levantamiento = @caliente
ORDER BY fecha_registro DESC
OPTION (RECOMPILE);

SET STATISTICS IO, TIME OFF;
GO

-- ---- Q1-B. INDICE PROPUESTO ------------------------------------------------
-- Llave (id_levantamiento, fecha_registro DESC): el arbol B+ queda ordenado
--   primero por levantamiento y, dentro de cada uno, de la fecha mas reciente
--   a la mas antigua. Un Seek va directo al levantamiento y las primeras
--   filas que encuentra YA son las 50 mas recientes: no hace falta ordenar.
-- INCLUDE (...): agrega esas columnas SOLO en las hojas (no en el arbol de
--   busqueda). Como la consulta pide justo esas columnas, el indice la
--   responde completa sin ir a la tabla ("indice cubriente"; evita Key Lookup).
CREATE NONCLUSTERED INDEX IX_deteccion_lev_fecha
    ON OCN.deteccion (id_levantamiento ASC, fecha_registro DESC)
    INCLUDE (id_problematica, intensidad, frecuencia);
GO

-- ---- Q1-C. MEDICION FINAL --------------------------------------------------
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

DECLARE @caliente INT = (SELECT MIN(id_levantamiento) FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO');
DECLARE @frio     INT = @caliente + 100;

SELECT TOP (50) fecha_registro, id_problematica, intensidad, frecuencia
FROM OCN.deteccion
WHERE id_levantamiento = @frio
ORDER BY fecha_registro DESC
OPTION (RECOMPILE);

SELECT TOP (50) fecha_registro, id_problematica, intensidad, frecuencia
FROM OCN.deteccion
WHERE id_levantamiento = @caliente
ORDER BY fecha_registro DESC
OPTION (RECOMPILE);

SET STATISTICS IO, TIME OFF;
GO

-- ---- Q1-D. ESTADISTICAS: DBCC SHOW_STATISTICS (captura el histograma) -----
-- Sin opcion: muestra las 3 partes (encabezado, vector de densidad, histograma).
-- WITH HISTOGRAM: muestra solo el histograma. Cada fila es un "escalon":
--   RANGE_HI_KEY = valor tope del escalon, EQ_ROWS = filas que valen
--   exactamente ese valor, RANGE_ROWS = filas entre el escalon anterior y
--   este, DISTINCT_RANGE_ROWS = valores distintos dentro de ese rango.
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_lev_fecha');
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_lev_fecha') WITH HISTOGRAM;

-- Fila del histograma para el levantamiento caliente: EQ_ROWS (estimado)
-- se compara contra el conteo real para la tabla estimado vs. real.
-- sys.dm_db_stats_histogram(): hace lo mismo que DBCC ... WITH HISTOGRAM pero
--   como funcion, asi se puede filtrar con WHERE y unir con otras consultas.
DECLARE @caliente INT = (SELECT MIN(id_levantamiento) FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO');
SELECT h.range_high_key, h.equal_rows, h.range_rows, h.distinct_range_rows,
       (SELECT COUNT(*) FROM OCN.deteccion WHERE id_levantamiento = @caliente) AS filas_reales
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_histogram(s.object_id, s.stats_id) h
WHERE s.object_id = OBJECT_ID('OCN.deteccion')
  AND s.name = N'IX_deteccion_lev_fecha'
  AND h.range_high_key = @caliente;
GO

-- ---- Q1-E. ARQUITECTURA: niveles y paginas del arbol B+ --------------------
-- index_level 0 = hojas; el nivel mas alto = raiz. page_count por nivel.
-- sys.dm_db_index_physical_stats(..., 'DETAILED'): estructura fisica del
--   indice, una fila por nivel del arbol. 'DETAILED' recorre todos los niveles
--   (es la modalidad que da page_count y record_count por nivel).
--   index_depth = cuantos niveles tiene el arbol (lo que cuesta un Seek).
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_lev_fecha'
   OR i.type_desc = 'CLUSTERED'   -- el clustered sirve de referencia (Q1-A)
ORDER BY i.index_id, ps.index_level DESC;
GO


/* =========================================================================
   CONSULTA 2 - FILTRO SOBRE UN SUBCONJUNTO DE FILAS
   "Detecciones de intensidad ALTA del primer trimestre de 2026"
   Solo el 3% de las filas tiene intensidad = 'alta'.
   Indice: nonclustered FILTRADO  WHERE intensidad = 'alta'
           => el arbol solo contiene ese 3% (menos paginas, menos niveles,
           menos costo de mantenimiento: solo se actualiza cuando la fila
           cumple el filtro).
   NOTA: el indice filtrado solo se usa si el predicado de la consulta
   coincide con el del filtro con un LITERAL (con parametro hace falta
   OPTION (RECOMPILE)).
   ========================================================================= */

-- ---- Q2-A. MEDICION INICIAL ------------------------------------------------
-- Se quita el indice de Q1: si existiera, el optimizador podria escanear ese
-- indice (mas angosto que la tabla) y la linea base no seria comparable.
-- (Antes de esta correccion el "antes" salia en 545 paginas en vez de 1,223.)
DROP INDEX IF EXISTS IX_deteccion_lev_fecha ON OCN.deteccion;
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

-- fecha >= '20260101' AND fecha < '20260401': rango "cerrado-abierto". Es
-- mejor que BETWEEN con '20260331' porque no deja fuera las horas del ultimo
-- dia, y es sargable (la columna va sola, sin funciones).
SELECT id_deteccion, fecha_registro, id_levantamiento, id_problematica
FROM OCN.deteccion
WHERE intensidad = 'alta'
  AND fecha_registro >= '20260101' AND fecha_registro < '20260401'
ORDER BY fecha_registro;

SET STATISTICS IO, TIME OFF;
GO

-- ---- Q2-B. INDICE PROPUESTO ------------------------------------------------
-- WHERE intensidad = 'alta' al final: indice FILTRADO. Solo guarda las filas
--   que cumplen esa condicion (el 3%). La llave es fecha_registro, asi el
--   rango de fechas y el ORDER BY se resuelven con un Seek ya ordenado.
-- id_deteccion no se pone en el INCLUDE porque ya va incluido de forma
--   automatica (es la llave del indice clustered).
CREATE NONCLUSTERED INDEX IX_deteccion_alta_fecha
    ON OCN.deteccion (fecha_registro)
    INCLUDE (id_levantamiento, id_problematica)
    WHERE intensidad = 'alta';
GO

-- ---- Q2-C. MEDICION FINAL --------------------------------------------------
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

SELECT id_deteccion, fecha_registro, id_levantamiento, id_problematica
FROM OCN.deteccion
WHERE intensidad = 'alta'
  AND fecha_registro >= '20260101' AND fecha_registro < '20260401'
ORDER BY fecha_registro;

SET STATISTICS IO, TIME OFF;
GO

-- ---- Q2-D. ESTADISTICAS ----------------------------------------------------
-- En el encabezado, "Filter Expression" y "Unfiltered Rows" vs "Rows".
-- Rows = filas dentro del filtro (~2,982); Unfiltered Rows = filas de toda
-- la tabla cuando se calculo la estadistica.
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_alta_fecha');
GO

-- ---- Q2-E. COMPARACION: indice filtrado vs. el mismo indice SIN filtro -----
-- Justifica "por que filtrado": mismo contenido util, mucho menos espacio.
CREATE NONCLUSTERED INDEX IX_tmp_intensidad_fecha
    ON OCN.deteccion (intensidad, fecha_registro)
    INCLUDE (id_levantamiento, id_problematica);
GO

-- sys.dm_db_partition_stats: filas y paginas usadas por cada indice.
-- Una pagina de SQL Server = 8 KB, por eso paginas * 8 / 1024 = megabytes.
SELECT i.name AS indice, i.has_filter, ps.row_count, ps.used_page_count,
       CAST(ps.used_page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS mb
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID('OCN.deteccion')
  AND i.name IN (N'IX_deteccion_alta_fecha', N'IX_tmp_intensidad_fecha');
GO

-- El indice temporal solo era para comparar tamanos; se elimina.
DROP INDEX IX_tmp_intensidad_fecha ON OCN.deteccion;
GO

-- ---- Q2-F. ARQUITECTURA ----------------------------------------------------
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_alta_fecha'
ORDER BY ps.index_level DESC;
GO


/* =========================================================================
   CONSULTA 3 - VALOR DERIVADO Y SARGABILIDAD
   "Cuantas detecciones se registraron en marzo de 2025"
   Problema: YEAR(fecha_registro) y MONTH(fecha_registro) aplican una
   funcion sobre la columna => predicado NO sargable: ningun indice sobre
   fecha_registro permite un Seek y el optimizador estima mal las filas.
   Solucion A (elegida): columna calculada anio_mes = YEAR*100 + MONTH
                         + indice nonclustered sobre ella.
   Solucion B (comparacion): reescribir como rango sobre fecha_registro
                         + indice sobre fecha_registro (se mide y se descarta).
   ========================================================================= */

-- ---- Q3-A. MEDICION INICIAL (consulta no sargable) -------------------------
-- Linea base limpia: sin los indices de Q1 ni Q2 (ver nota en Q2-A).
DROP INDEX IF EXISTS IX_deteccion_lev_fecha  ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_alta_fecha ON OCN.deteccion;
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

-- "Sargable" (Search ARGument ABLE): el predicado permite usar un Seek.
-- Aqui NO lo es: SQL Server tiene que calcular YEAR() y MONTH() para CADA
-- fila antes de poder comparar, asi que no puede saltar a las filas de
-- marzo 2025 y debe leer toda la tabla (Scan).
SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE YEAR(fecha_registro) = 2025 AND MONTH(fecha_registro) = 3;

SET STATISTICS IO, TIME OFF;
GO
-- En el plan real: compara "Estimated Number of Rows" vs "Actual Number of
-- Rows" del operador de acceso; la estimacion sale de una suposicion fija
-- porque no hay estadistica sobre la expresion.

-- ---- Q3-B. COLUMNA CALCULADA + INDICE PROPUESTO ----------------------------
-- No se persiste: el indice ya materializa el valor en sus hojas.
-- Columna calculada: no guarda datos propios, se define con una formula.
--   YEAR*100 + MONTH convierte marzo 2025 en el entero 202503 (un valor
--   comparable con "=" y barato de indexar).
-- Sin la palabra PERSISTED la tabla no guarda el valor; solo lo guarda el
-- indice que se crea en el paso siguiente.
ALTER TABLE OCN.deteccion
    ADD anio_mes AS (YEAR(fecha_registro) * 100 + MONTH(fecha_registro));
GO

-- Indice sobre la columna calculada: ahora el valor derivado SI esta
-- ordenado en un arbol B+, y buscar anio_mes = 202503 es un Seek.
-- (Va en un lote aparte, despues del GO, porque la columna debe existir
-- antes de poder referenciarla.)
CREATE NONCLUSTERED INDEX IX_deteccion_anio_mes
    ON OCN.deteccion (anio_mes);
GO

-- ---- Q3-C. MEDICION FINAL (consulta reescrita sobre la columna derivada) ---
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE anio_mes = 202503;

-- La version original SIGUE sin poder usar el indice (no coincide con la
-- definicion de la columna): demuestra por que hubo que reescribir.
SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE YEAR(fecha_registro) = 2025 AND MONTH(fecha_registro) = 3;

SET STATISTICS IO, TIME OFF;
GO

-- ---- Q3-D. ESTADISTICAS ----------------------------------------------------
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_anio_mes');
GO

-- ---- Q3-E. COMPARACION: solucion B (rango sargable + indice en la fecha) ---
-- Alternativa que no cambia el esquema: dejar la consulta como rango sobre
-- la columna original e indexar fecha_registro directamente.
CREATE NONCLUSTERED INDEX IX_tmp_fecha_registro
    ON OCN.deteccion (fecha_registro);
GO

CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE fecha_registro >= '20250301' AND fecha_registro < '20250401';

SET STATISTICS IO, TIME OFF;
GO

DROP INDEX IX_tmp_fecha_registro ON OCN.deteccion;
GO

-- ---- Q3-F. ARQUITECTURA ----------------------------------------------------
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_anio_mes'
ORDER BY ps.index_level DESC;
GO


/* =========================================================================
   BLOQUE 6.5. RECREAR LOS INDICES DE Q1 Y Q2
   Se quitaron para tomar lineas base limpias; para medir el costo de
   escritura y el espacio, los tres indices deben existir a la vez.
   ========================================================================= */
CREATE NONCLUSTERED INDEX IX_deteccion_lev_fecha
    ON OCN.deteccion (id_levantamiento ASC, fecha_registro DESC)
    INCLUDE (id_problematica, intensidad, frecuencia);

CREATE NONCLUSTERED INDEX IX_deteccion_alta_fecha
    ON OCN.deteccion (fecha_registro)
    INCLUDE (id_levantamiento, id_problematica)
    WHERE intensidad = 'alta';
GO


/* =========================================================================
   BLOQUE 7. RESUMEN: TAMANO DE LOS 3 INDICES FRENTE A LA TABLA
   ========================================================================= */
SELECT i.name AS indice, i.type_desc, i.has_filter, ps.row_count,
       ps.used_page_count, CAST(ps.used_page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS mb
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID('OCN.deteccion')
ORDER BY i.index_id;
GO


/* =========================================================================
   BLOQUE 8. COSTO DE ESCRITURA - DESPUES DE LOS 3 INDICES
   Misma prueba del BLOQUE 3. Compara tiempo y bytes de log.
   Cada INSERT ahora tambien debe actualizar los 3 indices nuevos (y el de
   anio_mes calcula su valor por fila), por eso tarda mas y escribe mas log.
   ========================================================================= */
SET STATISTICS IO, TIME ON;
BEGIN TRAN;
    DECLARE @t0 DATETIME2 = SYSDATETIME();

    INSERT INTO OCN.deteccion
        (fecha_registro, frecuencia, intensidad, observaciones_generales,
         descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
    SELECT TOP (10000) DATEADD(DAY, 1, fecha_registro), frecuencia, intensidad,
           'SINTETICO prueba escritura', 'SINTETICO_ESCRITURA',
           id_levantamiento, id_problematica, id_fuente, id_grupoetario
    FROM OCN.deteccion
    WHERE descripcion_anonima = 'SINTETICO';

    SELECT 'DESPUES de indices' AS momento,
           DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS ms_insert_10000_filas,
           dt.database_transaction_log_bytes_used    AS bytes_de_log
    FROM sys.dm_tran_database_transactions dt
    JOIN sys.dm_tran_current_transaction ct ON ct.transaction_id = dt.transaction_id
    WHERE dt.database_id = DB_ID();
ROLLBACK;
SET STATISTICS IO, TIME OFF;
GO


/* =========================================================================
   BLOQUE 9. LIMPIEZA (opcional, ejecutar solo al terminar el trabajo)
   Quita indices, columna calculada y datos sinteticos.
   Las detecciones sinteticas no tienen intervenciones, por lo que el
   DELETE no choca con ninguna llave foranea.
   Esta comentado a proposito: para ejecutarlo hay que quitar los
   delimitadores de comentario de bloque que lo rodean.
   ========================================================================= */
/*
DROP INDEX IF EXISTS IX_deteccion_lev_fecha  ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_alta_fecha ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_anio_mes   ON OCN.deteccion;
IF COL_LENGTH('OCN.deteccion', 'anio_mes') IS NOT NULL
    ALTER TABLE OCN.deteccion DROP COLUMN anio_mes;
GO
DELETE FROM OCN.deteccion      WHERE descripcion_anonima = 'SINTETICO';
DELETE FROM OCN.levantamiento  WHERE descripcion_levantamiento = 'SINTETICO';
DELETE FROM OCN.problematica   WHERE descripcion_problematica = 'SINTETICO';
GO
*/
