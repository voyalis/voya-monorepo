-- ============================================================================
-- Migration: 014_micromobility.sql (Version 1.2 - Fixed INSERT, Added ride_start_time for FKs)
-- Description: VoyaGo - Micromobility Module Schema: Vehicle Types (+Translations),
--              Vehicles (Inventory & Status), Stations, Station Status,
--              Ride Sessions (Partitioned), Ride Events, Vehicle History.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 005_fleet_management.sql,
--               011_payment_wallet.sql (for ride payment link)
-- ============================================================================

BEGIN;

-- Prefix 'mm_' denotes tables specific to the Micromobility module,
-- except for lookup tables (lkp_).

-------------------------------------------------------------------------------
-- 1. Micromobility Vehicle Types (lkp_mm_vehicle_types) & Translations
-- Description: Defines the types of micromobility vehicles available (e.g., specific scooter models).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.lkp_mm_vehicle_types (
    type_code       VARCHAR(50) PRIMARY KEY,    -- e.g., 'E_SCOOTER_SEGWAY_G30','E_BIKE_XIAOMI_Z20'
    -- Description moved to translation table
    brand           VARCHAR(50) NULL,
    model           VARCHAR(50) NULL,
    max_speed_kmh   SMALLINT NULL CHECK (max_speed_kmh IS NULL OR max_speed_kmh > 0),
    range_km        SMALLINT NULL CHECK (range_km IS NULL OR range_km > 0), -- Estimated range
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_mm_vehicle_types
    IS '[VoyaGo][Micromobility][Lookup] Defines specific types/models of micromobility 
        vehicles and their base specs.';

-- Added in v1.1: Translations Table
CREATE TABLE IF NOT EXISTS public.lkp_mm_vehicle_types_translations (
    type_code       VARCHAR(50) NOT NULL, -- FK defined later
    language_code   CHAR(2)     NOT NULL, -- FK defined later
    name            TEXT        NOT NULL, -- User-facing name (e.g., Electric Scooter V1)
    description     TEXT        NULL,     -- Optional description in the specific language
    PRIMARY KEY (type_code, language_code)
);
COMMENT ON TABLE public.lkp_mm_vehicle_types_translations
    IS '[VoyaGo][Micromobility][Lookup][I18n] Translations for micromobility 
        vehicle type names and descriptions.';

CREATE INDEX IF NOT EXISTS idx_lkp_mm_vehicle_types_trans_lang
    ON public.lkp_mm_vehicle_types_translations(language_code);

-- Seed Data (Examples) - Corrected INSERT without description in main table
INSERT INTO public.lkp_mm_vehicle_types
    (type_code, brand, model, max_speed_kmh, range_km, is_active)
VALUES
    ('E_SCOOTER_V1', 'Segway', 'Ninebot Max G30', 25, 40, TRUE),
    ('E_BIKE_CITY', 'Xiaomi', 'Himo Z20', 25, 80, TRUE)
ON CONFLICT (type_code) DO UPDATE SET
    -- description removed from SET clause
    brand = EXCLUDED.brand,
    model = EXCLUDED.model,
    max_speed_kmh = EXCLUDED.max_speed_kmh,
    range_km = EXCLUDED.range_km,
    is_active = EXCLUDED.is_active;

-- Seed translations including description
INSERT INTO public.lkp_mm_vehicle_types_translations
    (type_code, language_code, name, description)
VALUES
    ('E_SCOOTER_V1', 'tr', 'Elektrikli Scooter', 'Standart Paylaşımlı Elektrikli Scooter'),
    ('E_SCOOTER_V1', 'en', 'Electric Scooter', 'Standard Shared Electric Scooter'),
    ('E_BIKE_CITY', 'tr', 'Elektrikli Şehir Bisikleti', 'Paylaşımlı Şehir Tipi Elektrikli Bisiklet'),
    ('E_BIKE_CITY', 'en', 'Electric City Bike', 'Shared City Style Electric Bike')
ON CONFLICT (type_code, language_code) DO UPDATE SET -- Added ON CONFLICT DO UPDATE for translations
    name = EXCLUDED.name,
    description = EXCLUDED.description;


-------------------------------------------------------------------------------
-- 2. Micromobility Vehicles (mm_vehicles) - ** current_ride_start_time ADDED **
-- Description: Inventory and live status of individual micromobility vehicles.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_vehicles (
    vehicle_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_type_code       VARCHAR(50) NOT NULL,   -- Type of vehicle (FK defined later)
    partner_id              UUID NULL,          -- Operating partner, if any (FK defined later)
    -- Public identifier for the vehicle (e.g., QR code content, visible ID)
    vehicle_identifier      TEXT NOT NULL UNIQUE,
    -- User currently renting the vehicle
    current_user_id         UUID NULL,
    -- Active ride session ID (Composite FK defined later)
    current_ride_id         UUID NULL,
    current_ride_start_time TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    -- Current or last known location
    current_location        GEOGRAPHY(POINT, 4326) NULL,
    -- Current battery charge percentage
    battery_level           SMALLINT CHECK (battery_level IS NULL OR (battery_level BETWEEN 0 AND 100)),
    -- Current operational status (ENUM from 001)
    status                  public.mm_vehicle_status NOT NULL DEFAULT 'OFFLINE',
    -- Timestamp of the last communication/location update
    last_seen_at            TIMESTAMPTZ NULL,
    -- Timestamp of the last recorded maintenance
    last_maintenance_at     TIMESTAMPTZ NULL,
    -- Additional metadata (e.g., firmware version)
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL, -- Automatically updated by trigger

    -- Ensure ride start time is present if ride id is
    CONSTRAINT chk_mm_vehicle_ride_times CHECK (current_ride_id IS NULL OR current_ride_start_time IS NOT NULL)
);
COMMENT ON TABLE public.mm_vehicles
    IS '[VoyaGo][Micromobility] Inventory and real-time status of 
        individual micromobility vehicles (e-scooters, e-bikes).';
COMMENT ON COLUMN public.mm_vehicles.current_ride_start_time
    IS 'Partition key copied from mm_rides for composite foreign key (if current_ride_id is not NULL).';
COMMENT ON COLUMN public.mm_vehicles.vehicle_identifier
    IS 'Unique public identifier for the vehicle, often used in QR codes.';
COMMENT ON COLUMN public.mm_vehicles.metadata
    IS 'Additional metadata, e.g., {"firmware_version": "1.2.3", "iot_device_id": "..."}';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_mm_vehicles ON public.mm_vehicles;
CREATE TRIGGER trg_set_timestamp_on_mm_vehicles
    BEFORE UPDATE ON public.mm_vehicles
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Vehicles
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_type ON public.mm_vehicles(vehicle_type_code);
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_status ON public.mm_vehicles(status);
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_partner
    ON public.mm_vehicles(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_user
    ON public.mm_vehicles(current_user_id) WHERE current_user_id IS NOT NULL;
-- Index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_ride
    ON public.mm_vehicles(current_ride_id, current_ride_start_time) WHERE current_ride_id IS NOT NULL;
-- Index to find available vehicles with low battery
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_battery_low
    ON public.mm_vehicles(battery_level)
    WHERE battery_level IS NOT NULL AND battery_level < 20 AND status = 'AVAILABLE';
COMMENT ON INDEX public.idx_mm_vehicles_battery_low 
    IS '[VoyaGo][Perf] Quickly finds available vehicles needing a charge.';
-- Spatial index for finding nearby available vehicles
CREATE INDEX IF NOT EXISTS idx_mm_vehicles_loc
    ON public.mm_vehicles USING GIST(current_location)
    WHERE status = 'AVAILABLE' AND current_location IS NOT NULL;
COMMENT ON INDEX public.idx_mm_vehicles_loc 
    IS '[VoyaGo][Perf] Optimized spatial index for finding available vehicles nearby.';


-------------------------------------------------------------------------------
-- 2.1 Micromobility Vehicles History (mm_vehicles_history)
-- Description: Audit trail for changes to mm_vehicles records.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_vehicles_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL, -- INSERT, UPDATE, DELETE
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,        -- User performing the action
    vehicle_id      UUID NOT NULL,    -- The vehicle that was changed
    vehicle_data    JSONB NOT NULL      -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.mm_vehicles_history
    IS '[VoyaGo][Micromobility][History] Audit log capturing changes to mm_vehicles records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_mm_veh_hist_vid
    ON public.mm_vehicles_history(vehicle_id, action_at DESC);

-------------------------------------------------------------------------------
-- 2.2 Micromobility Vehicles History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_mm_vehicle_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review for security implications
AS $$
DECLARE
    v_actor_id UUID;
    v_data JSONB;
BEGIN
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := NULL; END;

    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.mm_vehicles_history
            (action_type, actor_id, vehicle_id, vehicle_data)
        VALUES
            (TG_OP::public.audit_action, v_actor_id, OLD.vehicle_id, v_data);
    END IF;

    IF TG_OP = 'UPDATE' THEN RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_mm_vehicle_history()
    IS '[VoyaGo][Micromobility][TriggerFn] Logs previous state of mm_vehicles row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_mm_vehicle_history ON public.mm_vehicles;
CREATE TRIGGER audit_mm_vehicle_history
    AFTER UPDATE OR DELETE ON public.mm_vehicles
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_mm_vehicle_history();


-------------------------------------------------------------------------------
-- 3. Micromobility Stations (mm_stations) - Optional Usage
-- Description: Defines docking, parking, or charging stations (optional for dockless systems).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_stations (
    station_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name            VARCHAR(100) NOT NULL, -- Station name or identifier
    location        GEOGRAPHY(POINT, 4326) NOT NULL, -- Geographic location
    -- Number of docks (NULL if dockless zone)
    capacity        SMALLINT NULL CHECK (capacity IS NULL OR capacity >= 0),
    is_charging     BOOLEAN DEFAULT FALSE NOT NULL, -- Does this station provide charging?
    is_active       BOOLEAN DEFAULT TRUE NOT NULL, -- Is the station operational?
    -- E.g., {"operating_hours": "06:00-23:00"}
    metadata        JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.mm_stations
    IS '[VoyaGo][Micromobility] Defines docking, parking, or charging stations 
        (Usage is optional, especially for dockless systems).';
COMMENT ON COLUMN public.mm_stations.capacity
    IS 'Number of docks available at the station. NULL can indicate a 
        virtual station or dockless parking zone.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_mm_stations ON public.mm_stations;
CREATE TRIGGER trg_set_timestamp_on_mm_stations
    BEFORE UPDATE ON public.mm_stations
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Stations
CREATE INDEX IF NOT EXISTS idx_mm_stations_active ON public.mm_stations(is_active);
-- For finding nearby stations
CREATE INDEX IF NOT EXISTS idx_mm_stations_loc ON public.mm_stations USING GIST(location);


-------------------------------------------------------------------------------
-- 4. Station Status (mm_station_status) - Optional Usage, Time-Series
-- Description: Tracks time-series data of vehicle/dock availability at stations.
-- Note: Can grow large, consider partitioning or TTL policies later.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_station_status (
    station_id          UUID NOT NULL,    -- Link to the station (FK defined later)
    status_time         TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), -- Timestamp of the status snapshot
    -- Count of available vehicles (NULL if not tracked/dockless)
    available_vehicles  SMALLINT NULL CHECK (available_vehicles IS NULL OR available_vehicles >= 0),
    -- Count of empty docks (NULL if not tracked/dockless)
    available_docks     SMALLINT NULL CHECK (available_docks IS NULL OR available_docks >= 0),
    is_operational      BOOLEAN DEFAULT TRUE NOT NULL, -- Was the station operational at this time?
    PRIMARY KEY (station_id, status_time) -- Composite PK ensures one status record per station per timestamp
);
COMMENT ON TABLE public.mm_station_status
    IS '[VoyaGo][Micromobility] Time-series log of vehicle/dock availability at stations 
        (More critical for docked systems). Consider partitioning/TTL.';

-- Indexes for Station Status
-- PK already covers (station_id, status_time). An index on just status_time might be 
    --useful for latest status queries across stations.
CREATE INDEX IF NOT EXISTS idx_mm_station_status_time
    ON public.mm_station_status(status_time DESC);


-------------------------------------------------------------------------------
-- 5. Ride Sessions (mm_rides) – Partitioned by start_time
-- Description: Records individual user ride sessions on micromobility vehicles.
-- Note: Partitioned by start_time. Partitions must be managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_rides (
    -- ride_id is part of PK, no default needed if application supplies it before insert
    ride_id             UUID NOT NULL,
    user_id             UUID NOT NULL,          -- User taking the ride (FK defined later)
    vehicle_id          UUID NOT NULL,          -- Vehicle used for the ride (FK defined later)
    start_time          TIMESTAMPTZ NOT NULL,   -- Ride start time (Partition Key & part of PK)
    end_time            TIMESTAMPTZ NULL,       -- Ride end time
    start_station_id    UUID NULL,              -- Starting station, if applicable (FK defined later)
    end_station_id      UUID NULL,              -- Ending station, if applicable (FK defined later)
    start_location      GEOGRAPHY(POINT, 4326) NOT NULL, -- Precise start location
    end_location        GEOGRAPHY(POINT, 4326) NULL, -- Precise end location
    route_geometry      GEOGRAPHY(LINESTRING, 4326) NULL, -- Optional: Recorded route geometry
    ride_status         public.mm_ride_status NOT NULL DEFAULT 'ONGOING', -- Ride status (ENUM from 001)
    -- Calculated ride distance
    distance_meters     NUMERIC(12,2) NULL CHECK (distance_meters IS NULL OR distance_meters >= 0),
    -- Calculated ride duration
    duration_seconds    INTEGER NULL CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    fare                NUMERIC(12,2) NULL CHECK (fare IS NULL OR fare >= 0), -- Calculated ride fare
    currency_code       CHAR(3) NULL,           -- Fare currency (FK defined later)
    payment_id          UUID NULL,              -- Link to the payment transaction (FK defined later)
    -- E.g., {"promo_applied": "MM_FIRST"}
    metadata            JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,       -- Automatically updated by trigger

    PRIMARY KEY (start_time, ride_id) -- Composite PK including partition key

) PARTITION BY RANGE (start_time);

COMMENT ON TABLE public.mm_rides
    IS '[VoyaGo][Micromobility] Records individual ride sessions undertaken by users 
        (Partitioned by start_time).';
COMMENT ON COLUMN public.mm_rides.start_time
    IS 'Timestamp when the ride started. Used as the partition key.';
COMMENT ON COLUMN public.mm_rides.fare
    IS 'Final calculated fare for the ride, typically populated after the ride ends.';
COMMENT ON COLUMN public.mm_rides.payment_id
    IS 'Reference to the payment record in pmt_payments covering this ride''s fare.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_mm_rides ON public.mm_rides;
CREATE TRIGGER trg_set_timestamp_on_mm_rides
    BEFORE UPDATE ON public.mm_rides
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Rides (Defined on main table)
-- PK provides index on (start_time, ride_id)
CREATE INDEX IF NOT EXISTS idx_mm_rides_user_time
    ON public.mm_rides(user_id, start_time DESC); -- Find user's recent rides
CREATE INDEX IF NOT EXISTS idx_mm_rides_vehicle_time
    ON public.mm_rides(vehicle_id, start_time DESC); -- Find vehicle's recent rides
CREATE INDEX IF NOT EXISTS idx_mm_rides_status
    ON public.mm_rides(ride_status);
CREATE INDEX IF NOT EXISTS idx_mm_rides_start_loc
    ON public.mm_rides USING GIST(start_location); -- Spatial index on start location
CREATE INDEX IF NOT EXISTS idx_mm_rides_end_loc
    -- Spatial index on end location
    ON public.mm_rides USING GIST(end_location) WHERE end_location IS NOT NULL;


-------------------------------------------------------------------------------
-- 6. Ride Events (mm_ride_events) - ** ride_start_time ADDED **
-- Description: Logs significant events occurring during a ride or related to a vehicle.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_ride_events (
    event_id        BIGSERIAL PRIMARY KEY,
    -- Link to the ride session (Composite FK defined later)
    ride_id         UUID NOT NULL,
    ride_start_time TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    -- Timestamp of the event
    event_time      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Type of event (ENUM from 001)
    event_type      public.mm_event_type NOT NULL,
    -- Optional text description of the event location
    location_text   TEXT NULL,
    -- Optional geographic coordinates of the event
    location_point  GEOGRAPHY(POINT, 4326) NULL,
    -- Optional battery level at the time of the event
    battery_level   SMALLINT NULL CHECK (battery_level IS NULL OR (battery_level BETWEEN 0 AND 100)),
    -- Additional event-specific data (e.g., geofence ID for geofence events)
    metadata        JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    -- Optional actor performing the event
    actor_id        UUID NULL
);
COMMENT ON TABLE public.mm_ride_events
    IS '[VoyaGo][Micromobility] Log of significant events related to a ride or vehicle 
        (e.g., unlock, lock, geofence enter/exit).';
COMMENT ON COLUMN public.mm_ride_events.ride_start_time
    IS 'Partition key copied from mm_rides for composite foreign key.';
COMMENT ON COLUMN public.mm_ride_events.metadata
    IS 'Additional structured data specific to the event type, 
        e.g., {"geofence_id": "zone_123"} for geofence events.';

-- Indexes for Ride Events
-- Get events for a specific ride (using composite key)
CREATE INDEX IF NOT EXISTS idx_mm_ride_events_ride_time
    ON public.mm_ride_events(ride_id, ride_start_time, event_time DESC); -- Updated Index
CREATE INDEX IF NOT EXISTS idx_mm_ride_events_type
    ON public.mm_ride_events(event_type);
CREATE INDEX IF NOT EXISTS idx_mm_ride_events_loc
    -- Spatial queries on event locations
    ON public.mm_ride_events USING GIST (location_point) WHERE location_point IS NOT NULL;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- lkp_mm_vehicle_types_translations -> lkp_mm_vehicle_types (type_code -> type_code) [CASCADE]
-- lkp_mm_vehicle_types_translations -> lkp_languages (language_code -> code) [CASCADE]
--
-- mm_vehicles -> lkp_mm_vehicle_types (vehicle_type_code -> type_code) [RESTRICT]
-- mm_vehicles -> fleet_partners (partner_id -> partner_id) [SET NULL?]
-- mm_vehicles -> core_user_profiles (current_user_id -> user_id) [SET NULL]
-- mm_vehicles -> mm_rides (current_ride_start_time, current_ride_id -> 
    --start_time, ride_id) [SET NULL] -- COMPOSITE FK
--
-- mm_vehicles_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- mm_vehicles_history -> mm_vehicles (vehicle_id -> vehicle_id) [CASCADE]
--
-- mm_station_status -> mm_stations (station_id -> station_id) [CASCADE]
--
-- mm_rides -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- mm_rides -> mm_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- mm_rides -> mm_stations (start_station_id -> station_id) [SET NULL]
-- mm_rides -> mm_stations (end_station_id -> station_id) [SET NULL]
-- mm_rides -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- mm_rides -> pmt_payments (payment_id -> payment_id) [SET NULL]
--
-- mm_ride_events -> mm_rides (ride_start_time, ride_id -> start_time, ride_id) [CASCADE] -- COMPOSITE FK
-- mm_ride_events -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 014_micromobility.sql (Version 1.2)
-- ============================================================================
