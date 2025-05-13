-- ============================================================================
-- Migration: 020_gamification.sql (Version 1.2 - Added booking_created_at for FKs)
-- Description: VoyaGo - Gamification & Loyalty: Badge Definitions, User Stats,
--              Point Transactions, User Badges, Challenges, Progress,
--              Leaderboards, and History tables. Adds partition key for FKs.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 002_lookup_data_*.sql,
--               003_core_user.sql, 010_booking_core.sql, 017_promotions_discounts.sql
-- ============================================================================

BEGIN;

-- Prefixes 'gam_' and 'loyalty_' denote tables related to Gamification and Loyalty.
-- Note: Assumes separate 'gamification' points tracked in gam_user_stats/gam_point_transactions
--       and 'loyalty' points tracked in core_user_profiles/loyalty_transactions.

-------------------------------------------------------------------------------
-- 1. Badge Definitions (gam_badge_definitions)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_badge_definitions (
    badge_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Unique code for referencing the badge internally (e.g., 'FIRST_RIDE', 'ECO_WARRIOR_L1')
    badge_code      VARCHAR(50) NOT NULL UNIQUE,
    -- User-facing name (Consider using a lookup/translation table like lkp_badges if multi-language)
    name            VARCHAR(100) NOT NULL,
    -- User-facing description (Consider using a lookup/translation table)
    description     TEXT NULL,
    -- Criteria for earning the badge defined as JSONB
    criteria        JSONB NOT NULL CHECK (jsonb_typeof(criteria) = 'object'),
    -- Reference to the badge icon (e.g., Storage URL or asset key)
    icon_ref        TEXT NULL,
    -- Can this badge be earned multiple times by the same user? (Added in v1.1)
    is_repeatable   BOOLEAN DEFAULT FALSE NOT NULL,
    is_active       BOOLEAN DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.gam_badge_definitions
    IS '[VoyaGo][Gamification] Defines badges available in the system and their earning criteria.';
COMMENT ON COLUMN public.gam_badge_definitions.criteria
    IS '[VoyaGo] Badge earning criteria as JSONB. 
        Example: {"event": "trip_completed", "count": 1}, {"total_points_earned": 1000}';
COMMENT ON COLUMN public.gam_badge_definitions.is_repeatable
    IS 'Indicates if a user can earn this badge more than once.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_gam_badge_definitions ON public.gam_badge_definitions;
CREATE TRIGGER trg_set_timestamp_on_gam_badge_definitions
    BEFORE UPDATE ON public.gam_badge_definitions
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Badge Definitions
CREATE INDEX IF NOT EXISTS idx_gam_badge_defs_active ON public.gam_badge_definitions(is_active);
-- Index for querying criteria
CREATE INDEX IF NOT EXISTS idx_gin_gam_badge_defs_criteria
    ON public.gam_badge_definitions USING GIN(criteria);


-------------------------------------------------------------------------------
-- 1.1 Badge Definitions History (gam_badge_definitions_history)
-- Description: Audit trail for changes to gam_badge_definitions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_badge_definitions_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    badge_id        UUID NOT NULL,      -- The badge definition that was changed
    badge_data      JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.gam_badge_definitions_history
    IS '[VoyaGo][Gamification][History] Audit log capturing changes to badge definitions.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_gam_badge_defs_hist_bid
    ON public.gam_badge_definitions_history(badge_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Badge Definitions History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_gam_badge_def_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.gam_badge_definitions_history
            (action_type, actor_id, badge_id, badge_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.badge_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_gam_badge_def_history()
    IS '[VoyaGo][Gamification][TriggerFn] Logs previous state of gam_badge_definitions row to
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_gam_badge_def_history ON public.gam_badge_definitions;
CREATE TRIGGER audit_gam_badge_def_history
    AFTER UPDATE OR DELETE ON public.gam_badge_definitions
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_gam_badge_def_history();


-------------------------------------------------------------------------------
-- 2. User Gamification Stats (gam_user_stats) - Added in v1.1
-- Description: Stores aggregated gamification statistics for each user.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_user_stats (
    -- Links to the user (FK defined later, ON DELETE CASCADE)
    user_id             UUID PRIMARY KEY,
    -- Current gamification point balance (distinct from loyalty points)
    current_points      INTEGER DEFAULT 0 NOT NULL CHECK (current_points >= 0),
    -- Current gamification level
    current_level       INTEGER DEFAULT 1 NOT NULL CHECK (current_level >= 1),
    -- Lifetime total points earned (for level progression, leaderboards)
    total_points_earned BIGINT DEFAULT 0 NOT NULL CHECK (total_points_earned >= 0),
    updated_at          TIMESTAMPTZ NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.gam_user_stats
    IS '[VoyaGo][Gamification] Stores current points, level, 
        and lifetime earned points for each user in the gamification system.';
COMMENT ON COLUMN public.gam_user_stats.current_points
    IS 'The user''s current spendable gamification point balance.';
COMMENT ON COLUMN public.gam_user_stats.total_points_earned
    IS 'Cumulative total of all gamification points ever earned by the user.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_gam_user_stats ON public.gam_user_stats;
CREATE TRIGGER trg_set_timestamp_on_gam_user_stats
    BEFORE UPDATE ON public.gam_user_stats
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for User Stats
-- Index for leaderboard ranking by points
CREATE INDEX IF NOT EXISTS idx_gam_user_stats_points ON public.gam_user_stats(current_points DESC);
-- Index for finding users by level
CREATE INDEX IF NOT EXISTS idx_gam_user_stats_level ON public.gam_user_stats(current_level DESC);


-------------------------------------------------------------------------------
-- 3. Gamification Point Transactions (gam_point_transactions) - ** booking_created_at ADDED **
-- Description: Logs individual gamification point earning/spending events.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_point_transactions (
    transaction_id      BIGSERIAL       PRIMARY KEY,
    user_id             UUID            NOT NULL,   -- User involved (FK defined later)
    -- Type of point transaction (ENUM from 001)
    change_type         public.gam_transaction_type NOT NULL,
    -- Amount of points changed (+ for earn, - for spend/expire)
    points_delta        INTEGER         NOT NULL CHECK (points_delta != 0),
    -- User's point balance *after* this transaction (Requires atomic update)
    balance_after       INTEGER         NOT NULL,
    -- Reason code for the transaction (e.g., 'CHALLENGE_COMPLETE', 'REWARD_REDEEMED')
    reason_code         VARCHAR(50)     NULL,
    -- Optional polymorphic link to the related entity triggering the transaction
    related_entity_type VARCHAR(50)     NULL,   -- e.g., 'BOOKING', 'CHALLENGE', 'PROMOTION'
    related_entity_id   TEXT            NULL,   -- ID of the related entity
    -- If related entity is booking_bookings, store partition key
    booking_created_at  TIMESTAMPTZ     NULL,   -- <<< EKLENEN SÜTUN
    description         TEXT            NULL,   -- Optional details about the transaction
    created_at          TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,

    CONSTRAINT chk_gpt_booking_created_at CHECK (
        related_entity_type != 'BOOKING' OR related_entity_id IS NULL OR booking_created_at IS NOT NULL
    )
);
COMMENT ON TABLE public.gam_point_transactions
    IS '[VoyaGo][Gamification] Logs each gamification point transaction 
        (earn, spend, expire, adjustment).';
COMMENT ON COLUMN public.gam_point_transactions.balance_after
    IS '[VoyaGo][Concurrency] User''s gamification point balance AFTER this transaction. 
        Must be updated atomically with gam_user_stats.current_points.';
COMMENT ON COLUMN public.gam_point_transactions.booking_created_at
    IS 'Partition key from booking_bookings, required if related_entity_type is BOOKING 
        and related_entity_id is set.';
COMMENT ON COLUMN public.gam_point_transactions.related_entity_type
    IS 'Type of entity related to this point transaction (e.g., BOOKING, CHALLENGE).';
COMMENT ON COLUMN public.gam_point_transactions.related_entity_id
    IS 'ID of the entity referenced in related_entity_type.';

-- Indexes for Point Transactions
-- Get recent transactions for a user
CREATE INDEX IF NOT EXISTS idx_gam_ptx_user_time
    ON public.gam_point_transactions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gam_ptx_type ON public.gam_point_transactions(change_type);
CREATE INDEX IF NOT EXISTS idx_gam_ptx_reason ON public.gam_point_transactions(reason_code);
-- Find transactions related to a specific entity (polymorphic)
CREATE INDEX IF NOT EXISTS idx_gam_ptx_entity
    ON public.gam_point_transactions(related_entity_type, related_entity_id) WHERE related_entity_id IS NOT NULL;
-- Index for potential composite FK lookup to bookings
CREATE INDEX IF NOT EXISTS idx_gam_ptx_booking
    ON public.gam_point_transactions(related_entity_id, booking_created_at) WHERE related_entity_type = 'BOOKING';


-------------------------------------------------------------------------------
-- 4. User Badges (gam_user_badges)
-- Description: Records badges awarded to users.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_user_badges (
    user_badge_id   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID NOT NULL,      -- User who earned the badge (FK defined later)
    badge_id        UUID NOT NULL,      -- Badge that was earned (FK defined later)
    awarded_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the badge was awarded
    revoked_at      TIMESTAMPTZ NULL,   -- Timestamp if the badge was revoked
    reason          TEXT        NULL    -- Optional reason for revocation
);
COMMENT ON TABLE public.gam_user_badges
    IS '[VoyaGo][Gamification] Records instances of badges being awarded to users.';

-- Ensures a user cannot have the same *active* badge multiple times if the badge is not repeatable.
-- Application logic should check gam_badge_definitions.is_repeatable before awarding.
CREATE UNIQUE INDEX IF NOT EXISTS uq_gam_user_badge_unique_active
    ON public.gam_user_badges(user_id, badge_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX public.uq_gam_user_badge_unique_active
    IS '[VoyaGo][Logic] Prevents a user from having the same active (non-revoked) badge multiple times. 
        Assumes application checks repeatability.';

-- Other Indexes for User Badges
CREATE INDEX IF NOT EXISTS idx_gam_user_badges_user ON public.gam_user_badges(user_id);
CREATE INDEX IF NOT EXISTS idx_gam_user_badges_badge ON public.gam_user_badges(badge_id);


-------------------------------------------------------------------------------
-- 4.1 User Badges History (gam_user_badges_history)
-- Description: Audit trail for badge awards/revocations.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_user_badges_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL, -- INSERT (Awarded), UPDATE (Revoked), DELETE
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,          -- User/System performing action
    user_badge_id   UUID NOT NULL,      -- The user_badge record affected
    badge_data      JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.gam_user_badges_history
    IS '[VoyaGo][Gamification][History] Audit log for user badge awards, revocations, or deletions.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_gam_user_badges_hist_ubid
    ON public.gam_user_badges_history(user_badge_id, action_at DESC);

-------------------------------------------------------------------------------
-- 4.2 User Badges History Trigger Function (Logs UPDATE for Revoke, and DELETE)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_gam_user_badge_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF TG_OP = 'DELETE' THEN
        -- Log deletion
        v_data := to_jsonb(OLD);
        INSERT INTO public.gam_user_badges_history
            (action_type, actor_id, user_badge_id, badge_data)
        VALUES
            ('DELETE', v_actor, OLD.user_badge_id, v_data);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' AND OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
        -- Log revocation (transition from non-revoked to revoked)
        v_data := to_jsonb(OLD);
        INSERT INTO public.gam_user_badges_history
            (action_type, actor_id, user_badge_id, badge_data)
        VALUES
            ('UPDATE', v_actor, OLD.user_badge_id, v_data);
        RETURN NEW;
    END IF;
    -- For other UPDATEs or INSERTs, do nothing in this history trigger
    IF TG_OP = 'UPDATE' THEN RETURN NEW; END IF; -- Allow other updates
    RETURN NULL; -- Should not be reached for DELETE
END;
$$;
COMMENT ON FUNCTION public.vg_log_gam_user_badge_history()
    IS '[VoyaGo][Gamification][TriggerFn] Logs state to history table on DELETE 
        or when a badge is revoked (revoked_at changes from NULL).';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_gam_user_badge_history ON public.gam_user_badges;
CREATE TRIGGER audit_gam_user_badge_history
    AFTER UPDATE OR DELETE ON public.gam_user_badges -- Consider AFTER UPDATE OF revoked_at OR DELETE
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_gam_user_badge_history();


-------------------------------------------------------------------------------
-- 5. Challenge Definitions (gam_challenge_definitions) - Added in v1.1
-- Description: Defines gamification challenges (e.g., complete 3 rides this week).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_challenge_definitions (
    challenge_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    challenge_code      VARCHAR(50) NOT NULL UNIQUE, -- Unique internal code (e.g., 'WEEKLY_3_RIDES')
    -- User-facing name (Consider using lookup/translation table)
    name                VARCHAR(150) NOT NULL,
    -- User-facing description (Consider using lookup/translation table)
    description         TEXT NULL,
    -- Criteria for completing the challenge as JSONB
    criteria            JSONB NOT NULL CHECK (jsonb_typeof(criteria) = 'object'),
    -- Rewards
    reward_points       INTEGER NULL CHECK (reward_points IS NULL OR reward_points > 0),
    reward_badge_id     UUID NULL,          -- Optional badge reward (FK defined later)
    -- Timing
    start_time          TIMESTAMPTZ NULL,   -- When the challenge becomes available
    end_time            TIMESTAMPTZ NULL,   -- When the challenge is no longer available
    is_recurring        BOOLEAN DEFAULT FALSE NOT NULL, -- Does the challenge repeat?
    recurring_interval  INTERVAL NULL,      -- Interval if recurring (e.g., '7 days', '1 month')
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL    -- Automatically updated by trigger
);
COMMENT ON TABLE public.gam_challenge_definitions
    IS '[VoyaGo][Gamification] Defines gamification challenges, 
        their criteria, rewards, and timing.';
COMMENT ON COLUMN public.gam_challenge_definitions.criteria
    IS '[VoyaGo] Challenge completion criteria as JSONB. 
        Example: {"event": "trip_completed", "count": 3, "time_window": "week"}';
COMMENT ON COLUMN public.gam_challenge_definitions.recurring_interval
    IS 'Specifies the interval for recurring challenges 
        (e.g., ''1 day'', ''7 days'', ''1 month'').';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_gam_challenges ON public.gam_challenge_definitions;
CREATE TRIGGER trg_set_timestamp_on_gam_challenges
    BEFORE UPDATE ON public.gam_challenge_definitions
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Challenges
CREATE INDEX IF NOT EXISTS idx_gam_challenges_active_time
    ON public.gam_challenge_definitions(is_active, start_time, end_time); -- Find active challenges
CREATE INDEX IF NOT EXISTS idx_gin_gam_challenges_criteria
    ON public.gam_challenge_definitions USING GIN(criteria); -- Query based on criteria


-------------------------------------------------------------------------------
-- 6. User Challenge Progress (gam_user_challenge_progress) - Added in v1.1
-- Description: Tracks individual user progress towards completing challenges.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_user_challenge_progress (
    progress_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id             UUID NOT NULL,      -- User participating (FK defined later)
    challenge_id        UUID NOT NULL,      -- Challenge being tracked (FK defined later)
    -- Defines the specific instance for recurring challenges
    instance_start_time TIMESTAMPTZ NOT NULL,
    instance_end_time   TIMESTAMPTZ NOT NULL,
    -- Stores current progress against criteria as JSONB
    current_progress    JSONB NULL 
        CHECK (current_progress IS NULL OR jsonb_typeof(current_progress) = 'object'),
    -- Status of the user's progress on this challenge instance (ENUM from 001)
    status              public.gam_challenge_status NOT NULL DEFAULT 'ACTIVE',
    completed_at        TIMESTAMPTZ NULL,   -- Timestamp when completed
    updated_at          TIMESTAMPTZ NULL,   -- Automatically updated by trigger

    -- Ensures unique progress record per user per challenge instance
    CONSTRAINT uq_user_challenge_instance UNIQUE (user_id, challenge_id, instance_start_time)
);
COMMENT ON TABLE public.gam_user_challenge_progress
    IS '[VoyaGo][Gamification] Tracks user progress on specific instances of challenges 
        (especially recurring ones).';
COMMENT ON COLUMN public.gam_user_challenge_progress.instance_start_time
    IS 'Start time of the specific period for which progress is tracked (for recurring challenges).';
COMMENT ON COLUMN public.gam_user_challenge_progress.instance_end_time
    IS 'End time of the specific period for which progress is tracked.';
COMMENT ON COLUMN public.gam_user_challenge_progress.current_progress
    IS '[VoyaGo] Current progress state as JSONB. Example: {"rides_completed": 2, "target_rides": 3}';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_gam_user_challenges ON public.gam_user_challenge_progress;
CREATE TRIGGER trg_set_timestamp_on_gam_user_challenges
    BEFORE UPDATE ON public.gam_user_challenge_progress
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Progress Tracking
CREATE INDEX IF NOT EXISTS idx_gam_user_challenges_user_status
    ON public.gam_user_challenge_progress(user_id, status); -- Find user's active/completed challenges
CREATE INDEX IF NOT EXISTS idx_gam_user_challenges_challenge
    ON public.gam_user_challenge_progress(challenge_id);
CREATE INDEX IF NOT EXISTS idx_gin_gam_user_challenges_progress
    ON public.gam_user_challenge_progress USING GIN(current_progress);


-------------------------------------------------------------------------------
-- 7. Leaderboards (gam_leaderboards)
-- Description: Defines different leaderboards based on various criteria.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_leaderboards (
    leaderboard_id  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Name of the leaderboard (e.g., "Monthly Points", "Eco Warriors")
    name            VARCHAR(100) NOT NULL UNIQUE, 
    description     TEXT         NULL,
    -- Criteria defining the leaderboard (period, metric, filters)
    criteria        JSONB        NULL CHECK (criteria IS NULL OR jsonb_typeof(criteria) = 'object'),
    is_active       BOOLEAN      DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ  DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ  NULL -- Automatically updated by trigger
);
COMMENT ON TABLE public.gam_leaderboards
    IS '[VoyaGo][Gamification] Defines different leaderboards based on 
        specified criteria (e.g., monthly points).';
COMMENT ON COLUMN public.gam_leaderboards.criteria
    IS '[VoyaGo] Criteria for the leaderboard as JSONB. 
        Example: {"period": "MONTHLY", "metric": "total_points_earned", "region": "TR", "min_level": 2}';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_gam_leaderboards ON public.gam_leaderboards;
CREATE TRIGGER trg_set_timestamp_on_gam_leaderboards
    BEFORE UPDATE ON public.gam_leaderboards
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Index for Leaderboards
CREATE INDEX IF NOT EXISTS idx_gam_leaderboards_active ON public.gam_leaderboards(is_active);


-------------------------------------------------------------------------------
-- 7.1 Leaderboard Snapshots (gam_leaderboard_snapshots)
-- Description: Stores periodic snapshots of leaderboard rankings.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.gam_leaderboard_snapshots (
    snapshot_id     BIGSERIAL PRIMARY KEY,
    leaderboard_id  UUID        NOT NULL,   -- Link to the leaderboard definition (FK defined later)
    snapshot_time   TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- When the snapshot was taken
    -- The actual leaderboard data (ranked list) stored as JSONB
    data            JSONB       NOT NULL CHECK (jsonb_typeof(data) = 'array')
);
COMMENT ON TABLE public.gam_leaderboard_snapshots
    IS '[VoyaGo][Gamification] Stores periodic snapshots of leaderboard rankings 
        (assumes calculation happens externally).';
COMMENT ON COLUMN public.gam_leaderboard_snapshots.data
    IS '[VoyaGo] Ranked leaderboard data as a JSONB array. 
        Example: [{"user_id": "uuid", "rank": 1, "value": 15000}, {"user_id": "uuid", "rank": 2, "value": 12500}]';

-- Index for Snapshots
CREATE INDEX IF NOT EXISTS idx_gam_lb_snapshots_lbid_time
    -- Get latest snapshots for a leaderboard
    ON public.gam_leaderboard_snapshots(leaderboard_id, snapshot_time DESC); 


-------------------------------------------------------------------------------
-- 8. Loyalty Transactions (loyalty_transactions) - ** booking_created_at ADDED **
-- Description: Detailed log of loyalty point transactions (distinct from gamification points).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
    transaction_id      BIGSERIAL PRIMARY KEY,
    user_id             UUID NOT NULL,      -- User involved (FK defined later)
    -- Type of loyalty transaction (ENUM from 001)
    transaction_type    public.loyalty_transaction_type NOT NULL,
    -- Change in loyalty points (+ or -)
    points_change       INTEGER NOT NULL CHECK (points_change != 0),
    -- User's loyalty point balance *after* this transaction (Requires atomic update)
    balance_after       INTEGER NOT NULL,
    -- Optional links to related entities (Composite FK for booking)
    related_booking_id  UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    related_promo_id    UUID NULL,          -- Link to promotion if points awarded via promo
    related_challenge_id UUID NULL,         -- Link to challenge if points awarded via challenge
    related_user_id     UUID NULL,          -- Link to referred user if points awarded via referral
    external_ref        TEXT NULL,          -- Optional external reference
    notes               TEXT NULL,          -- Optional notes
    transaction_time    TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,

    CONSTRAINT chk_lt_booking_created_at CHECK (related_booking_id IS NULL 
        OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.loyalty_transactions
    IS '[VoyaGo][Loyalty] Detailed log of all loyalty point transactions 
        (earn, spend, expire, adjust). Assumes loyalty points stored in core_user_profiles.';
COMMENT ON COLUMN public.loyalty_transactions.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key 
        (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.loyalty_transactions.balance_after
    IS '[VoyaGo][Concurrency] User''s loyalty point balance AFTER this transaction. 
        Must be updated atomically with core_user_profiles.loyalty_points_balance.';

-- Indexes for Loyalty Transactions
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_user_time
    ON public.loyalty_transactions(user_id, transaction_time DESC);
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_type ON public.loyalty_transactions(transaction_type);
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_booking
    ON public.loyalty_transactions(related_booking_id, booking_created_at) 
    WHERE related_booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_promo
    ON public.loyalty_transactions(related_promo_id) WHERE related_promo_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_loyalty_tx_challenge
    ON public.loyalty_transactions(related_challenge_id) 
    WHERE related_challenge_id IS NOT NULL;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- gam_badge_definitions_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- gam_badge_definitions_history -> gam_badge_definitions (badge_id -> badge_id) [CASCADE]
--
-- gam_user_stats -> core_user_profiles (user_id -> user_id) [CASCADE]
--
-- gam_point_transactions -> core_user_profiles (user_id -> user_id) [CASCADE]
-- gam_point_transactions -> booking_bookings (booking_created_at, related_entity_id -> 
    --created_at, booking_id) [SET NULL] -- COMPOSITE FK (if type='BOOKING')
-- Note: FK for related_entity_id depends on related_entity_type (Polymorphic).
--
-- gam_user_badges -> core_user_profiles (user_id -> user_id) [CASCADE]
-- gam_user_badges -> gam_badge_definitions (badge_id -> badge_id) [RESTRICT]
--
-- gam_user_badges_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- gam_user_badges_history -> gam_user_badges (user_badge_id -> user_badge_id) [CASCADE]
--
-- gam_challenge_definitions -> gam_badge_definitions (reward_badge_id -> badge_id) [SET NULL]
--
-- gam_user_challenge_progress -> core_user_profiles (user_id -> user_id) [CASCADE]
-- gam_user_challenge_progress -> gam_challenge_definitions (challenge_id -> challenge_id) [CASCADE]
--
-- gam_leaderboard_snapshots -> gam_leaderboards (leaderboard_id -> leaderboard_id) [CASCADE]
--
-- loyalty_transactions -> core_user_profiles (user_id -> user_id) [CASCADE]
-- loyalty_transactions -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [SET NULL] -- COMPOSITE FK
-- loyalty_transactions -> promotions (related_promo_id -> promotion_id) [SET NULL?] 
    -- Requires Promotions module
-- loyalty_transactions -> gam_challenge_definitions (related_challenge_id -> 
    --challenge_id) [SET NULL?]
-- loyalty_transactions -> core_user_profiles (related_user_id -> user_id) [SET NULL?] 
    -- For referrals
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 020_gamification.sql (Version 1.2)
-- ============================================================================
