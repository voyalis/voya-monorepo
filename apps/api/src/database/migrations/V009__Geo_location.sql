-- ============================================================================
-- Migration: 009_geo_location.sql (Version 1.1)
-- Description: Creates Geolocation module tables: Zones (with hierarchy and priority)
--              and partitioned Vehicle Location History (with altitude).
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               005_fleet_management.sql (for vehicle history FK)
-- ============================================================================

BEGIN;

-- Prefix 'geo_' denotes tables related to the Geolocation module.

-------------------------------------------------------------------------------
-- 1. Geographic Zones (geo_zones)
-- Description: Defines geographic areas (polygons) used for operations, pricing, etc.,
--              with support for hierarchy and priority to resolve overlaps.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.geo_zones (
    zone_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- For hierarchical zones (e.g., neighborhood within a city) (FK defined later)
    parent_zone_id      UUID NULL,
    name                VARCHAR(100) NOT NULL, -- User-friendly name for the zone
    zone_type_code      VARCHAR(30) NOT NULL, -- Type of zone (FK to lkp_zone_types, defined later)
    polygon             GEOGRAPHY(POLYGON, 4326) NOT NULL, -- The geographic boundary of the zone
    -- Zone-specific rules (pricing, allowed services etc.)
    rules               JSONB NULL CHECK (rules IS NULL OR jsonb_typeof(rules) = 'object'),
    priority            INTEGER DEFAULT 0 NOT NULL, -- Priority for resolving overlaps (higher value = higher priority)
    is_active           BOOLEAN DEFAULT TRUE NOT NULL, -- Is the zone currently active?
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);

COMMENT ON TABLE public.geo_zones
    IS '[VoyaGo][Geo] Defines geographic zones (operational areas, pricing zones, etc.) 
        with hierarchy and priority.';
COMMENT ON COLUMN public.geo_zones.polygon
    IS 'The geometric polygon defining the zone boundaries, using WGS 84 (SRID 4326).';
COMMENT ON COLUMN public.geo_zones.rules
    IS '[VoyaGo] Zone-specific rules as JSONB. 
        Example: {"pricing_modifier": 1.25, "allowed_services": ["TRANSFER"], "speed_limit_kph": 30}';
COMMENT ON COLUMN public.geo_zones.priority
    IS 'Determines precedence among overlapping zones of the same type (higher value means higher priority).';

-- Indexes for Zones
-- Critical for spatial queries (point-in-polygon)
CREATE INDEX IF NOT EXISTS idx_geo_zones_polygon ON public.geo_zones USING gist (polygon);
COMMENT ON INDEX public.idx_geo_zones_polygon 
    IS '[VoyaGo][Perf] Essential GIST index for performing spatial queries against zone boundaries.';
-- Find highest priority active zone of a type
CREATE INDEX IF NOT EXISTS idx_geo_zones_type_priority_active ON public.geo_zones(
    zone_type_code, priority DESC, is_active
);
CREATE INDEX IF NOT EXISTS idx_geo_zones_parent ON public.geo_zones(parent_zone_id) WHERE parent_zone_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_geo_zones_rules ON public.geo_zones USING gin (rules) WHERE rules IS NOT NULL;


-------------------------------------------------------------------------------
-- 2. Vehicle Location History (fleet_vehicle_location_history) - PARTITIONED TABLE
-- Description: Stores historical location data for vehicles, including altitude.
-- Note: This table is partitioned by range on 'recorded_at'. Partitions must be created and managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fleet_vehicle_location_history (
    vehicle_id          UUID NOT NULL,      -- Vehicle identifier (FK defined later)
    -- Timestamp of the location record (Partition Key) - Renamed from 'timestamp'
    recorded_at         TIMESTAMPTZ NOT NULL,
    location            GEOGRAPHY(POINT, 4326) NOT NULL, -- Geographic coordinates
    altitude_meters     NUMERIC(7,2) NULL,  -- Altitude above sea level in meters (optional)
    speed_kmh           NUMERIC(6,2) NULL CHECK (speed_kmh IS NULL OR speed_kmh >= 0), -- Speed in km/h
    -- Direction of travel (0-359 degrees)
    heading             SMALLINT NULL CHECK (heading IS NULL OR (heading BETWEEN 0 AND 359)),
    -- Positional accuracy in meters
    accuracy_meters     NUMERIC(6,2) NULL CHECK (accuracy_meters IS NULL OR accuracy_meters >= 0),
    -- Source of the location data
    source              VARCHAR(10) NULL CHECK (source IS NULL OR source IN ('GPS', 'NETWORK', 'MANUAL', 'OBD')),
    PRIMARY KEY (vehicle_id, recorded_at) -- Composite primary key suitable for partitioned table
) PARTITION BY RANGE (recorded_at);

COMMENT ON TABLE public.fleet_vehicle_location_history
    IS '[VoyaGo][Fleet][Location] Stores historical vehicle location points (including altitude). 
        Partitioned by timestamp for scalability.';
COMMENT ON COLUMN public.fleet_vehicle_location_history.recorded_at
    IS 'Timestamp when the location was recorded. This column is the partition key.';
COMMENT ON COLUMN public.fleet_vehicle_location_history.location
    IS 'Geographic point coordinates using WGS 84 (SRID 4326).';
COMMENT ON COLUMN public.fleet_vehicle_location_history.altitude_meters
    IS 'Altitude above sea level in meters, if available from the source.';
COMMENT ON COLUMN public.fleet_vehicle_location_history.heading
IS 'Compass direction of travel (degrees from North), if available.';
COMMENT ON COLUMN public.fleet_vehicle_location_history.accuracy_meters
    IS 'Estimated accuracy of the location reading in meters, if available.';
COMMENT ON CONSTRAINT fleet_vehicle_location_history_pkey ON public.fleet_vehicle_location_history
    IS 'Composite primary key ensures uniqueness per vehicle per timestamp, 
        suitable for partitioned tables.';

-- Indexes for Location History (Defined on the main table, propagated to partitions)
-- The primary key implicitly creates an index on (vehicle_id, recorded_at).
-- For time-based queries on history
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_location_history_time ON public.fleet_vehicle_location_history(
    recorded_at DESC
);
-- For spatial queries on history
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_location_history_loc ON public.fleet_vehicle_location_history USING gist (
    location
);


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for geo_zones
DROP TRIGGER IF EXISTS trg_set_timestamp_on_geo_zones ON public.geo_zones;
CREATE TRIGGER trg_set_timestamp_on_geo_zones
BEFORE UPDATE ON public.geo_zones
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Note: No updated_at trigger needed for fleet_vehicle_location_history (append-only log table).


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- ============================================================================

-- TODO in Migration 025: Add DEFERRABLE FK 
    --from geo_zones.parent_zone_id to geo_zones.zone_id (ON DELETE SET NULL or RESTRICT?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from geo_zones.zone_type_code to lkp_zone_types.zone_type_code (ON DELETE RESTRICT)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from fleet_vehicle_location_history.vehicle_id to fleet_vehicles.vehicle_id (ON DELETE CASCADE?)
--      Note on CASCADE for history: Deleting a vehicle cascades to delete its history. This can be intensive.
--      Alternatives: SET NULL (keeps history, loses link) or NO ACTION (prevents vehicle deletion if history exists).
--      CASCADE is often acceptable if vehicle deletion is rare and complete data removal is desired.


COMMIT;

-- ============================================================================
-- End of Migration: 009_geo_location.sql (Version 1.1)
-- ============================================================================
