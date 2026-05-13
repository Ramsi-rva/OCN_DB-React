import { useEffect, useState } from 'react'
import { getReporteDetecciones, getEstadisticasZona } from '../services/api'

export default function Dashboard({ setPage, dbStatus }) {
  const [stats, setStats]   = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    Promise.all([getReporteDetecciones(), getEstadisticasZona()])
      .then(([detecciones, estadisticas]) => {
        const total    = detecciones.length
        const alta     = detecciones.filter(d => d.intensidad_problema?.toLowerCase() === 'alta').length
        const zonas    = [...new Set(detecciones.map(d => d.zona))].length
        const cats     = [...new Set(detecciones.map(d => d.categoria_problematica))].length
        setStats({ total, alta, zonas, cats, detecciones, estadisticas })
      })
      .catch(() => setStats(null))
      .finally(() => setLoading(false))
  }, [])

  return (
    <>
      <div className="page-header">
        <h2>Dashboard</h2>
        <p>Vista general del sistema OCN — datos en tiempo real desde la base de datos</p>
      </div>

      {/* connection hint when offline */}
      {dbStatus === 'error' && (
        <div className="alert alert-error">
          ⚠ No se pudo conectar con la API. Asegúrate de que el servidor Node.js esté corriendo en el puerto 3001.
        </div>
      )}

      {loading ? (
        <div className="spinner"><div className="spin" /> Cargando datos…</div>
      ) : stats ? (
        <>
          <div className="stat-grid">
            <div className="stat-card">
              <div className="stat-value">{stats.total}</div>
              <div className="stat-label">Total detecciones</div>
            </div>
            <div className="stat-card">
              <div className="stat-value" style={{ color: 'var(--red)' }}>{stats.alta}</div>
              <div className="stat-label">Intensidad alta</div>
            </div>
            <div className="stat-card">
              <div className="stat-value" style={{ color: 'var(--accent)' }}>{stats.zonas}</div>
              <div className="stat-label">Zonas cubiertas</div>
            </div>
            <div className="stat-card">
              <div className="stat-value" style={{ color: 'var(--green)' }}>{stats.cats}</div>
              <div className="stat-label">Categorías</div>
            </div>
          </div>

          {/* últimas detecciones */}
          <div className="card">
            <div className="card-title">◉ Últimas detecciones registradas</div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>#</th>
                    <th>Zona</th>
                    <th>Problemática</th>
                    <th>Prioridad</th>
                    <th>Intensidad</th>
                    <th>Grupo afectado</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.detecciones.slice(0, 6).map(d => (
                    <tr key={d.folio_deteccion}>
                      <td style={{ color: 'var(--txt-muted)', fontFamily: 'monospace' }}>{d.folio_deteccion}</td>
                      <td>{d.zona}</td>
                      <td>{d.problematica}</td>
                      <td>
                        <span className={`badge badge-${d.prioridad?.toLowerCase() === 'alta' ? 'alta' : d.prioridad?.toLowerCase() === 'media' ? 'media' : 'baja'}`}>
                          {d.prioridad}
                        </span>
                      </td>
                      <td>
                        <span className={`badge badge-${d.intensidad_problema?.toLowerCase()}`}>
                          {d.intensidad_problema}
                        </span>
                      </td>
                      <td>{d.grupo_afectado}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div style={{ marginTop: '1rem' }}>
              <button className="btn btn-ghost" onClick={() => setPage('detecciones')}>
                Ver todas →
              </button>
            </div>
          </div>

          {/* resumen por zona */}
          <div className="card">
            <div className="card-title">◧ Estadísticas por zona</div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Zona</th>
                    <th>Tipo</th>
                    <th>Población</th>
                    <th>Categoría</th>
                    <th>Total</th>
                    <th>Alta</th>
                    <th>Media</th>
                    <th>Baja</th>
                  </tr>
                </thead>
                <tbody>
                  {stats.estadisticas.map((e, i) => (
                    <tr key={i}>
                      <td>{e.zona}</td>
                      <td><span className="badge badge-blue">{e.tipo_zona}</span></td>
                      <td>{Number(e.poblacion_aproximada).toLocaleString()}</td>
                      <td>{e.categoria_problematica}</td>
                      <td style={{ fontWeight: 600 }}>{e.total_detecciones}</td>
                      <td style={{ color: 'var(--red)' }}>{e.detecciones_intensidad_alta}</td>
                      <td style={{ color: 'var(--amber)' }}>{e.detecciones_intensidad_media}</td>
                      <td style={{ color: 'var(--green)' }}>{e.detecciones_intensidad_baja}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      ) : (
        <div className="empty">
          <span className="icon">⚠</span>
          No se pudieron cargar los datos. Verifica la conexión con la API.
        </div>
      )}
    </>
  )
}