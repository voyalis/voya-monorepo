-- ============================================================================
-- Migration: 005_lookup_data_part4.sql (Version 2.3 / Part 4 of 4)
-- Description: Populates initial lookup tables - Part 4.
-- Scope:
--   - Commission Types (lkp_commission_types, _translations)
--   - Tax Categories (lkp_tax_categories)
--   - Micromobility Vehicle Types (lkp_mm_vehicle_types, _translations)
--   - API Permissions (lkp_api_permissions)
--   - Support Categories (lkp_support_categories, _translations)
--   - Application Configuration (app_config)
-- Author: VoyaGo Team
-- ============================================================================

BEGIN;

-- ============================================================================
-- 22. Commission Types & Translations (lkp_commission_types, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_commission_types (
    commission_type public.commission_type PRIMARY KEY, -- References ENUM defined in 001
    description     text                    NULL,
    is_active       boolean                 DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_commission_types 
    IS '[VoyaGo][Lookup][Finance] Defines how commissions are calculated (percentage, fixed, etc.).';

CREATE TABLE IF NOT EXISTS public.lkp_commission_types_translations (
    commission_type public.commission_type NOT NULL,
    language_code   char(2)                NOT NULL,
    name            text                   NOT NULL,
    PRIMARY KEY (commission_type, language_code)
);
COMMENT ON TABLE public.lkp_commission_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for commission type names.';

-- Foreign Key Constraints for Commission Type Translations
ALTER TABLE public.lkp_commission_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_comm_types_trans_type,
DROP CONSTRAINT IF EXISTS fk_lkp_comm_types_trans_lang;
ALTER TABLE public.lkp_commission_types_translations
ADD CONSTRAINT fk_lkp_comm_types_trans_type
FOREIGN KEY (commission_type)
REFERENCES public.lkp_commission_types(commission_type)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_comm_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_commission_types_translations_lang
ON public.lkp_commission_types_translations(language_code);

-- Seed commission types (references ENUM values)
INSERT INTO public.lkp_commission_types (commission_type, description, is_active) VALUES
('PERCENTAGE',   'Commission calculated as a percentage of the transaction value.', TRUE),
('FIXED_AMOUNT', 'Commission is a fixed monetary amount per transaction.',           TRUE),
('PER_ITEM',     'Commission is calculated based on the number of items.',           TRUE)
ON CONFLICT (commission_type) DO NOTHING; -- ENUM values are fixed, just ensure table entry exists

-- Seed commission type translations
INSERT INTO public.lkp_commission_types_translations (commission_type, language_code, name) VALUES
('PERCENTAGE',   'tr', 'Yüzdesel'),
('PERCENTAGE',   'en', 'Percentage'),
('FIXED_AMOUNT', 'tr', 'Sabit Tutar'),
('FIXED_AMOUNT', 'en', 'Fixed Amount'),
('PER_ITEM',     'tr', 'Öğe Başına'),
('PER_ITEM',     'en', 'Per Item')
ON CONFLICT (commission_type, language_code) DO NOTHING;


-- ============================================================================
-- 23. Tax Categories (lkp_tax_categories)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_tax_categories (
    category_code   varchar(30) PRIMARY KEY,
    description     text        NULL,
    is_active       boolean     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_tax_categories 
    IS '[VoyaGo][Lookup][Finance] Defines categories of taxes applicable to services or products.';

-- Seed tax categories
INSERT INTO public.lkp_tax_categories (category_code, description, is_active) VALUES
('VAT',               'Value Added Tax',               TRUE),
('ACCOMMODATION_TAX', 'Specific tax for accommodation', TRUE),
('CITY_TAX',          'Tax levied by a specific city', TRUE)
ON CONFLICT (category_code) DO NOTHING; -- No translations needed if codes are descriptive enough internally


-- ============================================================================
-- 24. Micromobility Vehicle Types & Translations (lkp_mm_vehicle_types, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_mm_vehicle_types (
    type_code       varchar(50) PRIMARY KEY, -- Specific model/type code (e.g., SEGWAY_NINEBOT_MAX)
    brand           varchar(50) NULL,
    model           varchar(50) NULL,
    max_speed_kmh   smallint    NULL CHECK (max_speed_kmh IS NULL OR max_speed_kmh > 0),
    range_km        smallint    NULL CHECK (range_km IS NULL OR range_km > 0), -- Estimated range
    is_active       boolean     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_mm_vehicle_types 
    IS '[VoyaGo][Lookup][Micromobility] Defines specific types/models of micromobility vehicles (scooters, bikes).';
-- Note: Removed redundant 'description' column, use translation table instead.

CREATE TABLE IF NOT EXISTS public.lkp_mm_vehicle_types_translations (
    type_code       varchar(50) NOT NULL,
    language_code   char(2)     NOT NULL,
    name            text        NOT NULL, -- User-facing name (e.g., Electric Scooter v1)
    description     text        NULL,     -- Optional longer description
    PRIMARY KEY (type_code, language_code)
);
COMMENT ON TABLE public.lkp_mm_vehicle_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for micromobility vehicle type names and descriptions.';

-- Foreign Key Constraints for Micromobility Type Translations
ALTER TABLE public.lkp_mm_vehicle_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_mm_types_trans_type,
DROP CONSTRAINT IF EXISTS fk_lkp_mm_types_trans_lang;
ALTER TABLE public.lkp_mm_vehicle_types_translations
ADD CONSTRAINT fk_lkp_mm_types_trans_type
FOREIGN KEY (type_code)
REFERENCES public.lkp_mm_vehicle_types(type_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_mm_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_mm_vehicle_types_translations_lang
ON public.lkp_mm_vehicle_types_translations(language_code);

-- Seed micromobility vehicle types
INSERT INTO public.lkp_mm_vehicle_types (type_code, brand, model, max_speed_kmh, range_km, is_active) VALUES
('E_SCOOTER_SEGWAY_MAX', 'Segway',  'Ninebot Max', 25, 40, TRUE),
('E_BIKE_XIAOMI_Z20',    'Xiaomi',  'Himo Z20',    25, 80, TRUE)
ON CONFLICT (type_code) DO UPDATE SET
    brand         = excluded.brand,
    model         = excluded.model,
    max_speed_kmh = excluded.max_speed_kmh,
    range_km      = excluded.range_km,
    is_active     = excluded.is_active;

-- Seed micromobility vehicle type translations
INSERT INTO public.lkp_mm_vehicle_types_translations (type_code, language_code, name, description) VALUES
('E_SCOOTER_SEGWAY_MAX', 'tr', 'Elektrikli Scooter (Max)', 'Segway Ninebot Max Scooter'),
('E_SCOOTER_SEGWAY_MAX', 'en', 'Electric Scooter (Max)',   'Segway Ninebot Max Scooter'),
('E_BIKE_XIAOMI_Z20',    'tr', 'Elektrikli Bisiklet (Z20)','Xiaomi Himo Z20 E-Bike'),
('E_BIKE_XIAOMI_Z20',    'en', 'Electric Bike (Z20)',      'Xiaomi Himo Z20 E-Bike')
ON CONFLICT (type_code, language_code) DO NOTHING;


-- ============================================================================
-- 25. API Permissions (lkp_api_permissions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_api_permissions (
    permission_code varchar(100) PRIMARY KEY, -- Unique code for the permission (e.g., booking:create)
    description     text         NOT NULL      -- Description of what the permission grants
);
COMMENT ON TABLE public.lkp_api_permissions 
    IS '[VoyaGo][API][Lookup] Defines granular permissions for API access control.';

-- Seed API permissions (Examples, align with actual API structure)
INSERT INTO public.lkp_api_permissions (permission_code, description) VALUES
('booking:create',          'Permission to create new bookings'),
('booking:read:self',       'Permission to read own bookings'),
('booking:read:all',        'Permission to read all bookings (Admin)'),
('booking:cancel:self',     'Permission to cancel own bookings'),
('driver:read:self',        'Permission to read own driver profile'),
('driver:update_location',  'Permission to update driver location'),
('driver:list:nearby',      'Permission to list nearby drivers'),
('vehicle:read:assigned',   'Permission to read details of assigned vehicle'),
('vehicle:list:all',        'Permission to list all vehicles (Admin)'),
('partner:read:own',        'Permission to read own partner details (Partner Admin)'),
('admin:manage_users',      'Permission to manage users (Admin)'),
('admin:view_reports',      'Permission to view system reports (Admin)')
ON CONFLICT (permission_code) DO UPDATE SET
    description = excluded.description;


-- ============================================================================
-- 26. Support Categories & Translations (lkp_support_categories, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_support_categories (
    category_code   varchar(50) PRIMARY KEY,
    is_active       boolean     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_support_categories 
    IS '[VoyaGo][Lookup][Support] Defines categories for classifying support tickets or requests.';

CREATE TABLE IF NOT EXISTS public.lkp_support_categories_translations (
    category_code   varchar(50) NOT NULL,
    language_code   char(2)     NOT NULL,
    name            text        NOT NULL,
    PRIMARY KEY (category_code, language_code)
);
COMMENT ON TABLE public.lkp_support_categories_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for support category names.';

-- Foreign Key Constraints for Support Category Translations
ALTER TABLE public.lkp_support_categories_translations
DROP CONSTRAINT IF EXISTS fk_lkp_supp_cat_trans_cat,
DROP CONSTRAINT IF EXISTS fk_lkp_supp_cat_trans_lang;
ALTER TABLE public.lkp_support_categories_translations
ADD CONSTRAINT fk_lkp_supp_cat_trans_cat
FOREIGN KEY (category_code)
REFERENCES public.lkp_support_categories(category_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_supp_cat_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_support_categories_translations_lang
ON public.lkp_support_categories_translations(language_code);

-- Seed support categories
INSERT INTO public.lkp_support_categories (category_code, is_active) VALUES
('PAYMENT_ISSUE',     TRUE),
('BOOKING_ISSUE',     TRUE),
('ACCOUNT_QUESTION',  TRUE),
('TECHNICAL_PROBLEM', TRUE),
('FEEDBACK',          TRUE),
('DRIVER_ISSUE',      TRUE), -- Specific category for driver-related support
('PARTNER_ISSUE',     TRUE), -- Specific category for partner-related support
('OTHER',             TRUE)
ON CONFLICT (category_code) DO NOTHING;

-- Seed support category translations
INSERT INTO public.lkp_support_categories_translations (category_code, language_code, name) VALUES
('PAYMENT_ISSUE',     'tr', 'Ödeme Sorunu'),
('PAYMENT_ISSUE',     'en', 'Payment Issue'),
('BOOKING_ISSUE',     'tr', 'Rezervasyon Sorunu'),
('BOOKING_ISSUE',     'en', 'Booking Issue'),
('ACCOUNT_QUESTION',  'tr', 'Hesap Sorusu'),
('ACCOUNT_QUESTION',  'en', 'Account Question'),
('TECHNICAL_PROBLEM', 'tr', 'Teknik Problem'),
('TECHNICAL_PROBLEM', 'en', 'Technical Problem'),
('FEEDBACK',          'tr', 'Geri Bildirim'),
('FEEDBACK',          'en', 'Feedback'),
('DRIVER_ISSUE',      'tr', 'Sürücü Konuları'),
('DRIVER_ISSUE',      'en', 'Driver Issues'),
('PARTNER_ISSUE',     'tr', 'Partner Konuları'),
('PARTNER_ISSUE',     'en', 'Partner Issues'),
('OTHER',             'tr', 'Diğer'),
('OTHER',             'en', 'Other')
ON CONFLICT (category_code, language_code) DO NOTHING;


-- ============================================================================
-- 27. Application Configuration (app_config)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.app_config (
    config_key          varchar(100) PRIMARY KEY,
    config_value        jsonb        NOT NULL, -- Store value as JSONB for flexibility
    description         text         NULL,
    -- Hint for interpreting JSONB value
    value_type          varchar(20)  DEFAULT 'string' NOT NULL CHECK (
        value_type IN ('string', 'number', 'boolean', 'json', 'array')
    ),
    is_client_visible   boolean      DEFAULT FALSE NOT NULL, -- Can this config be exposed to clients?
    is_encrypted        boolean      DEFAULT FALSE NOT NULL, -- Is the value encrypted at rest (or a reference)?
    is_active           boolean      DEFAULT TRUE NOT NULL,
    updated_at          timestamptz  DEFAULT clock_timestamp() NOT NULL
);
COMMENT ON TABLE public.app_config 
    IS '[VoyaGo][Config] Stores global application settings and feature flags.';

-- Trigger to automatically update 'updated_at' timestamp on changes
DROP TRIGGER IF EXISTS trg_set_timestamp_on_app_config ON public.app_config;
CREATE TRIGGER trg_set_timestamp_on_app_config
BEFORE UPDATE ON public.app_config
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp(); -- Use function from 001

-- GIN index for efficient querying of JSONB config values
CREATE INDEX IF NOT EXISTS idx_gin_app_config_value
ON public.app_config USING gin(config_value);

-- Seed application configuration settings
-- Note: Storing actual secrets here is bad practice. Using references (e.g., vault_ref) is better.
INSERT INTO public.app_config (
    config_key, config_value, description, value_type, is_client_visible, is_encrypted, is_active
) VALUES
(
    'system.default_currency',
    '"TRY"',
    'Default currency for new users/operations',
    'string',
    TRUE,
    FALSE,
    TRUE
),
(
    'system.default_country',
    '"TR"',
    'Default country code',
    'string',
    TRUE,
    FALSE,
    TRUE
),
(
    'system.default_language',
    '"tr"',
    'Default language code',
    'string',
    TRUE,
    FALSE,
    TRUE
),
(
    'booking.assignment_timeout_seconds',
    '60',
    'Timeout in seconds for driver to accept booking',
    'number',
    FALSE,
    FALSE,
    TRUE
),
(
    'driver.location_update_interval_seconds',
    '15',
    'Frequency of driver location updates',
    'number',
    TRUE,
    FALSE,
    TRUE
),
(
    'contact.support_email',
    '"destek@voyago.app"',
    'Public support email address',
    'string',
    TRUE,
    FALSE,
    TRUE
),
(
    'limits.max_active_bookings_per_user',
    '5',
    'Maximum concurrent active bookings per user',
    'number',
    FALSE,
    FALSE,
    TRUE
),
(
    'external.maps_api_key_vault_ref',
    '"vg-maps-key"',
    'Reference to Maps API Key in vault',
    'string',
    FALSE,
    TRUE,
    TRUE
),
(
    'external.stripe_sk_vault_ref',
    '"vg-stripe-sk"',
    'Reference to Stripe Secret Key in vault',
    'string',
    FALSE,
    TRUE,
    TRUE
),
(
    'logging.audit_log_retention_days',
    '180',
    'Retention period for audit logs in days',
    'number',
    FALSE,
    FALSE,
    TRUE
),
(
    'logging.system_log_retention_days',
    '90',
    'Retention period for system logs in days',
    'number',
    FALSE,
    FALSE,
    TRUE
)
ON CONFLICT (config_key) DO UPDATE SET
    config_value      = excluded.config_value,
    description       = excluded.description,
    value_type        = excluded.value_type,
    is_client_visible = excluded.is_client_visible,
    is_encrypted      = excluded.is_encrypted,
    is_active         = excluded.is_active,
    updated_at        = clock_timestamp(); -- Explicitly set update time on conflict


COMMIT;
-- ============================================================================
-- End of original file: 005_lookup_data_part4.sql
-- ============================================================================
