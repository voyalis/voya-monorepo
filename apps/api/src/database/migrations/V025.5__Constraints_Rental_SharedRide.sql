
-- ============================================================================
-- Migration: V025.5__Constraints_Rental_SharedRide.sql (Version 1.1 - Composite FK Fix)
-- Description: Add Foreign Key constraints for Rental & Shared Ride modules.
--              Uses composite FKs for references to partitioned table 'booking_bookings'.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Rental/SharedRide tables and referenced tables,
--               including addition of 'booking_created_at' to relevant tables.
--               (e.g., 001..005, 010b, 010c)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Rental Drops
ALTER TABLE public.rental_vehicle_availability DROP CONSTRAINT IF EXISTS fk_rva_vehicle;
ALTER TABLE public.rental_vehicle_availability DROP CONSTRAINT IF EXISTS fk_rva_maintenance;
-- FK to booking_rental_details
ALTER TABLE public.rental_vehicle_availability DROP CONSTRAINT IF EXISTS fk_rva_rental_booking;
ALTER TABLE public.rental_pricing_plans DROP CONSTRAINT IF EXISTS fk_rpp_partner;
ALTER TABLE public.rental_pricing_plans DROP CONSTRAINT IF EXISTS fk_rpp_vehicle_type;
ALTER TABLE public.rental_pricing_plans DROP CONSTRAINT IF EXISTS fk_rpp_currency;
ALTER TABLE public.rental_extras DROP CONSTRAINT IF EXISTS fk_re_partner;
ALTER TABLE public.rental_extras DROP CONSTRAINT IF EXISTS fk_re_currency;
-- booking_rental_details FKs are handled in V025.3

-- Shared Ride Drops
ALTER TABLE public.shared_ride_requests DROP CONSTRAINT IF EXISTS fk_srr_user;
ALTER TABLE public.shared_ride_requests DROP CONSTRAINT IF EXISTS fk_srr_origin;
ALTER TABLE public.shared_ride_requests DROP CONSTRAINT IF EXISTS fk_srr_destination;
ALTER TABLE public.shared_ride_requests DROP CONSTRAINT IF EXISTS fk_srr_match;
ALTER TABLE public.shared_ride_matches DROP CONSTRAINT IF EXISTS fk_srm_currency;
ALTER TABLE public.shared_ride_matches DROP CONSTRAINT IF EXISTS fk_srm_driver;
ALTER TABLE public.shared_ride_matches DROP CONSTRAINT IF EXISTS fk_srm_vehicle;
ALTER TABLE public.shared_ride_members DROP CONSTRAINT IF EXISTS fk_srmem_match;
ALTER TABLE public.shared_ride_members DROP CONSTRAINT IF EXISTS fk_srmem_request;
ALTER TABLE public.shared_ride_assignments DROP CONSTRAINT IF EXISTS fk_sra_match;
ALTER TABLE public.shared_ride_assignments DROP CONSTRAINT IF EXISTS fk_sra_driver;
ALTER TABLE public.shared_ride_assignments DROP CONSTRAINT IF EXISTS fk_sra_vehicle;
ALTER TABLE public.shared_ride_assignments DROP CONSTRAINT IF EXISTS fk_sra_leg; -- Added missing drop

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Rental Module Relationships
ALTER TABLE public.rental_vehicle_availability
    ADD CONSTRAINT fk_rva_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_rva_maintenance FOREIGN KEY (related_maintenance_id) REFERENCES public.fleet_vehicle_maintenance(
        maintenance_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    -- FK to booking_rental_details (which itself links to partitioned booking_bookings)
    ADD CONSTRAINT fk_rva_rental_booking FOREIGN KEY (
        related_rental_booking_id
    ) REFERENCES public.booking_rental_details(booking_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.rental_pricing_plans
    ADD CONSTRAINT fk_rpp_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_rpp_vehicle_type FOREIGN KEY (vehicle_type_code) REFERENCES public.lkp_vehicle_types(
        type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_rpp_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.rental_extras
    ADD CONSTRAINT fk_re_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_re_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- Note: booking_rental_details FKs were defined in V025.3, including the composite key to booking_bookings.

-- Section: Shared Ride Module Relationships
ALTER TABLE public.shared_ride_requests
    ADD CONSTRAINT fk_srr_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srr_origin FOREIGN KEY (origin_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srr_destination FOREIGN KEY (destination_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srr_match FOREIGN KEY (assigned_match_id) REFERENCES public.shared_ride_matches(
        match_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shared_ride_matches
    ADD CONSTRAINT fk_srm_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srm_driver FOREIGN KEY (assigned_driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srm_vehicle FOREIGN KEY (assigned_vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shared_ride_members
    ADD CONSTRAINT fk_srmem_match FOREIGN KEY (match_id) REFERENCES public.shared_ride_matches(
        match_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_srmem_request FOREIGN KEY (request_id) REFERENCES public.shared_ride_requests(
        request_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shared_ride_assignments
    ADD CONSTRAINT fk_sra_match FOREIGN KEY (match_id) REFERENCES public.shared_ride_matches(
        match_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_sra_driver FOREIGN KEY (driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_sra_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- rental_vehicle_availability -> fleet_vehicles (vehicle_id -> vehicle_id) [CASCADE?]
-- rental_vehicle_availability -> booking_rental_details (related_rental_booking_id -> booking_id) [SET NULL?]
-- rental_vehicle_availability -> fleet_vehicle_maintenance (related_maintenance_id -> maintenance_id) [SET NULL?]
--
-- rental_pricing_plans -> fleet_partners (partner_id -> partner_id) [CASCADE?]
-- rental_pricing_plans -> lkp_vehicle_types (vehicle_type_code -> type_code) [RESTRICT?]
-- rental_pricing_plans -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- rental_pricing_plans -> ??? (vehicle_category) [No FK - ENUM]
--
-- rental_extras -> fleet_partners (partner_id -> partner_id) [CASCADE?]
-- rental_extras -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- booking_rental_details -> See V025.3 for its FKs
--
-- shared_ride_requests -> core_user_profiles (user_id -> user_id) [CASCADE]
-- shared_ride_requests -> core_addresses (origin_address_id -> address_id) [RESTRICT]
-- shared_ride_requests -> core_addresses (destination_address_id -> address_id) [RESTRICT]
-- shared_ride_requests -> shared_ride_matches (assigned_match_id -> match_id) [SET NULL]
--
-- shared_ride_matches -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- shared_ride_matches -> fleet_drivers (assigned_driver_id -> driver_id) [SET NULL]
-- shared_ride_matches -> fleet_vehicles (assigned_vehicle_id -> vehicle_id) [SET NULL]
--
-- shared_ride_members -> shared_ride_matches (match_id -> match_id) [CASCADE]
-- shared_ride_members -> shared_ride_requests (request_id -> request_id) [CASCADE]
--
-- shared_ride_assignments -> shared_ride_matches (match_id -> match_id) [CASCADE]
-- shared_ride_assignments -> fleet_drivers (driver_id -> driver_id) [RESTRICT]
-- shared_ride_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- shared_ride_assignments -> booking_booking_legs (booking_created_at, 
    --related_booking_leg_id -> booking_created_at, leg_id) [SET NULL?] -- COMPOSITE FK
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.5__Constraints_Rental_SharedRide.sql (Version 1.1)
-- ============================================================================
