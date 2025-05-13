-- ============================================================================
-- Migration: V025.3__Constraints_Acc_Cms_Api.sql (Version 1.3 - Composite FK Fix)
-- Description: Add FK constraints for Accommodation, CMS & API Management modules.
--              Uses composite FK for booking_bookings reference where applicable.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining Acc/CMS/API tables and referenced tables,
--               including addition of 'booking_created_at' to booking_accommodation_details.
--               (e.g., 001..008, 010b)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- Accommodation Module Constraints Drop
ALTER TABLE public.acc_properties DROP CONSTRAINT IF EXISTS fk_acc_prop_partner;
ALTER TABLE public.acc_properties DROP CONSTRAINT IF EXISTS fk_acc_prop_address;
ALTER TABLE public.acc_property_features_link DROP CONSTRAINT IF EXISTS fk_acc_pflink_prop;
ALTER TABLE public.acc_property_features_link DROP CONSTRAINT IF EXISTS fk_acc_pflink_feat;
ALTER TABLE public.acc_room_types DROP CONSTRAINT IF EXISTS fk_acc_room_prop;
ALTER TABLE public.acc_room_types DROP CONSTRAINT IF EXISTS fk_acc_room_curr;
ALTER TABLE public.acc_room_amenities_link DROP CONSTRAINT IF EXISTS fk_acc_ralink_room;
ALTER TABLE public.acc_room_amenities_link DROP CONSTRAINT IF EXISTS fk_acc_ralink_amen;
ALTER TABLE public.acc_inventory_calendar DROP CONSTRAINT IF EXISTS fk_acc_inv_room;
ALTER TABLE public.acc_inventory_calendar DROP CONSTRAINT IF EXISTS fk_acc_inv_curr;
-- Will be recreated as composite
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_booking; 
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_prop;
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_room;
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_pickup_loc;
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_dropoff_loc;
ALTER TABLE public.booking_accommodation_details DROP CONSTRAINT IF EXISTS fk_bacc_currency;

-- CMS Module Constraints Drop
ALTER TABLE public.cms_categories DROP CONSTRAINT IF EXISTS fk_cms_cat_parent;
ALTER TABLE public.cms_categories_translations DROP CONSTRAINT IF EXISTS fk_cms_cattrans_cat;
ALTER TABLE public.cms_categories_translations DROP CONSTRAINT IF EXISTS fk_cms_cattrans_lang;
ALTER TABLE public.cms_content_items DROP CONSTRAINT IF EXISTS fk_cms_item_cat;
ALTER TABLE public.cms_content_items DROP CONSTRAINT IF EXISTS fk_cms_item_author;
ALTER TABLE public.cms_content_translations DROP CONSTRAINT IF EXISTS fk_cms_contrans_item;
ALTER TABLE public.cms_content_translations DROP CONSTRAINT IF EXISTS fk_cms_contrans_lang;

-- API Management Module Constraints Drop
ALTER TABLE public.system_api_integrations DROP CONSTRAINT IF EXISTS fk_sysapi_partner;
ALTER TABLE public.api_clients DROP CONSTRAINT IF EXISTS fk_apiclients_partner;
ALTER TABLE public.api_keys DROP CONSTRAINT IF EXISTS fk_apikeys_client;
ALTER TABLE public.api_client_permissions DROP CONSTRAINT IF EXISTS fk_aclientperm_client;
ALTER TABLE public.api_client_permissions DROP CONSTRAINT IF EXISTS fk_aclientperm_perm;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Accommodation Module Relationships
ALTER TABLE public.acc_properties
    ADD CONSTRAINT fk_acc_prop_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_acc_prop_address FOREIGN KEY (address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.acc_property_features_link
    ADD CONSTRAINT fk_acc_pflink_prop FOREIGN KEY (property_id) REFERENCES public.acc_properties(
        property_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_acc_pflink_feat FOREIGN KEY (feature_code) REFERENCES public.lkp_property_features(
        feature_code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.acc_room_types
    ADD CONSTRAINT fk_acc_room_prop FOREIGN KEY (property_id) REFERENCES public.acc_properties(
        property_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_acc_room_curr FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.acc_room_amenities_link
    ADD CONSTRAINT fk_acc_ralink_room FOREIGN KEY (room_type_id) REFERENCES public.acc_room_types(
        room_type_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_acc_ralink_amen FOREIGN KEY (amenity_code) REFERENCES public.lkp_room_amenities(
        amenity_code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.acc_inventory_calendar
    ADD CONSTRAINT fk_acc_inv_room FOREIGN KEY (room_type_id) REFERENCES public.acc_room_types(
        room_type_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_acc_inv_curr FOREIGN KEY (currency_code) REFERENCES public.lkp_currencies(
        currency_code
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

-- FKs for booking_accommodation_details (Using COMPOSITE FK to booking_bookings)
ALTER TABLE public.booking_accommodation_details
    ADD CONSTRAINT fk_bacc_booking FOREIGN KEY (booking_created_at, booking_id) REFERENCES public.booking_bookings(
        created_at, booking_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bacc_prop FOREIGN KEY (property_id) REFERENCES public.acc_properties(
        property_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_bacc_room FOREIGN KEY (room_type_id) REFERENCES public.acc_room_types(
        room_type_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;


-- Section: CMS Module Relationships
ALTER TABLE public.cms_categories
    ADD CONSTRAINT fk_cms_cat_parent FOREIGN KEY (parent_category_id) REFERENCES public.cms_categories(
        category_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.cms_categories_translations
    ADD CONSTRAINT fk_cms_cattrans_cat FOREIGN KEY (category_id) REFERENCES public.cms_categories(
        category_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cms_cattrans_lang FOREIGN KEY (language_code) REFERENCES public.lkp_languages(
        code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.cms_content_items
    ADD CONSTRAINT fk_cms_item_cat FOREIGN KEY (category_id) REFERENCES public.cms_categories(
        category_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cms_item_author FOREIGN KEY (author_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.cms_content_translations
    ADD CONSTRAINT fk_cms_contrans_item FOREIGN KEY (item_id) REFERENCES public.cms_content_items(
        item_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_cms_contrans_lang FOREIGN KEY (language_code) REFERENCES public.lkp_languages(
        code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


-- Section: API Management Module Relationships
ALTER TABLE public.system_api_integrations
    ADD CONSTRAINT fk_sysapi_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.api_clients
    ADD CONSTRAINT fk_apiclients_partner FOREIGN KEY (partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.api_keys
    ADD CONSTRAINT fk_apikeys_client FOREIGN KEY (client_id) REFERENCES public.api_clients(
        client_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.api_client_permissions
    ADD CONSTRAINT fk_aclientperm_client FOREIGN KEY (client_id) REFERENCES public.api_clients(
        client_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_aclientperm_perm FOREIGN KEY (permission_code) REFERENCES public.lkp_api_permissions(
        permission_code
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Section: Auth User Link (Commented Out)
-- FK to auth.users omitted for portability.

-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- acc_properties -> fleet_partners (partner_id -> partner_id) [SET NULL]
-- acc_properties -> core_addresses (address_id -> address_id) [RESTRICT]
-- acc_property_features_link -> acc_properties (property_id -> property_id) [CASCADE]
-- acc_property_features_link -> lkp_property_features (feature_code -> feature_code) [CASCADE]
-- acc_room_types -> acc_properties (property_id -> property_id) [CASCADE]
-- acc_room_types -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- acc_room_amenities_link -> acc_room_types (room_type_id -> room_type_id) [CASCADE]
-- acc_room_amenities_link -> lkp_room_amenities (amenity_code -> amenity_code) [CASCADE]
-- acc_inventory_calendar -> acc_room_types (room_type_id -> room_type_id) [CASCADE]
-- acc_inventory_calendar -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- booking_accommodation_details -> booking_bookings (booking_created_at, 
    --booking_id -> created_at, booking_id) [CASCADE] -- COMPOSITE FK
-- booking_accommodation_details -> acc_properties (property_id -> property_id) [RESTRICT]
-- booking_accommodation_details -> acc_room_types (room_type_id -> room_type_id) [RESTRICT]
-- booking_accommodation_details -> core_addresses (pickup_location_id -> address_id) [RESTRICT]
-- booking_accommodation_details -> core_addresses (dropoff_location_id -> address_id) [RESTRICT]
-- booking_accommodation_details -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- cms_categories -> cms_categories (parent_category_id -> category_id) [SET NULL]
-- cms_categories_translations -> cms_categories (category_id -> category_id) [CASCADE]
-- cms_categories_translations -> lkp_languages (language_code -> code) [CASCADE]
-- cms_content_items -> cms_categories (category_id -> category_id) [SET NULL]
-- cms_content_items -> core_user_profiles (author_id -> user_id) [SET NULL]
-- cms_content_translations -> cms_content_items (item_id -> item_id) [CASCADE]
-- cms_content_translations -> lkp_languages (language_code -> code) [CASCADE]
--
-- system_api_integrations -> fleet_partners (partner_id -> partner_id) [SET NULL]
-- api_clients -> fleet_partners (partner_id -> partner_id) [SET NULL]
-- api_keys -> api_clients (client_id -> client_id) [CASCADE]
-- api_client_permissions -> api_clients (client_id -> client_id) [CASCADE]
-- api_client_permissions -> lkp_api_permissions (permission_code -> permission_code) [CASCADE]
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.3__Constraints_Acc_Cms_Api.sql (Version 1.3)
-- ============================================================================
