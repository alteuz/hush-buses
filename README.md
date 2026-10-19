<div align="center">

<img src="docs/readme/banner.png" alt="Hush Buses — cada bus, cada cupo, en el mapa" width="100%">

<br>

**Sistema de información geográfica para una empresa de transporte intermunicipal de Cundinamarca, Colombia.**<br>
Disponibilidad de parqueaderos, ubicación de buses y puestos por bus sobre un mapa dinámico de OpenStreetMap.

<br>

[![Demo en vivo](https://img.shields.io/badge/demo-hushbusapp.vercel.app-FF2D9B?style=for-the-badge&logo=vercel&logoColor=white)](https://hushbusapp.vercel.app)
[![Sistema](https://img.shields.io/badge/abrir-sistema-B98CF0?style=for-the-badge&logo=leaflet&logoColor=white)](https://hushbusapp.vercel.app/app/index.html)
[![Guía PDF](https://img.shields.io/badge/guía-demostración_PDF-36D6B0?style=for-the-badge&logo=adobeacrobatreader&logoColor=white)](docs/Guia-Demostracion-Hush-Buses.pdf)

![PostGIS](https://img.shields.io/badge/PostGIS-3-336791?logo=postgresql&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-PostgreSQL_17-3ECF8E?logo=supabase&logoColor=white)
![Leaflet](https://img.shields.io/badge/Leaflet-1.9-199900?logo=leaflet&logoColor=white)
![OpenStreetMap](https://img.shields.io/badge/OpenStreetMap-tiles_·_Nominatim_·_OSRM-7EBC6F?logo=openstreetmap&logoColor=white)
![Three.js](https://img.shields.io/badge/Three.js-bus_3D-000000?logo=threedotjs&logoColor=white)
![Cordova](https://img.shields.io/badge/Apache_Cordova-app_móvil-E8E8E8?logo=apachecordova&logoColor=black)
![License](https://img.shields.io/badge/licencia-MIT-FF2D9B)

*“Reescribe las reglas del campo de batalla.”*

</div>

---

## ✦ El reto

Taller 2 — **Geocodificación y uso de mapas dinámicos**. Una empresa de transporte intermunicipal necesita un software que, **solo dentro de los límites de Cundinamarca**, responda tres preguntas:

| | Pregunta | Cómo la resuelve Hush |
|:-:|---|---|
| **a** | ¿Cuántos cupos libres hay en cada parqueadero? | Cada llegada abre una estadía y cada salida la cierra; `v_parking_availability` compara estadías abiertas con la capacidad, y un trigger con bloqueo de fila impide el sobrecupo. |
| **b** | ¿Dónde está cada bus? | En el parqueadero de su estadía abierta. En ruta, PostGIS estima la posición con `ST_LineInterpolatePoint` y el mapa lo anima sobre la vía real. |
| **c** | ¿Cuántos puestos le quedan a cada bus? | Cada tiquete es un puesto de un viaje: disponibles = capacidad − vendidos. La base rechaza puestos duplicados o inexistentes. |

Además se entregan: diseño con el **modelo de vistas 4+1**, la **base de datos PostGIS**, el **sistema web** con el mapa de OpenStreetMap y una **app móvil en Cordova**.

## ✦ Recorrido visual

<table>
  <tr>
    <td width="50%"><img src="docs/guia/img/08-terminal.jpeg" alt="Detalle de terminal"><br><sub><b>Terminales</b> — cupos libres, buses parqueados, permanencia, próximas salidas y conductores.</sub></td>
    <td width="50%"><img src="docs/guia/img/14-en-vivo.jpeg" alt="Recorrido en vivo"><br><sub><b>En vivo</b> — bus 3D sobre la vía real (OSRM), cámara que lo sigue y reloj ×30–×600.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/guia/img/09-geocodificacion.jpeg" alt="Geocodificación"><br><sub><b>Geocodificación</b> — Nominatim + KNN de PostGIS para la terminal más cercana.</sub></td>
    <td><img src="docs/guia/img/12-puestos.jpeg" alt="Puestos por bus"><br><sub><b>Puestos</b> — mapa 2+2 del bus y venta de puestos con reglas en la base.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/guia/img/11-registro-salida.jpeg" alt="Registro de salida"><br><sub><b>Registrar</b> — llegadas, salidas y viajes (origen, destino, horas, permanencia).</sub></td>
    <td><img src="docs/guia/img/13-conductores.jpeg" alt="Horarios de conductores"><br><sub><b>Conductores</b> — horarios de servicio y viajes asignados con línea de “ahora”.</sub></td>
  </tr>
  <tr>
    <td><img src="docs/guia/img/03-mapa-red.jpeg" alt="Red de terminales"><br><sub><b>La red</b> — los 21 parqueaderos del enunciado y la frontera del departamento.</sub></td>
    <td><img src="docs/guia/img/05-vista-procesos.jpeg" alt="Vista de procesos"><br><sub><b>Vistas 4+1</b> — escenarios, lógica, procesos, desarrollo y física.</sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/guia/img/15-movil.jpeg" alt="App móvil" width="240">
  &nbsp;&nbsp;
  <img src="docs/guia/img/16-movil-en-vivo.jpeg" alt="App móvil en vivo" width="240">
  <br><sub><b>App móvil (Cordova)</b> — el mismo código, con navegación inferior y GPS del dispositivo.</sub>
</p>

## ✦ Qué incluye

- **Página de inicio** con hero en video, animaciones ligadas al scroll, mapa de la red, diagramas 4+1 interactivos y el sistema embebido.
- **Sistema web** (Leaflet + OpenStreetMap): terminales, flota, registro de movimientos, puestos y horarios de conductores.
- **Recorrido en vivo**: bus 3D de bajo poligonaje (Three.js) que avanza por la vía real según la hora de salida y la de llegada.
- **Geocodificación** directa e inversa con Nominatim y terminal más cercana con el operador KNN `<->` de PostGIS.
- **Reglas de negocio dentro de PostgreSQL**: límites del departamento, capacidad, traslapes, puestos y permisos por parqueadero.
- **App móvil Cordova** que empaqueta exactamente el mismo código del sistema web.
- **Documentación**: [vistas 4+1](docs/ARCHITECTURE.md) y [guía de demostración en PDF](docs/Guia-Demostracion-Hush-Buses.pdf).

## ✦ Arquitectura

```mermaid
flowchart LR
  subgraph Clientes
    W["Página + sistema web<br/>HTML · CSS · JS"]
    M["App Cordova<br/>WebView + GPS"]
  end
  subgraph Supabase["Supabase · us-east-1"]
    R["PostgREST<br/>RLS · funciones api_*"] --> D[("PostgreSQL 17<br/>PostGIS 3")]
  end
  OSM["OpenStreetMap<br/>mosaicos · Nominatim · OSRM"]
  W -- HTTPS · JSON --> R
  M -- HTTPS · JSON --> R
  W --> OSM
  M --> OSM
```

No hay servidor de aplicaciones propio: los clientes son estáticos (servidos en **Vercel**) y hablan directo con la API de Supabase. Toda escritura pasa por funciones `api_*` que ejecutan las reglas en una sola transacción. El detalle de las cinco vistas está en [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

### Base de datos (SRID 4326)

| Tabla | Rol |
|---|---|
| `service_area` | Polígonos de Cundinamarca y Bogotá D.C. tomados de OpenStreetMap |
| `parking_lot` | Los 21 parqueaderos del taller · capacidad · `geometry(Point)` + GiST |
| `bus` | Flota · placa colombiana · capacidad de puestos |
| `trip` | Información del bus: origen, destino, salida, llegada, permanencia, estado |
| `parking_stay` | Llegada + salida registradas por el administrador → permanencia real y ubicación |
| `ticket` | Puesto vendido, único por viaje |
| `driver` · `driver_shift` | Conductores y turnos de servicio (≤ 12 h, sin traslapes) |
| `app_user` | Administradores de cada parqueadero |

Vistas: `v_parking_availability` · `v_bus_location` · `v_trip_detail` · `v_parked_buses` · `v_driver_schedule` · `v_stay_history`.

## ✦ Ejecutarlo

**1. Base de datos.** Cree un proyecto en [Supabase](https://supabase.com) y, en el SQL Editor, ejecute en orden:

```text
database/01_schema.sql       tablas, restricciones e índices espaciales
database/02_functions.sql    reglas: límites, capacidad, traslapes, puestos, llegada/salida
database/03_views.sql        vistas de disponibilidad, ubicación, puestos y horarios
database/04_service_area.sql polígonos de Cundinamarca y Bogotá D.C.
database/05_seed.sql         21 parqueaderos + flota, conductores y operación demo
database/06_api.sql          RLS y funciones RPC públicas
database/07_hardening.sql    ajustes de seguridad y validaciones
```

**2. Conectar.** En [`app/js/config.js`](app/js/config.js) ponga la URL del proyecto y la llave pública (*publishable key*). Es segura de publicar: RLS solo permite lecturas y las escrituras pasan por las funciones `api_*`.

**3. Servir.**

```bash
npx serve .
```

Abra `http://localhost:3000` (página) o `http://localhost:3000/app/` (sistema).

**4. App móvil** (requiere Android SDK y JDK 17):

```bash
cd mobile
npm install
npm run sync
npx cordova platform add android
npx cordova run android
```

> El sitio necesita internet: carga mosaicos de OpenStreetMap, Nominatim, OSRM y librerías desde CDN (Leaflet, supabase-js, Three.js, Phosphor, Google Fonts).

## ✦ Estructura

```text
.
├── index.html              página de inicio (landing)
├── app/                    sistema web — también es la app móvil
│   ├── index.html
│   ├── css/app.css
│   └── js/                 config · api (datos) · app (UI) · live (en vivo) · bus3d (Three.js)
├── database/               SQL 01–07 + consultas de ejemplo
├── mobile/                 proyecto Cordova (config.xml, sync de www/)
├── assets/                 video del hero, ícono y datos de la red
├── docs/                   vistas 4+1, guía PDF, capturas y banner
└── vercel.json             despliegue estático
```

## ✦ Seguridad

- **RLS** en las 9 tablas: los clientes solo leen; no existen políticas de escritura.
- Escrituras únicamente por funciones `api_*` (*SECURITY DEFINER*) que validan cada regla.
- Documento y teléfono de los conductores no son públicos (permisos por columna).
- Todo texto externo se escapa antes de mostrarse.
- Proyecto académico sin inicio de sesión: cualquiera con la página puede registrar movimientos de demostración (el botón ↺ regenera los datos). En producción se añadiría Supabase Auth.

## ✦ Equipo

| Desarrolladores |
|---|
| **Andres Camilo Aldana Cantor** |
| **David Alejandro Castro Peña** |
| **Alejandro Agudelo Quintero** |

Taller 2 — Geocodificación y uso de mapas dinámicos · Profesor **Carlos Armando López Solano, MSc.**

## ✦ Créditos y licencia

- Código bajo licencia [MIT](LICENSE).
- Datos del mapa © colaboradores de [OpenStreetMap](https://www.openstreetmap.org/copyright) (ODbL) · rutas [OSRM](https://project-osrm.org) · geocodificación [Nominatim](https://nominatim.org).
- Video del hero: “Buses and cars in the freeway”, [Mixkit](https://mixkit.co) (licencia Mixkit).
- Íconos: [Phosphor Icons](https://phosphoricons.com) (MIT).
- La temática, el nombre, el eslogan y el ícono de **Hush** pertenecen a **Riot Games** (VALORANT). Este es un proyecto académico de fans, sin afiliación ni respaldo de Riot Games; esos recursos no están cubiertos por la licencia MIT.
