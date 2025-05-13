-- ============================================================================
-- Migration: 006_accommodation_management.sql
-- Description: Creates accommodation module tables: Properties, Room Types,
--              Features, Inventory/Availability, and Booking Details.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-04-20 -- (Assuming original date is intended)
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql (for partner relationship)
-- ============================================================================

BEGIN;

-- Prefix 'acc_' denotes tables related to the Accommodation module.

-------------------------------------------------------------------------------
-- 1. Accommodation Properties (acc_properties)
-- Description: Main table for accommodation properties like hotels, apartments, houses.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.acc_properties (
    property_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID NULL,        -- Managing partner (FK to fleet_partners, defined later)
    name                VARCHAR(200) NOT NULL, -- Name of the property
    property_type       public.PROPERTY_TYPE NOT NULL, -- Type (HOTEL, APARTMENT etc.) (References ENUM from 001)
    description         TEXT NULL,        -- Description of the property
    address_id          UUID NOT NULL,    -- Location address (FK to core_addresses, defined later)
    -- Denormalized from core_addresses.point for performance. Needs sync trigger (See note below).
    location            GEOGRAPHY(POINT, 4326) NOT NULL,
    -- Star rating, if applicable
    star_rating         NUMERIC(2,1) NULL CHECK (star_rating IS NULL OR (star_rating BETWEEN 0.5 AND 5.0)),
    check_in_time       TIME NULL,        -- Standard check-in time (e.g., '14:00')
    check_out_time      TIME NULL,        -- Standard check-out time (e.g., '11:00')
    contact_email       TEXT NULL CHECK (
        contact_email IS NULL OR contact_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
    ),
    contact_phone       TEXT NULL,        -- PII: Sensitive Data! Handle with care.
    images              TEXT[] NULL,      -- Array of URLs pointing to property images (e.g., in object storage)
    policies            JSONB NULL,       -- Property-specific policies (cancellation, child, pet rules etc.)
    status              VARCHAR(20) DEFAULT 'ACTIVE' NOT NULL
    CHECK (status IN ('DRAFT', 'PENDING_APPROVAL', 'ACTIVE', 'INACTIVE')), -- Property listing status
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);

COMMENT ON TABLE public.acc_properties
    IS '[VoyaGo][Accommodation] Core information about accommodation properties (hotels, homes, etc.).';
COMMENT ON COLUMN public.acc_properties.partner_id
    IS 'References the partner managing this property, if applicable.';
COMMENT ON COLUMN public.acc_properties.location
    IS 'Denormalized geographic point from core_addresses for query performance. 
        Synchronization trigger required when core_addresses.point changes.';
COMMENT ON COLUMN public.acc_properties.contact_phone
    IS 'PII - Sensitive Data! Should be handled securely.';
COMMENT ON COLUMN public.acc_properties.images
    IS 'Array of URLs linking to property images stored externally (e.g., object storage).';
COMMENT ON COLUMN public.acc_properties.policies
    IS '[VoyaGo] Property-specific policy overrides or additions as JSONB. 
        Example: {"cancellation_policy_override_id": "uuid", 
        "child_policy": "free_under_6", "pet_policy": "allowed_small_extra_fee"}';

-- Indexes for Properties
CREATE INDEX IF NOT EXISTS idx_acc_properties_partner ON public.acc_properties(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_acc_properties_type ON public.acc_properties(property_type);
CREATE INDEX IF NOT EXISTS idx_acc_properties_status ON public.acc_properties(status);
-- Critical for proximity searches
CREATE INDEX IF NOT EXISTS idx_acc_properties_location ON public.acc_properties USING gist (location);
COMMENT ON INDEX public.idx_acc_properties_location 
    IS '[VoyaGo][Perf] Essential GIST index for location-based searches.';
CREATE INDEX IF NOT EXISTS idx_gin_acc_properties_policies ON public.acc_properties USING gin (policies);


-------------------------------------------------------------------------------
-- 2. Property Features Link Table (acc_property_features_link)
-- Description: Many-to-many link between properties and their features.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.acc_property_features_link (
    property_id UUID NOT NULL, -- FK to acc_properties (defined later, ON DELETE CASCADE)
    feature_code VARCHAR(50) NOT NULL, -- FK to lkp_property_features (defined later, ON DELETE CASCADE)
    PRIMARY KEY (property_id, feature_code)
);
COMMENT ON TABLE public.acc_property_features_link
    IS '[VoyaGo][Accommodation] Links properties to their features 
        (e.g., Pool, Parking) via a many-to-many relationship.';
-- Note: Additional indexes usually not required beyond the composite primary key.


-------------------------------------------------------------------------------
-- 3. Room Types (acc_room_types)
-- Description: Defines specific room/apartment types within a property.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.acc_room_types (
    room_type_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_id     UUID NOT NULL,      -- FK to acc_properties (defined later, ON DELETE CASCADE)
    name            VARCHAR(100) NOT NULL, -- Name of the room type (e.g., 'Standard Double', 'Sea View Suite')
    description     TEXT NULL,
    base_price      NUMERIC(12,2) NULL, -- Default nightly price (can be overridden by inventory calendar)
    currency_code   CHAR(3) NULL,       -- Currency for base_price (FK to lkp_currencies, defined later)
    max_occupancy   SMALLINT NOT NULL CHECK (max_occupancy > 0), -- Maximum number of guests
    bed_details     JSONB NULL,         -- Type and count of beds (e.g., {"king": 1, "sofa_bed": 1})
    room_size_sqm   NUMERIC(6,1) NULL,  -- Room size in square meters
    images          TEXT[] NULL,        -- Array of URLs for room type specific images
    is_active       BOOLEAN DEFAULT TRUE NOT NULL, -- Is this room type currently offered?
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.acc_room_types
    IS '[VoyaGo][Accommodation] Defines the different types of 
        rooms or units available within a property.';
COMMENT ON COLUMN public.acc_room_types.base_price
    IS 'Default base price per night for this room type. 
        Can be overridden daily in acc_inventory_calendar.';
COMMENT ON COLUMN public.acc_room_types.bed_details
    IS '[VoyaGo] Bed types and counts within the room as JSONB. 
        Example: {"double": 1, "single": 2, "crib_available": true}';

-- Indexes for Room Types
CREATE INDEX IF NOT EXISTS idx_acc_room_types_property ON public.acc_room_types(property_id);
CREATE INDEX IF NOT EXISTS idx_acc_room_types_active ON public.acc_room_types(is_active);
CREATE INDEX IF NOT EXISTS idx_gin_acc_room_types_bed_details ON public.acc_room_types USING gin (bed_details);


-------------------------------------------------------------------------------
-- 4. Room Amenities Link Table (acc_room_amenities_link)
-- Description: Many-to-many link between room types and their amenities.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.acc_room_amenities_link (
    room_type_id UUID NOT NULL, -- FK to acc_room_types (defined later, ON DELETE CASCADE)
    amenity_code VARCHAR(50) NOT NULL, -- FK to lkp_room_amenities (defined later, ON DELETE CASCADE)
    PRIMARY KEY (room_type_id, amenity_code)
);
COMMENT ON TABLE public.acc_room_amenities_link
    IS '[VoyaGo][Accommodation] Links room types to their specific amenities 
        (e.g., WiFi, AC) via a many-to-many relationship.';
-- Note: Additional indexes usually not required beyond the composite primary key.


-------------------------------------------------------------------------------
-- 5. Inventory Calendar (acc_inventory_calendar)
-- Description: Tracks daily availability, price overrides, and restrictions per room type.
-- Note: This table is a candidate for partitioning by inventory_date (e.g., monthly/yearly).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.acc_inventory_calendar (
    inventory_id        BIGSERIAL PRIMARY KEY,
    room_type_id        UUID NOT NULL,    -- FK to acc_room_types (defined later, ON DELETE CASCADE)
    inventory_date      DATE NOT NULL,    -- The specific date this record applies to
    -- Number of rooms of this type available on this date
    available_count     SMALLINT NOT NULL CHECK (available_count >= 0),
    price_override      NUMERIC(12,2) NULL, -- Specific price for this date, overrides room_type.base_price if set
    currency_code       CHAR(3) NULL,     -- Currency for price_override (FK defined later)
    -- Minimum stay length starting this date
    min_stay_nights     SMALLINT DEFAULT 1 NOT NULL CHECK (min_stay_nights >= 1),
    -- Maximum stay length
    max_stay_nights     SMALLINT NULL CHECK (max_stay_nights IS NULL OR max_stay_nights >= min_stay_nights),
    closed_for_arrival  BOOLEAN DEFAULT FALSE NOT NULL, -- Is check-in disallowed on this date?
    closed_for_departure BOOLEAN DEFAULT FALSE NOT NULL, -- Is check-out disallowed on this date?
    restrictions        JSONB NULL,       -- Other restrictions (e.g., weekend only)
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,

    -- Ensures only one record per room type per date
    CONSTRAINT uq_acc_inventory_room_date UNIQUE (room_type_id, inventory_date)
);
COMMENT ON TABLE public.acc_inventory_calendar
    IS '[VoyaGo][Accommodation] Tracks daily availability counts, price overrides, 
        and stay restrictions for each room type. Candidate for date-based partitioning.';
COMMENT ON COLUMN public.acc_inventory_calendar.available_count
    IS 'Number of physical rooms of this type available for booking on this specific date.';
COMMENT ON COLUMN public.acc_inventory_calendar.price_override
    IS 'If set, overrides the default base_price from acc_room_types for this specific date.';
COMMENT ON COLUMN public.acc_inventory_calendar.min_stay_nights
    IS 'Minimum number of nights required for a booking starting on this date.';
COMMENT ON COLUMN public.acc_inventory_calendar.restrictions
    IS '[VoyaGo] Additional stay restrictions as JSONB. 
        Example: {"day_of_week_arrival_only": ["Fri", "Sat"]}';

-- Indexes for Inventory Calendar
-- The UNIQUE constraint uq_acc_inventory_room_date implicitly creates an index on (room_type_id, inventory_date).
-- CREATE INDEX IF NOT EXISTS idx_acc_inventory_room_date ON 
    --public.acc_inventory_calendar(room_type_id, inventory_date); 
    -- Redundant due to UNIQUE constraint
CREATE INDEX IF NOT EXISTS idx_acc_inventory_date_available ON public.acc_inventory_calendar(
    inventory_date, available_count
)
WHERE available_count > 0; -- Optimized for finding available rooms on a specific date
COMMENT ON INDEX public.idx_acc_inventory_date_available
IS '[VoyaGo][Perf] Efficiently finds available room types for a given date range.';


-------------------------------------------------------------------------------
-- 6. Accommodation Booking Details (booking_accommodation_details)
-- Description: Stores accommodation-specific details linked to a main booking record.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_accommodation_details (
    -- FK to a central booking table (e.g., booking_bookings, defined later, ON DELETE CASCADE)
    booking_id              UUID PRIMARY KEY,
    property_id             UUID NOT NULL,    -- FK to acc_properties (defined later, ON DELETE RESTRICT recommended)
    room_type_id            UUID NOT NULL,    -- FK to acc_room_types (defined later, ON DELETE RESTRICT recommended)
    check_in_date           DATE NOT NULL,
    check_out_date          DATE NOT NULL,
    -- Can be calculated, but stored for convenience
    number_of_nights        SMALLINT NOT NULL CHECK (number_of_nights > 0),
    -- Number of rooms of this type booked
    number_of_rooms         SMALLINT DEFAULT 1 NOT NULL CHECK (number_of_rooms > 0),
    adult_count             SMALLINT NOT NULL CHECK (adult_count > 0),
    child_count             SMALLINT DEFAULT 0 NOT NULL CHECK (child_count >= 0),
    child_ages              INTEGER[] NULL,   -- Array of children's ages, if relevant for pricing/policy
    special_requests        TEXT NULL,        -- Any special requests from the guest
    estimated_arrival_time  TIME NULL,        -- Guest's estimated time of arrival
    booking_source          VARCHAR(50) NULL, -- Source of the booking (e.g., 'VoyaGoApp', 'ChannelManagerX', 'Direct')
    booking_created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    external_booking_ref    TEXT NULL,        -- Reference ID from an external system (e.g., channel manager booking ID)

    CONSTRAINT chk_booking_acc_dates CHECK (check_out_date > check_in_date),
    CONSTRAINT chk_booking_acc_guest_count CHECK (adult_count + child_count > 0) -- Ensure at least one guest
);
COMMENT ON TABLE public.booking_accommodation_details
IS '[VoyaGo][Booking] Stores details specific to accommodation bookings, extending a central booking record.';
COMMENT ON COLUMN public.booking_accommodation_details.booking_id
IS 'Primary key, also serves as a foreign key to the main bookings table (defined later).';
COMMENT ON COLUMN public.booking_accommodation_details.number_of_nights
IS 'Number of nights calculated between check_in_date and check_out_date. Stored for easy access.';
COMMENT ON COLUMN public.booking_accommodation_details.external_booking_ref
IS 'Reference identifier from an external booking source, like a channel manager or OTA.';
-- Note: created_at/updated_at are typically tracked on the main booking record linked via booking_id.


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for acc_properties
DROP TRIGGER IF EXISTS trg_set_timestamp_on_acc_properties ON public.acc_properties;
CREATE TRIGGER trg_set_timestamp_on_acc_properties
BEFORE UPDATE ON public.acc_properties
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for acc_room_types
DROP TRIGGER IF EXISTS trg_set_timestamp_on_acc_room_types ON public.acc_room_types;
CREATE TRIGGER trg_set_timestamp_on_acc_room_types
BEFORE UPDATE ON public.acc_room_types
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for acc_inventory_calendar
DROP TRIGGER IF EXISTS trg_set_timestamp_on_acc_inventory ON public.acc_inventory_calendar;
CREATE TRIGGER trg_set_timestamp_on_acc_inventory
BEFORE UPDATE ON public.acc_inventory_calendar
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- Note: Actual FK constraints with DEFERRABLE INITIALLY DEFERRED
--       will be added in a later migration (e.g., 025_constraints.sql)
--       to manage dependencies effectively.
-- ============================================================================

-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_properties.partner_id to fleet_partners.partner_id (ON DELETE SET NULL?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_properties.address_id to core_addresses.address_id (ON DELETE RESTRICT?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_property_features_link.property_id to acc_properties.property_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_property_features_link.feature_code to lkp_property_features.feature_code (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_room_types.property_id to acc_properties.property_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_room_types.currency_code to lkp_currencies.currency_code (ON DELETE RESTRICT)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_room_amenities_link.room_type_id to acc_room_types.room_type_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_room_amenities_link.amenity_code to lkp_room_amenities.amenity_code (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_inventory_calendar.room_type_id to acc_room_types.room_type_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from acc_inventory_calendar.currency_code to lkp_currencies.currency_code (ON DELETE RESTRICT)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from booking_accommodation_details.booking_id to booking_bookings.booking_id (ON DELETE CASCADE) 
    -- ASSUMING booking_bookings table exists
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from booking_accommodation_details.property_id to acc_properties.property_id (ON DELETE RESTRICT) 
    -- Don't delete property if bookings exist
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from booking_accommodation_details.room_type_id to acc_room_types.room_type_id (ON DELETE RESTRICT) 
    -- Don't delete room type if bookings exist


COMMIT;

-- ============================================================================
-- End of Migration: 006_accommodation_management.sql
-- ============================================================================
