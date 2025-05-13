-- ============================================================================
-- Migration: V025.6__Constraints_Cargo_Micromobility.sql (Version 1.1 - Composite FK Fix)
-- Description: Add Foreign Key constraints for Cargo & Micromobility modules.
--              Uses composite FKs for references to partitioned tables.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Cargo/MM tables and referenced tables
--               (e.g., 001..005, 008, 010b, 011, 013, 014)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Cargo Drops
ALTER TABLE public.cargo_partners DROP CONSTRAINT IF EXISTS fk_cp_fleet_partner;
ALTER TABLE public.cargo_partners DROP CONSTRAINT IF EXISTS fk_cp_api_integration;
-- Will be recreated as composite
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_booking; 
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_partner;
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_sender_user;
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_sender_addr;
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_recipient_addr;
ALTER TABLE public.cargo_shipments DROP CONSTRAINT IF EXISTS fk_cs_currency;
ALTER TABLE public.cargo_packages DROP CONSTRAINT IF EXISTS fk_cpkg_shipment;
ALTER TABLE public.cargo_packages DROP CONSTRAINT IF EXISTS fk_cpkg_currency;
ALTER TABLE public.cargo_tracking_events DROP CONSTRAINT IF EXISTS fk_cte_package;
-- Refers to partitioned cargo_shipments, omitted
ALTER TABLE public.cargo_tracking_events DROP CONSTRAINT IF EXISTS fk_cte_shipment; 
ALTER TABLE public.cargo_tracking_events DROP CONSTRAINT IF EXISTS fk_cte_actor;
-- Will be recreated as composite
ALTER TABLE public.cargo_leg_assignments DROP CONSTRAINT IF EXISTS fk_cla_leg; 
ALTER TABLE public.cargo_leg_assignments DROP CONSTRAINT IF EXISTS fk_cla_package;
ALTER TABLE public.cargo_leg_assignments DROP CONSTRAINT IF EXISTS fk_cla_vehicle;
ALTER TABLE public.cargo_leg_assignments DROP CONSTRAINT IF EXISTS fk_cla_driver;

-- Micromobility Drops
ALTER TABLE public.lkp_mm_vehicle_types_translations DROP CONSTRAINT IF EXISTS fk_mmvtt_type;
ALTER TABLE public.lkp_mm_vehicle_types_translations DROP CONSTRAINT IF EXISTS fk_mmvtt_lang;
ALTER TABLE public.mm_vehicles DROP CONSTRAINT IF EXISTS fk_mmv_type;
ALTER TABLE public.mm_vehicles DROP CONSTRAINT IF EXISTS fk_mmv_partner;
ALTER TABLE public.mm_vehicles DROP CONSTRAINT IF EXISTS fk_mmv_user;
-- Will be recreated as composite
ALTER TABLE public.mm_vehicles DROP CONSTRAINT IF EXISTS fk_mmv_ride; 
ALTER TABLE public.mm_vehicles_history DROP CONSTRAINT IF EXISTS fk_mmvh_actor;
ALTER TABLE public.mm_vehicles_history DROP CONSTRAINT IF EXISTS fk_mmvh_vehicle;
ALTER TABLE public.mm_station_status DROP CONSTRAINT IF EXISTS fk_mmss_station;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_user;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_vehicle;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_start_station;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_end_station;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_currency;
ALTER TABLE public.mm_rides DROP CONSTRAINT IF EXISTS fk_mmr_payment;
-- Will be recreated as composite
ALTER TABLE public.mm_ride_events DROP CONSTRAINT IF EXISTS fk_mmre_ride; 
ALTER TABLE public.mm_ride_events DROP CONSTRAINT IF EXISTS fk_mmre_actor;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Cargo Module Relationships
ALTER TABLE public.cargo_partners
    ADD CONSTRAINT fk_cp_fleet_partner FOREIGN KEY (fleet_partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cp_api_integration FOREIGN KEY (api_integration_id) REFERENCES public.system_api_integrations(
        integration_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM cargo_shipments (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.cargo_shipments
    ADD CONSTRAINT fk_cs_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cs_partner FOREIGN KEY (cargo_partner_id) REFERENCES public.cargo_partners(
        partner_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cs_sender_user FOREIGN KEY (sender_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cs_sender_addr FOREIGN KEY (sender_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cs_recipient_addr FOREIGN KEY (recipient_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cs_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.cargo_packages
    ADD CONSTRAINT fk_cpkg_shipment FOREIGN KEY (shipment_id) REFERENCES public.cargo_shipments(
        shipment_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cpkg_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM cargo_tracking_events
ALTER TABLE public.cargo_tracking_events
    ADD CONSTRAINT fk_cte_package FOREIGN KEY (package_id) REFERENCES public.cargo_packages(
        package_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    -- FK to shipment_id omitted as it's denormalized and links via package_id -> cargo_shipments.
    ADD CONSTRAINT fk_cte_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM cargo_leg_assignments (Using COMPOSITE FK to booking_booking_legs)
ALTER TABLE public.cargo_leg_assignments
    ADD CONSTRAINT fk_cla_package FOREIGN KEY (package_id) REFERENCES public.cargo_packages(
        package_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cla_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cla_driver FOREIGN KEY (driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Section: Micromobility Module Relationships
ALTER TABLE public.lkp_mm_vehicle_types_translations
    ADD CONSTRAINT fk_mmvtt_type FOREIGN KEY (type_code) REFERENCES public.lkp_mm_vehicle_types(
        type_code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmvtt_lang FOREIGN KEY (language_code) REFERENCES public.lkp_languages(
        code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM mm_vehicles (Using COMPOSITE FK to mm_rides)
ALTER TABLE public.mm_vehicles
    ADD CONSTRAINT fk_mmv_type FOREIGN KEY (vehicle_type_code) REFERENCES public.lkp_mm_vehicle_types(
        type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmv_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmv_user FOREIGN KEY (current_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmv_ride FOREIGN KEY (current_ride_start_time, current_ride_id) REFERENCES public.mm_rides(
        start_time, ride_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.mm_vehicles_history
    ADD CONSTRAINT fk_mmvh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmvh_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.mm_vehicles(
        vehicle_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.mm_station_status
    ADD CONSTRAINT fk_mmss_station FOREIGN KEY (station_id) REFERENCES public.mm_stations(
        station_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM mm_rides (to non-partitioned tables)
ALTER TABLE public.mm_rides
    ADD CONSTRAINT fk_mmr_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmr_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.mm_vehicles(
        vehicle_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmr_start_station FOREIGN KEY (start_station_id) REFERENCES public.mm_stations(
        station_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmr_end_station FOREIGN KEY (end_station_id) REFERENCES public.mm_stations(
        station_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmr_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmr_payment FOREIGN KEY (payment_id) REFERENCES public.pmt_payments(
        payment_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM mm_ride_events (Using COMPOSITE FK to mm_rides)
ALTER TABLE public.mm_ride_events
    ADD CONSTRAINT fk_mmre_ride FOREIGN KEY (ride_start_time, ride_id) REFERENCES public.mm_rides(
        start_time, ride_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_mmre_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- cargo_partners -> fleet_partners (fleet_partner_id -> partner_id) [CASCADE]
-- cargo_partners -> system_api_integrations (api_integration_id -> integration_id) [SET NULL]
--
-- cargo_shipments -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- cargo_shipments -> cargo_partners (cargo_partner_id -> partner_id) [RESTRICT]
-- cargo_shipments -> core_user_profiles (sender_user_id -> user_id) [RESTRICT]
-- cargo_shipments -> core_addresses (sender_address_id -> address_id) [RESTRICT]
-- cargo_shipments -> core_addresses (recipient_address_id -> address_id) [RESTRICT]
-- cargo_shipments -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- cargo_packages -> cargo_shipments (shipment_id -> shipment_id) [CASCADE]
-- cargo_packages -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- cargo_tracking_events -> cargo_packages (package_id -> package_id) [CASCADE]
-- cargo_tracking_events -> cargo_shipments (shipment_id) [OMITTED - Relies on package link]
-- cargo_tracking_events -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- cargo_leg_assignments -> booking_booking_legs (booking_created_at, 
    --booking_leg_id -> booking_created_at, leg_id) [CASCADE] -- COMPOSITE FK
-- cargo_leg_assignments -> cargo_packages (package_id -> package_id) [CASCADE?]
-- cargo_leg_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [SET NULL]
-- cargo_leg_assignments -> fleet_drivers (driver_id -> driver_id) [SET NULL]
--
-- lkp_mm_vehicle_types_translations -> lkp_mm_vehicle_types (type_code -> type_code) [CASCADE]
-- lkp_mm_vehicle_types_translations -> lkp_languages (language_code -> code) [CASCADE]
--
-- mm_vehicles -> lkp_mm_vehicle_types (vehicle_type_code -> type_code) [RESTRICT]
-- mm_vehicles -> fleet_partners (partner_id -> partner_id) [SET NULL?]
-- mm_vehicles -> core_user_profiles (current_user_id -> user_id) [SET NULL]
-- mm_vehicles -> mm_rides (current_ride_start_time, 
    --current_ride_id -> start_time, ride_id) [SET NULL] -- COMPOSITE FK
--
-- mm_vehicles_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- mm_vehicles_history -> mm_vehicles (vehicle_id -> vehicle_id) [CASCADE]
--
-- mm_station_status -> mm_stations (station_id -> station_id) [CASCADE]
--
-- mm_rides -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- mm_rides -> mm_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- mm_rides -> mm_stations (start_station_id -> station_id) [SET NULL]
-- mm_rides -> mm_stations (end_station_id -> station_id) [SET NULL]
-- mm_rides -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- mm_rides -> pmt_payments (payment_id -> payment_id) [SET NULL]
--
-- mm_ride_events -> mm_rides (ride_start_time, ride_id -> start_time, ride_id) [CASCADE] 
    -- COMPOSITE FK
-- mm_ride_events -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.6__Constraints_Cargo_Micromobility.sql (Version 1.1)
-- ============================================================================
