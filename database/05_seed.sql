-- =====================================================================
--  05_seed.sql  —  Reference data from the workshop + demo operations
-- =====================================================================
SET search_path = public, extensions;

-- ---------------------------------------------------------------------
-- The 21 parking lots given by the company (workshop table).
-- ST_MakePoint takes (longitude, latitude).
-- ---------------------------------------------------------------------
INSERT INTO parking_lot (code, municipality, name, capacity, geom) VALUES
 ('CHO', 'Chocontá',      'Terminal Chocontá',       2, ST_SetSRID(ST_MakePoint(-73.687044, 5.146678), 4326)),
 ('TIB', 'Tibiritá',      'Terminal Tibiritá',       3, ST_SetSRID(ST_MakePoint(-73.504577, 5.051490), 4326)),
 ('JER', 'Jerusalén',     'Terminal Jerusalén',      2, ST_SetSRID(ST_MakePoint(-74.695855, 4.562677), 4326)),
 ('RIC', 'Ricaurte',      'Terminal Ricaurte',       3, ST_SetSRID(ST_MakePoint(-74.767717, 4.282114), 4326)),
 ('PSA', 'Puerto Salgar', 'Terminal Puerto Salgar',  2, ST_SetSRID(ST_MakePoint(-74.654130, 5.466157), 4326)),
 ('LVE', 'La Vega',       'Terminal La Vega',        3, ST_SetSRID(ST_MakePoint(-74.338211, 4.992574), 4326)),
 ('UTI', 'Útica',         'Terminal Útica',          2, ST_SetSRID(ST_MakePoint(-74.481177, 5.185815), 4326)),
 ('VIL', 'Villeta',       'Terminal Villeta',        4, ST_SetSRID(ST_MakePoint(-74.470477, 5.013166), 4326)),
 ('GUA', 'Guasca',        'Terminal Guasca',         3, ST_SetSRID(ST_MakePoint(-73.874693, 4.869582), 4326)),
 ('CHQ', 'Choachí',       'Terminal Choachí',        2, ST_SetSRID(ST_MakePoint(-73.924819, 4.526448), 4326)),
 ('PAC', 'Pacho',         'Terminal Pacho',          2, ST_SetSRID(ST_MakePoint(-74.159068, 5.140074), 4326)),
 ('YAC', 'Yacopí',        'Terminal Yacopí',         2, ST_SetSRID(ST_MakePoint(-74.338550, 5.463235), 4326)),
 ('COG', 'Cogua',         'Terminal Cogua',          2, ST_SetSRID(ST_MakePoint(-73.979012, 5.066298), 4326)),
 ('COT', 'Cota',          'Terminal Cota',           3, ST_SetSRID(ST_MakePoint(-74.109258, 4.807059), 4326)),
 ('SOP', 'Sopó',          'Terminal Sopó',           4, ST_SetSRID(ST_MakePoint(-73.941829, 4.913516), 4326)),
 ('TOC', 'Tocancipá',     'Terminal Tocancipá',      4, ST_SetSRID(ST_MakePoint(-73.905176, 4.967864), 4326)),
 ('FAC', 'Facatativá',    'Terminal Facatativá',     4, ST_SetSRID(ST_MakePoint(-74.366498, 4.819769), 4326)),
 ('ECO', 'El Colegio',    'Terminal El Colegio',     2, ST_SetSRID(ST_MakePoint(-74.443732, 4.582815), 4326)),
 ('SIM', 'Simijaca',      'Terminal Simijaca',       2, ST_SetSRID(ST_MakePoint(-73.848055, 5.507497), 4326)),
 ('UBA', 'Ubaté',         'Terminal Ubaté',          3, ST_SetSRID(ST_MakePoint(-73.819161, 5.310340), 4326)),
 ('BOG', 'Bogotá D.C.',   'Terminal Bogotá D.C.',    8, ST_SetSRID(ST_MakePoint(-74.147794, 4.677584), 4326));

-- ---------------------------------------------------------------------
-- Users: one system admin + one administrator per parking lot.
-- ---------------------------------------------------------------------
INSERT INTO app_user (username, full_name, role, parking_lot_id)
VALUES ('admin', 'Centro de operaciones', 'SYSTEM_ADMIN', NULL);

INSERT INTO app_user (username, full_name, role, parking_lot_id)
SELECT 'admin.' || lower(code), 'Administrador · ' || municipality, 'LOT_ADMIN', id
FROM parking_lot ORDER BY id;

-- ---------------------------------------------------------------------
-- Drivers.
-- ---------------------------------------------------------------------
INSERT INTO driver (document_id, full_name, phone, license_category) VALUES
 ('79451230', 'Carlos Andrés Rojas',      '3104567812', 'C2'),
 ('80123456', 'Jhon Fredy Martínez',      '3112345678', 'C3'),
 ('1023456789', 'Luis Eduardo Gómez',     '3209876543', 'C2'),
 ('52345678', 'Martha Lucía Pérez',       '3156789012', 'C2'),
 ('79876543', 'José Alirio Cárdenas',     '3001234567', 'C3'),
 ('1012345678', 'Diego Alejandro Ruiz',   '3017654321', 'C2'),
 ('80987654', 'Wilson Hernández',         '3123456789', 'C2'),
 ('1030567890', 'Andrés Felipe Castro',   '3134567890', 'C3'),
 ('79234567', 'Edgar Mauricio Torres',    '3145678901', 'C2'),
 ('52987654', 'Sandra Milena Vargas',     '3167890123', 'C2'),
 ('80345678', 'Óscar Iván Moreno',        '3178901234', 'C3'),
 ('1018456789', 'Camilo Ernesto Díaz',    '3189012345', 'C2'),
 ('79567890', 'Hernando Bautista',        '3190123456', 'C2'),
 ('80654321', 'Fabio Nelson Ramírez',     '3201234567', 'C3'),
 ('1022345678', 'Juan Sebastián Ortiz',   '3212345678', 'C2'),
 ('79112233', 'Rafael Antonio Suárez',    '3223456789', 'C2'),
 ('52445566', 'Diana Carolina Rincón',    '3234567890', 'C2'),
 ('80778899', 'Germán Darío Peña',        '3245678901', 'C3'),
 ('1015667788', 'Santiago Forero',        '3006789012', 'C2'),
 ('79990011', 'Álvaro Enrique Pinzón',    '3017890123', 'C2'),
 ('80223344', 'Nelson Javier Acosta',     '3028901234', 'C3'),
 ('1026778899', 'Brayan Stiven López',    '3039012345', 'C2'),
 ('79334455', 'Ricardo Alfonso Mejía',    '3040123456', 'C2'),
 ('52556677', 'Paola Andrea Quintero',    '3051234567', 'C2');

-- ---------------------------------------------------------------------
-- Fleet (30 intermunicipal buses).
-- ---------------------------------------------------------------------
INSERT INTO bus (plate, internal_code, brand, model_year, seat_capacity) VALUES
 ('WTN482', 'CB-101', 'Mercedes-Benz O500',  2021, 42),
 ('SXK219', 'CB-102', 'Volvo B8R',           2022, 44),
 ('TJM730', 'CB-103', 'Scania K310',         2020, 40),
 ('WPL915', 'CB-104', 'Chevrolet NQR',       2019, 30),
 ('SNB364', 'CB-105', 'Mercedes-Benz O500',  2023, 42),
 ('TKR508', 'CB-106', 'Hino AK8J',           2018, 40),
 ('WFA127', 'CB-107', 'Volvo B8R',           2021, 44),
 ('SGD846', 'CB-108', 'Mercedes-Benz Sprinter', 2022, 19),
 ('TXH271', 'CB-109', 'Chevrolet NQR',       2020, 30),
 ('WMC693', 'CB-110', 'Scania K310',         2023, 40),
 ('SVE452', 'CB-111', 'Mercedes-Benz O500',  2019, 42),
 ('TBQ318', 'CB-112', 'Hino AK8J',           2021, 40),
 ('WZG584', 'CB-113', 'Volvo B8R',           2024, 44),
 ('SHN907', 'CB-114', 'Mercedes-Benz Sprinter', 2023, 19),
 ('TLW263', 'CB-115', 'Chevrolet NQR',       2018, 30),
 ('WDR749', 'CB-116', 'Scania K310',         2022, 40),
 ('SPU136', 'CB-117', 'Mercedes-Benz O500',  2020, 42),
 ('TFY572', 'CB-118', 'Volvo B8R',           2021, 44),
 ('WKJ381', 'CB-119', 'Hino AK8J',           2019, 40),
 ('SAT628', 'CB-120', 'Chevrolet NQR',       2022, 30),
 ('TRV914', 'CB-121', 'Mercedes-Benz O500',  2024, 42),
 ('WQB205', 'CB-122', 'Scania K310',         2021, 40),
 ('SLM473', 'CB-123', 'Mercedes-Benz Sprinter', 2020, 19),
 ('TCX836', 'CB-124', 'Volvo B8R',           2023, 44),
 ('WHE159', 'CB-125', 'Chevrolet NQR',       2021, 30),
 ('SYF742', 'CB-126', 'Hino AK8J',           2022, 40),
 ('TNP395', 'CB-127', 'Mercedes-Benz O500',  2018, 42),
 ('WVS618', 'CB-128', 'Scania K310',         2024, 40),
 ('SCZ287', 'CB-129', 'Volvo B8R',           2020, 44),
 ('TGU531', 'CB-130', 'Chevrolet NQR',       2023, 30);

-- ---------------------------------------------------------------------
-- Demo operations, always relative to now() so the map looks "live".
-- Can be re-run any time:  SELECT fn_seed_operations();
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_trip_minutes(p_from integer, p_to integer)
RETURNS integer
LANGUAGE sql STABLE
SET search_path = public, extensions
AS $$
    -- straight-line distance × 1.35 road factor, 38 km/h mountain average
    SELECT GREATEST(40, round(ST_DistanceSphere(a.geom, b.geom) / 1000 * 1.35 / 38 * 60))::int
    FROM parking_lot a, parking_lot b
    WHERE a.id = p_from AND b.id = p_to;
$$;

CREATE OR REPLACE FUNCTION fn_free_driver(p_from timestamptz, p_to timestamptz)
RETURNS integer
LANGUAGE sql VOLATILE
SET search_path = public, extensions
AS $$
    SELECT d.id FROM driver d
    WHERE NOT EXISTS (
        SELECT 1 FROM trip t
        WHERE t.driver_id = d.id AND t.status <> 'CANCELLED'
          AND tstzrange(t.scheduled_departure, t.scheduled_arrival) && tstzrange(p_from - interval '20 min', p_to + interval '20 min')
    )
    ORDER BY random() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_seed_operations()
RETURNS void
LANGUAGE plpgsql
SET search_path = public, extensions
AS $$
DECLARE
    -- where each bus is parked right now (26 buses), respecting capacities
    v_parked text[] := ARRAY['BOG','BOG','BOG','BOG','BOG','BOG','FAC','FAC','FAC','SOP','SOP',
                             'TOC','TOC','TOC','TOC','VIL','VIL','UBA','COT','CHO','CHO','GUA',
                             'LVE','PAC','RIC','SIM'];
    -- buses currently on the road (4)
    v_routes text[][] := ARRAY[['BOG','PSA'], ['FAC','VIL'], ['UBA','SIM'], ['COT','JER']];
    v_hub_dest text[] := ARRAY['BOG','FAC','VIL','UBA','SOP','GUA','COT','PAC','LVE','ECO','CHQ','TIB','UTI','YAC','COG'];
    v_names text[] := ARRAY['Ana','Luis','María','Jorge','Camila','Andrés','Laura','Felipe','Valentina','Julián',
                            'Daniela','Mateo','Sofía','Nicolás','Paula','Sergio','Juliana','Esteban','Natalia','David'];
    v_last  text[] := ARRAY['García','Rodríguez','Martínez','López','González','Hernández','Sánchez','Ramírez',
                            'Torres','Flórez','Rivera','Gómez','Díaz','Moreno','Jiménez','Rojas','Castro','Vargas'];
    v_bus      record;
    v_i        integer := 0;
    v_lot      integer;
    v_from     integer;
    v_to       integer;
    v_mins     integer;
    v_arrived  timestamptz;
    v_dep      timestamptz;
    v_dwell    integer;
    v_trip     integer;
    v_cap      integer;
    v_sold     integer;
    v_driver   integer;
BEGIN
    DELETE FROM ticket WHERE true;        -- WHERE required by Supabase safeupdate
    DELETE FROM parking_stay WHERE true;
    DELETE FROM trip WHERE true;
    DELETE FROM driver_shift WHERE true;
    PERFORM setseed(0.4242);

    FOR v_bus IN SELECT id, seat_capacity FROM bus ORDER BY id LOOP
        v_i := v_i + 1;

        IF v_i <= array_length(v_parked, 1) THEN
            -- ---------- bus parked at v_lot ----------
            SELECT id INTO v_lot FROM parking_lot WHERE code = v_parked[v_i];
            SELECT id INTO v_from FROM parking_lot
             WHERE code = CASE WHEN v_parked[v_i] = 'BOG' THEN v_hub_dest[2 + (v_i % 14)] ELSE 'BOG' END;
            IF v_from = v_lot THEN
                SELECT id INTO v_from FROM parking_lot WHERE code = 'FAC';
            END IF;

            v_mins    := fn_trip_minutes(v_from, v_lot);
            v_arrived := now() - make_interval(mins => 8 + floor(random() * 150)::int);
            v_dwell   := (2 + floor(random() * 7)::int) * 15;          -- 30..120 min
            v_dep     := v_arrived - make_interval(mins => v_mins);

            -- previous stay at the origin (gives dwell-time history)
            INSERT INTO parking_stay (bus_id, parking_lot_id, arrived_at, departed_at, arrival_registered_by, departure_registered_by)
            VALUES (v_bus.id, v_from, v_dep - make_interval(mins => 25 + floor(random() * 80)::int), v_dep,
                    (SELECT id FROM app_user WHERE parking_lot_id = v_from), (SELECT id FROM app_user WHERE parking_lot_id = v_from));

            v_driver := fn_free_driver(v_dep, v_arrived);
            INSERT INTO trip (bus_id, driver_id, origin_lot_id, destination_lot_id, scheduled_departure, scheduled_arrival,
                              dwell_minutes, actual_departure, actual_arrival, status)
            VALUES (v_bus.id, v_driver, v_from, v_lot, v_dep, v_arrived, v_dwell, v_dep, v_arrived, 'ARRIVED')
            RETURNING id INTO v_trip;

            INSERT INTO parking_stay (bus_id, parking_lot_id, arrival_trip_id, arrived_at, arrival_registered_by)
            VALUES (v_bus.id, v_lot, v_trip, v_arrived, (SELECT id FROM app_user WHERE parking_lot_id = v_lot));

            -- next scheduled departure from this lot
            SELECT id INTO v_to FROM parking_lot
             WHERE code = CASE WHEN v_parked[v_i] = 'BOG' THEN v_hub_dest[1 + ((v_i * 3) % 15)]
                               WHEN random() < 0.6 THEN 'BOG'
                               ELSE v_hub_dest[1 + floor(random() * 15)::int] END;
            IF v_to = v_lot OR v_to IS NULL THEN
                SELECT id INTO v_to FROM parking_lot WHERE code = CASE WHEN v_parked[v_i] = 'BOG' THEN 'VIL' ELSE 'BOG' END;
            END IF;

            v_dep := GREATEST(v_arrived + make_interval(mins => v_dwell),
                              date_trunc('minute', now()) + make_interval(mins => 5 + floor(random() * 180)::int));
            v_dep := date_trunc('hour', v_dep) + make_interval(mins => (ceil(extract(minute FROM v_dep) / 5) * 5)::int);
            v_mins := fn_trip_minutes(v_lot, v_to);
            v_driver := fn_free_driver(v_dep, v_dep + make_interval(mins => v_mins));

            -- planned dwell at this lot = time until the next scheduled departure
            UPDATE trip SET dwell_minutes = LEAST(1440, ceil(extract(epoch FROM v_dep - v_arrived) / 60))::int
             WHERE id = v_trip;

            INSERT INTO trip (bus_id, driver_id, origin_lot_id, destination_lot_id, scheduled_departure, scheduled_arrival, dwell_minutes)
            VALUES (v_bus.id, v_driver, v_lot, v_to, v_dep, v_dep + make_interval(mins => v_mins),
                    (2 + floor(random() * 5)::int) * 15)
            RETURNING id INTO v_trip;

            -- tickets already sold for that trip
            v_cap  := v_bus.seat_capacity;
            v_sold := floor(v_cap * (0.15 + random() * 0.85))::int;
            INSERT INTO ticket (trip_id, seat_number, passenger_name, sold_at)
            SELECT v_trip, s.n,
                   v_names[1 + floor(random() * 20)::int] || ' ' || v_last[1 + floor(random() * 18)::int],
                   now() - make_interval(mins => floor(random() * 600)::int)
            FROM (SELECT n FROM generate_series(1, v_cap) AS n ORDER BY random() LIMIT v_sold) s;

        ELSE
            -- ---------- bus on the road ----------
            SELECT id INTO v_from FROM parking_lot WHERE code = v_routes[v_i - array_length(v_parked, 1)][1];
            SELECT id INTO v_to   FROM parking_lot WHERE code = v_routes[v_i - array_length(v_parked, 1)][2];
            v_mins := fn_trip_minutes(v_from, v_to);
            v_dep  := now() - make_interval(mins => LEAST(v_mins - 12, 15 + floor(random() * 50)::int));

            INSERT INTO parking_stay (bus_id, parking_lot_id, arrived_at, departed_at, arrival_registered_by, departure_registered_by)
            VALUES (v_bus.id, v_from, v_dep - make_interval(mins => 30 + floor(random() * 60)::int), v_dep,
                    (SELECT id FROM app_user WHERE parking_lot_id = v_from), (SELECT id FROM app_user WHERE parking_lot_id = v_from));

            v_driver := fn_free_driver(v_dep, v_dep + make_interval(mins => v_mins));
            INSERT INTO trip (bus_id, driver_id, origin_lot_id, destination_lot_id, scheduled_departure, scheduled_arrival,
                              dwell_minutes, actual_departure, status)
            VALUES (v_bus.id, v_driver, v_from, v_to, v_dep, v_dep + make_interval(mins => v_mins), 45, v_dep, 'IN_TRANSIT');
        END IF;
    END LOOP;

    -- ---------- driver service schedules (shifts) ----------
    INSERT INTO driver_shift (driver_id, base_lot_id, starts_at, ends_at)
    SELECT d.id,
           COALESCE(f.first_origin, (SELECT id FROM parking_lot WHERE code = 'BOG')),
           sh.starts_at,
           LEAST(sh.starts_at + interval '12 hours',
                 GREATEST(sh.starts_at + interval '8 hours', f.last_arrival + interval '30 minutes'))
    FROM driver d
    LEFT JOIN LATERAL (
        SELECT (array_agg(t.origin_lot_id ORDER BY t.scheduled_departure))[1] AS first_origin,
               min(t.scheduled_departure) AS first_departure,
               max(t.scheduled_arrival)   AS last_arrival
        FROM trip t WHERE t.driver_id = d.id
    ) f ON true
    CROSS JOIN LATERAL (
        SELECT date_trunc('hour', COALESCE(f.first_departure - interval '45 minutes',
                                           now() + make_interval(hours => 1 + (d.id % 4)))) AS starts_at
    ) sh;
END;
$$;

SELECT fn_seed_operations();
