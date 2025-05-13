-- ============================================================================
-- Migration: V025.7__Constraints_Shuttle_Pricing.sql (Version 1.2 - Composite FK Fix)
-- Description: Add FK constraints for Shuttle & Pricing modules.
--              Uses composite FKs for references to partitioned tables.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Shuttle/Pricing tables and referenced tables,
--               including addition of partition key columns to relevant tables.
--               (e.g., 001..005, 009, 010, 011, 015, 016, 023)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Shuttle Drops
ALTER TABLE public.shuttle_stops DROP CONSTRAINT IF EXISTS fk_shstop_service;
ALTER TABLE public.shuttle_stops DROP CONSTRAINT IF EXISTS fk_shstop_address;
ALTER TABLE public.shuttle_routes DROP CONSTRAINT IF EXISTS fk_shroute_service;
ALTER TABLE public.shuttle_schedules DROP CONSTRAINT IF EXISTS fk_shsch_service;
ALTER TABLE public.shuttle_trips DROP CONSTRAINT IF EXISTS fk_shtrip_service;
ALTER TABLE public.shuttle_trips DROP CONSTRAINT IF EXISTS fk_shtrip_schedule;
ALTER TABLE public.shuttle_trips DROP CONSTRAINT IF EXISTS fk_shtrip_vehicle;
ALTER TABLE public.shuttle_trips DROP CONSTRAINT IF EXISTS fk_shtrip_driver;
ALTER TABLE public.shuttle_trip_legs DROP CONSTRAINT IF EXISTS fk_shtl_trip;
ALTER TABLE public.shuttle_trip_legs DROP CONSTRAINT IF EXISTS fk_shtl_stop;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_trip;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_user;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_pickup_stop;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_dropoff_stop;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_currency;
ALTER TABLE public.shuttle_bookings DROP CONSTRAINT IF EXISTS fk_shb_payment;
ALTER TABLE public.shuttle_boardings DROP CONSTRAINT IF EXISTS fk_shbrd_booking;
ALTER TABLE public.shuttle_boardings DROP CONSTRAINT IF EXISTS fk_shbrd_leg;
ALTER TABLE public.shuttle_boardings DROP CONSTRAINT IF EXISTS fk_shbrd_actor;

-- Pricing Drops
ALTER TABLE public.pricing_rules DROP CONSTRAINT IF EXISTS fk_pr_service;
ALTER TABLE public.pricing_rules DROP CONSTRAINT IF EXISTS fk_pr_partner;
ALTER TABLE public.pricing_rules DROP CONSTRAINT IF EXISTS fk_pr_zone;
ALTER TABLE public.pricing_calculations DROP CONSTRAINT IF EXISTS fk_pc_booking; -- Will be recreated as composite
ALTER TABLE public.pricing_calculations DROP CONSTRAINT IF EXISTS fk_pc_ride; -- Will be recreated as composite
ALTER TABLE public.pricing_calculations DROP CONSTRAINT IF EXISTS fk_pc_currency;
ALTER TABLE public.pricing_rules_history DROP CONSTRAINT IF EXISTS fk_prh_actor; -- Added missing drop
ALTER TABLE public.pricing_rules_history DROP CONSTRAINT IF EXISTS fk_prh_rule; -- Added missing drop

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Shuttle Module Relationships
ALTER TABLE public.shuttle_stops
    ADD CONSTRAINT fk_shstop_service FOREIGN KEY (service_id) REFERENCES public.shuttle_services(
        service_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shstop_address FOREIGN KEY (address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_routes
    ADD CONSTRAINT fk_shroute_service FOREIGN KEY (service_id) REFERENCES public.shuttle_services(
        service_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_schedules
    ADD CONSTRAINT fk_shsch_service FOREIGN KEY (service_id) REFERENCES public.shuttle_services(
        service_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_trips
    ADD CONSTRAINT fk_shtrip_service FOREIGN KEY (service_id) REFERENCES public.shuttle_services(
        service_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shtrip_schedule FOREIGN KEY (schedule_id) REFERENCES public.shuttle_schedules(
        schedule_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shtrip_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shtrip_driver FOREIGN KEY (driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_trip_legs
    ADD CONSTRAINT fk_shtl_trip FOREIGN KEY (trip_id) REFERENCES public.shuttle_trips(
        trip_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shtl_stop FOREIGN KEY (stop_id) REFERENCES public.shuttle_stops(
        stop_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_bookings
    -- Changed to RESTRICT
    ADD CONSTRAINT fk_shb_trip FOREIGN KEY (trip_id) REFERENCES public.shuttle_trips(
        trip_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shb_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shb_pickup_stop FOREIGN KEY (pickup_stop_id) REFERENCES public.shuttle_stops(
        stop_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shb_dropoff_stop FOREIGN KEY (dropoff_stop_id) REFERENCES public.shuttle_stops(
        stop_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shb_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shb_payment FOREIGN KEY (payment_id) REFERENCES public.pmt_payments(
        payment_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.shuttle_boardings
    ADD CONSTRAINT fk_shbrd_booking FOREIGN KEY (booking_id) REFERENCES public.shuttle_bookings(
        booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shbrd_leg FOREIGN KEY (trip_leg_id) REFERENCES public.shuttle_trip_legs(
        leg_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_shbrd_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Section: Pricing Module Relationships
ALTER TABLE public.pricing_rules
    -- Changed to RESTRICT
    ADD CONSTRAINT fk_pr_service FOREIGN KEY (service_code) REFERENCES public.lkp_service_types(
        service_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pr_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pr_zone FOREIGN KEY (zone_id) REFERENCES public.geo_zones(
        zone_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.pricing_rules_history
    ADD CONSTRAINT fk_prh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_prh_rule FOREIGN KEY (rule_id) REFERENCES public.pricing_rules(
        rule_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM pricing_calculations (Using COMPOSITE FKs to partitioned tables)
ALTER TABLE public.pricing_calculations
    ADD CONSTRAINT fk_pc_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pc_ride FOREIGN KEY (ride_start_time, ride_id) REFERENCES public.mm_rides(
        start_time, ride_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_pc_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;
    -- Note: FK for applied_rules (JSONB) is not possible.


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- shuttle_stops -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_stops -> core_addresses (address_id -> address_id) [RESTRICT]
-- shuttle_routes -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_schedules -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_trips -> shuttle_services (service_id -> service_id) [CASCADE]
-- shuttle_trips -> shuttle_schedules (schedule_id -> schedule_id) [SET NULL]
-- shuttle_trips -> fleet_vehicles (vehicle_id -> vehicle_id) [SET NULL]
-- shuttle_trips -> fleet_drivers (driver_id -> driver_id) [SET NULL]
-- shuttle_trip_legs -> shuttle_trips (trip_id -> trip_id) [CASCADE]
-- shuttle_trip_legs -> shuttle_stops (stop_id -> stop_id) [CASCADE?]
-- shuttle_bookings -> shuttle_trips (trip_id -> trip_id) [RESTRICT]
-- shuttle_bookings -> core_user_profiles (user_id -> user_id) [CASCADE]
-- shuttle_bookings -> shuttle_stops (pickup_stop_id -> stop_id) [RESTRICT]
-- shuttle_bookings -> shuttle_stops (dropoff_stop_id -> stop_id) [RESTRICT]
-- shuttle_bookings -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- shuttle_bookings -> pmt_payments (payment_id -> payment_id) [SET NULL]
-- shuttle_boardings -> shuttle_bookings (booking_id -> booking_id) [CASCADE]
-- shuttle_boardings -> shuttle_trip_legs (trip_leg_id -> leg_id) [SET NULL?]
-- shuttle_boardings -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- pricing_rules -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- pricing_rules -> fleet_partners (partner_id -> partner_id) [CASCADE]
-- pricing_rules -> geo_zones (zone_id -> zone_id) [CASCADE]
--
-- pricing_rules_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- pricing_rules_history -> pricing_rules (rule_id -> rule_id) [CASCADE]
--
-- pricing_calculations -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- pricing_calculations -> mm_rides (ride_start_time, ride_id -> 
    --start_time, ride_id) [SET NULL?] -- COMPOSITE FK
-- pricing_calculations -> ??? (ride_id -> other ride tables?) [Polymorphic]
-- pricing_calculations -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.7__Constraints_Shuttle_Pricing.sql (Version 1.2)
-- ============================================================================
