-- ============================================================================
-- Migration: 010_booking_core.sql (Version 1.3 - Added booking_created_at for Composite FKs)
-- Description: Creates core Booking & Journey module tables: Cancellation Policies,
--              Bookings (Partitioned), Legs, Status History, Bidding System.
--              Adds partition key column to tables referencing booking_bookings.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql, 003_core_user.sql,
--               004_core_organization.sql, 005_fleet_management.sql
-- ============================================================================

BEGIN;

-- Prefix 'booking_' denotes tables related to the Booking & Journey module.

-------------------------------------------------------------------------------
-- 10.1 Cancellation Policies (booking_cancellation_policies)
-- Description: Defines reusable policies for booking cancellation rules and fees.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_cancellation_policies (
    policy_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Unique name for the policy
    name            VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT NULL,
    -- Rules defining fee calculation based on time/status
    rules           JSONB NOT NULL CHECK (jsonb_typeof(rules) = 'array'),
    -- Is this the default policy?
    is_default      BOOLEAN DEFAULT FALSE NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.booking_cancellation_policies
    IS '[VoyaGo][Booking] Defines policies outlining booking cancellation rules and potential fees.';
COMMENT ON COLUMN public.booking_cancellation_policies.rules
    IS '[VoyaGo] Cancellation rules as a JSONB array. 
        Example: [{"hours_before": 24, "fee_percent": 0}, {"hours_before": 2, "fee_percent": 50}]';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_booking_cancel_policies ON public.booking_cancellation_policies;
CREATE TRIGGER trg_set_timestamp_on_booking_cancel_policies
    BEFORE UPDATE ON public.booking_cancellation_policies
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Policies
-- Find default active policy
CREATE INDEX IF NOT EXISTS idx_booking_cancel_policies_default
    ON public.booking_cancellation_policies(is_default, is_active);
CREATE INDEX IF NOT EXISTS idx_gin_booking_cancel_policies_rules
    ON public.booking_cancellation_policies USING GIN (rules);


-------------------------------------------------------------------------------
-- 10.2 Bookings (booking_bookings) - PARTITIONED TABLE (PK/Unique Fixed)
-- Description: Main table for all booking records. Partitioned by creation date.
-- Note: Partitions need to be created and managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_bookings (
    -- Core Identifiers (Part of PK or Unique Constraint)
    -- Partition Key & Part of PK/Unique
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Unique booking identifier (App/Trigger generated), Part of PK
    booking_id                  UUID NOT NULL,
    -- User-friendly ID, Part of Unique constraint
    booking_number              VARCHAR(20) NOT NULL DEFAULT (
        'BK' || upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 8))
    ),

    -- Core References
    -- User who made the booking
    user_id                     UUID NOT NULL,
    -- Associated organization, if applicable
    organization_id             UUID NULL,
    -- Main service type (ENUM from 001)
    service_code                public.service_code NOT NULL,
    -- Currency for pricing
    currency_code               CHAR(3) NOT NULL,

    -- Timestamps & Status
    -- Scheduled start time of the service/journey
    start_time                  TIMESTAMPTZ NULL,
    -- Scheduled end time of the service/journey
    end_time                    TIMESTAMPTZ NULL,
    -- Overall booking status (ENUM from 001)
    booking_status              public.booking_status NOT NULL DEFAULT 'DRAFT',
    -- Payment status (ENUM from 001)
    payment_status              public.payment_status NOT NULL DEFAULT 'PENDING',
    -- Last modification time (Trigger handled)
    updated_at                  TIMESTAMPTZ NULL,
    -- For optimistic locking
    concurrency_version         INTEGER NOT NULL DEFAULT 1,

    -- Pricing & Financials
    estimated_price             NUMERIC(12,2) NULL CHECK (estimated_price IS NULL OR estimated_price >= 0),
    final_price                 NUMERIC(12,2) NULL CHECK (final_price IS NULL OR final_price >= 0),
    total_tax_amount            NUMERIC(12,2) NULL CHECK (total_tax_amount IS NULL OR total_tax_amount >= 0),
    platform_commission_amount  NUMERIC(12,2) NULL CHECK (
        platform_commission_amount IS NULL OR platform_commission_amount >= 0
    ),

    -- Cancellation Details
    -- Applied cancellation policy
    cancellation_policy_id      UUID NULL,
    -- Reason code if cancelled
    cancellation_reason_code    VARCHAR(50) NULL,
    -- Timestamp of cancellation
    cancelled_at                TIMESTAMPTZ NULL,
    -- User/System/Admin who initiated cancellation
    cancelled_by_actor_id       UUID NULL,

    -- Additional Info
    -- Applied promotion code
    applied_promo_code          VARCHAR(50) NULL,
    -- Denormalized origin address text (optional)
    origin_address_text         TEXT NULL,
    -- Denormalized destination address text (optional)
    destination_address_text    TEXT NULL,
    -- User or system notes related to the booking
    notes                       TEXT NULL,
    -- Extra metadata
    metadata                    JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),

    -- Constraints including Partition Key
    PRIMARY KEY (created_at, booking_id),
    UNIQUE (created_at, booking_number)

) PARTITION BY RANGE (created_at);

COMMENT ON TABLE public.booking_bookings
    IS '[VoyaGo][Booking] Main table for booking records, partitioned by creation date (created_at). 
        PK and Unique constraints include the partition key.';
COMMENT ON COLUMN public.booking_bookings.created_at
    IS 'Timestamp when the booking record was created. Used as the partition key.';
COMMENT ON COLUMN public.booking_bookings.booking_id
    IS 'Unique identifier for the booking, generated by the application or a trigger. 
        Part of the composite primary key.';
COMMENT ON COLUMN public.booking_bookings.booking_number
    IS 'User-friendly, readable booking identifier. Part of a composite unique key.';
COMMENT ON COLUMN public.booking_bookings.origin_address_text
    IS 'Denormalized origin address for quick display, full details in booking_booking_legs.';
COMMENT ON COLUMN public.booking_bookings.destination_address_text
    IS 'Denormalized destination address for quick display, full details in booking_booking_legs.';
COMMENT ON COLUMN public.booking_bookings.concurrency_version
    IS 'Version number for optimistic concurrency control during updates.';
COMMENT ON CONSTRAINT booking_bookings_pkey ON public.booking_bookings
    IS 'Composite primary key including the partition key (created_at).';
COMMENT ON CONSTRAINT booking_bookings_created_at_booking_number_key ON public.booking_bookings
    IS 'Composite unique key including the partition key (created_at).';


-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_booking_bookings ON public.booking_bookings;
CREATE TRIGGER trg_set_timestamp_on_booking_bookings
    BEFORE UPDATE ON public.booking_bookings
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();


-- Indexes for Bookings (Defined on main table, propagated to partitions)
CREATE INDEX IF NOT EXISTS idx_booking_bookings_user_time
    ON public.booking_bookings(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_booking_bookings_org_time
    ON public.booking_bookings(organization_id, created_at DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_booking_bookings_status_payment
    ON public.booking_bookings(booking_status, payment_status);
CREATE INDEX IF NOT EXISTS idx_booking_bookings_start_time
    ON public.booking_bookings(start_time) WHERE start_time IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_booking_bookings_metadata
    ON public.booking_bookings USING GIN (metadata) WHERE metadata IS NOT NULL;


-------------------------------------------------------------------------------
-- 10.3 Booking Legs (booking_booking_legs) - ** booking_created_at ADDED **
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_booking_legs (
    leg_id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Link to the main booking (Composite FK defined later)
    booking_id              UUID NOT NULL,
    booking_created_at      TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN
    -- Order of this leg within the booking
    sequence                SMALLINT NOT NULL CHECK (sequence > 0),
    -- Mode of transport/service for this leg (ENUM from 001)
    mode                    public.service_code NOT NULL,
    -- Origin address (FK defined later)
    origin_address_id       UUID NOT NULL,
    -- Destination address (FK defined later)
    destination_address_id  UUID NOT NULL,
    -- Planned start time for this leg
    scheduled_start_time    TIMESTAMPTZ NULL,
    -- Planned end time for this leg
    scheduled_end_time      TIMESTAMPTZ NULL,
    -- Actual start time recorded
    actual_start_time       TIMESTAMPTZ NULL,
    -- Actual end time recorded
    actual_end_time         TIMESTAMPTZ NULL,
    -- Status of this specific leg (ENUM from 001)
    leg_status              public.booking_leg_status NOT NULL DEFAULT 'PLANNED',
    -- Assigned vehicle (FK defined later)
    assigned_vehicle_id     UUID NULL,
    -- Assigned driver (FK defined later)
    assigned_driver_id      UUID NULL,
    -- Operating partner for this leg (FK defined later)
    carrier_partner_id      UUID NULL,
    -- Estimated or actual distance
    distance_meters         INTEGER NULL CHECK (distance_meters IS NULL OR distance_meters >= 0),
    -- Estimated or actual duration
    duration_seconds        INTEGER NULL CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    -- Planned or actual route geometry (Requires GIST index later)
    route_geometry          GEOGRAPHY(LINESTRING, 4326) NULL,
    -- Price specifically for this leg (if applicable)
    leg_price               NUMERIC(12, 2) NULL CHECK (leg_price IS NULL OR leg_price >= 0),
    -- Additional leg-specific details
    leg_details             JSONB NULL CHECK (leg_details IS NULL OR jsonb_typeof(leg_details) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,

    -- Ensures sequence is unique per booking
    CONSTRAINT uq_booking_leg_sequence UNIQUE (booking_id, sequence) DEFERRABLE INITIALLY DEFERRED 
);
COMMENT ON TABLE public.booking_booking_legs
    IS '[VoyaGo][Booking] Represents individual segments or legs of a multi-part booking or journey.';
COMMENT ON COLUMN public.booking_booking_legs.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key.';
COMMENT ON COLUMN public.booking_booking_legs.sequence
    IS 'The sequential order of this leg within the overall booking.';
COMMENT ON COLUMN public.booking_booking_legs.route_geometry
    IS 'Planned or actual route as a LineString. Requires a GIST index for spatial queries (to be added later).';
COMMENT ON COLUMN public.booking_booking_legs.leg_details
    IS '[VoyaGo] Additional details specific to this leg. Example: {"flight_number": "VY123", "seat_number": "14A"}';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_booking_legs ON public.booking_booking_legs;
CREATE TRIGGER trg_set_timestamp_on_booking_legs
    BEFORE UPDATE ON public.booking_booking_legs
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Booking Legs
CREATE INDEX IF NOT EXISTS idx_booking_legs_driver_status
    ON public.booking_booking_legs(assigned_driver_id, leg_status) WHERE assigned_driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_booking_legs_vehicle_status
    ON public.booking_booking_legs(assigned_vehicle_id, leg_status) WHERE assigned_vehicle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_booking_legs_status
    ON public.booking_booking_legs(leg_status);
CREATE INDEX IF NOT EXISTS idx_booking_legs_scheduled_start
    ON public.booking_booking_legs(scheduled_start_time) WHERE scheduled_start_time IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_booking_legs_details
    ON public.booking_booking_legs USING GIN (leg_details) WHERE leg_details IS NOT NULL;
-- Add index including the new booking_created_at for FK joining
CREATE INDEX IF NOT EXISTS idx_booking_legs_booking
    ON public.booking_booking_legs(booking_id, booking_created_at);


-------------------------------------------------------------------------------
-- 10.4 Booking Status History (booking_status_history) - ** booking_created_at ADDED **
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_status_history (
    history_id          BIGSERIAL PRIMARY KEY,
    -- Link to the main booking (Composite FK defined later)
    booking_id          UUID NOT NULL,
    booking_created_at  TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN
    -- Link to the leg, if change is leg-specific (FK defined later)
    leg_id              UUID NULL,
    -- The status being set (value from booking_status or booking_leg_status ENUMs)
    status              TEXT NOT NULL,
    -- When the status change occurred
    timestamp           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    -- Who/what triggered the change
    actor_type          VARCHAR(10) CHECK (actor_type IN ('USER', 'DRIVER', 'SYSTEM', 'ADMIN', 'PARTNER')),
    -- ID of the actor (user, driver, partner), if applicable
    actor_id            UUID NULL,
    -- Optional notes explaining the change
    notes               TEXT NULL,
    -- Additional context about the change
    details             JSONB NULL CHECK (details IS NULL OR jsonb_typeof(details) = 'object')
);
COMMENT ON TABLE public.booking_status_history
    IS '[VoyaGo][Booking][Audit] Logs the history of status changes for bookings and booking legs.';
COMMENT ON COLUMN public.booking_status_history.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key.';
COMMENT ON COLUMN public.booking_status_history.status
    IS 'The value of the status (e.g., ''CONFIRMED'', ''COMPLETED'') being recorded.';
COMMENT ON COLUMN public.booking_status_history.actor_id
    IS 'Identifier for the user, driver, or partner who initiated the change, if applicable.';
COMMENT ON COLUMN public.booking_status_history.details
    IS '[VoyaGo] Additional structured details related to the status change. 
        Example: {"cancellation_fee_applied": 10.50}';

-- Indexes for Status History
-- Get history for a booking (using composite key)
CREATE INDEX IF NOT EXISTS idx_bsh_booking_time
    ON public.booking_status_history(booking_id, booking_created_at, timestamp DESC); -- Updated Index
-- Get history for a leg
CREATE INDEX IF NOT EXISTS idx_bsh_leg_time
    ON public.booking_status_history(leg_id, timestamp DESC) WHERE leg_id IS NOT NULL;
-- Find changes by actor
CREATE INDEX IF NOT EXISTS idx_bsh_actor
    ON public.booking_status_history(actor_type, actor_id) WHERE actor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_bsh_details
    ON public.booking_status_history USING GIN (details) WHERE details IS NOT NULL;


-------------------------------------------------------------------------------
-- 10.5 Bid Requests (booking_bid_requests) - ** booking_created_at ADDED, UNIQUE constraint updated **
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_bid_requests (
    request_id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Link to the main booking (Composite FK defined later). Needs UNIQUE constraint adjusted.
    booking_id                  UUID NOT NULL,
    booking_created_at          TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN
    service_code                public.service_code NOT NULL,
    -- Origin for bidding context (FK defined later)
    origin_address_id           UUID NULL,
    -- Destination for bidding context (FK defined later)
    destination_address_id      UUID NULL,
    -- Required pickup time
    pickup_time                 TIMESTAMPTZ NULL,
    -- Filter for vehicle category
    required_vehicle_category   public.vehicle_category NULL,
    -- Required vehicle/service features
    required_features           JSONB NULL CHECK (
        required_features IS NULL OR jsonb_typeof(required_features) = 'object'
    ),
    -- Additional notes for bidders
    notes                       TEXT NULL,
    -- Optional ceiling price set by user
    passenger_max_acceptable_price NUMERIC(12,2) NULL CHECK (
        passenger_max_acceptable_price IS NULL OR passenger_max_acceptable_price > 0
    ),
    -- Status of the request (ENUM from 001)
    status                      public.bid_request_status NOT NULL DEFAULT 'OPEN',
    created_at                  TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- When the bid request closes automatically
    expires_at                  TIMESTAMPTZ NULL,
    -- Link to the accepted bid (FK defined later)
    winning_bid_id              UUID NULL,

    -- Each booking instance can have at most one active bid request
    CONSTRAINT uq_booking_bid_request_booking UNIQUE (booking_id, booking_created_at) DEFERRABLE INITIALLY DEFERRED  
);
COMMENT ON TABLE public.booking_bid_requests
    IS '[VoyaGo][Booking][Bidding] Represents a request for dynamic price bids associated with a specific booking.';
COMMENT ON COLUMN public.booking_bid_requests.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key and uniqueness.';
COMMENT ON COLUMN public.booking_bid_requests.required_features
    IS '[VoyaGo] Specific features required by the user for this bid request. 
        Example: {"min_rating": 4.5, "luggage_capacity": 3}';
COMMENT ON COLUMN public.booking_bid_requests.passenger_max_acceptable_price
    IS 'Optional maximum price the passenger is willing to pay, used to filter bids.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_booking_bid_requests ON public.booking_bid_requests;
CREATE TRIGGER trg_set_timestamp_on_booking_bid_requests
    BEFORE UPDATE ON public.booking_bid_requests
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Bid Requests
CREATE INDEX IF NOT EXISTS idx_booking_bid_requests_status_expiry
    ON public.booking_bid_requests(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_gin_booking_bid_requests_features
    ON public.booking_bid_requests USING GIN (required_features) WHERE required_features IS NOT NULL;
-- Unique constraint already creates index on (booking_id, booking_created_at)


-------------------------------------------------------------------------------
-- 10.6 Bids (booking_bids)
-------------------------------------------------------------------------------
-- (No changes needed in this table definition)
CREATE TABLE IF NOT EXISTS public.booking_bids (
    bid_id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id              UUID NOT NULL,
    bidder_entity_type      public.bidder_entity_type NOT NULL,
    bidder_entity_id        UUID NOT NULL,
    bid_amount              NUMERIC(12,2) NOT NULL CHECK (bid_amount > 0),
    currency_code           CHAR(3) NOT NULL,
    bid_time                TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    notes                   TEXT NULL,
    proposed_vehicle_id     UUID NULL,
    proposed_driver_id      UUID NULL,
    status                  public.bid_status NOT NULL DEFAULT 'SUBMITTED',
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.booking_bids
    IS '[VoyaGo][Booking][Bidding] Stores individual price bids submitted by 
        drivers or partners in response to a bid request.';
-- Trigger and Indexes remain the same...
DROP TRIGGER IF EXISTS trg_set_timestamp_on_booking_bids ON public.booking_bids;
CREATE TRIGGER trg_set_timestamp_on_booking_bids 
    BEFORE UPDATE ON public.booking_bids FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();
CREATE INDEX IF NOT EXISTS idx_booking_bids_request_status ON public.booking_bids(request_id, status);
CREATE INDEX IF NOT EXISTS idx_booking_bids_bidder ON public.booking_bids(bidder_entity_type, bidder_entity_id);
CREATE INDEX IF NOT EXISTS idx_gin_booking_bids_metadata ON public.booking_bids USING GIN (
    metadata
) WHERE metadata IS NOT NULL;


-- ============================================================================
-- Triggers (Common updated_at triggers) - Already defined above per table
-- ============================================================================


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- booking_bookings -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- booking_bookings -> core_organizations (organization_id -> organization_id) [SET NULL?]
-- booking_bookings -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- booking_bookings -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- booking_bookings -> booking_cancellation_policies (cancellation_policy_id -> policy_id) [SET NULL?]
-- booking_bookings -> lkp_cancellation_reasons (cancellation_reason_code -> reason_code) [SET NULL?]
-- booking_bookings -> core_user_profiles (cancelled_by_actor_id -> user_id) [SET NULL?]
-- booking_bookings -> ??? (applied_promo_code -> promotions_table.promo_code) [SET NULL?] 
    -- Requires Promotions module
--
-- booking_booking_legs -> booking_bookings (booking_created_at, booking_id -> created_at, booking_id) [CASCADE] 
    -- COMPOSITE FK
-- booking_booking_legs -> lkp_service_types (mode -> service_code) [RESTRICT]
-- booking_booking_legs -> core_addresses (origin_address_id -> address_id) [RESTRICT]
-- booking_booking_legs -> core_addresses (destination_address_id -> address_id) [RESTRICT]
-- booking_booking_legs -> fleet_vehicles (assigned_vehicle_id -> vehicle_id) [SET NULL?]
-- booking_booking_legs -> fleet_drivers (assigned_driver_id -> driver_id) [SET NULL?]
-- booking_booking_legs -> fleet_partners (carrier_partner_id -> partner_id) [SET NULL?]
--
-- booking_status_history -> booking_bookings (booking_created_at, booking_id -> created_at, booking_id) [CASCADE] 
    -- COMPOSITE FK
-- booking_status_history -> booking_booking_legs (leg_id -> leg_id) [CASCADE? SET NULL?]
-- booking_status_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- booking_bid_requests -> booking_bookings (booking_created_at, booking_id -> created_at, booking_id) [CASCADE] 
    -- COMPOSITE FK
-- booking_bid_requests -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- booking_bid_requests -> core_addresses (origin_address_id -> address_id) [SET NULL?]
-- booking_bid_requests -> core_addresses (destination_address_id -> address_id) [SET NULL?]
-- booking_bid_requests -> booking_bids (winning_bid_id -> bid_id) [SET NULL]
--
-- booking_bids -> booking_bid_requests (request_id -> request_id) [CASCADE]
-- booking_bids -> ??? (bidder_entity_id -> fleet_drivers.driver_id or fleet_partners.partner_id) [Complex - No DB FK]
-- booking_bids -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- booking_bids -> fleet_vehicles (proposed_vehicle_id -> vehicle_id) [SET NULL?]
-- booking_bids -> fleet_drivers (proposed_driver_id -> driver_id) [SET NULL?]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 010_booking_core.sql (Version 1.3)
-- ============================================================================
