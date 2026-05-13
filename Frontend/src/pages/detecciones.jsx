import { useEffect, useState } from 'react'
import { getReporteDetecciones } from '../services/api'

export default function Detecciones() {
  const [data, setData]       = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState(null)
  const [search, setSearch]   = useState('')

  useEffect(() => {
    getReporteDetecciones()
      .then(setData)
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }, [])

  const filtered = data.filter(d =>
    [d.zona, d.problematica, d.categoria_problematica, d.grupo_afectado]
      .some(v => v?.toLowerCase().includes(search.toLowerCase()))
  )

  const badgeClass = v => {
    const val = v?.toLowerCase()
    if (val === 'alta') return 'badge-alta'
    if (val === 'media') return 'badge-media'
    return 'badge-baja'
  }

  return (
    <>
      <div className="page-header">
        <h2>Detecciones por zona</h2>
        <p>Vista: <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>OCN.vw_reporte_detecciones_por_zona</code></p>
      </div>

      <div className="card">
        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem' }}>
          <div className="form-group" style={{ flex: 1 }}>
            <label>Buscar</label>
            <input
              type="text"
              placeholder="Zona, problemática, grupo…"
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
          <div style={{ display: 'flex', alignItems: 'flex-end' }}>
            <span style={{ fontSize: '.8rem', color: 'var(--txt-muted)', paddingBottom: '.6rem' }}>
              {filtered.length} registros
            </span>
          </div>
        </div>

        {loading && <div className="spinner"><div className="spin" /> Ejecutando vista…</div>}
        {error   && <div className="alert alert-error">{error}</div>}
        {!loading && !error && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Folio</th>
                  <th>Fecha</th>
                  <th>Zona</th>
                  <th>Tipo zona</th>
                  <th>Problemática</th>
                  <th>Categoría</th>
                  <th>Prioridad</th>
                  <th>Frecuencia</th>
                  <th>Intensidad</th>
                  <th>Grupo afectado</th>
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 ? (
                  <tr><td colSpan={10} className="empty">Sin resultados</td></tr>
                ) : filtered.map(d => (
                  <tr key={d.folio_deteccion}>
                    <td style={{ fontFamily: 'monospace', color: 'var(--txt-muted)' }}>{d.folio_deteccion}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      {d.fecha_registro ? new Date(d.fecha_registro).toLocaleDateString('es-MX') : '—'}
                    </td>
                    <td style={{ fontWeight: 600, color: 'var(--txt)' }}>{d.zona}</td>
                    <td><span className="badge badge-blue">{d.tipo_zona}</span></td>
                    <td>{d.problematica}</td>
                    <td>{d.categoria_problematica}</td>
                    <td><span className={`badge ${badgeClass(d.prioridad)}`}>{d.prioridad}</span></td>
                    <td>{d.frecuencia_ocurrencia}</td>
                    <td><span className={`badge ${badgeClass(d.intensidad_problema)}`}>{d.intensidad_problema}</span></td>
                    <td>{d.grupo_afectado}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </>
  )
}