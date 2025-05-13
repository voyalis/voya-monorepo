-- ============================================================================
-- Migration: 003_core_user.sql
-- Description: Creates core user management tables (profiles, roles, addresses,
--              payment methods, preferences, devices, etc.).
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-04-19 -- (Assuming original date is intended)
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_part1.sql,
--               003_lookup_data_part2.sql, 004_lookup_data_part3.sql,
--               005_lookup_data_part4.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. User Profiles (core_user_profiles)
-- Description: Stores core user information, preferences, loyalty status,
--              and privacy-related fields. Extends the auth.users table.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_user_profiles (
    -- Must match auth.users(id) (FK constraint added in a later migration, see section 25)
    user_id                 UUID PRIMARY KEY,
    -- PII: Sensitive Data! Requires masking/pseudonymization at the application layer.
    full_name               TEXT NULL,
    -- PII: Sensitive Data! MUST be encrypted at the application layer or via DB extension (e.g., pgcrypto).
    phone_number            TEXT NULL,
    phone_country_code      VARCHAR(5) NULL,  -- PII: Associated with phone_number.
    is_phone_verified       BOOLEAN DEFAULT FALSE NOT NULL,
    -- Should be kept in sync with auth.users(email) (e.g., via triggers/hooks).
    email                   TEXT UNIQUE NOT NULL,
    is_email_verified       BOOLEAN DEFAULT FALSE NOT NULL, -- Can be sourced/synced from auth.users.
    profile_picture_url     TEXT NULL,        -- URL to profile picture, potentially Supabase Storage.
    -- User-specific settings (theme, accessibility, communication etc.)
    preferences             JSONB DEFAULT '{}'::JSONB NOT NULL,
    loyalty_tier_code       VARCHAR(20) NULL, -- FK to lkp_loyalty_tiers (added in section 25)
    loyalty_points_balance  INTEGER DEFAULT 0 NOT NULL CHECK (loyalty_points_balance >= 0),
    language_code           CHAR(2) DEFAULT 'tr' NOT NULL, -- FK to lkp_languages (added in section 25)
    -- Profile verification status (e.g., for KYC)
    verification_status     public.DOCUMENT_STATUS DEFAULT 'PENDING_VERIFICATION' NOT NULL,
    mfa_enabled             BOOLEAN DEFAULT FALSE NOT NULL, -- Could be synced with auth.users MFA status.
    is_deleted              BOOLEAN DEFAULT FALSE NOT NULL, -- Soft delete flag.
    -- Timestamp when user data was anonymized upon request (GDPR/KVKK compliance).
    anonymized_at           TIMESTAMPTZ NULL,
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL -- Automatically updated by trigger

    -- Note: A UNIQUE constraint on (phone_country_code, phone_number) can be problematic
    -- if phone_number is encrypted or NULL. Uniqueness checks for encrypted PII
    -- often need to be handled carefully at the application layer or via specific hashing techniques.
    -- CONSTRAINT uq_user_phone UNIQUE (phone_country_code, phone_number)
);

COMMENT ON TABLE public.core_user_profiles
IS '[VoyaGo][Core] Stores detailed user profile information, preferences, loyalty status, and verification details.';
COMMENT ON COLUMN public.core_user_profiles.user_id
IS 'References the primary key of the Supabase auth.users table.';
COMMENT ON COLUMN public.core_user_profiles.full_name
IS 'PII - Personally Identifiable Information. Must be handled securely.';
COMMENT ON COLUMN public.core_user_profiles.phone_number
IS 'PII - Personally Identifiable Information. MUST be encrypted before storing.';
COMMENT ON COLUMN public.core_user_profiles.email
IS 'Should be kept consistent with the value in Supabase auth.users.email.';
COMMENT ON COLUMN public.core_user_profiles.preferences
IS '[VoyaGo] User preferences stored as JSONB. Example: 
    {"theme": "dark", "preferred_vehicle_types": ["SEDAN_ELECTRIC"], 
    "accessibility_needs": ["WHEELCHAIR_RAMP"], "communication_prefs": {"email_promo": true}}';
COMMENT ON COLUMN public.core_user_profiles.anonymized_at
IS 'Timestamp marking when user data was anonymized based on user request (GDPR/KVKK compliance).';

-- Trigger to update 'updated_at' timestamp
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_user_profiles ON public.core_user_profiles;
CREATE TRIGGER trg_set_timestamp_on_core_user_profiles
BEFORE UPDATE ON public.core_user_profiles
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp(); -- Uses function from 001

-- Indexes for common lookups and performance
CREATE INDEX IF NOT EXISTS idx_core_user_profiles_email ON public.core_user_profiles(email);
CREATE INDEX IF NOT EXISTS idx_core_user_profiles_loyalty_tier ON public.core_user_profiles(loyalty_tier_code);
CREATE INDEX IF NOT EXISTS idx_core_user_profiles_verification ON public.core_user_profiles(verification_status);
CREATE INDEX IF NOT EXISTS idx_gin_core_user_profiles_preferences ON public.core_user_profiles USING gin (preferences);
COMMENT ON INDEX public.idx_gin_core_user_profiles_preferences
IS '[VoyaGo][Perf] GIN index for efficient querying within the JSONB preferences field.';


-- ============================================================================
-- 2. User Roles (core_user_roles)
-- Description: Assigns application roles (defined by app_role ENUM) to users.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_user_roles (
    user_id     UUID NOT NULL, -- FK to core_user_profiles (added in section 25)
    role        public.APP_ROLE NOT NULL, -- References ENUM from 001
    assigned_at TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    assigned_by UUID NULL, -- FK to core_user_profiles (Admin/System user, added in section 25)
    PRIMARY KEY (user_id, role) -- A user can have multiple roles
);
COMMENT ON TABLE public.core_user_roles
    IS '[VoyaGo][Core][Auth] Maps users to their application roles (using ENUM). 
        More granular permissions might be handled in separate permission tables if needed later.';
COMMENT ON COLUMN public.core_user_roles.assigned_by
    IS 'User ID of the administrator or system process that assigned the role (optional).';

-- Index for querying users by role
CREATE INDEX IF NOT EXISTS idx_core_user_roles_role ON public.core_user_roles(role);


-- ============================================================================
-- 3. Addresses (core_addresses)
-- Description: Stores user-saved addresses or general Points of Interest (POIs).
--              Includes fields for address validation.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_addresses (
    address_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- FK to core_user_profiles (added in section 25). NULL indicates a general POI.
    user_id             UUID NULL,
    label               VARCHAR(50) NULL, -- User-defined label (e.g., Home, Work)
    address_type        public.ADDRESS_TYPE DEFAULT 'OTHER' NOT NULL, -- References ENUM from 001
    address_text        TEXT NOT NULL,    -- Full, unstructured address text
    address_components  JSONB NULL,       -- Structured address components (e.g., from geocoding)
    point               GEOGRAPHY(POINT, 4326) NOT NULL, -- Geographic location (latitude, longitude)
    validation_status   VARCHAR(20) DEFAULT 'UNVERIFIED' NOT NULL
    -- Status of address verification via geocoding
    CHECK (validation_status IN ('VERIFIED', 'UNVERIFIED', 'FAILED', 'MANUAL_OVERRIDE')),
    validated_at        TIMESTAMPTZ NULL, -- Timestamp of the last validation attempt
    geocoding_provider  TEXT NULL,        -- Name of the geocoding service used for validation
    provider_reference_id TEXT NULL,      -- Reference ID from the geocoding provider (if any)
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);

COMMENT ON TABLE public.core_addresses
    IS '[VoyaGo][Core] Stores user addresses or general Points of Interest (POIs), 
        including address validation details.';
COMMENT ON COLUMN public.core_addresses.user_id
    IS 'User associated with the address. NULL if this represents a general Point of Interest.';
COMMENT ON COLUMN public.core_addresses.address_components
    IS '[VoyaGo] Structured components derived from geocoding. 
        Example: {"street_number": "10", "route": "Atatürk Cd.", 
        "locality": "Arnavutköy", "country": "TR", "postal_code": "34275"}';
COMMENT ON COLUMN public.core_addresses.point
    IS 'Geographic point using WGS 84 spatial reference system (SRID 4326).';
COMMENT ON COLUMN public.core_addresses.validation_status
    IS '[VoyaGo] Indicates if the address was successfully verified by a geocoding service, 
        failed verification, or was manually approved.';

-- Trigger to update 'updated_at' timestamp
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_addresses ON public.core_addresses;
CREATE TRIGGER trg_set_timestamp_on_core_addresses
BEFORE UPDATE ON public.core_addresses
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes
-- Spatial index for location queries
CREATE INDEX IF NOT EXISTS idx_core_addresses_point ON public.core_addresses USING gist (point);
-- Index for user-specific addresses
CREATE INDEX IF NOT EXISTS idx_core_addresses_user ON public.core_addresses(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_core_addresses_type ON public.core_addresses(address_type);
CREATE INDEX IF NOT EXISTS idx_gin_core_addresses_components ON public.core_addresses USING gin (address_components);
COMMENT ON INDEX public.idx_gin_core_addresses_components
IS '[VoyaGo][Perf] GIN index for efficient searching within the JSONB address components.';


-- ============================================================================
-- 4. Payment Methods (pmt_payment_methods)
-- Description: Stores user's registered payment methods. Sensitive data (e.g., full card numbers) is NOT stored here.
-- Table Prefix: 'pmt_' denotes payment-related tables.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.pmt_payment_methods (
    payment_method_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL, -- FK to core_user_profiles (added in section 25)
    method_type         public.PAYMENT_METHOD_TYPE NOT NULL, -- References ENUM from 001
    provider_code       VARCHAR(30) NOT NULL, -- FK to lkp_payment_providers (added in section 25)
    -- Secure token/ID from the payment provider OR a vault reference. Actual sensitive data is NOT stored.
    provider_token_ref  TEXT NOT NULL,
    -- Masked details for display purposes only (e.g., {'last4': '1234', 'brand': 'Visa', 'expiry_month': 12, ...})
    details             JSONB NULL,
    is_default          BOOLEAN DEFAULT FALSE NOT NULL, -- Is this the user's default payment method?
    -- Status of payment method verification (if required)
    verification_status public.DOCUMENT_STATUS DEFAULT 'PENDING_VERIFICATION' NOT NULL,
    is_deleted          BOOLEAN DEFAULT FALSE NOT NULL, -- Soft delete flag
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.pmt_payment_methods
    IS '[VoyaGo][Payment] Stores references to user payment methods managed by external providers. 
        No sensitive card data is stored directly.';
COMMENT ON COLUMN public.pmt_payment_methods.provider_token_ref
    IS '[VoyaGo][Security] Reference token/ID provided by the payment gateway for this specific payment method, 
        OR a reference to a secret stored in a vault.';
COMMENT ON COLUMN public.pmt_payment_methods.details
    IS '[VoyaGo][Security] Non-sensitive, masked details for UI display purposes only 
        (e.g., card last 4 digits, brand).';
COMMENT ON COLUMN public.pmt_payment_methods.is_default
    IS 'Indicates if this is the primary payment method for the user.';

-- Trigger to update 'updated_at' timestamp
DROP TRIGGER IF EXISTS trg_set_timestamp_on_pmt_payment_methods ON public.pmt_payment_methods;
CREATE TRIGGER trg_set_timestamp_on_pmt_payment_methods
BEFORE UPDATE ON public.pmt_payment_methods
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Unique index to ensure only one active default payment method per user
DROP INDEX IF EXISTS uidx_pmt_payment_methods_user_default;
CREATE UNIQUE INDEX uidx_pmt_payment_methods_user_default
ON public.pmt_payment_methods (user_id)
WHERE is_default IS TRUE AND is_deleted IS FALSE;
COMMENT ON INDEX public.uidx_pmt_payment_methods_user_default
IS '[VoyaGo][Logic] Ensures a user can only have one active payment method marked as default.';

-- Other Indexes
CREATE INDEX IF NOT EXISTS idx_pmt_payment_methods_user ON public.pmt_payment_methods(user_id);
CREATE INDEX IF NOT EXISTS idx_pmt_payment_methods_provider ON public.pmt_payment_methods(provider_code);


-- ============================================================================
-- 5. User Notification Preferences (core_user_notification_preferences)
-- Description: Manages user preferences for receiving notifications per channel and type.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_user_notification_preferences (
    user_id             UUID NOT NULL, -- FK to core_user_profiles (added in section 25)
    channel             public.NOTIFICATION_CHANNEL NOT NULL, -- References ENUM from 001
    notification_type   public.NOTIFICATION_TYPE NOT NULL, -- References ENUM from 001
    is_enabled          BOOLEAN DEFAULT TRUE NOT NULL, -- User preference for this specific notification
    updated_at          TIMESTAMPTZ DEFAULT clock_timestamp(), -- Tracks when the preference was last changed
    PRIMARY KEY (user_id, channel, notification_type)
);
COMMENT ON TABLE public.core_user_notification_preferences
    IS '[VoyaGo][Core] Defines user preferences for receiving specific types of 
        notifications via different channels (Push, Email, SMS).';

-- Trigger to update 'updated_at' only when 'is_enabled' changes
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_user_notif_prefs ON public.core_user_notification_preferences;
CREATE TRIGGER trg_set_timestamp_on_core_user_notif_prefs
BEFORE UPDATE ON public.core_user_notification_preferences
FOR EACH ROW
WHEN (old.is_enabled IS DISTINCT FROM new.is_enabled) -- Condition: Only run if is_enabled changes
EXECUTE FUNCTION public.vg_trigger_set_timestamp();


-- ============================================================================
-- 6. Deleted/Anonymized Users Log (core_deleted_users_log)
-- Description: Audit log for user deletions and anonymizations for compliance.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_deleted_users_log (
    log_id          BIGSERIAL PRIMARY KEY,
    user_id         UUID NOT NULL UNIQUE, -- The ID of the deleted/anonymized user (from auth.users)
    -- Hash of the email before deletion (for potential checks without storing PII)
    email_hash      TEXT NULL,
    phone_hash      TEXT NULL,            -- Hash of the phone number before deletion
    action_type     VARCHAR(20) NOT NULL CHECK (action_type IN ('DELETED', 'ANONYMIZED')),
    reason          TEXT NULL,            -- Reason for deletion/anonymization (e.g., user request, admin action)
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE public.core_deleted_users_log
IS '[VoyaGo][Core][Audit] Logs user deletion and anonymization events for GDPR/KVKK compliance and auditing.';
COMMENT ON COLUMN public.core_deleted_users_log.email_hash
IS 'Cryptographic hash (e.g., SHA-256) of the user''s email address before deletion.';
COMMENT ON COLUMN public.core_deleted_users_log.phone_hash
IS 'Cryptographic hash (e.g., SHA-256) of the user''s phone number before deletion.';


-- ============================================================================
-- 7. User Devices (core_user_devices)
-- Description: Tracks user devices and associated push notification tokens.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_user_devices (
    device_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL, -- FK to core_user_profiles (added in section 25)
    -- Push notification token (FCM, APNS, etc.). Uniqueness ensures token isn't registered multiple times.
    device_token    TEXT NOT NULL UNIQUE,
    device_type     VARCHAR(10) CHECK (device_type IN ('IOS', 'ANDROID', 'WEB')), -- Platform type
    os_version      TEXT NULL,        -- Operating system version
    app_version     VARCHAR(20) NULL, -- Application version on the device
    last_login_at   TIMESTAMPTZ NULL, -- Timestamp of the last login from this device
    ip_address      INET NULL,        -- IP address used during the last login from this device
    is_active       BOOLEAN DEFAULT TRUE NOT NULL, -- Is the device token considered valid/active?
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.core_user_devices
    IS '[VoyaGo][Core] Tracks user devices and associated push notification tokens 
        for sending targeted notifications.';
COMMENT ON COLUMN public.core_user_devices.device_token
    IS 'Unique token provided by the push notification service (FCM, APNS).';
COMMENT ON COLUMN public.core_user_devices.ip_address
    IS 'Last known IP address associated with this device session.';

-- Trigger to update 'updated_at' timestamp
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_user_devices ON public.core_user_devices;
CREATE TRIGGER trg_set_timestamp_on_core_user_devices
BEFORE UPDATE ON public.core_user_devices
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes
CREATE INDEX IF NOT EXISTS idx_core_user_devices_user ON public.core_user_devices(user_id);
-- For targeted pushes
CREATE INDEX IF NOT EXISTS idx_core_user_devices_active_type ON public.core_user_devices(is_active, device_type);


-- ============================================================================
-- 8. Emergency Contacts (core_user_emergency_contacts)
-- Description: Stores user-designated emergency contacts.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_user_emergency_contacts (
    emergency_contact_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id                 UUID NOT NULL, -- FK to core_user_profiles (added in section 25)
    name                    TEXT NOT NULL, -- Name of the emergency contact person
    phone_number            TEXT NOT NULL, -- PII: Sensitive Data! MUST be encrypted/masked at the application layer.
    phone_country_code      VARCHAR(5) NULL,
    relationship            TEXT NULL,     -- Relationship to the user (e.g., Spouse, Parent)
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.core_user_emergency_contacts
IS '[VoyaGo][Core] Stores emergency contacts designated by the user.';
COMMENT ON COLUMN public.core_user_emergency_contacts.phone_number
IS 'PII - Personally Identifiable Information. MUST be encrypted or masked before storing.';

-- Trigger to update 'updated_at' timestamp
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_user_emergency_contacts ON public.core_user_emergency_contacts;
CREATE TRIGGER trg_set_timestamp_on_core_user_emergency_contacts
BEFORE UPDATE ON public.core_user_emergency_contacts
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Index for finding contacts per user
CREATE INDEX IF NOT EXISTS idx_core_user_emergency_contacts_user ON public.core_user_emergency_contacts(user_id);


COMMIT;

-- ============================================================================
-- End of Migration: 003_core_user.sql
-- ============================================================================
