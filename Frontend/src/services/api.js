// src/services/api.js
// Capa de servicio: centraliza todas las llamadas a la API Node.js
// Cada función corresponde a una vista o procedimiento almacenado del proyecto OCN.

const BASE = '/api'

async function request(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: 'Error desconocido' }))
    throw new Error(err.message || `HTTP ${res.status}`)
  }
  return res.json()
}

// ── Estado de conexión ────────────────────────────────────────
export const ping = () => request('/ping')

// ── Vista 1: reporte general de detecciones por zona ─────────
export const getReporteDetecciones = () =>
  request('/vistas/reporte-detecciones')

// ── Vista 2: estadísticas de problemáticas por zona ──────────
export const getEstadisticasZona = () =>
  request('/vistas/estadisticas-zona')

// ── Vista 3: levantamientos con fuente ───────────────────────
export const getLevantamientosFuente = () =>
  request('/vistas/levantamientos-fuente')

// ── SP 1: registrar nueva detección ──────────────────────────
export const registrarDeteccion = (datos) =>
  request('/procedimientos/registrar-deteccion', {
    method: 'POST',
    body: JSON.stringify(datos),
  })

// ── SP 2: consultar detecciones por rango de fechas ──────────
export const consultarPorFecha = (fechaInicio, fechaFin) =>
  request(`/procedimientos/detecciones-por-fecha?inicio=${fechaInicio}&fin=${fechaFin}`)

// ── SP 3: resumen por zona ────────────────────────────────────
export const getResumenZona = (idZona = null) => {
  const qs = idZona ? `?zona=${idZona}` : ''
  return request(`/procedimientos/resumen-zona${qs}`)
}

// ── Catálogos para el formulario ──────────────────────────────
export const getCatalogos = () => request('/catalogos')

// ── SP dinámico: buscar intervenciones con filtros opcionales ─
export const getIntervenciones = (filtros = {}) => {
  const params = new URLSearchParams(
    Object.fromEntries(Object.entries(filtros).filter(([, v]) => v))
  )
  const qs = params.toString()
  return request(`/procedimientos/intervenciones-buscar${qs ? `?${qs}` : ''}`)
}

// ── SP transaccional: registrar intervención completa ─────────
export const registrarIntervencion = (datos) =>
  request('/procedimientos/registrar-intervencion', {
    method: 'POST',
    body: JSON.stringify(datos),
  })

// ── Catálogos para el formulario de intervenciones ─────────────
export const getCatalogosIntervencion = () => request('/catalogos-intervencion')
// ── Trigger: eliminar intervención (bloqueado si está Completada) ─
export const eliminarIntervencion = (id) =>
  request(`/procedimientos/eliminar-intervencion/${id}`, {
    method: 'DELETE',
  })