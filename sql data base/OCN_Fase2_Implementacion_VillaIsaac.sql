CREATE  DATABASE  OCN_DB;
go

USE OCN_DB;
go

CREATE SCHEMA OCN;
go

CREATE TABLE OCN.tipo_zona
(
	id_tipo_zona INTEGER PRIMARY KEY IDENTITY(1,1),
	nombre_tipo_zona VARCHAR(100) NOT NULL,
	descripcion_tipo_zona VARCHAR(255) NOT NULL
);
go

CREATE TABLE OCN.zona
(
	id_zona INTEGER PRIMARY KEY IDENTITY(1,1),
	nombre_zona VARCHAR(100) NOT NULL,
	id_tipo_zona INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.tipo_zona(id_tipo_zona),
	poblacion_aprox INTEGER NOT NULL,
	descripcion_zona VARCHAR(255) NOT NULL
);
go

CREATE TABLE OCN.levantamiento
(
	id_levantamiento INTEGER PRIMARY KEY IDENTITY(1,1),
	fecha DATETIME NOT NULL,
	descripcion_levantamiento VARCHAR(255) NOT NULL,
	nombre_equipo VARCHAR(100) NOT NULL,
	id_zona INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.zona(id_zona),
	num_integrantes INTEGER NOT NULL
);
go

CREATE TABLE OCN.tipo_fuente
(
	id_tipo_fuente INTEGER PRIMARY KEY IDENTITY(1,1),
	nombre_tipo_fuente VARCHAR(100) NOT NULL,
	descripcion_tipo_fuente VARCHAR(255) NOT NULL
);
go

CREATE TABLE OCN.fuente
(
	id_fuente INTEGER PRIMARY KEY IDENTITY(1,1),
	id_tipo_fuente INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.tipo_fuente(id_tipo_fuente),
	confiabilidad VARCHAR(100) NOT NULL
);
go

CREATE TABLE OCN.problematica
(
	id_problematica INTEGER PRIMARY KEY IDENTITY(1,1),
	nombre_problematica VARCHAR(100) NOT NULL,
	categoria VARCHAR(100) NOT NULL,
	nivel_prioridad VARCHAR(100) NOT NULL,
	descripcion_problematica VARCHAR(255) NOT NULL
);
go

CREATE TABLE OCN.grupo_etario
(
	id_grupoetario INTEGER PRIMARY KEY IDENTITY(1,1),
	rango_edad VARCHAR(50) NOT NULL,
	nombre_grupo VARCHAR(100) NOT NULL
);
go


CREATE TABLE OCN.deteccion
(
	id_deteccion INTEGER PRIMARY KEY IDENTITY(1,1),
	fecha_registro DATETIME NOT NULL,
	frecuencia VARCHAR(100) NOT NULL,
	intensidad VARCHAR(100) NOT NULL,
	observaciones_generales VARCHAR(255) NOT NULL,
	descripcion_anonima VARCHAR(255) NOT NULL,
	id_levantamiento INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.levantamiento(id_levantamiento),
	id_problematica INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.problematica(id_problematica),
	id_fuente INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.fuente(id_fuente),
	id_grupoetario INTEGER NOT NULL FOREIGN KEY REFERENCES OCN.grupo_etario(id_grupoetario)
);
go

INSERT INTO OCN.tipo_zona (nombre_tipo_zona, descripcion_tipo_zona)
VALUES ('Urbana', 'Zona con alta densidad poblacional y servicios básicos');
INSERT INTO OCN.tipo_zona (nombre_tipo_zona, descripcion_tipo_zona)
VALUES ('Rural', 'Zona con baja densidad y acceso limitado a servicios');

INSERT INTO OCN.tipo_fuente (nombre_tipo_fuente, descripcion_tipo_fuente)
VALUES ('Encuesta directa', 'Información recopilada mediante entrevistas a habitantes');
INSERT INTO OCN.tipo_fuente (nombre_tipo_fuente, descripcion_tipo_fuente)
VALUES ('Observación de campo', 'Información obtenida por recorridos del equipo');

INSERT INTO OCN.grupo_etario (rango_edad, nombre_grupo)
VALUES ('0-17', 'Niños y adolescentes');
INSERT INTO OCN.grupo_etario (rango_edad, nombre_grupo)
VALUES ('18-64', 'Adultos');

INSERT INTO OCN.problematica (nombre_problematica, categoria, nivel_prioridad, descripcion_problematica)
VALUES ('Falta de alumbrado', 'Infraestructura', 'Alta', 'Colonias sin luz durante las noches');
INSERT INTO OCN.problematica (nombre_problematica, categoria, nivel_prioridad, descripcion_problematica)
VALUES ('Basura en calles', 'Salubridad', 'Media', 'Acumulación de residuos en vía pública');

INSERT INTO OCN.zona (nombre_zona, id_tipo_zona, poblacion_aprox, descripcion_zona)
VALUES ('Zona Norte', 1, 12000, 'Área urbana con alta densidad poblacional');
INSERT INTO OCN.zona (nombre_zona, id_tipo_zona, poblacion_aprox, descripcion_zona)
VALUES ('Zona Sur', 2, 4500, 'Área rural con acceso limitado a servicios');

INSERT INTO OCN.fuente (id_tipo_fuente, confiabilidad)
VALUES (1, 'Alta');
INSERT INTO OCN.fuente (id_tipo_fuente, confiabilidad)
VALUES (2, 'Media');

INSERT INTO OCN.levantamiento (fecha, descripcion_levantamiento, nombre_equipo, id_zona, num_integrantes)
VALUES ('2026-01-10', 'Levantamiento inicial zona norte', 'Equipo A', 1, 4);
INSERT INTO OCN.levantamiento (fecha, descripcion_levantamiento, nombre_equipo, id_zona, num_integrantes)
VALUES ('2026-01-15', 'Levantamiento inicial zona sur', 'Equipo B', 2, 3);

INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-10', 'Diaria', 'alta', 'Reportado por múltiples habitantes', 'Residente sector 3', 1, 1, 1, 2);
INSERT INTO OCN.deteccion (fecha_registro, frecuencia, intensidad, observaciones_generales, descripcion_anonima, id_levantamiento, id_problematica, id_fuente, id_grupoetario)
VALUES ('2026-01-15', 'Semanal', 'media', 'Observado en recorrido de campo', 'Habitante zona sur', 2, 2, 2, 1);

SELECT * FROM OCN.tipo_zona;

SELECT * FROM OCN.tipo_fuente;

SELECT * FROM OCN.grupo_etario;

SELECT * FROM OCN.problematica;

SELECT * FROM OCN.zona;

SELECT * FROM OCN.fuente;

SELECT * FROM OCN.levantamiento;

SELECT * FROM OCN.deteccion;