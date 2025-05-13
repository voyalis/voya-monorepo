-- ============================================================================
-- Migration: 011_finance_core.sql (Version 1.2 - Added booking_created_at for FKs)
-- Description: VoyaGo - Core Finance Tables: Payouts, Commission Rules,
--              Transaction Commissions, Invoice References. Adds partition key columns for composite FKs.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql, 010_booking_core.sql,
--               011_payment_wallet.sql (This file!)
-- ============================================================================

BEGIN;

-- Prefix 'fin_' denotes tables related to the Finance module.
-- Prefix 'pmt_' reused from previous migration for consistency.

-------------------------------------------------------------------------------
-- 1. Payments (pmt_payments) - ** booking_created_at ADDED **
-- Description: Records payment attempts and transactions within the platform.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pmt_payments (
    payment_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Optional link to the booking (Composite FK defined later)
    booking_id              UUID NULL,
    booking_created_at      TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    -- User initiating or associated with the payment
    user_id                 UUID NOT NULL,
    -- Payment amount (positive value)
    amount                  NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    -- Currency of the payment
    currency_code           CHAR(3) NOT NULL,
    -- Current status of the payment (ENUM from 001)
    status                  public.payment_status NOT NULL DEFAULT 'PENDING',
    -- Purpose of the payment (ENUM from 001)
    purpose                 public.payment_purpose NOT NULL,
    -- Payment method used (FK defined later)
    payment_method_id       UUID NULL,
    -- Reference ID from the external payment gateway
    gateway_reference_id    TEXT NULL,
    -- Payment Intent ID from the gateway (e.g., Stripe pi_xxx), should be unique if present
    payment_intent_id       TEXT UNIQUE NULL,
    -- Link to a related payment (e.g., original payment for a refund)
    related_payment_id      UUID NULL,
    -- Applied promotion code, if any
    applied_promo_code      VARCHAR(50) NULL,
    -- Calculated tax amount included in the payment
    tax_amount              NUMERIC(12,2) NULL CHECK (tax_amount IS NULL OR tax_amount >= 0),
    -- Error message from the gateway or system if payment failed
    error_message           TEXT NULL,
    -- Error code from the gateway or system
    error_code              VARCHAR(50) NULL,
    -- Additional metadata
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_pmt_booking_created_at CHECK (booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.pmt_payments
    IS '[VoyaGo][Payment] Records payment attempts and their outcomes.';
COMMENT ON COLUMN public.pmt_payments.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if booking_id is not NULL).';
COMMENT ON COLUMN public.pmt_payments.gateway_reference_id
    IS 'Transaction ID or reference provided by the external payment gateway.';
COMMENT ON COLUMN public.pmt_payments.payment_intent_id
    IS 'Unique identifier for the payment attempt provided by the gateway (e.g., Stripe PaymentIntent ID).';
COMMENT ON COLUMN public.pmt_payments.related_payment_id
    IS 'Reference to another payment, e.g., the original payment for a refund transaction.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_pmt_payments ON public.pmt_payments;
CREATE TRIGGER trg_set_timestamp_on_pmt_payments
    BEFORE UPDATE ON public.pmt_payments
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Payments
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_pmt_payments_booking
    ON public.pmt_payments(booking_id, booking_created_at) WHERE booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_pmt_payments_user
    ON public.pmt_payments(user_id);
CREATE INDEX IF NOT EXISTS idx_pmt_payments_status
    ON public.pmt_payments(status);
CREATE INDEX IF NOT EXISTS idx_pmt_payments_purpose
    ON public.pmt_payments(purpose);
CREATE INDEX IF NOT EXISTS idx_pmt_payments_gateway_ref
    ON public.pmt_payments(gateway_reference_id) WHERE gateway_reference_id IS NOT NULL;
-- Unique constraint on payment_intent_id already creates an index.
CREATE INDEX IF NOT EXISTS idx_pmt_payments_related
    ON public.pmt_payments(related_payment_id) WHERE related_payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_pmt_payments_metadata
    ON public.pmt_payments USING GIN (metadata) WHERE metadata IS NOT NULL;


-------------------------------------------------------------------------------
-- 2. User Wallet Transactions (pmt_user_wallet_transactions) - ** booking_created_at ADDED **
-- Description: Logs all balance changes in user wallets.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.pmt_user_wallet_transactions (
    transaction_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- User whose wallet is affected
    user_id             UUID NOT NULL,
    -- Type of transaction (ENUM from 001)
    type                public.wallet_transaction_type NOT NULL,
    -- Amount debited or credited (must not be zero)
    amount              NUMERIC(12, 2) NOT NULL CHECK (amount != 0),
    -- Currency of the transaction
    currency_code       CHAR(3) NOT NULL,
    -- Wallet balance *after* this transaction was successfully applied
    balance_after       NUMERIC(14, 2) NOT NULL,
    -- Link to the payment that triggered this transaction (e.g., top-up payment)
    related_payment_id  UUID NULL,
    -- Link to the booking related to this transaction (Composite FK defined later)
    related_booking_id  UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN (Partition Key for FK)
    -- Link to the promotion that generated this credit (if applicable)
    related_promo_id    UUID NULL,
    -- Optional external reference for reconciliation
    external_reference  TEXT NULL,
    -- Key provided by the client API call to prevent duplicate processing
    idempotency_key     TEXT NULL,
    -- Description of the transaction
    description         TEXT NULL,
    -- Timestamp of the transaction
    timestamp           TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,

    CONSTRAINT chk_puwt_booking_created_at CHECK (related_booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.pmt_user_wallet_transactions
    IS '[VoyaGo][Payment] Logs balance movements (debits/credits) for user wallets.';
COMMENT ON COLUMN public.pmt_user_wallet_transactions.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key 
    (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.pmt_user_wallet_transactions.balance_after
    IS '[VoyaGo][Concurrency] Wallet balance after the transaction completed. 
    Must be updated atomically (e.g., using Stored Procedure with FOR UPDATE lock).';
COMMENT ON COLUMN public.pmt_user_wallet_transactions.idempotency_key
    IS '[VoyaGo] Unique key provided by API clients to prevent accidental 
    duplicate processing of the same transaction request.';

-- Indexes for Wallet Transactions
CREATE INDEX IF NOT EXISTS idx_puwt_user_time
    ON public.pmt_user_wallet_transactions(user_id, timestamp DESC); -- Get user's recent transactions
CREATE INDEX IF NOT EXISTS idx_puwt_type
    ON public.pmt_user_wallet_transactions(type);
CREATE INDEX IF NOT EXISTS idx_puwt_related_payment
    ON public.pmt_user_wallet_transactions(related_payment_id) WHERE related_payment_id IS NOT NULL;
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_puwt_related_booking
    ON public.pmt_user_wallet_transactions(related_booking_id, booking_created_at) WHERE related_booking_id IS NOT NULL;

-- Corrected Partial Unique Index for Idempotency (v1.1 Fix)
DROP INDEX IF EXISTS public.uidx_puwt_idempotency;
DROP INDEX IF EXISTS public.idx_puwt_user_idempotency;
CREATE UNIQUE INDEX idx_puwt_user_idempotency
    ON public.pmt_user_wallet_transactions (user_id, idempotency_key)
    WHERE idempotency_key IS NOT NULL;
COMMENT ON INDEX public.idx_puwt_user_idempotency
    IS '[VoyaGo][Concurrency] Ensures a user cannot reuse the same idempotency key, 
        preventing duplicate wallet operations when a key is provided.';

-- Note: No updated_at trigger needed for wallet transactions (append-only log).


-------------------------------------------------------------------------------
-- 3. Payouts (fin_payouts) - Moved from 012, ** Renamed from fin_payouts **
-- Description: Tracks payout records for partners and drivers.
-------------------------------------------------------------------------------
-- This table seems more related to Finance core than Payment/Wallet,
-- but was included in the original 011 script provided. Keeping it here.
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
    requested_at            TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    approved_at             TIMESTAMPTZ NULL, -- Timestamp of approval
    processed_at            TIMESTAMPTZ NULL, -- Timestamp when processing started (e.g., sent to payment provider)
    paid_at                 TIMESTAMPTZ NULL, -- Timestamp when payment confirmation received
    external_transaction_ref TEXT NULL,       -- Reference ID from the payment provider
    notes                   TEXT NULL,        -- Internal notes about the payout
    updated_at              TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_payout_entity CHECK (partner_id IS NOT NULL OR driver_id IS NOT NULL),
    CONSTRAINT chk_payout_single_entity CHECK (NOT (partner_id IS NOT NULL AND driver_id IS NOT NULL)),
    CONSTRAINT chk_payout_dates CHECK (payout_period_end >= payout_period_start)
);
COMMENT ON TABLE public.fin_payouts
    IS '[VoyaGo][Finance] Tracks payout records generated for partners or drivers.';
-- Comments on columns remain the same...

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_payouts ON public.fin_payouts;
CREATE TRIGGER trg_set_timestamp_on_fin_payouts
    BEFORE UPDATE ON public.fin_payouts
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Payouts remain the same...
CREATE INDEX IF NOT EXISTS idx_fin_payouts_partner_period 
    ON public.fin_payouts(partner_id, payout_period_end DESC) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_payouts_driver_period 
    ON public.fin_payouts(driver_id, payout_period_end DESC) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_payouts_status ON public.fin_payouts(status);


-------------------------------------------------------------------------------
-- 4. Commission Rules (fin_commission_rules) - Moved from 012
-------------------------------------------------------------------------------
-- This table seems more related to Finance core than Payment/Wallet.
CREATE TABLE IF NOT EXISTS public.fin_commission_rules (
    rule_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name                VARCHAR(100) NOT NULL UNIQUE,
    partner_id          UUID NULL,
    service_code        public.service_code NULL,
    commission_type     public.commission_type NOT NULL, -- Uses ENUM
    commission_value    NUMERIC(10, 4) NOT NULL CHECK (commission_value >= 0),
    currency_code       CHAR(3) NULL,     -- Required if commission_type is FIXED_AMOUNT
    priority            INTEGER DEFAULT 0 NOT NULL,
    valid_from          DATE NULL,
    valid_to            DATE NULL,
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,
    CONSTRAINT chk_commission_rule_dates CHECK (valid_from IS NULL OR valid_to IS NULL OR valid_from <= valid_to),
    CONSTRAINT chk_commission_currency CHECK (commission_type != 'FIXED_AMOUNT' OR currency_code IS NOT NULL)
);
COMMENT ON TABLE public.fin_commission_rules
    IS '[VoyaGo][Finance] Defines rules for calculating platform commissions, 
        applicable globally or per partner/service.';
-- Comments on columns remain the same...

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_commission_rules ON public.fin_commission_rules;
CREATE TRIGGER trg_set_timestamp_on_fin_commission_rules
    BEFORE UPDATE ON public.fin_commission_rules
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Commission Rules remain the same...
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_partner_active 
    ON public.fin_commission_rules(partner_id, is_active, priority DESC, valid_to) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_service_active 
    ON public.fin_commission_rules(service_code, is_active, priority DESC, valid_to) WHERE service_code IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_comm_rules_global_active 
    ON public.fin_commission_rules(is_active, priority DESC, valid_to) WHERE partner_id IS NULL
    AND service_code IS NULL;


-------------------------------------------------------------------------------
-- 5. Transaction Commissions (fin_transaction_commissions) - ** booking_created_at ADDED **
-- Description: Records calculated commission amounts for specific transactions.
-------------------------------------------------------------------------------
-- This table seems more related to Finance core than Payment/Wallet.
CREATE TABLE IF NOT EXISTS public.fin_transaction_commissions (
    commission_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Source of the commission calculation (Composite FK for booking)
    source_payment_id   UUID NULL,
    source_booking_id   UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    -- Rule used for calculation
    commission_rule_id  UUID NULL,
    -- Calculated Amount
    calculated_amount   NUMERIC(12, 4) NOT NULL CHECK (calculated_amount >= 0),
    currency_code       CHAR(3) NOT NULL,
    -- Details of calculation (base amount, rate/value used)
    calculation_details JSONB NULL CHECK (calculation_details IS NULL OR jsonb_typeof(calculation_details) = 'object'),
    -- Denormalized type for easier reporting
    commission_type     public.commission_type NULL, -- Uses ENUM
    -- Entities involved
    partner_id          UUID NULL,
    driver_id           UUID NULL,
    -- Timestamp
    transaction_time    TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),

    CONSTRAINT chk_ftc_booking_created_at CHECK (source_booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.fin_transaction_commissions
    IS '[VoyaGo][Finance] Records individual commission amounts calculated for transactions (payments, bookings).';
COMMENT ON COLUMN public.fin_transaction_commissions.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if source_booking_id is not NULL).';
-- Other comments remain the same...

-- Indexes for Transaction Commissions
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_payment
    ON public.fin_transaction_commissions(source_payment_id) WHERE source_payment_id IS NOT NULL;
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_booking
    ON public.fin_transaction_commissions(source_booking_id, booking_created_at) WHERE source_booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_partner_time
    ON public.fin_transaction_commissions(partner_id, transaction_time DESC) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_driver_time
    ON public.fin_transaction_commissions(driver_id, transaction_time DESC) WHERE driver_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_txn_comm_rule
    ON public.fin_transaction_commissions(commission_rule_id) WHERE commission_rule_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_fin_txn_comm_details
    ON public.fin_transaction_commissions USING GIN (calculation_details) WHERE calculation_details IS NOT NULL;


-------------------------------------------------------------------------------
-- 6. Invoice References (fin_invoice_references) - ** booking_created_at ADDED **
-- Description: Stores references to invoices generated in an external finance system.
-------------------------------------------------------------------------------
-- This table seems more related to Finance core than Payment/Wallet.
CREATE TABLE IF NOT EXISTS public.fin_invoice_references (
    invoice_ref_id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Entity the invoice relates to
    organization_id     UUID NULL,
    user_id             UUID NULL,
    -- Related VoyaGo objects (Composite FK for booking)
    related_booking_id  UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
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
    CONSTRAINT chk_invoice_entity CHECK (
        organization_id IS NOT NULL
        OR user_id IS NOT NULL
        OR related_payout_id IS NOT NULL
        OR related_booking_id IS NOT NULL
    ),
    CONSTRAINT chk_fir_booking_created_at CHECK (related_booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.fin_invoice_references
    IS '[VoyaGo][Finance] Stores references to invoices generated in an external finance/accounting system.';
COMMENT ON COLUMN public.fin_invoice_references.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if related_booking_id is not NULL).';
-- Other comments remain the same...

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_fin_invoice_refs ON public.fin_invoice_references;
CREATE TRIGGER trg_set_timestamp_on_fin_invoice_refs
    BEFORE UPDATE ON public.fin_invoice_references
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Invoice References
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_org ON public.fin_invoice_references(organization_id, invoice_date DESC) 
    WHERE organization_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_user ON public.fin_invoice_references(user_id, invoice_date DESC) 
    WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_payout ON public.fin_invoice_references(related_payout_id) 
    WHERE related_payout_id IS NOT NULL;
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_booking ON public.fin_invoice_references(
    related_booking_id, booking_created_at
) 
    WHERE related_booking_id IS NOT NULL;
-- Unique constraint on external_invoice_id already creates an index
CREATE INDEX IF NOT EXISTS idx_fin_invoice_refs_status ON public.fin_invoice_references(status);


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- pmt_payments -> booking_bookings (booking_created_at, booking_id -> created_at, booking_id) 
    --[SET NULL?] -- COMPOSITE FK
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
-- pmt_user_wallet_transactions -> ??? (related_promo_id -> promotions.promotion_id) 
    --[SET NULL?] -- Needs Promotions module
--
-- fin_payouts -> fleet_partners (partner_id -> partner_id) [RESTRICT?]
-- fin_payouts -> fleet_drivers (driver_id -> driver_id) [RESTRICT?]
-- fin_payouts -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- fin_commission_rules -> fleet_partners (partner_id -> partner_id) [CASCADE?]
-- fin_commission_rules -> lkp_service_types (service_code -> service_code) [RESTRICT?]
-- fin_commission_rules -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
--
-- fin_transaction_commissions -> pmt_payments (source_payment_id -> payment_id) [SET NULL?]
-- fin_transaction_commissions -> booking_bookings (booking_created_at, source_booking_id -> 
    --created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- fin_transaction_commissions -> fin_commission_rules (commission_rule_id -> rule_id) [SET NULL]
-- fin_transaction_commissions -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- fin_transaction_commissions -> fleet_partners (partner_id -> partner_id) [SET NULL?]
-- fin_transaction_commissions -> fleet_drivers (driver_id -> driver_id) [SET NULL?]
--
-- fin_invoice_references -> core_organizations (organization_id -> organization_id) [RESTRICT?]
-- fin_invoice_references -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- fin_invoice_references -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- fin_invoice_references -> fin_payouts (related_payout_id -> payout_id) [SET NULL?]
-- fin_invoice_references -> lkp_currencies (currency_code -> currency_code) [RESTRICT]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 011_finance_core.sql (Version 1.2)
-- ============================================================================
