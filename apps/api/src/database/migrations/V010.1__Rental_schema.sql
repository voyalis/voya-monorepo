-- ============================================================================
-- Migration: 010b_rental_schema.sql (Version 1.2 - Added booking_created_at)
-- Description: VoyaGo - Rental Module Schema: ENUMs, Availability (Partitioned),
--              Pricing Plans, Extras, and Booking Details (adds partition key for FK).
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql, 010_booking_core.sql
-- ============================================================================

BEGIN;

-- Prefix 'rental_' denotes tables specific to the Rental module,
-- except for booking details which extend the booking table.

-------------------------------------------------------------------------------
-- 0. Rental Specific ENUM Types
-------------------------------------------------------------------------------

DO $$
BEGIN
    CREATE TYPE public.rental_availability_status AS ENUM (
        'BOOKED',       -- Reserved for a rental
        'MAINTENANCE',  -- Unavailable due to maintenance
        'BLOCKED',      -- Manually blocked (e.g., relocation, admin)
        'AVAILABLE'     -- Available for booking
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.rental_availability_status
    IS '[VoyaGo][ENUM][Rental] Represents the availability status of a rental vehicle during a time period.';

DO $$
BEGIN
    CREATE TYPE public.rental_pricing_period AS ENUM (
        'HOUR',
        'DAY',
        'WEEK',
        'MONTH'
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.rental_pricing_period
    IS '[VoyaGo][ENUM][Rental] Defines the time unit for rental pricing plans (e.g., price per day).';

DO $$
BEGIN
    CREATE TYPE public.rental_extra_pricing_type AS ENUM (
        'PER_RENTAL', -- Fixed price for the entire rental duration
        'PER_DAY'     -- Price calculated per day of rental
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.rental_extra_pricing_type
    IS '[VoyaGo][ENUM][Rental] Specifies how the price for rental extras (e.g., child seat) is calculated.';

DO $$
BEGIN
    CREATE TYPE public.rental_fuel_policy AS ENUM (
        'FULL_TO_FULL',     -- Pick up full, return full
        'PREPAID_INCLUDED', -- Fuel cost included in rental price (prepaid)
        'PREPAID_SEPARATE', -- Option to prepay fuel separately
        'SAME_LEVEL'        -- Return with the same fuel level as picked up
    );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
COMMENT ON TYPE public.rental_fuel_policy
    IS '[VoyaGo][ENUM][Rental] Defines the fuel policy options for vehicle rentals.';

-------------------------------------------------------------------------------
-- 1. Rental Vehicle Availability (Partitioned)
-- Description: Tracks time slots indicating when vehicles are available, booked,
--              or otherwise unavailable. Partitioned by start_time.
-- Note: Partitions must be created and managed separately. Overlap constraints
--       using GIST exclusion should be added later.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rental_vehicle_availability (
    availability_id             UUID DEFAULT uuid_generate_v4(),
    vehicle_id                  UUID NOT NULL,    -- Vehicle this availability record refers to (FK defined later)
    start_time                  TIMESTAMPTZ NOT NULL, -- Start of the time slot (Partition Key & part of PK)
    end_time                    TIMESTAMPTZ NOT NULL, -- End of the time slot
    status                      public.rental_availability_status NOT NULL, -- Availability status during this slot
    related_rental_booking_id   UUID NULL,        -- Link to the rental booking if status is 'BOOKED' (FK defined later)
    -- Link to maintenance record if status is 'MAINTENANCE' (FK defined later)
    related_maintenance_id      BIGINT NULL,
    notes                       TEXT NULL,        -- Notes regarding this specific slot (e.g., reason for block)
    created_at                  TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,

    CONSTRAINT chk_rental_availability_times CHECK (end_time > start_time),
    -- Overlap prevention constraint to be added later (e.g., in Migration 025)
    -- CONSTRAINT exclude_overlapping_availability EXCLUDE USING GIST 
        --(vehicle_id WITH =, tsrange(start_time, end_time, '()') WITH &&) WHERE (status != 'AVAILABLE'),
    PRIMARY KEY (start_time, availability_id) -- Composite PK including partition key

) PARTITION BY RANGE (start_time);

COMMENT ON TABLE public.rental_vehicle_availability
    IS '[VoyaGo][Rental] Tracks availability slots for rental vehicles (Partitioned by start_time). 
        Requires GIST exclusion constraints later to prevent overlaps.';
COMMENT ON COLUMN public.rental_vehicle_availability.start_time
    IS 'Start time of the availability/block slot. Also serves as the partition key.';
COMMENT ON COLUMN public.rental_vehicle_availability.related_rental_booking_id
    IS 'Reference to the booking_rental_details record if this slot represents a booking.';
COMMENT ON COLUMN public.rental_vehicle_availability.related_maintenance_id
    IS 'Reference to the fleet_vehicle_maintenance record if the vehicle is unavailable due to maintenance.';
COMMENT ON CONSTRAINT rental_vehicle_availability_pkey ON public.rental_vehicle_availability
    IS 'Composite primary key including the partition key (start_time).';

-- Indexes for Availability (Defined on main table, propagated to partitions)
-- Crucial for finding availability for a vehicle in a time range
CREATE INDEX IF NOT EXISTS idx_rental_avail_vehicle_time
    ON public.rental_vehicle_availability(vehicle_id, start_time, end_time);
CREATE INDEX IF NOT EXISTS idx_rental_avail_status
    ON public.rental_vehicle_availability(status);
CREATE INDEX IF NOT EXISTS idx_rental_avail_rental_booking
    ON public.rental_vehicle_availability(related_rental_booking_id)
    WHERE related_rental_booking_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 2. Rental Pricing Plans
-- Description: Defines pricing structures and conditions for vehicle rentals.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rental_pricing_plans (
    plan_id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Name of the pricing plan (e.g., "Weekend Special", "Standard Daily Rate")
    name                    VARCHAR(150) NOT NULL,
    -- Partner offering this plan (NULL for platform default) (FK defined later)
    partner_id              UUID NULL,
    -- Specific vehicle type this applies to (FK defined later)
    vehicle_type_code       VARCHAR(50) NULL,
    -- Or applies to a whole category (FK defined later)
    vehicle_category        public.vehicle_category NULL,
    -- Pricing unit (HOUR, DAY, etc.)
    period_unit             public.rental_pricing_period NOT NULL,
    -- Price per period_unit
    rate                    NUMERIC(10, 2) NOT NULL CHECK (rate >= 0),
    -- Currency for the rate (FK defined later)
    currency_code           CHAR(3) NOT NULL,
    -- Kilometers included per period_unit (0 = unlimited or not applicable)
    km_included             INTEGER DEFAULT 0 NOT NULL CHECK (km_included >= 0),
    -- Cost per km over the included limit
    km_overcharge_rate      NUMERIC(8, 2) NULL CHECK (km_overcharge_rate IS NULL OR km_overcharge_rate >= 0),
    -- Security deposit required
    deposit_amount          NUMERIC(10, 2) NULL CHECK (deposit_amount IS NULL OR deposit_amount >= 0),
    -- Fuel policy (ENUM)
    fuel_policy             public.rental_fuel_policy NOT NULL DEFAULT 'FULL_TO_FULL',
    -- Details of included insurance
    insurance_policy_details JSONB NULL CHECK (
        insurance_policy_details IS NULL OR jsonb_typeof(insurance_policy_details) = 'object'
    ),
    -- Minimum rental duration (e.g., '3 hours', '1 day')
    min_rental_duration     INTERVAL NULL,
    -- Maximum rental duration
    max_rental_duration     INTERVAL NULL,
    -- Date the plan becomes valid
    valid_from              DATE NULL,
    -- Date the plan expires
    valid_to                DATE NULL,
    is_active               BOOLEAN DEFAULT TRUE NOT NULL,
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,

    CONSTRAINT chk_rental_plan_dates CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_from <= valid_to),
    CONSTRAINT chk_rental_plan_duration CHECK (
        min_rental_duration IS NULL
        OR max_rental_duration IS NULL
        OR min_rental_duration <= max_rental_duration
    ),
    -- Ensure plan targets either type or category or is general
    CONSTRAINT chk_rental_plan_target CHECK (
        (vehicle_type_code IS NOT NULL AND vehicle_category IS NULL)
        OR (vehicle_type_code IS NULL AND vehicle_category IS NOT NULL)
        OR (vehicle_type_code IS NULL AND vehicle_category IS NULL)
    )
);
COMMENT ON TABLE public.rental_pricing_plans
    IS '[VoyaGo][Rental] Defines pricing plans and associated conditions for vehicle rentals.';
COMMENT ON COLUMN public.rental_pricing_plans.km_included
    IS 'Kilometers included per pricing period (e.g., per day). 0 typically means unlimited or pay-per-km.';
COMMENT ON COLUMN public.rental_pricing_plans.insurance_policy_details
    IS '[VoyaGo] Details of the insurance included in the plan. 
        Example: {"type": "Standard CDW", "excess_amount": 1000, "theft_protection_included": true}';
COMMENT ON CONSTRAINT chk_rental_plan_target ON public.rental_pricing_plans
    IS 'Ensures a pricing plan targets either a specific vehicle type, 
        a vehicle category, or neither (general plan), but not both.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_rental_pricing_plans ON public.rental_pricing_plans;
CREATE TRIGGER trg_set_timestamp_on_rental_pricing_plans
    BEFORE UPDATE ON public.rental_pricing_plans
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Pricing Plans
CREATE INDEX IF NOT EXISTS idx_rental_plans_partner
    ON public.rental_pricing_plans(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rental_plans_type
    ON public.rental_pricing_plans(vehicle_type_code) WHERE vehicle_type_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rental_plans_category
    ON public.rental_pricing_plans(vehicle_category) WHERE vehicle_category IS NOT NULL;
-- Find active plans for a date range
CREATE INDEX IF NOT EXISTS idx_rental_plans_active_valid
    ON public.rental_pricing_plans(is_active, valid_from, valid_to);


-------------------------------------------------------------------------------
-- 3. Rental Extras
-- Description: Defines optional extras available for rent (e.g., child seat, GPS).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rental_extras (
    extra_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Partner offering this extra (NULL for platform default) (FK defined later)
    partner_id      UUID NULL,
    -- Unique code for the extra (e.g., 'CHILD_SEAT_0_1')
    code            VARCHAR(50) NOT NULL UNIQUE,
    name            VARCHAR(100) NOT NULL, -- Display name
    description     TEXT NULL,
    -- How the extra is priced (PER_RENTAL, PER_DAY)
    pricing_type    public.rental_extra_pricing_type NOT NULL,
    price           NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    -- Currency for the price (FK defined later)
    currency_code   CHAR(3) NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.rental_extras
    IS '[VoyaGo][Rental] Defines optional extras that can be added to 
        a vehicle rental (e.g., child seat, GPS, additional driver).';
COMMENT ON COLUMN public.rental_extras.code
    IS 'Unique code identifying the rental extra.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_rental_extras ON public.rental_extras;
CREATE TRIGGER trg_set_timestamp_on_rental_extras
    BEFORE UPDATE ON public.rental_extras
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Extras
CREATE INDEX IF NOT EXISTS idx_rental_extras_partner
    ON public.rental_extras(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_rental_extras_active
    ON public.rental_extras(is_active);


-------------------------------------------------------------------------------
-- 4. Booking Rental Details - ** booking_created_at ADDED **
-- Description: Stores rental-specific details associated with a booking record.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_rental_details (
    -- PK & Logical FK to booking_bookings (Composite FK defined later)
    booking_id                  UUID PRIMARY KEY,
    booking_created_at          TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN
    -- Rented vehicle (FK defined later)
    vehicle_id                  UUID NOT NULL,
    -- Applied pricing plan (FK defined later)
    pricing_plan_id             UUID NOT NULL,
    -- Actual or scheduled pickup time
    pickup_time                 TIMESTAMPTZ NOT NULL,
    -- Actual or scheduled dropoff time
    dropoff_time                TIMESTAMPTZ NOT NULL,
    -- Pickup location (FK defined later)
    pickup_location_id          UUID NOT NULL,
    -- Dropoff location (FK defined later)
    dropoff_location_id         UUID NOT NULL,
    -- Odometer readings
    pickup_odometer_reading     INTEGER NULL CHECK (pickup_odometer_reading IS NULL OR pickup_odometer_reading >= 0),
    dropoff_odometer_reading    INTEGER NULL CHECK (dropoff_odometer_reading IS NULL OR dropoff_odometer_reading >= 0),
    -- Fuel levels
    pickup_fuel_level_pct       SMALLINT NULL CHECK (
        pickup_fuel_level_pct IS NULL OR (pickup_fuel_level_pct BETWEEN 0 AND 100)
    ),
    dropoff_fuel_level_pct      SMALLINT NULL CHECK (
        dropoff_fuel_level_pct IS NULL OR (dropoff_fuel_level_pct BETWEEN 0 AND 100)
    ),
    -- Details at time of booking
    applied_pricing_plan_details JSONB NULL CHECK (
        applied_pricing_plan_details IS NULL OR jsonb_typeof(applied_pricing_plan_details) = 'object'
    ),
    selected_extras             JSONB NULL CHECK (selected_extras IS NULL OR jsonb_typeof(selected_extras) = 'array'),
    insurance_details           JSONB NULL CHECK (
        insurance_details IS NULL OR jsonb_typeof(insurance_details) = 'object'
    ),
    -- Pricing
    total_rental_price          NUMERIC(12, 2) NULL CHECK (total_rental_price IS NULL OR total_rental_price >= 0),
    currency_code               CHAR(3) NULL,     -- Currency for total_rental_price (FK defined later)
    -- Guest counts
    adult_count                 SMALLINT NOT NULL CHECK (adult_count > 0),
    child_count                 SMALLINT DEFAULT 0 NOT NULL CHECK (child_count >= 0),
    child_ages                  INTEGER[] NULL,

    CONSTRAINT chk_rental_booking_times CHECK (dropoff_time > pickup_time),
    CONSTRAINT chk_rental_booking_odometer CHECK (
        pickup_odometer_reading IS NULL
        OR dropoff_odometer_reading IS NULL
        OR dropoff_odometer_reading >= pickup_odometer_reading
    ),
    CONSTRAINT chk_rental_booking_guest_count CHECK (adult_count + child_count > 0)
);
COMMENT ON TABLE public.booking_rental_details
    IS '[VoyaGo][Booking][Rental] Stores specific details for vehicle rental bookings, 
        extending the main booking_bookings table.';
COMMENT ON COLUMN public.booking_rental_details.booking_id
    IS 'Primary key, also the logical foreign key referencing the associated record in booking_bookings.';
COMMENT ON COLUMN public.booking_rental_details.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key.';
COMMENT ON COLUMN public.booking_rental_details.applied_pricing_plan_details
    IS '[VoyaGo] Snapshot (as JSONB) of the rental_pricing_plans record applicable 
        at the time of booking, ensuring historical price accuracy.';
COMMENT ON COLUMN public.booking_rental_details.selected_extras
    IS '[VoyaGo] Array (as JSONB) detailing selected rental extras. 
        Example: [{"extra_code": "CHILD_SEAT_0_1", "quantity": 1, "price_at_booking": 10.00, "currency": "EUR"}]';
COMMENT ON COLUMN public.booking_rental_details.total_rental_price
    IS 'Calculated price for the core rental period and selected extras,
        excluding platform fees or taxes which are handled in the main booking record.';

-- Indexes for Booking Rental Details
CREATE INDEX IF NOT EXISTS idx_booking_rental_details_vehicle ON public.booking_rental_details(vehicle_id);
CREATE INDEX IF NOT EXISTS idx_booking_rental_details_plan ON public.booking_rental_details(pricing_plan_id);
CREATE INDEX IF NOT EXISTS idx_booking_rental_details_pickup_time ON public.booking_rental_details(pickup_time);
CREATE INDEX IF NOT EXISTS idx_booking_rental_details_dropoff_time ON public.booking_rental_details(dropoff_time);
-- Add index including the new booking_created_at for FK joining
CREATE INDEX IF NOT EXISTS idx_booking_rental_details_booking
    ON public.booking_rental_details(booking_id, booking_created_at); -- Index for Composite FK


-------------------------------------------------------------------------------
-- 5. Rental Reservation Extras (M2M Link - Optional Alternative)
-------------------------------------------------------------------------------
/* -- Uncomment if choosing M2M table over JSONB for extras
CREATE TABLE IF NOT EXISTS public.rental_reservation_extras (
    rental_booking_id   UUID NOT NULL,
    extra_id            UUID NOT NULL,
    quantity            SMALLINT DEFAULT 1 NOT NULL CHECK (quantity > 0),
    price_at_booking    NUMERIC(10, 2) NOT NULL,
    currency_code       CHAR(3) NOT NULL,
    PRIMARY KEY (rental_booking_id, extra_id)
);
COMMENT ON TABLE public.rental_reservation_extras
    IS '[VoyaGo][Rental] Links rental bookings to selected extras (M2M). 
    Alternative to JSONB approach in booking_rental_details.';
CREATE INDEX IF NOT EXISTS idx_rental_res_extras_extra
    ON public.rental_reservation_extras(extra_id);
*/


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================
DROP TRIGGER IF EXISTS trg_set_timestamp_on_rental_pricing_plans ON public.rental_pricing_plans;
CREATE TRIGGER trg_set_timestamp_on_rental_pricing_plans
    BEFORE UPDATE ON public.rental_pricing_plans
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

DROP TRIGGER IF EXISTS trg_set_timestamp_on_rental_extras ON public.rental_extras;
CREATE TRIGGER trg_set_timestamp_on_rental_extras
    BEFORE UPDATE ON public.rental_extras
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- rental_vehicle_availability -> fleet_vehicles (vehicle_id -> vehicle_id) [CASCADE?]
-- rental_vehicle_availability -> booking_rental_details (related_rental_booking_id -> booking_id) [SET NULL?]
-- rental_vehicle_availability -> fleet_vehicle_maintenance (related_maintenance_id -> maintenance_id) [SET NULL?]
--
-- rental_pricing_plans -> fleet_partners (partner_id -> partner_id) [CASCADE?]
-- rental_pricing_plans -> lkp_vehicle_types (vehicle_type_code -> type_code) [RESTRICT?]
-- rental_pricing_plans -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- rental_pricing_plans -> ??? (vehicle_category) [No FK - ENUM]
--
-- rental_extras -> fleet_partners (partner_id -> partner_id) [CASCADE?]
-- rental_extras -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- booking_rental_details -> booking_bookings (booking_created_at, booking_id -> 
    --created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- booking_rental_details -> fleet_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- booking_rental_details -> rental_pricing_plans (pricing_plan_id -> plan_id) [RESTRICT]
-- booking_rental_details -> core_addresses (pickup_location_id -> address_id) [RESTRICT]
-- booking_rental_details -> core_addresses (dropoff_location_id -> address_id) [RESTRICT]
-- booking_rental_details -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- rental_reservation_extras (if used) -> booking_rental_details (rental_booking_id -> booking_id) [CASCADE]
-- rental_reservation_extras (if used) -> rental_extras (extra_id -> extra_id) [RESTRICT]
-- rental_reservation_extras (if used) -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 010b_rental_schema.sql (Version 1.2)
-- ============================================================================
