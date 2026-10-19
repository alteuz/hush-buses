-- =====================================================================
--  06_api.sql  —  Security (RLS) + public API exposed by Supabase
--
--  Clients (web + Cordova app) talk to PostgREST with the publishable key:
--    · READ  : SELECT on tables/views (RLS policy "public read")
--    · WRITE : only through the api_* functions below (SECURITY DEFINER),
--              which run every business rule of 02_functions.sql.
--  Direct INSERT/UPDATE/DELETE is impossible: no write policies exist.
-- =====================================================================
SET search_path = public, extensions;

-- ---------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['service_area','parking_lot','app_user','driver','driver_shift',
                             'bus','trip','ticket','parking_stay']
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY "public read" ON %I FOR SELECT TO anon, authenticated USING (true)', t);
    END LOOP;
END $$;

-- Internal helpers are not callable from the API. They are revoked one by one
-- (not "ALL FUNCTIONS IN SCHEMA public") because PostGIS may live in public.
REVOKE EXECUTE ON FUNCTION
    fn_register_arrival(integer, integer, integer, integer, timestamptz),
    fn_register_departure(integer, integer, integer, integer, timestamptz),
    fn_assert_lot_admin(integer, integer),
    fn_seed_operations(),
    fn_free_driver(timestamptz, timestamptz),
    fn_trip_minutes(integer, integer)
FROM PUBLIC, anon, authenticated;
-- The read-only border check is used by api_nearest_lots.
GRANT EXECUTE ON FUNCTION fn_in_service_area(geometry) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- READ endpoints (JSON shaped for the map)
-- ---------------------------------------------------------------------

-- Department borders as a GeoJSON FeatureCollection.
CREATE OR REPLACE FUNCTION api_service_area()
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT json_build_object(
        'type', 'FeatureCollection',
        'features', json_agg(json_build_object(
            'type', 'Feature',
            'properties', json_build_object('name', name),
            'geometry', ST_AsGeoJSON(geom, 5)::json)))
    FROM service_area;
$$;

-- Everything the map needs in one round trip.
CREATE OR REPLACE FUNCTION api_overview()
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT json_build_object(
        'generated_at', now(),
        'lots', (
            SELECT json_agg(l ORDER BY l.municipality) FROM (
                SELECT a.*,
                       (SELECT COALESCE(json_agg(p ORDER BY p.next_departure NULLS LAST), '[]'::json)
                          FROM v_parked_buses p WHERE p.parking_lot_id = a.id) AS parked,
                       (SELECT COALESCE(json_agg(json_build_object('full_name', s.full_name, 'starts_at', s.starts_at,
                                                                   'ends_at', s.ends_at, 'status', s.status)
                                                 ORDER BY s.starts_at), '[]'::json)
                          FROM v_driver_schedule s
                         WHERE s.base_lot_id = a.id AND s.status <> 'FINISHED') AS drivers
                FROM v_parking_availability a
            ) l
        ),
        'buses', (SELECT json_agg(b ORDER BY b.internal_code) FROM v_bus_location b),
        'stats', (
            SELECT json_build_object(
                'lots',        (SELECT count(*) FROM parking_lot),
                'bays',        (SELECT sum(capacity) FROM parking_lot),
                'occupied',    (SELECT count(*) FROM parking_stay WHERE departed_at IS NULL),
                'buses',       (SELECT count(*) FROM bus WHERE active),
                'in_transit',  (SELECT count(*) FROM trip WHERE status = 'IN_TRANSIT'),
                'departures_next_hour', (SELECT count(*) FROM trip WHERE status = 'SCHEDULED'
                                           AND scheduled_departure BETWEEN now() AND now() + interval '1 hour'),
                'seats_available', (SELECT COALESCE(sum(seats_available), 0) FROM v_trip_detail WHERE status = 'SCHEDULED'),
                'drivers_on_duty', (SELECT count(*) FROM v_driver_schedule WHERE status = 'ON_DUTY')
            )
        )
    );
$$;

-- Detail panel of one parking lot.
CREATE OR REPLACE FUNCTION api_lot_detail(p_lot_id integer)
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT json_build_object(
        'lot', (SELECT row_to_json(a) FROM v_parking_availability a WHERE a.id = p_lot_id),
        'parked', (SELECT COALESCE(json_agg(p ORDER BY p.arrived_at), '[]'::json)
                     FROM v_parked_buses p WHERE p.parking_lot_id = p_lot_id),
        'departures', (SELECT COALESCE(json_agg(t ORDER BY t.scheduled_departure), '[]'::json)
                         FROM v_trip_detail t
                        WHERE t.origin_lot_id = p_lot_id AND t.status = 'SCHEDULED'),
        'arrivals', (SELECT COALESCE(json_agg(t ORDER BY t.scheduled_arrival), '[]'::json)
                       FROM v_trip_detail t
                      WHERE t.destination_lot_id = p_lot_id AND t.status = 'IN_TRANSIT'),
        'drivers', (SELECT COALESCE(json_agg(s ORDER BY s.starts_at), '[]'::json)
                      FROM v_driver_schedule s WHERE s.base_lot_id = p_lot_id),
        'history', (SELECT COALESCE(json_agg(h ORDER BY h.departed_at DESC), '[]'::json)
                      FROM (SELECT * FROM v_stay_history WHERE parking_lot_id = p_lot_id
                            ORDER BY departed_at DESC LIMIT 8) h),
        'avg_dwell_min', (SELECT round(avg(dwell_min))::int FROM v_stay_history WHERE parking_lot_id = p_lot_id)
    );
$$;

-- Geocoding companion: nearest parking lots to a coordinate (KNN on the
-- GiST index with the <-> operator) + whether the point is inside the
-- department.
CREATE OR REPLACE FUNCTION api_nearest_lots(p_lat float8, p_lng float8, p_limit integer DEFAULT 5)
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    WITH q AS (SELECT ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326) AS g)
    SELECT json_build_object(
        'inside_service_area', fn_in_service_area((SELECT g FROM q)),
        'lots', (
            SELECT COALESCE(json_agg(n), '[]'::json) FROM (
                SELECT a.id, a.code, a.municipality, a.capacity, a.available, a.lat, a.lng,
                       round((ST_DistanceSphere(pl.geom, q.g) / 1000)::numeric, 1)::float8 AS distance_km
                FROM parking_lot pl
                JOIN v_parking_availability a ON a.id = pl.id
                CROSS JOIN q
                ORDER BY pl.geom <-> q.g
                LIMIT LEAST(GREATEST(p_limit, 1), 21)
            ) n
        )
    );
$$;

-- Seat map of a trip.
CREATE OR REPLACE FUNCTION api_trip_seats(p_trip_id integer)
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT json_build_object(
        'trip', (SELECT row_to_json(t) FROM v_trip_detail t WHERE t.id = p_trip_id),
        'sold', (SELECT COALESCE(json_agg(seat_number ORDER BY seat_number), '[]'::json)
                   FROM ticket WHERE trip_id = p_trip_id)
    );
$$;

-- Lists for the forms.
CREATE OR REPLACE FUNCTION api_catalog()
RETURNS json
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT json_build_object(
        'lots',    (SELECT json_agg(json_build_object('id', id, 'code', code, 'municipality', municipality, 'capacity', capacity) ORDER BY municipality) FROM parking_lot),
        'buses',   (SELECT json_agg(json_build_object('id', id, 'plate', plate, 'internal_code', internal_code, 'seat_capacity', seat_capacity) ORDER BY internal_code) FROM bus WHERE active),
        'drivers', (SELECT json_agg(json_build_object('id', id, 'full_name', full_name) ORDER BY full_name) FROM driver),
        'users',   (SELECT json_agg(json_build_object('id', id, 'full_name', full_name, 'role', role, 'parking_lot_id', parking_lot_id) ORDER BY id) FROM app_user)
    );
$$;

-- ---------------------------------------------------------------------
-- WRITE endpoints (run with the owner's rights, rules enforced in SQL)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api_register_arrival(
    p_bus_id integer, p_lot_id integer, p_trip_id integer DEFAULT NULL,
    p_user_id integer DEFAULT NULL, p_at timestamptz DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN json_build_object('stay_id',
        fn_register_arrival(p_bus_id, p_lot_id, p_trip_id, p_user_id, COALESCE(p_at, now())));
END;
$$;

CREATE OR REPLACE FUNCTION api_register_departure(
    p_bus_id integer, p_lot_id integer, p_trip_id integer DEFAULT NULL,
    p_user_id integer DEFAULT NULL, p_at timestamptz DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    RETURN json_build_object('trip_id',
        fn_register_departure(p_bus_id, p_lot_id, p_trip_id, p_user_id, COALESCE(p_at, now())));
END;
$$;

-- Register the bus information: origin, destination, departure time,
-- arrival time and planned dwell time at the destination lot.
CREATE OR REPLACE FUNCTION api_create_trip(
    p_bus_id integer, p_origin_lot_id integer, p_destination_lot_id integer,
    p_departure timestamptz, p_arrival timestamptz, p_dwell_minutes integer DEFAULT 30,
    p_driver_id integer DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_id integer;
BEGIN
    IF p_departure < now() - interval '5 minutes' THEN
        RAISE EXCEPTION 'La hora de salida ya pasó.';
    END IF;
    INSERT INTO trip (bus_id, driver_id, origin_lot_id, destination_lot_id,
                      scheduled_departure, scheduled_arrival, dwell_minutes)
    VALUES (p_bus_id, p_driver_id, p_origin_lot_id, p_destination_lot_id,
            p_departure, p_arrival, p_dwell_minutes)
    RETURNING id INTO v_id;
    RETURN json_build_object('trip_id', v_id);
END;
$$;

CREATE OR REPLACE FUNCTION api_sell_ticket(p_trip_id integer, p_seat_number integer, p_passenger text DEFAULT NULL)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO ticket (trip_id, seat_number, passenger_name)
    VALUES (p_trip_id, p_seat_number, NULLIF(trim(p_passenger), ''))
    RETURNING id INTO v_id;
    RETURN json_build_object('ticket_id', v_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'El puesto % ya fue vendido.', p_seat_number;
END;
$$;

CREATE OR REPLACE FUNCTION api_create_parking_lot(
    p_code text, p_municipality text, p_name text, p_capacity integer, p_lat float8, p_lng float8)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO parking_lot (code, municipality, name, capacity, geom)
    VALUES (upper(p_code), p_municipality, p_name, p_capacity, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326))
    RETURNING id INTO v_id;
    INSERT INTO app_user (username, full_name, role, parking_lot_id)
    VALUES ('admin.' || lower(p_code), 'Administrador · ' || p_municipality, 'LOT_ADMIN', v_id);
    RETURN json_build_object('parking_lot_id', v_id);
END;
$$;

-- Regenerates the demo operations relative to the current time.
CREATE OR REPLACE FUNCTION api_reset_demo()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
    PERFORM fn_seed_operations();
    RETURN json_build_object('ok', true, 'at', now());
END;
$$;

GRANT EXECUTE ON FUNCTION
    api_service_area(), api_overview(), api_lot_detail(integer),
    api_nearest_lots(float8, float8, integer), api_trip_seats(integer), api_catalog(),
    api_register_arrival(integer, integer, integer, integer, timestamptz),
    api_register_departure(integer, integer, integer, integer, timestamptz),
    api_create_trip(integer, integer, integer, timestamptz, timestamptz, integer, integer),
    api_sell_ticket(integer, integer, text),
    api_create_parking_lot(text, text, text, integer, float8, float8),
    api_reset_demo()
TO anon, authenticated;
