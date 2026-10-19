-- =====================================================================
--  queries.sql  —  Consultas espaciales de ejemplo (anexo del taller)
-- =====================================================================
SET search_path = public, extensions;

-- 1. Disponibilidad de cupos en cada parqueadero ---------------------------
SELECT code, municipality, capacity, occupied, available, occupancy_pct
FROM v_parking_availability
ORDER BY available DESC, municipality;

-- 2. Ubicación de todos los buses (parqueados o estimada en ruta) ----------
SELECT internal_code, plate, state, parked_at, origin, destination,
       round(progress::numeric, 2) AS progress, lat, lng
FROM v_bus_location
ORDER BY state, internal_code;

-- 3. Puestos disponibles por bus en sus próximos viajes --------------------
SELECT internal_code, origin, destination, scheduled_departure,
       seat_capacity, seats_sold, seats_available
FROM v_trip_detail
WHERE status = 'SCHEDULED'
ORDER BY scheduled_departure;

-- 4. Horas de salida de los buses parqueados en un parqueadero ------------
SELECT plate, arrived_at, dwell_so_far_min, next_departure, next_destination, next_driver
FROM v_parked_buses
WHERE lot = 'Bogotá D.C.'
ORDER BY next_departure;

-- 5. Horarios de servicio de los conductores con base en una terminal -----
SELECT full_name, base_lot, starts_at, ends_at, status, trips
FROM v_driver_schedule
WHERE base_lot = 'Facatativá'
ORDER BY starts_at;

-- 6. Las 3 terminales más cercanas a un punto geocodificado (KNN) ---------
--    Ejemplo: Zipaquirá (5.0221, -74.0058)
SELECT pl.code, pl.municipality, a.available,
       round((ST_DistanceSphere(pl.geom, ST_SetSRID(ST_MakePoint(-74.0058, 5.0221), 4326)) / 1000)::numeric, 1) AS km
FROM parking_lot pl
JOIN v_parking_availability a ON a.id = pl.id
ORDER BY pl.geom <-> ST_SetSRID(ST_MakePoint(-74.0058, 5.0221), 4326)
LIMIT 3;

-- 7. ¿Un punto está dentro del área de servicio? ---------------------------
SELECT fn_in_service_area(ST_SetSRID(ST_MakePoint(-74.0058, 5.0221), 4326)) AS zipaquira,   -- true
       fn_in_service_area(ST_SetSRID(ST_MakePoint(-75.5636, 6.2518), 4326)) AS medellin;    -- false

-- 8. Distancia en línea recta entre cada par origen-destino programado ----
SELECT origin, destination, distance_km, scheduled_departure, scheduled_arrival
FROM v_trip_detail
WHERE status IN ('SCHEDULED', 'IN_TRANSIT')
ORDER BY distance_km DESC;

-- 9. Parqueaderos dentro de un radio de 40 km de Bogotá D.C. ---------------
SELECT b.municipality, round((ST_DistanceSphere(a.geom, b.geom) / 1000)::numeric, 1) AS km
FROM parking_lot a, parking_lot b
WHERE a.code = 'BOG' AND b.code <> 'BOG'
  AND ST_DWithin(a.geom::geography, b.geom::geography, 40000)
ORDER BY km;

-- 10. Tiempo promedio de permanencia por parqueadero ----------------------
SELECT lot, count(*) AS stays, round(avg(dwell_min)) AS avg_dwell_min
FROM v_stay_history
GROUP BY lot
ORDER BY avg_dwell_min DESC;

-- 11. Flujo de operación desde el cliente (RPC) -----------------------------
-- SELECT api_register_departure(p_bus_id => 1, p_lot_id => 21);           -- registra salida
-- SELECT api_register_arrival(p_bus_id => 1, p_lot_id => 8);              -- registra llegada
-- SELECT api_create_trip(1, 21, 8, now() + interval '2 h', now() + interval '4 h', 45);
-- SELECT api_sell_ticket(p_trip_id => 10, p_seat_number => 12, p_passenger => 'Ana Pérez');
