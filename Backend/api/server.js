// api/server.js
// Servidor Express que conecta React con SQL Server mediante mssql.
// Expone endpoints que ejecutan las vistas y procedimientos del proyecto OCN.

const express = require('express')
const sql     = require('mssql')
const cors    = require('cors')

const app  = express()
const PORT = 3882

app.use(cors())
app.use(express.json())

// ── Configuración de conexión SQL Server ──────────────────────
// Ajusta server, user y password según tu entorno local.
const config = {
  server: 'localhost',
  port: 1433,
  database: 'OCN_DB',
  user: 'sa',
  password: '123456',
  options: {
    encrypt: false,
    trustServerCertificate: true,
    enableArithAbort: true
  },
}

// Pool de conexiones (se reutiliza en todas las rutas)
let pool

async function getPool() {
  if (!pool) {
    pool = await sql.connect(config)
  }
  return pool
}

// ── Utilidad para manejar errores ─────────────────────────────
function handleError(res, err) {
  console.error('[OCN-API]', err.message)
  res.status(500).json({ message: err.message })
}

// ─────────────────────────────────────────────────────────────
// GET /api/ping  →  verifica conexión
// ─────────────────────────────────────────────────────────────
app.get('/api/ping', async (req, res) => {
  try {
    const p      = await getPool()
    const result = await p.request().query('select 1 as ok')
    res.json({ ok: true, server: config.server, database: config.database })
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/vistas/reporte-detecciones
// Ejecuta: select * from OCN.vw_reporte_detecciones_por_zona
// ─────────────────────────────────────────────────────────────
app.get('/api/vistas/reporte-detecciones', async (req, res) => {
  try {
    const p      = await getPool()
    const result = await p.request().query(`
      select
        folio_deteccion,
        zona,
        tipo_zona,
        problematica,
        categoria_problematica,
        prioridad,
        frecuencia_ocurrencia,
        intensidad_problema,
        grupo_afectado,
        observaciones,
        fecha_registro
      from OCN.vw_reporte_detecciones_por_zona
    `)
    res.json(result.recordset)
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/vistas/estadisticas-zona
// Ejecuta: select * from OCN.vw_estadisticas_problematicas_por_zona
// ─────────────────────────────────────────────────────────────
app.get('/api/vistas/estadisticas-zona', async (req, res) => {
  try {
    const p      = await getPool()
    const result = await p.request().query(`
      select
        zona,
        tipo_zona,
        poblacion_aproximada,
        categoria_problematica,
        nivel_prioridad,
        total_detecciones,
        detecciones_intensidad_alta,
        detecciones_intensidad_media,
        detecciones_intensidad_baja
      from OCN.vw_estadisticas_problematicas_por_zona
      order by total_detecciones desc
    `)
    res.json(result.recordset)
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/vistas/levantamientos-fuente
// Ejecuta: select * from OCN.vw_levantamientos_con_fuente
// ─────────────────────────────────────────────────────────────
app.get('/api/vistas/levantamientos-fuente', async (req, res) => {
  try {
    const p      = await getPool()
    const result = await p.request().query(`
      select
        equipo_levantamiento,
        fecha_levantamiento,
        integrantes_equipo,
        zona_cubierta,
        metodo_recoleccion,
        nivel_confiabilidad,
        grupo_etario_participante,
        rango_edad_participante,
        frecuencia_reporte,
        descripcion_anonima
      from OCN.vw_levantamientos_con_fuente
      order by fecha_levantamiento
    `)
    res.json(result.recordset)
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// POST /api/procedimientos/registrar-deteccion
// Ejecuta: OCN.sp_registrar_deteccion con parámetros del body
// ─────────────────────────────────────────────────────────────
app.post('/api/procedimientos/registrar-deteccion', async (req, res) => {
  const {
    fecha_registro, frecuencia, intensidad, observaciones,
    descripcion_anonima, id_levantamiento, id_problematica,
    id_fuente, id_grupoetario,
  } = req.body

  try {
    const p = await getPool()
    const result = await p.request()
      .input('fecha_registro',      sql.DateTime, new Date(fecha_registro))
      .input('frecuencia',          sql.VarChar(100), frecuencia)
      .input('intensidad',          sql.VarChar(100), intensidad)
      .input('observaciones',       sql.VarChar(255), observaciones)
      .input('descripcion_anonima', sql.VarChar(255), descripcion_anonima)
      .input('id_levantamiento',    sql.Int, parseInt(id_levantamiento))
      .input('id_problematica',     sql.Int, parseInt(id_problematica))
      .input('id_fuente',           sql.Int, parseInt(id_fuente))
      .input('id_grupoetario',      sql.Int, parseInt(id_grupoetario))
      .execute('OCN.sp_registrar_deteccion')

    const msg = result.recordset?.[0]?.resultado ?? 'Detección registrada.'
    res.json({ resultado: msg })
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/procedimientos/detecciones-por-fecha?inicio=&fin=
// Ejecuta: OCN.sp_consultar_detecciones_por_fecha
// ─────────────────────────────────────────────────────────────
app.get('/api/procedimientos/detecciones-por-fecha', async (req, res) => {
  const { inicio, fin } = req.query
  if (!inicio || !fin) {
    return res.status(400).json({ message: 'Se requieren los parámetros inicio y fin.' })
  }
  try {
    const p = await getPool()
    const result = await p.request()
      .input('fecha_inicio', sql.DateTime, new Date(inicio))
      .input('fecha_fin',    sql.DateTime, new Date(fin + 'T23:59:59'))
      .execute('OCN.sp_consultar_detecciones_por_fecha')

    res.json(result.recordset)
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/procedimientos/resumen-zona?zona=
// Ejecuta: OCN.sp_resumen_por_zona
// ─────────────────────────────────────────────────────────────
app.get('/api/procedimientos/resumen-zona', async (req, res) => {
  const idZona = req.query.zona ? parseInt(req.query.zona) : null
  try {
    const p = await getPool()
    const result = await p.request()
      .input('id_zona', sql.Int, idZona)
      .execute('OCN.sp_resumen_por_zona')

    res.json(result.recordset)
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
// GET /api/catalogos  →  datos para poblar los selects del form
// ─────────────────────────────────────────────────────────────
app.get('/api/catalogos', async (req, res) => {
  try {
    const p = await getPool()

    const [lev, prob, fue, grp] = await Promise.all([
      p.request().query('select id_levantamiento, nombre_equipo, fecha from OCN.levantamiento'),
      p.request().query('select id_problematica, nombre_problematica from OCN.problematica'),
      p.request().query(`
        select f.id_fuente, tf.nombre_tipo_fuente, f.confiabilidad
        from OCN.fuente f
        inner join OCN.tipo_fuente tf on f.id_tipo_fuente = tf.id_tipo_fuente
      `),
      p.request().query('select id_grupoetario, nombre_grupo, rango_edad from OCN.grupo_etario'),
    ])

    res.json({
      levantamientos: lev.recordset,
      problematicas:  prob.recordset,
      fuentes:        fue.recordset,
      grupos:         grp.recordset,
    })
  } catch (err) {
    handleError(res, err)
  }
})

// ─────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n  OCN API corriendo en http://localhost:${PORT}`)
  console.log(`  Base de datos: ${config.database} en ${config.server}\n`)
})