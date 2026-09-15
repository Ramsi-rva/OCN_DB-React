import { useState, useEffect } from 'react'
import { ping } from './services/api'
import Dashboard    from './pages/dashboard'
import Detecciones  from './pages/detecciones'
import Estadisticas from './pages/estadisticas'
import Registrar    from './pages/registrar'
import Intervenciones         from './pages/intervenciones'
import RegistrarIntervencion  from './pages/registrarIntervencion'
import PorFecha     from './pages/porFecha'

const PAGES = [
  { id: 'dashboard',    label: 'Dashboard',         icon: '◈' },
  { id: 'detecciones',  label: 'Detecciones',        icon: '◉' },
  { id: 'estadisticas', label: 'Estadísticas',        icon: '◧' },
  { id: 'por-fecha',    label: 'Consulta por fecha',  icon: '◷' },
  { id: 'registrar',    label: 'Registrar detección', icon: '◎' },
  { id: 'intervenciones',        label: 'Intervenciones',           icon: '◆' },
  { id: 'registrar-intervencion', label: 'Registrar intervención',   icon: '✚' },
]

export default function App() {
  const [page, setPage]     = useState('dashboard')
  const [dbStatus, setStatus] = useState('loading') // 'loading' | 'ok' | 'error'

  useEffect(() => {
    ping()
      .then(() => setStatus('ok'))
      .catch(() => setStatus('error'))
  }, [])

  const statusLabel = {
    loading: 'Conectando a SQL Server…',
    ok:      'Conectado a OCN_DB · SQL Server',
    error:   'Sin conexión a la base de datos',
  }[dbStatus]

  const renderPage = () => {
    switch (page) {
      case 'dashboard':    return <Dashboard    setPage={setPage} dbStatus={dbStatus} />
      case 'detecciones':  return <Detecciones />
      case 'estadisticas': return <Estadisticas />
      case 'por-fecha':    return <PorFecha />
      case 'registrar':    return <Registrar />
      case 'intervenciones':         return <Intervenciones setPage={setPage} />
      case 'registrar-intervencion': return <RegistrarIntervencion />
      default:             return <Dashboard    setPage={setPage} dbStatus={dbStatus} />
    }
  }

  return (
    <div className="layout">
      {/* ── Sidebar ── */}
      <aside className="sidebar">
        <div className="sidebar-logo">
          <h1>
            <span className="dot" />
            OCN
          </h1>
          <span>Observatorio Ciudadano</span>
        </div>

        <nav className="sidebar-nav">
          <div className="nav-label">Módulos</div>
          {PAGES.map(p => (
            <button
              key={p.id}
              className={`nav-link${page === p.id ? ' active' : ''}`}
              onClick={() => setPage(p.id)}
            >
              <span className="icon">{p.icon}</span>
              {p.label}
            </button>
          ))}
        </nav>

        <div style={{ padding: '0 1.25rem 1rem', borderTop: '1px solid var(--border)', paddingTop: '1rem' }}>
          <div className="status-bar" style={{ margin: 0 }}>
            <span className={`status-dot ${dbStatus}`} />
            <span style={{ fontSize: '.72rem' }}>{statusLabel}</span>
          </div>
        </div>
      </aside>

      {/* ── Main content ── */}
      <main className="main">
        {renderPage()}
      </main>
    </div>
  )
}
