import { useState, useEffect } from 'react'
import { registrarIntervencion, getCatalogosIntervencion } from '../services/api'

const INITIAL = {
  id_deteccion:             '',
  id_recurso:               '',
  tipo_intervencion:        'Visita de verificación',
  descripcion_intervencion: '',
  responsable:              '',
  fecha_planeada:           new Date().toISOString().slice(0, 10),
  estado:                   'Planeada',
}

const TIPOS = [
  'Visita de verificación',
  'Canalización a recurso comunitario',
  'Plática informativa',
  'Referencia a institución',
]

const ESTADOS = ['Planeada', 'EnProceso', 'Completada']

export default function RegistrarIntervencion() {
  const [form, setForm]       = useState(INITIAL)
  const [catalogos, setCat]   = useState(null)
  const [loading, setLoading] = useState(false)
  const [catLoad, setCatLoad] = useState(true)
  const [msg, setMsg]         = useState(null) // { type, text }

  useEffect(() => {
    getCatalogosIntervencion()
      .then(setCat)
      .catch(() => setCat(null))
      .finally(() => setCatLoad(false))
  }, [])

  const set = (k, v) => setForm(f => ({ ...f, [k]: v }))

  const submit = async () => {
    const required = ['id_deteccion', 'tipo_intervencion', 'descripcion_intervencion',
                       'responsable', 'fecha_planeada', 'estado']
    if (required.some(k => !form[k])) {
      setMsg({ type: 'error', text: 'Completa todos los campos antes de registrar.' })
      return
    }
    setLoading(true)
    setMsg(null)
    try {
      const res = await registrarIntervencion({
        ...form,
        id_recurso: form.id_recurso || null,
      })
      setMsg({ type: 'success', text: res.resultado || 'Intervención registrada correctamente.' })
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
        <h2>Registrar intervención</h2>
        <p>Procedimiento: <code style={{ color: 'var(--accent)', fontSize: '.8rem' }}>OCN.sp_intervencion_registrar_completa</code></p>
      </div>

      {catLoad && <div className="spinner"><div className="spin" /> Cargando catálogos…</div>}

      {!catLoad && (
        <div className="card">
          <div className="card-title">◎ Nueva intervención</div>

          {msg && (
            <div className={`alert alert-${msg.type === 'success' ? 'success' : 'error'}`}>
              {msg.text}
            </div>
          )}

          <div className="form-grid">
            <div className="form-group">
              <label>Detección relacionada</label>
              <select value={form.id_deteccion} onChange={e => set('id_deteccion', e.target.value)}>
                <option value="">— seleccionar —</option>
                {catalogos?.detecciones?.map(d => (
                  <option key={d.id_deteccion} value={d.id_deteccion}>
                    #{d.id_deteccion} · {d.zona} · {d.problematica}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Recurso comunitario (opcional)</label>
              <select value={form.id_recurso} onChange={e => set('id_recurso', e.target.value)}>
                <option value="">— ninguno —</option>
                {catalogos?.recursos?.map(r => (
                  <option key={r.id_recurso} value={r.id_recurso}>
                    {r.nombre_recurso}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label>Tipo de intervención</label>
              <select value={form.tipo_intervencion} onChange={e => set('tipo_intervencion', e.target.value)}>
                {TIPOS.map(t => <option key={t}>{t}</option>)}
              </select>
            </div>

            <div className="form-group">
              <label>Estado</label>
              <select value={form.estado} onChange={e => set('estado', e.target.value)}>
                {ESTADOS.map(e => <option key={e}>{e}</option>)}
              </select>
            </div>

            <div className="form-group">
              <label>Responsable</label>
              <input type="text" placeholder="Nombre del responsable"
                value={form.responsable}
                onChange={e => set('responsable', e.target.value)} />
            </div>

            <div className="form-group">
              <label>Fecha planeada</label>
              <input type="date" value={form.fecha_planeada}
                onChange={e => set('fecha_planeada', e.target.value)} />
            </div>

            <div className="form-group" style={{ gridColumn: '1 / -1' }}>
              <label>Descripción</label>
              <input type="text" placeholder="Detalle de la intervención…"
                value={form.descripcion_intervencion}
                onChange={e => set('descripcion_intervencion', e.target.value)} />
            </div>
          </div>

          <div style={{ marginTop: '1.5rem', display: 'flex', gap: '.75rem' }}>
            <button className="btn btn-primary" onClick={submit} disabled={loading}>
              {loading ? 'Registrando…' : 'Registrar intervención'}
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
              exec OCN.sp_intervencion_registrar_completa<br />
              &nbsp;&nbsp;@id_deteccion = {form.id_deteccion || '?'},<br />
              &nbsp;&nbsp;@id_recurso = {form.id_recurso || 'NULL'},<br />
              &nbsp;&nbsp;@tipo_intervencion = '{form.tipo_intervencion}',<br />
              &nbsp;&nbsp;@estado = '{form.estado}',<br />
              &nbsp;&nbsp;@fecha_planeada = '{form.fecha_planeada}'
            </code>
          </div>
        </div>
      )}
    </>
  )
}