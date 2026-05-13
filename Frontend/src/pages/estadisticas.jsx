import { useEffect, useState } from 'react'
import { getEstadisticasZona, getLevantamientosFuente } from '../services/api'

export default function Estadisticas() {
  const [zonas, setZonas]         = useState([])
  const [fuentes, setFuentes]     = useState([])
  const [loading, setLoading]     = useState(true)
  const [error, setError]         = useState(null)

  useEffect(() => {
    Promise.all([getEstadisticasZona(), getLevantamientosFuente()])
      .then(([z, f]) => { setZonas(z); setFuentes(f) })
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  return (
    <>
      <div className="page-header">
        <h2>Estadísticas y levantamientos</h2>
        <p>
          Vistas:{' '}
          <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>vw_estadisticas_problematicas_por_zona</code>
          {' · '}
          <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>vw_levantamientos_con_fuente</code>
        </p>
      </div>

      {loading && <div className="spinner"><div className="spin" /> Consultando vistas…</div>}
      {error   && <div className="alert alert-error">{error}</div>}

      {!loading && !error && (
        <>
          <div className="card">
            <div className="card-title">◧ Problemáticas por zona e intensidad</div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Zona</th>
                    <th>Tipo</th>
                    <th>Población</th>
                    <th>Categoría</th>
                    <th>Nivel prioridad</th>
                    <th>Total</th>
                    <th>Alta</th>
                    <th>Media</th>
                    <th>Baja</th>
                  </tr>
                </thead>
                <tbody>
                  {zonas.map((z, i) => (
                    <tr key={i}>
                      <td style={{ fontWeight: 600, color: 'var(--txt)' }}>{z.zona}</td>
                      <td><span className="badge badge-blue">{z.tipo_zona}</span></td>
                      <td>{Number(z.poblacion_aproximada).toLocaleString()}</td>
                      <td>{z.categoria_problematica}</td>
                      <td>
                        <span className={`badge badge-${z.nivel_prioridad?.toLowerCase() === 'alta' ? 'alta' : z.nivel_prioridad?.toLowerCase() === 'media' ? 'media' : 'baja'}`}>
                          {z.nivel_prioridad}
                        </span>
                      </td>
                      <td style={{ fontWeight: 700 }}>{z.total_detecciones}</td>
                      <td style={{ color: 'var(--red)' }}>{z.detecciones_intensidad_alta}</td>
                      <td style={{ color: 'var(--amber)' }}>{z.detecciones_intensidad_media}</td>
                      <td style={{ color: 'var(--green)' }}>{z.detecciones_intensidad_baja}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>

          <div className="card">
            <div className="card-title">◈ Levantamientos con fuente y grupo etario</div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Equipo</th>
                    <th>Fecha</th>
                    <th>Zona</th>
                    <th>Método</th>
                    <th>Confiabilidad</th>
                    <th>Grupo etario</th>
                    <th>Rango edad</th>
                    <th>Frecuencia</th>
                  </tr>
                </thead>
                <tbody>
                  {fuentes.map((f, i) => (
                    <tr key={i}>
                      <td style={{ fontWeight: 600, color: 'var(--txt)' }}>{f.equipo_levantamiento}</td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        {f.fecha_levantamiento ? new Date(f.fecha_levantamiento).toLocaleDateString('es-MX') : '—'}
                      </td>
                      <td>{f.zona_cubierta}</td>
                      <td>{f.metodo_recoleccion}</td>
                      <td>
                        <span className={`badge badge-${f.nivel_confiabilidad?.toLowerCase() === 'alta' ? 'alta' : 'media'}`}>
                          {f.nivel_confiabilidad}
                        </span>
                      </td>
                      <td>{f.grupo_etario_participante}</td>
                      <td>{f.rango_edad_participante}</td>
                      <td>{f.frecuencia_reporte}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </>
  )
}