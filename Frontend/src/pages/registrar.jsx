import { useState, useEffect } from 'react'
import { registrarDeteccion, getCatalogos } from '../services/api'

const INITIAL = {
  fecha_registro:      new Date().toISOString().slice(0, 10),
  frecuencia:          'Diaria',
  intensidad:          'alta',
  observaciones:       '',
  descripcion_anonima: '',
  id_levantamiento:    '',
  id_problematica:     '',
  id_fuente:           '',
  id_grupoetario:      '',
}

export default function Registrar() {
  const [form, setForm]       = useState(INITIAL)
  const [catalogos, setCat]   = useState(null)
  const [loading, setLoading] = useState(false)
  const [catLoad, setCatLoad] = useState(true)
  const [msg, setMsg]         = useState(null)   // { type, text }

  useEffect(() => {
    getCatalogos()
      .then(setCat)
      .catch(() => setCat(null))
      .finally(() => setCatLoad(false))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  const submit = async () => {
    const required = ['fecha_registro','frecuencia','intensidad','observaciones',
                      'descripcion_anonima','id_levantamiento','id_problematica',
                      'id_fuente','id_grupoetario']
    if (required.some(k => !form[k])) {
      setMsg({ type: 'error', text: 'Completa todos los campos antes de registrar.' })
      return
    }
    setLoading(true)
    setMsg(null)
    try {
      const res = await registrarDeteccion(form)
      setMsg({ type: 'success', text: res.resultado || 'Detección registrada correctamente.' })
      setForm(INITIAL)
    } catch (e) {
      setMsg({ type: 'error', text: e.message })
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      <div className="page-header">
        <h2>Registrar detección</h2>
        <p>Procedimiento: <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>OCN.sp_registrar_deteccion</code></p>
      </div>

      {catLoad && <div className="spinner"><div className="spin" /> Cargando catálogos…</div>}

      {!catLoad && (
        <div className="card">
          <div className="card-title">◎ Nueva detección</div>

          {msg && (
            <div className={`alert alert-${msg.type === 'success' ? 'success' : 'error'}`}>
              {msg.text}
            </div>
          )}

          <div className="form-grid">
            <div className="form-group">
              <label>Fecha de registro</label>
              <input type="date" value={form.fecha_registro}
                onChange={e => set('fecha_registro', e.target.value)} />
            </div>

            <div className="form-group">
              <label>Frecuencia</label>
              <select value={form.frecuencia} onChange={e => set('frecuencia', e.target.value)}>
                {['Diaria','Semanal','Mensual','Ocasional'].map(o =>
                  <option key={o}>{o}</option>
                )}
              </select>
            </div>

            <div className="form-group">
              <label>Intensidad</label>
              <select value={form.intensidad} onChange={e => set('intensidad', e.target.value)}>
                <option value="alta">Alta</option>
                <option value="media">Media</option>
                <option value="baja">Baja</option>
              </select>
            </div>

            <div className="form-group">
              <label>Levantamiento</label>
              <select value={form.id_levantamiento} onChange={e => set('id_levantamiento', e.target.value)}>
                <option value="">— seleccionar —</option>
                {catalogos?.levantamientos?.map(l => (
                  <option key={l.id_levantamiento} value={l.id_levantamiento}>
                    {l.nombre_equipo} · {new Date(l.fecha).toLocaleDateString('es-MX')}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Problemática</label>
              <select value={form.id_problematica} onChange={e => set('id_problematica', e.target.value)}>
                <option value="">— seleccionar —</option>
                {catalogos?.problematicas?.map(p => (
                  <option key={p.id_problematica} value={p.id_problematica}>
                    {p.nombre_problematica}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Fuente</label>
              <select value={form.id_fuente} onChange={e => set('id_fuente', e.target.value)}>
                <option value="">— seleccionar —</option>
                {catalogos?.fuentes?.map(f => (
                  <option key={f.id_fuente} value={f.id_fuente}>
                    {f.nombre_tipo_fuente} · {f.confiabilidad}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Grupo etario</label>
              <select value={form.id_grupoetario} onChange={e => set('id_grupoetario', e.target.value)}>
                <option value="">— seleccionar —</option>
                {catalogos?.grupos?.map(g => (
                  <option key={g.id_grupoetario} value={g.id_grupoetario}>
                    {g.nombre_grupo} ({g.rango_edad})
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Descripción anónima</label>
              <input type="text" placeholder="Residente sector…"
                value={form.descripcion_anonima}
                onChange={e => set('descripcion_anonima', e.target.value)} />
            </div>

            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <label>Observaciones generales</label>
              <input type="text" placeholder="Notas del equipo de campo…"
                value={form.observaciones}
                onChange={e => set('observaciones', e.target.value)} />
            </div>
          </div>

          <div style={{ marginTop: '1.5rem', display: 'flex', gap: '.75rem' }}>
            <button className="btn btn-primary" onClick={submit} disabled={loading}>
              {loading ? 'Registrando…' : 'Registrar detección'}
            </button>
            <button className="btn btn-ghost" onClick={() => { setForm(INITIAL); setMsg(null) }}>
              Limpiar
            </button>
          </div>

          <div style={{ marginTop: '1.25rem', padding: '1rem', background: 'var(--bg)', borderRadius: 'var(--radius)', border: '1px solid var(--border)' }}>
            <div style={{ fontSize: '.72rem', color: 'var(--txt-muted)', marginBottom: '.4rem', textTransform: 'uppercase', letterSpacing: '.06em' }}>
              Llamada que se ejecutará
            </div>
            <code style={{ fontSize: '.75rem', color: 'var(--accent)', lineHeight: 1.6 }}>
              exec OCN.sp_registrar_deteccion<br />
              &nbsp;&nbsp;@fecha_registro = '{form.fecha_registro}',<br />
              &nbsp;&nbsp;@frecuencia = '{form.frecuencia}',<br />
              &nbsp;&nbsp;@intensidad = '{form.intensidad}',<br />
              &nbsp;&nbsp;@id_levantamiento = {form.id_levantamiento || '?'},<br />
              &nbsp;&nbsp;@id_problematica = {form.id_problematica || '?'},<br />
              &nbsp;&nbsp;@id_fuente = {form.id_fuente || '?'},<br />
              &nbsp;&nbsp;@id_grupoetario = {form.id_grupoetario || '?'}
            </code>
          </div>
        </div>
      )}
    </>
  )
}