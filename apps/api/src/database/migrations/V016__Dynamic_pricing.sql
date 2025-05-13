-- ============================================================================
-- Migration: 016_dynamic_pricing.sql (Version 1.2 - Added Partition Keys for FKs)
-- Description: VoyaGo - Dynamic Pricing Rules Engine & Calculation Logs.
--              Adds partition key columns for composite FKs.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 002_lookup_data_*.sql (Lookups),
--               005_fleet_management.sql (partner ref), 009_geo_location.sql (zone ref),
--               010_booking_core.sql (service_code ref, booking ref),
--               014_micromobility.sql (ride ref)
-- ============================================================================

BEGIN;

-- Prefix 'pricing_' denotes tables related to the Dynamic Pricing module.

-------------------------------------------------------------------------------
-- 1. Pricing Rules (pricing_rules)
-- Description: Defines rules for calculating base fares or price adjustments.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pricing_rules (
    rule_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(100) NOT NULL UNIQUE, -- Human-readable name for the rule
    description         TEXT NULL,
    -- Type of rule (e.g., BASE_FARE, ADJUSTMENT) (ENUM from 001)
    rule_type           public.pricing_rule_type NOT NULL,
    -- Scope/Applicability Filters (NULL means applies generally)
    service_code        public.service_code NULL,       -- Apply to specific service? (ENUM from 001)
    vehicle_category    public.vehicle_category NULL,   -- Apply to specific category? (ENUM from 001)
    partner_id          UUID NULL,                      -- Apply to specific partner? (FK defined later)
    zone_id             UUID NULL,                      -- Apply within specific geo-zone? (FK defined later)
    -- Time condition
    time_window         TSRANGE NULL,                   -- Time range the rule is active (e.g., peak hours)
    -- Additional arbitrary conditions
    conditions          JSONB NULL CHECK (conditions IS NULL OR jsonb_typeof(conditions) = 'object'),
    -- The actual price adjustment or base fare calculation
    adjustment          JSONB NOT NULL CHECK (
        jsonb_typeof(adjustment) = 'object' AND adjustment ? 'type' AND adjustment ? 'value'
    ),
    -- Rule Precedence
    priority            INTEGER DEFAULT 0 NOT NULL,     -- Higher value means higher priority in case of conflicts
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,  -- Is the rule currently active?
    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,               -- Automatically updated by trigger

    -- Constraints
    CONSTRAINT chk_pricing_time_window CHECK (time_window IS NULL OR upper_inf(time_window) 
        OR lower_inf(time_window) OR upper(time_window) > lower(time_window)),
    CONSTRAINT chk_pricing_adjustment_format CHECK (jsonb_typeof(adjustment) = 'object' 
        AND adjustment ? 'type' AND adjustment ? 'value') -- Ensure basic adjustment structure
);
COMMENT ON TABLE public.pricing_rules
    IS '[VoyaGo][Pricing] Defines dynamic and static rules for price calculations based on various dimensions.';
COMMENT ON COLUMN public.pricing_rules.time_window
    IS 'Time range (inclusive lower, exclusive upper) during which this rule applies. 
        Example: ''[2025-05-01 08:00:00+03, 2025-05-01 10:00:00+03)''. Uses TSRANGE type.';
COMMENT ON COLUMN public.pricing_rules.conditions
    IS '[VoyaGo] Additional conditions for the rule as JSONB. 
        Example: {"min_distance_km": 5, "user_segment": "premium"}';
COMMENT ON COLUMN public.pricing_rules.adjustment
    IS '[VoyaGo] Price adjustment details as JSONB. Example: {"type": "PERCENT_INCREASE", "value": 20}, 
        {"type": "FIXED_ADD", "value": 5.00, "currency": "TRY"}, {"type": "SET_FIXED", "value": 50.00, "currency": "TRY"}';
COMMENT ON COLUMN public.pricing_rules.priority
    IS 'Determines which rule takes precedence if multiple rules match the same criteria (higher value wins).';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_pricing_rules ON public.pricing_rules;
CREATE TRIGGER trg_set_timestamp_on_pricing_rules
    BEFORE UPDATE ON public.pricing_rules
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Rules
-- Index for general rule lookup based on scope and priority
CREATE INDEX IF NOT EXISTS idx_pr_rules_lookup
    ON public.pricing_rules(is_active, service_code, rule_type, priority DESC);
-- Indexes for specific scope lookups
CREATE INDEX IF NOT EXISTS idx_pr_rules_zone_priority
    ON public.pricing_rules(zone_id, priority DESC, is_active) WHERE zone_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pr_rules_partner_priority
    ON public.pricing_rules(partner_id, priority DESC, is_active) WHERE partner_id IS NOT NULL;
-- GIST index for time window overlap queries
CREATE INDEX IF NOT EXISTS idx_pr_rules_time_gist
    ON public.pricing_rules USING GIST (time_window) WHERE time_window IS NOT NULL;
COMMENT ON INDEX public.idx_pr_rules_time_gist 
    IS '[VoyaGo][Perf] GIST index to efficiently query rules based on time overlaps.';
-- GIN indexes for JSONB fields
CREATE INDEX IF NOT EXISTS idx_gin_pr_rules_conditions
    ON public.pricing_rules USING GIN (conditions) WHERE conditions IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_pr_rules_adjustment
    ON public.pricing_rules USING GIN (adjustment);


-------------------------------------------------------------------------------
-- 1.1 Pricing Rules History (pricing_rules_history)
-- Description: Audit trail for changes to pricing_rules.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pricing_rules_history (
    history_id      BIGSERIAL       PRIMARY KEY,
    action_type     public.audit_action NOT NULL,   -- INSERT, UPDATE, DELETE
    action_at       TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID            NULL,           -- User making the change
    rule_id         UUID            NOT NULL,       -- The rule that was changed
    rule_data       JSONB           NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.pricing_rules_history
    IS '[VoyaGo][Pricing][History] Audit log capturing changes to pricing_rules records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_pr_rules_hist_rid
    ON public.pricing_rules_history(rule_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Pricing Rules History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_pricing_rules_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.pricing_rules_history
            (action_type, actor_id, rule_id, rule_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.rule_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_pricing_rules_history()
    IS '[VoyaGo][Pricing][TriggerFn] Logs previous state of pricing_rules row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_pricing_rules_history ON public.pricing_rules;
CREATE TRIGGER audit_pricing_rules_history
    AFTER UPDATE OR DELETE ON public.pricing_rules
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_pricing_rules_history();


-------------------------------------------------------------------------------
-- 2. Pricing Calculations Log (pricing_calculations) - ** Partition Key Columns ADDED **
-- Description: Logs the details of each price calculation performed.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pricing_calculations (
    calc_id                     BIGSERIAL       PRIMARY KEY,
    -- Context of the calculation (Composite FKs defined later)
    booking_id                  UUID            NULL,
    booking_created_at          TIMESTAMPTZ     NULL, -- <<< EKLENEN SÜTUN
    ride_id                     UUID            NULL,
    ride_start_time             TIMESTAMPTZ     NULL, -- <<< EKLENEN SÜTUN (e.g., for mm_rides)
    -- Rules Applied (Improved in v1.1)
    -- Array of applied rule IDs and their effects
    applied_rules               JSONB           NULL CHECK (
        applied_rules IS NULL OR jsonb_typeof(applied_rules) = 'array'
    ), 
    -- Calculation Results
    base_fare                   NUMERIC(12,2)   NOT NULL CHECK (base_fare >= 0), -- Starting fare before adjustments
    total_adjustment            NUMERIC(12,2)   NOT NULL DEFAULT 0, -- Net amount added/subtracted by rules
    -- Calculated final fare (base + adjustment)
    final_fare                  NUMERIC(12,2)   NOT NULL CHECK (final_fare >= 0),
    currency_code               CHAR(3)         NOT NULL, -- Currency of the fares
    -- Calculation Metadata
    calculation_engine_version  VARCHAR(20)     NULL,   -- Version of the pricing engine used
    -- Input parameters used (distance, duration etc.)
    details                     JSONB           NULL CHECK (details IS NULL OR jsonb_typeof(details) = 'object'), 
    calculated_at               TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,

    -- Ensure partition keys are present if the corresponding ID is present
    CONSTRAINT chk_pc_booking_created_at CHECK (booking_id IS NULL OR booking_created_at IS NOT NULL),
    CONSTRAINT chk_pc_ride_start_time CHECK (ride_id IS NULL OR ride_start_time IS NOT NULL)

);
COMMENT ON TABLE public.pricing_calculations
    IS '[VoyaGo][Pricing][Log] Detailed log of price calculation events, 
        including applied rules and results.';
COMMENT ON COLUMN public.pricing_calculations.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if booking_id is not NULL).';
COMMENT ON COLUMN public.pricing_calculations.ride_start_time
    IS 'Partition key copied from related ride table (e.g., mm_rides.start_time) 
        for composite foreign key (if ride_id is not NULL).';
COMMENT ON COLUMN public.pricing_calculations.applied_rules
    IS '[VoyaGo] JSONB array detailing the pricing rules applied. 
        Example: [{"rule_id": "uuid-rule-1", "adjustment": {"type": "PERCENT", "value": -10}}, ...]';
COMMENT ON COLUMN public.pricing_calculations.final_fare
    IS 'Final calculated fare after applying all relevant rule adjustments to the base fare.';
COMMENT ON COLUMN public.pricing_calculations.details
    IS '[VoyaGo] Input parameters used for the calculation as JSONB. 
        Example: {"distance_km": 5.2, "duration_min": 15, "zone_ids": ["zone-a"]}';

-- Indexes for Calculation Logs
-- Add indexes for composite FK lookups
CREATE INDEX IF NOT EXISTS idx_pc_booking
    ON public.pricing_calculations(booking_id, booking_created_at) WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pc_ride
    ON public.pricing_calculations(ride_id, ride_start_time) WHERE ride_id IS NOT NULL;
-- GIN index to query which rules were applied
CREATE INDEX IF NOT EXISTS idx_gin_pc_applied_rules
    ON public.pricing_calculations USING GIN (applied_rules) WHERE applied_rules IS NOT NULL;
COMMENT ON INDEX public.idx_gin_pc_applied_rules 
    IS '[VoyaGo][Perf] Allows efficient querying of calculations based on the rules applied.';
CREATE INDEX IF NOT EXISTS idx_pc_time
    ON public.pricing_calculations(calculated_at DESC);
-- GIN index to query calculation details/inputs
CREATE INDEX IF NOT EXISTS idx_gin_pc_details
    ON public.pricing_calculations USING GIN (details) WHERE details IS NOT NULL;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- pricing_rules -> lkp_service_types (service_code -> service_code) [CASCADE? RESTRICT?]
-- pricing_rules -> fleet_partners (partner_id -> partner_id) [CASCADE? RESTRICT?]
-- pricing_rules -> geo_zones (zone_id -> zone_id) [CASCADE? RESTRICT?]
-- Note: pricing_rules.vehicle_category references an ENUM, no FK.
--
-- pricing_rules_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- pricing_rules_history -> pricing_rules (rule_id -> rule_id) [CASCADE]
--
-- pricing_calculations -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- pricing_calculations -> mm_rides (ride_start_time, 
    --ride_id -> start_time, ride_id) [SET NULL?] -- COMPOSITE FK (Example for mm_rides)
-- pricing_calculations -> ??? (ride_id -> other ride tables?) [No Direct FK for polymorphic]
-- pricing_calculations -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- Note: pricing_calculations.applied_rules contains rule IDs but is JSONB, no direct FK.
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 016_dynamic_pricing.sql (Version 1.2)
-- ============================================================================
