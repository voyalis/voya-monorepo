-- ============================================================================
-- Migration: 017_promotions_discounts.sql (Version 1.1 - Added booking_created_at for FK)
-- Description: VoyaGo - Promotions & Discounts Module: Campaigns, Discount Codes,
--              Redemption Tracking, and History. Adds partition key for FK.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 002_lookup_data_*.sql,
--               003_core_user.sql, 010_booking_core.sql
-- ============================================================================

BEGIN;

-- Using table prefixes 'promotions_', 'discount_' where logical for clarity.

-------------------------------------------------------------------------------
-- 1. Promotions (promotions)
-- Description: Defines overall campaigns or promotions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promotions (
    promotion_id    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Unique, user-friendly name for the campaign
    name            VARCHAR(100) NOT NULL UNIQUE,
    -- Optional general code associated with the campaign (can be NULL if only specific codes exist)
    code            VARCHAR(50) NULL UNIQUE,
    description     TEXT NULL,
    -- Type of promotion (ENUM from 001)
    promo_type      public.promo_type NOT NULL,
    -- Details of the discount (e.g., percentage or fixed amount)
    discount        JSONB NOT NULL CHECK (jsonb_typeof(discount) = 'object'),
    -- Conditions required for the promotion to apply (e.g., min order value)
    conditions      JSONB NULL CHECK (conditions IS NULL OR jsonb_typeof(conditions) = 'object'),
    -- Validity period
    start_at        TIMESTAMPTZ NOT NULL,
    end_at          TIMESTAMPTZ NULL,
    -- Usage limits
    -- Total usage limit for the entire promotion
    usage_limit     INTEGER NULL CHECK (usage_limit IS NULL OR usage_limit > 0),
    -- Limit per user
    per_user_limit  INTEGER NULL CHECK (per_user_limit IS NULL OR per_user_limit > 0),
    -- Status (ENUM from 001)
    status          public.promo_status NOT NULL DEFAULT 'DRAFT',
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_promo_time CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT chk_promo_discount_format CHECK (jsonb_typeof(discount) = 'object')
);
COMMENT ON TABLE public.promotions
    IS '[VoyaGo][Promo] Defines platform-wide promotions and campaigns.';
COMMENT ON COLUMN public.promotions.code
    IS 'Optional general coupon code associated directly with the promotion.';
COMMENT ON COLUMN public.promotions.discount
    IS '[VoyaGo] Discount details as JSONB. 
        Example: {"percent": 15} or {"amount": 50, "currency": "TRY"}';
COMMENT ON COLUMN public.promotions.conditions
    IS '[VoyaGo] Conditions for eligibility as JSONB. 
        Example: {"min_order_amount": 100, "currency": "TRY", "applies_to_service": ["TRANSFER"]}';
COMMENT ON COLUMN public.promotions.usage_limit
    IS 'Maximum number of times this promotion can be used overall 
        (across all users/codes). NULL for unlimited.';
COMMENT ON COLUMN public.promotions.per_user_limit
    IS 'Maximum number of times a single user can benefit from 
        this promotion. NULL for unlimited.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_promotions ON public.promotions;
CREATE TRIGGER trg_set_timestamp_on_promotions
    BEFORE UPDATE ON public.promotions
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Promotions
CREATE INDEX IF NOT EXISTS idx_promotions_status_time
    ON public.promotions(status, start_at, end_at); -- Find active promotions
CREATE INDEX IF NOT EXISTS idx_gin_promotions_discount
    ON public.promotions USING GIN (discount);
CREATE INDEX IF NOT EXISTS idx_gin_promotions_conditions
    ON public.promotions USING GIN (conditions) WHERE conditions IS NOT NULL;
-- UNIQUE constraint on 'code' already creates an index


-------------------------------------------------------------------------------
-- 1.1 Promotions History (promotions_history)
-- Description: Audit trail for changes to promotions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promotions_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,          -- User making the change
    promotion_id    UUID NOT NULL,      -- The promotion that was changed
    promo_data      JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.promotions_history
    IS '[VoyaGo][Promo][History] Audit log capturing changes to promotions records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_promotions_hist_pid
    ON public.promotions_history(promotion_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Promotions History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_promotions_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.promotions_history
            (action_type, actor_id, promotion_id, promo_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.promotion_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_promotions_history()
    IS '[VoyaGo][Promo][TriggerFn] Logs previous state of promotions 
        row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_promotions_history ON public.promotions;
CREATE TRIGGER audit_promotions_history
    AFTER UPDATE OR DELETE ON public.promotions
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_promotions_history();


-------------------------------------------------------------------------------
-- 2. Discount Codes (discount_codes)
-- Description: Specific discount codes linked to a promotion.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_codes (
    code_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Link to the parent promotion
    promotion_id    UUID NOT NULL,
    -- The actual code entered by the user
    code            VARCHAR(30) NOT NULL UNIQUE,
    -- Can this code be used only once ever?
    single_use      BOOLEAN DEFAULT FALSE NOT NULL,
    expires_at      TIMESTAMPTZ NULL,       -- Optional expiration specific to this code
    -- Current usage count for this specific code
    usage_count     INTEGER DEFAULT 0 NOT NULL CHECK (usage_count >= 0),
    -- Optional usage limit specific to this code (overrides promotion limit if stricter)
    usage_limit     INTEGER NULL CHECK (usage_limit IS NULL OR usage_limit > 0),
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL      -- Automatically updated by trigger
);
COMMENT ON TABLE public.discount_codes
    IS '[VoyaGo][Promo] Specific discount codes associated with a promotion, 
        potentially with their own limits.';
COMMENT ON COLUMN public.discount_codes.usage_count
    IS 'Tracks how many times this specific code has been successfully redeemed. 
        Requires atomic updates.';
COMMENT ON COLUMN public.discount_codes.usage_limit
    IS 'Maximum number of times this specific code can be used. 
        NULL means limited only by the parent promotion''s limit.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_discount_codes ON public.discount_codes;
CREATE TRIGGER trg_set_timestamp_on_discount_codes
    BEFORE UPDATE ON public.discount_codes
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Discount Codes
CREATE INDEX IF NOT EXISTS idx_discount_codes_promo ON public.discount_codes(promotion_id);
CREATE INDEX IF NOT EXISTS idx_discount_codes_expires
    ON public.discount_codes(expires_at) WHERE expires_at IS NOT NULL;
-- UNIQUE constraint on 'code' already creates an index


-------------------------------------------------------------------------------
-- 2.1 Discount Codes History (discount_codes_history)
-- Description: Audit trail for changes to discount_codes.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_codes_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    code_id         UUID NOT NULL,      -- The discount_code that was changed
    code_data       JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.discount_codes_history
    IS '[VoyaGo][Promo][History] Audit log capturing changes to discount_codes records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_dc_hist_cid
    ON public.discount_codes_history(code_id, action_at DESC);

-------------------------------------------------------------------------------
-- 2.2 Discount Codes History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_discount_codes_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.discount_codes_history
            (action_type, actor_id, code_id, code_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.code_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_discount_codes_history()
    IS '[VoyaGo][Promo][TriggerFn] Logs previous state of discount_codes 
        row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_discount_codes_history ON public.discount_codes;
CREATE TRIGGER audit_discount_codes_history
    AFTER UPDATE OR DELETE ON public.discount_codes
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_discount_codes_history();


-------------------------------------------------------------------------------
-- 3. Discount Code Redemptions (discount_code_redemptions) - ** booking_created_at ADDED **
-- Description: Tracks each instance a discount code is successfully used.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_code_redemptions (
    redemption_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code_id             UUID NOT NULL,      -- The discount code used (FK defined later)
    user_id             UUID NOT NULL,      -- The user who redeemed the code (FK defined later)
    -- The booking the code was applied to (Composite FK defined later)
    booking_id          UUID NOT NULL,
    booking_created_at  TIMESTAMPTZ NOT NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    redeemed_at         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the redemption occurred
    actor_id            UUID NULL,  -- Actor performing the redemption (user/system) (FK defined later)
    -- Additional context
    metadata            JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),

    -- Since booking_id is NOT NULL
    CONSTRAINT chk_dcr_booking_created_at CHECK (booking_created_at IS NOT NULL) 
);
COMMENT ON TABLE public.discount_code_redemptions
    IS '[VoyaGo][Promo] Records each successful redemption of a discount code.';
COMMENT ON COLUMN public.discount_code_redemptions.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key.';

-- Indexes for Redemptions
CREATE INDEX IF NOT EXISTS idx_dcr_code ON public.discount_code_redemptions(code_id);
CREATE INDEX IF NOT EXISTS idx_dcr_user ON public.discount_code_redemptions(user_id);
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_dcr_booking
    ON public.discount_code_redemptions(booking_id, booking_created_at);


-------------------------------------------------------------------------------
-- 3.1 Discount Code Redemptions History (discount_code_redemptions_history)
-- Description: Audit trail for deletions of redemption records (updates are unlikely).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.discount_code_redemptions_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL, -- Expected to be mostly DELETE
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    redemption_id   UUID NOT NULL,      -- The redemption record that was changed
    redemption_data JSONB NOT NULL        -- Row data before DELETE
);
COMMENT ON TABLE public.discount_code_redemptions_history
    IS '[VoyaGo][Promo][History] Audit log capturing deletions (primarily) 
        of discount_code_redemptions records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_dcrh_rid
    ON public.discount_code_redemptions_history(redemption_id, action_at DESC);

-------------------------------------------------------------------------------
-- 3.2 Discount Code Redemptions History Trigger Function (DELETE only)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_dcr_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    -- Only log DELETE operations for redemptions, updates are less common/meaningful here
    IF TG_OP = 'DELETE' THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.discount_code_redemptions_history
            (action_type, actor_id, redemption_id, redemption_data)
        VALUES
            ('DELETE', v_actor, OLD.redemption_id, v_data);
        RETURN OLD;
    END IF;
    RETURN NULL; -- Do nothing for INSERT/UPDATE
END;
$$;
COMMENT ON FUNCTION public.vg_log_dcr_history()
    IS '[VoyaGo][Promo][TriggerFn] Logs state of discount_code_redemptions 
        row to history table only on DELETE.';

-- Attach the trigger for DELETE events
DROP TRIGGER IF EXISTS audit_dcr_history ON public.discount_code_redemptions;
CREATE TRIGGER audit_dcr_history
    AFTER DELETE ON public.discount_code_redemptions -- Trigger only on DELETE
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_dcr_history();


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- promotions_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- promotions_history -> promotions (promotion_id -> promotion_id) [CASCADE]
--
-- discount_codes -> promotions (promotion_id -> promotion_id) [CASCADE]
--
-- discount_codes_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- discount_codes_history -> discount_codes (code_id -> code_id) [CASCADE]
--
-- discount_code_redemptions -> discount_codes (code_id -> code_id) [RESTRICT?]
-- discount_code_redemptions -> core_user_profiles (user_id -> user_id) [CASCADE? RESTRICT?]
-- discount_code_redemptions -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- discount_code_redemptions -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- discount_code_redemptions_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- discount_code_redemptions_history -> discount_code_redemptions 
    --(redemption_id -> redemption_id) [CASCADE]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 017_promotions_discounts.sql (Version 1.1)
-- ============================================================================
