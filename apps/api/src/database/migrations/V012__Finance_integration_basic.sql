-- ============================================================================
-- Migration: 011_finance_core.sql (Version 1.1 - ENUM, Check, GIN Fix)
-- Description: VoyaGo - Core Finance Tables: Payouts, Commission Rules,
--              Transaction Commissions, Invoice References.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql, 010_booking_core.sql,
--               011_payment_wallet.sql (implicitly for pmt_payments link)
-- ============================================================================

BEGIN;

-- Prefix 'fin_' denotes tables related to the Finance module.

-------------------------------------------------------------------------------
-- 1. Payouts (fin_payouts)
-- Description: Tracks payout records for partners and drivers.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fin_payouts (
    payout_id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id              UUID NULL,        -- Target partner, if applicable
    driver_id               UUID NULL,        -- Target driver, if applicable
    payout_period_start     DATE NOT NULL,    -- Start date of the period this payout covers
    payout_period_end       DATE NOT NULL,    -- End date of the period this payout covers
    total_earnings          NUMERIC(14, 2) NOT NULL CHECK (total_earnings >= 0), -- Gross earnings in the period
    -- Total commission amount deducted
    commission_deducted     NUMERIC(14, 2) NOT NULL CHECK (commission_deducted >= 0),
    adjustments             NUMERIC(14, 2) DEFAULT 0 NOT NULL, -- Other adjustments (bonuses, penalties)
    payout_amount           NUMERIC(14, 2) NOT NULL CHECK (payout_amount >= 0), -- Final amount to be paid out
    currency_code           CHAR(3) NOT NULL,   -- Currency of the payout
    -- Payout status (ENUM from 001)
    status                  public.payout_status NOT NULL DEFAULT 'PENDING_CALCULATION',
    -- When the payout calculation was initiated/requested
    requested_at    TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    approved_at             TIMESTAMPTZ NULL, -- Timestamp of approval
    processed_at            TIMESTAMPTZ NULL, -- Timestamp when processing started (e.g., sent to payment provider)
    paid_at                 TIMESTAMPTZ NULL, -- Timestamp when payment confirmation received
    external_transaction_ref TEXT NULL,       -- Reference ID from the payment provider
    notes                   TEXT NULL,        -- Internal notes about the payout
    updated_at              TIMESTAMPTZ NULL, -- Automatically updated by trigger

    -- Ensure payout is linked to either a partner or a driver, but not neither
    CONSTRAINT chk_payout_entity CHECK (partner_id IS NOT NULL OR driver_id IS NOT NULL),
    -- Ensure only one entity is linked
    CONSTRAINT chk_payout_single_entity CHECK (NOT (partner_id IS NOT NULL AND driver_id IS NOT NULL)),
    CONSTRAINT chk_payout_dates CHECK (payout_period_end >= payout_period_start)
);
COMMENT ON TABLE public.fin_payouts
    IS '[VoyaGo][Finance] Tracks payout records generated for partners or drivers.';
COMMENT ON COLUMN public.fin_payouts.adjustments
    IS 'Sum of any adjustments like bonuses, penalties, or manual corrections applied to the payout.';
COMMENT ON COLUMN public.fin_payouts.payout_amount
    IS 'The final net amount transferred to the partner/driver (Earnings - Commission + Adjustments).';
COMMENT ON CONSTRAINT chk_payout_entity ON public.fin_payouts
    IS 'Ensures that each payout record is associated with either a partner or a driver.';
COMMENT ON CONSTRAINT chk_payout_single_entity ON public.fin_payouts
    IS 'Ensures that each payout record is associated with only one entity (either partner or driver).';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_payouts ON public.fin_payouts;
CREATE TRIGGER trg_set_timestamp_on_fin_payouts
    BEFORE UPDATE ON public.fin_payouts
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Payouts
CREATE INDEX IF NOT EXISTS idx_fin_payouts_partner_period
    ON public.fin_payouts(partner_id, payout_period_end DESC) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_payouts_driver_period
    ON public.fin_payouts(driver_id, payout_period_end DESC) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_payouts_status
    ON public.fin_payouts(status);


-------------------------------------------------------------------------------
-- 2. Commission Rules (fin_commission_rules)
-- Description: Defines rules for calculating platform commissions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fin_commission_rules (
    rule_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(100) NOT NULL UNIQUE, -- Descriptive name for the rule
    partner_id          UUID NULL,        -- Apply to a specific partner? (FK defined later)
    service_code        public.service_code NULL, -- Apply to a specific service type? (Uses ENUM from 001)
    commission_type     public.commission_type NOT NULL, -- How commission is calculated (ENUM from 001)
    -- Percentage (e.g., 15.50) or Fixed Amount
    commission_value    NUMERIC(10, 4) NOT NULL CHECK (commission_value >= 0),
    currency_code       CHAR(3) NULL,     -- Required if commission_type is FIXED_AMOUNT (FK defined later)
    priority            INTEGER DEFAULT 0 NOT NULL, -- Rule precedence (higher value = higher priority)
    valid_from          DATE NULL,        -- Rule validity start date
    valid_to            DATE NULL,        -- Rule validity end date
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_commission_rule_dates CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_from <= valid_to),
    -- Ensure currency is set if type is FIXED_AMOUNT
    CONSTRAINT chk_commission_currency CHECK (commission_type != 'FIXED_AMOUNT' OR currency_code IS NOT NULL)
);
COMMENT ON TABLE public.fin_commission_rules
    IS '[VoyaGo][Finance] Defines rules for calculating platform commissions, applicable globally 
        or per partner/service.';
COMMENT ON COLUMN public.fin_commission_rules.commission_value
    IS 'The value used for calculation (e.g., 15.5 for 15.5% percentage, or 5.00 for fixed amount).';
COMMENT ON COLUMN public.fin_commission_rules.priority
    IS 'Determines which rule applies if multiple match (higher value takes precedence).';
COMMENT ON CONSTRAINT chk_commission_currency ON public.fin_commission_rules
    IS 'Ensures that a currency code is provided when the commission type is a fixed amount.';


-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_commission_rules ON public.fin_commission_rules;
CREATE TRIGGER trg_set_timestamp_on_fin_commission_rules
    BEFORE UPDATE ON public.fin_commission_rules
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Commission Rules (Find applicable rules efficiently)
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_partner_active
    ON public.fin_commission_rules(partner_id, is_active, priority DESC, valid_to) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_service_active
    ON public.fin_commission_rules(service_code, is_active, priority DESC, valid_to) WHERE service_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_global_active
    ON public.fin_commission_rules(is_active, priority DESC, valid_to) 
    WHERE partner_id IS NULL AND service_code IS NULL;


-------------------------------------------------------------------------------
-- 3. Transaction Commissions (fin_transaction_commissions)
-- Description: Records calculated commission amounts for specific transactions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fin_transaction_commissions (
    commission_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Source of the commission calculation
    source_payment_id   UUID NULL,        -- Related payment (FK defined later)
    source_booking_id   UUID NULL,        -- Related booking (FK defined later)
    -- Rule used for calculation
    commission_rule_id  UUID NULL,        -- Rule applied (FK defined later)
    -- Calculated Amount
    calculated_amount   NUMERIC(12, 4) NOT NULL CHECK (calculated_amount >= 0),
    currency_code       CHAR(3) NOT NULL,   -- Currency of the commission (FK defined later)
    -- Details of calculation (base amount, rate/value used)
    calculation_details JSONB NULL CHECK (calculation_details IS NULL OR jsonb_typeof(calculation_details) = 'object'),
    -- Denormalized type for easier reporting
    commission_type     public.commission_type NULL, -- Type of commission applied (ENUM from 001)
    -- Entities involved
    partner_id          UUID NULL,        -- Partner involved (FK defined later)
    driver_id           UUID NULL,        -- Driver involved (FK defined later)
    -- Timestamp
    transaction_time    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
COMMENT ON TABLE public.fin_transaction_commissions
    IS '[VoyaGo][Finance] Records individual commission amounts calculated for transactions (payments, bookings).';
COMMENT ON COLUMN public.fin_transaction_commissions.calculation_details
    IS '[VoyaGo] Details of how the commission was calculated as JSONB. 
        Example: {"base_amount": 100.00, "rule_type": "PERCENTAGE", "rule_value": 15.50}';
COMMENT ON COLUMN public.fin_transaction_commissions.commission_type
    IS 'Denormalized commission type (from the applied rule) for easier querying.';

-- Indexes for Transaction Commissions
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_payment
    ON public.fin_transaction_commissions(source_payment_id) WHERE source_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_booking
    ON public.fin_transaction_commissions(source_booking_id) WHERE source_booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_partner_time
    ON public.fin_transaction_commissions(partner_id, transaction_time DESC) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_driver_time
    ON public.fin_transaction_commissions(driver_id, transaction_time DESC) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_rule
    ON public.fin_transaction_commissions(commission_rule_id) WHERE commission_rule_id IS NOT NULL;
-- GIN index for querying calculation details
CREATE INDEX IF NOT EXISTS idx_gin_fin_txn_comm_details
    ON public.fin_transaction_commissions USING GIN (calculation_details) WHERE calculation_details IS NOT NULL;
COMMENT ON INDEX public.idx_gin_fin_txn_comm_details
    IS '[VoyaGo][Perf] GIN index for querying commission calculation details stored in JSONB.';


-------------------------------------------------------------------------------
-- 4. Invoice References (fin_invoice_references)
-- Description: Stores references to invoices generated in an external finance system.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fin_invoice_references (
    invoice_ref_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Entity the invoice relates to
    organization_id     UUID NULL,
    user_id             UUID NULL,
    -- Related VoyaGo objects
    related_booking_id  UUID NULL,
    related_payout_id   UUID NULL,
    -- External Invoice Details
    external_invoice_id TEXT NOT NULL UNIQUE, -- ID from the external accounting/billing system
    invoice_date        DATE NOT NULL,
    due_date            DATE NULL,
    total_amount        NUMERIC(14, 2) NOT NULL CHECK (total_amount >= 0),
    currency_code       CHAR(3) NOT NULL,
    status              public.invoice_status NOT NULL DEFAULT 'DRAFT', -- Invoice status (ENUM from 001)
    -- Reference to the invoice document (e.g., PDF) stored securely
    pdf_url_vault_ref   TEXT NULL,
    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL, -- Automatically updated by trigger

    -- Ensure invoice is linked to at least one relevant entity
    CONSTRAINT chk_invoice_entity CHECK (organization_id IS NOT NULL
        OR user_id IS NOT NULL
        OR related_payout_id IS NOT NULL
        -- Added booking_id check
        OR related_booking_id IS NOT NULL
    )
);
COMMENT ON TABLE public.fin_invoice_references
    IS '[VoyaGo][Finance] Stores references to invoices generated in an external finance/accounting system.';
COMMENT ON COLUMN public.fin_invoice_references.external_invoice_id
    IS 'Unique identifier of the invoice in the external system.';
COMMENT ON COLUMN public.fin_invoice_references.pdf_url_vault_ref
    IS '[VoyaGo][Security] Secure reference (e.g., vault path or signed URL info) to the actual invoice PDF file,
        not a direct public URL.';
COMMENT ON CONSTRAINT chk_invoice_entity ON public.fin_invoice_references
    IS 'Ensures the invoice reference is associated with at least one relevant entity (Org, User, Payout, Booking).';


-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_invoice_refs ON public.fin_invoice_references;
CREATE TRIGGER trg_set_timestamp_on_fin_invoice_refs
    BEFORE UPDATE ON public.fin_invoice_references
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Invoice References
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_org
    ON public.fin_invoice_references(organization_id, invoice_date DESC) WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_user
    ON public.fin_invoice_references(user_id, invoice_date DESC) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_payout
    ON public.fin_invoice_references(related_payout_id) WHERE related_payout_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_booking
    ON public.fin_invoice_references(related_booking_id) WHERE related_booking_id IS NOT NULL;
-- UNIQUE constraint on external_invoice_id already creates an index
-- CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_external ON public.fin_invoice_references(external_invoice_id);
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_status
    ON public.fin_invoice_references(status);


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- --------------------------------------------------------------------------------------------------
-- fin_payouts -> fleet_partners (partner_id -> partner_id) [RESTRICT?]
-- fin_payouts -> fleet_drivers (driver_id -> driver_id) [RESTRICT?]
-- fin_payouts -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- fin_commission_rules -> fleet_partners (partner_id -> partner_id) [CASCADE?] -- Delete rules if partner deleted?
-- fin_commission_rules -> lkp_service_types (service_code -> service_code) [RESTRICT]
-- fin_commission_rules -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- fin_transaction_commissions -> pmt_payments (source_payment_id -> payment_id) [SET NULL?]
-- fin_transaction_commissions -> booking_bookings (source_booking_id -> booking_id) [SET NULL?] 
    -- Keep commission record even if booking deleted?
-- fin_transaction_commissions -> fin_commission_rules (commission_rule_id -> rule_id) [SET NULL] 
    -- Keep record even if rule deleted, use details?
-- fin_transaction_commissions -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- fin_transaction_commissions -> fleet_partners (partner_id -> partner_id) [SET NULL?]
-- fin_transaction_commissions -> fleet_drivers (driver_id -> driver_id) [SET NULL?]
--
-- fin_invoice_references -> core_organizations (organization_id -> organization_id) [RESTRICT?]
-- fin_invoice_references -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- fin_invoice_references -> booking_bookings (related_booking_id -> booking_id) [SET NULL?]
-- fin_invoice_references -> fin_payouts (related_payout_id -> payout_id) [SET NULL?]
-- fin_invoice_references -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 011_finance_core.sql (Version 1.1)
-- ============================================================================
