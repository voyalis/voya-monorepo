-- ============================================================================
-- Migration: 010c_shared_ride_schema.sql (Version 1.0)
-- Description: VoyaGo - Shared Ride Module Base Schema: ENUMs, Requests, Matches,
--              Members, and Assignments.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 005_fleet_management.sql,
--               010_booking_core.sql
-- ============================================================================

BEGIN;

-- Prefix 'shared_ride_' denotes tables specific to the Shared Ride module.

-------------------------------------------------------------------------------
-- 0. Shared Ride Specific ENUM Types
-------------------------------------------------------------------------------

DO $$
BEGIN
    CREATE TYPE public.shared_ride_request_status AS ENUM (
        'PENDING',                      -- Request received, awaiting matching
        'MATCHING_IN_PROGRESS',         -- Being processed by the matching engine
        'MATCHED_PENDING_ACCEPTANCE',   -- Match found, awaiting user/system confirmation
        'ASSIGNED',                     -- Match confirmed and assigned to a driver
        'CANCELLED_BY_USER',            -- Cancelled by the user
        'EXPIRED',                      -- Timed out or no suitable match found
        'FAILED'                        -- Technical failure during processing
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.shared_ride_request_status
    IS '[VoyaGo][ENUM][SharedRide] Represents the status of a user''s request for a shared ride.';

DO $$
BEGIN
    CREATE TYPE public.shared_ride_match_status AS ENUM (
        'PROPOSED',                     -- Suggested by the matching engine
        'CONFIRMED',                    -- Confirmed by all participants or system rules
        'ASSIGNED_TO_DRIVER',           -- Assigned to a specific driver/vehicle
        'ACTIVE',                       -- The shared ride journey has started
        'COMPLETED',                    -- The shared ride journey is fully completed
        'CANCELLED'                     -- The match was cancelled before or during the trip
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.shared_ride_match_status
    IS '[VoyaGo][ENUM][SharedRide] Represents the status of a group of matched shared ride requests.';

DO $$
BEGIN
    CREATE TYPE public.shared_ride_assignment_status AS ENUM (
        'OFFERED',                      -- Offered to a driver
        'ACCEPTED',                     -- Accepted by the driver
        'REJECTED',                     -- Rejected by the driver
        'EN_ROUTE_FIRST_PICKUP',        -- Driver is en route to the first pickup location
        'ACTIVE_PICKUPS',               -- Driver is currently picking up passengers
        'ACTIVE_DROPOFFS',              -- Driver is currently dropping off passengers
        'COMPLETED',                    -- All passengers dropped off, assignment completed
        'CANCELLED_BY_DRIVER',          -- Cancelled by the driver after acceptance
        'CANCELLED_BY_SYSTEM'           -- Cancelled by the system (e.g., due to timeout, operational issue)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.shared_ride_assignment_status
    IS '[VoyaGo][ENUM][SharedRide] Represents the status of a shared ride assignment from the driver''s perspective.';

-------------------------------------------------------------------------------
-- Helper Function for Assignment Timestamps
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_trigger_set_assignment_timestamps()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
AS $$
BEGIN
    -- Always update updated_at on any modification
    NEW.updated_at := clock_timestamp();

    -- Only update status_updated_at if the status column actually changes
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        NEW.status_updated_at := clock_timestamp();
    END IF;

    RETURN NEW;
END;
$$;
COMMENT ON FUNCTION public.vg_trigger_set_assignment_timestamps()
    IS '[VoyaGo][Helper] Trigger function to set updated_at always, and status_updated_at only when status changes.';

-------------------------------------------------------------------------------
-- 1. Shared Ride Requests (shared_ride_requests)
-- Description: Stores individual user requests for joining or initiating a shared ride.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shared_ride_requests (
    request_id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                         UUID NOT NULL,    -- User making the request
    origin_address_id               UUID NOT NULL,    -- Origin address
    destination_address_id          UUID NOT NULL,    -- Destination address
    earliest_pickup_time            TIMESTAMPTZ NOT NULL, -- Earliest acceptable pickup time
    latest_pickup_time              TIMESTAMPTZ NOT NULL, -- Latest acceptable pickup time
    passenger_count                 SMALLINT NOT NULL DEFAULT 1 CHECK (passenger_count > 0),
    -- Max extra travel time user accepts
    max_detour_preference_minutes   SMALLINT NULL CHECK (
        max_detour_preference_minutes IS NULL OR max_detour_preference_minutes >= 0
    ),
    -- Max price user is willing to pay
    max_price_preference            NUMERIC(10,2) NULL CHECK (max_price_preference IS NULL OR max_price_preference > 0),
    request_time                    TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the request was made
    -- Current status of the request
    status                          public.shared_ride_request_status NOT NULL DEFAULT 'PENDING',
    assigned_match_id               UUID NULL,        -- Match this request belongs to, once assigned
    cancellation_reason             TEXT NULL,        -- Reason if status is CANCELLED_BY_USER
    created_at                      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at                      TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_shared_ride_request_times CHECK (latest_pickup_time >= earliest_pickup_time)
);
COMMENT ON TABLE public.shared_ride_requests
    IS '[VoyaGo][SharedRide] Stores user requests for shared rides, including preferences and status.';
COMMENT ON COLUMN public.shared_ride_requests.max_detour_preference_minutes
    IS 'Maximum additional travel time (in minutes) the user is willing to tolerate compared to a direct route.';
COMMENT ON COLUMN public.shared_ride_requests.max_price_preference
    IS 'Optional: Maximum price the user is willing to pay for the shared ride.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_shared_ride_requests ON public.shared_ride_requests;
CREATE TRIGGER trg_set_timestamp_on_shared_ride_requests
    BEFORE UPDATE ON public.shared_ride_requests
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Requests
CREATE INDEX IF NOT EXISTS idx_srr_user_time ON public.shared_ride_requests(user_id, request_time DESC);
-- Index for matching engine: Find pending requests within time windows
CREATE INDEX IF NOT EXISTS idx_srr_status_time
    ON public.shared_ride_requests(status, earliest_pickup_time, latest_pickup_time) WHERE status = 'PENDING';
COMMENT ON INDEX public.idx_srr_status_time
    IS '[VoyaGo][Perf] Optimized index for the matching engine to find pending requests.';
CREATE INDEX IF NOT EXISTS idx_srr_origin ON public.shared_ride_requests(origin_address_id);
CREATE INDEX IF NOT EXISTS idx_srr_destination ON public.shared_ride_requests(destination_address_id);
CREATE INDEX IF NOT EXISTS idx_srr_match
    ON public.shared_ride_requests(assigned_match_id) WHERE assigned_match_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 2. Shared Ride Matches (shared_ride_matches)
-- Description: Represents a group of matched shared ride requests proposed or confirmed by the system.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shared_ride_matches (
    match_id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status                  public.shared_ride_match_status NOT NULL DEFAULT 'PROPOSED', -- Status of the match group
    -- Estimated total cost for the matched ride
    estimated_cost          NUMERIC(12,2) NULL CHECK (estimated_cost IS NULL OR estimated_cost >= 0),
    currency_code           CHAR(3) NULL,       -- Currency of the estimated cost
    assigned_driver_id      UUID NULL,          -- Assigned driver
    assigned_vehicle_id     UUID NULL,          -- Assigned vehicle
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL    -- Automatically updated by trigger
);
COMMENT ON TABLE public.shared_ride_matches
    IS '[VoyaGo][SharedRide] Represents groups of matched user requests forming a potential or confirmed shared ride.';
COMMENT ON COLUMN public.shared_ride_matches.estimated_cost
    IS 'System-estimated total cost for completing all legs in this matched ride.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_shared_ride_matches ON public.shared_ride_matches;
CREATE TRIGGER trg_set_timestamp_on_shared_ride_matches
    BEFORE UPDATE ON public.shared_ride_matches
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Matches
CREATE INDEX IF NOT EXISTS idx_srm_status ON public.shared_ride_matches(status);
CREATE INDEX IF NOT EXISTS idx_srm_driver
    ON public.shared_ride_matches(assigned_driver_id) WHERE assigned_driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_srm_vehicle
    ON public.shared_ride_matches(assigned_vehicle_id) WHERE assigned_vehicle_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 3. Shared Ride Members (shared_ride_members) - M2M
-- Description: Links requests to matches, storing sequence and pricing details per member.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shared_ride_members (
    match_id                UUID NOT NULL,    -- Link to the match group
    -- Link to the user request. Unique ensures request is in only one match.
    request_id              UUID NOT NULL UNIQUE,
    pickup_sequence         SMALLINT NOT NULL CHECK (pickup_sequence > 0),   -- Order in which this member is picked up
    -- Order in which this member is dropped off
    dropoff_sequence        SMALLINT NOT NULL CHECK (dropoff_sequence > 0),
    estimated_pickup_time   TIMESTAMPTZ NULL, -- Estimated pickup time for this member
    estimated_dropoff_time  TIMESTAMPTZ NULL, -- Estimated dropoff time for this member
    -- Calculated fare for this member
    individual_fare         NUMERIC(10, 2) NULL CHECK (individual_fare IS NULL OR individual_fare >= 0),
    -- Optional score from the matching algorithm indicating match quality/weight
    weight_score            REAL NULL,

    PRIMARY KEY (match_id, request_id)
);
COMMENT ON TABLE public.shared_ride_members
    IS '[VoyaGo][SharedRide] Details of user requests within a specific match group 
        (pickup/dropoff order, estimated times, fare).';
COMMENT ON COLUMN public.shared_ride_members.request_id
    IS 'Unique reference to the user''s shared ride request included in this match.';
COMMENT ON COLUMN public.shared_ride_members.pickup_sequence
    IS 'The sequence number indicating the order this member will be picked up relative to others in the match.';
COMMENT ON COLUMN public.shared_ride_members.dropoff_sequence
    IS 'The sequence number indicating the order this member will be dropped off relative to others in the match.';
COMMENT ON COLUMN public.shared_ride_members.individual_fare
    IS 'The calculated fare allocated to this specific member of the shared ride.';
COMMENT ON COLUMN public.shared_ride_members.weight_score
    IS 'Optional score generated by the matching algorithm, 
        potentially indicating the contribution or quality of this member in the match.';

-- Indexes for Members
CREATE INDEX IF NOT EXISTS idx_srmem_req ON public.shared_ride_members(request_id); -- Find match details by request ID
-- Order members by pickup
CREATE INDEX IF NOT EXISTS idx_srmem_match_pickup_seq ON public.shared_ride_members(match_id, pickup_sequence);
-- Order members by dropoff
CREATE INDEX IF NOT EXISTS idx_srmem_match_dropoff_seq ON public.shared_ride_members(match_id, dropoff_sequence);


-------------------------------------------------------------------------------
-- 4. Shared Ride Assignments (shared_ride_assignments)
-- Description: Assigns a confirmed shared ride match to a specific driver/vehicle.
-- Note: Potential overlap with a generic dispatch system exists.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shared_ride_assignments (
    assignment_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- The match being assigned. Unique ensures one assignment per match.
    match_id            UUID NOT NULL UNIQUE,
    -- Assigned driver
    driver_id           UUID NOT NULL,
    -- Assigned vehicle
    vehicle_id          UUID NOT NULL,
    -- When the assignment was made/confirmed
    assigned_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- Assignment status (ENUM)
    status              public.shared_ride_assignment_status NOT NULL DEFAULT 'OFFERED',
    -- Optional reason for current status (e.g., rejection reason)
    status_reason       TEXT NULL,
    -- Timestamp of the last status change (set by trigger)
    status_updated_at   TIMESTAMPTZ NULL,
    -- Optimized route plan from AI/routing engine
    route_plan          JSONB NULL CHECK (route_plan IS NULL OR jsonb_typeof(route_plan) = 'object'),
    -- Breakdown of costs per request ID within the match
    cost_split_details  JSONB NULL CHECK (cost_split_details IS NULL OR jsonb_typeof(cost_split_details) = 'object'),
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- Automatically updated by trigger
    updated_at          TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.shared_ride_assignments
    IS '[VoyaGo][SharedRide] Assigns a confirmed shared ride match to a driver/vehicle, 
        including route plan and cost breakdown.';
COMMENT ON COLUMN public.shared_ride_assignments.match_id
    IS 'The shared ride match group being assigned to the driver/vehicle.';
COMMENT ON COLUMN public.shared_ride_assignments.status_updated_at
    IS 'Timestamp specifically tracking the last change in the assignment status.';
COMMENT ON COLUMN public.shared_ride_assignments.route_plan
    IS '[VoyaGo] Optimized route details as JSONB. Example: {"polyline": "...", 
        "total_distance_m": 15000, "total_duration_s": 1800, "legs": 
        [{"request_id": "...", "action": "pickup", "sequence": 1}, ...]}';
COMMENT ON COLUMN public.shared_ride_assignments.cost_split_details
    IS '[VoyaGo] Breakdown of fare allocation per request ID in the match. 
        Example: {"request_id_1": 15.50, "request_id_2": 18.20}';

-- Trigger for updated_at and status_updated_at
DROP TRIGGER IF EXISTS trg_set_assignment_timestamps ON public.shared_ride_assignments;
CREATE TRIGGER trg_set_assignment_timestamps
    BEFORE UPDATE ON public.shared_ride_assignments
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_assignment_timestamps(); -- Uses custom trigger defined above

-- Indexes for Assignments
-- UNIQUE constraint on match_id creates an index.
CREATE INDEX IF NOT EXISTS idx_sra_driver_status
    ON public.shared_ride_assignments(driver_id, status); -- Find assignments for a driver by status
CREATE INDEX IF NOT EXISTS idx_sra_vehicle_status
    ON public.shared_ride_assignments(vehicle_id, status); -- Find assignments for a vehicle by status
CREATE INDEX IF NOT EXISTS idx_sra_status
    ON public.shared_ride_assignments(status);


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- --------------------------------------------------------------------------------------------------
-- shared_ride_requests -> core_user_profiles (user_id -> user_id) [CASCADE? RESTRICT?]
-- shared_ride_requests -> core_addresses (origin_address_id -> address_id) [RESTRICT]
-- shared_ride_requests -> core_addresses (destination_address_id -> address_id) [RESTRICT]
-- shared_ride_requests -> shared_ride_matches (assigned_match_id -> match_id) [SET NULL]
--
-- shared_ride_matches -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- shared_ride_matches -> fleet_drivers (assigned_driver_id -> driver_id) [SET NULL]
-- shared_ride_matches -> fleet_vehicles (assigned_vehicle_id -> vehicle_id) [SET NULL]
--
-- shared_ride_members -> shared_ride_matches (match_id -> match_id) [CASCADE]
-- shared_ride_members -> shared_ride_requests (request_id -> request_id) [CASCADE]
--
-- shared_ride_assignments -> shared_ride_matches (match_id -> match_id) [CASCADE? RESTRICT?]
-- shared_ride_assignments -> fleet_drivers (driver_id -> driver_id) [RESTRICT?]
-- shared_ride_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [RESTRICT?]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 010c_shared_ride_schema.sql (Version 1.0)
-- ============================================================================
