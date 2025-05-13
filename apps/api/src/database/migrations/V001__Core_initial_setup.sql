-- ============================================================================
-- Migration: 001_core_initial_setup.sql (Version 1.5)
-- Description: VoyaGo Core Environment Setup: Installs required extensions,
--              creates a helper function for timestamp updates, and defines
--              all application-wide ENUM types.
-- Schema: public, extensions
-- Author: VoyaGo Team
-- Date: 2025-04-20
-- ============================================================================

BEGIN;

------------------------------------------------------------
-- 1. Required PostgreSQL Extensions
------------------------------------------------------------

-- Enable UUID generation functions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
COMMENT ON EXTENSION "uuid-ossp"
    IS '[VoyaGo][Required] Provides functions for generating Universally Unique Identifiers (UUIDs).';

-- Enable geospatial data types and functions
CREATE EXTENSION IF NOT EXISTS postgis;
COMMENT ON EXTENSION postgis
    IS '[VoyaGo][Required] Enables support for geographic objects and spatial queries.';

-- Enable GiST index operators for B-tree types (e.g., range types)
CREATE EXTENSION IF NOT EXISTS btree_gist;
COMMENT ON EXTENSION btree_gist
    IS '[VoyaGo][Required] Provides GiST index operator classes for B-tree comparable data types.';

-- Enable LTree data type for hierarchical tree-like structures
CREATE EXTENSION IF NOT EXISTS ltree;
COMMENT ON EXTENSION ltree
    IS '[VoyaGo][Optional] Provides data type for representing labels of data stored in a 
    hierarchical tree-like structure.';

-- Create schema for extensions to maintain separation (e.g., for pgcrypto, Supabase compatibility)
CREATE SCHEMA IF NOT EXISTS extensions;
COMMENT ON SCHEMA extensions
    IS '[VoyaGo][System] Schema dedicated to housing PostgreSQL extensions.';

-- Enable cryptographic functions within the 'extensions' schema
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
COMMENT ON EXTENSION pgcrypto
    IS '[VoyaGo][Required] Provides cryptographic functions, e.g., 
    for hashing/encrypting sensitive data like API keys.';

------------------------------------------------------------
-- 2. Helper Function: Automatic Timestamp Update
------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.vg_trigger_set_timestamp()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE -- Ensures the function is re-evaluated for each row
SECURITY INVOKER -- Executes with the privileges of the calling user
AS $$
BEGIN
    -- Only update updated_at column on UPDATE operations
    IF TG_OP = 'UPDATE' THEN
        -- Use clock_timestamp() for the actual time of modification,
        -- not the transaction start time.
        NEW.updated_at := clock_timestamp();
    END IF;
    RETURN NEW; -- Return the modified row to be inserted/updated
END;
$$;

COMMENT ON FUNCTION public.vg_trigger_set_timestamp()
    IS '[VoyaGo][Helper] Trigger function to automatically set the `updated_at` column to the 
    current timestamp on row updates.';

------------------------------------------------------------
-- 3. ENUM Type Definitions (Formatted for Readability and Length)
------------------------------------------------------------

-- Section 3.1: General & User Management ENUMs

DO $$
BEGIN
    CREATE TYPE public.payment_method_type AS ENUM (
        'CARD',
        'WALLET',
        'BANK_TRANSFER',
        'CORPORATE_ACCOUNT',
        'CASH'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL; -- Ignore if type already exists
END
$$;
COMMENT ON TYPE public.payment_method_type
    IS '[VoyaGo][ENUM] Defines the supported methods for processing payments.';

DO $$
BEGIN
    CREATE TYPE public.document_status AS ENUM (
        'MISSING',
        'UPLOADED',
        'PENDING_VERIFICATION',
        'VERIFIED',
        'REJECTED',
        'EXPIRED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.document_status
    IS '[VoyaGo][ENUM] Represents the lifecycle status of user or entity documents.';

DO $$
BEGIN
    CREATE TYPE public.app_role AS ENUM (
        'SYSTEM',
        'ADMIN',
        'SUPPORT_AGENT',
        'SUPPORT_LEAD',
        'OPS_MANAGER',
        'FLEET_MANAGER',
        'FINANCE_BASIC',
        'FINANCE_MANAGER',
        'MARKETING',
        'PARTNER_ADMIN',
        'PARTNER_USER',
        'DRIVER',
        'USER',
        'TRAVEL_ARRANGER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.app_role
    IS '[VoyaGo][ENUM] Defines application-level user roles for Role-Based Access Control (RBAC).';

DO $$
BEGIN
    CREATE TYPE public.address_type AS ENUM (
        'HOME',
        'WORK',
        'SAVED_PLACE',
        'POI',
        'STATION',
        'AIRPORT',
        'HOTEL',
        'RENTAL_LOCATION',
        'PICKUP_POINT',
        'DROPOFF_POINT',
        'OTHER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.address_type
    IS '[VoyaGo][ENUM] Classifies different types of saved addresses or locations.';

-- Section 3.2: Fleet & Service ENUMs

DO $$
BEGIN
    CREATE TYPE public.service_code AS ENUM (
        'TRANSFER',
        'SHUTTLE',
        'RENTAL',
        'CHAUFFEUR',
        'INTERCITY',
        'CARGO',
        'PUBLIC_TRANSPORT',
        'MICROMOBILITY',
        'ACCOMMODATION',
        'WALK',
        'WAIT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.service_code
    IS '[VoyaGo][ENUM] Identifies the primary service types offered on the platform.';

DO $$
BEGIN
    CREATE TYPE public.vehicle_category AS ENUM (
        'CAR',
        'VAN',
        'BUS',
        'TRUCK',
        'MOTORCYCLE',
        'BICYCLE',
        'SCOOTER',
        'OTHER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.vehicle_category
    IS '[VoyaGo][ENUM] Broad classification of vehicle types.';

DO $$
BEGIN
    CREATE TYPE public.vehicle_status AS ENUM (
        'AVAILABLE',
        'IN_USE',
        'MAINTENANCE',
        'INACTIVE',
        'BOOKED',
        'PENDING_INSPECTION',
        'DECOMMISSIONED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.vehicle_status
    IS '[VoyaGo][ENUM] Operational status of vehicles in the fleet.';

DO $$
BEGIN
    CREATE TYPE public.driver_status AS ENUM (
        'ACTIVE',
        'INACTIVE',
        'ON_TRIP',
        'OFFLINE',
        'PENDING_VERIFICATION',
        'SUSPENDED',
        'ONBOARDING'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.driver_status
    IS '[VoyaGo][ENUM] Operational and platform status of drivers.';

DO $$
BEGIN
    CREATE TYPE public.partner_type AS ENUM (
        'CORPORATE_FLEET',
        'RENTAL_COMPANY',
        'LOGISTICS_PROVIDER',
        'TAXI_FLEET',
        'INDIVIDUAL_DRIVER',
        'ACCOMMODATION_PROVIDER',
        'OTHER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.partner_type
    IS '[VoyaGo][ENUM] Types of business partners operating on the platform.';

DO $$
BEGIN
    CREATE TYPE public.property_type AS ENUM (
        'HOTEL',
        'APARTMENT',
        'HOSTEL',
        'GUEST_HOUSE',
        'RESORT',
        'VILLA',
        'OTHER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.property_type
    IS '[VoyaGo][ENUM] Types of accommodation properties.';

-- Section 3.3: Booking, Journey & Bidding ENUMs

DO $$
BEGIN
    CREATE TYPE public.booking_status AS ENUM (
        'DRAFT',
        'PENDING_PAYMENT',
        'PENDING_CONFIRMATION',
        'CONFIRMED',
        'DRIVER_ASSIGNED',
        'EN_ROUTE_PICKUP',
        'ARRIVED_PICKUP',
        'IN_PROGRESS',
        'COMPLETED',
        'CANCELLED_BY_USER',
        'CANCELLED_BY_DRIVER',
        'CANCELLED_BY_SYSTEM',
        'NO_SHOW',
        'FAILED',
        'PARTIALLY_COMPLETED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.booking_status
    IS '[VoyaGo][ENUM] Represents the lifecycle status of a booking.';

DO $$
BEGIN
    CREATE TYPE public.booking_leg_status AS ENUM (
        'PLANNED',
        'ASSIGNED',
        'EN_ROUTE_ORIGIN',
        'ARRIVED_ORIGIN',
        'IN_PROGRESS',
        'COMPLETED',
        'SKIPPED',
        'CANCELLED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.booking_leg_status
    IS '[VoyaGo][ENUM] Status of an individual leg within a multi-leg booking.';

DO $$
BEGIN
    CREATE TYPE public.bid_request_status AS ENUM (
        'OPEN',
        'CLOSED_ACCEPTED',
        'CLOSED_EXPIRED',
        'CLOSED_NO_BIDS',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.bid_request_status
    IS '[VoyaGo][ENUM] Status of requests for bids (price proposals).';

DO $$
BEGIN
    CREATE TYPE public.bid_status AS ENUM (
        'SUBMITTED',
        'RETRACTED',
        'ACCEPTED',
        'REJECTED',
        'EXPIRED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.bid_status
    IS '[VoyaGo][ENUM] Status of an individual bid submitted for a request.';

DO $$
BEGIN
    CREATE TYPE public.bidder_entity_type AS ENUM (
        'DRIVER',
        'PARTNER'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.bidder_entity_type
    IS '[VoyaGo][ENUM] Type of entity (Driver or Partner) submitting a bid.';

-- Section 3.4: Payment & Finance ENUMs

DO $$
BEGIN
    CREATE TYPE public.payment_status AS ENUM (
        'PENDING',
        'REQUIRES_ACTION',
        'REQUIRES_CAPTURE',
        'PROCESSING',
        'AUTHORIZED',
        'PAID',
        'FAILED',
        'REFUND_PENDING',
        'REFUNDED',
        'PARTIALLY_REFUNDED',
        'CHARGEBACK'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.payment_status
    IS '[VoyaGo][ENUM] Detailed status of payment processing.';

DO $$
BEGIN
    CREATE TYPE public.payment_purpose AS ENUM (
        'BOOKING_PAYMENT',
        'WALLET_TOPUP',
        'REFUND',
        'PLATFORM_FEE',
        'DRIVER_PAYOUT',
        'PARTNER_PAYOUT',
        'CANCELLATION_FEE',
        'ADJUSTMENT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.payment_purpose
    IS '[VoyaGo][ENUM] The reason or context for a specific payment transaction.';

DO $$
BEGIN
    CREATE TYPE public.wallet_transaction_type AS ENUM (
        'TOPUP',
        'BOOKING_PAYMENT',
        'REFUND_IN',
        'PAYOUT_OUT',
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'PROMO_CREDIT',
        'FEE'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.wallet_transaction_type
    IS '[VoyaGo][ENUM] Types of balance movements within a user''s wallet.';

DO $$
BEGIN
    CREATE TYPE public.invoice_status AS ENUM (
        'DRAFT',
        'SENT',
        'PENDING_PAYMENT',
        'PAID',
        'PARTIALLY_PAID',
        'OVERDUE',
        'CANCELLED',
        'VOID'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.invoice_status
    IS '[VoyaGo][ENUM][Finance] Status lifecycle of invoices.';

DO $$
BEGIN
    CREATE TYPE public.payout_status AS ENUM (
        'PENDING_CALCULATION',
        'PENDING_APPROVAL',
        'APPROVED',
        'PROCESSING',
        'PAID',
        'FAILED',
        'REJECTED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.payout_status
    IS '[VoyaGo][ENUM][Finance] Status of payout processes for drivers or partners.';

DO $$
BEGIN
    CREATE TYPE public.commission_type AS ENUM (
        'PERCENTAGE',
        'FIXED_AMOUNT',
        'PER_ITEM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.commission_type
    IS '[VoyaGo][ENUM][Finance] Method used for calculating commissions.';

-- Section 3.5: Cargo ENUMs

DO $$
BEGIN
    CREATE TYPE public.cargo_status AS ENUM (
        'ORDER_PLACED',
        'PICKUP_SCHEDULED',
        'PICKED_UP',
        'IN_TRANSIT',
        'AT_HUB',
        'OUT_FOR_DELIVERY',
        'DELIVERY_ATTEMPTED',
        'DELIVERED',
        'RETURNED',
        'CANCELLED',
        'EXCEPTION'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.cargo_status
    IS '[VoyaGo][ENUM] Tracking status of cargo shipments through the delivery process.';

DO $$
BEGIN
    CREATE TYPE public.cargo_partner_service_level AS ENUM (
        'STANDARD',
        'EXPRESS',
        'SAME_DAY',
        'OVERNIGHT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.cargo_partner_service_level
    IS '[VoyaGo][ENUM] Defines the service levels offered by cargo partners.';

-- Section 3.6: Support & Messaging ENUMs

DO $$
BEGIN
    CREATE TYPE public.support_ticket_status AS ENUM (
        'NEW',
        'OPEN',
        'PENDING_USER',
        'PENDING_AGENT',
        'IN_PROGRESS',
        'RESOLVED',
        'CLOSED',
        'REOPENED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.support_ticket_status
    IS '[VoyaGo][ENUM] Status lifecycle of customer support tickets.';

DO $$
BEGIN
    CREATE TYPE public.support_ticket_priority AS ENUM (
        'LOW',
        'MEDIUM',
        'HIGH',
        'URGENT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.support_ticket_priority
    IS '[VoyaGo][ENUM] Priority levels assigned to support tickets.';

DO $$
BEGIN
    CREATE TYPE public.rated_entity_type AS ENUM (
        'DRIVER',
        'VEHICLE',
        'PASSENGER',
        'SUPPORT_AGENT',
        'BOOKING',
        'ACCOMMODATION',
        'PROPERTY'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.rated_entity_type
    IS '[VoyaGo][Support][ENUM] Identifies the types of entities that can be rated or reviewed.';

DO $$
BEGIN
    CREATE TYPE public.message_status AS ENUM (
        'SENT',
        'DELIVERED',
        'READ',
        'FAILED',
        'DELETED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.message_status
    IS '[VoyaGo][Messaging][ENUM] Delivery and read status of messages within the platform.';

DO $$
BEGIN
    CREATE TYPE public.report_status AS ENUM (
        'NEW',
        'OPEN',
        'IN_REVIEW',
        'ACTION_TAKEN',
        'RESOLVED',
        'CLOSED',
        'REJECTED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.report_status
    IS '[VoyaGo][ENUM][Support] Status of user-submitted reports (distinct from analytics reports).';

-- Section 3.7: Notification ENUMs

DO $$
BEGIN
    CREATE TYPE public.notification_channel AS ENUM (
        'PUSH',
        'SMS',
        'EMAIL',
        'IN_APP',
        'WEBHOOK'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.notification_channel
    IS '[VoyaGo][ENUM] Channels through which notifications can be delivered.';

DO $$
BEGIN
    CREATE TYPE public.notification_type AS ENUM (
        'BOOKING_UPDATE',
        'PAYMENT_STATUS',
        'PROMOTION_OFFER',
        'SYSTEM_ALERT',
        'SUPPORT_UPDATE',
        'ACCOUNT_ACTIVITY',
        'GAMIFICATION_UPDATE',
        'DOCUMENT_EXPIRY',
        'NEW_MESSAGE'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.notification_type
    IS '[VoyaGo][ENUM] Categorizes the different types of notifications sent by the system.';

DO $$
BEGIN
    CREATE TYPE public.notification_status AS ENUM (
        'PENDING',
        'SCHEDULED',
        'SENT',
        'DELIVERED',
        'FAILED',
        'RETRY',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.notification_status
    IS '[VoyaGo][Notifications][ENUM] Lifecycle status of an individual notification.';

-- Section 3.8: Pricing & Promotion ENUMs

DO $$
BEGIN
    CREATE TYPE public.pricing_rule_type AS ENUM (
        'BASE_FARE',
        'ADJUSTMENT',
        'SURGE',
        'CUSTOM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.pricing_rule_type
    IS '[VoyaGo][Pricing][ENUM] Types of rules used in the pricing engine.';

DO $$
BEGIN
    CREATE TYPE public.promo_type AS ENUM (
        'PERCENTAGE_OFF',
        'FIXED_AMOUNT_OFF',
        'FREE_CREDIT',
        'BUY_ONE_GET_ONE',
        'CUSTOM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.promo_type
    IS '[VoyaGo][Promo][ENUM] Types of promotions or discounts offered.';

DO $$
BEGIN
    CREATE TYPE public.promo_status AS ENUM (
        'DRAFT',
        'ACTIVE',
        'PAUSED',
        'EXPIRED',
        'DISABLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.promo_status
    IS '[VoyaGo][Promo][ENUM] Activation status of a promotion.';

DO $$
BEGIN
    CREATE TYPE public.discount_type AS ENUM (
        'PERCENTAGE',
        'FIXED_AMOUNT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.discount_type
    IS '[VoyaGo][ENUM] Specifies how a discount is applied (percentage or fixed amount).';

-- Section 3.9: Gamification ENUMs

DO $$
BEGIN
    CREATE TYPE public.loyalty_transaction_type AS ENUM (
        'EARN_TRIP',
        'EARN_PROMO',
        'EARN_CHALLENGE',
        'EARN_REFERRAL',
        'SPEND_REWARD',
        'TIER_BONUS',
        'ADJUSTMENT_IN',
        'ADJUSTMENT_OUT',
        'EXPIRATION'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.loyalty_transaction_type
    IS '[VoyaGo][ENUM] Types of transactions affecting loyalty points.';

DO $$
BEGIN
    CREATE TYPE public.gam_transaction_type AS ENUM (
        'EARN',
        'SPEND',
        'EXPIRE',
        'ADJUSTMENT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.gam_transaction_type
    IS '[VoyaGo][Gamification][ENUM] General types of gamification point transactions.';

DO $$
BEGIN
    CREATE TYPE public.gam_challenge_status AS ENUM (
        'ACTIVE',
        'COMPLETED',
        'FAILED',
        'EXPIRED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.gam_challenge_status
    IS '[VoyaGo][Gamification][ENUM] Status of gamification challenges.';

-- Section 3.10: Dispatch ENUMs

DO $$
BEGIN
    CREATE TYPE public.dispatch_request_type AS ENUM (
        'BOOKING_TRANSFER',
        'BOOKING_CARGO',
        'BOOKING_SHUTTLE',
        'MM_RIDE_START'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.dispatch_request_type
    IS '[VoyaGo][Dispatch][ENUM] Type of work item to be dispatched.';

DO $$
BEGIN
    CREATE TYPE public.dispatch_request_status AS ENUM (
        'PENDING',
        'SEARCHING',
        'OFFERED',
        'ASSIGNED',
        'NO_DRIVER_FOUND',
        'CANCELLED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.dispatch_request_status
    IS '[VoyaGo][Dispatch][ENUM] Status of a central dispatch request.';

DO $$
BEGIN
    CREATE TYPE public.dispatch_assignment_status AS ENUM (
        'OFFERED',
        'ACCEPTED',
        'REJECTED',
        'EN_ROUTE_PICKUP',
        'ARRIVED_PICKUP',
        'STARTED',
        'COMPLETED',
        'CANCELLED_BY_DRIVER',
        'CANCELLED_BY_SYSTEM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.dispatch_assignment_status
    IS '[VoyaGo][Dispatch][ENUM] Status of a specific assignment offer made to a driver.';

-- Section 3.11: AI, Analytics & System ENUMs

DO $$
BEGIN
    CREATE TYPE public.ai_model_type AS ENUM (
        'RECOMMENDATION',
        'PRICING_SURGE',
        'ETA_PREDICTION',
        'FRAUD_DETECTION',
        'ROUTE_OPTIMIZATION',
        'DEMAND_FORECASTING',
        'PREDICTIVE_MAINTENANCE',
        'CUSTOM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.ai_model_type
    IS '[VoyaGo][AI][ENUM] Purpose or type of an AI/ML model used in the system.';

DO $$
BEGIN
    CREATE TYPE public.ai_training_status AS ENUM (
        'PENDING',
        'QUEUED',
        'RUNNING',
        'SUCCEEDED',
        'FAILED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.ai_training_status
    IS '[VoyaGo][AI][ENUM] Status of an AI model training job.';

DO $$
BEGIN
    CREATE TYPE public.ai_inference_status AS ENUM (
        'REQUESTED',
        'PROCESSING',
        'COMPLETED',
        'ERROR',
        'TIMEOUT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.ai_inference_status
    IS '[VoyaGo][AI][ENUM] Status of a request made to an AI model for inference.';

DO $$
BEGIN
    CREATE TYPE public.report_type AS ENUM (
        'OPERATIONAL',
        'FINANCIAL',
        'USER_BEHAVIOR',
        'MODEL_PERFORMANCE',
        'SYSTEM_HEALTH',
        'CUSTOM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.report_type
    IS '[VoyaGo][Analytics][ENUM] Categorization of different analytical reports.';

DO $$
BEGIN
    CREATE TYPE public.analysis_report_status AS ENUM (
        'PENDING',
        'GENERATING',
        'COMPLETED',
        'FAILED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.analysis_report_status
    IS '[VoyaGo][ENUM][Analytics] Status of a report generation job.';

DO $$
BEGIN
    CREATE TYPE public.system_log_level AS ENUM (
        'DEBUG',
        'INFO',
        'NOTICE',
        'WARN',
        'ERROR',
        'CRITICAL',
        'ALERT',
        'EMERGENCY'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.system_log_level
    IS '[VoyaGo][System] Severity levels for application and system logs.';

DO $$
BEGIN
    CREATE TYPE public.job_status AS ENUM (
        'ENABLED',
        'DISABLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.job_status
    IS '[VoyaGo][Jobs] Status indicating if a defined scheduled job is active.';

DO $$
BEGIN
    CREATE TYPE public.job_run_status AS ENUM (
        'PENDING',
        'RUNNING',
        'SUCCESS',
        'FAILED',
        'SKIPPED',
        'TIMEOUT'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.job_run_status
    IS '[VoyaGo][Jobs] Outcome status of a specific execution of a scheduled job.';

DO $$
BEGIN
    CREATE TYPE public.task_status AS ENUM (
        'PENDING',
        'IN_PROGRESS',
        'COMPLETED',
        'FAILED',
        'CANCELLED',
        'SKIPPED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.task_status
    IS '[VoyaGo][System][ENUM] General status for background tasks or processes 
        (e.g., maintenance, report generation).';

DO $$
BEGIN
    CREATE TYPE public.audit_action AS ENUM (
        'INSERT',
        'UPDATE',
        'DELETE'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.audit_action
    IS '[VoyaGo][ENUM] Action types recorded in audit logs.';

-- Section 3.12: Micromobility Specific ENUMs

DO $$
BEGIN
    CREATE TYPE public.mm_vehicle_status AS ENUM (
        'AVAILABLE',
        'IN_USE',
        'MAINTENANCE',
        'OFFLINE',
        'LOW_BATTERY',
        'DECOMMISSIONED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.mm_vehicle_status
    IS '[VoyaGo][Micromobility][ENUM] Status of micromobility vehicles like scooters or bikes.';

DO $$
BEGIN
    CREATE TYPE public.mm_ride_status AS ENUM (
        'REQUESTED',
        'ONGOING',
        'PAUSED',
        'COMPLETED',
        'CANCELLED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.mm_ride_status
    IS '[VoyaGo][Micromobility][ENUM] Status of a micromobility ride session.';

DO $$
BEGIN
    CREATE TYPE public.mm_event_type AS ENUM (
        'UNLOCK',
        'LOCK',
        'PAUSE',
        'RESUME',
        'BATTERY_UPDATE',
        'GEOFENCE_ENTER',
        'GEOFENCE_EXIT',
        'RIDE_START',
        'RIDE_END',
        'LOW_BATTERY_ALERT',
        'MAINTENANCE_REQUEST'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.mm_event_type
    IS '[VoyaGo][Micromobility][ENUM] Types of events related to micromobility vehicles and rides.';

-- Section 3.13: Shuttle Specific ENUMs

DO $$
BEGIN
    CREATE TYPE public.shuttle_status AS ENUM (
        'DRAFT',
        'ACTIVE',
        'SUSPENDED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shuttle_status
    IS '[VoyaGo][Shuttle][ENUM] Overall status of a defined shuttle service or route.';

DO $$
BEGIN
    CREATE TYPE public.shuttle_trip_status AS ENUM (
        'SCHEDULED',
        'READY',
        'DEPARTED',
        'IN_TRANSIT',
        'ARRIVED',
        'COMPLETED',
        'DELAYED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shuttle_trip_status
    IS '[VoyaGo][Shuttle][ENUM] Status of an individual shuttle trip execution.';

DO $$
BEGIN
    CREATE TYPE public.shuttle_boarding_status AS ENUM (
        'BOOKED',
        'CHECKED_IN',
        'BOARDED',
        'ALIGHTED',
        'MISSED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shuttle_boarding_status
    IS '[VoyaGo][Shuttle][ENUM] Status related to passenger boarding on a shuttle trip.';

-- Section 3.14: Rental & Shared Ride Specific ENUMs (Newly Added)

DO $$
BEGIN
    CREATE TYPE public.rental_availability_status AS ENUM (
        'BOOKED',
        'MAINTENANCE',
        'BLOCKED',
        'AVAILABLE'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.rental_availability_status
    IS '[VoyaGo][Rental][ENUM] Availability status of a rental vehicle for specific periods.';

DO $$
BEGIN
    CREATE TYPE public.rental_pricing_period AS ENUM (
        'HOUR',
        'DAY',
        'WEEK',
        'MONTH'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.rental_pricing_period
    IS '[VoyaGo][Rental][ENUM] Time units used for defining rental pricing.';

DO $$
BEGIN
    CREATE TYPE public.rental_extra_pricing_type AS ENUM (
        'PER_RENTAL',
        'PER_DAY'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.rental_extra_pricing_type
    IS '[VoyaGo][Rental][ENUM] Calculation basis for rental extra charges (e.g., GPS, child seat).';

DO $$
BEGIN
    CREATE TYPE public.rental_fuel_policy AS ENUM (
        'FULL_TO_FULL',
        'PREPAID_INCLUDED',
        'PREPAID_SEPARATE',
        'SAME_LEVEL'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.rental_fuel_policy
    IS '[VoyaGo][Rental][ENUM] Fuel policy applicable to the vehicle rental.';

DO $$
BEGIN
    CREATE TYPE public.shared_ride_request_status AS ENUM (
        'PENDING',
        'MATCHING_IN_PROGRESS',
        'MATCHED_PENDING_ACCEPTANCE',
        'ASSIGNED',
        'CANCELLED_BY_USER',
        'EXPIRED',
        'FAILED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shared_ride_request_status
    IS '[VoyaGo][SharedRide][ENUM] Status of a user''s request to join or initiate a shared ride.';

DO $$
BEGIN
    CREATE TYPE public.shared_ride_match_status AS ENUM (
        'PROPOSED',
        'CONFIRMED',
        'ASSIGNED_TO_DRIVER',
        'ACTIVE',
        'COMPLETED',
        'CANCELLED'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shared_ride_match_status
    IS '[VoyaGo][SharedRide][ENUM] Status of a potential or confirmed match between shared ride requests.';

DO $$
BEGIN
    CREATE TYPE public.shared_ride_assignment_status AS ENUM (
        'OFFERED',
        'ACCEPTED',
        'REJECTED',
        'EN_ROUTE_FIRST_PICKUP',
        'ACTIVE_PICKUPS',
        'ACTIVE_DROPOFFS',
        'COMPLETED',
        'CANCELLED_BY_DRIVER',
        'CANCELLED_BY_SYSTEM'
    );
EXCEPTION
    WHEN duplicate_object THEN NULL;
END
$$;
COMMENT ON TYPE public.shared_ride_assignment_status
    IS '[VoyaGo][SharedRide][ENUM] Status of assigning and executing a matched shared ride by a driver.';


COMMIT;

-- ============================================================================
-- End of Migration: 001_core_initial_setup.sql (Version 1.5)
-- ============================================================================
