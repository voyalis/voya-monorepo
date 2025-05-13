-- ============================================================================
-- Migration: 013_cargo_logistics.sql (Version 1.2 - Added booking_created_at for FKs)
-- Description: VoyaGo - Cargo & Logistics Module Schema: Partners, Shipments,
--              Packages, Tracking Events, Leg Assignments. Includes history tables,
--              revised leg assignment linkage, and helper triggers. Adds partition key cols.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql, 010_booking_core.sql,
--               011_finance_core.sql
-- ============================================================================

BEGIN;

-- Prefix 'cargo_' denotes tables specific to the Cargo & Logistics module.

-------------------------------------------------------------------------------
-- 1. Cargo Partners (cargo_partners)
-- Description: Represents business partners providing cargo and logistics services.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_partners (
    partner_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Optional link to a general partner record in fleet_partners
    fleet_partner_id    UUID NULL UNIQUE,
    name                VARCHAR(150) NOT NULL UNIQUE, -- Display name of the cargo partner
    contact_email       TEXT NULL CHECK (contact_email IS NULL 
        OR contact_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'),
    contact_phone       TEXT NULL,          -- PII: Sensitive Data! Handle securely.
    -- Default service level offered by this partner (ENUM from 001)
    service_level       public.cargo_partner_service_level NOT NULL DEFAULT 'STANDARD',
    -- URL template for tracking shipments via partner's system 
        -- (e.g., 'https://tracker.cargopartner.com/?id={tracking_id}')
    tracking_url_template TEXT NULL,
    -- Optional link to API integration configuration
    api_integration_id  UUID NULL,
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.cargo_partners
    IS '[VoyaGo][Cargo] Defines cargo and logistics service partners integrated with the platform.';
COMMENT ON COLUMN public.cargo_partners.fleet_partner_id
    IS 'Optional foreign key linking to the main fleet_partners table if the 
        cargo partner is also a fleet partner.';
COMMENT ON COLUMN public.cargo_partners.contact_phone
    IS 'PII - Sensitive Data! Should be handled securely.';
COMMENT ON COLUMN public.cargo_partners.tracking_url_template
    IS 'URL template used to construct tracking links for this partner''s shipments. 
        Use {tracking_id} as placeholder.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cargo_partners ON public.cargo_partners;
CREATE TRIGGER trg_set_timestamp_on_cargo_partners
    BEFORE UPDATE ON public.cargo_partners
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Cargo Partners
CREATE INDEX IF NOT EXISTS idx_cargo_partners_service ON public.cargo_partners(service_level);
CREATE INDEX IF NOT EXISTS idx_cargo_partners_active ON public.cargo_partners(is_active);


-------------------------------------------------------------------------------
-- 2. Shipments (cargo_shipments) - ** booking_created_at ADDED **
-- Description: Main record for cargo shipments.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_shipments (
    shipment_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- User-friendly shipment identifier
    shipment_number         VARCHAR(25) NOT NULL UNIQUE 
        DEFAULT ('SHP' || upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 12))),
    -- Optional link to a VoyaGo booking (Composite FK defined later)
    booking_id              UUID NULL,
    booking_created_at      TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    -- Optional external reference ID (e.g., from an e-commerce platform)
    external_ref_id         TEXT NULL,
    -- Assigned cargo partner for this shipment
    cargo_partner_id        UUID NULL,
    -- Sender details
    sender_user_id          UUID NOT NULL,
    sender_address_id       UUID NOT NULL,
    -- Recipient details
    recipient_name          TEXT NOT NULL,      -- PII: Handle securely
    recipient_phone         TEXT NULL,          -- PII: Handle securely (encryption/masking recommended)
    recipient_email         TEXT NULL,          -- PII: Handle securely
    recipient_address_id    UUID NOT NULL,
    -- Time windows
    pickup_window_start     TIMESTAMPTZ NULL,
    pickup_window_end       TIMESTAMPTZ NULL,
    delivery_window_start   TIMESTAMPTZ NULL,
    delivery_window_end     TIMESTAMPTZ NULL,
    -- Shipment status (ENUM from 001)
    status                  public.cargo_status NOT NULL DEFAULT 'ORDER_PLACED',
    -- Value and dimensions
    total_declared_value    NUMERIC(12,2) NULL CHECK (total_declared_value IS NULL OR total_declared_value >= 0),
    currency_code           CHAR(3) NULL,       -- Currency for declared value
    total_weight_kg         NUMERIC(10,3) NULL CHECK (total_weight_kg IS NULL OR total_weight_kg >=0),
    total_volume_m3         NUMERIC(10,4) NULL CHECK (total_volume_m3 IS NULL OR total_volume_m3 >=0),
    -- Other details
    service_instructions    TEXT NULL,        -- Special instructions (e.g., fragile, keep upright)
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,   -- Automatically updated by trigger

    -- Check constraint for pickup time window consistency
    CONSTRAINT chk_cargo_shipment_pickup_window CHECK (pickup_window_start IS NULL 
        OR pickup_window_end IS NULL OR pickup_window_start <= pickup_window_end),
    -- Check constraint for delivery time window consistency
    CONSTRAINT chk_cargo_shipment_delivery_window CHECK (delivery_window_start IS NULL 
        OR delivery_window_end IS NULL OR delivery_window_start <= delivery_window_end),
    -- Ensure booking_created_at is present if booking_id is
    CONSTRAINT chk_cargo_booking_created_at CHECK (booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.cargo_shipments
    IS '[VoyaGo][Cargo] Main records for cargo shipments initiated on the platform.';
COMMENT ON COLUMN public.cargo_shipments.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if booking_id is not NULL).';
COMMENT ON COLUMN public.cargo_shipments.recipient_phone
    IS 'PII - Sensitive Data! Should be encrypted or masked.';
COMMENT ON COLUMN public.cargo_shipments.recipient_email
    IS 'PII - Sensitive Data! Should be handled securely.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cargo_shipments ON public.cargo_shipments;
CREATE TRIGGER trg_set_timestamp_on_cargo_shipments
    BEFORE UPDATE ON public.cargo_shipments
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Shipments
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_booking
    ON public.cargo_shipments(booking_id, booking_created_at) WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_partner
    ON public.cargo_shipments(cargo_partner_id) WHERE cargo_partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_sender
    ON public.cargo_shipments(sender_user_id);
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_status
    ON public.cargo_shipments(status);
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_pickup_window
    ON public.cargo_shipments(pickup_window_start, pickup_window_end);
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_delivery_window
    ON public.cargo_shipments(delivery_window_start, delivery_window_end);
CREATE INDEX IF NOT EXISTS idx_gin_cargo_shipments_meta
    ON public.cargo_shipments USING GIN (metadata) WHERE metadata IS NOT NULL;


-------------------------------------------------------------------------------
-- 2.1 Shipments History (cargo_shipments_history) - Added in v1.1
-- Description: Audit trail for changes made to cargo_shipments records.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_shipments_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL, -- INSERT, UPDATE, DELETE (ENUM from 001)
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,        -- User who performed the action (if available, e.g., from auth.uid())
    shipment_id     UUID NOT NULL,    -- The shipment that was changed
    shipment_data   JSONB NOT NULL      -- The state of the row *before* the UPDATE or DELETE action
);
COMMENT ON TABLE public.cargo_shipments_history
    IS '[VoyaGo][Cargo][History] Audit log capturing changes to cargo_shipments records.';
COMMENT ON COLUMN public.cargo_shipments_history.shipment_data
    IS 'Stores the JSONB representation of the cargo_shipments 
        row before the change occurred (for UPDATE/DELETE actions).';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_cargo_shipments_history_shipment
    ON public.cargo_shipments_history(shipment_id, action_at DESC);

-------------------------------------------------------------------------------
-- 2.2 Shipments History Trigger Function - Added in v1.1
-- Description: Function to automatically log changes to cargo_shipments.
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_cargo_shipment_history()
RETURNS TRIGGER
LANGUAGE plpgsql
-- SECURITY DEFINER recommended for audit triggers to ensure permissions,
-- but requires careful review of the function's safety.
SECURITY DEFINER
AS $$
DECLARE
    v_actor_id UUID;
    v_data JSONB;
BEGIN
    -- Attempt to get the actor ID from Supabase Auth context, default to NULL if unavailable
    BEGIN
        v_actor_id := auth.uid();
    EXCEPTION WHEN OTHERS THEN
        v_actor_id := NULL;
    END;

    -- Log the previous state on UPDATE or DELETE
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD); -- Capture the row data before the change
        INSERT INTO public.cargo_shipments_history
            (action_type, actor_id, shipment_id, shipment_data)
        VALUES
            (TG_OP::public.audit_action, v_actor_id, OLD.shipment_id, v_data);
    END IF;

    -- Return NEW for UPDATE, OLD for DELETE to allow the original operation to proceed
    IF TG_OP = 'UPDATE' THEN
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        RETURN OLD; -- Standard practice for AFTER DELETE triggers
    END IF;

    RETURN NULL; -- Should not be reached for AFTER triggers defined for UPDATE/DELETE
END;
$$;
COMMENT ON FUNCTION public.vg_log_cargo_shipment_history()
    IS '[VoyaGo][Cargo][TriggerFn] Logs previous state of cargo_shipments row to history table on UPDATE or DELETE.';

-- Create the trigger
DROP TRIGGER IF EXISTS audit_cargo_shipment_history ON public.cargo_shipments;
CREATE TRIGGER audit_cargo_shipment_history
    AFTER UPDATE OR DELETE ON public.cargo_shipments -- AFTER trigger ensures the main operation succeeded first
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_cargo_shipment_history();


-------------------------------------------------------------------------------
-- 3. Packages (cargo_packages)
-- Description: Details of individual packages within a shipment.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_packages (
    package_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- User-friendly package identifier
    package_number      VARCHAR(30) NOT NULL UNIQUE 
        DEFAULT ('PKG' || upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 15))),
    -- Link to the parent shipment (FK defined later, ON DELETE CASCADE)
    shipment_id         UUID NOT NULL,
    -- Sequence number within the shipment
    sequence_no         SMALLINT NOT NULL CHECK (sequence_no > 0),
    -- Physical attributes
    weight_kg           NUMERIC(8,3) NULL CHECK (weight_kg IS NULL OR weight_kg > 0), -- Made nullable as per review
    -- {"length": L, "width": W, "height": H}
    dimensions_cm       JSONB NULL CHECK (dimensions_cm IS NULL OR jsonb_typeof(dimensions_cm) = 'object'),
    -- Content details
    content_desc        TEXT NULL,        -- Description of contents
    declared_value      NUMERIC(12,2) NULL CHECK (declared_value IS NULL OR declared_value >= 0),
    currency_code       CHAR(3) NULL,     -- Currency for declared value (FK defined later)
    is_fragile          BOOLEAN DEFAULT FALSE NOT NULL,
    is_dangerous        BOOLEAN DEFAULT FALSE NOT NULL,
    -- Tracking
    tracking_id         TEXT NULL,    -- Optional specific tracking ID for this package (e.g., from partner)
    -- Metadata
    metadata            JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL
    -- updated_at often not needed if packages are immutable after creation, or use history table
);
COMMENT ON TABLE public.cargo_packages
    IS '[VoyaGo][Cargo] Stores details about individual packages within a shipment.';
COMMENT ON COLUMN public.cargo_packages.dimensions_cm
    IS 'Package dimensions in centimeters as JSONB. Example: {"length": 100, "width": 50, "height": 30}';
COMMENT ON COLUMN public.cargo_packages.weight_kg
    IS 'Weight of the package in kilograms. Made nullable.';

-- Unique constraint for package sequence within a shipment
ALTER TABLE public.cargo_packages DROP CONSTRAINT IF EXISTS uq_cargo_pkg_seq;
ALTER TABLE public.cargo_packages ADD CONSTRAINT uq_cargo_pkg_seq UNIQUE (shipment_id, sequence_no);

-- Indexes for Packages
CREATE INDEX IF NOT EXISTS idx_cargo_packages_shipment ON public.cargo_packages(shipment_id);
CREATE INDEX IF NOT EXISTS idx_cargo_packages_tracking_id
    ON public.cargo_packages(tracking_id) WHERE tracking_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 3.1 Packages History (cargo_packages_history) - Added in v1.1
-- Description: Audit trail for changes made to cargo_packages records.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_packages_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL, -- INSERT, UPDATE, DELETE (ENUM from 001)
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,          -- User who performed the action
    package_id      UUID NOT NULL,      -- The package that was changed
    package_data    JSONB NOT NULL        -- The state of the row *before* the UPDATE or DELETE action
);
COMMENT ON TABLE public.cargo_packages_history
    IS '[VoyaGo][Cargo][History] Audit log capturing changes to cargo_packages records.';
COMMENT ON COLUMN public.cargo_packages_history.package_data
    IS 'Stores the JSONB representation of the cargo_packages row before the change occurred 
        (for UPDATE/DELETE actions).';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_cargo_packages_history_pkg
    ON public.cargo_packages_history(package_id, action_at DESC);

-------------------------------------------------------------------------------
-- 3.2 Packages History Trigger Function - Added in v1.1
-- Description: Function to automatically log changes to cargo_packages.
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_cargo_package_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Review security implications
AS $$
DECLARE
    v_actor_id UUID;
    v_data JSONB;
BEGIN
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := NULL; END;

    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.cargo_packages_history
            (action_type, actor_id, package_id, package_data)
        VALUES
            (TG_OP::public.audit_action, v_actor_id, OLD.package_id, v_data);
    END IF;

    IF TG_OP = 'UPDATE' THEN RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_cargo_package_history()
    IS '[VoyaGo][Cargo][TriggerFn] Logs previous state of cargo_packages row to 
        history table on UPDATE or DELETE.';

-- Create the trigger
DROP TRIGGER IF EXISTS audit_cargo_package_history ON public.cargo_packages;
CREATE TRIGGER audit_cargo_package_history
    AFTER UPDATE OR DELETE ON public.cargo_packages
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_cargo_package_history();


-------------------------------------------------------------------------------
-- 4. Tracking Events (cargo_tracking_events) - Partitioned, Includes Shipment ID Trigger
-- Description: Time-stamped log of location and status updates for packages.
-- Note: Partitioned by event_time. Partitions must be managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_tracking_events (
    event_id        BIGSERIAL NOT NULL,
    -- Link to the specific package being tracked
    package_id      UUID NOT NULL,
    -- Denormalized shipment ID for easier querying (populated by trigger)
    shipment_id     UUID NOT NULL,
    -- Timestamp of the event (Partition Key)
    event_time      TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Location details
    location_text   TEXT NULL,        -- Description of the location (e.g., "Warehouse A")
    location_point  GEOGRAPHY(POINT, 4326) NULL, -- Geographic coordinates of the event
    -- Status update
    status          public.cargo_status NOT NULL, -- New status of the package (ENUM from 001)
    notes           TEXT NULL,        -- Additional notes related to the event
    -- Optional actor ID (e.g., driver performing scan)
    actor_id        UUID NULL,

    PRIMARY KEY (event_time, event_id) -- Composite PK including partition key

) PARTITION BY RANGE (event_time);

COMMENT ON TABLE public.cargo_tracking_events
    IS '[VoyaGo][Cargo] Time-stamped log of status and location updates for cargo packages 
        (Partitioned by event_time).';
COMMENT ON COLUMN public.cargo_tracking_events.event_time
    IS 'Timestamp when the tracking event occurred. Used as the partition key.';
COMMENT ON COLUMN public.cargo_tracking_events.shipment_id
    IS 'Denormalized shipment ID, automatically populated from the related package for easier querying.';
COMMENT ON CONSTRAINT cargo_tracking_events_pkey ON public.cargo_tracking_events
    IS 'Composite primary key including the partition key (event_time).';

-------------------------------------------------------------------------------
-- 4.1 Tracking Event Shipment ID Population Trigger Function - Added in v1.1
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_populate_tracking_shipment_id()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- On INSERT, find shipment_id from the package_id and assign it to NEW record
    IF TG_OP = 'INSERT' THEN
        SELECT cp.shipment_id INTO NEW.shipment_id
        FROM public.cargo_packages AS cp
        WHERE cp.package_id = NEW.package_id;

        -- If package isn't found (should ideally not happen due to FKs later), raise warning or error
        IF NEW.shipment_id IS NULL THEN
            RAISE WARNING '[vg_populate_tracking_shipment_id] Package % not found 
                for tracking event, setting shipment_id to NULL.', NEW.package_id;
            -- Alternatively, raise an exception if this is considered a critical error:
            -- RAISE EXCEPTION 'Package % not found for tracking event.', NEW.package_id;
        END IF;
    END IF;

    -- On UPDATE, if package_id changes (unlikely but possible), re-populate shipment_id
    IF TG_OP = 'UPDATE' AND NEW.package_id IS DISTINCT FROM OLD.package_id THEN
         SELECT cp.shipment_id INTO NEW.shipment_id
         FROM public.cargo_packages AS cp
         WHERE cp.package_id = NEW.package_id;

         IF NEW.shipment_id IS NULL THEN
             RAISE WARNING '[vg_populate_tracking_shipment_id] Updated Package % not found for tracking event.',
                NEW.package_id;
         END IF;
    END IF;

    RETURN NEW; -- Allow the INSERT or UPDATE operation to proceed
END;
$$;
COMMENT ON FUNCTION public.vg_populate_tracking_shipment_id()
    IS '[VoyaGo][Cargo][TriggerFn] Automatically populates shipment_id in 
        cargo_tracking_events based on package_id during INSERT or UPDATE.';

-- Attach the trigger (BEFORE operation to modify NEW row)
DROP TRIGGER IF EXISTS trg_populate_shipment_id_on_tracking ON public.cargo_tracking_events;
CREATE TRIGGER trg_populate_shipment_id_on_tracking
    -- Trigger only if package_id is involved
    BEFORE INSERT OR UPDATE OF package_id ON public.cargo_tracking_events 
    FOR EACH ROW EXECUTE FUNCTION public.vg_populate_tracking_shipment_id();


-- Indexes for Tracking Events (Defined on main table)
-- PK provides index on (event_time, event_id)
CREATE INDEX IF NOT EXISTS idx_cargo_events_pkg_time
    ON public.cargo_tracking_events(package_id, event_time DESC); -- Track events for a package
CREATE INDEX IF NOT EXISTS idx_cargo_events_shipment_time
    -- Track events for a shipment (uses denormalized ID)
    ON public.cargo_tracking_events(shipment_id, event_time DESC); 
CREATE INDEX IF NOT EXISTS idx_cargo_events_loc
    -- Spatial queries on event locations
    ON public.cargo_tracking_events USING GIST (location_point) WHERE location_point IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_events_status
    ON public.cargo_tracking_events(status);


-------------------------------------------------------------------------------
-- 5. Cargo Leg Assignments (cargo_leg_assignments) - ** booking_created_at ADDED **
-- Description: Assigns cargo-related booking legs (pickup, delivery) to vehicles/drivers.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_leg_assignments (
    assignment_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Link to the relevant leg in the main booking structure (Composite FK defined later)
    booking_leg_id      UUID NOT NULL,
    booking_created_at  TIMESTAMPTZ NOT NULL, -- (Partition key from booking_bookings via booking_booking_legs)
    -- Optional: Link to a specific package if the assignment is package-level
    package_id          UUID NULL,
    -- Assigned resources
    vehicle_id          UUID NULL,
    driver_id           UUID NULL,
    -- Type of assignment for this leg (e.g., pickup, delivery)
    assignment_type     VARCHAR(20) NOT NULL CHECK (assignment_type IN ('PICKUP', 'DELIVERY', 'TRANSFER', 'LINEHAUL')),
    -- Timestamps
    planned_start_time  TIMESTAMPTZ NULL,
    planned_end_time    TIMESTAMPTZ NULL,
    actual_start_time   TIMESTAMPTZ NULL,
    actual_end_time     TIMESTAMPTZ NULL,
    assigned_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL, -- Automatically updated by trigger

    -- Ensures a specific assignment type (e.g., PICKUP) is unique for a given booking leg
    CONSTRAINT uq_cargo_leg_assignment_type UNIQUE (booking_leg_id, assignment_type) DEFERRABLE INITIALLY DEFERRED
);
COMMENT ON TABLE public.cargo_leg_assignments
    IS '[VoyaGo][Cargo] Assigns cargo-related booking legs 
        (pickup, delivery, etc.) to specific vehicles/drivers.';
COMMENT ON COLUMN public.cargo_leg_assignments.booking_leg_id
    IS 'References the corresponding leg ID in the booking_booking_legs table.';
COMMENT ON COLUMN public.cargo_leg_assignments.booking_created_at
    IS 'Partition key copied from booking_bookings (via booking_booking_legs)
        for potential composite foreign key joins.';
COMMENT ON COLUMN public.cargo_leg_assignments.assignment_type
    IS 'Specifies the purpose of this assignment for the given booking leg 
        (e.g., Pickup task, Delivery task).';
COMMENT ON CONSTRAINT uq_cargo_leg_assignment_type ON public.cargo_leg_assignments
    IS 'Ensures that for a specific booking leg, 
        there is only one assignment of a particular type (e.g., one PICKUP assignment).';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_cargo_leg_assignments ON public.cargo_leg_assignments;
CREATE TRIGGER trg_set_timestamp_on_cargo_leg_assignments
    BEFORE UPDATE ON public.cargo_leg_assignments
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Assignments
-- Index for FK
CREATE INDEX IF NOT EXISTS idx_cargo_assign_leg ON public.cargo_leg_assignments(booking_leg_id, booking_created_at);
CREATE INDEX IF NOT EXISTS idx_cargo_assign_package
    ON public.cargo_leg_assignments(package_id) WHERE package_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_assign_vehicle
    ON public.cargo_leg_assignments(vehicle_id) WHERE vehicle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_assign_driver
    ON public.cargo_leg_assignments(driver_id) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cargo_assign_type ON public.cargo_leg_assignments(assignment_type);


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- cargo_partners -> fleet_partners (fleet_partner_id -> partner_id) [SET NULL? CASCADE?]
-- cargo_partners -> system_api_integrations (api_integration_id -> integration_id) [SET NULL]
--
-- cargo_shipments -> booking_bookings (booking_created_at, booking_id -> 
    --created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- cargo_shipments -> cargo_partners (cargo_partner_id -> partner_id) [RESTRICT]
-- cargo_shipments -> core_user_profiles (sender_user_id -> user_id) [RESTRICT]
-- cargo_shipments -> core_addresses (sender_address_id -> address_id) [RESTRICT]
-- cargo_shipments -> core_addresses (recipient_address_id -> address_id) [RESTRICT]
-- cargo_shipments -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- cargo_shipments_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- cargo_shipments_history -> cargo_shipments (shipment_id -> shipment_id) [CASCADE]
--
-- cargo_packages -> cargo_shipments (shipment_id -> shipment_id) [CASCADE]
-- cargo_packages -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- cargo_packages_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- cargo_packages_history -> cargo_packages (package_id -> package_id) [CASCADE]
--
-- cargo_tracking_events -> cargo_packages (package_id -> package_id) [CASCADE]
-- cargo_tracking_events -> cargo_shipments (shipment_id) 
    --[OMITTED - Partitioned Target, relies on package link]
-- cargo_tracking_events -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- cargo_leg_assignments -> booking_booking_legs (booking_created_at, booking_leg_id -> 
    --booking_created_at, leg_id) [CASCADE] -- COMPOSITE FK
-- cargo_leg_assignments -> cargo_packages (package_id -> package_id) [CASCADE?]
-- cargo_leg_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [SET NULL]
-- cargo_leg_assignments -> fleet_drivers (driver_id -> driver_id) [SET NULL]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 013_cargo_logistics.sql (Version 1.2)
-- ============================================================================
