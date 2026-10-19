// Hush — control center (web + Cordova)
(function () {
  'use strict';

  const cfg = window.CUNDIBUS_CONFIG || {};
  const TZ = cfg.timeZone || 'America/Bogota';

  // ---------------------------------------------------------------- helpers
  const $ = (s, el) => (el || document).querySelector(s);
  const $$ = (s, el) => Array.from((el || document).querySelectorAll(s));
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const timeFmt = new Intl.DateTimeFormat('es-CO', { hour: '2-digit', minute: '2-digit', hourCycle: 'h23', timeZone: TZ });
  const fmtTime = (iso) => (iso ? timeFmt.format(new Date(iso)) : '—');
  const fmtDur = (min) => {
    if (min == null || isNaN(min)) return '—';
    min = Math.round(min);
    return min < 60 ? min + ' min' : Math.floor(min / 60) + ' h ' + String(min % 60).padStart(2, '0');
  };
  const minsUntil = (iso) => Math.round((new Date(iso) - Date.now()) / 60000);
  const rel = (iso) => {
    const m = minsUntil(iso);
    if (Math.abs(m) < 1) return 'ahora';
    return m > 0 ? 'en ' + fmtDur(m) : 'hace ' + fmtDur(-m);
  };
  // Form times are always Colombian time (UTC−5, no daylight saving), whatever the device's zone.
  const CO_OFFSET_MS = 5 * 3600e3;
  const toLocalInput = (d) => new Date(new Date(d).getTime() - CO_OFFSET_MS).toISOString().slice(0, 16);
  const fromLocalInput = (v) => new Date(v + ':00-05:00').toISOString();
  const roundTo5 = (d) => { d = new Date(d); d.setSeconds(0, 0); d.setMinutes(Math.ceil(d.getMinutes() / 5) * 5); return d; };
  const ST = { ON_DUTY: 'En turno', UPCOMING: 'Próximo', FINISHED: 'Terminado', PARKED: 'Parqueado', IN_TRANSIT: 'En ruta', IDLE: 'Inactivo' };
  const lotState = (l) => (l.available <= 0 ? 's-full' : l.available / l.capacity <= 0.34 ? 's-mid' : 's-ok');
  const stateVar = { 's-ok': 'var(--ok)', 's-mid': 'var(--mid)', 's-full': 'var(--full)' };
  const haversineKm = (a, b) => {
    const R = 6371, r = Math.PI / 180;
    const dLat = (b.lat - a.lat) * r, dLng = (b.lng - a.lng) * r;
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(a.lat * r) * Math.cos(b.lat * r) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  };
  // same estimate the database uses (fn_trip_minutes)
  const estimateMinutes = (a, b) => Math.max(40, Math.round(haversineKm(a, b) * 1.35 / 38 * 60));

  function toast(kind, title, text) {
    const el = document.createElement('div');
    el.className = 'toast ' + kind;
    el.innerHTML = '<i class="ph-fill ' + (kind === 'ok' ? 'ph-check-circle' : 'ph-warning') + '"></i><div><b>' + esc(title) + '</b><span>' + esc(text || '') + '</span></div>';
    $('#toasts').appendChild(el);
    setTimeout(() => { el.style.transition = 'opacity .3s'; el.style.opacity = '0'; setTimeout(() => el.remove(), 320); }, kind === 'ok' ? 3800 : 6500);
  }

  // ---------------------------------------------------------------- state
  const state = {
    overview: null,
    catalog: null,
    trips: [],
    lotsById: new Map(),
    selectedLot: null,
    selectedBus: null,
    fleetFilter: 'ALL',
    op: 'arrival',
    seatTripId: null,
    pickedSeat: null,
    geo: null
  };

  // ---------------------------------------------------------------- map
  const map = L.map('map', { zoomControl: false, minZoom: 7, maxZoom: 18, zoomSnap: 0.25 }).setView([4.9, -74.1], 8.5);
  L.control.zoom({ position: 'topright' }).addTo(map);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 19,
    className: 'tiles-night',
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
  }).addTo(map);

  const layers = {
    mask: L.layerGroup().addTo(map),
    routes: L.layerGroup().addTo(map),
    geo: L.layerGroup().addTo(map),
    lots: L.layerGroup().addTo(map),
    buses: L.layerGroup().addTo(map)
  };
  const lotMarkers = new Map();
  Live.init(map, { container: $('.map-wrap'), esc: esc, fmtTime: fmtTime, fmtDur: fmtDur, onSelect: (id) => focusBus(id) });

  map.on('zoomend', () => $('#shell').classList.toggle('map-zoomed', map.getZoom() >= 10));

  function drawServiceArea(fc) {
    layers.mask.clearLayers();
    const holes = [];
    fc.features.forEach((f) => {
      const polys = f.geometry.type === 'MultiPolygon' ? f.geometry.coordinates : [f.geometry.coordinates];
      polys.forEach((p) => holes.push(p[0].map((c) => [c[1], c[0]])));
    });
    const world = [[-89, -179], [-89, 179], [89, 179], [89, -179]];
    L.polygon([world].concat(holes), { stroke: false, fillColor: '#0B0610', fillOpacity: 0.6, interactive: false, renderer: L.svg({ padding: 3 }) }).addTo(layers.mask);
    const outline = L.geoJSON(fc, { style: { color: '#FBEFF7', weight: 1.3, opacity: 0.6, dashArray: '3 6', fill: false }, interactive: false }).addTo(layers.mask);
    state.areaBounds = outline.getBounds();
    fitArea();
  }

  // The container can be 0×0 while the page is hidden (iframe, background tab).
  function fitArea() {
    map.invalidateSize();
    const s = map.getSize();
    if (!s.x || !s.y) return setTimeout(fitArea, 250);
    map.fitBounds(state.areaBounds, { padding: [16, 16] });
  }
  window.addEventListener('resize', () => {
    map.invalidateSize();
    if (state.areaBounds && !state.selectedLot && !state.selectedBus) fitArea();
  });

  function nextDeparture(lot) {
    return (lot.parked || []).filter((p) => p.next_departure).sort((a, b) => new Date(a.next_departure) - new Date(b.next_departure))[0];
  }

  function lotTip(l) {
    const nd = nextDeparture(l);
    return '<b>' + esc(l.municipality) + '</b><br>' + l.available + ' de ' + l.capacity + ' cupos libres' +
      (nd ? '<br>Próxima salida ' + fmtTime(nd.next_departure) + ' → ' + esc(nd.next_destination) : '');
  }

  function renderLotMarkers() {
    state.overview.lots.forEach((l) => {
      const st = lotState(l);
      const html = '<div class="lot-pin ' + st + (state.selectedLot === l.id ? ' is-selected' : '') + '" style="--p:' + l.occupancy_pct + '">' +
        '<div class="ring"></div><div class="core">' + l.available + '</div><div class="tag">' + esc(l.municipality) + '</div></div>';
      const icon = L.divIcon({ className: '', html: html, iconSize: [40, 40], iconAnchor: [20, 20] });
      let m = lotMarkers.get(l.id);
      if (!m) {
        m = L.marker([l.lat, l.lng], { icon: icon, riseOnHover: true, keyboard: true, title: l.municipality }).addTo(layers.lots);
        m.bindTooltip('', { className: 'tip', direction: 'top', offset: [0, -22] });
        m.on('click', () => openLot(l.id, true));
        lotMarkers.set(l.id, m);
      } else {
        m.setIcon(icon);
      }
      m.setTooltipContent(lotTip(l));
    });
  }

  function busProgress(b) {
    const t0 = new Date(b.actual_departure).getTime();
    const t1 = new Date(b.scheduled_arrival).getTime();
    return Math.min(1, Math.max(0, (Date.now() - t0) / Math.max(1, t1 - t0)));
  }

  // Buses on the road are animated by live.js (3D bus on the real road).
  function renderBuses() {
    if (!state.overview) return;
    Live.sync(state.overview.buses.filter((b) => b.state === 'IN_TRANSIT'), state.lotsById);
  }

  // ---------------------------------------------------------------- data
  const status = (kind, text) => {
    const el = $('#status');
    el.className = 'status' + (kind ? ' is-' + kind : '');
    $('b', el).textContent = text;
  };

  async function loadOverview() {
    const ov = await Api.overview();
    state.overview = ov;
    state.lotsById = new Map(ov.lots.map((l) => [l.id, l]));
    renderKpis();
    renderLotMarkers();
    renderBuses();
    status('live', 'En vivo');
  }

  async function loadTrips() {
    state.trips = await Api.upcomingTrips();
  }

  async function refreshAll(opts) {
    const btn = $('#btn-refresh');
    btn.classList.add('is-spinning');
    try {
      await Promise.all([loadOverview(), loadTrips()]);
      renderLotsView(opts && opts.keepDetail);
      renderFleet();
      fillOpsForms();
      fillSeatTrips();
      if (isActive('drivers')) renderDrivers();
      if (isActive('seats') && state.seatTripId) loadSeats(state.seatTripId);
    } catch (e) {
      status('error', 'Sin conexión');
      toast('err', 'No se pudieron cargar los datos', e.message);
    } finally {
      btn.classList.remove('is-spinning');
    }
  }

  function renderKpis() {
    const s = state.overview.stats;
    const vals = {
      free: (s.bays - s.occupied) + '/' + s.bays,
      in_transit: s.in_transit,
      departures_next_hour: s.departures_next_hour,
      drivers_on_duty: s.drivers_on_duty
    };
    $$('#kpis [data-k]').forEach((el) => { el.textContent = vals[el.dataset.k]; });
  }

  // ---------------------------------------------------------------- tabs
  const isActive = (tab) => $('.tab.is-active').dataset.tab === tab;

  function switchTab(tab) {
    $$('.tab').forEach((t) => t.classList.toggle('is-active', t.dataset.tab === tab));
    $$('.view').forEach((v) => v.classList.toggle('is-active', v.dataset.view === tab));
    if (tab === 'drivers') renderDrivers();
    if (tab === 'seats' && !state.seatTripId) fillSeatTrips(true);
  }
  $$('.tab').forEach((t) => t.addEventListener('click', () => switchTab(t.dataset.tab)));

  $('#sheet-handle').addEventListener('click', () => $('#panel').classList.toggle('is-expanded'));

  // ---------------------------------------------------------------- terminals
  function bays(lot, large) {
    let html = '<div class="bays' + (large ? ' lg' : '') + '" style="--c:' + stateVar[lotState(lot)] + '">';
    for (let i = 0; i < lot.capacity; i++) {
      html += '<i class="' + (i < lot.occupied ? 'on' : '') + '">' + (large && i < lot.occupied ? '<span class="ph-fill ph-bus"></span>' : '') + '</i>';
    }
    return html + '</div>';
  }

  function renderLotsView(keepDetail) {
    if (state.selectedLot && keepDetail !== false) return openLot(state.selectedLot, false);
    const lots = state.overview.lots;
    const s = state.overview.stats;
    let html = '<h3 class="sec-title">Terminales <span class="count">' + lots.length + '</span> · ' + (s.bays - s.occupied) + ' de ' + s.bays + ' cupos libres</h3><div class="list">';
    lots.forEach((l) => {
      const nd = nextDeparture(l);
      html += '<button class="row" data-lot="' + l.id + '">' +
        '<span class="code ' + lotState(l) + '">' + esc(l.code) + '</span>' +
        '<span class="row-main"><span class="row-title">' + esc(l.municipality) + '</span>' +
        '<span class="row-sub">' + (nd ? 'Próxima ' + fmtTime(nd.next_departure) + ' → ' + esc(nd.next_destination) : 'Sin salidas programadas') + '</span>' +
        bays(l) + '</span>' +
        '<span class="row-side"><span class="big">' + l.available + '<small>/' + l.capacity + '</small></span><span class="tiny">libres</span></span>' +
        '</button>';
    });
    $('#lots-body').innerHTML = html + '</div>';
    $$('#lots-body [data-lot]').forEach((b) => b.addEventListener('click', () => openLot(+b.dataset.lot, true)));
  }

  async function openLot(id, fly) {
    const prev = state.selectedLot;
    state.selectedLot = id;
    if (prev !== id) renderLotMarkers();
    if (!isActive('lots')) switchTab('lots');
    const lot = state.lotsById.get(id);
    if (fly && lot) map.flyTo([lot.lat, lot.lng], Math.max(map.getZoom(), 11), { duration: 0.9 });
    if (prev !== id) $('#lots-body').innerHTML = '<div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>';
    try {
      const d = await Api.lotDetail(id);
      if (state.selectedLot !== id) return;
      renderLotDetail(d);
    } catch (e) {
      toast('err', 'No se pudo cargar la terminal', e.message);
    }
  }

  function closeLot() {
    state.selectedLot = null;
    renderLotMarkers();
    renderLotsView(false);
  }

  function renderLotDetail(d) {
    const l = d.lot;
    let html = '<button class="back" data-back><i class="ph ph-caret-left"></i>Todas las terminales</button>' +
      '<div class="lot-hero"><h3>' + esc(l.municipality) + '</h3>' +
      '<div class="coords">' + esc(l.name) + ' · ' + l.lat.toFixed(6) + ', ' + l.lng.toFixed(6) + '</div>' +
      '<div class="avail"><div><span class="big">' + l.available + '<small>/' + l.capacity + '</small></span><span class="tiny">cupos disponibles</span></div>' +
      '<span class="state ' + (l.available ? 'PARKED' : 'IN_TRANSIT') + '">' + (l.available ? 'Recibe buses' : 'Lleno') + '</span></div>' +
      '<div style="margin-top:12px">' + bays(l, true) + '</div>' +
      '<div class="lot-actions"><button class="btn-ghost" data-go="arrival"><i class="ph ph-sign-in"></i>Llegada</button>' +
      '<button class="btn-ghost" data-go="departure"><i class="ph ph-sign-out"></i>Salida</button></div></div>';

    // parked buses
    html += '<h3 class="sec-title">Parqueados ahora <span class="count">' + d.parked.length + '</span></h3>';
    if (!d.parked.length) html += '<p class="empty">No hay buses parqueados en esta terminal.</p>';
    d.parked.forEach((p) => {
      const planned = p.planned_dwell_min;
      const pct = planned ? Math.min(100, Math.round(p.dwell_so_far_min / planned * 100)) : 0;
      const over = planned && p.dwell_so_far_min > planned;
      html += '<div class="card"><div class="card-top"><div><span class="plate">' + esc(p.plate) + '</span> ' +
        '<span class="tiny" style="display:inline;margin-left:6px">' + esc(p.internal_code) + ' · ' + p.seat_capacity + ' puestos</span></div>' +
        '<span class="tiny">' + (p.arrived_from ? 'desde ' + esc(p.arrived_from) : '') + '</span></div>' +
        '<div class="kv"><div><div class="k">Llegó</div><div class="v">' + fmtTime(p.arrived_at) + '</div></div>' +
        '<div><div class="k">Sale</div><div class="v">' + (p.next_departure ? fmtTime(p.next_departure) : '—') + '</div></div>' +
        '<div><div class="k">Destino</div><div class="v">' + esc(p.next_destination || '—') + '</div></div>' +
        '<div><div class="k">Puestos libres</div><div class="v">' + (p.next_seats_available != null ? p.next_seats_available + '/' + p.seat_capacity : '—') + '</div></div>' +
        '<div style="grid-column:span 2"><div class="k">Conductor</div><div class="v">' + esc(p.next_driver || 'Sin asignar') + '</div></div></div>' +
        '<div class="dwell' + (over ? ' over' : '') + '"><div class="dwell-top"><span>Permanencia <b>' + fmtDur(p.dwell_so_far_min) + '</b>' +
        (planned ? ' de ' + fmtDur(planned) + ' planeada' : '') + '</span><span>' + (p.next_departure ? rel(p.next_departure) : '') + '</span></div>' +
        '<div class="meter"><span style="width:' + pct + '%"></span></div></div></div>';
    });

    // departures
    html += '<h3 class="sec-title">Salidas <span class="count">' + d.departures.length + '</span></h3>';
    if (!d.departures.length) html += '<p class="empty">Sin salidas programadas.</p>';
    else {
      html += '<div class="timeline">';
      d.departures.forEach((t) => {
        html += '<div class="tl-item"><div><div class="tl-time">' + fmtTime(t.scheduled_departure) + ' <span class="tiny" style="display:inline">' + rel(t.scheduled_departure) + '</span></div>' +
          '<div class="tl-sub">→ ' + esc(t.destination) + ' · ' + esc(t.internal_code) + ' · ' + esc(t.driver_name || 'sin conductor') + '</div></div>' +
          '<div class="row-side"><span class="big" style="font-size:18px">' + t.seats_available + '</span><span class="tiny">puestos</span></div></div>';
      });
      html += '</div>';
    }

    // arrivals
    if (d.arrivals.length) {
      html += '<h3 class="sec-title">Llegando <span class="count">' + d.arrivals.length + '</span></h3><div class="timeline">';
      d.arrivals.forEach((t) => {
        html += '<div class="tl-item"><div><div class="tl-time">Llega ' + fmtTime(t.scheduled_arrival) + '</div>' +
          '<div class="tl-sub">desde ' + esc(t.origin) + ' · ' + esc(t.plate) + ' · permanencia planeada ' + fmtDur(t.dwell_minutes) + '</div></div></div>';
      });
      html += '</div>';
    }

    // drivers
    html += '<h3 class="sec-title">Horarios de servicio de conductores <span class="count">' + d.drivers.length + '</span></h3>';
    if (!d.drivers.length) html += '<p class="empty">No hay conductores con base en esta terminal hoy.</p>';
    else {
      html += '<div class="list">';
      d.drivers.forEach((s) => {
        html += '<div class="row"><span class="code"><i class="ph ph-steering-wheel" style="font-size:20px"></i></span>' +
          '<span class="row-main"><span class="row-title">' + esc(s.full_name) + '</span>' +
          '<span class="row-sub">' + fmtTime(s.starts_at) + ' – ' + fmtTime(s.ends_at) + ' · ' + s.trips + ' viaje' + (s.trips === 1 ? '' : 's') + '</span></span>' +
          '<span class="state ' + s.status + '">' + ST[s.status] + '</span></div>';
      });
      html += '</div>';
    }

    // history
    if (d.history.length) {
      html += '<h3 class="sec-title">Historial de permanencia · prom. <span class="count">' + fmtDur(d.avg_dwell_min) + '</span></h3><div class="timeline">';
      d.history.forEach((h) => {
        html += '<div class="tl-item"><div><div class="tl-time">' + fmtTime(h.arrived_at) + ' → ' + fmtTime(h.departed_at) + '</div>' +
          '<div class="tl-sub">' + esc(h.plate) + ' · ' + fmtDur(h.dwell_min) + '</div></div></div>';
      });
      html += '</div>';
    }

    $('#lots-body').innerHTML = html;
    $('[data-back]').addEventListener('click', closeLot);
    $$('[data-go]').forEach((b) => b.addEventListener('click', () => goRegister(b.dataset.go, l.id)));
  }

  // ---------------------------------------------------------------- geocoding
  $('#geo-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const q = $('#geo-input').value.trim();
    if (!q) return;
    const box = $('#geo-results');
    box.innerHTML = '<div class="skeleton" style="height:44px"></div>';
    try {
      const res = await Api.geocode(q);
      if (!res.length) { box.innerHTML = '<p class="empty">No se encontraron lugares en Cundinamarca para “' + esc(q) + '”.</p>'; return; }
      box.innerHTML = res.map((r, i) => {
        const parts = r.display_name.split(',');
        return '<button class="geo-item" data-i="' + i + '"><i class="ph-fill ph-map-pin"></i><span>' + esc(parts[0]) +
          '<small>' + esc(parts.slice(1, 4).join(',')) + '</small></span></button>';
      }).join('');
      $$('.geo-item', box).forEach((b) => b.addEventListener('click', () => {
        const r = res[+b.dataset.i];
        showGeoPoint(+r.lat, +r.lon, r.display_name.split(',')[0], r.display_name);
      }));
    } catch (err) {
      box.innerHTML = '<p class="empty">' + esc(err.message) + '</p>';
    }
  });

  async function showGeoPoint(lat, lng, title, subtitle) {
    if (state.selectedLot) { state.selectedLot = null; renderLotMarkers(); renderLotsView(false); }
    switchTab('lots');
    layers.geo.clearLayers();
    L.marker([lat, lng], { icon: L.divIcon({ className: '', html: '<div class="geo-pin"></div>', iconSize: [22, 22], iconAnchor: [11, 11] }), zIndexOffset: 800 }).addTo(layers.geo);
    const box = $('#geo-results');
    box.innerHTML = '<div class="skeleton" style="height:120px"></div>';
    try {
      const n = await Api.nearestLots(lat, lng, 3);
      const pts = [[lat, lng]];
      n.lots.forEach((l) => {
        pts.push([l.lat, l.lng]);
        L.polyline([[lat, lng], [l.lat, l.lng]], { color: '#B98CF0', weight: 2, opacity: 0.75, dashArray: '4 6', interactive: false }).addTo(layers.geo);
      });
      map.flyToBounds(pts, { padding: [60, 60], maxZoom: 12, duration: 0.9 });
      box.innerHTML = '<div class="geo-card"><h4>' + esc(title) + '</h4><p>' + esc(subtitle || (lat.toFixed(5) + ', ' + lng.toFixed(5))) + '</p>' +
        (n.inside_service_area ? '<span class="badge-in"><i class="ph ph-check-circle"></i>Dentro de Cundinamarca</span>'
                               : '<span class="badge-out"><i class="ph ph-warning"></i>Fuera del área de servicio</span>') +
        '<h3 class="sec-title" style="margin-top:14px">Terminales más cercanas</h3><div class="list">' +
        n.lots.map((l) => '<button class="row" data-lot="' + l.id + '"><span class="code ' + lotState(l) + '">' + esc(l.code) + '</span>' +
          '<span class="row-main"><span class="row-title">' + esc(l.municipality) + '</span><span class="row-sub">' + 'a ' + l.distance_km + ' km</span></span>' +
          '<span class="row-side"><span class="big">' + l.available + '<small>/' + l.capacity + '</small></span><span class="tiny">libres</span></span></button>').join('') +
        '</div><button class="back" data-clear style="margin:10px 0 0"><i class="ph ph-x"></i>Limpiar búsqueda</button></div>';
      $$('[data-lot]', box).forEach((b) => b.addEventListener('click', () => openLot(+b.dataset.lot, true)));
      $('[data-clear]', box).addEventListener('click', () => { box.innerHTML = ''; layers.geo.clearLayers(); $('#geo-input').value = ''; });
    } catch (e) {
      box.innerHTML = '<p class="empty">' + esc(e.message) + '</p>';
    }
  }

  $('#btn-locate').addEventListener('click', () => {
    if (!navigator.geolocation) return toast('err', 'Ubicación no disponible', 'Este dispositivo no tiene GPS.');
    navigator.geolocation.getCurrentPosition(async (pos) => {
      const { latitude: lat, longitude: lng } = pos.coords;
      let label = 'Su ubicación';
      let sub = '';
      try { const r = await Api.reverse(lat, lng); sub = r.display_name || ''; } catch (e) { /* reverse geocoding is optional */ }
      showGeoPoint(lat, lng, label, sub);
    }, (err) => toast('err', 'Ubicación no disponible', err.message), { enableHighAccuracy: true, timeout: 12000 });
  });

  // ---------------------------------------------------------------- fleet
  $$('#fleet-filter .chip').forEach((c) => c.addEventListener('click', () => {
    state.fleetFilter = c.dataset.f;
    $$('#fleet-filter .chip').forEach((x) => x.classList.toggle('is-active', x === c));
    renderFleet();
  }));

  function renderFleet() {
    const buses = state.overview.buses.filter((b) => state.fleetFilter === 'ALL' || b.state === state.fleetFilter);
    $('#fleet-body').innerHTML = buses.map((b) => {
      let where;
      if (b.state === 'PARKED') where = 'Parqueado en ' + esc(b.parked_at) + ' desde ' + fmtTime(b.arrived_at);
      else if (b.state === 'IN_TRANSIT') where = esc(b.origin) + ' → ' + esc(b.destination) + ' · llega ' + fmtTime(b.scheduled_arrival);
      else where = 'Sin viaje activo';
      const next = b.next_departure ? 'Próxima ' + fmtTime(b.next_departure) + ' → ' + esc(b.next_destination) : '';
      const prog = b.state === 'IN_TRANSIT' ? '<div class="meter" style="--c:var(--accent)"><span style="width:' + Math.round(busProgress(b) * 100) + '%"></span></div>' : '';
      return '<button class="row' + (state.selectedBus === b.bus_id ? ' is-selected' : '') + '" data-bus="' + b.bus_id + '">' +
        '<span class="code">' + esc(b.internal_code.replace('CB-', '')) + '</span>' +
        '<span class="row-main"><span class="row-title">' + esc(b.plate) + ' <span class="state ' + b.state + '">' + ST[b.state] + '</span></span>' +
        '<span class="row-sub">' + where + '</span>' + (next ? '<span class="row-sub">' + next + '</span>' : '') + prog + '</span>' +
        '<span class="row-side"><span class="big">' + (b.next_seats_available != null ? b.next_seats_available : '—') + '</span><span class="tiny">puestos libres</span></span></button>';
    }).join('') || '<p class="empty">No hay buses.</p>';
    $$('#fleet-body [data-bus]').forEach((r) => r.addEventListener('click', () => focusBus(+r.dataset.bus)));
  }

  function focusBus(id) {
    const b = state.overview.buses.find((x) => x.bus_id === id);
    if (!b) return;
    state.selectedBus = id;
    if (b.state === 'PARKED') {
      openLot(b.parking_lot_id, true);
    } else {
      if (!isActive('fleet')) switchTab('fleet');
      renderFleet();
      Live.follow(id);
    }
  }

  // ---------------------------------------------------------------- register
  const forms = { arrival: $('#form-arrival'), departure: $('#form-departure'), trip: $('#form-trip') };

  $$('#ops-seg button').forEach((b) => b.addEventListener('click', () => setOp(b.dataset.op)));
  function setOp(op) {
    state.op = op;
    $$('#ops-seg button').forEach((b) => b.classList.toggle('is-active', b.dataset.op === op));
    Object.keys(forms).forEach((k) => { forms[k].hidden = k !== op; });
  }

  function goRegister(op, lotId) {
    switchTab('ops');
    setOp(op);
    const f = forms[op];
    if (f.lot) { f.lot.value = String(lotId); f.lot.dispatchEvent(new Event('change')); }
    $('#panel').classList.add('is-expanded');
  }

  const opt = (v, label, sel) => '<option value="' + esc(v) + '"' + (sel ? ' selected' : '') + '>' + esc(label) + '</option>';

  function lotOptions(selected) {
    return state.overview.lots.map((l) => opt(l.id, l.municipality + ' · ' + l.available + '/' + l.capacity + ' libres', String(l.id) === String(selected))).join('');
  }

  function userOptions(lotId) {
    const users = (state.catalog ? state.catalog.users : []).filter((u) => u.role === 'SYSTEM_ADMIN' || String(u.parking_lot_id) === String(lotId));
    const rank = (u) => (u.role === 'LOT_ADMIN' ? 0 : 1);
    return users.sort((a, b) => rank(a) - rank(b)).map((u) => opt(u.id, u.full_name)).join('');
  }

  function fillOpsForms() {
    if (!state.overview || !state.catalog) return;
    ['arrival', 'departure'].forEach((k) => {
      const f = forms[k];
      const cur = f.lot.value || (state.selectedLot || state.overview.lots[0].id);
      f.lot.innerHTML = lotOptions(cur);
      f.lot.value = String(cur);
      fillLotDependent(k);
    });
    const t = forms.trip;
    const keep = { bus: t.bus.value, driver: t.driver.value, origin: t.origin.value, destination: t.destination.value };
    t.bus.innerHTML = state.catalog.buses.map((b) => opt(b.id, b.internal_code + ' · ' + b.plate + ' · ' + b.seat_capacity + ' puestos')).join('');
    t.driver.innerHTML = opt('', '— Sin asignar —') + state.catalog.drivers.map((d) => opt(d.id, d.full_name)).join('');
    const lotsOpt = state.catalog.lots.map((l) => opt(l.id, l.municipality)).join('');
    t.origin.innerHTML = lotsOpt;
    t.destination.innerHTML = lotsOpt;
    Object.keys(keep).forEach((k) => { if (keep[k]) t[k].value = keep[k]; });
    if (!keep.destination) t.destination.selectedIndex = 1;
    if (!t.departure.value) {
      t.departure.value = toLocalInput(roundTo5(Date.now() + 60 * 60000));
      estimateArrival();
    }
  }

  function fillLotDependent(k) {
    const f = forms[k];
    const lotId = +f.lot.value;
    const curUser = f.user.value;
    f.user.innerHTML = userOptions(lotId);
    if (curUser && $$('option', f.user).some((o) => o.value === curUser)) f.user.value = curUser;
    const curBus = f.bus.value;
    if (k === 'arrival') {
      const buses = state.overview.buses.filter((b) => b.state !== 'PARKED');
      const here = buses.filter((b) => b.destination_lot_id === lotId);
      const others = buses.filter((b) => b.destination_lot_id !== lotId);
      f.bus.innerHTML =
        (here.length ? '<optgroup label="Llegando a esta terminal">' + here.map((b) => opt(b.bus_id, b.internal_code + ' · ' + b.plate + ' — desde ' + b.origin)).join('') + '</optgroup>' : '') +
        (others.length ? '<optgroup label="Otros buses no parqueados">' + others.map((b) => opt(b.bus_id, b.internal_code + ' · ' + b.plate + (b.destination ? ' — rumbo a ' + b.destination : ''))).join('') + '</optgroup>' : '');
      if (!buses.length) f.bus.innerHTML = opt('', 'Todos los buses están parqueados');
    } else {
      const lot = state.lotsById.get(lotId);
      const parked = lot ? lot.parked : [];
      f.bus.innerHTML = parked.length ? parked.map((p) => opt(p.bus_id, p.internal_code + ' · ' + p.plate)).join('') : opt('', 'No hay buses parqueados aquí');
    }
    if (curBus && $$('option', f.bus).some((o) => o.value === curBus)) f.bus.value = curBus;
    if (!f.at.value || !f.at.dataset.touched) f.at.value = toLocalInput(new Date());
    updateNote(k);
  }

  function updateNote(k) {
    const f = forms[k];
    const note = $('[data-note]', f);
    const busId = +f.bus.value;
    const lotId = +f.lot.value;
    if (!busId) { note.innerHTML = ''; return; }
    if (k === 'arrival') {
      const b = state.overview.buses.find((x) => x.bus_id === busId);
      const lot = state.lotsById.get(lotId);
      if (b && b.state === 'IN_TRANSIT') {
        note.innerHTML = b.destination_lot_id === lotId
          ? 'Cierra el viaje <b>#' + b.trip_id + '</b> ' + esc(b.origin) + ' → ' + esc(b.destination) + ' (salió ' + fmtTime(b.actual_departure) + ').'
          : '⚠ Este bus va rumbo a <b>' + esc(b.destination) + '</b>. La base de datos rechazará la llegada aquí.';
      } else note.innerHTML = 'Llegada sin viaje asociado.';
      if (lot && lot.available <= 0) note.innerHTML += '<br>⚠ <b>' + esc(lot.municipality) + '</b> está lleno — la regla de capacidad la rechazará.';
    } else {
      const lot = state.lotsById.get(lotId);
      const p = lot && lot.parked.find((x) => x.bus_id === busId);
      const trips = state.trips.filter((t) => t.bus_id === busId && t.origin_lot_id === lotId);
      const curTrip = f.trip.value;
      f.trip.innerHTML = trips.length ? trips.map((t) => opt(t.id, fmtTime(t.scheduled_departure) + ' → ' + t.destination + ' · #' + t.id)).join('') : opt('', 'Sin viaje programado — cree uno primero');
      if (curTrip && trips.some((t) => String(t.id) === curTrip)) f.trip.value = curTrip;
      const t = trips.find((x) => String(x.id) === f.trip.value);
      note.innerHTML = (p ? 'Parqueado desde <b>' + fmtTime(p.arrived_at) + '</b> · permanencia <b>' + fmtDur(p.dwell_so_far_min) + '</b>.' : '') +
        (t ? '<br>Sale hacia <b>' + esc(t.destination) + '</b> · programado ' + fmtTime(t.scheduled_departure) + ' · ' + t.seats_sold + '/' + t.seat_capacity + ' puestos vendidos · ' + esc(t.driver_name || 'sin conductor') + '.' : '');
    }
  }

  ['arrival', 'departure'].forEach((k) => {
    const f = forms[k];
    f.lot.addEventListener('change', () => fillLotDependent(k));
    f.bus.addEventListener('change', () => updateNote(k));
    if (f.trip) f.trip.addEventListener('change', () => updateNote(k));
    f.at.addEventListener('input', () => { f.at.dataset.touched = '1'; });
  });

  function estimateArrival() {
    const t = forms.trip;
    const o = state.lotsById.get(+t.origin.value);
    const d = state.lotsById.get(+t.destination.value);
    const note = $('[data-note]', t);
    if (!o || !d || !t.departure.value) return;
    if (o.id === d.id) { note.innerHTML = '⚠ El origen y el destino deben ser diferentes.'; return; }
    const mins = estimateMinutes(o, d);
    if (!t.arrival.dataset.touched) t.arrival.value = toLocalInput(roundTo5(Date.parse(fromLocalInput(t.departure.value)) + mins * 60000));
    note.innerHTML = 'Distancia ≈ <b>' + haversineKm(o, d).toFixed(1) + ' km</b> en línea recta · viaje estimado <b>' + fmtDur(mins) + '</b>.';
  }
  ['origin', 'destination', 'departure'].forEach((n) => forms.trip[n].addEventListener('change', estimateArrival));
  forms.trip.arrival.addEventListener('input', () => { forms.trip.arrival.dataset.touched = '1'; });

  async function submitWith(form, fn, okTitle) {
    const btn = $('button[type=submit]', form);
    btn.disabled = true;
    try {
      const res = await fn();
      toast('ok', okTitle, res);
      $$('input[type=datetime-local]', form).forEach((i) => { delete i.dataset.touched; });
      await refreshAll({ keepDetail: true });
    } catch (e) {
      toast('err', 'Rechazado por la base de datos', e.message);
    } finally {
      btn.disabled = false;
    }
  }

  forms.arrival.addEventListener('submit', (e) => {
    e.preventDefault();
    const f = forms.arrival;
    const lot = state.lotsById.get(+f.lot.value);
    const bus = state.overview.buses.find((b) => b.bus_id === +f.bus.value);
    submitWith(f, async () => {
      const r = await Api.registerArrival({ busId: +f.bus.value, lotId: +f.lot.value, userId: +f.user.value || null, at: fromLocalInput(f.at.value) });
      return (bus ? bus.internal_code : 'Bus') + ' parqueado en ' + lot.municipality + ' (estadía #' + r.stay_id + ').';
    }, 'Llegada registrada');
  });

  forms.departure.addEventListener('submit', (e) => {
    e.preventDefault();
    const f = forms.departure;
    const lot = state.lotsById.get(+f.lot.value);
    submitWith(f, async () => {
      const r = await Api.registerDeparture({ busId: +f.bus.value, lotId: +f.lot.value, tripId: +f.trip.value || null, userId: +f.user.value || null, at: fromLocalInput(f.at.value) });
      return 'El viaje #' + r.trip_id + ' salió de ' + lot.municipality + ' — el bus ya está en ruta';
    }, 'Salida registrada');
  });

  forms.trip.addEventListener('submit', (e) => {
    e.preventDefault();
    const f = forms.trip;
    submitWith(f, async () => {
      const r = await Api.createTrip({
        busId: +f.bus.value, driverId: +f.driver.value || null,
        originId: +f.origin.value, destinationId: +f.destination.value,
        departure: fromLocalInput(f.departure.value), arrival: fromLocalInput(f.arrival.value), dwell: +f.dwell.value
      });
      return 'Viaje #' + r.trip_id + ' registrado.';
    }, 'Viaje registrado');
  });

  // ---------------------------------------------------------------- seats
  function fillSeatTrips(autoload) {
    const sel = $('#seat-trip');
    const cur = state.seatTripId;
    sel.innerHTML = state.trips.length
      ? state.trips.map((t) => opt(t.id, fmtTime(t.scheduled_departure) + ' · ' + t.origin + ' → ' + t.destination + ' · ' + t.internal_code + ' · ' + t.seats_available + ' libres', t.id === cur)).join('')
      : opt('', 'No hay viajes próximos');
    if (autoload && state.trips.length) {
      state.seatTripId = cur || state.trips[0].id;
      sel.value = String(state.seatTripId);
      loadSeats(state.seatTripId);
    }
  }
  $('#seat-trip').addEventListener('change', (e) => { state.seatTripId = +e.target.value; state.pickedSeat = null; loadSeats(state.seatTripId); });

  async function loadSeats(id) {
    try {
      const d = await Api.tripSeats(id);
      if (state.seatTripId !== id) return;
      renderSeats(d);
    } catch (e) {
      toast('err', 'No se pudieron cargar los puestos', e.message);
    }
  }

  function renderSeats(d) {
    const t = d.trip;
    if (!t) { $('#seat-body').innerHTML = '<p class="empty">Viaje no encontrado.</p>'; return; }
    const sold = new Set(d.sold);
    const pct = Math.round(sold.size / t.seat_capacity * 100);
    let grid = '';
    for (let i = 1; i <= t.seat_capacity; i++) {
      if ((i - 1) % 4 === 2) grid += '<span class="aisle"></span>';
      const isSold = sold.has(i);
      grid += '<button class="seat' + (isSold ? ' sold' : '') + (state.pickedSeat === i ? ' picked' : '') + '" data-seat="' + i + '"' +
        (isSold ? ' disabled aria-label="Puesto ' + i + ' vendido"' : ' aria-label="Puesto ' + i + ' disponible"') + '>' + i + '</button>';
    }
    $('#seat-body').innerHTML = '<div class="seat-wrap">' +
      '<div class="trip-card"><div class="trip-route">' + esc(t.origin) + '<i class="ph ph-arrow-right"></i>' + esc(t.destination) + '</div>' +
      '<div class="row-sub" style="margin-top:6px">' + fmtTime(t.scheduled_departure) + ' – ' + fmtTime(t.scheduled_arrival) + ' · ' + esc(t.internal_code) + ' · ' + esc(t.plate) + ' · ' + esc(t.driver_name || 'sin conductor') + '</div>' +
      '<div class="seat-stats"><div><span class="big">' + (t.seat_capacity - sold.size) + '</span><span class="tiny">disponibles</span></div>' +
      '<div><span class="big">' + sold.size + '</span><span class="tiny">vendidos</span></div>' +
      '<div><span class="big">' + pct + '<small>%</small></span><span class="tiny">ocupación</span></div></div>' +
      '<div class="meter" style="--c:var(--accent)"><span style="width:' + pct + '%"></span></div></div>' +
      '<div class="bus-shell"><div class="bus-front"><span>Frente</span><i class="ph ph-steering-wheel"></i></div><div class="seat-grid">' + grid + '</div></div>' +
      '<form class="sell-bar" id="sell-form"' + (state.pickedSeat ? '' : ' hidden') + '><input name="passenger" placeholder="Nombre del pasajero (opcional)">' +
      '<button class="btn-primary" type="submit"><i class="ph ph-ticket"></i>Vender puesto ' + (state.pickedSeat || '') + '</button></form>' +
      '<p class="hint" style="text-align:center">' + (state.pickedSeat ? '' : 'Toque un puesto verde para venderlo.') + '</p></div>';

    $$('#seat-body .seat:not(.sold)').forEach((s) => s.addEventListener('click', () => {
      state.pickedSeat = state.pickedSeat === +s.dataset.seat ? null : +s.dataset.seat;
      renderSeats(d);
    }));
    const form = $('#sell-form');
    if (form) form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const seat = state.pickedSeat;
      try {
        await Api.sellTicket(t.id, seat, form.passenger.value);
        toast('ok', 'Puesto vendido', 'Puesto ' + seat + ' en ' + t.origin + ' → ' + t.destination + '.');
        state.pickedSeat = null;
        await refreshAll({ keepDetail: true });
        loadSeats(t.id);
      } catch (err) {
        toast('err', 'Rechazado por la base de datos', err.message);
      }
    });
  }

  // ---------------------------------------------------------------- drivers
  $('#driver-lot').addEventListener('change', renderDrivers);

  async function renderDrivers() {
    const body = $('#driver-body');
    if (!body.innerHTML) body.innerHTML = '<div class="skeleton"></div><div class="skeleton"></div>';
    try {
      const [shifts, trips] = await Promise.all([Api.driverSchedule(), Api.driverTrips()]);
      const sel = $('#driver-lot');
      if (sel.options.length <= 1 && state.catalog) sel.innerHTML += state.catalog.lots.map((l) => opt(l.id, l.municipality)).join('');
      const lotFilter = sel.value;
      const now = Date.now();
      const t0 = now - 4 * 3600e3, t1 = now + 10 * 3600e3, span = t1 - t0;
      const x = (iso) => Math.min(100, Math.max(0, (new Date(iso) - t0) / span * 100));
      const order = { ON_DUTY: 0, UPCOMING: 1, FINISHED: 2 };
      const rows = shifts.filter((s) => !lotFilter || String(s.base_lot_id) === lotFilter)
        .sort((a, b) => order[a.status] - order[b.status] || new Date(a.starts_at) - new Date(b.starts_at));

      let axis = '';
      const first = Math.ceil(t0 / 7200e3) * 7200e3;
      for (let t = first; t < t1; t += 7200e3) axis += '<span style="left:' + ((t - t0) / span * 100) + '%">' + timeFmt.format(new Date(t)) + '</span>';
      const nowX = (now - t0) / span * 100;
      axis += '<span class="now-tag" style="left:' + nowX + '%">AHORA</span>';

      let html = '<div class="gantt"><div class="g-axis">' + axis + '</div>';
      rows.forEach((s) => {
        const myTrips = trips.filter((t) => t.driver_id === s.driver_id);
        const left = x(s.starts_at), width = Math.max(0.8, x(s.ends_at) - left);
        html += '<div class="g-row"><div class="g-name"><b>' + esc(s.full_name) + '</b><small>' + esc(s.base_lot) + ' · ' + fmtTime(s.starts_at) + '–' + fmtTime(s.ends_at) + '</small></div>' +
          '<div class="g-track"><div class="g-shift ' + s.status + '" style="left:' + left + '%;width:' + width + '%" title="' + esc(s.full_name + ' · ' + fmtTime(s.starts_at) + '–' + fmtTime(s.ends_at) + ' · ' + s.status) + '"></div>' +
          myTrips.map((t) => {
            const l = x(t.scheduled_departure), w = Math.max(0.6, x(t.scheduled_arrival) - l);
            return w > 0 ? '<div class="g-trip" style="left:' + l + '%;width:' + w + '%" title="' + esc(t.internal_code + ' · ' + t.origin + ' → ' + t.destination + ' · ' + fmtTime(t.scheduled_departure) + '–' + fmtTime(t.scheduled_arrival)) + '"></div>' : '';
          }).join('') +
          '<div class="g-now" style="left:' + nowX + '%"></div></div></div>';
      });
      if (!rows.length) html += '<p class="empty">Sin turnos para esta terminal.</p>';
      html += '</div><p class="hint" style="margin-top:12px"><span class="dot ok"></span> turno de servicio &nbsp; <span class="dot full"></span> viaje asignado &nbsp; ventana: −4 h / +10 h</p>';
      body.innerHTML = html;
    } catch (e) {
      body.innerHTML = '<p class="empty">' + esc(e.message) + '</p>';
    }
  }

  // ---------------------------------------------------------------- top bar
  function tick() { $('#clock').textContent = timeFmt.format(new Date()); }
  tick();
  setInterval(tick, 10000);

  $('#btn-refresh').addEventListener('click', () => refreshAll({ keepDetail: true }));
  $('#btn-reset').addEventListener('click', async () => {
    if (!confirm('¿Regenerar las operaciones de demostración (buses parqueados, viajes, puestos y turnos) a partir de la hora actual?')) return;
    try {
      await Api.resetDemo();
      state.seatTripId = null;
      toast('ok', 'Datos de demostración regenerados', 'Las operaciones ahora parten de las ' + fmtTime(new Date()) + '.');
      await refreshAll({ keepDetail: true });
    } catch (e) {
      toast('err', 'No se pudo regenerar', e.message);
    }
  });

  // ---------------------------------------------------------------- boot
  async function boot() {
    if (!Api.configured) {
      status('error', 'Sin configurar');
      $('#lots-body').innerHTML = '<div class="setup"><h3>Conecte Supabase</h3><p>Configure <code>supabaseUrl</code> y <code>supabaseKey</code> en <code>app/js/config.js</code> y ejecute los archivos SQL de <code>/database</code>.</p></div>';
      map.setView([4.9, -74.1], 8.5);
      return;
    }
    $('#lots-body').innerHTML = '<div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>';
    try {
      const [area, catalog] = await Promise.all([Api.serviceArea(), Api.catalog()]);
      state.catalog = catalog;
      drawServiceArea(area);
      await refreshAll();
    } catch (e) {
      status('error', 'Sin conexión');
      $('#lots-body').innerHTML = '<div class="setup"><h3>No se puede conectar con la base de datos</h3><p>' + esc(e.message) + '</p></div>';
    }
    setInterval(() => { if (!document.hidden) refreshAll({ keepDetail: true }); }, (cfg.refreshSeconds || 30) * 1000);
  }

  if (window.cordova) document.addEventListener('deviceready', boot, false);
  else boot();
})();
