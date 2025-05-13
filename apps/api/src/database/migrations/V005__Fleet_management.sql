-- ============================================================================
-- Migration: 005_fleet_management.sql
-- Description: Creates fleet management tables: Partners, Drivers, Vehicles,
--              versioned Documents, and Maintenance records.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-04-19 -- (Assuming original date is intended)
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Partners (fleet_partners)
-- Description: Represents service provider partners (companies or individuals).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_partners (
    partner_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id         UUID NULL,        -- Optional link to core_organizations (FK defined below)
    -- Partner display name (Consider removing UNIQUE constraint if non-unique names are allowed)
    name                    VARCHAR(150) NOT NULL,
    legal_name              VARCHAR(200) NULL, -- Official legal name of the entity
    partner_type            public.PARTNER_TYPE NOT NULL, -- References ENUM from 001
    status                  VARCHAR(30) NOT NULL DEFAULT 'PENDING_APPROVAL'
    -- Current status
    CHECK (status IN ('PENDING_APPROVAL', 'ACTIVE', 'INACTIVE', 'SUSPENDED', 'REJECTED', 'ONBOARDING')),
    onboarding_step         VARCHAR(50) NULL,   -- Current step in the partner onboarding process
    approved_at             TIMESTAMPTZ NULL,   -- Timestamp when the partner was approved
    approved_by             UUID NULL,        -- User who approved the partner (FK defined below)
    -- Primary email (unique)
    primary_contact_email   TEXT UNIQUE CHECK (
        primary_contact_email IS NULL OR primary_contact_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
    ),
    -- PII: Sensitive Data! Handle with care (encryption/masking recommended).
    primary_contact_phone   TEXT NULL,
    address_id              UUID NULL,          -- FK to core_addresses (defined below)
    tax_id                  VARCHAR(50) NULL,
    tax_office              VARCHAR(100) NULL,
    -- Reference to vault storing sensitive bank details (e.g., IBAN) for payouts
    bank_details_vault_ref  TEXT NULL,
    payout_preferences      JSONB NULL,         -- Payout settings (frequency, minimum amount, etc.)
    agreement_details       JSONB NULL,         -- Details like contract number, commission rates
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
    -- Consider adding a UNIQUE constraint on `name` if partner names must be unique.
    -- CONSTRAINT uq_fleet_partners_name UNIQUE (name)
);

COMMENT ON TABLE public.fleet_partners
    IS '[VoyaGo][Fleet] Represents service provider partners (companies or individual carriers).';
COMMENT ON COLUMN public.fleet_partners.organization_id
    IS 'Optional link to a corresponding entry in core_organizations if the partner is structured that way.';
COMMENT ON COLUMN public.fleet_partners.name
    IS 'Display name of the partner. Consider if this needs to be unique.';
COMMENT ON COLUMN public.fleet_partners.primary_contact_phone
    IS 'PII - Sensitive Data! Must be handled securely (e.g., masked or encrypted at application level).';
COMMENT ON COLUMN public.fleet_partners.bank_details_vault_ref
    IS '[VoyaGo][Security] Vault reference storing sensitive bank account details for 
        payouts instead of storing IBAN directly.';
COMMENT ON COLUMN public.fleet_partners.payout_preferences
    IS '[VoyaGo] Stores payout preferences. 
        Example: {"payout_schedule": "WEEKLY", "min_payout_amount": 100, "preferred_method": "BANK_TRANSFER"}';
COMMENT ON COLUMN public.fleet_partners.agreement_details
    IS '[VoyaGo] Stores agreement details. 
        Example: {"agreement_no": "AGR-123", "commission_rate_pct": 15.5, "valid_until": "2026-12-31"}';


-- Indexes for Partners
CREATE INDEX IF NOT EXISTS idx_fleet_partners_organization ON public.fleet_partners(
    organization_id
) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fleet_partners_type ON public.fleet_partners(partner_type);
CREATE INDEX IF NOT EXISTS idx_fleet_partners_status ON public.fleet_partners(status);
CREATE INDEX IF NOT EXISTS idx_gin_fleet_partners_payout_prefs ON public.fleet_partners USING gin (payout_preferences);
CREATE INDEX IF NOT EXISTS idx_gin_fleet_partners_agreement ON public.fleet_partners USING gin (agreement_details);


-- ============================================================================
-- 2. Drivers (fleet_drivers)
-- Description: Profiles and operational status of drivers on the platform.
--              Extends core_user_profiles.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_drivers (
    driver_id               UUID PRIMARY KEY, -- FK to core_user_profiles (FK defined below)
    assigned_partner_id     UUID NULL,        -- FK to fleet_partners (FK defined below). NULL if independent driver.
    -- PII: Sensitive Data! MUST be encrypted/masked. Uniqueness check might need app-level handling if encrypted.
    license_number          TEXT UNIQUE,
    license_expiry          DATE NULL,
    avg_rating              NUMERIC(3, 2) DEFAULT 0.00 CHECK (avg_rating BETWEEN 0 AND 5), -- Calculated average rating
    status                  public.DRIVER_STATUS NOT NULL DEFAULT 'PENDING_VERIFICATION', -- References ENUM from 001
    -- FK to fleet_vehicles (FK defined below). Vehicle currently in use by driver.
    current_vehicle_id      UUID NULL,
    last_location           GEOGRAPHY(POINT, 4326) NULL, -- Last known geographic location
    last_location_update    TIMESTAMPTZ NULL,
    -- Overall driver verification status (based on documents etc.)
    verification_status     public.DOCUMENT_STATUS DEFAULT 'PENDING_VERIFICATION' NOT NULL,
    onboarding_status       VARCHAR(30) DEFAULT 'PENDING_DOCUMENTS' NOT NULL
    CHECK (
        onboarding_status IN ('PENDING_DOCUMENTS', 'PENDING_TRAINING', 'PENDING_APPROVAL', 'ACTIVE', 'REJECTED')
    ),
    training_completed_at   TIMESTAMPTZ NULL,
    background_check_status VARCHAR(20) DEFAULT 'PENDING' NOT NULL
    CHECK (background_check_status IN ('PENDING', 'IN_PROGRESS', 'PASSED', 'FAILED', 'NOT_REQUIRED')),
    payout_preferences      JSONB NULL,       -- Payout details (e.g., bank ref, email)
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
    -- is_deleted status is managed via the corresponding core_user_profiles record.
);

COMMENT ON TABLE public.fleet_drivers
    IS '[VoyaGo][Fleet] Stores operational information for drivers, extending core_user_profiles.';
COMMENT ON COLUMN public.fleet_drivers.driver_id
    IS 'References the user_id in core_user_profiles.';
COMMENT ON COLUMN public.fleet_drivers.license_number
    IS 'PII - Sensitive Data! Must be encrypted/masked at application or DB level (e.g., pgsodium). 
        Uniqueness needs careful handling if encrypted.';
COMMENT ON COLUMN public.fleet_drivers.avg_rating
    IS 'Calculated average driver rating (updated periodically or via triggers/functions).';
COMMENT ON COLUMN public.fleet_drivers.current_vehicle_id
    IS 'The vehicle the driver is currently assigned to or using.';
COMMENT ON COLUMN public.fleet_drivers.payout_preferences
    IS '[VoyaGo] Driver payout preferences. 
        Example: {"bank_account_vault_ref": "vault:driver-iban-123", "payment_email": "driver@example.com"}';

-- Indexes for Drivers
CREATE INDEX IF NOT EXISTS idx_fleet_drivers_status ON public.fleet_drivers(status);
CREATE INDEX IF NOT EXISTS idx_fleet_drivers_partner ON public.fleet_drivers(
    assigned_partner_id
) WHERE assigned_partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fleet_drivers_location ON public.fleet_drivers USING gist(last_location)
WHERE last_location IS NOT NULL AND status = 'ACTIVE'; -- Spatial index for finding nearby active drivers
COMMENT ON INDEX public.idx_fleet_drivers_location 
    IS '[VoyaGo][Perf] Optimized spatial index for finding active drivers nearby.';
CREATE INDEX IF NOT EXISTS idx_fleet_drivers_vehicle ON public.fleet_drivers(
    current_vehicle_id
) WHERE current_vehicle_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fleet_drivers_onboarding ON public.fleet_drivers(onboarding_status);
CREATE INDEX IF NOT EXISTS idx_gin_fleet_drivers_payout_prefs ON public.fleet_drivers USING gin (payout_preferences);


-- ============================================================================
-- 3. Vehicles (fleet_vehicles)
-- Description: Details of vehicles available on the platform (owned or partner).
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_vehicles (
    vehicle_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id              UUID NULL,        -- Owning/Operating partner (FK defined below)
    vehicle_type_code       VARCHAR(50) NOT NULL, -- FK to lkp_vehicle_types (FK defined below)
    license_plate           VARCHAR(20) NOT NULL UNIQUE, -- Vehicle license plate (unique)
    vin                     VARCHAR(17) UNIQUE NULL, -- Vehicle Identification Number (unique if present)
    make                    VARCHAR(50) NULL, -- Manufacturer (e.g., Toyota)
    model                   VARCHAR(50) NULL, -- Model (e.g., Corolla)
    year                    SMALLINT NULL CHECK (
        year IS NULL OR (year > 1980 AND year <= date_part('year', current_date) + 1)
    ),
    color                   VARCHAR(30) NULL,
    capacity                SMALLINT NOT NULL CHECK (capacity > 0), -- Passenger or Cargo capacity based on type
    features                JSONB NULL,       -- Additional features (e.g., WiFi, Child Seat)
    status                  public.VEHICLE_STATUS NOT NULL DEFAULT 'INACTIVE', -- References ENUM from 001
    current_location        GEOGRAPHY(POINT, 4326) NULL, -- Current or last known location
    last_seen_at            TIMESTAMPTZ NULL, -- Timestamp of last location update
    assigned_driver_id      UUID NULL,        -- Driver currently assigned to this vehicle (FK defined below)
    maintenance_status      VARCHAR(20) DEFAULT 'OK' NOT NULL
    CHECK (maintenance_status IN ('OK', 'DUE', 'OVERDUE', 'IN_SHOP')), -- Maintenance indicator
    last_maintenance_date   DATE NULL,
    insurance_expiry        DATE NULL,        -- Expiry date of primary insurance
    inspection_expiry       DATE NULL,        -- Expiry date of mandatory inspection
    -- Last known odometer reading
    current_km_reading      INTEGER NULL CHECK (current_km_reading IS NULL OR current_km_reading >= 0),
    telematics_device_id    TEXT NULL UNIQUE, -- Unique ID of the installed telematics device, if any
    registration_details    JSONB NULL,       -- Owner info, registration date, etc.
    is_active               BOOLEAN DEFAULT TRUE NOT NULL, -- Is the vehicle active on the platform?
    is_deleted              BOOLEAN DEFAULT FALSE NOT NULL, -- Soft delete flag
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
);

COMMENT ON TABLE public.fleet_vehicles
    IS '[VoyaGo][Fleet] Stores details, status, and operational information for vehicles in the fleet.';
COMMENT ON COLUMN public.fleet_vehicles.capacity
    IS 'Passenger or cargo capacity depending on the vehicle type.';
COMMENT ON COLUMN public.fleet_vehicles.features
    IS '[VoyaGo] Vehicle-specific features. 
        Example: {"wifi": true, "child_seat": true, "pet_friendly": false, "wheelchair_accessible": true}';
COMMENT ON COLUMN public.fleet_vehicles.current_km_reading
    IS 'Last reported odometer reading for the vehicle.';
COMMENT ON COLUMN public.fleet_vehicles.telematics_device_id
    IS 'Unique identifier for the telematics/GPS device installed in the vehicle, if applicable.';
COMMENT ON COLUMN public.fleet_vehicles.registration_details
    IS '[VoyaGo] Additional registration details. 
        Example: {"registered_owner": "Fleet Partner Inc.", "registration_date": "2023-01-15"}';


-- Indexes for Vehicles
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_partner ON public.fleet_vehicles(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_driver ON public.fleet_vehicles(
    assigned_driver_id
) WHERE assigned_driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_loc_status_type ON public.fleet_vehicles USING gist (current_location)
-- Optimized for finding nearby available vehicles
WHERE status = 'AVAILABLE' AND is_active = TRUE AND is_deleted = FALSE;
COMMENT ON INDEX public.idx_fleet_vehicles_loc_status_type 
    IS '[VoyaGo][Perf] Optimized spatial index for finding nearby, available, active vehicles.';
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_status ON public.fleet_vehicles(status);
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_type ON public.fleet_vehicles(vehicle_type_code);
-- Index for license plate lookups (supports LIKE 'prefix%')
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_plate ON public.fleet_vehicles(license_plate text_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_fleet_vehicles_telematics ON public.fleet_vehicles(
    telematics_device_id
) WHERE telematics_device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_fleet_vehicles_features ON public.fleet_vehicles USING gin (features);
COMMENT ON INDEX public.idx_gin_fleet_vehicles_features
IS '[VoyaGo][Perf] GIN index for efficient searching within the JSONB vehicle features.';


-- ============================================================================
-- 4. Driver Documents (fleet_driver_documents)
-- Description: Stores driver documents with versioning and status tracking.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_driver_documents (
    document_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id           UUID NOT NULL,        -- FK to fleet_drivers (defined below)
    document_type_code  VARCHAR(50) NOT NULL, -- FK to lkp_document_types (defined below)
    version             SMALLINT DEFAULT 1 NOT NULL, -- Document version number
    file_storage_path   TEXT NOT NULL,        -- Path/reference to the file in storage (e.g., Supabase Storage)
    issue_date          DATE NULL,            -- Date the document was issued
    expiry_date         DATE NULL,            -- Date the document expires
    verification_status public.DOCUMENT_STATUS DEFAULT 'UPLOADED' NOT NULL, -- References ENUM from 001
    verified_by         UUID NULL,            -- User who verified the document (FK defined below)
    verified_at         TIMESTAMPTZ NULL,
    rejection_reason    TEXT NULL,            -- Reason if verification_status is 'REJECTED'
    notes               TEXT NULL,            -- Additional notes by verifier or user
    uploaded_by         UUID NULL,            -- User who uploaded the document (FK defined below)
    uploaded_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,
    -- Is this the currently active version of this document type for this driver?
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,

    CONSTRAINT uq_fleet_driver_doc_type_version UNIQUE (
        driver_id, document_type_code, version
    ) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_fleet_driver_doc_dates CHECK (expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date)
);
COMMENT ON TABLE public.fleet_driver_documents
IS '[VoyaGo][Fleet] Stores documents related to drivers (License, SRC, etc.) with version history.';
COMMENT ON COLUMN public.fleet_driver_documents.is_active
    IS 'Indicates if this is the current, valid version of the document. 
        Should be FALSE for older versions or replaced documents.';

-- Partial unique index to ensure only one document of a type is active per driver
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_driver_doc_type_active ON public.fleet_driver_documents (
    driver_id, document_type_code
)
WHERE is_active IS TRUE;
COMMENT ON INDEX public.uidx_fleet_driver_doc_type_active
IS '[VoyaGo][Logic] Ensures only one document instance per type can be marked as active for a given driver.';

-- Other Indexes for Driver Documents
-- Useful for finding latest/active docs
CREATE INDEX IF NOT EXISTS idx_fleet_driver_docs_driver_type ON public.fleet_driver_documents(
    driver_id, document_type_code, is_active, version DESC
);
-- Find expiring active docs
CREATE INDEX IF NOT EXISTS idx_fleet_driver_docs_expiry ON public.fleet_driver_documents(
    expiry_date
) WHERE expiry_date IS NOT NULL
AND is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_fleet_driver_docs_status ON public.fleet_driver_documents(
    verification_status, is_active
);


-- ============================================================================
-- 5. Vehicle Documents (fleet_vehicle_documents)
-- Description: Stores vehicle documents with versioning and status tracking.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_vehicle_documents (
    document_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id          UUID NOT NULL,        -- FK to fleet_vehicles (defined below)
    document_type_code  VARCHAR(50) NOT NULL, -- FK to lkp_document_types (defined below)
    version             SMALLINT DEFAULT 1 NOT NULL,
    file_storage_path   TEXT NOT NULL,
    issue_date          DATE NULL,
    expiry_date         DATE NULL,
    verification_status public.DOCUMENT_STATUS DEFAULT 'UPLOADED' NOT NULL,
    verified_by         UUID NULL,            -- FK to core_user_profiles (defined below)
    verified_at         TIMESTAMPTZ NULL,
    rejection_reason    TEXT NULL,
    notes               TEXT NULL,
    uploaded_by         UUID NULL,            -- FK to core_user_profiles (defined below)
    uploaded_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,

    CONSTRAINT uq_fleet_vehicle_doc_type_version UNIQUE (
        vehicle_id, document_type_code, version
    ) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_fleet_vehicle_doc_dates CHECK (
        expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date
    )
);
COMMENT ON TABLE public.fleet_vehicle_documents
    IS '[VoyaGo][Fleet] Stores documents related to vehicles 
        (Registration, Insurance, Inspection, etc.) with version history.';
COMMENT ON COLUMN public.fleet_vehicle_documents.is_active
        IS 'Indicates if this is the current, valid version of the document for the vehicle.';

-- Partial unique index to ensure only one document of a type is active per vehicle
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_vehicle_doc_type_active ON public.fleet_vehicle_documents (
    vehicle_id, document_type_code
)
WHERE is_active IS TRUE;
COMMENT ON INDEX public.uidx_fleet_vehicle_doc_type_active
    IS '[VoyaGo][Logic] Ensures only one document instance per type can be 
        marked as active for a given vehicle.';

-- Other Indexes for Vehicle Documents
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_docs_vehicle_type ON public.fleet_vehicle_documents(
    vehicle_id, document_type_code, is_active, version DESC
);
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_docs_expiry ON public.fleet_vehicle_documents(
    expiry_date
) WHERE expiry_date IS NOT NULL
AND is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_docs_status ON public.fleet_vehicle_documents(
    verification_status, is_active
);


-- ============================================================================
-- 6. Partner Documents (fleet_partner_documents)
-- Description: Stores partner documents with versioning and status tracking.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_partner_documents (
    document_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id          UUID NOT NULL,        -- FK to fleet_partners (defined below)
    document_type_code  VARCHAR(50) NOT NULL, -- FK to lkp_document_types (defined below)
    version             SMALLINT DEFAULT 1 NOT NULL,
    file_storage_path   TEXT NOT NULL,
    issue_date          DATE NULL,
    expiry_date         DATE NULL,
    verification_status public.DOCUMENT_STATUS DEFAULT 'UPLOADED' NOT NULL,
    verified_by         UUID NULL,            -- FK to core_user_profiles (defined below)
    verified_at         TIMESTAMPTZ NULL,
    rejection_reason    TEXT NULL,
    notes               TEXT NULL,
    uploaded_by         UUID NULL,            -- FK to core_user_profiles (defined below)
    uploaded_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,

    CONSTRAINT uq_fleet_partner_doc_type_version UNIQUE (
        partner_id, document_type_code, version
    ) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT chk_fleet_partner_doc_dates CHECK (
        expiry_date IS NULL OR issue_date IS NULL OR expiry_date >= issue_date
    )
);
COMMENT ON TABLE public.fleet_partner_documents
IS '[VoyaGo][Fleet] Stores documents related to partners (Agreement, Tax Cert, etc.) with version history.';
COMMENT ON COLUMN public.fleet_partner_documents.is_active
IS 'Indicates if this is the current, valid version of the document for the partner.';

-- Partial unique index to ensure only one document of a type is active per partner
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_partner_doc_type_active ON public.fleet_partner_documents (
    partner_id, document_type_code
)
WHERE is_active IS TRUE;
COMMENT ON INDEX public.uidx_fleet_partner_doc_type_active
IS '[VoyaGo][Logic] Ensures only one document instance per type can be marked as active for a given partner.';

-- Other Indexes for Partner Documents
CREATE INDEX IF NOT EXISTS idx_fleet_partner_docs_partner_type ON public.fleet_partner_documents(
    partner_id, document_type_code, is_active, version DESC
);
CREATE INDEX IF NOT EXISTS idx_fleet_partner_docs_expiry ON public.fleet_partner_documents(
    expiry_date
) WHERE expiry_date IS NOT NULL
AND is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_fleet_partner_docs_status ON public.fleet_partner_documents(
    verification_status, is_active
);


-- ============================================================================
-- 7. Vehicle Maintenance Records (fleet_vehicle_maintenance)
-- Description: Logs scheduled or completed maintenance activities for vehicles.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fleet_vehicle_maintenance (
    maintenance_id          BIGSERIAL PRIMARY KEY,
    vehicle_id              UUID NOT NULL,        -- FK to fleet_vehicles (defined below)
    maintenance_type_code   VARCHAR(50) NOT NULL, -- FK to lkp_maintenance_types (defined below)
    status                  public.TASK_STATUS DEFAULT 'PENDING' NOT NULL, -- References ENUM from 001
    schedule_date           DATE NULL,            -- Planned date for the maintenance
    completion_date         DATE NULL,            -- Actual date the maintenance was completed
    -- Odometer reading at time of maintenance
    odometer_reading        INTEGER NULL CHECK (odometer_reading IS NULL OR odometer_reading >= 0),
    cost                    NUMERIC(10, 2) NULL CHECK (cost IS NULL OR cost >= 0), -- Cost of the maintenance
    currency_code           CHAR(3) NULL,         -- Currency of the cost (FK defined below)
    provider                TEXT NULL,            -- Service provider who performed the maintenance
    notes                   TEXT NULL,            -- General notes about the maintenance
    maintenance_details     JSONB NULL,           -- Structured details (e.g., parts replaced, labor hours)
    completed_by_user_id    UUID NULL,            -- User who recorded the completion (FK defined below)
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL,

    CONSTRAINT chk_fleet_vehicle_maint_dates CHECK (
        completion_date IS NULL OR schedule_date IS NULL OR completion_date >= schedule_date
    )
);
COMMENT ON TABLE public.fleet_vehicle_maintenance
    IS '[VoyaGo][Fleet] Logs scheduled and completed maintenance activities for fleet vehicles.';
COMMENT ON COLUMN public.fleet_vehicle_maintenance.maintenance_details
    IS '[VoyaGo] Structured details of the maintenance performed. 
        Example: {"parts_changed": ["oil_filter", "air_filter"], "labor_hours": 2.5, "invoice_ref": "INV-987"}';

-- Indexes for Vehicle Maintenance
-- Find recent/scheduled maintenance for vehicle
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_maint_vehicle_time ON public.fleet_vehicle_maintenance(
    vehicle_id, completion_date DESC, schedule_date DESC
);
-- Find pending/scheduled tasks
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_maint_status_schedule ON public.fleet_vehicle_maintenance(
    status, schedule_date
);
CREATE INDEX IF NOT EXISTS idx_fleet_vehicle_maint_type ON public.fleet_vehicle_maintenance(maintenance_type_code);
CREATE INDEX IF NOT EXISTS idx_gin_fleet_vehicle_maint_details ON public.fleet_vehicle_maintenance USING gin (
    maintenance_details
);
COMMENT ON INDEX public.idx_gin_fleet_vehicle_maint_details
IS '[VoyaGo][Perf] GIN index for efficient searching within the JSONB maintenance details.';


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for fleet_partners
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_partners ON public.fleet_partners;
CREATE TRIGGER trg_set_timestamp_on_fleet_partners
BEFORE UPDATE ON public.fleet_partners
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_drivers
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_drivers ON public.fleet_drivers;
CREATE TRIGGER trg_set_timestamp_on_fleet_drivers
BEFORE UPDATE ON public.fleet_drivers
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_vehicles
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_vehicles ON public.fleet_vehicles;
CREATE TRIGGER trg_set_timestamp_on_fleet_vehicles
BEFORE UPDATE ON public.fleet_vehicles
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_driver_documents
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_driver_docs ON public.fleet_driver_documents;
CREATE TRIGGER trg_set_timestamp_on_fleet_driver_docs
BEFORE UPDATE ON public.fleet_driver_documents
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_vehicle_documents
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_vehicle_docs ON public.fleet_vehicle_documents;
CREATE TRIGGER trg_set_timestamp_on_fleet_vehicle_docs
BEFORE UPDATE ON public.fleet_vehicle_documents
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_partner_documents
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_partner_docs ON public.fleet_partner_documents;
CREATE TRIGGER trg_set_timestamp_on_fleet_partner_docs
BEFORE UPDATE ON public.fleet_partner_documents
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fleet_vehicle_maintenance
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fleet_vehicle_maint ON public.fleet_vehicle_maintenance;
CREATE TRIGGER trg_set_timestamp_on_fleet_vehicle_maint
BEFORE UPDATE ON public.fleet_vehicle_maintenance
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();


-- ============================================================================
-- Foreign Key Constraints (Defined as DEFERRABLE INITIALLY DEFERRED)
-- ============================================================================

-- Foreign Keys for fleet_partners
ALTER TABLE public.fleet_partners
DROP CONSTRAINT IF EXISTS fk_partner_organization,
DROP CONSTRAINT IF EXISTS fk_partner_approved_by,
DROP CONSTRAINT IF EXISTS fk_partner_address;
ALTER TABLE public.fleet_partners
ADD CONSTRAINT fk_partner_organization FOREIGN KEY (organization_id)
REFERENCES public.core_organizations(organization_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_partner_approved_by FOREIGN KEY (approved_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_partner_address FOREIGN KEY (address_id)
REFERENCES public.core_addresses(address_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_drivers
ALTER TABLE public.fleet_drivers
DROP CONSTRAINT IF EXISTS fk_driver_user_profile,
DROP CONSTRAINT IF EXISTS fk_driver_partner,
DROP CONSTRAINT IF EXISTS fk_driver_current_vehicle;
ALTER TABLE public.fleet_drivers
ADD CONSTRAINT fk_driver_user_profile FOREIGN KEY (driver_id)
-- If user profile deleted, driver record is likely invalid
REFERENCES public.core_user_profiles(user_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_driver_partner FOREIGN KEY (assigned_partner_id)
-- Driver becomes independent if partner deleted
REFERENCES public.fleet_partners(partner_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_driver_current_vehicle FOREIGN KEY (current_vehicle_id)
-- Unassign vehicle if deleted
REFERENCES public.fleet_vehicles(vehicle_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_vehicles
ALTER TABLE public.fleet_vehicles
DROP CONSTRAINT IF EXISTS fk_vehicle_partner,
DROP CONSTRAINT IF EXISTS fk_vehicle_type,
DROP CONSTRAINT IF EXISTS fk_vehicle_assigned_driver;
ALTER TABLE public.fleet_vehicles
ADD CONSTRAINT fk_vehicle_partner FOREIGN KEY (partner_id)
-- Vehicle might become unmanaged if partner deleted
REFERENCES public.fleet_partners(partner_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_vehicle_type FOREIGN KEY (vehicle_type_code)
-- Prevent deleting type if used
REFERENCES public.lkp_vehicle_types(type_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_vehicle_assigned_driver FOREIGN KEY (assigned_driver_id)
-- Unassign driver if driver deleted
REFERENCES public.fleet_drivers(driver_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_driver_documents
ALTER TABLE public.fleet_driver_documents
DROP CONSTRAINT IF EXISTS fk_driver_doc_driver,
DROP CONSTRAINT IF EXISTS fk_driver_doc_type,
DROP CONSTRAINT IF EXISTS fk_driver_doc_verified_by,
DROP CONSTRAINT IF EXISTS fk_driver_doc_uploaded_by;
ALTER TABLE public.fleet_driver_documents
ADD CONSTRAINT fk_driver_doc_driver FOREIGN KEY (driver_id)
-- Delete docs if driver deleted
REFERENCES public.fleet_drivers(driver_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_driver_doc_type FOREIGN KEY (document_type_code)
REFERENCES public.lkp_document_types(doc_type_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_driver_doc_verified_by FOREIGN KEY (verified_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_driver_doc_uploaded_by FOREIGN KEY (uploaded_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_vehicle_documents
ALTER TABLE public.fleet_vehicle_documents
DROP CONSTRAINT IF EXISTS fk_vehicle_doc_vehicle,
DROP CONSTRAINT IF EXISTS fk_vehicle_doc_type,
DROP CONSTRAINT IF EXISTS fk_vehicle_doc_verified_by,
DROP CONSTRAINT IF EXISTS fk_vehicle_doc_uploaded_by;
ALTER TABLE public.fleet_vehicle_documents
ADD CONSTRAINT fk_vehicle_doc_vehicle FOREIGN KEY (vehicle_id)
-- Delete docs if vehicle deleted
REFERENCES public.fleet_vehicles(vehicle_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_vehicle_doc_type FOREIGN KEY (document_type_code)
REFERENCES public.lkp_document_types(doc_type_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_vehicle_doc_verified_by FOREIGN KEY (verified_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_vehicle_doc_uploaded_by FOREIGN KEY (uploaded_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_partner_documents
ALTER TABLE public.fleet_partner_documents
DROP CONSTRAINT IF EXISTS fk_partner_doc_partner,
DROP CONSTRAINT IF EXISTS fk_partner_doc_type,
DROP CONSTRAINT IF EXISTS fk_partner_doc_verified_by,
DROP CONSTRAINT IF EXISTS fk_partner_doc_uploaded_by;
ALTER TABLE public.fleet_partner_documents
ADD CONSTRAINT fk_partner_doc_partner FOREIGN KEY (partner_id)
-- Delete docs if partner deleted
REFERENCES public.fleet_partners(partner_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_partner_doc_type FOREIGN KEY (document_type_code)
REFERENCES public.lkp_document_types(doc_type_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_partner_doc_verified_by FOREIGN KEY (verified_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_partner_doc_uploaded_by FOREIGN KEY (uploaded_by)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Foreign Keys for fleet_vehicle_maintenance
ALTER TABLE public.fleet_vehicle_maintenance
DROP CONSTRAINT IF EXISTS fk_maint_vehicle,
DROP CONSTRAINT IF EXISTS fk_maint_type,
DROP CONSTRAINT IF EXISTS fk_maint_currency,
DROP CONSTRAINT IF EXISTS fk_maint_completed_by;
ALTER TABLE public.fleet_vehicle_maintenance
ADD CONSTRAINT fk_maint_vehicle FOREIGN KEY (vehicle_id)
-- Delete maint records if vehicle deleted
REFERENCES public.fleet_vehicles(vehicle_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_maint_type FOREIGN KEY (maintenance_type_code)
REFERENCES public.lkp_maintenance_types(maintenance_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_maint_currency FOREIGN KEY (currency_code)
REFERENCES public.lkp_currencies(currency_code) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_maint_completed_by FOREIGN KEY (completed_by_user_id)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

COMMIT;

-- ============================================================================
-- End of Migration: 005_fleet_management.sql
-- ============================================================================
