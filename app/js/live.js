// Live tracking of buses on the road.
// The database knows departure/arrival times (no GPS is required by the
// workshop). Here each bus is placed along the real road — routed with OSRM
// over OpenStreetMap — according to elapsed time, animated every frame and
// drawn as a small 3D bus. A simulation clock (×30…×600) lets you watch it move.
window.Live = (function () {
  'use strict';

  const OSRM = 'https://router.project-osrm.org/route/v1/driving/';
  const RAD = Math.PI / 180;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  let map, routeLayer, busLayer, opts, hud, chip;
  const routes = new Map();          // trip_id → route
  const items = new Map();           // bus_id  → animated bus
  let speed = 1, simOffset = 0, lastT = 0, followId = null, camFollow = false, hudT = 0;

  // ------------------------------------------------------------- geometry
  function km(a, b) {
    const h = Math.sin((b[0] - a[0]) * RAD / 2) ** 2 +
      Math.cos(a[0] * RAD) * Math.cos(b[0] * RAD) * Math.sin((b[1] - a[1]) * RAD / 2) ** 2;
    return 2 * 6371 * Math.asin(Math.sqrt(h));
  }

  function bearing(a, b) {
    const p1 = a[0] * RAD, p2 = b[0] * RAD, dl = (b[1] - a[1]) * RAD;
    const y = Math.sin(dl) * Math.cos(p2);
    const x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl);
    return (Math.atan2(y, x) / RAD + 360) % 360;
  }

  function buildRoute(pts, source, roadKm) {
    if (pts.length > 1600) {                       // keep it light for per-frame work
      const k = Math.ceil(pts.length / 1600);
      pts = pts.filter((p, i) => i % k === 0 || i === pts.length - 1);
    }
    const cum = [0];
    for (let i = 1; i < pts.length; i++) cum.push(cum[i - 1] + km(pts[i - 1], pts[i]));
    const total = cum[cum.length - 1] || 0.001;
    return { pts: pts, cum: cum, total: total, roadKm: roadKm || total, source: source };
  }

  function pointAt(r, dist) {
    dist = Math.max(0, Math.min(r.total, dist));
    let lo = 0, hi = r.cum.length - 1;
    while (hi - lo > 1) {
      const mid = (lo + hi) >> 1;
      if (r.cum[mid] <= dist) lo = mid; else hi = mid;
    }
    const seg = r.cum[hi] - r.cum[lo] || 1;
    const t = (dist - r.cum[lo]) / seg;
    const a = r.pts[lo], b = r.pts[hi];
    return { pos: [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t], i: lo };
  }

  function along(r, p) {
    const d = p * r.total;
    const here = pointAt(r, d);
    const look = d + 0.35 < r.total ? pointAt(r, d + 0.35).pos : null;
    const back = look ? here.pos : pointAt(r, d - 0.35).pos;
    return { pos: here.pos, i: here.i, heading: bearing(back, look || here.pos) };
  }

  const angleDiff = (a, b) => ((b - a + 540) % 360) - 180;

  // ------------------------------------------------------------- data
  const simNow = () => Date.now() + simOffset;

  function progress(b) {
    const t0 = Date.parse(b.actual_departure);
    const t1 = Date.parse(b.scheduled_arrival);
    return Math.min(1, Math.max(0, (simNow() - t0) / Math.max(1, t1 - t0)));
  }

  function routeFor(b, o, d) {
    if (routes.has(b.trip_id)) return routes.get(b.trip_id);
    const line = buildRoute([[o.lat, o.lng], [d.lat, d.lng]], 'line');
    routes.set(b.trip_id, line);
    fetch(OSRM + o.lng + ',' + o.lat + ';' + d.lng + ',' + d.lat + '?overview=full&geometries=geojson')
      .then((res) => (res.ok ? res.json() : Promise.reject(res.status)))
      .then((j) => {
        const best = j.routes && j.routes[0];
        if (!best) return;
        const r = buildRoute(best.geometry.coordinates.map((c) => [c[1], c[0]]), 'osrm', best.distance / 1000);
        routes.set(b.trip_id, r);
        const it = items.get(b.bus_id);
        if (it && it.bus.trip_id === b.trip_id) attach(it, r);
      })
      .catch(() => { /* keep the straight line */ });
    return line;
  }

  // ------------------------------------------------------------- markers
  function attach(it, r) {
    it.route = r;
    it.ahead.setLatLngs(r.pts);
    it.trailT = 0;
  }

  function create(b, r) {
    const flat = !window.Bus3D || !Bus3D.available();
    const html = '<div class="bus3d' + (flat ? ' is-flat' : '') + '">' +
      '<span class="bus3d-halo"></span>' +
      (flat ? '<i class="ph-fill ph-bus"></i>' : '<canvas width="' + Bus3D.size + '" height="' + Bus3D.size + '"></canvas>') +
      '<span class="bus3d-tag">' + opts.esc(b.internal_code) + '</span></div>';
    const it = {
      bus: b,
      heading: null,
      drawn: null,
      trailT: 0,
      ahead: L.polyline(r.pts, { color: '#FF2D9B', weight: 2.5, opacity: 0.4, dashArray: '2 8', interactive: false }).addTo(routeLayer),
      glow: L.polyline([], { color: '#FF2D9B', weight: 9, opacity: 0.16, interactive: false }).addTo(routeLayer),
      done: L.polyline([], { color: '#FF2D9B', weight: 3.5, opacity: 1, interactive: false }).addTo(routeLayer),
      marker: L.marker(r.pts[0], {
        icon: L.divIcon({ className: 'bus3d-icon', html: html, iconSize: [64, 64], iconAnchor: [32, 38] }),
        zIndexOffset: 700
      }).addTo(busLayer)
    };
    it.route = r;
    it.el = it.marker.getElement().querySelector('.bus3d');
    it.canvas = it.el.querySelector('canvas');
    it.marker.bindTooltip('', { className: 'tip', direction: 'top', offset: [0, -30] });
    it.marker.on('click', () => opts.onSelect(b.bus_id));
    return it;
  }

  function remove(id) {
    const it = items.get(id);
    if (!it) return;
    [it.ahead, it.glow, it.done].forEach((l) => routeLayer.removeLayer(l));
    busLayer.removeLayer(it.marker);
    items.delete(id);
    if (followId === id) unfollow();
  }

  // Called by the app after every data refresh with the buses IN_TRANSIT.
  function sync(buses, lotsById) {
    const live = new Set();
    buses.forEach((b) => {
      const o = lotsById.get(b.origin_lot_id);
      const d = lotsById.get(b.destination_lot_id);
      if (!o || !d) return;
      live.add(b.bus_id);
      const r = routeFor(b, o, d);
      let it = items.get(b.bus_id);
      if (it && it.bus.trip_id !== b.trip_id) { remove(b.bus_id); it = null; }
      if (!it) { it = create(b, r); items.set(b.bus_id, it); }
      it.bus = b;
      it.marker.setTooltipContent('<b>' + opts.esc(b.internal_code) + ' · ' + opts.esc(b.plate) + '</b><br>' +
        opts.esc(b.origin) + ' → ' + opts.esc(b.destination) + '<br>Llega ' + opts.fmtTime(b.scheduled_arrival) + ' · clic para seguir');
    });
    Array.from(items.keys()).forEach((id) => { if (!live.has(id)) remove(id); });
    chip.querySelector('b').textContent = items.size;
    chip.hidden = items.size === 0;
  }

  // ------------------------------------------------------------- animation loop
  function frame(t) {
    requestAnimationFrame(frame);
    let dt = lastT ? t - lastT : 0;
    lastT = t;
    if (dt > 250) dt = 250;                       // tab was hidden
    simOffset += dt * (speed - 1);

    items.forEach((it) => {
      const r = it.route;
      const p = progress(it.bus);
      const a = along(r, p);
      it.p = p;
      it.pos = a.pos;
      it.marker.setLatLng(a.pos);

      // smooth turning, then re-render the 3D bus only when it actually turns
      it.heading = it.heading == null ? a.heading : (it.heading + angleDiff(it.heading, a.heading) * (reduce ? 1 : 0.12) + 360) % 360;
      if (it.canvas && (it.drawn == null || Math.abs(angleDiff(it.drawn, it.heading)) > 0.6)) {
        Bus3D.render(it.canvas, it.heading);
        it.drawn = it.heading;
      }
      it.el.classList.toggle('is-arrived', p >= 1);
      it.el.classList.toggle('is-followed', followId === it.bus.bus_id);

      if (t - it.trailT > 120) {
        it.trailT = t;
        const trail = r.pts.slice(0, a.i + 1);
        trail.push(a.pos);
        it.done.setLatLngs(trail);
        it.glow.setLatLngs(trail);
      }
    });

    const f = followId != null && items.get(followId);
    if (f && camFollow) {
      // keep the bus in the free part of the map, beside / below the HUD
      const z = map.getZoom();
      const wide = window.innerWidth > 860;
      const off = hud.hidden ? 0 : wide ? (hud.offsetLeft + hud.offsetWidth) / 2 : (hud.offsetTop + hud.offsetHeight) / 2;
      const target = map.project(f.pos, z).subtract(wide ? [off, 0] : [0, off]);
      map.panTo(map.unproject(target, z), { animate: false });
    }
    if (f && t - hudT > 200) { hudT = t; paintHud(f); }
  }

  // ------------------------------------------------------------- follow + HUD
  function follow(id) {
    const it = items.get(id);
    if (!it) return;
    followId = id;
    hud.hidden = false;
    document.body.classList.add('is-following');
    setTimeout(() => map.invalidateSize(), 420);
    camFollow = false;
    map.flyTo(it.pos || it.route.pts[0], Math.max(map.getZoom(), 13), { duration: reduce ? 0 : 1.1 });
    map.once('moveend', () => { if (followId === id && hud.querySelector('.lh-cam input').checked) camFollow = true; });
    paintHud(it);
  }

  function unfollow() {
    followId = null;
    camFollow = false;
    hud.hidden = true;
    document.body.classList.remove('is-following');
    setTimeout(() => map.invalidateSize(), 420);
  }

  function setSpeed(s) {
    speed = s;
    if (s === 1) simOffset = 0;                    // "En vivo" = back to the real clock
    hud.querySelectorAll('[data-s]').forEach((x) => x.classList.toggle('is-active', +x.dataset.s === s));
  }

  function paintHud(it) {
    const b = it.bus, r = it.route;
    const t0 = Date.parse(b.actual_departure), t1 = Date.parse(b.scheduled_arrival);
    const left = Math.max(0, (t1 - simNow()) / 60000);
    const q = (s) => hud.querySelector(s);
    q('.plate').textContent = b.plate;
    q('.lh-code').textContent = b.internal_code;
    q('.lh-o').textContent = b.origin;
    q('.lh-d').textContent = b.destination;
    q('.lh-fill').style.transform = 'scaleX(' + it.p.toFixed(4) + ')';
    q('.lh-runner').style.left = (it.p * 100).toFixed(2) + '%';
    q('.lh-km').textContent = (it.p * r.roadKm).toFixed(1) + ' / ' + r.roadKm.toFixed(0);
    q('.lh-spd').textContent = Math.round(r.roadKm / Math.max(0.1, (t1 - t0) / 3600000));
    q('.lh-eta').textContent = it.p >= 1 ? 'Llegó' : opts.fmtTime(b.scheduled_arrival);
    q('.lh-left').textContent = it.p >= 1 ? 'pendiente registrar llegada' : 'faltan ' + opts.fmtDur(left);
    q('.lh-mode').textContent = speed > 1 ? 'SIM ×' + speed + ' · ' + opts.fmtTime(new Date(simNow())) : 'TIEMPO REAL';
    q('.lh-mode').classList.toggle('is-sim', speed > 1);
    q('.lh-note').textContent = (r.source === 'osrm' ? 'Ruta por vías reales (OSRM · OpenStreetMap). ' : 'Trazando ruta… mostrando línea recta. ') +
      (speed > 1 ? 'Simulación visual: los datos de la base no cambian.' : 'Posición estimada por tiempo transcurrido.');
  }

  function step(dir) {
    const ids = Array.from(items.keys());
    if (!ids.length) return;
    const i = ids.indexOf(followId);
    follow(ids[(i + dir + ids.length) % ids.length]);
  }

  function buildUi(container) {
    chip = document.createElement('button');
    chip.className = 'live-chip';
    chip.type = 'button';
    chip.hidden = true;
    chip.innerHTML = '<span class="live-dot"></span>En vivo · <b>0</b> en ruta';
    chip.addEventListener('click', () => step(1));

    hud = document.createElement('section');
    hud.className = 'live-hud';
    hud.hidden = true;
    hud.setAttribute('aria-label', 'Recorrido en vivo');
    hud.innerHTML =
      '<header><span class="live-dot"></span><b>Recorrido en vivo</b><span class="lh-mode"></span>' +
      '<button type="button" class="lh-x" aria-label="Cerrar"><i class="ph ph-x"></i></button></header>' +
      '<div class="lh-bus"><span class="plate"></span><span class="lh-code"></span>' +
      '<span class="lh-nav"><button type="button" data-nav="-1" aria-label="Bus anterior"><i class="ph ph-caret-left"></i></button>' +
      '<button type="button" data-nav="1" aria-label="Bus siguiente"><i class="ph ph-caret-right"></i></button></span></div>' +
      '<div class="lh-route"><span class="lh-o"></span><i class="ph ph-arrow-right"></i><span class="lh-d"></span></div>' +
      '<div class="lh-bar"><span class="lh-fill"></span><span class="lh-runner"><i class="ph-fill ph-bus"></i></span></div>' +
      '<div class="lh-stats"><div><b class="lh-km"></b><small>km recorridos</small></div>' +
      '<div><b class="lh-spd"></b><small>km/h prom.</small></div>' +
      '<div><b class="lh-eta"></b><small class="lh-left"></small></div></div>' +
      '<div class="lh-speed" role="group" aria-label="Velocidad de simulación">' +
      '<button type="button" data-s="1" class="is-active">En vivo</button><button type="button" data-s="30">×30</button>' +
      '<button type="button" data-s="120">×120</button><button type="button" data-s="600">×600</button></div>' +
      '<label class="lh-cam"><input type="checkbox" checked> Cámara sigue al bus</label>' +
      '<p class="lh-note"></p>';

    hud.querySelector('.lh-x').addEventListener('click', unfollow);
    hud.querySelectorAll('[data-nav]').forEach((x) => x.addEventListener('click', () => step(+x.dataset.nav)));
    hud.querySelectorAll('[data-s]').forEach((x) => x.addEventListener('click', () => setSpeed(+x.dataset.s)));
    hud.querySelector('.lh-cam input').addEventListener('change', (e) => { camFollow = e.target.checked; });
    map.on('dragstart', () => { camFollow = false; hud.querySelector('.lh-cam input').checked = false; });

    container.appendChild(chip);
    container.appendChild(hud);
  }

  function init(leafletMap, options) {
    map = leafletMap;
    opts = options;
    routeLayer = L.layerGroup().addTo(map);
    busLayer = L.layerGroup().addTo(map);
    buildUi(options.container);
    requestAnimationFrame(frame);
  }

  return { init: init, sync: sync, follow: follow, unfollow: unfollow };
})();
