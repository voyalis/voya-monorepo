-- ============================================================================
-- Migration: V025.1__Constraints_Core.sql (Version 1.1 - Standardized)
-- Description: Add Foreign Key and Check constraints for Core User & Org modules.
--              Constraints are defined as DEFERRABLE INITIALLY DEFERRED.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining core user/org tables and related lookup tables
--               (e.g., 001, 002_*, 003, 004, 011)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- (DROP statements remain the same)
ALTER TABLE public.core_user_profiles DROP CONSTRAINT IF EXISTS fk_user_profiles_loyalty_tier;
ALTER TABLE public.core_user_profiles DROP CONSTRAINT IF EXISTS fk_user_profiles_language;
ALTER TABLE public.core_user_roles DROP CONSTRAINT IF EXISTS fk_user_roles_user;
ALTER TABLE public.core_user_roles DROP CONSTRAINT IF EXISTS fk_user_roles_assigned_by;
ALTER TABLE public.core_addresses DROP CONSTRAINT IF EXISTS fk_addresses_user;
ALTER TABLE public.pmt_payment_methods DROP CONSTRAINT IF EXISTS fk_payment_methods_user;
ALTER TABLE public.pmt_payment_methods DROP CONSTRAINT IF EXISTS fk_payment_methods_provider;
ALTER TABLE public.core_user_notification_preferences DROP CONSTRAINT IF EXISTS fk_user_notif_prefs_user;
ALTER TABLE public.core_user_devices DROP CONSTRAINT IF EXISTS fk_user_devices_user;
ALTER TABLE public.core_user_emergency_contacts DROP CONSTRAINT IF EXISTS fk_emergency_contacts_user;
ALTER TABLE public.core_organizations DROP CONSTRAINT IF EXISTS fk_organizations_parent;
ALTER TABLE public.core_organizations DROP CONSTRAINT IF EXISTS fk_organizations_address;
ALTER TABLE public.core_organizations DROP CONSTRAINT IF EXISTS fk_organizations_primary_contact;
ALTER TABLE public.core_organization_members DROP CONSTRAINT IF EXISTS fk_org_members_org;
ALTER TABLE public.core_organization_members DROP CONSTRAINT IF EXISTS fk_org_members_user;
ALTER TABLE public.core_organization_members DROP CONSTRAINT IF EXISTS fk_org_members_invited_by;
ALTER TABLE public.core_corporate_travel_policies DROP CONSTRAINT IF EXISTS fk_corp_policies_org;
ALTER TABLE public.fin_corporate_billing_accounts DROP CONSTRAINT IF EXISTS fk_corp_billing_org;
ALTER TABLE public.fin_corporate_billing_accounts DROP CONSTRAINT IF EXISTS fk_corp_billing_address;

-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: Core User Module Relationships
ALTER TABLE public.core_user_profiles
    ADD CONSTRAINT fk_user_profiles_loyalty_tier
        FOREIGN KEY (loyalty_tier_code) REFERENCES public.lkp_loyalty_tiers(tier_code)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_user_profiles_language
        FOREIGN KEY (language_code) REFERENCES public.lkp_languages(code)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_user_roles
    ADD CONSTRAINT fk_user_roles_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_user_roles_assigned_by
        FOREIGN KEY (assigned_by) REFERENCES public.core_user_profiles(user_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_addresses
    ADD CONSTRAINT fk_addresses_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.pmt_payment_methods
    ADD CONSTRAINT fk_payment_methods_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_payment_methods_provider
        FOREIGN KEY (provider_code) REFERENCES public.lkp_payment_providers(provider_code)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_user_notification_preferences
    ADD CONSTRAINT fk_user_notif_prefs_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_user_devices
    ADD CONSTRAINT fk_user_devices_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_user_emergency_contacts
    ADD CONSTRAINT fk_emergency_contacts_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


-- Section: Core Organization Module Relationships
ALTER TABLE public.core_organizations
    ADD CONSTRAINT fk_organizations_parent
        FOREIGN KEY (parent_organization_id) REFERENCES public.core_organizations(organization_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_organizations_address
        FOREIGN KEY (address_id) REFERENCES public.core_addresses(address_id)
        ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_organizations_primary_contact
        FOREIGN KEY (primary_contact_user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_organization_members
    ADD CONSTRAINT fk_org_members_org
        FOREIGN KEY (organization_id) REFERENCES public.core_organizations(organization_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_org_members_user
        FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(user_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_org_members_invited_by
        FOREIGN KEY (invited_by) REFERENCES public.core_user_profiles(user_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.core_corporate_travel_policies
    ADD CONSTRAINT fk_corp_policies_org
        FOREIGN KEY (organization_id) REFERENCES public.core_organizations(organization_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.fin_corporate_billing_accounts
    ADD CONSTRAINT fk_corp_billing_org
        FOREIGN KEY (organization_id) REFERENCES public.core_organizations(organization_id)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_corp_billing_address
        FOREIGN KEY (billing_address_id) REFERENCES public.core_addresses(address_id)
        ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Not part of this file's scope)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- Refer to subsequent V025.* migration files for constraints related to other modules.
-- --------------------------------------------------------------------------------------------------
-- core_user_profiles -> auth.users (user_id -> id) [OMITTED for portability]
-- ============================================================================

-- ============================================================================
-- End of Migration: V025.1__Constraints_Core.sql
-- ============================================================================
