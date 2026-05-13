# OCN – Observatorio Ciudadano de Necesidades
## Aplicación React + Node.js + SQL Server

---

## Estructura del proyecto

```
ocn-app/
├── api/                  ← Servidor Node.js (Express + mssql)
│   ├── server.js         ← API REST: endpoints que llaman vistas y SPs
│   └── package.json
│
├── src/                  ← Frontend React + Vite
│   ├── services/
│   │   └── api.js        ← Capa de servicio: centraliza fetch a la API
│   ├── pages/
│   │   ├── Dashboard.jsx    ← Resumen general (vista 1 + vista 2)
│   │   ├── Detecciones.jsx  ← Tabla completa (vista 1)
│   │   ├── Estadisticas.jsx ← Estadísticas (vista 2 + vista 3)
│   │   ├── PorFecha.jsx     ← Consulta por fechas (SP 2)
│   │   └── Registrar.jsx    ← Formulario de captura (SP 1)
│   ├── App.jsx           ← Navegación lateral + routing
│   ├── index.css         ← Sistema de diseño OCN
│   └── main.jsx
│
├── index.html
├── vite.config.js        ← Proxy /api → localhost:3001
└── package.json
```

---

## Pasos para ejecutar

### 1. Configurar la base de datos
Asegúrate de haber ejecutado en SQL Server:
- `OCN_Fase3_Implementacion_VillaIsaac.sql` (tablas + datos)
- `vistas_OCN.sql` (las 3 vistas)
- `procedimientos_OCN.sql` (los 3 procedimientos almacenados)

### 2. Configurar la API
Edita `api/server.js` y ajusta las credenciales:

```js
const config = {
  server:   'localhost\\SQLEXPRESS',  // tu instancia de SQL Server
  database: 'OCN_DB',
  user:     'sa',
  password: 'TuPasswordAqui',         // tu contraseña
}
```

### 3. Instalar dependencias e iniciar la API

```bash
cd api
npm install
npm start
# → Servidor en http://localhost:3001
```

### 4. Instalar dependencias e iniciar React

```bash
# (desde la raíz ocn-app/)
npm install
npm run dev
# → App en http://localhost:5173
```

---

## Flujo de datos

```
Usuario (navegador)
  │
  │  interactúa con la interfaz React
  ▼
React (Vite · puerto 5173)
  │
  │  fetch('/api/...')  →  proxy en vite.config.js
  ▼
API Node.js (Express · puerto 3001)
  │
  │  mssql · query() / execute()
  ▼
SQL Server · OCN_DB
  │
  │  devuelve recordset
  ▼
API → JSON → React → tabla / formulario
```

### Endpoints disponibles

| Método | Endpoint                                   | Objeto BD usado                        |
|--------|--------------------------------------------|----------------------------------------|
| GET    | /api/ping                                  | conexión                               |
| GET    | /api/vistas/reporte-detecciones            | vw_reporte_detecciones_por_zona        |
| GET    | /api/vistas/estadisticas-zona              | vw_estadisticas_problematicas_por_zona |
| GET    | /api/vistas/levantamientos-fuente          | vw_levantamientos_con_fuente           |
| POST   | /api/procedimientos/registrar-deteccion    | sp_registrar_deteccion                 |
| GET    | /api/procedimientos/detecciones-por-fecha  | sp_consultar_detecciones_por_fecha     |
| GET    | /api/procedimientos/resumen-zona           | sp_resumen_por_zona                    |
| GET    | /api/catalogos                             | tablas catálogo                        |

---

## Tecnologías utilizadas

| Capa       | Tecnología         |
|------------|--------------------|
| Frontend   | React 18 + Vite 5  |
| API        | Node.js + Express  |
| BD client  | mssql (npm)        |
| Base datos | SQL Server         |