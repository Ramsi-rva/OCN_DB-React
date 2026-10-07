/*Mapeo respecto al enunciado (los nombres reales de tu base difieren
   de los nombres genericos del documento):
       Zonas              -> OCN.zona
       Problematicas      -> OCN.problematica
       RegistrosOCN       -> OCN.deteccion
       RecursosComunitarios -> OCN.recurso_comunitario (nueva, no existia)*/

USE OCN_DB;
go

/* =========================================================================
   Se agrega auto-relacion en zona para poder construir la CTE recursiva
   del Tema 5 sin inventar una tabla nueva para esto.
   ========================================================================= */
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('OCN.zona') AND name = 'id_zona_padre'
)
BEGIN
    ALTER TABLE OCN.zona ADD id_zona_padre INTEGER NULL
        CONSTRAINT fk_zona_zona_padre FOREIGN KEY REFERENCES OCN.zona(id_zona);
END
go

/* =========================================================================
   NUEVAS ENTIDADES
   ========================================================================= */

-- Entidad RecursosComunitarios
IF OBJECT_ID('OCN.recurso_comunitario') IS NULL
BEGIN
    CREATE TABLE OCN.recurso_comunitario
    (
        id_recurso INTEGER PRIMARY KEY IDENTITY(1,1),
        nombre_recurso VARCHAR(150) NOT NULL,
        tipo_recurso VARCHAR(100) NOT NULL,
        id_zona INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.zona(id_zona),
        capacidad INTEGER NULL,
        descripcion_recurso VARCHAR(255) NULL
    );
END
go

-- Entidad principal: Intervenciones
-- Cardinalidad: 1 deteccion -> N intervenciones ; 1 recurso_comunitario -> N intervenciones (opcional)
IF OBJECT_ID('OCN.intervencion') IS NULL
BEGIN
    CREATE TABLE OCN.intervencion
    (
        id_intervencion INTEGER PRIMARY KEY IDENTITY(1,1),
        id_deteccion INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.deteccion(id_deteccion),
        id_recurso INTEGER NULL FOREIGN KEY REFERENCES OCN.recurso_comunitario(id_recurso),
        tipo_intervencion VARCHAR(100) NOT NULL,
        descripcion_intervencion VARCHAR(255) NOT NULL,
        responsable VARCHAR(100) NOT NULL,
        fecha_planeada DATETIME NOT NULL,
        fecha_ejecucion DATETIME NULL,
        estado VARCHAR(20) NOT NULL
            CONSTRAINT ck_intervencion_estado CHECK (estado IN ('Planeada','EnProceso','Completada')),
        fecha_creacion DATETIME NOT NULL CONSTRAINT df_intervencion_fecha_creacion DEFAULT (GETDATE()),
        fecha_actualizacion DATETIME NOT NULL CONSTRAINT df_intervencion_fecha_actualizacion DEFAULT (GETDATE())
    );
END
go

-- Tabla de auditoria para el trigger de cambios de estado (Tema 3)
-- NOTA: FK con ON DELETE CASCADE para que al borrar una intervencion
-- se elimine automaticamente su historial de auditoria (evita el error 547).
IF OBJECT_ID('OCN.intervencion_auditoria') IS NULL
BEGIN
    CREATE TABLE OCN.intervencion_auditoria
    (
        id_auditoria INTEGER PRIMARY KEY IDENTITY(1,1),
        id_intervencion INTEGER NOT NULL
            CONSTRAINT fk_auditoria_intervencion
            FOREIGN KEY REFERENCES OCN.intervencion(id_intervencion)
            ON DELETE CASCADE,
        estado_anterior VARCHAR(20) NULL,
        estado_nuevo VARCHAR(20) NOT NULL,
        fecha_cambio DATETIME NOT NULL CONSTRAINT df_auditoria_fecha DEFAULT (GETDATE()),
        usuario_bd VARCHAR(128) NOT NULL CONSTRAINT df_auditoria_usuario DEFAULT (SUSER_SNAME())
    );
END
go

-- Migracion de seguridad: si la tabla ya existia con la FK vieja
-- (sin cascada, p.ej. "FK__intervenc__id_in__208CD6FA"), se reemplaza.
IF EXISTS (
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID('OCN.intervencion_auditoria')
      AND referenced_object_id = OBJECT_ID('OCN.intervencion')
      AND delete_referential_action = 0  -- 0 = NO ACTION (sin cascada)
)
BEGIN
    DECLARE @fk_name SYSNAME;
    SELECT @fk_name = name FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID('OCN.intervencion_auditoria')
      AND referenced_object_id = OBJECT_ID('OCN.intervencion')
      AND delete_referential_action = 0;

    EXEC('ALTER TABLE OCN.intervencion_auditoria DROP CONSTRAINT [' + @fk_name + ']');
    ALTER TABLE OCN.intervencion_auditoria
        ADD CONSTRAINT fk_auditoria_intervencion
        FOREIGN KEY (id_intervencion) REFERENCES OCN.intervencion(id_intervencion)
        ON DELETE CASCADE;
END
go

-- Tabla de errores para el procedimiento transaccional (Tema 2)
IF OBJECT_ID('OCN.error_log') IS NULL
BEGIN
    CREATE TABLE OCN.error_log
    (
        id_error INTEGER PRIMARY KEY IDENTITY(1,1),
        fecha_error DATETIME NOT NULL CONSTRAINT df_error_fecha DEFAULT (GETDATE()),
        procedimiento VARCHAR(200) NULL,
        mensaje_error VARCHAR(2000) NULL,
        numero_error INTEGER NULL,
        severidad_error INTEGER NULL,
        estado_error INTEGER NULL,
        linea_error INTEGER NULL
    );
END
go

/* =========================================================================
   (nueva zona, sub-zonas para jerarquia, levantamiento y detecciones
    adicionales, recursos comunitarios, y 15 intervenciones en 3 zonas
    y los 3 estados posibles)
   ========================================================================= */

-- Tercera zona (para tener 3 zonas con intervenciones)
INSERT INTO OCN.zona (nombre_zona, id_tipo_zona, poblacion_aprox, descripcion_zona)
VALUES ('Zona Centro', 1, 8000, 'Area urbana mixta con comercio y vivienda');
-- id_zona resultante: 3

-- Sub-zonas de Zona Norte, para demostrar la jerarquia en la CTE recursiva
INSERT INTO OCN.zona (nombre_zona, id_tipo_zona, poblacion_aprox, descripcion_zona, id_zona_padre)
VALUES ('Zona Norte - Sector 1', 1, 5000, 'Subdivision norte', 1);
INSERT INTO OCN.zona (nombre_zona, id_tipo_zona, poblacion_aprox, descripcion_zona, id_zona_padre)
VALUES ('Zona Norte - Sector 2', 1, 7000, 'Subdivision norte', 1);
-- id_zona resultantes: 4 y 5

-- Levantamiento para Zona Centro (id_zona = 3)
INSERT INTO OCN.levantamiento (fecha, descripcion_levantamiento, nombre_equipo, id_zona, num_integrantes)
VALUES ('2026-01-20', 'Levantamiento inicial zona centro', 'Equipo C', 3, 5);
-- id_levantamiento resultante: 3

-- Detecciones adicionales (las originales fueron id 1 y 2)
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-11', 'Diaria', 'alta', 'Segundo reporte de la misma zona', 'Vecino sector 1', 1, 2, 1, 1);          -- id 3, Zona Norte
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-16', 'Semanal', 'baja', 'Reporte adicional zona sur', 'Habitante sector 2', 2, 1, 2, 2);           -- id 4, Zona Sur
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-21', 'Diaria', 'media', 'Reporte inicial zona centro', 'Comerciante local', 3, 1, 1, 2);           -- id 5, Zona Centro
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-22', 'Semanal', 'media', 'Segundo reporte zona centro', 'Vecino de la plaza', 3, 2, 2, 1);         -- id 6, Zona Centro
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-12', 'Diaria', 'alta', 'Tercer reporte zona norte', 'Comite vecinal', 1, 1, 1, 2);                 -- id 7, Zona Norte

-- Recursos comunitarios (uno por zona)
INSERT INTO OCN.recurso_comunitario (nombre_recurso, tipo_recurso, id_zona, capacidad, descripcion_recurso)
VALUES ('Centro Comunitario Norte', 'Centro comunitario', 1, 80, 'Espacio para platicas y canalizacion de casos');   -- id 1
INSERT INTO OCN.recurso_comunitario (nombre_recurso, tipo_recurso, id_zona, capacidad, descripcion_recurso)
VALUES ('DIF Municipal Sur', 'Institucion de gobierno', 2, 50, 'Atencion social y canalizacion institucional');      -- id 2
INSERT INTO OCN.recurso_comunitario (nombre_recurso, tipo_recurso, id_zona, capacidad, descripcion_recurso)
VALUES ('Casa de la Cultura Centro', 'Centro comunitario', 3, 120, 'Actividades comunitarias y talleres');           -- id 3

-- 15 intervenciones: Zona Norte (det 1,3,7) / Zona Sur (det 2,4) / Zona Centro (det 5,6)
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (1, 1, 'Visita de verificacion', 'Verificacion de postes sin luz', 'Ana Torres', '2026-01-12', '2026-01-13', 'Completada', DATEADD(DAY,-40,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (1, NULL, 'Platica informativa', 'Platica sobre seguridad vial nocturna', 'Luis Prado', '2026-02-20', NULL, 'Planeada', DATEADD(DAY,-5,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (3, 1, 'Canalizacion a recurso comunitario', 'Canalizacion a centro comunitario norte', 'Ana Torres', '2026-01-18', '2026-01-19', 'Completada', DATEADD(DAY,-30,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (3, NULL, 'Visita de verificacion', 'Segunda visita de seguimiento', 'Marco Diaz', '2026-02-25', NULL, 'EnProceso', DATEADD(DAY,-10,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (7, 1, 'Referencia a institucion', 'Referencia a alumbrado publico municipal', 'Ana Torres', '2026-03-01', NULL, 'Planeada', DATEADD(DAY,-20,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (7, NULL, 'Platica informativa', 'Platica comunitaria sobre iluminacion', 'Luis Prado', '2026-03-05', NULL, 'Planeada', DATEADD(DAY,-3,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (2, 2, 'Canalizacion a recurso comunitario', 'Canalizacion a DIF para manejo de residuos', 'Carla Nunez', '2026-01-22', '2026-01-23', 'Completada', DATEADD(DAY,-35,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (2, NULL, 'Visita de verificacion', 'Verificacion de limpieza de calles', 'Jorge Salas', '2026-02-28', NULL, 'EnProceso', DATEADD(DAY,-12,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (4, 2, 'Platica informativa', 'Platica sobre manejo de basura', 'Carla Nunez', '2026-03-02', NULL, 'Planeada', DATEADD(DAY,-6,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (4, NULL, 'Referencia a institucion', 'Referencia a servicios municipales', 'Jorge Salas', '2026-03-10', NULL, 'Planeada', DATEADD(DAY,-2,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (5, 3, 'Visita de verificacion', 'Verificacion de reporte inicial', 'Sofia Ramos', '2026-01-25', '2026-01-26', 'Completada', DATEADD(DAY,-32,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (5, NULL, 'Canalizacion a recurso comunitario', 'Canalizacion a casa de la cultura', 'Sofia Ramos', '2026-02-27', NULL, 'EnProceso', DATEADD(DAY,-15,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (6, 3, 'Platica informativa', 'Platica sobre convivencia comunitaria', 'Pedro Villa', '2026-03-03', NULL, 'Planeada', DATEADD(DAY,-4,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (6, NULL, 'Visita de verificacion', 'Verificacion de seguimiento', 'Pedro Villa', '2026-02-28', NULL, 'EnProceso', DATEADD(DAY,-18,GETDATE()));
INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, fecha_ejecucion, estado, fecha_creacion)
VALUES (5, 3, 'Referencia a institucion', 'Referencia a proteccion civil', 'Sofia Ramos', '2026-01-30', '2026-01-31', 'Completada', DATEADD(DAY,-25,GETDATE()));
go

/* =========================================================================
   PROCEDIMIENTOS ALMACENADOS
   ========================================================================= */

IF OBJECT_ID('OCN.sp_intervencion_insertar') IS NOT NULL DROP PROCEDURE OCN.sp_intervencion_insertar;
go
CREATE PROCEDURE OCN.sp_intervencion_insertar
    @id_deteccion INT,
    @id_recurso INT = NULL,
    @tipo_intervencion VARCHAR(100),
    @descripcion_intervencion VARCHAR(255),
    @responsable VARCHAR(100),
    @fecha_planeada DATETIME,
    @estado VARCHAR(20) = 'Planeada'
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, estado)
    VALUES (@id_deteccion, @id_recurso, @tipo_intervencion, @descripcion_intervencion, @responsable, @fecha_planeada, @estado);

    SELECT SCOPE_IDENTITY() AS id_intervencion_creada;
END
go

IF OBJECT_ID('OCN.sp_intervencion_buscar') IS NOT NULL DROP PROCEDURE OCN.sp_intervencion_buscar;
go
CREATE PROCEDURE OCN.sp_intervencion_buscar
    @id_zona INT = NULL,
    @estado VARCHAR(20) = NULL,
    @tipo_intervencion VARCHAR(100) = NULL,
    @fecha_desde DATETIME = NULL,
    @fecha_hasta DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sql NVARCHAR(MAX);
    DECLARE @where NVARCHAR(MAX) = N' WHERE 1=1 ';

    IF @id_zona IS NOT NULL
        SET @where += N' AND z.id_zona = @p_id_zona ';
    IF @estado IS NOT NULL
        SET @where += N' AND i.estado = @p_estado ';
    IF @tipo_intervencion IS NOT NULL
        SET @where += N' AND i.tipo_intervencion = @p_tipo_intervencion ';
    IF @fecha_desde IS NOT NULL
        SET @where += N' AND i.fecha_planeada >= @p_fecha_desde ';
    IF @fecha_hasta IS NOT NULL
        SET @where += N' AND i.fecha_planeada <= @p_fecha_hasta ';

    SET @sql = N'
        SELECT i.id_intervencion, i.tipo_intervencion, i.estado, i.fecha_planeada,
               z.nombre_zona, p.nombre_problematica, i.responsable
        FROM OCN.intervencion i
        INNER JOIN OCN.deteccion d ON i.id_deteccion = d.id_deteccion
        INNER JOIN OCN.levantamiento l ON d.id_levantamiento = l.id_levantamiento
        INNER JOIN OCN.zona z ON l.id_zona = z.id_zona
        INNER JOIN OCN.problematica p ON d.id_problematica = p.id_problematica'
        + @where + N' ORDER BY i.fecha_planeada DESC;';

    EXEC sp_executesql @sql,
        N'@p_id_zona INT, @p_estado VARCHAR(20), @p_tipo_intervencion VARCHAR(100), @p_fecha_desde DATETIME, @p_fecha_hasta DATETIME',
        @p_id_zona = @id_zona, @p_estado = @estado, @p_tipo_intervencion = @tipo_intervencion,
        @p_fecha_desde = @fecha_desde, @p_fecha_hasta = @fecha_hasta;
END
go

 EXEC OCN.sp_intervencion_buscar @estado = 'Planeada';
 EXEC OCN.sp_intervencion_buscar @id_zona = 1, @estado = 'Completada';

/* =========================================================================
   TRANSACCIONES Y MANEJO DE ERRORES
   ========================================================================= */

IF OBJECT_ID('OCN.sp_intervencion_registrar_completa') IS NOT NULL DROP PROCEDURE OCN.sp_intervencion_registrar_completa;
go
CREATE PROCEDURE OCN.sp_intervencion_registrar_completa
    @id_deteccion INT,
    @id_recurso INT = NULL,
    @tipo_intervencion VARCHAR(100),
    @descripcion_intervencion VARCHAR(255),
    @responsable VARCHAR(100),
    @fecha_planeada DATETIME,
    @estado VARCHAR(20),
    @id_intervencion_generada INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM OCN.deteccion WHERE id_deteccion = @id_deteccion)
            THROW 50001, 'La deteccion indicada no existe.', 1;

        IF @id_recurso IS NOT NULL AND NOT EXISTS (SELECT 1 FROM OCN.recurso_comunitario WHERE id_recurso = @id_recurso)
            THROW 50002, 'El recurso comunitario indicado no existe.', 1;

        IF @estado NOT IN ('Planeada','EnProceso','Completada')
            THROW 50003, 'Estado de intervencion invalido.', 1;

        INSERT INTO OCN.intervencion (id_deteccion, id_recurso, tipo_intervencion, descripcion_intervencion, responsable, fecha_planeada, estado)
        VALUES (@id_deteccion, @id_recurso, @tipo_intervencion, @descripcion_intervencion, @responsable, @fecha_planeada, @estado);

        SET @id_intervencion_generada = SCOPE_IDENTITY();

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        INSERT INTO OCN.error_log (procedimiento, mensaje_error, numero_error, severidad_error, estado_error, linea_error)
        VALUES (OBJECT_NAME(@@PROCID), ERROR_MESSAGE(), ERROR_NUMBER(), ERROR_SEVERITY(), ERROR_STATE(), ERROR_LINE());

        SET @id_intervencion_generada = NULL;
        THROW;
    END CATCH
END
go

-- Ejemplo exitoso:
 DECLARE @nuevo INT;
 EXEC OCN.sp_intervencion_registrar_completa 1, 1, 'Visita de verificacion', 'Prueba OK', 'Test User', '2026-04-01', 'Planeada', @nuevo OUTPUT;
 SELECT @nuevo;

 --Ejemplo que provoca error y se registra en error_log (deteccion inexistente):
 DECLARE @nuevo2 INT;
 BEGIN TRY
     EXEC OCN.sp_intervencion_registrar_completa 9999, NULL, 'Visita de verificacion', 'Prueba error', 'Test User', '2026-04-01', 'Planeada', @nuevo2 OUTPUT;
 END TRY
 BEGIN CATCH
     SELECT ERROR_MESSAGE() AS mensaje_capturado;
 END CATCH
 SELECT * FROM OCN.error_log;

/* =========================================================================
   DESENCADENADORES (TRIGGERS)
   ========================================================================= */

-- Trigger 1: audita cada cambio de estado
IF OBJECT_ID('OCN.trg_intervencion_auditoria_estado') IS NOT NULL DROP TRIGGER OCN.trg_intervencion_auditoria_estado;
go
CREATE TRIGGER OCN.trg_intervencion_auditoria_estado
ON OCN.intervencion
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    IF UPDATE(estado)
    BEGIN
        INSERT INTO OCN.intervencion_auditoria (id_intervencion, estado_anterior, estado_nuevo)
        SELECT i.id_intervencion, d.estado, i.estado
        FROM inserted i
        INNER JOIN deleted d ON i.id_intervencion = d.id_intervencion
        WHERE i.estado <> d.estado;
    END
END
go

-- Trigger 2: impide eliminar intervenciones Completadas
-- (la FK con ON DELETE CASCADE en intervencion_auditoria se encarga
--  de limpiar el historial de auditoria automaticamente)
IF OBJECT_ID('OCN.trg_intervencion_bloquear_borrado_completada') IS NOT NULL DROP TRIGGER OCN.trg_intervencion_bloquear_borrado_completada;
go
CREATE TRIGGER OCN.trg_intervencion_bloquear_borrado_completada
ON OCN.intervencion
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted WHERE estado = 'Completada')
    BEGIN
        RAISERROR('No se permite eliminar intervenciones en estado Completada.', 16, 1);
        RETURN;
    END

    DELETE i
    FROM OCN.intervencion i
    INNER JOIN deleted d ON i.id_intervencion = d.id_intervencion;
END
go

-- Pruebas:
 UPDATE OCN.intervencion SET estado = 'EnProceso' WHERE id_intervencion = 2;
 SELECT * FROM OCN.intervencion_auditoria;
 DELETE FROM OCN.intervencion WHERE id_intervencion = 1;              -- debe fallar (Completada)
 DELETE FROM OCN.intervencion WHERE id_intervencion = 2;              -- debe funcionar (EnProceso)

/* =========================================================================
   CURSOR Y ALTERNATIVA SET-BASED
   ========================================================================= */

IF OBJECT_ID('OCN.sp_intervencion_escalar_cursor') IS NOT NULL DROP PROCEDURE OCN.sp_intervencion_escalar_cursor;
go
CREATE PROCEDURE OCN.sp_intervencion_escalar_cursor
    @dias_antiguedad INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @id_intervencion INT;

    DECLARE cur_intervenciones_pendientes CURSOR LOCAL FAST_FORWARD FOR
        SELECT id_intervencion
        FROM OCN.intervencion
        WHERE estado = 'Planeada'
          AND DATEDIFF(DAY, fecha_creacion, GETDATE()) > @dias_antiguedad;

    OPEN cur_intervenciones_pendientes;
    FETCH NEXT FROM cur_intervenciones_pendientes INTO @id_intervencion;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        UPDATE OCN.intervencion
        SET estado = 'EnProceso',
            fecha_actualizacion = GETDATE()
        WHERE id_intervencion = @id_intervencion;

        FETCH NEXT FROM cur_intervenciones_pendientes INTO @id_intervencion;
    END

    CLOSE cur_intervenciones_pendientes;
    DEALLOCATE cur_intervenciones_pendientes;
END
go

IF OBJECT_ID('OCN.sp_intervencion_escalar_setbased') IS NOT NULL DROP PROCEDURE OCN.sp_intervencion_escalar_setbased;
go
CREATE PROCEDURE OCN.sp_intervencion_escalar_setbased
    @dias_antiguedad INT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE OCN.intervencion
    SET estado = 'EnProceso',
        fecha_actualizacion = GETDATE()
    WHERE estado = 'Planeada'
      AND DATEDIFF(DAY, fecha_creacion, GETDATE()) > @dias_antiguedad;
END
go


/* =========================================================================
   CTE (una simple + una recursiva)
   ========================================================================= */

;WITH cte_intervenciones_por_zona AS
(
    SELECT z.id_zona, z.nombre_zona,
           COUNT(i.id_intervencion) AS total_intervenciones,
           SUM(CASE WHEN i.estado = 'Completada' THEN 1 ELSE 0 END) AS completadas
    FROM OCN.zona z
    LEFT JOIN OCN.levantamiento l ON l.id_zona = z.id_zona
    LEFT JOIN OCN.deteccion d ON d.id_levantamiento = l.id_levantamiento
    LEFT JOIN OCN.intervencion i ON i.id_deteccion = d.id_deteccion
    GROUP BY z.id_zona, z.nombre_zona
)
SELECT * FROM cte_intervenciones_por_zona ORDER BY total_intervenciones DESC;
go

;WITH cte_jerarquia_zonas AS
(
    SELECT id_zona, nombre_zona, id_zona_padre, 0 AS nivel,
           CAST(nombre_zona AS VARCHAR(500)) AS ruta
    FROM OCN.zona
    WHERE id_zona_padre IS NULL

    UNION ALL

    SELECT z.id_zona, z.nombre_zona, z.id_zona_padre, cte.nivel + 1,
           CAST(cte.ruta + ' > ' + z.nombre_zona AS VARCHAR(500))
    FROM OCN.zona z
    INNER JOIN cte_jerarquia_zonas cte ON z.id_zona_padre = cte.id_zona
)
SELECT * FROM cte_jerarquia_zonas ORDER BY ruta;
go

/* =========================================================================
   SUBCONSULTAS (una simple + una correlacionada)
   ========================================================================= */

SELECT z.nombre_zona, COUNT(i.id_intervencion) AS total
FROM OCN.zona z
INNER JOIN OCN.levantamiento l ON l.id_zona = z.id_zona
INNER JOIN OCN.deteccion d ON d.id_levantamiento = l.id_levantamiento
INNER JOIN OCN.intervencion i ON i.id_deteccion = d.id_deteccion
GROUP BY z.nombre_zona
HAVING COUNT(i.id_intervencion) > (
    SELECT AVG(cnt * 1.0) FROM (
        SELECT COUNT(i2.id_intervencion) AS cnt
        FROM OCN.zona z2
        INNER JOIN OCN.levantamiento l2 ON l2.id_zona = z2.id_zona
        INNER JOIN OCN.deteccion d2 ON d2.id_levantamiento = l2.id_levantamiento
        INNER JOIN OCN.intervencion i2 ON i2.id_deteccion = d2.id_deteccion
        GROUP BY z2.id_zona
    ) AS sub
);
go

SELECT i.id_intervencion, i.tipo_intervencion, i.estado, z.nombre_zona,
       DATEDIFF(DAY, i.fecha_creacion, GETDATE()) AS dias_abierta
FROM OCN.intervencion i
INNER JOIN OCN.deteccion d ON i.id_deteccion = d.id_deteccion
INNER JOIN OCN.levantamiento l ON d.id_levantamiento = l.id_levantamiento
INNER JOIN OCN.zona z ON l.id_zona = z.id_zona
WHERE DATEDIFF(DAY, i.fecha_creacion, GETDATE()) > (
    SELECT AVG(DATEDIFF(DAY, i2.fecha_creacion, GETDATE()) * 1.0)
    FROM OCN.intervencion i2
    INNER JOIN OCN.deteccion d2 ON i2.id_deteccion = d2.id_deteccion
    INNER JOIN OCN.levantamiento l2 ON d2.id_levantamiento = l2.id_levantamiento
    WHERE l2.id_zona = l.id_zona
);
go

/* =========================================================================
   TEMA COMPLEMENTARIO: FUNCIONES
   ========================================================================= */

IF OBJECT_ID('OCN.fn_dias_intervencion_abierta') IS NOT NULL DROP FUNCTION OCN.fn_dias_intervencion_abierta;
go
CREATE FUNCTION OCN.fn_dias_intervencion_abierta (@id_intervencion INT)
RETURNS INT
AS
BEGIN
    DECLARE @dias INT;
    SELECT @dias = DATEDIFF(DAY, fecha_creacion, ISNULL(fecha_ejecucion, GETDATE()))
    FROM OCN.intervencion
    WHERE id_intervencion = @id_intervencion;
    RETURN @dias;
END
go

IF OBJECT_ID('OCN.fn_intervenciones_por_estado') IS NOT NULL DROP FUNCTION OCN.fn_intervenciones_por_estado;
go
CREATE FUNCTION OCN.fn_intervenciones_por_estado (@estado VARCHAR(20))
RETURNS TABLE
AS
RETURN
(
    SELECT i.id_intervencion, i.tipo_intervencion, i.responsable, i.fecha_planeada, z.nombre_zona
    FROM OCN.intervencion i
    INNER JOIN OCN.deteccion d ON i.id_deteccion = d.id_deteccion
    INNER JOIN OCN.levantamiento l ON d.id_levantamiento = l.id_levantamiento
    INNER JOIN OCN.zona z ON l.id_zona = z.id_zona
    WHERE i.estado = @estado
);
go

SELECT z.nombre_zona, i.id_intervencion, i.tipo_intervencion, i.estado,
       DATEDIFF(DAY, i.fecha_creacion, GETDATE()) AS dias_abierta,
       RANK() OVER (PARTITION BY z.id_zona ORDER BY DATEDIFF(DAY, i.fecha_creacion, GETDATE()) DESC) AS ranking_antiguedad
FROM OCN.intervencion i
INNER JOIN OCN.deteccion d ON i.id_deteccion = d.id_deteccion
INNER JOIN OCN.levantamiento l ON d.id_levantamiento = l.id_levantamiento
INNER JOIN OCN.zona z ON l.id_zona = z.id_zona
ORDER BY z.nombre_zona, ranking_antiguedad;
go

-- Ejemplos de uso de las funciones:
 SELECT OCN.fn_dias_intervencion_abierta(2) AS dias_abierta_intervencion_2;
 SELECT * FROM OCN.fn_intervenciones_por_estado('Planeada');