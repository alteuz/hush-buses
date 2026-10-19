-- =====================================================================
--  07_hardening.sql  —  Fixes from the code review (before public deploy)
-- =====================================================================
SET search_path = public, extensions;

-- 1. Personal data: drivers' ID number and phone are not public.
--    Clients may only read the columns the map needs.
REVOKE SELECT ON driver FROM anon, authenticated;
GRANT SELECT (id, full_name, license_category) ON driver TO anon, authenticated;

-- 2. Creating parking lots is an administrative task with no public UI.
REVOKE EXECUTE ON FUNCTION api_create_parking_lot(text, text, text, integer, float8, float8)
    FROM PUBLIC, anon, authenticated;

-- 3. Times recorded by the lot administrator cannot be in the future.
CREATE OR REPLACE FUNCTION fn_assert_not_future(p_at timestamptz)
RETURNS void LANGUAGE plpgsql STABLE SET search_path = public, extensions
AS $$
BEGIN
    IF p_at > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'La hora registrada no puede estar en el futuro.';
    END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION fn_assert_not_future(timestamptz) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION api_register_arrival(
    p_bus_id integer, p_lot_id integer, p_trip_id integer DEFAULT NULL,
    p_user_id integer DEFAULT NULL, p_at timestamptz DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
BEGIN
    PERFORM fn_assert_not_future(COALESCE(p_at, now()));
    RETURN json_build_object('stay_id',
        fn_register_arrival(p_bus_id, p_lot_id, p_trip_id, p_user_id, COALESCE(p_at, now())));
END;
$$;

CREATE OR REPLACE FUNCTION api_register_departure(
    p_bus_id integer, p_lot_id integer, p_trip_id integer DEFAULT NULL,
    p_user_id integer DEFAULT NULL, p_at timestamptz DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
BEGIN
    PERFORM fn_assert_not_future(COALESCE(p_at, now()));
    RETURN json_build_object('trip_id',
        fn_register_departure(p_bus_id, p_lot_id, p_trip_id, p_user_id, COALESCE(p_at, now())));
END;
$$;

-- 4. Trip registration: readable messages instead of constraint errors.
CREATE OR REPLACE FUNCTION api_create_trip(
    p_bus_id integer, p_origin_lot_id integer, p_destination_lot_id integer,
    p_departure timestamptz, p_arrival timestamptz, p_dwell_minutes integer DEFAULT 30,
    p_driver_id integer DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_id integer;
BEGIN
    IF p_origin_lot_id = p_destination_lot_id THEN
        RAISE EXCEPTION 'El origen y el destino deben ser diferentes.';
    END IF;
    IF p_arrival <= p_departure THEN
        RAISE EXCEPTION 'La hora de llegada debe ser posterior a la hora de salida.';
    END IF;
    IF p_arrival - p_departure > interval '24 hours' THEN
        RAISE EXCEPTION 'Un viaje no puede durar más de 24 horas.';
    END IF;
    IF p_dwell_minutes IS NULL OR p_dwell_minutes NOT BETWEEN 0 AND 1440 THEN
        RAISE EXCEPTION 'La permanencia debe estar entre 0 y 1440 minutos.';
    END IF;
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

-- 5. Seat sale: passenger names are trimmed to the column size.
CREATE OR REPLACE FUNCTION api_sell_ticket(p_trip_id integer, p_seat_number integer, p_passenger text DEFAULT NULL)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $$
DECLARE v_id integer;
BEGIN
    INSERT INTO ticket (trip_id, seat_number, passenger_name)
    VALUES (p_trip_id, p_seat_number, NULLIF(left(trim(p_passenger), 120), ''))
    RETURNING id INTO v_id;
    RETURN json_build_object('ticket_id', v_id);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'El puesto % ya fue vendido.', p_seat_number;
END;
$$;
