-- Proyecto OCN - Optimizacion de consultas criticas
-- Entrega 1 (RegistrosOCN es OCN.deteccion en mi base)
-- Los datos de prueba llevan 'SINTETICO' para poder borrarlos al final (bloque 9)

USE OCN_DB;
GO

-- estas opciones las piden los indices filtrados y las columnas calculadas
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO


-- ===== BLOQUE 0: reiniciar =====
-- borro los indices que voy a crear para poder correr el script otra vez desde cero
-- (el IF EXISTS es para que no marque error si todavia no existen)
DROP INDEX IF EXISTS IX_deteccion_lev_fecha     ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_alta_fecha    ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_anio_mes      ON OCN.deteccion;
DROP INDEX IF EXISTS IX_tmp_intensidad_fecha    ON OCN.deteccion;
DROP INDEX IF EXISTS IX_tmp_fecha_registro      ON OCN.deteccion;
-- col_length da null si la columna no existe, asi se si hay que borrarla
IF COL_LENGTH('OCN.deteccion', 'anio_mes') IS NOT NULL
    ALTER TABLE OCN.deteccion DROP COLUMN anio_mes;
GO


-- ===== BLOQUE 1: generar los datos (100,000 filas, el minimo era 50,000) =====
-- lo hago todo en un solo insert, es mucho mas rapido que un cursor o un while
-- hice que los datos no fueran parejos para que el histograma tenga algo que mostrar:
--   intensidad: 3% alta, 37% media, 60% baja
--   15% de las filas caen en un solo levantamiento
DECLARE @existentes INT =
    (SELECT COUNT(*) FROM OCN.deteccion WHERE descripcion_anonima = 'SINTETICO');

IF @existentes = 0   -- si ya hay datos de prueba no los vuelve a crear
BEGIN
    -- por si una corrida anterior se quedo a la mitad
    DELETE FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO';
    DELETE FROM OCN.problematica  WHERE descripcion_problematica  = 'SINTETICO';

    -- problematicas: hago una lista de numeros del 1 al 18 con row_number
    -- (el order by (select null) es por que la funcion lo pide, el orden no me importa)
    ;WITH n AS (
        SELECT TOP (18) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    )
    INSERT INTO OCN.problematica (nombre_problematica, categoria, nivel_prioridad, descripcion_problematica)
    -- concat pega textos, choose saca el valor que toca segun el numero (1 = el primero)
    -- n % 3 + 1 es el residuo de dividir entre 3, asi se van alternando
    SELECT CONCAT('Problematica sintetica ', n),
           CHOOSE(n % 3 + 1, 'Infraestructura', 'Salubridad', 'Seguridad'),
           CHOOSE(n % 3 + 1, 'Alta', 'Media', 'Baja'),
           'SINTETICO'
    FROM n;

    -- numero las zonas desde 0 para asignarlas por turnos a los levantamientos
    -- count(*) over () me da el total de zonas en cada fila
    -- select into #zona la guarda en una tabla temporal
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
    -- el formato yyyymmdd en cast siempre se lee igual sin importar el idioma
    -- dateadd le suma n dias a la fecha
    SELECT DATEADD(DAY, n.n, CAST('20230101' AS DATETIME)),
           'SINTETICO',
           CONCAT('Equipo sintetico ', n.n),
           z.id_zona,
           3 + n.n % 4
    FROM n
    JOIN #zona z ON z.rn = n.n % z.tot;   -- el % reparte las zonas por turnos

    -- lo mismo con las demas tablas: ids numerados desde 0
    -- asi un numero random entre 0 y total-1 me elige un id al azar
    SELECT id_levantamiento, ROW_NUMBER() OVER (ORDER BY id_levantamiento) - 1 AS rn
    INTO #lev FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO';

    SELECT id_problematica, ROW_NUMBER() OVER (ORDER BY id_problematica) - 1 AS rn
    INTO #prob FROM OCN.problematica;

    SELECT id_fuente, ROW_NUMBER() OVER (ORDER BY id_fuente) - 1 AS rn
    INTO #fuente FROM OCN.fuente;

    SELECT id_grupoetario, ROW_NUMBER() OVER (ORDER BY id_grupoetario) - 1 AS rn
    INTO #grupo FROM OCN.grupo_etario;

    DECLARE @lev_n   INT = (SELECT COUNT(*) FROM #lev);
    DECLARE @prob_n  INT = (SELECT COUNT(*) FROM #prob);
    DECLARE @fuente_n INT = (SELECT COUNT(*) FROM #fuente);
    DECLARE @grupo_n INT = (SELECT COUNT(*) FROM #grupo);

    -- los numeros random los guardo primero en #rnd. La primera vez los puse
    -- directo en el join y tardo mas de 12 min, porque newid() se recalcula
    -- en cada comparacion
    -- newid() da un guid distinto cada vez, checksum() lo vuelve un entero
    -- el & 2147483647 es para que nunca salga negativo
    -- el cross join junta cada fila con todas las demas, asi salen filas de sobra
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

    -- paso cada random a una posicion valida (r % total da de 0 a total-1)
    -- el case manda el 15% de las filas al levantamiento 0, ese es el "caliente"
    SELECT n, r1, r2, r3,
           CASE WHEN r4 % 100 < 15 THEN 0 ELSE r5 % @lev_n END AS lev_rn,
           r6 % @prob_n   AS prob_rn,
           r7 % @fuente_n AS fuente_rn,
           r8 % @grupo_n  AS grupo_rn
    INTO #rnd2
    FROM #rnd;

    INSERT INTO OCN.deteccion
        (fecha_registro, frecuencia, intensidad, observaciones_generales,
         descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
    -- fecha: segundos al azar dentro de 1400 dias (un dia tiene 86400 segundos)
    -- intensidad: r3 % 100 da de 0 a 99, menos de 3 es alta, menos de 40 media
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
    JOIN #lev    l ON l.rn = x.lev_rn      -- cada join cambia la posicion random
    JOIN #prob   p ON p.rn = x.prob_rn     -- por el id real de esa tabla
    JOIN #fuente f ON f.rn = x.fuente_rn
    JOIN #grupo  g ON g.rn = x.grupo_rn;

    DROP TABLE #zona, #lev, #prob, #fuente, #grupo, #rnd, #rnd2;
END
GO

-- verifico cuantas filas quedaron y como se repartieron
-- el sum(case ... then 1 end) solo cuenta las que cumplen la condicion
SELECT COUNT(*)                                                    AS total_filas_deteccion,
       SUM(CASE WHEN descripcion_anonima = 'SINTETICO' THEN 1 END) AS filas_sinteticas
FROM OCN.deteccion;

-- el sum(count(*)) over () es el total, lo uso para sacar el porcentaje
SELECT intensidad, COUNT(*) AS filas,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS porcentaje
FROM OCN.deteccion
GROUP BY intensidad ORDER BY filas DESC;

SELECT TOP (5) id_levantamiento, COUNT(*) AS filas
FROM OCN.deteccion
GROUP BY id_levantamiento ORDER BY filas DESC;   -- el primero es el caliente
GO


-- ===== BLOQUE 2: linea base =====
-- rebuild deja la tabla compacta. Los rollback de las pruebas de escritura
-- dejan paginas reservadas y si no, las lecturas cambian cada vez que corro el script
ALTER INDEX ALL ON OCN.deteccion REBUILD;
GO
UPDATE STATISTICS OCN.deteccion WITH FULLSCAN;   -- fullscan lee todas las filas, no una muestra
GO

SELECT i.index_id, i.name, i.type_desc, i.is_primary_key, i.has_filter
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID('OCN.deteccion');

-- estadisticas que ya existen y cuando se actualizaron
-- string_agg junta los nombres de las columnas en un solo texto
-- el cross apply corre la funcion una vez por cada estadistica
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


-- ===== BLOQUE 3: costo de escritura ANTES de los indices =====
-- inserto 10,000 filas y hago rollback para que la tabla quede igual
-- mido el tiempo y los bytes de log. Lo repito en el bloque 8 con los indices
SET STATISTICS IO, TIME ON;
BEGIN TRAN;
    DECLARE @t0 DATETIME2 = SYSDATETIME();   -- hora de inicio

    INSERT INTO OCN.deteccion
        (fecha_registro, frecuencia, intensidad, observaciones_generales,
         descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
    SELECT TOP (10000) DATEADD(DAY, 1, fecha_registro), frecuencia, intensidad,
           'SINTETICO prueba escritura', 'SINTETICO_ESCRITURA',
           id_levantamiento, id_problematica, id_fuente, id_grupoetario
    FROM OCN.deteccion
    WHERE descripcion_anonima = 'SINTETICO';

    -- los bytes de log salen de las dmv de la transaccion actual
    SELECT 'ANTES de indices' AS momento,
           DATEDIFF(MILLISECOND, @t0, SYSDATETIME()) AS ms_insert_10000_filas,
           dt.database_transaction_log_bytes_used    AS bytes_de_log
    FROM sys.dm_tran_database_transactions dt
    JOIN sys.dm_tran_current_transaction ct ON ct.transaction_id = dt.transaction_id
    WHERE dt.database_id = DB_ID();
ROLLBACK;
SET STATISTICS IO, TIME OFF;
GO


-- ===== CONSULTA 1: igualdad con orden =====
-- las 50 detecciones mas recientes de un levantamiento
-- indice compuesto (levantamiento, fecha desc) con include para que lo cubra todo
-- pruebo con un levantamiento frio (~400 filas) y el caliente (~15,000)

-- Q1-A: medicion inicial
-- checkpoint + dropcleanbuffers vacian la cache para medir siempre en frio
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

DECLARE @caliente INT = (SELECT MIN(id_levantamiento) FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO');
DECLARE @frio     INT = @caliente + 100;

-- con option (recompile) usa el valor real de la variable contra el histograma,
-- sin eso saca un promedio y el estimado sale mal
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

-- Q1-B: el indice
-- como la llave ya esta ordenada por fecha desc, no tiene que ordenar nada
-- el include guarda las demas columnas en las hojas, asi no va a la tabla
CREATE NONCLUSTERED INDEX IX_deteccion_lev_fecha
    ON OCN.deteccion (id_levantamiento ASC, fecha_registro DESC)
    INCLUDE (id_problematica, intensidad, frecuencia);
GO

-- Q1-C: medicion final
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

-- Q1-D: estadisticas (aqui se ve el histograma)
-- eq_rows son las filas que valen exactamente ese valor
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_lev_fecha');
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_lev_fecha') WITH HISTOGRAM;

-- estimado (equal_rows) contra las filas reales del levantamiento caliente
-- dm_db_stats_histogram es lo mismo que el dbcc pero se puede filtrar con where
DECLARE @caliente INT = (SELECT MIN(id_levantamiento) FROM OCN.levantamiento WHERE descripcion_levantamiento = 'SINTETICO');
SELECT h.range_high_key, h.equal_rows, h.range_rows, h.distinct_range_rows,
       (SELECT COUNT(*) FROM OCN.deteccion WHERE id_levantamiento = @caliente) AS filas_reales
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_histogram(s.object_id, s.stats_id) h
WHERE s.object_id = OBJECT_ID('OCN.deteccion')
  AND s.name = N'IX_deteccion_lev_fecha'
  AND h.range_high_key = @caliente;
GO

-- Q1-E: niveles y paginas del arbol
-- index_level 0 son las hojas, el nivel mas alto es la raiz
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_lev_fecha'
   OR i.type_desc = 'CLUSTERED'   -- el clustered lo dejo de referencia
ORDER BY i.index_id, ps.index_level DESC;
GO


-- ===== CONSULTA 2: filtro sobre un subconjunto =====
-- detecciones de intensidad alta del primer trimestre de 2026
-- solo el 3% de las filas es 'alta', asi que uso un indice filtrado
-- ojo: solo lo usa si la consulta trae el literal 'alta'

-- Q2-A: medicion inicial
-- quito el indice de Q1 porque si no, escanea ese en vez de la tabla
-- y la linea base ya no es comparable
DROP INDEX IF EXISTS IX_deteccion_lev_fecha ON OCN.deteccion;
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

-- uso >= inicio y < fin en vez de between, para no perder las horas del ultimo dia
SELECT id_deteccion, fecha_registro, id_levantamiento, id_problematica
FROM OCN.deteccion
WHERE intensidad = 'alta'
  AND fecha_registro >= '20260101' AND fecha_registro < '20260401'
ORDER BY fecha_registro;

SET STATISTICS IO, TIME OFF;
GO

-- Q2-B: el indice
-- el where del final lo hace filtrado, solo guarda las filas alta
-- id_deteccion no lo pongo en el include porque ya va por ser la llave del clustered
CREATE NONCLUSTERED INDEX IX_deteccion_alta_fecha
    ON OCN.deteccion (fecha_registro)
    INCLUDE (id_levantamiento, id_problematica)
    WHERE intensidad = 'alta';
GO

-- Q2-C: medicion final
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

SELECT id_deteccion, fecha_registro, id_levantamiento, id_problematica
FROM OCN.deteccion
WHERE intensidad = 'alta'
  AND fecha_registro >= '20260101' AND fecha_registro < '20260401'
ORDER BY fecha_registro;

SET STATISTICS IO, TIME OFF;
GO

-- Q2-D: estadisticas
-- en el encabezado se ve el Filter Expression y Unfiltered Rows contra Rows
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_alta_fecha');
GO

-- Q2-E: comparo contra el mismo indice sin filtro, para ver cuanto espacio ahorra
CREATE NONCLUSTERED INDEX IX_tmp_intensidad_fecha
    ON OCN.deteccion (intensidad, fecha_registro)
    INCLUDE (id_levantamiento, id_problematica);
GO

-- una pagina son 8 KB, por eso paginas * 8 / 1024 son los MB
SELECT i.name AS indice, i.has_filter, ps.row_count, ps.used_page_count,
       CAST(ps.used_page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS mb
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID('OCN.deteccion')
  AND i.name IN (N'IX_deteccion_alta_fecha', N'IX_tmp_intensidad_fecha');
GO

DROP INDEX IX_tmp_intensidad_fecha ON OCN.deteccion;   -- solo era para comparar
GO

-- Q2-F: arquitectura
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_alta_fecha'
ORDER BY ps.index_level DESC;
GO


-- ===== CONSULTA 3: valor derivado y sargabilidad =====
-- detecciones de marzo de 2025
-- el year() y month() sobre la columna no dejan usar un seek (no es sargable)
-- solucion A (la que elegi): columna calculada anio_mes + indice
-- solucion B (solo para comparar): rango sobre fecha_registro + indice en la fecha

-- Q3-A: medicion inicial
-- quito los indices de Q1 y Q2 por lo mismo de antes
DROP INDEX IF EXISTS IX_deteccion_lev_fecha  ON OCN.deteccion;
DROP INDEX IF EXISTS IX_deteccion_alta_fecha ON OCN.deteccion;
GO
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

-- tiene que calcular year() y month() en cada fila, por eso lee toda la tabla
SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE YEAR(fecha_registro) = 2025 AND MONTH(fecha_registro) = 3;

SET STATISTICS IO, TIME OFF;
GO
-- en el plan comparar Estimated Number of Rows contra Actual Number of Rows

-- Q3-B: columna calculada + indice
-- no la puse persisted, el valor solo lo guarda el indice
-- year*100 + month vuelve marzo 2025 en 202503
ALTER TABLE OCN.deteccion
    ADD anio_mes AS (YEAR(fecha_registro) * 100 + MONTH(fecha_registro));
GO

-- va despues del go porque la columna tiene que existir antes
CREATE NONCLUSTERED INDEX IX_deteccion_anio_mes
    ON OCN.deteccion (anio_mes);
GO

-- Q3-C: medicion final
CHECKPOINT; DBCC DROPCLEANBUFFERS;
SET STATISTICS IO, TIME ON;

SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE anio_mes = 202503;

-- la consulta original sigue sin usar el indice, por eso hubo que reescribirla
SELECT COUNT(*) AS total
FROM OCN.deteccion
WHERE YEAR(fecha_registro) = 2025 AND MONTH(fecha_registro) = 3;

SET STATISTICS IO, TIME OFF;
GO

-- Q3-D: estadisticas
DBCC SHOW_STATISTICS (N'OCN.deteccion', N'IX_deteccion_anio_mes');
GO

-- Q3-E: solucion B, rango de fechas con indice en fecha_registro
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

-- Q3-F: arquitectura
SELECT i.name AS indice, ps.index_depth, ps.index_level, ps.page_count,
       ps.record_count, ps.avg_record_size_in_bytes
FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('OCN.deteccion'), NULL, NULL, 'DETAILED') ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE i.name = N'IX_deteccion_anio_mes'
ORDER BY ps.index_level DESC;
GO


-- ===== BLOQUE 6.5: volver a crear los indices de Q1 y Q2 =====
-- los quite para tener lineas base limpias, pero para medir escritura y
-- espacio tienen que estar los tres al mismo tiempo
CREATE NONCLUSTERED INDEX IX_deteccion_lev_fecha
    ON OCN.deteccion (id_levantamiento ASC, fecha_registro DESC)
    INCLUDE (id_problematica, intensidad, frecuencia);

CREATE NONCLUSTERED INDEX IX_deteccion_alta_fecha
    ON OCN.deteccion (fecha_registro)
    INCLUDE (id_levantamiento, id_problematica)
    WHERE intensidad = 'alta';
GO


-- ===== BLOQUE 7: tamano de los indices =====
SELECT i.name AS indice, i.type_desc, i.has_filter, ps.row_count,
       ps.used_page_count, CAST(ps.used_page_count * 8.0 / 1024 AS DECIMAL(10,2)) AS mb
FROM sys.dm_db_partition_stats ps
JOIN sys.indexes i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE ps.object_id = OBJECT_ID('OCN.deteccion')
ORDER BY i.index_id;
GO


-- ===== BLOQUE 8: costo de escritura DESPUES de los indices =====
-- es la misma prueba del bloque 3, ahora cada insert tambien actualiza los indices
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


-- ===== BLOQUE 9: limpieza =====
-- correrlo solo hasta terminar todo, borra los indices, la columna y los datos de prueba
-- esta comentado, hay que quitarle los delimitadores para ejecutarlo
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
