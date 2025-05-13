-- ============================================================================
-- Migration: 002_lookup_data_part1.sql (Version 2.3 / Part 1 of 4)
-- Description: Populates initial lookup tables - Part 1.
-- Scope:
--   - Languages (lkp_languages)
--   - Currencies (lkp_currencies)
--   - Countries (lkp_countries, lkp_countries_translations)
--   - Document Types (lkp_document_types, lkp_document_types_translations)
--   - Vehicle Types (lkp_vehicle_types, lkp_vehicle_types_translations)
--   - Service Types (lkp_service_types, lkp_service_types_translations)
--   - Cancellation Reasons (lkp_cancellation_reasons, lkp_cancellation_reasons_translations)
-- Author: VoyaGo Team
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Languages (lkp_languages)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_languages (
    code        CHAR(2) PRIMARY KEY, -- ISO 639-1 language code
    name        TEXT    NOT NULL,
    is_active   BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_languages 
    IS '[VoyaGo][Lookup] Defines supported languages within the application (base for I18n).';

-- Ensure language names are unique
CREATE UNIQUE INDEX IF NOT EXISTS uq_lkp_languages_name
ON public.lkp_languages(name);

-- Seed initial languages
INSERT INTO public.lkp_languages (code, name, is_active) VALUES
('tr', 'Türkçe',  TRUE),
('en', 'English', TRUE)
ON CONFLICT (code) DO UPDATE SET
    name      = excluded.name,
    is_active = excluded.is_active;

-- ============================================================================
-- 2. Currencies (lkp_currencies)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_currencies (
    currency_code       CHAR(3) PRIMARY KEY, -- ISO 4217 currency code
    name                TEXT    NOT NULL,
    symbol              TEXT,
    decimal_precision   SMALLINT DEFAULT 2 NOT NULL CHECK (decimal_precision >= 0),
    is_active           BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_currencies 
    IS '[VoyaGo][Lookup] Defines supported currencies based on ISO 4217 standard.';

-- Index for efficient filtering of active currencies
CREATE INDEX IF NOT EXISTS idx_lkp_currencies_active
ON public.lkp_currencies(is_active);

-- Seed initial currencies
INSERT INTO public.lkp_currencies (currency_code, name, symbol, decimal_precision, is_active) VALUES
('TRY', 'Turkish Lira', '₺', 2, TRUE),
('EUR', 'Euro',         '€', 2, TRUE),
('USD', 'US Dollar',    '$', 2, TRUE),
('GBP', 'British Pound', '£', 2, TRUE)
ON CONFLICT (currency_code) DO UPDATE SET
    name              = excluded.name,
    symbol            = excluded.symbol,
    decimal_precision = excluded.decimal_precision,
    is_active         = excluded.is_active;

-- ============================================================================
-- 3. Countries & Translations (lkp_countries, lkp_countries_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_countries (
    country_code            CHAR(2) PRIMARY KEY CHECK (country_code ~ '^[A-Z]{2}$'), -- ISO 3166-1 alpha-2 code
    default_currency_code   CHAR(3),
    phone_code              VARCHAR(5), -- International phone calling code prefix
    is_active               BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_countries IS '[VoyaGo][Lookup] Defines countries relevant to the application.';

CREATE TABLE IF NOT EXISTS public.lkp_countries_translations (
    country_code    CHAR(2) NOT NULL,
    language_code   CHAR(2) NOT NULL,
    name            TEXT    NOT NULL,
    PRIMARY KEY (country_code, language_code)
);
COMMENT ON TABLE public.lkp_countries_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for country names.';

-- Foreign Key Constraints for Countries
ALTER TABLE public.lkp_countries
DROP CONSTRAINT IF EXISTS fk_lkp_countries_currency;
ALTER TABLE public.lkp_countries
ADD CONSTRAINT fk_lkp_countries_currency
FOREIGN KEY (default_currency_code)
REFERENCES public.lkp_currencies(currency_code)
ON DELETE RESTRICT -- Prevent deleting currency if used by a country
DEFERRABLE INITIALLY DEFERRED;

-- Foreign Key Constraints for Country Translations
ALTER TABLE public.lkp_countries_translations
DROP CONSTRAINT IF EXISTS fk_lkp_countries_trans_country,
DROP CONSTRAINT IF EXISTS fk_lkp_countries_trans_lang;
ALTER TABLE public.lkp_countries_translations
ADD CONSTRAINT fk_lkp_countries_trans_country
FOREIGN KEY (country_code)
REFERENCES public.lkp_countries(country_code)
ON DELETE CASCADE -- Delete translations if country is deleted
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_countries_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE -- Delete translations if language is deleted
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_countries_translations_lang
ON public.lkp_countries_translations(language_code);

-- Seed initial countries data
INSERT INTO public.lkp_countries (country_code, default_currency_code, phone_code, is_active) VALUES
('TR', 'TRY', '+90', TRUE),
('DE', 'EUR', '+49', TRUE),
('US', 'USD', '+1',  TRUE),
('GB', 'GBP', '+44', TRUE)
ON CONFLICT (country_code) DO UPDATE SET
    default_currency_code = excluded.default_currency_code,
    phone_code            = excluded.phone_code,
    is_active             = excluded.is_active;

-- Seed initial countries translations data
INSERT INTO public.lkp_countries_translations (country_code, language_code, name) VALUES
('TR', 'tr', 'Türkiye'),
('TR', 'en', 'Turkey'),
('DE', 'tr', 'Almanya'),
('DE', 'en', 'Germany'),
('US', 'tr', 'Amerika Birleşik Devletleri'),
('US', 'en', 'United States'),
('GB', 'en', 'United Kingdom'),
('GB', 'tr', 'Birleşik Krallık')
ON CONFLICT (country_code, language_code) DO NOTHING; -- Translations are static, do nothing if exists


-- ============================================================================
-- 4. Document Types & Translations (lkp_document_types, lkp_document_types_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_document_types (
    doc_type_code           VARCHAR(50) PRIMARY KEY,
    entity_scope            VARCHAR(20) NOT NULL CHECK (entity_scope IN ('DRIVER','VEHICLE','PARTNER','USER')),
    default_validity_period INTERVAL, -- Optional default validity duration for this document type
    is_active               BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_document_types 
    IS '[VoyaGo][Lookup] Defines types of documents required or managed within the system (e.g., ID, license).';

CREATE TABLE IF NOT EXISTS public.lkp_document_types_translations (
    doc_type_code   VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (doc_type_code, language_code)
);
COMMENT ON TABLE public.lkp_document_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for document type names and descriptions.';

-- Foreign Key Constraints for Document Type Translations
ALTER TABLE public.lkp_document_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_doc_types_trans_type,
DROP CONSTRAINT IF EXISTS fk_lkp_doc_types_trans_lang;
ALTER TABLE public.lkp_document_types_translations
ADD CONSTRAINT fk_lkp_doc_types_trans_type
FOREIGN KEY (doc_type_code)
REFERENCES public.lkp_document_types(doc_type_code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_doc_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_document_types_translations_lang
ON public.lkp_document_types_translations(language_code);

-- Seed document types data
INSERT INTO public.lkp_document_types (doc_type_code, entity_scope, default_validity_period, is_active) VALUES
('USER_ID_FRONT',           'USER',     NULL,       TRUE),
('USER_ID_BACK',            'USER',     NULL,       TRUE),
('DRIVER_LICENSE_FRONT',    'DRIVER',   '10 years', TRUE),
('DRIVER_LICENSE_BACK',     'DRIVER',   '10 years', TRUE),
('VEHICLE_REGISTRATION',    'VEHICLE',  NULL,       TRUE),
('VEHICLE_INSURANCE_TRAFFIC','VEHICLE', '1 year',   TRUE),
('VEHICLE_INSPECTION',      'VEHICLE',  '2 years',  TRUE),
('DRIVER_SRC_PASSENGER',    'DRIVER',   NULL,       TRUE),
('DRIVER_PSYCHOTECHNICAL',  'DRIVER',   '5 years',  TRUE),
('PARTNER_AGREEMENT',       'PARTNER',  NULL,       TRUE),
('PARTNER_TAX_CERTIFICATE', 'PARTNER',  '1 year',   TRUE)
ON CONFLICT (doc_type_code) DO UPDATE SET
    entity_scope            = excluded.entity_scope,
    default_validity_period = excluded.default_validity_period,
    is_active               = excluded.is_active;

-- Seed document type translations data
INSERT INTO public.lkp_document_types_translations (doc_type_code, language_code, name, description) VALUES
('USER_ID_FRONT', 'tr', 'Kimlik Ön Yüz', 'Vatandaşlık kimlik kartı ön yüzü'),
('USER_ID_FRONT', 'en', 'ID Card Front', 'Front side of the national ID card'),
('USER_ID_BACK', 'tr', 'Kimlik Arka Yüz', 'Vatandaşlık kimlik kartı arka yüzü'),
('USER_ID_BACK', 'en', 'ID Card Back', 'Back side of the national ID card'),
('DRIVER_LICENSE_FRONT', 'tr', 'Sürücü Belgesi Ön Yüz', 'Geçerli sürücü ehliyeti ön yüzü'),
('DRIVER_LICENSE_FRONT', 'en', 'Driver License Front', 'Front side of the valid driver license'),
('DRIVER_LICENSE_BACK', 'tr', 'Sürücü Belgesi Arka Yüz', 'Geçerli sürücü ehliyeti arka yüzü'),
('DRIVER_LICENSE_BACK', 'en', 'Driver License Back', 'Back side of the valid driver license'),
('VEHICLE_REGISTRATION', 'tr', 'Araç Ruhsatı', 'Taşıt kayıt belgesi'),
('VEHICLE_REGISTRATION', 'en', 'Vehicle Registration', 'Vehicle registration certificate'),
('VEHICLE_INSURANCE_TRAFFIC', 'tr', 'Zorunlu Trafik Sigortası', 'Güncel trafik sigorta poliçesi'),
('VEHICLE_INSURANCE_TRAFFIC', 'en', 'Mandatory Traffic Insurance', 'Valid traffic insurance policy'),
('VEHICLE_INSPECTION', 'tr', 'Araç Muayenesi', 'Geçerli araç muayene raporu'),
('VEHICLE_INSPECTION', 'en', 'Vehicle Inspection', 'Valid vehicle inspection report'),
('DRIVER_SRC_PASSENGER', 'tr', 'SRC Belgesi (Yolcu)', 'Yolcu taşımacılığı mesleki yeterlilik belgesi'),
(
    'DRIVER_SRC_PASSENGER',
    'en',
    'SRC Certificate (Passenger)',
    'Vocational competence certificate for passenger transport'
),
('DRIVER_PSYCHOTECHNICAL', 'tr', 'Psikoteknik Belgesi', 'Sürücü psikoteknik değerlendirme raporu'),
('DRIVER_PSYCHOTECHNICAL', 'en', 'Psychotechnical Certificate', 'Driver psychotechnical evaluation report'),
('PARTNER_AGREEMENT', 'tr', 'Partner Sözleşmesi', 'İmzalı iş ortaklığı sözleşmesi'),
('PARTNER_AGREEMENT', 'en', 'Partner Agreement', 'Signed partnership agreement'),
('PARTNER_TAX_CERTIFICATE', 'tr', 'Vergi Levhası', 'Güncel vergi levhası'),
('PARTNER_TAX_CERTIFICATE', 'en', 'Tax Certificate', 'Current tax certificate')
ON CONFLICT (doc_type_code, language_code) DO NOTHING;

-- ============================================================================
-- 5. Vehicle Types & Translations (lkp_vehicle_types, lkp_vehicle_types_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_vehicle_types (
    type_code               VARCHAR(50) PRIMARY KEY,
    category                public.VEHICLE_CATEGORY NOT NULL, -- References ENUM defined in 001
    default_capacity        SMALLINT CHECK (default_capacity > 0), -- Default passenger capacity
    icon_url                TEXT,
    base_cost_multiplier    NUMERIC(4,2) DEFAULT 1.00 NOT NULL, -- Pricing adjustment factor
    is_electric             BOOLEAN DEFAULT FALSE NOT NULL,
    is_active               BOOLEAN DEFAULT TRUE  NOT NULL
);
COMMENT ON TABLE public.lkp_vehicle_types 
    IS '[VoyaGo][Lookup] Defines specific vehicle types available for services.';

CREATE TABLE IF NOT EXISTS public.lkp_vehicle_types_translations (
    type_code       VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (type_code, language_code)
);
COMMENT ON TABLE public.lkp_vehicle_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for vehicle type names and descriptions.';

-- Foreign Key Constraints for Vehicle Type Translations
ALTER TABLE public.lkp_vehicle_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_vehicle_types_trans_type,
DROP CONSTRAINT IF EXISTS fk_lkp_vehicle_types_trans_lang;
ALTER TABLE public.lkp_vehicle_types_translations
ADD CONSTRAINT fk_lkp_vehicle_types_trans_type
FOREIGN KEY (type_code)
REFERENCES public.lkp_vehicle_types(type_code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_vehicle_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_vehicle_types_translations_lang
ON public.lkp_vehicle_types_translations(language_code);

-- Seed vehicle types data
INSERT INTO public.lkp_vehicle_types
(type_code, category, default_capacity, icon_url, base_cost_multiplier, is_electric, is_active) VALUES
('SEDAN_ECO',         'CAR',     4, '/icons/sedan_eco.png',      1.00, FALSE, TRUE),
('SEDAN_COMFORT',     'CAR',     4, '/icons/sedan_comfort.png',  1.20, FALSE, TRUE),
('SEDAN_PREMIUM',     'CAR',     4, '/icons/sedan_premium.png',  1.60, FALSE, TRUE),
('SEDAN_ELECTRIC',    'CAR',     4, '/icons/sedan_electric.png', 1.15, TRUE,  TRUE),
('SUV_STANDARD',      'CAR',     5, '/icons/suv.png',            1.35, FALSE, TRUE),
('SUV_LARGE',         'CAR',     7, '/icons/suv_large.png',      1.70, FALSE, TRUE),
('VAN_PASSENGER',     'VAN',     8, '/icons/van_passenger.png',  1.50, FALSE, TRUE),
('VAN_PREMIUM',       'VAN',     6, '/icons/van_premium.png',    2.00, FALSE, TRUE),
('SHUTTLE_BUS_16',    'BUS',    16, '/icons/bus_16.png',         1.80, FALSE, TRUE),
('CARGO_VAN_SMALL',   'VAN',     2, '/icons/van_cargo_small.png',1.00, FALSE, TRUE),
('CARGO_VAN_LARGE',   'TRUCK',   2, '/icons/van_cargo_large.png',1.40, FALSE, TRUE),
('E_SCOOTER_V1',      'SCOOTER', 1, '/icons/scooter.png',        0.50, TRUE,  TRUE),
('E_BIKE_V1',         'BICYCLE', 1, '/icons/ebike.png',          0.60, TRUE,  TRUE),
('CARGO_BIKE',        'BICYCLE', 1, '/icons/bike_cargo.png',     0.70, FALSE, TRUE)
ON CONFLICT (type_code) DO UPDATE SET
    category             = excluded.category,
    default_capacity     = excluded.default_capacity,
    icon_url             = excluded.icon_url,
    base_cost_multiplier = excluded.base_cost_multiplier,
    is_electric          = excluded.is_electric,
    is_active            = excluded.is_active;

-- Seed vehicle type translations data
INSERT INTO public.lkp_vehicle_types_translations
(type_code, language_code, name, description) VALUES
('SEDAN_ECO', 'tr', 'Ekonomik Sedan', 'Standart sedan'),
('SEDAN_ECO', 'en', 'Economy Sedan', 'Standard sedan'),
('SEDAN_COMFORT', 'tr', 'Konfor Sedan', 'Daha konforlu sedan'),
('SEDAN_COMFORT', 'en', 'Comfort Sedan', 'More comfortable sedan'),
('SEDAN_PREMIUM', 'tr', 'Premium Sedan', 'Lüks sedan deneyimi'),
('SEDAN_PREMIUM', 'en', 'Premium Sedan', 'Luxury sedan experience'),
('SEDAN_ELECTRIC', 'tr', 'Elektrikli Sedan', 'Çevre dostu elektrikli'),
('SEDAN_ELECTRIC', 'en', 'Electric Sedan', 'Eco-friendly electric'),
('SUV_STANDARD', 'tr', 'Standart SUV', 'Geniş SUV'),
('SUV_STANDARD', 'en', 'Standard SUV', 'Spacious SUV'),
('SUV_LARGE', 'tr', 'Büyük SUV', '7 koltuklu SUV'),
('SUV_LARGE', 'en', 'Large SUV', '7-seater SUV'),
('VAN_PASSENGER', 'tr', 'Yolcu Minivanı (8)', '8 kişiye kadar'),
('VAN_PASSENGER', 'en', 'Passenger Van (8)', 'Up to 8 passengers'),
('VAN_PREMIUM', 'tr', 'Premium Minivan (6)', 'VIP taşımacılık için'),
('VAN_PREMIUM', 'en', 'Premium Van (6)', 'For VIP transport'),
('SHUTTLE_BUS_16', 'tr', 'Shuttle Minibüs (16)', '16 koltuklu'),
('SHUTTLE_BUS_16', 'en', 'Shuttle Bus (16)', '16-seater bus'),
('CARGO_VAN_SMALL', 'tr', 'Küçük Kargo Vanı', 'Paket teslimatı için'),
('CARGO_VAN_SMALL', 'en', 'Small Cargo Van', 'For package delivery'),
('CARGO_VAN_LARGE', 'tr', 'Büyük Kargo Kamyoneti', 'Hacimli eşya taşımacılığı'),
('CARGO_VAN_LARGE', 'en', 'Large Cargo Van', 'For bulky item transport'),
('E_SCOOTER_V1', 'tr', 'Elektrikli Scooter', 'Kısa mesafe ulaşım'),
('E_SCOOTER_V1', 'en', 'Electric Scooter', 'Short distance transport'),
('E_BIKE_V1', 'tr', 'Elektrikli Bisiklet', 'Destekli bisiklet'),
('E_BIKE_V1', 'en', 'Electric Bike', 'Assisted bicycle'),
('CARGO_BIKE', 'tr', 'Kargo Bisikleti', 'Çevreci kargo teslimatı'),
('CARGO_BIKE', 'en', 'Cargo Bike', 'Eco-friendly cargo delivery')
ON CONFLICT (type_code, language_code) DO NOTHING;


-- ============================================================================
-- 6. Service Types & Translations (lkp_service_types, lkp_service_types_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_service_types (
    service_code    public.SERVICE_CODE PRIMARY KEY, -- References ENUM defined in 001
    requires_driver BOOLEAN NOT NULL, -- Does this service typically require a driver?
    is_shared       BOOLEAN NOT NULL, -- Is this service typically shared among users?
    is_cargo        BOOLEAN NOT NULL, -- Is this primarily a cargo/delivery service?
    is_rental       BOOLEAN NOT NULL, -- Is this primarily a rental service (vehicle or property)?
    is_scheduled    BOOLEAN DEFAULT FALSE NOT NULL, -- Does this service run on a fixed schedule?
    attributes      JSONB,   -- Additional type-specific attributes (e.g., luggage limits)
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_service_types 
    IS '[VoyaGo][Lookup] Defines the core service types offered by the platform.';

CREATE TABLE IF NOT EXISTS public.lkp_service_types_translations (
    service_code    public.SERVICE_CODE NOT NULL,
    language_code   CHAR(2)             NOT NULL,
    name            TEXT                NOT NULL,
    description     TEXT,
    PRIMARY KEY (service_code, language_code)
);
COMMENT ON TABLE public.lkp_service_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for service type names and descriptions.';

-- Foreign Key Constraints for Service Type Translations
ALTER TABLE public.lkp_service_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_service_types_trans_service,
DROP CONSTRAINT IF EXISTS fk_lkp_service_types_trans_lang;
ALTER TABLE public.lkp_service_types_translations
ADD CONSTRAINT fk_lkp_service_types_trans_service
FOREIGN KEY (service_code)
REFERENCES public.lkp_service_types(service_code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_service_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_service_types_translations_lang
ON public.lkp_service_types_translations(language_code);

-- GIN index for efficient querying of JSONB attributes
CREATE INDEX IF NOT EXISTS idx_gin_lkp_service_types_attributes
ON public.lkp_service_types USING gin(attributes);

-- Seed service types data
INSERT INTO public.lkp_service_types
(service_code, requires_driver, is_shared, is_cargo, is_rental, is_scheduled, attributes, is_active) VALUES
(
    'TRANSFER',       TRUE,  FALSE, FALSE, FALSE, FALSE,
    jsonb_build_object('max_passengers', 4, 'luggage_limit', jsonb_build_object('standard', 2)), TRUE
),
(
    'SHUTTLE',        TRUE,  TRUE,  FALSE, FALSE, TRUE,
    jsonb_build_object('max_passengers', 1, 'luggage_limit', jsonb_build_object('standard', 1)), TRUE
),
(
    'RENTAL',         FALSE, FALSE, FALSE, TRUE,  TRUE,
    NULL, TRUE
),
(
    'CHAUFFEUR',      TRUE,  FALSE, FALSE, FALSE, TRUE,
    jsonb_build_object('booking_lead_time_minutes', 60), TRUE
),
(
    'INTERCITY',      TRUE,  FALSE, FALSE, FALSE, TRUE,
    jsonb_build_object('max_passengers', 4), TRUE
),
(
    'CARGO',          TRUE,  FALSE, TRUE,  FALSE, FALSE,
    jsonb_build_object('max_weight_kg', 25), TRUE
),
(
    'MICROMOBILITY',  FALSE, TRUE,  FALSE, TRUE,  FALSE,
    jsonb_build_object('type', 'SCOOTER'), TRUE
), -- Default type, can vary per vehicle
(
    'PUBLIC_TRANSPORT',FALSE,TRUE, FALSE, FALSE, FALSE,
    NULL, FALSE
), -- Example, might be inactive initially
(
    'ACCOMMODATION',  FALSE, FALSE, FALSE, TRUE,  TRUE,
    NULL, TRUE
)
ON CONFLICT (service_code) DO UPDATE SET
    requires_driver = excluded.requires_driver,
    is_shared       = excluded.is_shared,
    is_cargo        = excluded.is_cargo,
    is_rental       = excluded.is_rental,
    is_scheduled    = excluded.is_scheduled,
    attributes      = excluded.attributes,
    is_active       = excluded.is_active;

-- Seed service type translations data
INSERT INTO public.lkp_service_types_translations
(service_code, language_code, name, description) VALUES
('TRANSFER', 'tr', 'Özel Transfer', 'Size özel araçla noktadan noktaya'),
('TRANSFER', 'en', 'Private Transfer', 'Point-to-point with a private vehicle'),
('SHUTTLE', 'tr', 'Paylaşımlı Shuttle', 'Belirli güzergahlarda paylaşımlı servis'),
('SHUTTLE', 'en', 'Shared Shuttle', 'Shared service on specific routes'),
('RENTAL', 'tr', 'Araç Kiralama', 'Sürücüsüz araç kiralama'),
('RENTAL', 'en', 'Car Rental', 'Self-drive car rental'),
('CHAUFFEUR', 'tr', 'Şoförlü Tahsis', 'Saatlik/günlük şoförlü kiralama'),
('CHAUFFEUR', 'en', 'Chauffeur Service', 'Hourly/daily rental with driver'),
('INTERCITY', 'tr', 'Şehirlerarası Transfer', 'Şehirlerarası özel yolculuk'),
('INTERCITY', 'en', 'Intercity Transfer', 'Private intercity travel'),
('CARGO', 'tr', 'Kargo/Paket', 'Paket ve eşya taşımacılığı'),
('CARGO', 'en', 'Cargo/Package', 'Package and goods transport'),
('MICROMOBILITY', 'tr', 'Mikromobilite', 'Scooter/bisiklet kiralama'),
('MICROMOBILITY', 'en', 'Micromobility', 'Scooter/bike rental'),
('PUBLIC_TRANSPORT', 'tr', 'Toplu Taşıma', 'Toplu taşıma entegrasyonu'),
('PUBLIC_TRANSPORT', 'en', 'Public Transport', 'Public transport integration'),
('ACCOMMODATION', 'tr', 'Konaklama', 'Otel/Ev kiralama'),
('ACCOMMODATION', 'en', 'Accommodation', 'Hotel/Home rental')
ON CONFLICT (service_code, language_code) DO NOTHING;


-- ============================================================================
-- 7. Cancellation Reasons & Translations (lkp_cancellation_reasons, lkp_cancellation_reasons_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_cancellation_reasons (
    reason_code         VARCHAR(50) PRIMARY KEY,
    -- Who initiated cancellation?
    applicable_actor    VARCHAR(10) NOT NULL CHECK (applicable_actor IN ('USER','DRIVER','SYSTEM','PARTNER')),
    is_user_visible     BOOLEAN DEFAULT TRUE NOT NULL, -- Should this reason be shown to the end-user?
    is_driver_visible   BOOLEAN DEFAULT TRUE NOT NULL, -- Should this reason be shown to the driver?
    is_partner_visible  BOOLEAN DEFAULT FALSE NOT NULL, -- Should this reason be shown to partners?
    requires_fee        BOOLEAN DEFAULT FALSE NOT NULL, -- Does this reason typically incur a cancellation fee?
    is_active           BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_cancellation_reasons 
    IS '[VoyaGo][Lookup] Defines standard reasons for booking cancellations.';

CREATE TABLE IF NOT EXISTS public.lkp_cancellation_reasons_translations (
    reason_code     VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    description     TEXT        NOT NULL, -- User/Driver facing text for the reason
    PRIMARY KEY (reason_code, language_code)
);
COMMENT ON TABLE public.lkp_cancellation_reasons_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for cancellation reasons.';

-- Foreign Key Constraints for Cancellation Reason Translations
ALTER TABLE public.lkp_cancellation_reasons_translations
DROP CONSTRAINT IF EXISTS fk_lkp_cancel_reasons_trans_reason,
DROP CONSTRAINT IF EXISTS fk_lkp_cancel_reasons_trans_lang;
ALTER TABLE public.lkp_cancellation_reasons_translations
ADD CONSTRAINT fk_lkp_cancel_reasons_trans_reason
FOREIGN KEY (reason_code)
REFERENCES public.lkp_cancellation_reasons(reason_code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_cancel_reasons_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_cancellation_reasons_translations_lang
ON public.lkp_cancellation_reasons_translations(language_code);

-- Seed cancellation reasons data
INSERT INTO public.lkp_cancellation_reasons
(
    reason_code, applicable_actor, is_user_visible, is_driver_visible, is_partner_visible, requires_fee, is_active
) VALUES
('USER_PLAN_CHANGED',       'USER',   TRUE,  TRUE,  FALSE, TRUE,  TRUE),
('USER_FOUND_BETTER_OPTION','USER',   TRUE,  TRUE,  FALSE, TRUE,  TRUE),
('USER_NO_SHOW',            'SYSTEM', TRUE,  TRUE,  TRUE,  TRUE,  TRUE), -- Often logged by driver/system
('USER_LATE',               'DRIVER', TRUE,  TRUE,  FALSE, TRUE,  TRUE), -- Driver cancels due to user lateness
('USER_SAFETY_CONCERN',     'USER',   TRUE,  FALSE, FALSE, FALSE, TRUE),
('DRIVER_UNAVAILABLE',      'DRIVER', TRUE,  TRUE,  TRUE,  FALSE, TRUE),
('DRIVER_REJECTED',         'DRIVER', TRUE,  TRUE,  TRUE,  FALSE, TRUE),
('DRIVER_LATE',             'USER',   TRUE,  TRUE,  FALSE, FALSE, TRUE), -- User cancels due to driver lateness
('DRIVER_SAFETY_CONCERN',   'DRIVER', FALSE, TRUE,  FALSE, FALSE, TRUE),
('DRIVER_VEHICLE_ISSUE',    'DRIVER', TRUE,  TRUE,  TRUE,  FALSE, TRUE),
('SYSTEM_NO_DRIVER_FOUND',  'SYSTEM', TRUE,  FALSE, FALSE, FALSE, TRUE),
('SYSTEM_PAYMENT_FAILED',   'SYSTEM', TRUE,  FALSE, FALSE, FALSE, TRUE),
('SYSTEM_OPERATIONAL_ISSUE','SYSTEM', FALSE, FALSE, FALSE, FALSE, TRUE), -- Internal reason
('SYSTEM_WEATHER_CONDITION','SYSTEM', TRUE,  TRUE,  TRUE,  FALSE, TRUE),
('PARTNER_OPERATIONAL',     'PARTNER',TRUE,  TRUE,  TRUE,  FALSE, TRUE) -- E.g., Rental company cancels
ON CONFLICT (reason_code) DO UPDATE SET
    applicable_actor   = excluded.applicable_actor,
    is_user_visible    = excluded.is_user_visible,
    is_driver_visible  = excluded.is_driver_visible,
    is_partner_visible = excluded.is_partner_visible,
    requires_fee       = excluded.requires_fee,
    is_active          = excluded.is_active;

-- Seed cancellation reason translations data
INSERT INTO public.lkp_cancellation_reasons_translations
(reason_code, language_code, description) VALUES
('USER_PLAN_CHANGED', 'tr', 'Planlarım değişti'),
('USER_PLAN_CHANGED', 'en', 'My plans changed'),
('USER_FOUND_BETTER_OPTION', 'tr', 'Daha iyi bir seçenek buldum'),
('USER_FOUND_BETTER_OPTION', 'en', 'Found a better option'),
('USER_NO_SHOW', 'tr', 'Kullanıcı gelmedi'),
('USER_NO_SHOW', 'en', 'User no-show'),
('USER_LATE', 'tr', 'Kullanıcı gecikti'),
('USER_LATE', 'en', 'User was late'),
('USER_SAFETY_CONCERN', 'tr', 'Güvenlik endişesi'),
('USER_SAFETY_CONCERN', 'en', 'Safety concern'),
('DRIVER_UNAVAILABLE', 'tr', 'Sürücü müsait değil'),
('DRIVER_UNAVAILABLE', 'en', 'Driver unavailable'),
('DRIVER_REJECTED', 'tr', 'Sürücü reddetti'),
('DRIVER_REJECTED', 'en', 'Driver rejected'),
('DRIVER_LATE', 'tr', 'Sürücü geç kaldı'),
('DRIVER_LATE', 'en', 'Driver was late'),
('DRIVER_SAFETY_CONCERN', 'tr', 'Sürücü güvenlik endişesi'),
('DRIVER_SAFETY_CONCERN', 'en', 'Driver safety concern'),
('DRIVER_VEHICLE_ISSUE', 'tr', 'Araç sorunu'),
('DRIVER_VEHICLE_ISSUE', 'en', 'Vehicle issue'),
('SYSTEM_NO_DRIVER_FOUND', 'tr', 'Sürücü bulunamadı'),
('SYSTEM_NO_DRIVER_FOUND', 'en', 'No driver found'),
('SYSTEM_PAYMENT_FAILED', 'tr', 'Ödeme başarısız'),
('SYSTEM_PAYMENT_FAILED', 'en', 'Payment failed'),
('SYSTEM_OPERATIONAL_ISSUE', 'tr', 'Operasyonel sorun'),
('SYSTEM_OPERATIONAL_ISSUE', 'en', 'Operational issue'),
('SYSTEM_WEATHER_CONDITION', 'tr', 'Hava koşulları'),
('SYSTEM_WEATHER_CONDITION', 'en', 'Weather conditions'),
('PARTNER_OPERATIONAL', 'tr', 'İş ortağı kaynaklı sorun'),
('PARTNER_OPERATIONAL', 'en', 'Partner operational issue')
ON CONFLICT (reason_code, language_code) DO NOTHING;


COMMIT;
-- ============================================================================
-- End of original file: 002_lookup_data_part1.sql
-- ============================================================================
