
-- ============================================================================
-- Migration: V025.8__Constraints_Promo_Gamification.sql (Version 1.1 - Composite FK Fix) -- Renamed for sequence
-- Description: Add FK constraints for Promotions & Gamification modules.
--              Uses composite FKs for references to partitioned table 'booking_bookings'.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Promo/Gamification tables and referenced tables,
--               including addition of 'booking_created_at' to relevant tables.
--               (e.g., 001..003, 010, 017, 020)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Promotions Drops
ALTER TABLE public.discount_codes DROP CONSTRAINT IF EXISTS fk_dc_promotion;
ALTER TABLE public.discount_code_redemptions DROP CONSTRAINT IF EXISTS fk_dcr_code;
ALTER TABLE public.discount_code_redemptions DROP CONSTRAINT IF EXISTS fk_dcr_user;
ALTER TABLE public.discount_code_redemptions DROP CONSTRAINT IF EXISTS fk_dcr_booking; -- Will be recreated as composite
ALTER TABLE public.discount_code_redemptions DROP CONSTRAINT IF EXISTS fk_dcr_actor;
ALTER TABLE public.promotions_history DROP CONSTRAINT IF EXISTS fk_promo_hist_actor;
ALTER TABLE public.promotions_history DROP CONSTRAINT IF EXISTS fk_promo_hist_promo;
ALTER TABLE public.discount_codes_history DROP CONSTRAINT IF EXISTS fk_dc_hist_actor;
ALTER TABLE public.discount_codes_history DROP CONSTRAINT IF EXISTS fk_dc_hist_code;
ALTER TABLE public.discount_code_redemptions_history DROP CONSTRAINT IF EXISTS fk_dcrh_actor;
ALTER TABLE public.discount_code_redemptions_history DROP CONSTRAINT IF EXISTS fk_dcrh_redemption;

-- Gamification Drops
ALTER TABLE public.gam_user_stats DROP CONSTRAINT IF EXISTS fk_gus_user;
ALTER TABLE public.gam_point_transactions DROP CONSTRAINT IF EXISTS fk_gpt_user;
ALTER TABLE public.gam_point_transactions DROP CONSTRAINT IF EXISTS fk_gpt_booking; -- Will be recreated as composite
ALTER TABLE public.gam_user_badges DROP CONSTRAINT IF EXISTS fk_gub_user;
ALTER TABLE public.gam_user_badges DROP CONSTRAINT IF EXISTS fk_gub_badge;
ALTER TABLE public.gam_badge_definitions_history DROP CONSTRAINT IF EXISTS fk_gbdh_actor;
ALTER TABLE public.gam_badge_definitions_history DROP CONSTRAINT IF EXISTS fk_gbdh_badge;
ALTER TABLE public.gam_challenge_definitions DROP CONSTRAINT IF EXISTS fk_gcd_badge;
ALTER TABLE public.gam_user_challenge_progress DROP CONSTRAINT IF EXISTS fk_gucp_user;
ALTER TABLE public.gam_user_challenge_progress DROP CONSTRAINT IF EXISTS fk_gucp_challenge;
ALTER TABLE public.gam_user_badges_history DROP CONSTRAINT IF EXISTS fk_gubh_actor;
ALTER TABLE public.gam_user_badges_history DROP CONSTRAINT IF EXISTS fk_gubh_user_badge;
ALTER TABLE public.gam_leaderboard_snapshots DROP CONSTRAINT IF EXISTS fk_gls_leaderboard;

-- Loyalty Drops
ALTER TABLE public.loyalty_transactions DROP CONSTRAINT IF EXISTS fk_lt_user;
ALTER TABLE public.loyalty_transactions DROP CONSTRAINT IF EXISTS fk_lt_booking; -- Will be recreated as composite
ALTER TABLE public.loyalty_transactions DROP CONSTRAINT IF EXISTS fk_lt_promo;
ALTER TABLE public.loyalty_transactions DROP CONSTRAINT IF EXISTS fk_lt_challenge;
ALTER TABLE public.loyalty_transactions DROP CONSTRAINT IF EXISTS fk_lt_related_user;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Promotions Module Relationships
ALTER TABLE public.promotions_history
    ADD CONSTRAINT fk_promo_hist_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_promo_hist_promo FOREIGN KEY (promotion_id) REFERENCES public.promotions(
        promotion_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.discount_codes
    ADD CONSTRAINT fk_dc_promotion FOREIGN KEY (promotion_id) REFERENCES public.promotions(
        promotion_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.discount_codes_history
    ADD CONSTRAINT fk_dc_hist_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dc_hist_code FOREIGN KEY (code_id) REFERENCES public.discount_codes(
        code_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM discount_code_redemptions (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.discount_code_redemptions
    ADD CONSTRAINT fk_dcr_code FOREIGN KEY (code_id) REFERENCES public.discount_codes(
        code_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dcr_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dcr_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dcr_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.discount_code_redemptions_history
    ADD CONSTRAINT fk_dcrh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dcrh_redemption FOREIGN KEY (redemption_id) REFERENCES public.discount_code_redemptions(
        redemption_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


-- Section: Gamification Module Relationships
ALTER TABLE public.gam_badge_definitions_history
    ADD CONSTRAINT fk_gbdh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_gbdh_badge FOREIGN KEY (badge_id) REFERENCES public.gam_badge_definitions(
        badge_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.gam_user_stats
    ADD CONSTRAINT fk_gus_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM gam_point_transactions (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.gam_point_transactions
    ADD CONSTRAINT fk_gpt_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
    -- Add composite FK check logic if related_entity_type = 'BOOKING'
    -- This cannot be a direct FK due to polymorphism, but the columns exist.
    -- Application layer or triggers must ensure integrity if related_entity_type='BOOKING'.

ALTER TABLE public.gam_user_badges
    ADD CONSTRAINT fk_gub_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_gub_badge FOREIGN KEY (badge_id) REFERENCES public.gam_badge_definitions(
        badge_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.gam_user_badges_history
    ADD CONSTRAINT fk_gubh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_gubh_user_badge FOREIGN KEY (user_badge_id) REFERENCES public.gam_user_badges(
        user_badge_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.gam_challenge_definitions
    ADD CONSTRAINT fk_gcd_badge FOREIGN KEY (reward_badge_id) REFERENCES public.gam_badge_definitions(
        badge_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.gam_user_challenge_progress
    ADD CONSTRAINT fk_gucp_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_gucp_challenge FOREIGN KEY (challenge_id) REFERENCES public.gam_challenge_definitions(
        challenge_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.gam_leaderboard_snapshots
    ADD CONSTRAINT fk_gls_leaderboard FOREIGN KEY (leaderboard_id) REFERENCES public.gam_leaderboards(
        leaderboard_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Section: Loyalty Module Relationships (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.loyalty_transactions
    ADD CONSTRAINT fk_lt_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_lt_booking FOREIGN KEY (
        booking_created_at, related_booking_id
    ) REFERENCES public.booking_bookings(created_at, booking_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_lt_promo FOREIGN KEY (related_promo_id) REFERENCES public.promotions(
        promotion_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_lt_challenge FOREIGN KEY (related_challenge_id) REFERENCES public.gam_challenge_definitions(
        challenge_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_lt_related_user FOREIGN KEY (related_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
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
-- discount_code_redemptions_history -> discount_code_redemptions (redemption_id -> redemption_id) [CASCADE]
--
-- gam_user_stats -> core_user_profiles (user_id -> user_id) [CASCADE]
--
-- gam_point_transactions -> core_user_profiles (user_id -> user_id) [CASCADE]
-- gam_point_transactions -> booking_bookings (booking_created_at, 
    --related_entity_id -> created_at, booking_id) [No FK - Polymorphic]
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
-- loyalty_transactions -> booking_bookings (booking_created_at, 
    --related_booking_id -> created_at, booking_id) [SET NULL] -- COMPOSITE FK
-- loyalty_transactions -> promotions (related_promo_id -> promotion_id) [SET NULL?]
-- loyalty_transactions -> gam_challenge_definitions (related_challenge_id -> challenge_id) [SET NULL?]
-- loyalty_transactions -> core_user_profiles (related_user_id -> user_id) [SET NULL?]
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.8__Constraints_Promo_Gamification.sql (Version 1.1)
-- ============================================================================
