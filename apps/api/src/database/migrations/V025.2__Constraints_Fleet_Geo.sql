-- ============================================================================
-- Migration: V025.2__Constraints_Fleet_Geo.sql (Version 1.1 - Standardized)
-- Description: Add Foreign Key constraints for Fleet & Geo modules.
--              Includes partial unique indexes for active documents.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Fleet/Geo tables and referenced tables:
--               001..005 (Core/Lookups/Fleet), 009 (Geo)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Fleet Drops
ALTER TABLE public.fleet_partners DROP CONSTRAINT IF EXISTS fk_fleet_partners_organization;
ALTER TABLE public.fleet_partners DROP CONSTRAINT IF EXISTS fk_fleet_partners_address;
ALTER TABLE public.fleet_drivers DROP CONSTRAINT IF EXISTS fk_fleet_drivers_user;
ALTER TABLE public.fleet_drivers DROP CONSTRAINT IF EXISTS fk_fleet_drivers_partner;
ALTER TABLE public.fleet_drivers DROP CONSTRAINT IF EXISTS fk_fleet_drivers_vehicle;
ALTER TABLE public.fleet_vehicles DROP CONSTRAINT IF EXISTS fk_fleet_vehicles_partner;
ALTER TABLE public.fleet_vehicles DROP CONSTRAINT IF EXISTS fk_fleet_vehicles_type;
ALTER TABLE public.fleet_vehicles DROP CONSTRAINT IF EXISTS fk_fleet_vehicles_driver;
ALTER TABLE public.fleet_driver_documents DROP CONSTRAINT IF EXISTS fk_fdd_driver;
ALTER TABLE public.fleet_driver_documents DROP CONSTRAINT IF EXISTS fk_fdd_type;
ALTER TABLE public.fleet_driver_documents DROP CONSTRAINT IF EXISTS fk_fdd_verified_by;
ALTER TABLE public.fleet_driver_documents DROP CONSTRAINT IF EXISTS fk_fdd_uploaded_by;
-- Drop index before potentially recreating constraint logic implicitly
DROP INDEX IF EXISTS public.uidx_fleet_driver_docs_active; 
ALTER TABLE public.fleet_vehicle_documents DROP CONSTRAINT IF EXISTS fk_fvd_vehicle;
ALTER TABLE public.fleet_vehicle_documents DROP CONSTRAINT IF EXISTS fk_fvd_type;
ALTER TABLE public.fleet_vehicle_documents DROP CONSTRAINT IF EXISTS fk_fvd_verified_by;
ALTER TABLE public.fleet_vehicle_documents DROP CONSTRAINT IF EXISTS fk_fvd_uploaded_by;
DROP INDEX IF EXISTS public.uidx_fleet_vehicle_docs_active;
ALTER TABLE public.fleet_partner_documents DROP CONSTRAINT IF EXISTS fk_fpd_partner;
ALTER TABLE public.fleet_partner_documents DROP CONSTRAINT IF EXISTS fk_fpd_type;
ALTER TABLE public.fleet_partner_documents DROP CONSTRAINT IF EXISTS fk_fpd_verified_by;
ALTER TABLE public.fleet_partner_documents DROP CONSTRAINT IF EXISTS fk_fpd_uploaded_by;
DROP INDEX IF EXISTS public.uidx_fleet_partner_docs_active;
ALTER TABLE public.fleet_vehicle_maintenance DROP CONSTRAINT IF EXISTS fk_fvm_vehicle;
ALTER TABLE public.fleet_vehicle_maintenance DROP CONSTRAINT IF EXISTS fk_fvm_type;
ALTER TABLE public.fleet_vehicle_maintenance DROP CONSTRAINT IF EXISTS fk_fvm_currency;
ALTER TABLE public.fleet_vehicle_maintenance DROP CONSTRAINT IF EXISTS fk_fvm_completed_by;

-- Geo Drops
ALTER TABLE public.geo_zones DROP CONSTRAINT IF EXISTS fk_geo_zones_parent;
ALTER TABLE public.geo_zones DROP CONSTRAINT IF EXISTS fk_geo_zones_type;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Fleet Module Relationships
-- Table: fleet_partners
ALTER TABLE public.fleet_partners
    ADD CONSTRAINT fk_fleet_partners_organization
        FOREIGN KEY (organization_id) REFERENCES public.core_organizations(organization_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fleet_partners_address
        FOREIGN KEY (address_id) REFERENCES public.core_addresses(address_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- Table: fleet_drivers
ALTER TABLE public.fleet_drivers
    ADD CONSTRAINT fk_fleet_drivers_user
        FOREIGN KEY (driver_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fleet_drivers_partner
        FOREIGN KEY (assigned_partner_id) REFERENCES public.fleet_partners(partner_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fleet_drivers_vehicle
        FOREIGN KEY (current_vehicle_id) REFERENCES public.fleet_vehicles(vehicle_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Table: fleet_vehicles
ALTER TABLE public.fleet_vehicles
    ADD CONSTRAINT fk_fleet_vehicles_partner
        FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(partner_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fleet_vehicles_type
        FOREIGN KEY (vehicle_type_code) REFERENCES public.lkp_vehicle_types(type_code)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fleet_vehicles_driver
        FOREIGN KEY (assigned_driver_id) REFERENCES public.fleet_drivers(driver_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Table: fleet_driver_documents
ALTER TABLE public.fleet_driver_documents
    ADD CONSTRAINT fk_fdd_driver FOREIGN KEY (driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fdd_type FOREIGN KEY (document_type_code) REFERENCES public.lkp_document_types(
        doc_type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fdd_verified_by FOREIGN KEY (verified_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fdd_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
-- Partial Unique Index for active documents
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_driver_docs_active
    ON public.fleet_driver_documents (driver_id, document_type_code)
    WHERE (is_active = TRUE);
COMMENT ON INDEX public.uidx_fleet_driver_docs_active
    IS '[VoyaGo][Logic] Ensures only one document per type is active for a driver.';


-- Table: fleet_vehicle_documents
ALTER TABLE public.fleet_vehicle_documents
    ADD CONSTRAINT fk_fvd_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvd_type FOREIGN KEY (document_type_code) REFERENCES public.lkp_document_types(
        doc_type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvd_verified_by FOREIGN KEY (verified_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvd_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
-- Partial Unique Index for active documents
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_vehicle_docs_active
    ON public.fleet_vehicle_documents (vehicle_id, document_type_code)
    WHERE (is_active = TRUE);
COMMENT ON INDEX public.uidx_fleet_vehicle_docs_active
    IS '[VoyaGo][Logic] Ensures only one document per type is active for a vehicle.';


-- Table: fleet_partner_documents
ALTER TABLE public.fleet_partner_documents
    ADD CONSTRAINT fk_fpd_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fpd_type FOREIGN KEY (document_type_code) REFERENCES public.lkp_document_types(
        doc_type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fpd_verified_by FOREIGN KEY (verified_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fpd_uploaded_by FOREIGN KEY (uploaded_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;
-- Partial Unique Index for active documents
CREATE UNIQUE INDEX IF NOT EXISTS uidx_fleet_partner_docs_active
    ON public.fleet_partner_documents (partner_id, document_type_code)
    WHERE (is_active = TRUE);
COMMENT ON INDEX public.uidx_fleet_partner_docs_active
    IS '[VoyaGo][Logic] Ensures only one document per type is active for a partner.';


-- Table: fleet_vehicle_maintenance
ALTER TABLE public.fleet_vehicle_maintenance
    ADD CONSTRAINT fk_fvm_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvm_type FOREIGN KEY (maintenance_type_code) REFERENCES public.lkp_maintenance_types(
        maintenance_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvm_currency FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_fvm_completed_by FOREIGN KEY (completed_by_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- Section: Geo Module Relationships
-- Table: geo_zones
ALTER TABLE public.geo_zones
    ADD CONSTRAINT fk_geo_zones_parent FOREIGN KEY (parent_zone_id) REFERENCES public.geo_zones(
        zone_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_geo_zones_type FOREIGN KEY (zone_type_code) REFERENCES public.lkp_zone_types(
        zone_type_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- Note: FK for fleet_vehicle_location_history.vehicle_id -> fleet_vehicles.vehicle_id added in V025.6


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- --------------------------------------------------------------------------------------------------
-- fleet_partners -> core_organizations (organization_id -> organization_id) [SET NULL]
-- fleet_partners -> core_addresses (address_id -> address_id) [RESTRICT]
-- fleet_drivers -> core_user_profiles (driver_id -> user_id) [CASCADE]
-- fleet_drivers -> fleet_partners (assigned_partner_id -> partner_id) [SET NULL]
-- fleet_drivers -> fleet_vehicles (current_vehicle_id -> vehicle_id) [SET NULL]
-- fleet_vehicles -> fleet_partners (partner_id -> partner_id) [SET NULL]
-- fleet_vehicles -> lkp_vehicle_types (vehicle_type_code -> type_code) [RESTRICT]
-- fleet_vehicles -> fleet_drivers (assigned_driver_id -> driver_id) [SET NULL]
-- fleet_driver_documents -> fleet_drivers (driver_id -> driver_id) [CASCADE]
-- fleet_driver_documents -> lkp_document_types (document_type_code -> doc_type_code) [RESTRICT]
-- fleet_driver_documents -> core_user_profiles (verified_by -> user_id) [SET NULL]
-- fleet_driver_documents -> core_user_profiles (uploaded_by -> user_id) [SET NULL]
-- fleet_vehicle_documents -> fleet_vehicles (vehicle_id -> vehicle_id) [CASCADE]
-- fleet_vehicle_documents -> lkp_document_types (document_type_code -> doc_type_code) [RESTRICT]
-- fleet_vehicle_documents -> core_user_profiles (verified_by -> user_id) [SET NULL]
-- fleet_vehicle_documents -> core_user_profiles (uploaded_by -> user_id) [SET NULL]
-- fleet_partner_documents -> fleet_partners (partner_id -> partner_id) [CASCADE]
-- fleet_partner_documents -> lkp_document_types (document_type_code -> doc_type_code) [RESTRICT]
-- fleet_partner_documents -> core_user_profiles (verified_by -> user_id) [SET NULL]
-- fleet_partner_documents -> core_user_profiles (uploaded_by -> user_id) [SET NULL]
-- fleet_vehicle_maintenance -> fleet_vehicles (vehicle_id -> vehicle_id) [CASCADE]
-- fleet_vehicle_maintenance -> lkp_maintenance_types 
    --(maintenance_type_code -> maintenance_code) [RESTRICT]
-- fleet_vehicle_maintenance -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- fleet_vehicle_maintenance -> core_user_profiles (completed_by_user_id -> user_id) [SET NULL]
-- geo_zones -> geo_zones (parent_zone_id -> zone_id) [SET NULL]
-- geo_zones -> lkp_zone_types (zone_type_code -> zone_type_code) [RESTRICT]
-- ============================================================================

-- ============================================================================
-- End of Migration: V025.2__Constraints_Fleet_Geo.sql
-- ============================================================================
