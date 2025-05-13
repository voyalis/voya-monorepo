-- ============================================================================
-- Migration: 003_lookup_data_part2.sql (Version 2.3 / Part 2 of 4)
-- Description: Populates initial lookup tables - Part 2.
-- Scope:
--   - Units of Measure (lkp_uom, lkp_uom_translations)
--   - Zone Types (lkp_zone_types, lkp_zone_types_translations)
--   - Loyalty Tiers (lkp_loyalty_tiers, lkp_loyalty_tiers_translations)
--   - Badges (lkp_badges, lkp_badges_translations)
--   - Challenges (lkp_challenges, lkp_challenges_translations)
--   - Maintenance Types (lkp_maintenance_types, lkp_maintenance_types_translations)
--   - Payment Providers (lkp_payment_providers, lkp_payment_providers_translations)
-- Author: VoyaGo Team
-- ============================================================================

BEGIN;

-- ============================================================================
-- 8. Units of Measure (lkp_uom, lkp_uom_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_uom (
    uom_code    VARCHAR(20) PRIMARY KEY, -- Code for the unit of measure (e.g., DISTANCE_KM)
    is_active   BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_uom 
    IS '[VoyaGo][Lookup] Defines standard units of measure used across the application.';

CREATE TABLE IF NOT EXISTS public.lkp_uom_translations (
    uom_code        VARCHAR(20) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL, -- Full name of the unit (e.g., Kilometer)
    abbreviation    VARCHAR(10),          -- Common abbreviation (e.g., km)
    PRIMARY KEY (uom_code, language_code)
);
COMMENT ON TABLE public.lkp_uom_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations and abbreviations for units of measure.';

-- Foreign Key Constraints for UoM Translations
ALTER TABLE public.lkp_uom_translations
DROP CONSTRAINT IF EXISTS fk_lkp_uom_trans_uom,
DROP CONSTRAINT IF EXISTS fk_lkp_uom_trans_lang;
ALTER TABLE public.lkp_uom_translations
ADD CONSTRAINT fk_lkp_uom_trans_uom
FOREIGN KEY (uom_code)
REFERENCES public.lkp_uom(uom_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_uom_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_uom_translations_lang
ON public.lkp_uom_translations(language_code);

-- Seed units of measure
INSERT INTO public.lkp_uom (uom_code, is_active) VALUES
('DISTANCE_KM',    TRUE),
('DISTANCE_MILE',  TRUE),
('TIME_HOUR',      TRUE),
('TIME_MINUTE',    TRUE),
('TIME_SECOND',    TRUE),
('WEIGHT_KG',      TRUE),
('WEIGHT_LB',      TRUE),
('VOLUME_M3',      TRUE),
('VOLUME_FT3',     TRUE),
('QUANTITY_PIECE', TRUE),
('CURRENCY_POINT', TRUE) -- For loyalty points etc.
ON CONFLICT (uom_code) DO NOTHING;

-- Seed unit of measure translations
INSERT INTO public.lkp_uom_translations (uom_code, language_code, name, abbreviation) VALUES
('DISTANCE_KM',    'tr', 'Kilometre',    'km'),
('DISTANCE_KM',    'en', 'Kilometer',    'km'),
('DISTANCE_MILE',  'tr', 'Mil',          'mil'),
('DISTANCE_MILE',  'en', 'Mile',         'mi'),
('TIME_HOUR',      'tr', 'Saat',         'sa'),
('TIME_HOUR',      'en', 'Hour',         'hr'),
('TIME_MINUTE',    'tr', 'Dakika',       'dk'),
('TIME_MINUTE',    'en', 'Minute',       'min'),
('TIME_SECOND',    'tr', 'Saniye',       'sn'),
('TIME_SECOND',    'en', 'Second',       'sec'),
('WEIGHT_KG',      'tr', 'Kilogram',     'kg'),
('WEIGHT_KG',      'en', 'Kilogram',     'kg'),
('WEIGHT_LB',      'tr', 'Libre',        'lb'),
('WEIGHT_LB',      'en', 'Pound',        'lb'),
('VOLUME_M3',      'tr', 'Metreküp',     'm³'),
('VOLUME_M3',      'en', 'Cubic Meter',  'm³'),
('VOLUME_FT3',     'tr', 'Kübik Fit',    'ft³'),
('VOLUME_FT3',     'en', 'Cubic Foot',   'ft³'),
('QUANTITY_PIECE', 'tr', 'Adet',         'adet'),
('QUANTITY_PIECE', 'en', 'Piece',        'pc'),
('CURRENCY_POINT', 'tr', 'Puan',         'puan'),
('CURRENCY_POINT', 'en', 'Point',        'pts')
ON CONFLICT (uom_code, language_code) DO NOTHING;


-- ============================================================================
-- 9. Zone Types & Translations (lkp_zone_types, lkp_zone_types_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_zone_types (
    zone_type_code  VARCHAR(30) PRIMARY KEY, -- Code for the geographic zone type
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_zone_types 
    IS '[VoyaGo][Lookup] Defines types of geographic zones used for pricing, operations, etc.';

CREATE TABLE IF NOT EXISTS public.lkp_zone_types_translations (
    zone_type_code  VARCHAR(30) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (zone_type_code, language_code)
);
COMMENT ON TABLE public.lkp_zone_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for geographic zone types.';

-- Foreign Key Constraints for Zone Type Translations
ALTER TABLE public.lkp_zone_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_zone_types_trans_zone,
DROP CONSTRAINT IF EXISTS fk_lkp_zone_types_trans_lang;
ALTER TABLE public.lkp_zone_types_translations
ADD CONSTRAINT fk_lkp_zone_types_trans_zone
FOREIGN KEY (zone_type_code)
REFERENCES public.lkp_zone_types(zone_type_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_zone_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_zone_types_translations_lang
ON public.lkp_zone_types_translations(language_code);

-- Seed zone types
INSERT INTO public.lkp_zone_types (zone_type_code, is_active) VALUES
('OPERATIONAL_AREA',     TRUE), -- General service area
('PRICING_SURGE_ZONE',   TRUE), -- Zone for dynamic pricing
('NO_PICKUP_ZONE',       TRUE), -- Pickups disallowed
('NO_DROPOFF_ZONE',      TRUE), -- Dropoffs disallowed
('AIRPORT_ZONE',         TRUE), -- Special airport rules/pricing
('CITY_CENTER_ZONE',     TRUE), -- Special city center rules/pricing
('RESTRICTED_AREA',      TRUE), -- General restricted access area
('LOW_EMISSION_ZONE',    TRUE)  -- Low Emission Zone (LEZ)
ON CONFLICT (zone_type_code) DO NOTHING;

-- Seed zone type translations
INSERT INTO public.lkp_zone_types_translations (zone_type_code, language_code, name, description) VALUES
('OPERATIONAL_AREA',   'tr', 'Operasyon Alanı',         'Hizmetin aktif olduğu genel bölge'),
('OPERATIONAL_AREA',   'en', 'Operational Area',        'General area where service is active'),
('PRICING_SURGE_ZONE', 'tr', 'Yoğunluk Fiyat Bölgesi',  'Dinamik fiyat çarpanlarının uygulandığı bölge'),
('PRICING_SURGE_ZONE', 'en', 'Pricing Surge Zone',      'Area where dynamic pricing multipliers apply'),
('NO_PICKUP_ZONE',     'tr', 'Alış Yapılamaz Bölge',    'Bu bölgeden yolcu alışı yapılamaz'),
('NO_PICKUP_ZONE',     'en', 'No Pickup Zone',          'Passenger pickup is not allowed in this zone'),
('NO_DROPOFF_ZONE',    'tr', 'Bırakma Yapılamaz Bölge', 'Bu bölgeye yolcu bırakılamaz'),
('NO_DROPOFF_ZONE',    'en', 'No Dropoff Zone',         'Passenger dropoff is not allowed in this zone'),
('AIRPORT_ZONE',       'tr', 'Havalimanı Bölgesi',      'Havalimanı ve çevresi özel kurallar'),
('AIRPORT_ZONE',       'en', 'Airport Zone',            'Area with special rules for airport'),
('CITY_CENTER_ZONE',   'tr', 'Şehir Merkezi Bölgesi',   'Şehir merkezi özel kurallar'),
('CITY_CENTER_ZONE',   'en', 'City Center Zone',        'Defined area for city center rules'),
('RESTRICTED_AREA',    'tr', 'Kısıtlı Alan',            'Girişin yasak olduğu alan'),
('RESTRICTED_AREA',    'en', 'Restricted Area',         'Area where entry is prohibited'),
('LOW_EMISSION_ZONE',  'tr', 'Düşük Emisyon Bölgesi',   'Düşük emisyonlu araç bölgesi'),
('LOW_EMISSION_ZONE',  'en', 'Low Emission Zone',       'Area restricted to low emission vehicles')
ON CONFLICT (zone_type_code, language_code) DO NOTHING;


-- ============================================================================
-- 10. Loyalty Tiers & Translations (lkp_loyalty_tiers, lkp_loyalty_tiers_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_loyalty_tiers (
    tier_code   VARCHAR(20) PRIMARY KEY,
    level       SMALLINT    NOT NULL UNIQUE CHECK (level >= 0), -- Hierarchy level (0 = base)
    min_points  INTEGER     NOT NULL CHECK (min_points >= 0), -- Minimum points required for this tier
    benefits    JSONB,      -- JSON object describing tier benefits (e.g., {"discount_pct": 5})
    is_active   BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_loyalty_tiers 
    IS '[VoyaGo][Lookup][Gamification] Defines tiers within the user loyalty program.';

CREATE TABLE IF NOT EXISTS public.lkp_loyalty_tiers_translations (
    tier_code       VARCHAR(20) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (tier_code, language_code)
);
COMMENT ON TABLE public.lkp_loyalty_tiers_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for loyalty tier names and descriptions.';

-- Foreign Key Constraints for Loyalty Tier Translations
ALTER TABLE public.lkp_loyalty_tiers_translations
DROP CONSTRAINT IF EXISTS fk_lkp_loyalty_tiers_trans_tier,
DROP CONSTRAINT IF EXISTS fk_lkp_loyalty_tiers_trans_lang;
ALTER TABLE public.lkp_loyalty_tiers_translations
ADD CONSTRAINT fk_lkp_loyalty_tiers_trans_tier
FOREIGN KEY (tier_code)
REFERENCES public.lkp_loyalty_tiers(tier_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_loyalty_tiers_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_loyalty_tiers_translations_lang
ON public.lkp_loyalty_tiers_translations(language_code);

-- GIN index for efficient querying of JSONB benefits
CREATE INDEX IF NOT EXISTS idx_gin_lkp_loyalty_tiers_benefits
ON public.lkp_loyalty_tiers USING gin(benefits);

-- Seed loyalty tiers
INSERT INTO public.lkp_loyalty_tiers (tier_code, level, min_points, benefits, is_active) VALUES
('BRONZE',   0, 0,     '{"priority_support": false}', TRUE),
('SILVER',   1, 1000,  '{"discount_pct": 5, "priority_support": false}', TRUE),
('GOLD',     2, 5000,  '{"discount_pct": 10, "priority_support": true, "free_cancellation_hours": 1}', TRUE),
(
    'PLATINUM',
    3,
    15000,
    '{"discount_pct": 15, "priority_support": true, "free_cancellation_hours": 3, "exclusive_offers": true}',
    TRUE
)
ON CONFLICT (tier_code) DO UPDATE SET
    level      = excluded.level,
    min_points = excluded.min_points,
    benefits   = excluded.benefits,
    is_active  = excluded.is_active;
-- Add UNIQUE constraint on level if not already handled by UNIQUE INDEX
ALTER TABLE public.lkp_loyalty_tiers ADD CONSTRAINT uq_lkp_loyalty_tiers_level UNIQUE (level);


-- Seed loyalty tier translations
INSERT INTO public.lkp_loyalty_tiers_translations (tier_code, language_code, name, description) VALUES
('BRONZE',   'tr', 'Bronz',    'Başlangıç seviyesi'),
('BRONZE',   'en', 'Bronze',   'Starting level'),
('SILVER',   'tr', 'Gümüş',    'İndirimler başlasın'),
('SILVER',   'en', 'Silver',   'Start earning discounts'),
('GOLD',     'tr', 'Altın',    'Öncelikli destek'),
('GOLD',     'en', 'Gold',     'Priority support'),
('PLATINUM', 'tr', 'Platin',   'Özel avantajlar'),
('PLATINUM', 'en', 'Platinum', 'Exclusive benefits')
ON CONFLICT (tier_code, language_code) DO NOTHING;


-- ============================================================================
-- 11. Badges & Translations (lkp_badges, lkp_badges_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_badges (
    badge_code      VARCHAR(50) PRIMARY KEY,
    icon_url        TEXT,
    criteria        JSONB,      -- JSON describing the criteria to earn the badge
    is_repeatable   BOOLEAN     DEFAULT FALSE NOT NULL, -- Can this badge be earned multiple times?
    category        VARCHAR(30), -- Optional category for grouping badges (e.g., Completion, Eco)
    is_active       BOOLEAN     DEFAULT TRUE  NOT NULL
);
COMMENT ON TABLE public.lkp_badges 
    IS '[VoyaGo][Lookup][Gamification] Defines achievable badges and their earning criteria.';

CREATE TABLE IF NOT EXISTS public.lkp_badges_translations (
    badge_code      VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (badge_code, language_code)
);
COMMENT ON TABLE public.lkp_badges_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for badge names and descriptions.';

-- Foreign Key Constraints for Badge Translations
ALTER TABLE public.lkp_badges_translations
DROP CONSTRAINT IF EXISTS fk_lkp_badges_trans_badge,
DROP CONSTRAINT IF EXISTS fk_lkp_badges_trans_lang;
ALTER TABLE public.lkp_badges_translations
ADD CONSTRAINT fk_lkp_badges_trans_badge
FOREIGN KEY (badge_code)
REFERENCES public.lkp_badges(badge_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_badges_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_badges_translations_lang
ON public.lkp_badges_translations(language_code);

-- GIN index for efficient querying of JSONB criteria
CREATE INDEX IF NOT EXISTS idx_gin_lkp_badges_criteria
ON public.lkp_badges USING gin(criteria);

-- Seed badges
INSERT INTO public.lkp_badges (badge_code, icon_url, criteria, is_repeatable, category, is_active) VALUES
(
    'FIRST_RIDE_COMPLETED', '/icons/badge_first_ride.png',
    '{"event": "trip_completed", "count": 1}', FALSE, 'Completion', TRUE
),
(
    'FIVE_STAR_PASSENGER', '/icons/badge_5star_passenger.png',
    '{"condition": "AND", "rules": [{"field": "avg_rating_as_passenger", "operator": ">=", "value": 4.8}, 
    {"field": "trips_completed", "operator": ">=", "value": 10}]}',
    FALSE,
    'Rating',
    TRUE
),
(
    'GREEN_COMMUTER_LVL1', '/icons/badge_green_1.png',
    '{"event": "trip_completed", 
    "filter": {"service_code_in": ["MICROMOBILITY","PUBLIC_TRANSPORT","SEDAN_ELECTRIC"]}, "count": 10}',
    FALSE,
    'Eco',
    TRUE
),
(
    'GREEN_COMMUTER_LVL2', '/icons/badge_green_2.png',
    '{"event": "trip_completed", 
    "filter": {"service_code_in": ["MICROMOBILITY","PUBLIC_TRANSPORT","SEDAN_ELECTRIC"]}, "count": 50}',
    FALSE,
    'Eco',
    TRUE
),
(
    'NIGHT_OWL_EXPLORER', '/icons/badge_night_owl.png',
    '{"event": "trip_completed", "filter": {"time_range": {"start": "22:00", "end": "05:00"}}, "count": 5}',
    TRUE,
    'Time',
    TRUE
),
(
    'CITY_EXPLORER_IST', '/icons/badge_city_ist.png',
    '{"event": "trip_completed", "filter": {"zone_type": "CITY_CENTER_ZONE", "city": "Istanbul"}, "count": 3}',
    FALSE,
    'Location',
    TRUE
)
ON CONFLICT (badge_code) DO UPDATE SET
    icon_url      = excluded.icon_url,
    criteria      = excluded.criteria,
    is_repeatable = excluded.is_repeatable,
    category      = excluded.category,
    is_active     = excluded.is_active;

-- Seed badge translations
INSERT INTO public.lkp_badges_translations (badge_code, language_code, name, description) VALUES
('FIRST_RIDE_COMPLETED', 'tr', 'İlk Yolculuk', 'VoyaGo ile ilk yolculuğunu tamamladın!'),
('FIRST_RIDE_COMPLETED', 'en', 'First Ride Completed', 'You completed your first trip with VoyaGo!'),
('FIVE_STAR_PASSENGER', 'tr', '5 Yıldızlı Yolcu', 'Yolcu olarak yüksek puan ortalaması yakaladın.'),
('FIVE_STAR_PASSENGER', 'en', '5-Star Passenger', 'You achieved a high average rating as a passenger.'),
('GREEN_COMMUTER_LVL1', 'tr', 'Yeşil Gezgin (Seviye 1)', '10 kez çevre dostu ulaşım kullandın.'),
('GREEN_COMMUTER_LVL1', 'en', 'Green Commuter (Level 1)', 'You used eco-friendly transport 10 times.'),
('GREEN_COMMUTER_LVL2', 'tr', 'Yeşil Gezgin (Seviye 2)', '50 kez çevre dostu ulaşım kullandın!'),
('GREEN_COMMUTER_LVL2', 'en', 'Green Commuter (Level 2)', 'You used eco-friendly transport 50 times!'),
('NIGHT_OWL_EXPLORER', 'tr', 'Gece Kaşifi', 'Gece saatlerinde 5 yolculuk tamamladın.'),
('NIGHT_OWL_EXPLORER', 'en', 'Night Owl Explorer', 'You completed 5 trips during night hours.'),
('CITY_EXPLORER_IST', 'tr', 'İstanbul Kaşifi', 'İstanbul şehir merkezinde 3 yolculuk yaptın.'),
('CITY_EXPLORER_IST', 'en', 'Istanbul Explorer', 'You completed 3 trips in Istanbul city center.')
ON CONFLICT (badge_code, language_code) DO NOTHING;


-- ============================================================================
-- 12. Challenges & Translations (lkp_challenges, lkp_challenges_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_challenges (
    challenge_code      VARCHAR(50) PRIMARY KEY,
    -- Points awarded upon completion
    reward_points       INTEGER     CHECK (reward_points IS NULL OR reward_points > 0),
    criteria            JSONB,      -- JSON describing the criteria to complete the challenge
    reward_badge_code   VARCHAR(50), -- Optional badge awarded upon completion
    start_date          TIMESTAMPTZ, -- Challenge start validity date/time
    end_date            TIMESTAMPTZ, -- Challenge end validity date/time
    is_recurring        BOOLEAN     DEFAULT FALSE NOT NULL, -- Does the challenge repeat?
    recurring_interval  INTERVAL,   -- If recurring, specifies the interval (e.g., '7 days')
    is_active           BOOLEAN     DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_challenges 
    IS '[VoyaGo][Lookup][Gamification] Defines timed or recurring challenges for users.';

CREATE TABLE IF NOT EXISTS public.lkp_challenges_translations (
    challenge_code  VARCHAR(50) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL,
    description     TEXT,
    PRIMARY KEY (challenge_code, language_code)
);
COMMENT ON TABLE public.lkp_challenges_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for challenge names and descriptions.';

-- Foreign Key Constraints for Challenges
ALTER TABLE public.lkp_challenges
DROP CONSTRAINT IF EXISTS fk_lkp_challenges_badge;
ALTER TABLE public.lkp_challenges
ADD CONSTRAINT fk_lkp_challenges_badge
FOREIGN KEY (reward_badge_code)
REFERENCES public.lkp_badges(badge_code)
ON DELETE SET NULL -- Keep challenge even if badge is deleted
DEFERRABLE INITIALLY DEFERRED;

-- Foreign Key Constraints for Challenge Translations
ALTER TABLE public.lkp_challenges_translations
DROP CONSTRAINT IF EXISTS fk_lkp_challenges_trans_challenge,
DROP CONSTRAINT IF EXISTS fk_lkp_challenges_trans_lang;
ALTER TABLE public.lkp_challenges_translations
ADD CONSTRAINT fk_lkp_challenges_trans_challenge
FOREIGN KEY (challenge_code)
REFERENCES public.lkp_challenges(challenge_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_challenges_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_challenges_translations_lang
ON public.lkp_challenges_translations(language_code);

-- GIN index for efficient querying of JSONB criteria
CREATE INDEX IF NOT EXISTS idx_gin_lkp_challenges_criteria
ON public.lkp_challenges USING gin(criteria);

-- Seed challenges
INSERT INTO public.lkp_challenges
(
    challenge_code,
    reward_points,
    criteria,
    reward_badge_code,
    start_date,
    end_date,
    is_recurring,
    recurring_interval,
    is_active
) VALUES
(
    'WEEKLY_3_TRIPS', 150,
    '{"event": "trip_completed", "count": 3, "time_window": "current_week"}',
    NULL, date_trunc('week', current_timestamp), NULL, TRUE, '7 days', TRUE
),
(
    'MONTHLY_100KM_ECO', 500,
    '{"condition": "AND", "rules": [{"event": "trip_completed", 
    "aggregate": {"field": "distance_km", "function": "SUM"}, 
    "value": 100, "time_window": "current_month"}, 
    {"filter": {"vehicle_is_electric": true}}]}',
    'GREEN_COMMUTER_LVL1',
    date_trunc('month', current_timestamp),
    date_trunc('month', current_timestamp) + INTERVAL '1 month - 1 second',
    FALSE,
    NULL,
    TRUE
),
(
    'FIRST_INTERCITY_TRIP', 250,
    '{"event": "trip_completed", "filter": {"service_code": "INTERCITY"}, "count": 1}',
    NULL, NULL, NULL, FALSE, NULL, TRUE
)
ON CONFLICT (challenge_code) DO UPDATE SET
    reward_points      = excluded.reward_points,
    criteria           = excluded.criteria,
    reward_badge_code  = excluded.reward_badge_code,
    start_date         = excluded.start_date,
    end_date           = excluded.end_date,
    is_recurring       = excluded.is_recurring,
    recurring_interval = excluded.recurring_interval,
    is_active          = excluded.is_active;

-- Seed challenge translations
INSERT INTO public.lkp_challenges_translations
(challenge_code, language_code, name, description) VALUES
('WEEKLY_3_TRIPS', 'tr', 'Haftalık 3 Yolculuk', 'Bu hafta 3 VoyaGo yolculuğu tamamla, 150 puan kazan!'),
('WEEKLY_3_TRIPS', 'en', 'Complete 3 Trips This Week', 'Complete 3 VoyaGo trips this week and earn 150 points!'),
(
    'MONTHLY_100KM_ECO',
    'tr',
    'Aylık 100 km Yeşil Yolculuk',
    'Bu ay elektrikli araçlarla 100 km yol yap, 500 puan ve rozet kazan!'
),
(
    'MONTHLY_100KM_ECO',
    'en',
    'Monthly 100 km Eco Travel',
    'Travel 100 km with electric vehicles this month and earn 500 points and a badge!'
),
(
    'FIRST_INTERCITY_TRIP',
    'tr',
    'İlk Şehirlerarası Yolculuk',
    'İlk şehirlerarası yolculuğunu tamamla, 250 puan kazan!'
),
('FIRST_INTERCITY_TRIP', 'en', 'First Intercity Trip', 'Complete your first intercity trip and earn 250 points!')
ON CONFLICT (challenge_code, language_code) DO NOTHING;


-- ============================================================================
-- 13. Maintenance Types & Translations (lkp_maintenance_types, lkp_maintenance_types_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_maintenance_types (
    maintenance_code    VARCHAR(50) PRIMARY KEY,
    default_interval    INTERVAL,   -- Default time interval for this maintenance type
    -- Default KM interval
    default_km_interval INTEGER     CHECK (default_km_interval IS NULL OR default_km_interval > 0),
    applicable_entity   VARCHAR(10) DEFAULT 'VEHICLE' NOT NULL CHECK (applicable_entity IN ('VEHICLE', 'EQUIPMENT')),
    is_active           BOOLEAN     DEFAULT TRUE    NOT NULL
);
COMMENT ON TABLE public.lkp_maintenance_types 
IS '[VoyaGo][Lookup][Fleet] Defines standard types of maintenance tasks for vehicles or equipment.';

CREATE TABLE IF NOT EXISTS public.lkp_maintenance_types_translations (
    maintenance_code    VARCHAR(50) NOT NULL,
    language_code       CHAR(2)     NOT NULL,
    name                TEXT        NOT NULL,
    description         TEXT,
    PRIMARY KEY (maintenance_code, language_code)
);
COMMENT ON TABLE public.lkp_maintenance_types_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for maintenance type names and descriptions.';

-- Foreign Key Constraints for Maintenance Type Translations
ALTER TABLE public.lkp_maintenance_types_translations
DROP CONSTRAINT IF EXISTS fk_lkp_maint_types_trans_maint,
DROP CONSTRAINT IF EXISTS fk_lkp_maint_types_trans_lang;
ALTER TABLE public.lkp_maintenance_types_translations
ADD CONSTRAINT fk_lkp_maint_types_trans_maint
FOREIGN KEY (maintenance_code)
REFERENCES public.lkp_maintenance_types(maintenance_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_maint_types_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_maintenance_types_translations_lang
ON public.lkp_maintenance_types_translations(language_code);

-- Seed maintenance types
INSERT INTO public.lkp_maintenance_types
(maintenance_code, default_interval, default_km_interval, applicable_entity, is_active) VALUES
('PERIODIC_15K',            NULL,       15000, 'VEHICLE', TRUE), -- e.g., Standard 15k service
('OIL_CHANGE',              '6 months', 10000, 'VEHICLE', TRUE),
('TIRE_ROTATION',           '6 months', 10000, 'VEHICLE', TRUE),
('ANNUAL_INSPECTION_PREP',  '1 year',   NULL,  'VEHICLE', TRUE), -- Prep for gov inspection
('BRAKE_PAD_REPLACEMENT',   NULL,       50000, 'VEHICLE', TRUE),
('BATTERY_CHECK_EV',        '1 year',   NULL,  'VEHICLE', TRUE)  -- Specific to Electric Vehicles
ON CONFLICT (maintenance_code) DO UPDATE SET
    default_interval    = excluded.default_interval,
    default_km_interval = excluded.default_km_interval,
    applicable_entity   = excluded.applicable_entity,
    is_active           = excluded.is_active;

-- Seed maintenance type translations
INSERT INTO public.lkp_maintenance_types_translations
(maintenance_code, language_code, name, description) VALUES
('PERIODIC_15K', 'tr', 'Periyodik 15 000 KM Bakımı', 'Aracın 15 000 km periyodik bakımı'),
('PERIODIC_15K', 'en', 'Periodic 15 000 KM Service', 'Vehicle periodic service at 15 000 km'),
('OIL_CHANGE', 'tr', 'Yağ Değişimi', 'Motor yağı ve filtre değişimi'),
('OIL_CHANGE', 'en', 'Oil Change', 'Engine oil and filter replacement'),
('TIRE_ROTATION', 'tr', 'Lastik Rotasyonu', 'Lastiklerin yerlerinin değiştirilmesi'),
('TIRE_ROTATION', 'en', 'Tire Rotation', 'Rotating vehicle tires'),
('ANNUAL_INSPECTION_PREP', 'tr', 'Yıllık Muayene Hazırlık', 'Zorunlu araç muayenesi öncesi kontroller'),
('ANNUAL_INSPECTION_PREP', 'en', 'Annual Inspection Preparation', 'Checks before mandatory vehicle inspection'),
('BRAKE_PAD_REPLACEMENT', 'tr', 'Fren Balatası Değişimi', 'Aşınan fren balatalarının yenilenmesi'),
('BRAKE_PAD_REPLACEMENT', 'en', 'Brake Pad Replacement', 'Replacement of worn brake pads'),
('BATTERY_CHECK_EV', 'tr', 'EV Batarya Kontrolü', 'Elektrikli araç batarya sağlık kontrolü'),
('BATTERY_CHECK_EV', 'en', 'EV Battery Check', 'Electric vehicle battery health check')
ON CONFLICT (maintenance_code, language_code) DO NOTHING;


-- ============================================================================
-- 14. Payment Providers & Translations (lkp_payment_providers, lkp_payment_providers_translations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.lkp_payment_providers (
    provider_code   VARCHAR(30) PRIMARY KEY,
    website         TEXT,       -- Provider's official website
    capabilities    TEXT[],     -- Array of capabilities (e.g., CARD, 3DSECURE, INSTALLMENT)
    is_active       BOOLEAN DEFAULT TRUE NOT NULL
);
COMMENT ON TABLE public.lkp_payment_providers 
    IS '[VoyaGo][Lookup][Finance] Defines integrated payment gateway providers.';

CREATE TABLE IF NOT EXISTS public.lkp_payment_providers_translations (
    provider_code   VARCHAR(30) NOT NULL,
    language_code   CHAR(2)     NOT NULL,
    name            TEXT        NOT NULL, -- Display name for the provider
    PRIMARY KEY (provider_code, language_code)
);
COMMENT ON TABLE public.lkp_payment_providers_translations 
    IS '[VoyaGo][Lookup][I18n] Provides translations for payment provider names.';

-- Foreign Key Constraints for Payment Provider Translations
ALTER TABLE public.lkp_payment_providers_translations
DROP CONSTRAINT IF EXISTS fk_lkp_pay_prov_trans_prov,
DROP CONSTRAINT IF EXISTS fk_lkp_pay_prov_trans_lang;
ALTER TABLE public.lkp_payment_providers_translations
ADD CONSTRAINT fk_lkp_pay_prov_trans_prov
FOREIGN KEY (provider_code)
REFERENCES public.lkp_payment_providers(provider_code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_lkp_pay_prov_trans_lang
FOREIGN KEY (language_code)
REFERENCES public.lkp_languages(code)
ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Index for efficient lookup of translations by language
CREATE INDEX IF NOT EXISTS idx_lkp_payment_providers_translations_lang
ON public.lkp_payment_providers_translations(language_code);

-- Seed payment providers
INSERT INTO public.lkp_payment_providers (provider_code, website, capabilities, is_active) VALUES
('STRIPE',       'https://stripe.com',      ARRAY['CARD','3DSECURE','WALLET_PAY'],            TRUE),
('IYZICO',       'https://www.iyzico.com',  ARRAY['CARD','3DSECURE','INSTALLMENT','BANK_TRANSFER'], TRUE),
('PAYTR',        'https://www.paytr.com',   ARRAY['CARD','3DSECURE','INSTALLMENT'],            TRUE),
-- Internal wallet
('VOYAGOWALLET', NULL,                      ARRAY['WALLET'],                                  TRUE)
ON CONFLICT (provider_code) DO UPDATE SET
    website      = excluded.website,
    capabilities = excluded.capabilities,
    is_active    = excluded.is_active;

-- Seed payment provider translations
INSERT INTO public.lkp_payment_providers_translations (provider_code, language_code, name) VALUES
('STRIPE',       'tr', 'Stripe'),
('STRIPE',       'en', 'Stripe'),
('IYZICO',       'tr', 'Iyzico'),
('IYZICO',       'en', 'Iyzico'),
('PAYTR',        'tr', 'PayTR'),
('PAYTR',        'en', 'PayTR'),
('VOYAGOWALLET', 'tr', 'VoyaGo Cüzdan'),
('VOYAGOWALLET', 'en', 'VoyaGo Wallet')
ON CONFLICT (provider_code, language_code) DO NOTHING;


COMMIT;
-- ============================================================================
-- End of original file: 003_lookup_data_part2.sql
-- ============================================================================
