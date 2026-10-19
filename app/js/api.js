// Data access layer: Supabase (PostgREST + PostGIS) and OpenStreetMap Nominatim.
window.Api = (function () {
  const cfg = window.CUNDIBUS_CONFIG || {};
  const configured = !!(cfg.supabaseUrl && cfg.supabaseKey && !/^YOUR_/.test(cfg.supabaseUrl));
  const client = configured && window.supabase
    ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseKey, { auth: { persistSession: false } })
    : null;

  class ApiError extends Error {}

  function ensure() {
    if (!client) throw new ApiError('Supabase no está configurado (app/js/config.js).');
  }

  async function rpc(name, params) {
    ensure();
    const { data, error } = await client.rpc(name, params || {});
    if (error) throw new ApiError(error.message || 'La solicitud falló');
    return data;
  }

  async function select(view, build) {
    ensure();
    const { data, error } = await build(client.from(view));
    if (error) throw new ApiError(error.message || 'La solicitud falló');
    return data;
  }

  const NOMINATIM = 'https://nominatim.openstreetmap.org';

  async function nominatim(path, params) {
    const url = NOMINATIM + path + '?' + new URLSearchParams(Object.assign({ format: 'jsonv2', 'accept-language': 'es' }, params));
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) throw new ApiError('Servicio de geocodificación no disponible (' + res.status + ')');
    return res.json();
  }

  return {
    configured,
    ApiError,

    // ---- reads -----------------------------------------------------------
    overview: () => rpc('api_overview'),
    serviceArea: () => rpc('api_service_area'),
    catalog: () => rpc('api_catalog'),
    lotDetail: (id) => rpc('api_lot_detail', { p_lot_id: id }),
    nearestLots: (lat, lng, limit) => rpc('api_nearest_lots', { p_lat: lat, p_lng: lng, p_limit: limit || 4 }),
    tripSeats: (id) => rpc('api_trip_seats', { p_trip_id: id }),
    upcomingTrips: () => select('v_trip_detail', (q) => q.select('*').eq('status', 'SCHEDULED').order('scheduled_departure')),
    driverSchedule: () => select('v_driver_schedule', (q) => q.select('*').order('starts_at')),
    driverTrips: () => select('v_trip_detail', (q) => q
      .select('id,driver_id,origin,destination,scheduled_departure,scheduled_arrival,status,internal_code')
      .neq('status', 'CANCELLED').not('driver_id', 'is', null)),

    // ---- writes (business rules live in PostgreSQL) -----------------------
    registerArrival: (p) => rpc('api_register_arrival', {
      p_bus_id: p.busId, p_lot_id: p.lotId, p_trip_id: p.tripId || null, p_user_id: p.userId || null, p_at: p.at || null
    }),
    registerDeparture: (p) => rpc('api_register_departure', {
      p_bus_id: p.busId, p_lot_id: p.lotId, p_trip_id: p.tripId || null, p_user_id: p.userId || null, p_at: p.at || null
    }),
    createTrip: (p) => rpc('api_create_trip', {
      p_bus_id: p.busId, p_origin_lot_id: p.originId, p_destination_lot_id: p.destinationId,
      p_departure: p.departure, p_arrival: p.arrival, p_dwell_minutes: p.dwell, p_driver_id: p.driverId || null
    }),
    sellTicket: (tripId, seat, passenger) => rpc('api_sell_ticket', { p_trip_id: tripId, p_seat_number: seat, p_passenger: passenger || null }),
    resetDemo: () => rpc('api_reset_demo'),

    // ---- geocoding (OpenStreetMap Nominatim) ------------------------------
    geocode: (text) => nominatim('/search', {
      q: text, countrycodes: 'co', limit: 6, bounded: 1, viewbox: cfg.viewbox.join(',')
    }),
    reverse: (lat, lng) => nominatim('/reverse', { lat, lon: lng, zoom: 16 })
  };
})();
