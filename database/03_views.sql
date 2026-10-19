-- =====================================================================
--  03_views.sql  —  Read models used by the map and the mobile app
--  security_invoker = true → the views respect the RLS of the caller.
-- =====================================================================
SET search_path = public, extensions;

-- (a) Availability of parking spaces -----------------------------------
CREATE OR REPLACE VIEW v_parking_availability WITH (security_invoker = true) AS
SELECT pl.id,
       pl.code,
       pl.municipality,
       pl.name,
       pl.capacity::int                                         AS capacity,
       COALESCE(o.occupied, 0)::int                             AS occupied,
       (pl.capacity - COALESCE(o.occupied, 0))::int             AS available,
       round(100.0 * COALESCE(o.occupied, 0) / pl.capacity)::int AS occupancy_pct,
       ST_Y(pl.geom)::float8                                    AS lat,
       ST_X(pl.geom)::float8                                    AS lng
FROM parking_lot pl
LEFT JOIN (
    SELECT parking_lot_id, count(*) AS occupied
    FROM parking_stay
    WHERE departed_at IS NULL
    GROUP BY parking_lot_id
) o ON o.parking_lot_id = pl.id;

-- (c) Trips with seats sold / available --------------------------------
CREATE OR REPLACE VIEW v_trip_detail WITH (security_invoker = true) AS
SELECT t.id,
       t.status,
       t.bus_id,
       b.plate,
       b.internal_code,
       b.seat_capacity::int                                AS seat_capacity,
       t.driver_id,
       d.full_name                                         AS driver_name,
       t.origin_lot_id,
       o.municipality                                      AS origin,
       t.destination_lot_id,
       de.municipality                                     AS destination,
       t.scheduled_departure,
       t.scheduled_arrival,
       t.actual_departure,
       t.actual_arrival,
       t.dwell_minutes::int                                AS dwell_minutes,
       COALESCE(s.sold, 0)::int                            AS seats_sold,
       (b.seat_capacity - COALESCE(s.sold, 0))::int        AS seats_available,
       round((ST_DistanceSphere(o.geom, de.geom) / 1000)::numeric, 1)::float8 AS distance_km
FROM trip t
JOIN bus b          ON b.id  = t.bus_id
JOIN parking_lot o  ON o.id  = t.origin_lot_id
JOIN parking_lot de ON de.id = t.destination_lot_id
LEFT JOIN driver d  ON d.id  = t.driver_id
LEFT JOIN (SELECT trip_id, count(*) AS sold FROM ticket GROUP BY trip_id) s ON s.trip_id = t.id;

-- Buses currently parked + their next departure (dwell time so far) ----
CREATE OR REPLACE VIEW v_parked_buses WITH (security_invoker = true) AS
SELECT ps.id                                                AS stay_id,
       ps.parking_lot_id,
       pl.municipality                                      AS lot,
       ps.bus_id,
       b.plate,
       b.internal_code,
       b.seat_capacity::int                                 AS seat_capacity,
       ps.arrived_at,
       (extract(epoch FROM now() - ps.arrived_at) / 60)::int AS dwell_so_far_min,
       arr.dwell_minutes::int                               AS planned_dwell_min,
       ps.arrived_at + make_interval(mins => arr.dwell_minutes::int) AS planned_release,
       arr_o.municipality                                   AS arrived_from,
       nt.id                                                AS next_trip_id,
       nt.scheduled_departure                               AS next_departure,
       nt.destination                                       AS next_destination,
       nt.driver_name                                       AS next_driver,
       nt.seats_sold                                        AS next_seats_sold,
       nt.seats_available                                   AS next_seats_available
FROM parking_stay ps
JOIN bus b          ON b.id  = ps.bus_id
JOIN parking_lot pl ON pl.id = ps.parking_lot_id
LEFT JOIN trip arr          ON arr.id   = ps.arrival_trip_id
LEFT JOIN parking_lot arr_o ON arr_o.id = arr.origin_lot_id
LEFT JOIN LATERAL (
    SELECT td.*
    FROM v_trip_detail td
    WHERE td.bus_id = ps.bus_id
      AND td.origin_lot_id = ps.parking_lot_id
      AND td.status = 'SCHEDULED'
    ORDER BY td.scheduled_departure
    LIMIT 1
) nt ON true
WHERE ps.departed_at IS NULL;

-- (b) Location of buses -------------------------------------------------
-- No real-time GPS is required: the location is the parking lot where the
-- bus is parked. While a trip is IN_TRANSIT the position is *estimated*
-- by interpolating along the origin→destination line by elapsed time.
CREATE OR REPLACE VIEW v_bus_location WITH (security_invoker = true) AS
SELECT b.id                       AS bus_id,
       b.plate,
       b.internal_code,
       b.brand,
       b.seat_capacity::int       AS seat_capacity,
       CASE WHEN ps.id IS NOT NULL THEN 'PARKED'
            WHEN tr.id IS NOT NULL THEN 'IN_TRANSIT'
            ELSE 'IDLE' END       AS state,
       ps.parking_lot_id,
       pl.municipality            AS parked_at,
       ps.arrived_at,
       tr.id                      AS trip_id,
       tr.origin,
       tr.destination,
       tr.origin_lot_id,
       tr.destination_lot_id,
       tr.actual_departure,
       tr.scheduled_arrival,
       tr.progress,
       ST_Y(loc.g)::float8        AS lat,
       ST_X(loc.g)::float8        AS lng,
       nt.id                      AS next_trip_id,
       nt.scheduled_departure     AS next_departure,
       nt.destination             AS next_destination,
       nt.seats_available         AS next_seats_available
FROM bus b
LEFT JOIN parking_stay ps ON ps.bus_id = b.id AND ps.departed_at IS NULL
LEFT JOIN parking_lot pl  ON pl.id = ps.parking_lot_id
LEFT JOIN LATERAL (
    SELECT t.id, o.municipality AS origin, d.municipality AS destination,
           t.origin_lot_id, t.destination_lot_id,
           t.actual_departure, t.scheduled_arrival, o.geom AS og, d.geom AS dg,
           LEAST(1, GREATEST(0,
               extract(epoch FROM now() - t.actual_departure)
               / NULLIF(extract(epoch FROM t.scheduled_arrival - t.scheduled_departure), 0)
           ))::float8 AS progress
    FROM trip t
    JOIN parking_lot o ON o.id = t.origin_lot_id
    JOIN parking_lot d ON d.id = t.destination_lot_id
    WHERE t.bus_id = b.id AND t.status = 'IN_TRANSIT'
    ORDER BY t.actual_departure DESC
    LIMIT 1
) tr ON ps.id IS NULL
LEFT JOIN LATERAL (
    SELECT l.geom
    FROM parking_stay s JOIN parking_lot l ON l.id = s.parking_lot_id
    WHERE s.bus_id = b.id
    ORDER BY s.arrived_at DESC
    LIMIT 1
) last_seen ON true
LEFT JOIN LATERAL (
    SELECT td.id, td.scheduled_departure, td.destination, td.seats_available
    FROM v_trip_detail td
    WHERE td.bus_id = b.id AND td.status = 'SCHEDULED'
    ORDER BY td.scheduled_departure
    LIMIT 1
) nt ON true
CROSS JOIN LATERAL (
    SELECT CASE
             WHEN ps.id IS NOT NULL THEN pl.geom
             WHEN tr.id IS NOT NULL THEN ST_LineInterpolatePoint(ST_MakeLine(tr.og, tr.dg), tr.progress)
             ELSE last_seen.geom
           END AS g
) loc
WHERE b.active;

-- Driver service schedules ---------------------------------------------
CREATE OR REPLACE VIEW v_driver_schedule WITH (security_invoker = true) AS
SELECT s.id                AS shift_id,
       d.id                AS driver_id,
       d.full_name,
       d.license_category,
       s.base_lot_id,
       pl.municipality     AS base_lot,
       s.starts_at,
       s.ends_at,
       CASE WHEN now() < s.starts_at THEN 'UPCOMING'
            WHEN now() > s.ends_at   THEN 'FINISHED'
            ELSE 'ON_DUTY' END AS status,
       (SELECT count(*) FROM trip t
         WHERE t.driver_id = d.id AND t.status <> 'CANCELLED'
           AND t.scheduled_departure < s.ends_at AND t.scheduled_arrival > s.starts_at)::int AS trips
FROM driver_shift s
JOIN driver d       ON d.id  = s.driver_id
JOIN parking_lot pl ON pl.id = s.base_lot_id;

-- Dwell-time history (closed stays) ------------------------------------
CREATE OR REPLACE VIEW v_stay_history WITH (security_invoker = true) AS
SELECT ps.id, ps.parking_lot_id, pl.municipality AS lot, ps.bus_id, b.plate,
       ps.arrived_at, ps.departed_at,
       (extract(epoch FROM ps.departed_at - ps.arrived_at) / 60)::int AS dwell_min
FROM parking_stay ps
JOIN bus b          ON b.id  = ps.bus_id
JOIN parking_lot pl ON pl.id = ps.parking_lot_id
WHERE ps.departed_at IS NOT NULL;
