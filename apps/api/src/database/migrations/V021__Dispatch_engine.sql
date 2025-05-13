-- ============================================================================
-- Migration: 021_dispatch_engine.sql (Version 1.3 - Fixed CHECK Constraint Syntax)
-- Description: VoyaGo - Dispatch Engine Support: Requests, Assignments, Routes, History.
--              Adds partition key columns for composite FKs. Fixes CHECK constraint syntax.
--              (Driver/Vehicle status is read from Fleet module tables)
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs, Trigger Fn), 003_core_user.sql,
--               005_fleet_management.sql, 010_booking_core.sql (Booking/Leg refs),
--               013_cargo_logistics.sql, 014_micromobility.sql, 015_shuttle_shared.sql (Related Entity IDs)
-- ============================================================================

BEGIN;

-- Prefix 'dispatch_' denotes tables related to the central dispatching system.

-------------------------------------------------------------------------------
-- 0. Dispatch Specific ENUM Types
-------------------------------------------------------------------------------

DO $$
BEGIN
    -- Request type should cover all dispatchable work items
    CREATE TYPE public.dispatch_request_type AS ENUM (
        'BOOKING_TRANSFER',         -- Assigning a driver/vehicle for a transfer booking
        'BOOKING_CARGO',            -- Assigning a driver/vehicle for a cargo pickup/delivery leg
        'BOOKING_SHUTTLE',          -- Assigning a driver/vehicle to a shuttle trip instance
        'MM_RIDE_START'             -- Potentially dispatching a task related to micromobility (e.g., relocation)
        -- Add other types as needed
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.dispatch_request_type
    IS '[VoyaGo][Dispatch][ENUM] Defines the type of work item being dispatched.';

DO $$
BEGIN
    CREATE TYPE public.dispatch_request_status AS ENUM (
        'PENDING',          -- Waiting to be processed by the dispatch engine
        'SEARCHING',        -- Actively searching for suitable drivers/vehicles
        'OFFERED',          -- Offer sent to one or more drivers
        'ASSIGNED',         -- A driver/vehicle has accepted and is assigned
        'NO_DRIVER_FOUND',  -- Search completed, no suitable assignment found
        'CANCELLED',        -- Request cancelled before assignment
        'FAILED'            -- Processing failed due to a system error
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.dispatch_request_status
    IS '[VoyaGo][Dispatch][ENUM] Represents the lifecycle status of a dispatch request.';

DO $$
BEGIN
    CREATE TYPE public.dispatch_assignment_status AS ENUM (
        'OFFERED',              -- Assignment offered to the driver
        'ACCEPTED',             -- Driver accepted the assignment
        'REJECTED',             -- Driver rejected the assignment
        'EN_ROUTE_PICKUP',      -- Driver is en route to the first pickup/origin
        'ARRIVED_PICKUP',       -- Driver has arrived at the first pickup/origin
        'STARTED',              -- The main task (ride/delivery) has started
        'COMPLETED',            -- The assignment is successfully completed
        'CANCELLED_BY_DRIVER',  -- Driver cancelled after accepting
        'CANCELLED_BY_SYSTEM'   -- System cancelled the assignment (e.g., timeout, conflict)
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.dispatch_assignment_status
    IS '[VoyaGo][Dispatch][ENUM] Represents the status of an assignment offered to/accepted by a driver.';


-------------------------------------------------------------------------------
-- 1. Dispatch Requests (dispatch_requests) - ** Partition Key Columns ADDED, CHECK constraints FIXED **
-- Description: Central registry for all dispatchable tasks/requests.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dispatch_requests (
    request_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Type of work being dispatched (ENUM defined above)
    request_type            public.dispatch_request_type NOT NULL,
    -- ID of the primary related entity (e.g., booking_id, mm_ride_id). FK is polymorphic.
    related_entity_id       UUID NOT NULL,
    -- Partition keys from potential related partitioned tables (populated based on request_type)
    booking_created_at      TIMESTAMPTZ NULL, -- For BOOKING_* types
    ride_start_time         TIMESTAMPTZ NULL, -- For MM_RIDE_START type
    -- User associated with the original request (optional)
    user_id                 UUID NULL,
    -- Core details for dispatching
    pickup_time             TIMESTAMPTZ NOT NULL, -- Required pickup time
    pickup_address_id       UUID NOT NULL,        -- Pickup location address ID
    dropoff_address_id      UUID NULL,            -- Dropoff location address ID (optional depending on type)
    status                  public.dispatch_request_status NOT NULL DEFAULT 'PENDING', -- Current status (ENUM)
    priority                INTEGER DEFAULT 0 NOT NULL, -- Priority level (higher value = higher priority)
    -- Requirements and Preferences
    required_vehicle_features JSONB NULL 
        -- e.g., {"min_capacity": 4, "wheelchair_accessible": true}
        CHECK (required_vehicle_features IS NULL OR jsonb_typeof(required_vehicle_features) = 'object'), 
    assigned_partner_id     UUID NULL,            -- If assignment should be restricted to a specific partner
    preferred_driver_id     UUID NULL,            -- Optional preference for a specific driver
    preferred_vehicle_id    UUID NULL,            -- Optional preference for a specific vehicle
    -- Metadata
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,     -- Automatically updated by trigger

    -- Ensure partition keys are consistent with request type (basic check) - ** FIXED SYNTAX **
    CONSTRAINT chk_dr_booking_created_at CHECK ((request_type::TEXT NOT LIKE 'BOOKING%') 
        OR booking_created_at IS NOT NULL),
    CONSTRAINT chk_dr_ride_start_time CHECK ((request_type::TEXT != 'MM_RIDE_START') 
        OR ride_start_time IS NOT NULL)
);
COMMENT ON TABLE public.dispatch_requests
    IS '[VoyaGo][Dispatch] Central table registering all requests requiring driver/vehicle dispatch.';
COMMENT ON COLUMN public.dispatch_requests.related_entity_id
    IS 'Identifier of the primary entity related to this request 
        (e.g., booking_id, mm_ride_id). Target table depends on request_type (Polymorphic).';
COMMENT ON COLUMN public.dispatch_requests.booking_created_at
    IS 'Partition key copied from booking_bookings for potential composite 
        foreign key joins (if request_type is BOOKING_*).';
COMMENT ON COLUMN public.dispatch_requests.ride_start_time
    IS 'Partition key copied from mm_rides for potential composite foreign key 
        joins (if request_type is MM_RIDE_START).';
COMMENT ON COLUMN public.dispatch_requests.required_vehicle_features
    IS '[VoyaGo] Specifies required vehicle capabilities as JSONB, used for matching.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_dispatch_requests ON public.dispatch_requests;
CREATE TRIGGER trg_set_timestamp_on_dispatch_requests
    BEFORE UPDATE ON public.dispatch_requests
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Dispatch Requests
CREATE INDEX IF NOT EXISTS idx_dr_status_time_prio
    ON public.dispatch_requests(status, pickup_time, priority DESC);
CREATE INDEX IF NOT EXISTS idx_dr_related_entity
    ON public.dispatch_requests(related_entity_id, request_type);
CREATE INDEX IF NOT EXISTS idx_dr_user
    ON public.dispatch_requests(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_dr_req_features
    ON public.dispatch_requests USING GIN (required_vehicle_features) 
    WHERE required_vehicle_features IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dr_booking_created_at
    ON public.dispatch_requests(booking_created_at) WHERE booking_created_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_dr_ride_start_time
    ON public.dispatch_requests(ride_start_time) WHERE ride_start_time IS NOT NULL;


-------------------------------------------------------------------------------
-- 1.1 Dispatch Request History (dispatch_requests_history)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dispatch_requests_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,          -- User/System performing the action
    request_id      UUID NOT NULL,      -- The request that was changed
    request_data    JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.dispatch_requests_history
    IS '[VoyaGo][Dispatch][History] Audit log capturing changes to dispatch_requests records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_dr_requests_hist_rid
    ON public.dispatch_requests_history(request_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Dispatch Request History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_dispatch_request_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.dispatch_requests_history
            (action_type, actor_id, request_id, request_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.request_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_dispatch_request_history()
    IS '[VoyaGo][Dispatch][TriggerFn] Logs previous state of dispatch_requests row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_dispatch_request_history ON public.dispatch_requests;
CREATE TRIGGER audit_dispatch_request_history
    AFTER UPDATE OR DELETE ON public.dispatch_requests
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_dispatch_request_history();


-------------------------------------------------------------------------------
-- 2. Driver/Vehicle Status Table (REMOVED in v1.1)
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
-- 3. Dispatch Assignments (dispatch_assignments) - ** booking_created_at ADDED **
-- Description: Records the assignment of a request to a specific driver/vehicle.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dispatch_assignments (
    assignment_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id              UUID NOT NULL,        -- Link to the dispatch request (FK defined later)
    driver_id               UUID NOT NULL,        -- Assigned driver (FK defined later)
    vehicle_id              UUID NOT NULL,        -- Assigned vehicle (FK defined later)
    assigned_at             TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the assignment was confirmed
    -- Assignment status (ENUM)
    status                  public.dispatch_assignment_status NOT NULL DEFAULT 'OFFERED', 
    status_reason           TEXT NULL,            -- Reason for current status (e.g., rejection reason)
    status_updated_at       TIMESTAMPTZ NULL,     -- Timestamp of last status change (set by custom trigger)
    estimated_pickup_time   TIMESTAMPTZ NULL,     -- Driver's ETA to pickup
    estimated_completion_time TIMESTAMPTZ NULL,   -- Estimated completion time for the entire assignment
    -- Route details (polyline, ETA, etc.)
    route_info              JSONB NULL CHECK (route_info IS NULL OR jsonb_typeof(route_info) = 'object'), 
    -- Optional link to the specific booking leg being fulfilled (Composite FK defined later)
    related_booking_leg_id  UUID NULL,
    booking_created_at      TIMESTAMPTZ NULL,     -- <<< EKLENEN SÜTUN
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    -- Audit fields for assignment creation/update
    created_by              UUID NULL,       -- User/System that created the assignment (FK defined later)
    updated_by              UUID NULL,       -- User/System that last updated the assignment (FK defined later)
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,     -- Automatically updated by custom trigger

    CONSTRAINT chk_da_booking_created_at CHECK (related_booking_leg_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.dispatch_assignments
    IS '[VoyaGo][Dispatch] Records the assignment of a dispatch request to 
        a driver/vehicle and tracks its progress.';
COMMENT ON COLUMN public.dispatch_assignments.booking_created_at
    IS 'Partition key copied from booking_bookings (via booking_booking_legs) 
        for composite foreign key (if related_booking_leg_id is not NULL).';
COMMENT ON COLUMN public.dispatch_assignments.route_info
    IS '[VoyaGo] Contains route details like encoded polyline, 
        ETA, distance, duration relevant to this assignment.';

-- Trigger for updated_at and status_updated_at
-- Note: Ensure vg_trigger_set_assignment_timestamps function (defined in 010c or earlier) exists.
DROP TRIGGER IF EXISTS trg_set_timestamp_on_dispatch_assignments ON public.dispatch_assignments;
CREATE TRIGGER trg_set_timestamp_on_dispatch_assignments
    BEFORE UPDATE ON public.dispatch_assignments
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_assignment_timestamps(); -- Uses custom trigger

-- Indexes for Assignments
CREATE INDEX IF NOT EXISTS idx_da_request ON public.dispatch_assignments(request_id);
CREATE INDEX IF NOT EXISTS idx_da_driver_status ON public.dispatch_assignments(driver_id, status);
CREATE INDEX IF NOT EXISTS idx_da_vehicle_status ON public.dispatch_assignments(vehicle_id, status);
CREATE INDEX IF NOT EXISTS idx_da_status ON public.dispatch_assignments(status);
-- Index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_da_leg
    ON public.dispatch_assignments(related_booking_leg_id, booking_created_at) 
    WHERE related_booking_leg_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 3.1 Dispatch Assignments History (dispatch_assignments_history)
-- Description: Audit trail for changes to dispatch_assignments.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dispatch_assignments_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    assignment_id   UUID NOT NULL,      -- The assignment that was changed
    assignment_data JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.dispatch_assignments_history
    IS '[VoyaGo][Dispatch][History] Audit log capturing changes to dispatch_assignments records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_da_hist_aid
    ON public.dispatch_assignments_history(assignment_id, action_at DESC);

-------------------------------------------------------------------------------
-- 3.2 Dispatch Assignments History Trigger Function
-------------------------------------------------------------------------------
-- Note: Ensure this function or a similar one is defined
CREATE OR REPLACE FUNCTION public.vg_log_dispatch_assignment_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.dispatch_assignments_history
            (action_type, actor_id, assignment_id, assignment_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.assignment_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_dispatch_assignment_history()
    IS '[VoyaGo][Dispatch][TriggerFn] Logs previous state of dispatch_assignments row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_dispatch_assignment_history ON public.dispatch_assignments;
CREATE TRIGGER audit_dispatch_assignment_history
    AFTER UPDATE OR DELETE ON public.dispatch_assignments
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_dispatch_assignment_history();


-------------------------------------------------------------------------------
-- 4. Route Cache (dispatch_routes) - Optional
-- Description: Optional table to cache calculated route details for assignments.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.dispatch_routes (
    route_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Links 1:1 to an assignment (UNIQUE)
    assignment_id   UUID NOT NULL UNIQUE,
    -- Encoded polyline representation of the route
    polyline        TEXT NOT NULL,
    distance_m      NUMERIC(12,2) NOT NULL CHECK (distance_m >= 0), -- Route distance in meters
    duration_s      INTEGER NOT NULL CHECK (duration_s >= 0), -- Route duration in seconds
    generated_at    TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the route was calculated
    expires_at      TIMESTAMPTZ NULL      -- Optional cache expiration time
);
COMMENT ON TABLE public.dispatch_routes
    IS '[VoyaGo][Dispatch][Cache] Optional cache for storing calculated route details 
        (polyline, distance, duration) associated with an assignment.';

-- Indexes for Route Cache
-- UNIQUE constraint on assignment_id creates an index
CREATE INDEX IF NOT EXISTS idx_dr_routes_expiry
    ON public.dispatch_routes(expires_at) WHERE expires_at IS NOT NULL;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- dispatch_requests -> core_user_profiles (user_id -> user_id) [SET NULL]
-- dispatch_requests -> core_addresses (pickup_address_id -> address_id) [RESTRICT]
-- dispatch_requests -> core_addresses (dropoff_address_id -> address_id) [RESTRICT?]
-- dispatch_requests -> fleet_partners (assigned_partner_id -> partner_id) [SET NULL]
-- dispatch_requests -> fleet_drivers (preferred_driver_id -> driver_id) [SET NULL]
-- dispatch_requests -> fleet_vehicles (preferred_vehicle_id -> vehicle_id) [SET NULL]
-- Note: FK for related_entity_id depends on request_type (Polymorphic). Needs join with partition key columns.
--       Example logic (not actual FK): JOIN booking_bookings b ON r.related_entity_id = 
    --b.booking_id AND r.booking_created_at = b.created_at WHERE r.request_type LIKE 'BOOKING%'
--
-- dispatch_requests_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- dispatch_requests_history -> dispatch_requests (request_id -> request_id) [CASCADE]
--
-- dispatch_assignments -> dispatch_requests (request_id -> request_id) [CASCADE]
-- dispatch_assignments -> fleet_drivers (driver_id -> driver_id) [RESTRICT]
-- dispatch_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- dispatch_assignments -> booking_booking_legs (booking_created_at, 
    --related_booking_leg_id -> booking_created_at, leg_id) [SET NULL?] -- COMPOSITE FK
-- dispatch_assignments -> core_user_profiles (created_by -> user_id) [SET NULL]
-- dispatch_assignments -> core_user_profiles (updated_by -> user_id) [SET NULL]
--
-- dispatch_assignments_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- dispatch_assignments_history -> dispatch_assignments (assignment_id -> assignment_id) [CASCADE]
--
-- dispatch_routes -> dispatch_assignments (assignment_id -> assignment_id) [CASCADE]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 021_dispatch_engine.sql (Version 1.3 - Fixed CHECK Syntax)
-- ============================================================================
