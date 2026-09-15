import { useEffect, useState } from 'react'
import { getIntervenciones, getCatalogosIntervencion, eliminarIntervencion } from '../services/api'

const ESTADOS = ['Planeada', 'EnProceso', 'Completada']

export default function Intervenciones({ setPage }) {
  const [data, setData]       = useState([])
  const [zonas, setZonas]     = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError]     = useState(null)
  const [filtros, setFiltros] = useState({ estado: '', id_zona: '' })
  const [deletingId, setDeletingId] = useState(null)
  const [deleteMsg, setDeleteMsg]   = useState(null) // { type, text }

  const cargar = () => {
    setLoading(true)
    setError(null)
    getIntervenciones(filtros)
      .then(setData)
      .catch(e => setError(e.message))
      .finally(() => setLoading(false))
  }

  useEffect(() => {
    getCatalogosIntervencion()
      .then(cat => setZonas(cat.zonas || []))
      .catch(() => setZonas([]))
    cargar()
  }, []) // carga inicial

  const badgeClass = estado => {
    if (estado === 'Completada') return 'badge-baja'   // verde
    if (estado === 'EnProceso')  return 'badge-media'  // ambar
    return 'badge-blue'                                // Planeada
  }

  const eliminar = async (intervencion) => {
    const confirmar = window.confirm(
      `¿Eliminar la intervención #${intervencion.id_intervencion} (${intervencion.tipo_intervencion})?`
    )
    if (!confirmar) return

    setDeletingId(intervencion.id_intervencion)
    setDeleteMsg(null)
    try {
      const res = await eliminarIntervencion(intervencion.id_intervencion)
      setDeleteMsg({ type: 'success', text: res.resultado })
      cargar() // refresca la tabla
    } catch (e) {
      setDeleteMsg({ type: 'error', text: e.message })
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <>
      <div className="page-header">
        <h2>Intervenciones</h2>
        <p>Procedimiento: <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>OCN.sp_intervencion_buscar</code></p>
      </div>

      <div className="card">
        <div className="filter-row">
          <div className="form-group">
            <label>Estado</label>
            <select
              value={filtros.estado}
              onChange={e => setFiltros(f => ({ ...f, estado: e.target.value }))}
            >
              <option value="">Todos</option>
              {ESTADOS.map(e => <option key={e} value={e}>{e}</option>)}
            </select>
          </div>

          <div className="form-group">
            <label>Zona</label>
            <select
              value={filtros.id_zona}
              onChange={e => setFiltros(f => ({ ...f, id_zona: e.target.value }))}
            >
              <option value="">Todas</option>
              {zonas.map(z => (
                <option key={z.id_zona} value={z.id_zona}>{z.nombre_zona}</option>
              ))}
            </select>
          </div>

          <button className="btn btn-primary" onClick={cargar} disabled={loading}>
            {loading ? 'Consultando…' : 'Filtrar'}
          </button>

          {setPage && (
            <button className="btn btn-ghost" onClick={() => setPage('registrar-intervencion')}>
              + Registrar intervención
            </button>
          )}
        </div>

        {deleteMsg && (
          <div className={`alert alert-${deleteMsg.type === 'success' ? 'success' : 'error'}`}>
            {deleteMsg.text}
          </div>
        )}

        {loading && <div className="spinner"><div className="spin" /> Ejecutando procedimiento…</div>}
        {error   && <div className="alert alert-error">{error}</div>}

        {!loading && !error && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>#</th>
                  <th>Zona</th>
                  <th>Problemática</th>
                  <th>Tipo de intervención</th>
                  <th>Responsable</th>
                  <th>Fecha planeada</th>
                  <th>Estado</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {data.length === 0 ? (
                  <tr><td colSpan={8} className="empty">Sin resultados</td></tr>
                ) : data.map(i => (
                  <tr key={i.id_intervencion}>
                    <td style={{ color: 'var(--txt-muted)', fontFamily: 'monospace' }}>{i.id_intervencion}</td>
                    <td style={{ fontWeight: 600, color: 'var(--txt)' }}>{i.nombre_zona}</td>
                    <td>{i.nombre_problematica}</td>
                    <td>{i.tipo_intervencion}</td>
                    <td>{i.responsable}</td>
                    <td style={{ whiteSpace: 'nowrap' }}>
                      {i.fecha_planeada ? new Date(i.fecha_planeada).toLocaleDateString('es-MX') : '—'}
                    </td>
                    <td><span className={`badge ${badgeClass(i.estado)}`}>{i.estado}</span></td>
                    <td>
                      <button
                        className="btn btn-ghost"
                        style={{ color: 'var(--danger, #d33)', fontSize: '.8rem' }}
                        onClick={() => eliminar(i)}
                        disabled={deletingId === i.id_intervencion}
                        title={i.estado === 'Completada' ? 'No se permite eliminar intervenciones Completadas' : 'Eliminar'}
                      >
                        {deletingId === i.id_intervencion ? 'Eliminando…' : 'Eliminar'}
                      </button>
                    </td>
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