-- ============================================================================
-- Migration: V025.4__Constraints_Booking_Payment.sql (Version 1.1 - Composite FK Fix)
-- Description: Add Foreign Key constraints for Booking & Payment modules.
--              Uses composite FKs for references to partitioned table 'booking_bookings'.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Booking/Payment tables and referenced tables,
--               including addition of 'booking_created_at' to relevant tables.
--               (e.g., 001..005, 010, 011, 017)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- FKs *FROM* booking_bookings
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_user;
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_organization;
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_currency;
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_cancellation_policy;
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_cancellation_reason;
ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_cancelled_by;
-- ALTER TABLE public.booking_bookings DROP CONSTRAINT IF EXISTS fk_bb_promo_code; -- Omitted

-- FKs *FROM* booking_booking_legs
-- Will be recreated as composite
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_booking; 
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_origin_addr;
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_dest_addr;
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_vehicle;
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_driver;
ALTER TABLE public.booking_booking_legs DROP CONSTRAINT IF EXISTS fk_bbl_carrier;

-- FKs *FROM* booking_status_history
-- Will be recreated as composite
ALTER TABLE public.booking_status_history DROP CONSTRAINT IF EXISTS fk_bsh_booking; 
ALTER TABLE public.booking_status_history DROP CONSTRAINT IF EXISTS fk_bsh_leg;
ALTER TABLE public.booking_status_history DROP CONSTRAINT IF EXISTS fk_bsh_actor;

-- FKs *FROM* booking_bid_requests
-- Will be recreated as composite
ALTER TABLE public.booking_bid_requests DROP CONSTRAINT IF EXISTS fk_bbr_booking; 
ALTER TABLE public.booking_bid_requests DROP CONSTRAINT IF EXISTS fk_bbr_origin_addr;
ALTER TABLE public.booking_bid_requests DROP CONSTRAINT IF EXISTS fk_bbr_dest_addr;
ALTER TABLE public.booking_bid_requests DROP CONSTRAINT IF EXISTS fk_bbr_winning_bid;

-- FKs *FROM* booking_bids
ALTER TABLE public.booking_bids DROP CONSTRAINT IF EXISTS fk_bb_request;
ALTER TABLE public.booking_bids DROP CONSTRAINT IF EXISTS fk_bb_currency;
ALTER TABLE public.booking_bids DROP CONSTRAINT IF EXISTS fk_bb_vehicle;
ALTER TABLE public.booking_bids DROP CONSTRAINT IF EXISTS fk_bb_driver;

-- FKs *FROM* pmt_payments
-- Will be recreated as composite
ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_booking; 
ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_user;
ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_currency;
ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_method;
ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_related_payment;
-- ALTER TABLE public.pmt_payments DROP CONSTRAINT IF EXISTS fk_pmt_promo_code; -- Omitted

-- FKs *FROM* pmt_user_wallet_transactions
ALTER TABLE public.pmt_user_wallet_transactions DROP CONSTRAINT IF EXISTS fk_puwt_user;
ALTER TABLE public.pmt_user_wallet_transactions DROP CONSTRAINT IF EXISTS fk_puwt_currency;
ALTER TABLE public.pmt_user_wallet_transactions DROP CONSTRAINT IF EXISTS fk_puwt_payment;
-- Will be recreated as composite
ALTER TABLE public.pmt_user_wallet_transactions DROP CONSTRAINT IF EXISTS fk_puwt_booking; 
ALTER TABLE public.pmt_user_wallet_transactions DROP CONSTRAINT IF EXISTS fk_puwt_promo;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Booking Module Relationships

-- Constraints FROM booking_bookings (to non-partitioned tables)
ALTER TABLE public.booking_bookings
    ADD CONSTRAINT fk_bb_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_organization FOREIGN KEY (organization_id) REFERENCES public.core_organizations(
        organization_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_cancellation_policy FOREIGN KEY (
        cancellation_policy_id
    ) REFERENCES public.booking_cancellation_policies(policy_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_cancellation_reason FOREIGN KEY (
        cancellation_reason_code
    ) REFERENCES public.lkp_cancellation_reasons(reason_code) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_cancelled_by FOREIGN KEY (cancelled_by_actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
    -- FK for applied_promo_code omitted - requires Promotions module tables

-- Constraints FROM booking_booking_legs (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.booking_booking_legs
    ADD CONSTRAINT fk_bbl_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbl_origin_addr FOREIGN KEY (origin_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbl_dest_addr FOREIGN KEY (destination_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbl_vehicle FOREIGN KEY (assigned_vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbl_driver FOREIGN KEY (assigned_driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbl_carrier FOREIGN KEY (carrier_partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Constraints FROM booking_status_history (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.booking_status_history
    ADD CONSTRAINT fk_bsh_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bsh_leg FOREIGN KEY (leg_id) REFERENCES public.booking_booking_legs(
        leg_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bsh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Constraints FROM booking_bid_requests (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.booking_bid_requests
    ADD CONSTRAINT fk_bbr_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbr_origin_addr FOREIGN KEY (origin_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbr_dest_addr FOREIGN KEY (destination_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bbr_winning_bid FOREIGN KEY (winning_bid_id) REFERENCES public.booking_bids(
        bid_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Constraints FROM booking_bids
ALTER TABLE public.booking_bids
    ADD CONSTRAINT fk_bb_request FOREIGN KEY (request_id) REFERENCES public.booking_bid_requests(
        request_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_vehicle FOREIGN KEY (proposed_vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bb_driver FOREIGN KEY (proposed_driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- Section: Payment Module Relationships (Using COMPOSITE FK to booking_bookings)

-- Constraints FROM pmt_payments
ALTER TABLE public.pmt_payments
    ADD CONSTRAINT fk_pmt_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pmt_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pmt_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pmt_method FOREIGN KEY (payment_method_id) REFERENCES public.pmt_payment_methods(
        payment_method_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pmt_related_payment FOREIGN KEY (related_payment_id) REFERENCES public.pmt_payments(
        payment_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
    -- FK for applied_promo_code omitted - requires Promotions module tables

-- Constraints FROM pmt_user_wallet_transactions
ALTER TABLE public.pmt_user_wallet_transactions
    ADD CONSTRAINT fk_puwt_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_puwt_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_puwt_payment FOREIGN KEY (related_payment_id) REFERENCES public.pmt_payments(
        payment_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_puwt_booking FOREIGN KEY (
        booking_created_at, related_booking_id
    ) REFERENCES public.booking_bookings(created_at, booking_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
    -- FK for related_promo_id requires Promotions module tables
    -- ADD CONSTRAINT fk_puwt_promo FOREIGN KEY (related_promo_id) 
        --REFERENCES public.promotions(promotion_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- booking_bookings -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- booking_bookings -> core_organizations (organization_id -> organization_id) [SET NULL?]
-- booking_bookings -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- booking_bookings -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- booking_bookings -> booking_cancellation_policies (cancellation_policy_id -> policy_id) [SET NULL?]
-- booking_bookings -> lkp_cancellation_reasons (cancellation_reason_code -> reason_code) [SET NULL?]
-- booking_bookings -> core_user_profiles (cancelled_by_actor_id -> user_id) [SET NULL?]
-- booking_bookings -> ??? (applied_promo_code -> promotions_table.promo_code) [SET NULL?]
--
-- booking_booking_legs -> booking_bookings 
    --(booking_created_at, booking_id -> created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- booking_booking_legs -> lkp_service_types (mode -> service_code) [RESTRICT]
-- booking_booking_legs -> core_addresses (origin_address_id -> address_id) [RESTRICT]
-- booking_booking_legs -> core_addresses (destination_address_id -> address_id) [RESTRICT]
-- booking_booking_legs -> fleet_vehicles (assigned_vehicle_id -> vehicle_id) [SET NULL?]
-- booking_booking_legs -> fleet_drivers (assigned_driver_id -> driver_id) [SET NULL?]
-- booking_booking_legs -> fleet_partners (carrier_partner_id -> partner_id) [SET NULL?]
--
-- booking_status_history -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- booking_status_history -> booking_booking_legs (leg_id -> leg_id) [CASCADE? SET NULL?]
-- booking_status_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- booking_bid_requests -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- booking_bid_requests -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- booking_bid_requests -> core_addresses (origin_address_id -> address_id) [SET NULL?]
-- booking_bid_requests -> core_addresses (destination_address_id -> address_id) [SET NULL?]
-- booking_bid_requests -> booking_bids (winning_bid_id -> bid_id) [SET NULL]
--
-- booking_bids -> booking_bid_requests (request_id -> request_id) [CASCADE]
-- booking_bids -> ??? (bidder_entity_id -> fleet_drivers.driver_id 
    --or fleet_partners.partner_id) [Complex - No DB FK]
-- booking_bids -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- booking_bids -> fleet_vehicles (proposed_vehicle_id -> vehicle_id) [SET NULL?]
-- booking_bids -> fleet_drivers (proposed_driver_id -> driver_id) [SET NULL?]
--
-- pmt_payments -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- pmt_payments -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- pmt_payments -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- pmt_payments -> pmt_payment_methods (payment_method_id -> payment_method_id) [SET NULL?]
-- pmt_payments -> pmt_payments (related_payment_id -> payment_id) [SET NULL?]
-- pmt_payments -> ??? (applied_promo_code -> promotions.code ??) [SET NULL?] -- Needs Promotions module
--
-- pmt_user_wallet_transactions -> core_user_profiles (user_id -> user_id) [CASCADE? RESTRICT?]
-- pmt_user_wallet_transactions -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- pmt_user_wallet_transactions -> pmt_payments (related_payment_id -> payment_id) [SET NULL]
-- pmt_user_wallet_transactions -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [SET NULL] -- COMPOSITE FK
-- pmt_user_wallet_transactions -> ??? 
    --(related_promo_id -> promotions.promotion_id) [SET NULL?] -- Needs Promotions module
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.4__Constraints_Booking_Payment.sql (Version 1.1)
-- ============================================================================
