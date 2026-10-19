-- =====================================================================
--  02_functions.sql  —  Business rules enforced inside the database
--  (spatial borders, capacity, seats, overlaps, arrival/departure flow)
-- =====================================================================
SET search_path = public, extensions;

-- ---------------------------------------------------------------------
-- Is a point inside the authorised service area (Cundinamarca + Bogotá)?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_in_service_area(p geometry)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    SELECT EXISTS (SELECT 1 FROM service_area sa WHERE ST_Covers(sa.geom, p));
$$;

-- Human-readable (Spanish) trip status for error messages.
CREATE OR REPLACE FUNCTION fn_status_es(p_status text)
RETURNS text
LANGUAGE sql IMMUTABLE
SET search_path = public, extensions
AS $$
    SELECT CASE p_status
        WHEN 'SCHEDULED'  THEN 'programado'
        WHEN 'IN_TRANSIT' THEN 'en ruta'
        WHEN 'ARRIVED'    THEN 'finalizado'
        WHEN 'CANCELLED'  THEN 'cancelado'
        ELSE p_status END;
$$;

-- Parking lots can only be created inside the department borders.
CREATE OR REPLACE FUNCTION trg_parking_lot_in_area()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    IF NOT fn_in_service_area(NEW.geom) THEN
        RAISE EXCEPTION 'La ubicación (%, %) está fuera de Cundinamarca. El sistema solo opera dentro de los límites del departamento.',
            round(ST_Y(NEW.geom)::numeric, 6), round(ST_X(NEW.geom)::numeric, 6);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER parking_lot_in_area
BEFORE INSERT OR UPDATE OF geom ON parking_lot
FOR EACH ROW EXECUTE FUNCTION trg_parking_lot_in_area();

-- ---------------------------------------------------------------------
-- A parking lot can never hold more buses than its maximum capacity.
-- The lot row is locked so two administrators cannot overbook it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_parking_stay_capacity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_capacity  smallint;
    v_name      text;
    v_occupied  integer;
BEGIN
    IF NEW.departed_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    SELECT capacity, municipality INTO v_capacity, v_name
    FROM parking_lot WHERE id = NEW.parking_lot_id
    FOR UPDATE;

    SELECT count(*) INTO v_occupied
    FROM parking_stay
    WHERE parking_lot_id = NEW.parking_lot_id AND departed_at IS NULL AND id <> NEW.id;

    IF v_occupied >= v_capacity THEN
        RAISE EXCEPTION 'El parqueadero % está lleno (% de % cupos ocupados).', v_name, v_occupied, v_capacity;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER parking_stay_capacity
BEFORE INSERT ON parking_stay
FOR EACH ROW EXECUTE FUNCTION trg_parking_stay_capacity();

-- ---------------------------------------------------------------------
-- A bus (and a driver) cannot be assigned to two overlapping trips.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_trip_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_conflict integer;
BEGIN
    IF NEW.status = 'CANCELLED' THEN
        RETURN NEW;
    END IF;

    SELECT t.id INTO v_conflict
    FROM trip t
    WHERE t.bus_id = NEW.bus_id
      AND t.id <> NEW.id
      AND t.status <> 'CANCELLED'
      AND tstzrange(t.scheduled_departure, t.scheduled_arrival) && tstzrange(NEW.scheduled_departure, NEW.scheduled_arrival)
    LIMIT 1;
    IF v_conflict IS NOT NULL THEN
        RAISE EXCEPTION 'El bus ya tiene el viaje #% en ese horario.', v_conflict;
    END IF;

    IF NEW.driver_id IS NOT NULL THEN
        SELECT t.id INTO v_conflict
        FROM trip t
        WHERE t.driver_id = NEW.driver_id
          AND t.id <> NEW.id
          AND t.status <> 'CANCELLED'
          AND tstzrange(t.scheduled_departure, t.scheduled_arrival) && tstzrange(NEW.scheduled_departure, NEW.scheduled_arrival)
        LIMIT 1;
        IF v_conflict IS NOT NULL THEN
            RAISE EXCEPTION 'El conductor ya tiene asignado el viaje #% en ese horario.', v_conflict;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trip_overlap
BEFORE INSERT OR UPDATE OF bus_id, driver_id, scheduled_departure, scheduled_arrival, status ON trip
FOR EACH ROW EXECUTE FUNCTION trg_trip_overlap();

-- ---------------------------------------------------------------------
-- Driver shifts of the same driver cannot overlap.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_shift_overlap()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM driver_shift s
        WHERE s.driver_id = NEW.driver_id AND s.id <> NEW.id
          AND tstzrange(s.starts_at, s.ends_at) && tstzrange(NEW.starts_at, NEW.ends_at)
    ) THEN
        RAISE EXCEPTION 'El conductor ya tiene un turno que se cruza con este horario.';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER shift_overlap
BEFORE INSERT OR UPDATE ON driver_shift
FOR EACH ROW EXECUTE FUNCTION trg_shift_overlap();

-- ---------------------------------------------------------------------
-- Seats: the seat must exist in the bus and the trip must still be open.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_ticket_seat()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_capacity smallint;
    v_status   text;
BEGIN
    SELECT b.seat_capacity, t.status INTO v_capacity, v_status
    FROM trip t JOIN bus b ON b.id = t.bus_id
    WHERE t.id = NEW.trip_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'El viaje #% no existe.', NEW.trip_id;
    END IF;
    IF v_status <> 'SCHEDULED' THEN
        RAISE EXCEPTION 'Solo se pueden vender puestos antes de la salida (el viaje está %).', fn_status_es(v_status);
    END IF;
    IF NEW.seat_number > v_capacity THEN
        RAISE EXCEPTION 'El puesto % no existe: este bus tiene % puestos.', NEW.seat_number, v_capacity;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER ticket_seat
BEFORE INSERT ON ticket
FOR EACH ROW EXECUTE FUNCTION trg_ticket_seat();

-- ---------------------------------------------------------------------
-- Only the administrator of a lot (or a system admin) may record
-- movements in that lot.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_assert_lot_admin(p_user_id integer, p_lot_id integer)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_role text;
    v_lot  integer;
BEGIN
    IF p_user_id IS NULL THEN
        RETURN;
    END IF;
    SELECT role, parking_lot_id INTO v_role, v_lot FROM app_user WHERE id = p_user_id;
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'El usuario #% no existe.', p_user_id;
    END IF;
    IF v_role = 'LOT_ADMIN' AND v_lot <> p_lot_id THEN
        RAISE EXCEPTION 'Este usuario no es el administrador de ese parqueadero.';
    END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- ARRIVAL: the parking lot administrator records that a bus entered the
-- lot. Closes the trip that brought it (if any) and opens a parking stay.
-- Returns the parking_stay id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_register_arrival(
    p_bus_id   integer,
    p_lot_id   integer,
    p_trip_id  integer     DEFAULT NULL,
    p_user_id  integer     DEFAULT NULL,
    p_at       timestamptz DEFAULT now()
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_trip     trip%ROWTYPE;
    v_parked   text;
    v_stay_id  integer;
BEGIN
    PERFORM fn_assert_lot_admin(p_user_id, p_lot_id);

    SELECT pl.municipality INTO v_parked
    FROM parking_stay ps JOIN parking_lot pl ON pl.id = ps.parking_lot_id
    WHERE ps.bus_id = p_bus_id AND ps.departed_at IS NULL;
    IF v_parked IS NOT NULL THEN
        RAISE EXCEPTION 'Este bus ya está parqueado en %. Registre primero su salida.', v_parked;
    END IF;

    IF p_trip_id IS NULL THEN
        SELECT * INTO v_trip FROM trip
        WHERE bus_id = p_bus_id AND status = 'IN_TRANSIT'
        ORDER BY actual_departure DESC LIMIT 1;
    ELSE
        SELECT * INTO v_trip FROM trip WHERE id = p_trip_id;
        IF v_trip.id IS NULL THEN
            RAISE EXCEPTION 'El viaje #% no existe.', p_trip_id;
        END IF;
    END IF;

    IF v_trip.id IS NOT NULL THEN
        IF v_trip.bus_id <> p_bus_id THEN
            RAISE EXCEPTION 'El viaje #% pertenece a otro bus.', v_trip.id;
        END IF;
        IF v_trip.destination_lot_id <> p_lot_id THEN
            RAISE EXCEPTION 'El viaje #% se dirige a otro parqueadero.', v_trip.id;
        END IF;
        IF v_trip.status <> 'IN_TRANSIT' THEN
            RAISE EXCEPTION 'El viaje #% está % — nunca se registró su salida.', v_trip.id, fn_status_es(v_trip.status);
        END IF;
        IF p_at < v_trip.actual_departure THEN
            RAISE EXCEPTION 'La hora de llegada no puede ser anterior a la de salida.';
        END IF;
        UPDATE trip SET actual_arrival = p_at, status = 'ARRIVED' WHERE id = v_trip.id;
    END IF;

    INSERT INTO parking_stay (bus_id, parking_lot_id, arrival_trip_id, arrived_at, arrival_registered_by)
    VALUES (p_bus_id, p_lot_id, v_trip.id, p_at, p_user_id)
    RETURNING id INTO v_stay_id;

    RETURN v_stay_id;
END;
$$;

-- ---------------------------------------------------------------------
-- DEPARTURE: the administrator records that a parked bus left the lot on
-- a scheduled trip. Closes the parking stay (→ real dwell time) and puts
-- the trip IN_TRANSIT. Returns the trip id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_register_departure(
    p_bus_id   integer,
    p_lot_id   integer,
    p_trip_id  integer     DEFAULT NULL,
    p_user_id  integer     DEFAULT NULL,
    p_at       timestamptz DEFAULT now()
)
RETURNS integer
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    v_stay  parking_stay%ROWTYPE;
    v_trip  trip%ROWTYPE;
BEGIN
    PERFORM fn_assert_lot_admin(p_user_id, p_lot_id);

    SELECT * INTO v_stay FROM parking_stay
    WHERE bus_id = p_bus_id AND parking_lot_id = p_lot_id AND departed_at IS NULL;
    IF v_stay.id IS NULL THEN
        RAISE EXCEPTION 'Este bus no está parqueado en este parqueadero.';
    END IF;
    IF p_at < v_stay.arrived_at THEN
        RAISE EXCEPTION 'La hora de salida no puede ser anterior a la de llegada.';
    END IF;

    IF p_trip_id IS NULL THEN
        SELECT * INTO v_trip FROM trip
        WHERE bus_id = p_bus_id AND origin_lot_id = p_lot_id AND status = 'SCHEDULED'
        ORDER BY scheduled_departure LIMIT 1;
        IF v_trip.id IS NULL THEN
            RAISE EXCEPTION 'No hay un viaje programado para este bus desde este parqueadero. Registre primero el viaje.';
        END IF;
    ELSE
        SELECT * INTO v_trip FROM trip WHERE id = p_trip_id;
        IF v_trip.id IS NULL THEN
            RAISE EXCEPTION 'El viaje #% no existe.', p_trip_id;
        END IF;
        IF v_trip.bus_id <> p_bus_id OR v_trip.origin_lot_id <> p_lot_id THEN
            RAISE EXCEPTION 'El viaje #% no sale de este parqueadero con este bus.', v_trip.id;
        END IF;
        IF v_trip.status <> 'SCHEDULED' THEN
            RAISE EXCEPTION 'El viaje #% ya está %.', v_trip.id, fn_status_es(v_trip.status);
        END IF;
    END IF;

    UPDATE parking_stay
       SET departed_at = p_at, departure_trip_id = v_trip.id, departure_registered_by = p_user_id
     WHERE id = v_stay.id;

    UPDATE trip SET actual_departure = p_at, status = 'IN_TRANSIT' WHERE id = v_trip.id;

    RETURN v_trip.id;
END;
$$;
