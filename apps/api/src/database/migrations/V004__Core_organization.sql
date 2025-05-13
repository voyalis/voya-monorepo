-- ============================================================================
-- Migration: 004_core_organization.sql
-- Description: Creates core organizational structure tables (organizations,
--              members, policies, billing accounts). Includes hierarchy support
--              and invitation mechanism. Foreign keys are defined as deferrable.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-04-19 -- (Assuming original date is intended)
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql, 003_core_user.sql
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Organizations (core_organizations)
-- Description: Defines organizations (corporations, partners, departments)
--              with support for hierarchical structures (parent/child).
-- ============================================================================
-- Enable trigram support for faster text similarity searches
CREATE EXTENSION IF NOT EXISTS pg_trgm;
COMMENT ON EXTENSION pg_trgm 
    IS '[VoyaGo][Optional] Provides functions and operators for determining 
        the similarity of text based on trigram matching.';

CREATE TABLE IF NOT EXISTS public.core_organizations (
    organization_id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    parent_organization_id  UUID NULL,        -- For hierarchy (Self-referencing FK defined below)
    name                    VARCHAR(150) NOT NULL, -- Display name of the organization
    legal_name              VARCHAR(200) NULL, -- Official legal name
    -- Type classification
    organization_type       VARCHAR(30) CHECK (
        organization_type IN ('CORPORATE', 'GOVERNMENT', 'NGO', 'EDUCATIONAL', 'INTERNAL_DEPARTMENT', 'OTHER')
    ),
    tax_id                  VARCHAR(50) NULL, -- Tax identification number
    tax_office              VARCHAR(100) NULL,-- Associated tax office
    address_id              UUID NULL,        -- FK to core_addresses (defined below)
    primary_contact_user_id UUID NULL,        -- FK to core_user_profiles (defined below)
    billing_details         JSONB NULL,       -- Basic billing info (e.g., {"invoice_email": "billing@corp.com"})
    status                  VARCHAR(30) DEFAULT 'ACTIVE' NOT NULL
    -- Operational status
    CHECK (status IN ('PENDING_VERIFICATION', 'ACTIVE', 'INACTIVE', 'SUSPENDED', 'MERGED', 'CLOSED')),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
);

COMMENT ON TABLE public.core_organizations
    IS '[VoyaGo][Core] Represents organizations (companies, partners, departments) 
        with support for hierarchical relationships.';
COMMENT ON COLUMN public.core_organizations.parent_organization_id
    IS 'References the parent organization ID for hierarchical structure 
        (e.g., subsidiary of a holding company).';
COMMENT ON COLUMN public.core_organizations.organization_type
    IS 'Classification of the organization type.';
COMMENT ON COLUMN public.core_organizations.billing_details
    IS '[VoyaGo] Basic billing contact information. Detailed accounts are in fin_corporate_billing_accounts. 
    Example: {"invoice_email": "billing@corp.com", "preferred_currency": "EUR"}';
COMMENT ON COLUMN public.core_organizations.status
IS 'Current operational status of the organization.';


-- Indexes for Organizations
CREATE INDEX IF NOT EXISTS idx_core_organizations_parent ON public.core_organizations(
    parent_organization_id
) WHERE parent_organization_id IS NOT NULL;
-- For faster ILIKE/similarity searches if pg_trgm extension is enabled
CREATE INDEX IF NOT EXISTS idx_core_organizations_name_trgm ON public.core_organizations USING gin (name gin_trgm_ops);
-- CREATE INDEX IF NOT EXISTS idx_core_organizations_name ON public.core_organizations(name); 
-- Standard index as alternative
CREATE INDEX IF NOT EXISTS idx_core_organizations_type ON public.core_organizations(organization_type);
CREATE INDEX IF NOT EXISTS idx_core_organizations_status ON public.core_organizations(status);


-- ============================================================================
-- 2. Organization Members (core_organization_members)
-- Description: Links users to organizations, defines their role within the
--              organization, and manages invitation status.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_organization_members (
    membership_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL, -- FK to core_organizations (defined below)
    user_id             UUID NOT NULL, -- FK to core_user_profiles (defined below)
    role                public.APP_ROLE NOT NULL, -- User's role within this org (ENUM from 001)
    status              VARCHAR(15) DEFAULT 'ACTIVE' NOT NULL CHECK (status IN ('ACTIVE', 'INVITED', 'DEACTIVATED')),
    invited_by          UUID NULL,     -- User who sent the invitation (FK to core_user_profiles, defined below)
    invite_token        TEXT UNIQUE NULL, -- Unique token for accepting the invitation (set to NULL upon acceptance)
    invite_expires_at   TIMESTAMPTZ NULL, -- Expiration date for the invitation token
    joined_at           TIMESTAMPTZ NULL, -- Timestamp when the user accepted the invite and became active
    -- Timestamp when the record (invite/membership) was created
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- updated_at is typically not needed; status changes track key events.

    -- Ensures a user has only one membership record per organization
    CONSTRAINT uq_org_member UNIQUE (organization_id, user_id)
);
COMMENT ON TABLE public.core_organization_members
IS '[VoyaGo][Core] Manages user membership within organizations, including roles and invitation lifecycle.';
COMMENT ON COLUMN public.core_organization_members.status
IS 'Status of the membership: INVITED (pending acceptance), ACTIVE, DEACTIVATED.';
COMMENT ON COLUMN public.core_organization_members.invite_token
IS 'Unique, short-lived token used for verifying and accepting membership invitations.';
COMMENT ON COLUMN public.core_organization_members.joined_at
IS 'Timestamp indicating when an invited user accepted the invitation.';
COMMENT ON CONSTRAINT uq_org_member ON public.core_organization_members
IS 'Ensures a user cannot be added to the same organization multiple times.';

-- Indexes for Organization Members
CREATE INDEX IF NOT EXISTS idx_core_org_members_user ON public.core_organization_members(user_id);
CREATE INDEX IF NOT EXISTS idx_core_org_members_org_role ON public.core_organization_members(organization_id, role);
CREATE INDEX IF NOT EXISTS idx_core_org_members_status ON public.core_organization_members(status);
CREATE UNIQUE INDEX IF NOT EXISTS uidx_core_org_members_active_token ON public.core_organization_members(invite_token)
WHERE invite_token IS NOT NULL AND status = 'INVITED'; -- Ensure uniqueness only for active invite tokens
COMMENT ON INDEX public.uidx_core_org_members_active_token
IS '[VoyaGo][Logic] Efficiently finds and ensures uniqueness of active invitation tokens.';


-- ============================================================================
-- 3. Corporate Travel Policies (core_corporate_travel_policies)
-- Description: Defines travel policies (spending limits, approvals, rules)
--              for organizations.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.core_corporate_travel_policies (
    policy_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID NOT NULL, -- FK to core_organizations (defined below)
    name            VARCHAR(100) NOT NULL, -- User-friendly name for the policy
    description     TEXT NULL,
    rules           JSONB NOT NULL, -- Flexible JSONB structure defining policy rules
    is_default      BOOLEAN DEFAULT FALSE NOT NULL, -- Is this the default policy for the organization?
    is_active       BOOLEAN DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.core_corporate_travel_policies
    IS '[VoyaGo][Core] Defines corporate travel policies, including spending limits, 
        approval workflows, and applicable rules.';
COMMENT ON COLUMN public.core_corporate_travel_policies.rules
    IS '[VoyaGo] Policy rules defined in JSONB. Example: {"max_trip_cost": {"amount": 150, "currency": "EUR"}, 
        "allowed_vehicle_types": ["SEDAN_ECO"], "time_restriction": {"days": ["Mon-Fri"], "start_time": "08:00"}, 
        "requires_approval_above": {"amount": 50, "currency": "EUR"}}';
COMMENT ON COLUMN public.core_corporate_travel_policies.is_default
    IS 'Indicates if this policy applies by default to members of the organization unless overridden.';

-- Indexes for Corporate Travel Policies
-- Find default active policy quickly
CREATE INDEX IF NOT EXISTS idx_core_corp_policies_org_default ON public.core_corporate_travel_policies(
    organization_id, is_default, is_active
);
CREATE INDEX IF NOT EXISTS idx_gin_core_corp_travel_policies_rules ON public.core_corporate_travel_policies USING gin (
    rules
);
COMMENT ON INDEX public.idx_gin_core_corp_travel_policies_rules
IS '[VoyaGo][Perf] GIN index for efficient searching within the JSONB policy rules.';


-- ============================================================================
-- 4. Corporate Billing Accounts (fin_corporate_billing_accounts)
-- Description: Stores billing account details specific to organizations.
-- Table Prefix: 'fin_' denotes finance-related tables.
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.fin_corporate_billing_accounts (
    billing_account_id  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id     UUID NOT NULL, -- FK to core_organizations (defined below)
    account_name        VARCHAR(100) NULL, -- Optional name (e.g., 'Marketing Dept Billing')
    billing_address_id  UUID NULL,     -- FK to core_addresses (defined below)
    -- payment_method_id UUID NULL,     -- Optional FK to a corporate payment method in pmt_payment_methods
    billing_cycle       VARCHAR(15) DEFAULT 'MONTHLY' NOT NULL
    CHECK (billing_cycle IN ('MONTHLY', 'WEEKLY', 'BI_WEEKLY', 'QUARTERLY')),
    -- Basic email format check
    invoice_email       TEXT CHECK (
        invoice_email IS NULL OR invoice_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
    ),
    vat_number          VARCHAR(50) NULL, -- VAT / Tax ID number for invoicing
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.fin_corporate_billing_accounts
IS '[VoyaGo][Finance] Stores billing account specifics for organizations, including address and invoicing preferences.';
COMMENT ON COLUMN public.fin_corporate_billing_accounts.billing_cycle
IS 'Frequency at which invoices are generated for this account.';
COMMENT ON COLUMN public.fin_corporate_billing_accounts.invoice_email
IS 'Primary email address for sending invoices related to this account.';


-- Indexes for Corporate Billing Accounts
CREATE INDEX IF NOT EXISTS idx_fin_corp_billing_org ON public.fin_corporate_billing_accounts(organization_id);


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for core_organizations
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_organizations ON public.core_organizations;
CREATE TRIGGER trg_set_timestamp_on_core_organizations
BEFORE UPDATE ON public.core_organizations
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for core_corporate_travel_policies
DROP TRIGGER IF EXISTS trg_set_timestamp_on_core_corp_policies ON public.core_corporate_travel_policies;
CREATE TRIGGER trg_set_timestamp_on_core_corp_policies
BEFORE UPDATE ON public.core_corporate_travel_policies
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for fin_corporate_billing_accounts
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_corp_billing ON public.fin_corporate_billing_accounts;
CREATE TRIGGER trg_set_timestamp_on_fin_corp_billing
BEFORE UPDATE ON public.fin_corporate_billing_accounts
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();


-- ============================================================================
-- Foreign Key Constraints (Defined as DEFERRABLE)
-- Note: Defining FKs at the end can simplify script structure, especially
--       with inter-table dependencies within the same migration.
--       Using DEFERRABLE INITIALLY DEFERRED allows inserting related rows
--       within a single transaction without strict ordering constraints.
-- ============================================================================

-- Foreign Keys for core_organizations
ALTER TABLE public.core_organizations
DROP CONSTRAINT IF EXISTS fk_org_parent_org,
DROP CONSTRAINT IF EXISTS fk_org_address,
DROP CONSTRAINT IF EXISTS fk_org_primary_contact;

ALTER TABLE public.core_organizations
ADD CONSTRAINT fk_org_parent_org FOREIGN KEY (parent_organization_id)
REFERENCES public.core_organizations(organization_id) ON DELETE SET NULL -- Keep child org if parent is deleted
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_org_address FOREIGN KEY (address_id)
REFERENCES public.core_addresses(address_id) ON DELETE SET NULL
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_org_primary_contact FOREIGN KEY (primary_contact_user_id)
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL
DEFERRABLE INITIALLY DEFERRED;
COMMENT ON CONSTRAINT fk_org_parent_org ON public.core_organizations 
    IS 'Constraint for organizational hierarchy (self-referencing).';


-- Foreign Keys for core_organization_members
ALTER TABLE public.core_organization_members
DROP CONSTRAINT IF EXISTS fk_member_organization,
DROP CONSTRAINT IF EXISTS fk_member_user,
DROP CONSTRAINT IF EXISTS fk_member_invited_by;

ALTER TABLE public.core_organization_members
ADD CONSTRAINT fk_member_organization FOREIGN KEY (organization_id)
REFERENCES public.core_organizations(organization_id) ON DELETE CASCADE -- Remove membership if org is deleted
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_member_user FOREIGN KEY (user_id)
REFERENCES public.core_user_profiles(user_id) ON DELETE CASCADE -- Remove membership if user profile is deleted
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_member_invited_by FOREIGN KEY (invited_by)
-- Keep invite record even if inviter is deleted
REFERENCES public.core_user_profiles(user_id) ON DELETE SET NULL
DEFERRABLE INITIALLY DEFERRED;


-- Foreign Keys for core_corporate_travel_policies
ALTER TABLE public.core_corporate_travel_policies
DROP CONSTRAINT IF EXISTS fk_policy_organization;

ALTER TABLE public.core_corporate_travel_policies
ADD CONSTRAINT fk_policy_organization FOREIGN KEY (organization_id)
REFERENCES public.core_organizations(organization_id) ON DELETE CASCADE -- Delete policies if org is deleted
DEFERRABLE INITIALLY DEFERRED;


-- Foreign Keys for fin_corporate_billing_accounts
ALTER TABLE public.fin_corporate_billing_accounts
DROP CONSTRAINT IF EXISTS fk_billing_organization,
DROP CONSTRAINT IF EXISTS fk_billing_address;

ALTER TABLE public.fin_corporate_billing_accounts
ADD CONSTRAINT fk_billing_organization FOREIGN KEY (organization_id)
-- Delete billing account if org is deleted
REFERENCES public.core_organizations(organization_id) ON DELETE CASCADE
DEFERRABLE INITIALLY DEFERRED,
ADD CONSTRAINT fk_billing_address FOREIGN KEY (billing_address_id)
REFERENCES public.core_addresses(address_id) ON DELETE SET NULL -- Keep billing account if address is deleted
DEFERRABLE INITIALLY DEFERRED;
-- Optional FK to pmt_payment_methods if needed for corporate cards:
-- ADD CONSTRAINT fk_billing_payment_method FOREIGN KEY (payment_method_id) 
--REFERENCES public.pmt_payment_methods(payment_method_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


COMMIT;

-- ============================================================================
-- End of Migration: 004_core_organization.sql
-- ============================================================================
