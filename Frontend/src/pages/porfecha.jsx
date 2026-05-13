import { useState } from 'react'
import { consultarPorFecha } from '../services/api'

export default function PorFecha() {
  const [inicio, setInicio] = useState('2026-01-01')
  const [fin, setFin]       = useState('2026-12-31')
  const [data, setData]     = useState(null)
  const [loading, setLoading] = useState(false)
  const [error, setError]   = useState(null)

  const buscar = () => {
    if (!inicio || !fin) return
    setLoading(true)
    setError(null)
    consultarPorFecha(inicio, fin)
      .then(setData)
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }

  const badgeClass = v => {
    const val = v?.toLowerCase()
    if (val === 'alta') return 'badge-alta'
    if (val === 'media') return 'badge-media'
    return 'badge-baja'
  }

  return (
    <>
      <div className="page-header">
        <h2>Consulta por rango de fechas</h2>
        <p>Procedimiento: <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>OCN.sp_consultar_detecciones_por_fecha</code></p>
      </div>

      <div className="card">
        <div className="card-title">◷ Parámetros</div>
        <div className="filter-row">
          <div className="form-group">
            <label>Fecha inicio</label>
            <input type="date" value={inicio} onChange={e => setInicio(e.target.value)} />
          </div>
          <div className="form-group">
            <label>Fecha fin</label>
            <input type="date" value={fin} onChange={e => setFin(e.target.value)} />
          </div>
          <button className="btn btn-primary" onClick={buscar} disabled={loading}>
            {loading ? 'Consultando…' : 'Ejecutar'}
          </button>
        </div>

        <div style={{ fontSize: '.78rem', color: 'var(--txt-muted)', marginTop: '-.5rem' }}>
          Ejecuta: <code style={{ color: 'var(--accent)' }}>exec OCN.sp_consultar_detecciones_por_fecha @fecha_inicio='{inicio}', @fecha_fin='{fin}'</code>
        </div>
      </div>

      {loading && <div className="spinner"><div className="spin" /> Ejecutando procedimiento…</div>}
      {error   && <div className="alert alert-error">{error}</div>}

      {data !== null && !loading && (
        <div className="card">
          <div className="card-title">
            Resultados
            <span style={{ marginLeft: 'auto', fontSize: '.8rem', fontWeight: 400, color: 'var(--txt-muted)' }}>
              {data.length} registros encontrados
            </span>
          </div>
          {data.length === 0 ? (
            <div className="empty">
              <span className="icon">○</span>
              No hay detecciones en ese rango de fechas.
            </div>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Folio</th>
                    <th>Fecha</th>
                    <th>Zona</th>
                    <th>Problemática</th>
                    <th>Prioridad</th>
                    <th>Intensidad</th>
                    <th>Frecuencia</th>
                    <th>Grupo afectado</th>
                    <th>Observaciones</th>
                  </tr>
                </thead>
                <tbody>
                  {data.map(d => (
                    <tr key={d.folio}>
                      <td style={{ fontFamily: 'monospace', color: 'var(--txt-muted)' }}>{d.folio}</td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        {d.fecha ? new Date(d.fecha).toLocaleDateString('es-MX') : '—'}
                      </td>
                      <td style={{ fontWeight: 600, color: 'var(--txt)' }}>{d.zona}</td>
                      <td>{d.problematica}</td>
                      <td><span className={`badge ${badgeClass(d.prioridad)}`}>{d.prioridad}</span></td>
                      <td><span className={`badge ${badgeClass(d.intensidad)}`}>{d.intensidad}</span></td>
                      <td>{d.frecuencia}</td>
                      <td>{d.grupo_afectado}</td>
                      <td style={{ color: 'var(--txt-muted)', maxWidth: 220, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {d.observaciones}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </>
  )
}