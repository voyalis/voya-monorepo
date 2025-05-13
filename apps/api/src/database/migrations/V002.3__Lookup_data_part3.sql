-- ============================================================================
-- Migration: 004_lookup_data_part3.sql (Version 2.3 / Part 3 of 4)
-- Description: Populates initial lookup tables - Part 3.
-- Scope:
--   - Prerequisite Data (Add GB/GBP for Emission Factors FK)
--   - Report Reasons (lkp_report_reasons, lkp_report_reasons_translations)
--   - Bid Rejection Reasons (lkp_bid_rejection_reasons, _translations)
--   - Bid Cancellation Reasons (lkp_bid_cancellation_reasons, _translations)
--   - Emission Factors (lkp_emission_factors)
--   - Status Transitions (lkp_status_transitions)
--   - Room Amenities (lkp_room_amenities, _translations)
--   - Property Features (lkp_property_features, _translations)
-- Author: VoyaGo Team
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 15. Report Reasons & Translations (lkp_report_reasons, _translations)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.lkp_report_reasons (
    reason_code         VARCHAR(50) PRIMARY KEY,
    applies_to_entity   VARCHAR(20) NOT NULL CHECK (
        applies_to_entity IN ('USER','DRIVER','VEHICLE','BOOKING','PROPERTY','OTHER')
    ),
    is_active           BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_report_reasons 
    IS '[VoyaGo][Lookup][Support] Defines standard reasons for users reporting issues.';

CREATE TABLE IF NOT EXISTS public.lkp_report_reasons_translations (
    reason_code     VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    description     TEXT        NOT NULL, -- User-facing text for the report reason
    PRIMARY KEY (reason_code, language_code)
);
COMMENT ON TABLE public.lkp_report_reasons_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for report reasons.';

-- Foreign Key Constraints for Report Reason Translations
ALTER TABLE public.lkp_report_reasons_translations
DROP CONSTRAINT IF EXISTS fk_lkp_report_reas_trans_reason,
DROP CONSTRAINT IF EXISTS fk_lkp_report_reas_trans_lang;
ALTER TABLE public.lkp_report_reasons_translations
ADD CONSTRAINT fk_lkp_report_reas_trans_reason
FOREIGN KEY (reason_code)
REFERENCES public.lkp_report_reasons(reason_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_report_reas_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_report_reasons_translations_lang
ON public.lkp_report_reasons_translations(language_code);

-- Seed report reasons
INSERT INTO public.lkp_report_reasons (reason_code, applies_to_entity, is_active) VALUES
('DRIVER_RUDE_BEHAVIOR',     'DRIVER',   TRUE),
('DRIVER_DANGEROUS_DRIVING', 'DRIVER',   TRUE),
('DRIVER_LATE_PICKUP',       'DRIVER',   TRUE),
('DRIVER_WRONG_ROUTE',       'DRIVER',   TRUE),
('VEHICLE_UNCLEAN',          'VEHICLE',  TRUE),
('VEHICLE_CONDITION_ISSUE',  'VEHICLE',  TRUE),
('VEHICLE_WRONG_VEHICLE',    'VEHICLE',  TRUE),
('USER_HARASSMENT_REPORTED_BY_DRIVER', 'USER', TRUE), -- Reported by driver about user
('USER_NO_SHOW_REPORTED_BY_DRIVER',    'USER', TRUE), -- Reported by driver about user
('USER_DAMAGE_TO_VEHICLE',   'USER',     TRUE), -- Reported by driver about user
('BOOKING_ROUTE_ISSUE',      'BOOKING',  TRUE),
('BOOKING_PRICE_DISCREPANCY','BOOKING',  TRUE),
('BOOKING_WRONG_ADDRESS',    'BOOKING',  TRUE),
('PROPERTY_CLEANLINESS',     'PROPERTY', TRUE),
('PROPERTY_MISLEADING_INFO', 'PROPERTY', TRUE),
('OTHER_ISSUE',              'OTHER',    TRUE)
ON CONFLICT (reason_code) DO UPDATE SET
    applies_to_entity = excluded.applies_to_entity,
    is_active         = excluded.is_active;

-- Seed report reason translations
INSERT INTO public.lkp_report_reasons_translations (reason_code, language_code, description) VALUES
('DRIVER_RUDE_BEHAVIOR',    'tr', 'Sürücünün Kaba Davranışı'),
('DRIVER_RUDE_BEHAVIOR',    'en', 'Driver''s Rude Behavior'),
('DRIVER_DANGEROUS_DRIVING','tr', 'Sürücünün Tehlikeli Araç Kullanımı'),
('DRIVER_DANGEROUS_DRIVING','en', 'Driver''s Dangerous Driving'),
('DRIVER_LATE_PICKUP',      'tr', 'Sürücünün Alış Noktasına Geç Gelmesi'),
('DRIVER_LATE_PICKUP',      'en', 'Driver Late for Pickup'),
('DRIVER_WRONG_ROUTE',      'tr', 'Sürücü Yanlış Güzergah Kullandı'),
('DRIVER_WRONG_ROUTE',      'en', 'Driver Took Wrong Route'),
('VEHICLE_UNCLEAN',         'tr', 'Aracın Temiz Olmaması'),
('VEHICLE_UNCLEAN',         'en', 'Vehicle Was Unclean'),
('VEHICLE_CONDITION_ISSUE', 'tr', 'Araç Kondisyonuyla İlgili Sorun'),
('VEHICLE_CONDITION_ISSUE', 'en', 'Issue with Vehicle Condition'),
('VEHICLE_WRONG_VEHICLE',   'tr', 'Gelen Araç Farklıydı'),
('VEHICLE_WRONG_VEHICLE',   'en', 'Different Vehicle Arrived'),
('USER_HARASSMENT_REPORTED_BY_DRIVER', 'tr', 'Yolcunun Rahatsız Edici Davranışı (Sürücü Raporu)'),
('USER_HARASSMENT_REPORTED_BY_DRIVER', 'en', 'Passenger Harassment (Reported by Driver)'),
('USER_NO_SHOW_REPORTED_BY_DRIVER',    'tr', 'Yolcu Gelmedi (Sürücü Raporu)'),
('USER_NO_SHOW_REPORTED_BY_DRIVER',    'en', 'Passenger No-Show (Reported by Driver)'),
('USER_DAMAGE_TO_VEHICLE',  'tr', 'Yolcu Araca Zarar Verdi (Sürücü Raporu)'),
('USER_DAMAGE_TO_VEHICLE',  'en', 'Passenger Damaged Vehicle (Reported by Driver)'),
('BOOKING_ROUTE_ISSUE',     'tr', 'Güzergahla İlgili Sorun'),
('BOOKING_ROUTE_ISSUE',     'en', 'Issue with Route'),
('BOOKING_PRICE_DISCREPANCY','tr', 'Fiyat Uyuşmazlığı'),
('BOOKING_PRICE_DISCREPANCY','en', 'Price Discrepancy'),
('BOOKING_WRONG_ADDRESS',   'tr', 'Yanlış Adres Bilgisi'),
('BOOKING_WRONG_ADDRESS',   'en', 'Incorrect Address Information'),
('PROPERTY_CLEANLINESS',    'tr', 'Tesis Temizliği'),
('PROPERTY_CLEANLINESS',    'en', 'Property Cleanliness'),
('PROPERTY_MISLEADING_INFO','tr', 'Tesis Yanıltıcı Bilgi'),
('PROPERTY_MISLEADING_INFO','en', 'Property Misleading Information'),
('OTHER_ISSUE',             'tr', 'Diğer Sorun'),
('OTHER_ISSUE',             'en', 'Other Issue')
ON CONFLICT (reason_code, language_code) DO NOTHING;


-- ============================================================================
-- 16. Bid Rejection Reasons & Translations (lkp_bid_rejection_reasons, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_bid_rejection_reasons (
    reason_code VARCHAR(50) PRIMARY KEY,
    actor_type  VARCHAR(10) CHECK (actor_type IN ('USER', 'SYSTEM')), -- Who rejected the bid?
    is_active   BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_bid_rejection_reasons 
    IS '[VoyaGo][Lookup][Bidding] Standard reasons for rejecting a received bid.';

CREATE TABLE IF NOT EXISTS public.lkp_bid_rejection_reasons_translations (
    reason_code     VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    description     TEXT        NOT NULL, -- User/System facing text for the rejection reason
    PRIMARY KEY (reason_code, language_code)
);
COMMENT ON TABLE public.lkp_bid_rejection_reasons_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for bid rejection reasons.';

-- Foreign Key Constraints for Bid Rejection Reason Translations
ALTER TABLE public.lkp_bid_rejection_reasons_translations
DROP CONSTRAINT IF EXISTS fk_lkp_bid_rej_reas_trans_reason,
DROP CONSTRAINT IF EXISTS fk_lkp_bid_rej_reas_trans_lang;
ALTER TABLE public.lkp_bid_rejection_reasons_translations
ADD CONSTRAINT fk_lkp_bid_rej_reas_trans_reason
FOREIGN KEY (reason_code)
REFERENCES public.lkp_bid_rejection_reasons(reason_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_bid_rej_reas_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_bid_rejection_reasons_translations_lang
ON public.lkp_bid_rejection_reasons_translations(language_code);

-- Seed bid rejection reasons
INSERT INTO public.lkp_bid_rejection_reasons (reason_code, actor_type, is_active) VALUES
('USER_REJECT_PRICE_TOO_HIGH',     'USER',   TRUE),
('USER_REJECT_DRIVER_RATING_LOW',  'USER',   TRUE),
('USER_REJECT_VEHICLE_UNSUITABLE', 'USER',   TRUE),
('USER_REJECT_ETA_TOO_LONG',       'USER',   TRUE),
('SYSTEM_REJECT_TIME_EXPIRED',     'SYSTEM', TRUE), -- System rejected automatically due to timeout
('OTHER_USER_REASON',              'USER',   TRUE)  -- User provided a custom reason
ON CONFLICT (reason_code) DO UPDATE SET
    actor_type = excluded.actor_type,
    is_active  = excluded.is_active;

-- Seed bid rejection reason translations
INSERT INTO public.lkp_bid_rejection_reasons_translations (reason_code, language_code, description) VALUES
('USER_REJECT_PRICE_TOO_HIGH',     'tr', 'Teklif Edilen Fiyat Çok Yüksek'),
('USER_REJECT_PRICE_TOO_HIGH',     'en', 'Offered Price Too High'),
('USER_REJECT_DRIVER_RATING_LOW',  'tr', 'Sürücü Puanı Düşük'),
('USER_REJECT_DRIVER_RATING_LOW',  'en', 'Driver Rating Too Low'),
('USER_REJECT_VEHICLE_UNSUITABLE', 'tr', 'Önerilen Araç Uygun Değil'),
('USER_REJECT_VEHICLE_UNSUITABLE', 'en', 'Proposed Vehicle Unsuitable'),
('USER_REJECT_ETA_TOO_LONG',       'tr', 'Tahmini Varış Süresi Çok Uzun'),
('USER_REJECT_ETA_TOO_LONG',       'en', 'Estimated Time of Arrival Too Long'),
('SYSTEM_REJECT_TIME_EXPIRED',     'tr', 'Teklif Süresi Doldu (Sistem)'),
('SYSTEM_REJECT_TIME_EXPIRED',     'en', 'Offer Time Expired (System)'),
('OTHER_USER_REASON',              'tr', 'Diğer (Kullanıcı Belirtti)'),
('OTHER_USER_REASON',              'en', 'Other (User Specified)')
ON CONFLICT (reason_code, language_code) DO NOTHING;


-- ============================================================================
-- 17. Bid Request Cancellation Reasons & Translations (lkp_bid_cancellation_reasons, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_bid_cancellation_reasons (
    reason_code VARCHAR(50) PRIMARY KEY,
    actor_type  VARCHAR(10) CHECK (actor_type IN ('USER', 'SYSTEM')), -- Who cancelled the bid request?
    is_active   BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_bid_cancellation_reasons 
    IS '[VoyaGo][Lookup][Bidding] Standard reasons for cancelling a bid request before acceptance.';

CREATE TABLE IF NOT EXISTS public.lkp_bid_cancellation_reasons_translations (
    reason_code     VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    description     TEXT        NOT NULL, -- User/System facing text for the cancellation reason
    PRIMARY KEY (reason_code, language_code)
);
COMMENT ON TABLE public.lkp_bid_cancellation_reasons_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for bid request cancellation reasons.';

-- Foreign Key Constraints for Bid Cancellation Reason Translations
ALTER TABLE public.lkp_bid_cancellation_reasons_translations
DROP CONSTRAINT IF EXISTS fk_lkp_bid_canc_reas_trans_reason,
DROP CONSTRAINT IF EXISTS fk_lkp_bid_canc_reas_trans_lang;
ALTER TABLE public.lkp_bid_cancellation_reasons_translations
ADD CONSTRAINT fk_lkp_bid_canc_reas_trans_reason
FOREIGN KEY (reason_code)
REFERENCES public.lkp_bid_cancellation_reasons(reason_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_bid_canc_reas_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_bid_cancellation_reasons_translations_lang
ON public.lkp_bid_cancellation_reasons_translations(language_code);

-- Seed bid cancellation reasons
INSERT INTO public.lkp_bid_cancellation_reasons (reason_code, actor_type, is_active) VALUES
('USER_CANCEL_NO_LONGER_NEEDS',    'USER',   TRUE),
('USER_CANCEL_FOUND_ALTERNATIVE',  'USER',   TRUE),
('SYSTEM_CANCEL_NO_BIDS_RECEIVED', 'SYSTEM', TRUE), -- System cancelled automatically
('SYSTEM_CANCEL_TIMEOUT',          'SYSTEM', TRUE), -- System cancelled automatically
('SYSTEM_CANCEL_ADMIN_ACTION',     'SYSTEM', TRUE)  -- Cancelled manually by admin
ON CONFLICT (reason_code) DO UPDATE SET
    actor_type = excluded.actor_type,
    is_active  = excluded.is_active;

-- Seed bid cancellation reason translations
INSERT INTO public.lkp_bid_cancellation_reasons_translations (reason_code, language_code, description) VALUES
('USER_CANCEL_NO_LONGER_NEEDS',    'tr', 'Kullanıcı Artık İhtiyaç Duymuyor'),
('USER_CANCEL_NO_LONGER_NEEDS',    'en', 'User No Longer Needs Service'),
('USER_CANCEL_FOUND_ALTERNATIVE',  'tr', 'Kullanıcı Alternatif Bir Çözüm Buldu'),
('USER_CANCEL_FOUND_ALTERNATIVE',  'en', 'User Found an Alternative Solution'),
('SYSTEM_CANCEL_NO_BIDS_RECEIVED', 'tr', 'Sistem: Hiç Teklif Alınmadı'),
('SYSTEM_CANCEL_NO_BIDS_RECEIVED', 'en', 'System: No Bids Received'),
('SYSTEM_CANCEL_TIMEOUT',          'tr', 'Sistem: Zaman Aşımı'),
('SYSTEM_CANCEL_TIMEOUT',          'en', 'System: Timeout'),
('SYSTEM_CANCEL_ADMIN_ACTION',     'tr', 'Sistem: Yönetici İptali'),
('SYSTEM_CANCEL_ADMIN_ACTION',     'en', 'System: Canceled by Admin')
ON CONFLICT (reason_code, language_code) DO NOTHING;


-- ============================================================================
-- 18. Emission Factors (lkp_emission_factors)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_emission_factors (
    factor_id           SERIAL      PRIMARY KEY,
    mode_identifier     TEXT        NOT NULL, -- Correlates to vehicle type codes, service codes, etc.
    factor_type         VARCHAR(10) NOT NULL DEFAULT 'PerKm' CHECK (factor_type IN ('PerKm', 'PerHour', 'PerTrip')),
    -- CO2 equivalent grams per unit (km, hour, trip)
    co2e_grams_per_unit NUMERIC(10,4) NOT NULL CHECK (co2e_grams_per_unit >= 0),
    data_source         TEXT,       -- Source of the emission factor data (e.g., DEFRA 2024)
    region_scope        CHAR(2),    -- Optional ISO 3166-1 country code if factor is region-specific
    valid_from          DATE        DEFAULT '1900-01-01', -- Validity start date of the factor
    valid_to            DATE        DEFAULT '9999-12-31', -- Validity end date of the factor
    is_active           BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_emission_factors 
    IS '[VoyaGo][Lookup][Sustainability] Stores CO2e emission factors for 
        different transport modes/types, potentially region and time specific.';

-- Foreign Key Constraint for Region Scope
ALTER TABLE public.lkp_emission_factors
DROP CONSTRAINT IF EXISTS fk_lkp_emission_factors_region;
ALTER TABLE public.lkp_emission_factors
ADD CONSTRAINT fk_lkp_emission_factors_region
FOREIGN KEY (region_scope)
REFERENCES public.lkp_countries(country_code)
ON DELETE SET NULL -- Keep factor if country is deleted, but lose region specificity
DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of emission factors
CREATE INDEX IF NOT EXISTS idx_lkp_emission_factors_lookup
ON public.lkp_emission_factors(mode_identifier, region_scope, factor_type, is_active, valid_to DESC);

-- Seed emission factors (Examples, replace with actual data)
INSERT INTO public.lkp_emission_factors
(mode_identifier, factor_type, co2e_grams_per_unit, data_source, region_scope, is_active) VALUES
('SEDAN_ECO',        'PerKm', 120.50, 'DEFRA 2024',           'GB', TRUE),
('SEDAN_COMFORT',    'PerKm', 150.00, 'DEFRA 2024',           'GB', TRUE),
('SEDAN_ELECTRIC',   'PerKm',   5.00, 'TR Grid Avg Estimate', 'TR', TRUE), -- Example TR specific
('SUV_STANDARD',     'PerKm', 180.00, 'DEFRA 2024',           'GB', TRUE),
('E_SCOOTER_V1',     'PerKm',   8.00, 'Lifecycle Estimate',   NULL, TRUE), -- Generic factor
('WALK',             'PerKm',   0.00, 'Standard',             NULL, TRUE),
('CARGO_BIKE',       'PerKm',   2.00, 'Estimate',             NULL, TRUE),
('PUBLIC_TRANSPORT_BUS', 'PerKm', 105.00, 'DEFRA 2024 (Avg Bus)', 'GB', TRUE), -- Example for public transport
('PUBLIC_TRANSPORT_RAIL_TR','PerKm', 35.00, 'TCDD Report Estimate','TR', TRUE)  -- Example TR rail
ON CONFLICT (factor_id) DO UPDATE SET -- Assuming factor_id is unique identifier for updates if needed
    mode_identifier     = excluded.mode_identifier,
    factor_type         = excluded.factor_type,
    co2e_grams_per_unit = excluded.co2e_grams_per_unit,
    data_source         = excluded.data_source,
    region_scope        = excluded.region_scope,
    valid_from          = excluded.valid_from,
    valid_to            = excluded.valid_to,
    is_active           = excluded.is_active;


-- ============================================================================
-- 19. Status Transitions (lkp_status_transitions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_status_transitions (
    transition_id       SERIAL      PRIMARY KEY,
    entity_type         VARCHAR(50) NOT NULL, -- Type of entity this transition applies to (e.g., Booking, Driver)
    from_status         TEXT        NOT NULL, -- The status being transitioned from ('*' can represent any status)
    to_status           TEXT        NOT NULL, -- The status being transitioned to
    -- Specific role required to perform this transition (NULL = any allowed actor)
    allowed_role        public.APP_ROLE NULL,
    condition_function  TEXT        NULL,     -- Optional function name to call for additional validation logic
    is_active           BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_status_transitions 
    IS '[VoyaGo][Lookup][Advanced] Defines the allowed state transitions 
        for various entities, enforcing business logic.';

-- Seed status transitions (Examples, expand as needed)
-- Using TEXT for statuses allows referencing ENUM values without strict type dependency here,
-- actual validation happens in application logic or condition functions.
INSERT INTO public.lkp_status_transitions
(entity_type, from_status, to_status, allowed_role, condition_function, is_active) VALUES
-- Booking Transitions
('Booking', 'PENDING_CONFIRMATION', 'CONFIRMED',         'SYSTEM', 'vg_check_booking_payment_status', TRUE),
('Booking', 'PENDING_CONFIRMATION', 'FAILED',            'SYSTEM', NULL, TRUE), -- e.g., Payment failed
('Booking', 'CONFIRMED',            'DRIVER_ASSIGNED',   'SYSTEM', NULL, TRUE),
('Booking', 'CONFIRMED',            'CANCELLED_BY_USER', 'USER',   'vg_check_cancellation_window', TRUE),
('Booking', 'DRIVER_ASSIGNED',      'EN_ROUTE_PICKUP',   'DRIVER', NULL, TRUE),
('Booking', 'DRIVER_ASSIGNED',      'CANCELLED_BY_DRIVER','DRIVER',NULL, TRUE),
('Booking', 'EN_ROUTE_PICKUP',      'ARRIVED_PICKUP',    'DRIVER', NULL, TRUE),
('Booking', 'ARRIVED_PICKUP',       'IN_PROGRESS',       'DRIVER', NULL, TRUE),
('Booking', 'ARRIVED_PICKUP',       'NO_SHOW',           'DRIVER', NULL, TRUE), -- Driver marks no-show
('Booking', 'IN_PROGRESS',          'COMPLETED',         'DRIVER', NULL, TRUE),
('Booking', '*',                    'CANCELLED_BY_ADMIN','ADMIN',  NULL, TRUE), -- Admin can cancel from any state

-- Booking Leg Transitions
('BookingLeg', 'PLANNED',         'ASSIGNED',        'SYSTEM', NULL, TRUE),
('BookingLeg', 'ASSIGNED',        'EN_ROUTE_ORIGIN', 'DRIVER', NULL, TRUE),
('BookingLeg', 'EN_ROUTE_ORIGIN', 'ARRIVED_ORIGIN',  'DRIVER', NULL, TRUE),
('BookingLeg', 'ARRIVED_ORIGIN',  'IN_PROGRESS',     'DRIVER', NULL, TRUE),
('BookingLeg', 'IN_PROGRESS',     'COMPLETED',       'DRIVER', NULL, TRUE),
('BookingLeg', '*',               'CANCELLED',       'SYSTEM', NULL, TRUE), -- System/Admin cancel
('BookingLeg', '*',               'SKIPPED',         'DRIVER', NULL, TRUE), -- Driver skips a leg

-- Driver Status Transitions
('Driver', 'ACTIVE',    'ON_TRIP',   'SYSTEM', NULL, TRUE), -- System assigns trip
('Driver', 'ON_TRIP',   'ACTIVE',    'SYSTEM', NULL, TRUE), -- System completes trip
('Driver', 'ACTIVE',    'OFFLINE',   'DRIVER', NULL, TRUE),
('Driver', 'OFFLINE',   'ACTIVE',    'DRIVER', NULL, TRUE),
('Driver', '*',         'SUSPENDED', 'ADMIN',  NULL, TRUE),
('Driver', 'SUSPENDED', 'ACTIVE',    'ADMIN',  NULL, TRUE)
ON CONFLICT (transition_id) DO UPDATE SET -- Use transition_id for potential updates
    entity_type        = excluded.entity_type,
    from_status        = excluded.from_status,
    to_status          = excluded.to_status,
    allowed_role       = excluded.allowed_role,
    condition_function = excluded.condition_function,
    is_active          = excluded.is_active;

-- Index for efficient lookup of transitions
CREATE INDEX IF NOT EXISTS idx_lkp_status_transitions_lookup
ON public.lkp_status_transitions(entity_type, from_status, is_active);


-- ============================================================================
-- 20. Room Amenities & Translations (lkp_room_amenities, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_room_amenities (
    amenity_code    VARCHAR(50) PRIMARY KEY,
    icon_url        TEXT,
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_room_amenities 
    IS '[VoyaGo][Lookup][Accommodation] Defines amenities available within accommodation rooms.';

CREATE TABLE IF NOT EXISTS public.lkp_room_amenities_translations (
    amenity_code    VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    PRIMARY KEY (amenity_code, language_code)
);
COMMENT ON TABLE public.lkp_room_amenities_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for room amenity names.';

-- Foreign Key Constraints for Room Amenity Translations
ALTER TABLE public.lkp_room_amenities_translations
DROP CONSTRAINT IF EXISTS fk_lkp_room_amen_trans_amenity,
DROP CONSTRAINT IF EXISTS fk_lkp_room_amen_trans_lang;
ALTER TABLE public.lkp_room_amenities_translations
ADD CONSTRAINT fk_lkp_room_amen_trans_amenity
FOREIGN KEY (amenity_code)
REFERENCES public.lkp_room_amenities(amenity_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_room_amen_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_room_amenities_translations_lang
ON public.lkp_room_amenities_translations(language_code);

-- Seed room amenities
INSERT INTO public.lkp_room_amenities (amenity_code, icon_url, is_active) VALUES
('WIFI',             '/icons/wifi.png', TRUE),
('AC',               '/icons/ac.png',   TRUE),
('TV',               '/icons/tv.png',   TRUE),
('PRIVATE_BATHROOM', NULL,              TRUE),
('KITCHENETTE',      NULL,              TRUE),
('BALCONY',          NULL,              TRUE),
('PET_FRIENDLY',     '/icons/pets.png', TRUE)
ON CONFLICT (amenity_code) DO NOTHING;

-- Seed room amenity translations
INSERT INTO public.lkp_room_amenities_translations (amenity_code, language_code, name) VALUES
('WIFI',             'tr', 'Kablosuz İnternet'),
('WIFI',             'en', 'Wireless Internet'),
('AC',               'tr', 'Klima'),
('AC',               'en', 'Air Conditioning'),
('TV',               'tr', 'Televizyon'),
('TV',               'en', 'Television'),
('PRIVATE_BATHROOM', 'tr', 'Özel Banyo'),
('PRIVATE_BATHROOM', 'en', 'Private Bathroom'),
('KITCHENETTE',      'tr', 'Mini Mutfak'),
('KITCHENETTE',      'en', 'Kitchenette'),
('BALCONY',          'tr', 'Balkon'),
('BALCONY',          'en', 'Balcony'),
('PET_FRIENDLY',     'tr', 'Evcil Hayvan Kabul Edilir'),
('PET_FRIENDLY',     'en', 'Pet Friendly')
ON CONFLICT (amenity_code, language_code) DO NOTHING;


-- ============================================================================
-- 21. Property Features & Translations (lkp_property_features, _translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_property_features (
    feature_code    VARCHAR(50) PRIMARY KEY,
    icon_url        TEXT,
    category        VARCHAR(30), -- Optional category (e.g., RECREATION, FACILITIES)
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_property_features 
    IS '[VoyaGo][Lookup][Accommodation] Defines features available at accommodation properties (e.g., Pool, Gym).';

CREATE TABLE IF NOT EXISTS public.lkp_property_features_translations (
    feature_code    VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    PRIMARY KEY (feature_code, language_code)
);
COMMENT ON TABLE public.lkp_property_features_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for property feature names.';

-- Foreign Key Constraints for Property Feature Translations
ALTER TABLE public.lkp_property_features_translations
DROP CONSTRAINT IF EXISTS fk_lkp_prop_feat_trans_feat,
DROP CONSTRAINT IF EXISTS fk_lkp_prop_feat_trans_lang;
ALTER TABLE public.lkp_property_features_translations
ADD CONSTRAINT fk_lkp_prop_feat_trans_feat
FOREIGN KEY (feature_code)
REFERENCES public.lkp_property_features(feature_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_prop_feat_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_property_features_translations_lang
ON public.lkp_property_features_translations(language_code);

-- Seed property features
INSERT INTO public.lkp_property_features (feature_code, icon_url, category, is_active) VALUES
('POOL',            '/icons/pool.png',       'RECREATION', TRUE),
('GYM',             '/icons/gym.png',        'RECREATION', TRUE),
('PARKING',         '/icons/parking.png',    'FACILITIES', TRUE),
('RESTAURANT',      '/icons/restaurant.png', 'FOOD',       TRUE),
('SPA',             '/icons/spa.png',        'WELLNESS',   TRUE),
('AIRPORT_SHUTTLE', NULL,                    'TRANSPORT',  TRUE)
ON CONFLICT (feature_code) DO NOTHING;

-- Seed property feature translations
INSERT INTO public.lkp_property_features_translations (feature_code, language_code, name) VALUES
('POOL',            'tr', 'Yüzme Havuzu'),
('POOL',            'en', 'Swimming Pool'),
('GYM',             'tr', 'Spor Salonu'),
('GYM',             'en', 'Gym'),
('PARKING',         'tr', 'Otopark'),
('PARKING',         'en', 'Parking'),
('RESTAURANT',      'tr', 'Restoran'),
('RESTAURANT',      'en', 'Restaurant'),
('SPA',             'tr', 'Spa Merkezi'),
('SPA',             'en', 'Spa Center'),
('AIRPORT_SHUTTLE', 'tr', 'Havaalanı Servisi'),
('AIRPORT_SHUTTLE', 'en', 'Airport Shuttle')
ON CONFLICT (feature_code, language_code) DO NOTHING;


COMMIT;
-- ============================================================================
-- End of original file: 004_lookup_data_part3.sql
-- ============================================================================
