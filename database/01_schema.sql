-- =====================================================================
--  Hush  ·  Workshop 2: Geocoding and Use of Dynamic Maps
--  01_schema.sql  —  Tables, constraints and spatial indexes
--  Target: Supabase · PostgreSQL 17 with PostGIS 3.3+
--  SRID 4326 (WGS 84, lat/lng as used by GPS and OpenStreetMap)
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;   -- Supabase keeps extensions out of "public"
SET search_path = public, extensions;

-- ---------------------------------------------------------------------
-- Service area: the system may only operate inside these borders.
-- Two rows: Department of Cundinamarca + Bogotá D.C. (its capital district,
-- which OpenStreetMap maps as a separate administrative polygon).
-- ---------------------------------------------------------------------
CREATE TABLE service_area (
    id      serial       PRIMARY KEY,
    name    varchar(80)  NOT NULL UNIQUE,
    geom    geometry(MultiPolygon, 4326) NOT NULL
);
CREATE INDEX service_area_gix ON service_area USING gist (geom);

-- ---------------------------------------------------------------------
-- Parking lots (bus terminals) owned by the company.
-- ---------------------------------------------------------------------
CREATE TABLE parking_lot (
    id            serial       PRIMARY KEY,
    code          varchar(4)   NOT NULL UNIQUE CHECK (code ~ '^[A-Z]{3,4}$'),
    municipality  varchar(60)  NOT NULL UNIQUE,
    name          varchar(120) NOT NULL,
    capacity      smallint     NOT NULL CHECK (capacity BETWEEN 1 AND 50),
    geom          geometry(Point, 4326) NOT NULL,
    created_at    timestamptz  NOT NULL DEFAULT now()
);
CREATE INDEX parking_lot_gix ON parking_lot USING gist (geom);

-- ---------------------------------------------------------------------
-- System users. A LOT_ADMIN is the parking lot administrator who records
-- arrivals and departures for his/her own parking lot.
-- ---------------------------------------------------------------------
CREATE TABLE app_user (
    id              serial       PRIMARY KEY,
    username        varchar(40)  NOT NULL UNIQUE,
    full_name       varchar(120) NOT NULL,
    role            varchar(16)  NOT NULL CHECK (role IN ('SYSTEM_ADMIN', 'LOT_ADMIN')),
    parking_lot_id  integer      REFERENCES parking_lot (id),
    CHECK (role = 'SYSTEM_ADMIN' OR parking_lot_id IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- Drivers and their service schedules (shifts).
-- ---------------------------------------------------------------------
CREATE TABLE driver (
    id                serial       PRIMARY KEY,
    document_id       varchar(20)  NOT NULL UNIQUE,
    full_name         varchar(120) NOT NULL,
    phone             varchar(20),
    license_category  varchar(2)   NOT NULL DEFAULT 'C2' CHECK (license_category IN ('C1', 'C2', 'C3'))
);

CREATE TABLE driver_shift (
    id           serial      PRIMARY KEY,
    driver_id    integer     NOT NULL REFERENCES driver (id) ON DELETE CASCADE,
    base_lot_id  integer     NOT NULL REFERENCES parking_lot (id),
    starts_at    timestamptz NOT NULL,
    ends_at      timestamptz NOT NULL,
    CHECK (ends_at > starts_at),
    CHECK (ends_at - starts_at <= interval '12 hours')   -- labour rule
);
CREATE INDEX driver_shift_time_idx ON driver_shift (starts_at, ends_at);

-- ---------------------------------------------------------------------
-- Fleet.
-- ---------------------------------------------------------------------
CREATE TABLE bus (
    id             serial      PRIMARY KEY,
    plate          varchar(6)  NOT NULL UNIQUE CHECK (plate ~ '^[A-Z]{3}[0-9]{3}$'),  -- Colombian plate
    internal_code  varchar(10) NOT NULL UNIQUE,
    brand          varchar(40),
    model_year     smallint    CHECK (model_year BETWEEN 1990 AND 2100),
    seat_capacity  smallint    NOT NULL CHECK (seat_capacity BETWEEN 10 AND 60),
    active         boolean     NOT NULL DEFAULT true
);

-- ---------------------------------------------------------------------
-- Trip = the "bus information" required by the workshop:
--   origin, destination, departure time from origin,
--   arrival time at destination and parking-lot dwell time.
-- ---------------------------------------------------------------------
CREATE TABLE trip (
    id                   serial      PRIMARY KEY,
    bus_id               integer     NOT NULL REFERENCES bus (id),
    driver_id            integer     REFERENCES driver (id),
    origin_lot_id        integer     NOT NULL REFERENCES parking_lot (id),
    destination_lot_id   integer     NOT NULL REFERENCES parking_lot (id),
    scheduled_departure  timestamptz NOT NULL,
    scheduled_arrival    timestamptz NOT NULL,
    dwell_minutes        smallint    NOT NULL DEFAULT 30 CHECK (dwell_minutes BETWEEN 0 AND 1440),
    actual_departure     timestamptz,
    actual_arrival       timestamptz,
    status               varchar(12) NOT NULL DEFAULT 'SCHEDULED'
                         CHECK (status IN ('SCHEDULED', 'IN_TRANSIT', 'ARRIVED', 'CANCELLED')),
    created_at           timestamptz NOT NULL DEFAULT now(),
    CHECK (origin_lot_id <> destination_lot_id),
    CHECK (scheduled_arrival > scheduled_departure),
    CHECK (actual_arrival IS NULL OR actual_departure IS NULL OR actual_arrival >= actual_departure)
);
CREATE INDEX trip_bus_idx    ON trip (bus_id, scheduled_departure);
CREATE INDEX trip_origin_idx ON trip (origin_lot_id, scheduled_departure);
CREATE INDEX trip_status_idx ON trip (status);

-- ---------------------------------------------------------------------
-- Seats sold per trip  →  "availability of seats per bus".
-- ---------------------------------------------------------------------
CREATE TABLE ticket (
    id              serial       PRIMARY KEY,
    trip_id         integer      NOT NULL REFERENCES trip (id) ON DELETE CASCADE,
    seat_number     smallint     NOT NULL CHECK (seat_number > 0),
    passenger_name  varchar(120),
    sold_at         timestamptz  NOT NULL DEFAULT now(),
    UNIQUE (trip_id, seat_number)
);

-- ---------------------------------------------------------------------
-- Parking stay = one arrival + (later) one departure of a bus in a lot,
-- recorded by the parking lot administrator. Its interval is the
-- actual dwell time. The bus location is derived from the open stay.
-- ---------------------------------------------------------------------
CREATE TABLE parking_stay (
    id                       serial      PRIMARY KEY,
    bus_id                   integer     NOT NULL REFERENCES bus (id),
    parking_lot_id           integer     NOT NULL REFERENCES parking_lot (id),
    arrival_trip_id          integer     REFERENCES trip (id),
    departure_trip_id        integer     REFERENCES trip (id),
    arrived_at               timestamptz NOT NULL,
    departed_at              timestamptz,
    arrival_registered_by    integer     REFERENCES app_user (id),
    departure_registered_by  integer     REFERENCES app_user (id),
    CHECK (departed_at IS NULL OR departed_at >= arrived_at)
);
-- A bus can only be parked in one place at a time.
CREATE UNIQUE INDEX parking_stay_open_bus_uq ON parking_stay (bus_id) WHERE departed_at IS NULL;
CREATE INDEX parking_stay_open_lot_idx ON parking_stay (parking_lot_id) WHERE departed_at IS NULL;
