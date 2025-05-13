-- ============================================================================
-- Migration: 015_shuttle_shared.sql (Version 1.1 - Capacity, Stop Fix, History)
-- Description: VoyaGo - Shared Shuttle Module Schema: Services, Stops, Routes,
--              Schedules, Trips (with Capacity), Bookings & Boarding, History.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 005_fleet_management.sql,
--               010_booking_core.sql (for booking_booking_legs),
--               011_payment_wallet.sql (for pmt_payments)
-- ============================================================================

BEGIN;

-- Prefix 'shuttle_' denotes tables specific to the Shared Shuttle module.

-------------------------------------------------------------------------------
-- 1. Shuttle Services (shuttle_services)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_services (
    service_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Unique code identifying the service, potentially linked to lkp_service_types logic
    service_code    VARCHAR(50) NOT NULL UNIQUE,
    name            VARCHAR(150) NOT NULL, -- User-facing name of the shuttle service
    description     TEXT NULL,
    status          public.shuttle_status NOT NULL DEFAULT 'DRAFT', -- Service status (ENUM from 001)
    -- E.g., {"vehicle_type_preference": "VAN_PASSENGER", "luggage_policy": "1_standard"}
    metadata        JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'), 
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.shuttle_services
    IS '[VoyaGo][Shuttle] Defines the core shared shuttle services offered.';
COMMENT ON COLUMN public.shuttle_services.metadata
    IS 'Additional service-level configuration, e.g., preferred vehicle types, luggage policies.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_shuttle_services ON public.shuttle_services;
CREATE TRIGGER trg_set_timestamp_on_shuttle_services
    BEFORE UPDATE ON public.shuttle_services
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Services
CREATE INDEX IF NOT EXISTS idx_shuttle_services_status ON public.shuttle_services(status);


-------------------------------------------------------------------------------
-- 1.1 Shuttle Services History (shuttle_services_history) - Added in v1.1
-- Description: Audit trail for changes to shuttle_services.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_services_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    service_id      UUID NOT NULL,      -- The service that was changed
    service_data    JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.shuttle_services_history
    IS '[VoyaGo][Shuttle][History] Audit log capturing changes to shuttle_services records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_shuttle_services_hist_sid
    ON public.shuttle_services_history(service_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Shuttle Services History Trigger Function - Added in v1.1
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_shuttle_service_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.shuttle_services_history
            (action_type, actor_id, service_id, service_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.service_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_shuttle_service_history()
    IS '[VoyaGo][Shuttle][TriggerFn] Logs previous state of shuttle_services row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_shuttle_service_history ON public.shuttle_services;
CREATE TRIGGER audit_shuttle_service_history
    AFTER UPDATE OR DELETE ON public.shuttle_services
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_shuttle_service_history();


-------------------------------------------------------------------------------
-- 2. Shuttle Stops (shuttle_stops) - Revised in v1.1 (Location removed)
-- Description: Defines the sequence of stops for a shuttle service.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_stops (
    stop_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id      UUID NOT NULL,          -- Service this stop belongs to (FK defined later)
    sequence_no     SMALLINT NOT NULL CHECK (sequence_no > 0), -- Order of the stop in the service route
    -- Location of the stop (FK to core_addresses) - Location point comes from here.
    address_id      UUID NOT NULL,
    name            VARCHAR(100) NULL,      -- Optional specific name for the stop (e.g., "Main Terminal Gate 3")
    pickup_allowed  BOOLEAN DEFAULT TRUE NOT NULL, -- Can passengers board here?
    dropoff_allowed BOOLEAN DEFAULT TRUE NOT NULL, -- Can passengers alight here?
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,

    CONSTRAINT uq_shuttle_service_stop_seq UNIQUE (service_id, sequence_no) -- Sequence must be unique within a service
);
COMMENT ON TABLE public.shuttle_stops
    IS '[VoyaGo][Shuttle] Defines the sequence of stops associated with a shuttle service, linked to addresses.';
COMMENT ON COLUMN public.shuttle_stops.address_id
    IS 'Foreign key to core_addresses, providing the geographic location and address details for the stop.';

-- Indexes for Stops
CREATE INDEX IF NOT EXISTS idx_shuttle_stops_service_seq ON public.shuttle_stops(service_id, sequence_no);
-- GIST index is on the core_addresses table


-------------------------------------------------------------------------------
-- 3. Shuttle Routes (shuttle_routes)
-- Description: Stores the geographic route line for a shuttle service.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_routes (
    service_id      UUID PRIMARY KEY,       -- Links 1:1 to shuttle_services (FK defined later)
    route_geom      GEOGRAPHY(LINESTRING, 4326) NOT NULL -- The route geometry
);
COMMENT ON TABLE public.shuttle_routes
    IS '[VoyaGo][Shuttle] Stores the geographic route (LineString) for a shuttle service.';

-- Index for Routes
CREATE INDEX IF NOT EXISTS idx_shuttle_routes_geom ON public.shuttle_routes USING GIST(route_geom);


-------------------------------------------------------------------------------
-- 4. Shuttle Schedules (shuttle_schedules)
-- Description: Defines recurring schedules for shuttle services using iCal RRULE.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_schedules (
    schedule_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id      UUID NOT NULL,          -- Service this schedule applies to (FK defined later)
    start_time      TIME NOT NULL,          -- Departure time from the first stop for scheduled trips
    recurrence      TEXT NOT NULL,          -- Recurrence rule in iCal RRULE format (e.g., 'FREQ=DAILY;BYHOUR=8,12,16')
    valid_from      DATE NOT NULL,          -- Date the schedule becomes effective
    valid_to        DATE NULL,              -- Date the schedule expires (NULL if indefinite)
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL
    -- updated_at is less relevant for schedules, usually replaced rather than updated
);
COMMENT ON TABLE public.shuttle_schedules
    IS '[VoyaGo][Shuttle] Defines recurring schedules for shuttle services using the iCal RRULE format.';
COMMENT ON COLUMN public.shuttle_schedules.recurrence
    IS 'Recurrence rule string following iCalendar RRULE standard (RFC 5545). 
        Example: ''FREQ=WEEKLY;BYDAY=MO,WE,FR;BYHOUR=9;BYMINUTE=30''';

-- Indexes for Schedules
CREATE INDEX IF NOT EXISTS idx_shuttle_schedules_service ON public.shuttle_schedules(service_id);
CREATE INDEX IF NOT EXISTS idx_shuttle_schedules_validity ON public.shuttle_schedules(valid_from, valid_to);


-------------------------------------------------------------------------------
-- 5. Shuttle Trips (shuttle_trips) - Revised in v1.1 (Capacity Added)
-- Description: Represents specific instances of scheduled or ad-hoc shuttle trips.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_trips (
    trip_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_id      UUID NOT NULL,          -- Related service (FK defined later)
    schedule_id     UUID NULL,              -- Originating schedule, if applicable (FK defined later)
    trip_start      TIMESTAMPTZ NOT NULL,   -- Actual or planned start time of this specific trip instance
    trip_end        TIMESTAMPTZ NULL,       -- Estimated or actual end time of this trip instance
    vehicle_id      UUID NULL,              -- Assigned vehicle (FK defined later)
    driver_id       UUID NULL,              -- Assigned driver (FK defined later)
    -- Added in v1.1 for capacity tracking
    -- Total available seats on the assigned vehicle for this trip
    total_seats     SMALLINT NOT NULL CHECK (total_seats > 0), 
    booked_seats    SMALLINT NOT NULL DEFAULT 0 CHECK (booked_seats >= 0), -- Number of seats currently booked
    status          public.shuttle_trip_status NOT NULL DEFAULT 'SCHEDULED', -- Trip status (ENUM from 001)
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL        -- Automatically updated by trigger
);
COMMENT ON TABLE public.shuttle_trips
    IS '[VoyaGo][Shuttle] Represents individual instances of shuttle trips, 
        linking to schedules and assigned resources, includes capacity.';
COMMENT ON COLUMN public.shuttle_trips.trip_start
    IS 'The specific date and time this trip instance starts or is scheduled to start.';
COMMENT ON COLUMN public.shuttle_trips.total_seats
    IS 'Total passenger capacity available for this specific trip instance 
        (might depend on assigned vehicle).';
COMMENT ON COLUMN public.shuttle_trips.booked_seats
    IS 'Number of seats currently booked on this trip. 
        Should be updated atomically via triggers or application logic when bookings change.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_shuttle_trips ON public.shuttle_trips;
CREATE TRIGGER trg_set_timestamp_on_shuttle_trips
    BEFORE UPDATE ON public.shuttle_trips
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Trips
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_service_time ON public.shuttle_trips(service_id, trip_start);
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_status ON public.shuttle_trips(status);
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_vehicle
    ON public.shuttle_trips(vehicle_id) WHERE vehicle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_driver
    ON public.shuttle_trips(driver_id) WHERE driver_id IS NOT NULL;
-- Index for finding trips with available seats
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_availability
    ON public.shuttle_trips(trip_start, status) 
    WHERE (status = 'SCHEDULED' OR status = 'READY') AND booked_seats < total_seats;
COMMENT ON INDEX public.idx_shuttle_trips_availability 
    IS '[VoyaGo][Perf] Helps find upcoming trips with available seats quickly.';


-------------------------------------------------------------------------------
-- 5.1 Shuttle Trips History (shuttle_trips_history) - Added in v1.1
-- Description: Audit trail for changes to shuttle_trips.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_trips_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    trip_id         UUID NOT NULL,      -- The trip that was changed
    trip_data       JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.shuttle_trips_history
    IS '[VoyaGo][Shuttle][History] Audit log capturing changes to shuttle_trips records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_shuttle_trips_hist_tid
    ON public.shuttle_trips_history(trip_id, action_at DESC);

-------------------------------------------------------------------------------
-- 5.2 Shuttle Trips History Trigger Function - Added in v1.1
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_shuttle_trip_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.shuttle_trips_history
            (action_type, actor_id, trip_id, trip_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.trip_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_shuttle_trip_history()
    IS '[VoyaGo][Shuttle][TriggerFn] Logs previous state of shuttle_trips row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_shuttle_trip_history ON public.shuttle_trips;
CREATE TRIGGER audit_shuttle_trip_history
    AFTER UPDATE OR DELETE ON public.shuttle_trips
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_shuttle_trip_history();


-------------------------------------------------------------------------------
-- 6. Shuttle Trip Legs (shuttle_trip_legs)
-- Description: Defines the scheduled/actual timing for each stop within a specific trip.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_trip_legs (
    leg_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trip_id         UUID NOT NULL,          -- Link to the specific trip instance (FK defined later)
    stop_id         UUID NOT NULL,          -- Link to the stop (FK defined later)
    -- Denormalized from shuttle_stops for ordering legs per trip
    sequence_no     SMALLINT NOT NULL CHECK (sequence_no > 0), 
    arrival_time    TIMESTAMPTZ NULL,       -- Estimated or actual arrival time at this stop
    departure_time  TIMESTAMPTZ NULL,       -- Estimated or actual departure time from this stop
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL
    -- updated_at not typically needed here, times are event-based
);
COMMENT ON TABLE public.shuttle_trip_legs
    IS '[VoyaGo][Shuttle] Defines the sequence and planned/actual timing of 
        stops for a specific shuttle trip.';
COMMENT ON COLUMN public.shuttle_trip_legs.sequence_no
    IS 'The sequence number of this stop within this specific trip, 
        usually mirroring shuttle_stops.sequence_no.';

-- Indexes for Trip Legs
CREATE UNIQUE INDEX IF NOT EXISTS uq_shuttle_trip_stop_seq
    ON public.shuttle_trip_legs(trip_id, sequence_no);
CREATE INDEX IF NOT EXISTS idx_shuttle_trip_leg_trip_stop
    ON public.shuttle_trip_legs(trip_id, stop_id);


-------------------------------------------------------------------------------
-- 7. Shuttle Bookings (shuttle_bookings) - Separate table approach
-- Description: Stores passenger bookings for specific shuttle trips.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_bookings (
    booking_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Shuttle-specific booking number
    shuttle_booking_number VARCHAR(20) NOT NULL UNIQUE 
        DEFAULT ('SHB' || upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 8))),
    trip_id             UUID NOT NULL,        -- The specific trip being booked (FK defined later)
    user_id             UUID NOT NULL,        -- The user making the booking (FK defined later)
    -- Optional: Link to a master booking record if using a unified booking system approach
    -- main_booking_id  UUID NULL UNIQUE,
    passenger_count     SMALLINT NOT NULL DEFAULT 1 CHECK (passenger_count > 0),
    seat_numbers        TEXT[] NULL,          -- Array of assigned seat numbers, if applicable
    pickup_stop_id      UUID NOT NULL,        -- Boarding stop (FK to shuttle_stops)
    dropoff_stop_id     UUID NOT NULL,        -- Alighting stop (FK to shuttle_stops)
    fare                NUMERIC(12,2) NOT NULL CHECK (fare >= 0), -- Fare for this shuttle booking
    currency_code       CHAR(3) NOT NULL,     -- Currency of the fare (FK defined later)
    payment_id          UUID NULL UNIQUE,     -- Link to the payment record (FK defined later)
    -- Status of the booking itself (e.g., BOOKED, CANCELLED). Boarding status tracked separately.
    booking_status      public.shuttle_boarding_status NOT NULL DEFAULT 'BOOKED',
    notes               TEXT NULL,            -- Notes from the passenger
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL      -- Automatically updated by trigger
);
COMMENT ON TABLE public.shuttle_bookings
    IS '[VoyaGo][Shuttle] Stores passenger bookings for specific shuttle trips 
        (kept separate from main booking system).';
COMMENT ON COLUMN public.shuttle_bookings.shuttle_booking_number
    IS 'Unique, user-friendly identifier specifically for shuttle bookings.';
COMMENT ON COLUMN public.shuttle_bookings.booking_status
    IS 'Status of the shuttle booking itself (e.g., BOOKED, CANCELLED). 
        Note: Uses shuttle_boarding_status ENUM, consider dedicated ENUM if causing confusion.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_shuttle_bookings ON public.shuttle_bookings;
CREATE TRIGGER trg_set_timestamp_on_shuttle_bookings
    BEFORE UPDATE ON public.shuttle_bookings
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Shuttle Bookings
CREATE INDEX IF NOT EXISTS idx_shuttle_bookings_trip ON public.shuttle_bookings(trip_id);
CREATE INDEX IF NOT EXISTS idx_shuttle_bookings_user ON public.shuttle_bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_shuttle_bookings_status ON public.shuttle_bookings(booking_status);


-------------------------------------------------------------------------------
-- 7.1 Shuttle Bookings History (shuttle_bookings_history) - Added in v1.1
-- Description: Audit trail for changes to shuttle_bookings.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_bookings_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    booking_id      UUID NOT NULL,      -- The shuttle_booking that was changed
    booking_data    JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.shuttle_bookings_history
    IS '[VoyaGo][Shuttle][History] Audit log capturing changes to shuttle_bookings records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_shuttle_bookings_hist_bid
    ON public.shuttle_bookings_history(booking_id, action_at DESC);

-------------------------------------------------------------------------------
-- 7.2 Shuttle Bookings History Trigger Function - Added in v1.1
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_shuttle_booking_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.shuttle_bookings_history
            (action_type, actor_id, booking_id, booking_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.booking_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_shuttle_booking_history()
    IS '[VoyaGo][Shuttle][TriggerFn] Logs previous state of shuttle_bookings row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_shuttle_booking_history ON public.shuttle_bookings;
CREATE TRIGGER audit_shuttle_booking_history
    AFTER UPDATE OR DELETE ON public.shuttle_bookings
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_shuttle_booking_history();


-------------------------------------------------------------------------------
-- 8. Shuttle Boarding Status (shuttle_boardings)
-- Description: Tracks the boarding status events for a passenger on a booking.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shuttle_boardings (
    boarding_id     BIGSERIAL PRIMARY KEY,
    -- Link to the shuttle booking (FK defined later, ON DELETE CASCADE)
    booking_id      UUID NOT NULL,          
    -- Link to the specific trip leg (stop) where event occurred (FK defined later)
    trip_leg_id     UUID NULL,              
    -- Boarding event status (ENUM from 001)
    status          public.shuttle_boarding_status NOT NULL DEFAULT 'BOOKED', 
    timestamp       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the event occurred
    actor_id        UUID NULL,              -- User who recorded the event (e.g., driver, system)
    notes           TEXT NULL
);
COMMENT ON TABLE public.shuttle_boardings
    IS '[VoyaGo][Shuttle] Time-stamped log of passenger boarding events 
        (check-in, boarded, alighted, missed).';
COMMENT ON COLUMN public.shuttle_boardings.trip_leg_id
    IS 'Reference to the specific stop (shuttle_trip_legs) 
        where the boarding/alighting event happened, if applicable.';

-- Indexes for Boarding Status
CREATE INDEX IF NOT EXISTS idx_shuttle_boardings_booking
    ON public.shuttle_boardings(booking_id);
CREATE INDEX IF NOT EXISTS idx_shuttle_boardings_leg
    ON public.shuttle_boardings(trip_leg_id) WHERE trip_leg_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shuttle_boardings_status
    ON public.shuttle_boardings(status);


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- --------------------------------------------------------------------------------------------------
-- shuttle_services_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- shuttle_services_history -> shuttle_services (service_id -> service_id) [CASCADE]
--
-- shuttle_stops -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_stops -> core_addresses (address_id -> address_id) [RESTRICT]
--
-- shuttle_routes -> shuttle_services (service_id -> service_id) [CASCADE]
--
-- shuttle_schedules -> shuttle_services (service_id -> service_id) [CASCADE]
--
-- shuttle_trips -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_trips -> shuttle_schedules (schedule_id -> schedule_id) [SET NULL]
-- shuttle_trips -> fleet_vehicles (vehicle_id -> vehicle_id) [SET NULL]
-- shuttle_trips -> fleet_drivers (driver_id -> driver_id) [SET NULL]
--
-- shuttle_trips_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- shuttle_trips_history -> shuttle_trips (trip_id -> trip_id) [CASCADE]
--
-- shuttle_trip_legs -> shuttle_trips (trip_id -> trip_id) [CASCADE]
-- shuttle_trip_legs -> shuttle_stops (stop_id -> stop_id) [CASCADE?] 
    -- If stop deleted, maybe cascade leg deletion? Or RESTRICT?
--
-- shuttle_bookings -> shuttle_trips (trip_id -> trip_id) [RESTRICT] 
    -- Prevent trip deletion if bookings exist?
-- shuttle_bookings -> core_user_profiles (user_id -> user_id) [CASCADE? RESTRICT?]
-- shuttle_bookings -> shuttle_stops (pickup_stop_id -> stop_id) [RESTRICT]
-- shuttle_bookings -> shuttle_stops (dropoff_stop_id -> stop_id) [RESTRICT]
-- shuttle_bookings -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- shuttle_bookings -> pmt_payments (payment_id -> payment_id) [SET NULL]
--
-- shuttle_bookings_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- shuttle_bookings_history -> shuttle_bookings (booking_id -> booking_id) [CASCADE]
--
-- shuttle_boardings -> shuttle_bookings (booking_id -> booking_id) [CASCADE]
-- shuttle_boardings -> shuttle_trip_legs (trip_leg_id -> leg_id) [SET NULL?] 
    -- Keep boarding record even if leg removed?
-- shuttle_boardings -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 015_shuttle_shared.sql (Version 1.1)
-- ============================================================================
