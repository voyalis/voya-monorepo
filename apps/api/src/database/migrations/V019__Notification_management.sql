-- ============================================================================
-- Migration: 019_notification_management.sql (Version 1.2 - Added booking_created_at for FK)
-- Description: VoyaGo - Notification Management: Templates, Partitioned Queue,
--              Delivery Attempts Log, History. Adds partition key column for composite FK.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 002_lookup_data_*.sql (lkp_languages),
--               003_core_user.sql (core_user_profiles), 010_booking_core.sql,
--               018_support_messaging.sql (support_tickets)
-- ============================================================================

BEGIN;

-- Prefix 'notification_' used for tables related to the notification system,
-- except for the main queue table 'notifications'.

-------------------------------------------------------------------------------
-- 1. Notification Templates (notification_templates)
-- Description: Stores predefined message templates for different notification types,
--              channels, and languages.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_templates (
    template_id     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Unique code used by the application to reference this template type
    template_code   VARCHAR(50) NOT NULL UNIQUE,
    -- Type of notification this template is for (ENUM from 001)
    notification_type public.notification_type NOT NULL,
    -- Channel this template is designed for (ENUM from 001)
    channel_code    public.notification_channel NOT NULL,
    -- Language of this specific template version (FK defined later)
    language_code   CHAR(2) NOT NULL,
    -- Subject line template (for Email/SMS, may contain placeholders)
    subject_template TEXT NULL,
    -- Body content template (may contain placeholders like { {user_name} }, { {booking_number} } )
    body_template   TEXT NOT NULL,
    -- Additional metadata (e.g., priority, tags)
    metadata        JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    is_active       BOOLEAN DEFAULT TRUE NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL, -- Automatically updated by trigger

    -- Ensure uniqueness per template code and language
    CONSTRAINT uq_notification_template_code_lang UNIQUE (template_code, language_code)
);
COMMENT ON TABLE public.notification_templates
    IS '[VoyaGo][Notifications] Stores predefined message templates for 
        various notification types, channels, and languages.';
COMMENT ON COLUMN public.notification_templates.template_code
    IS 'Application-level unique identifier for a notification type 
        (e.g., ''booking_confirmed'', ''password_reset'').';
COMMENT ON COLUMN public.notification_templates.body_template
    IS 'Main content template. May contain placeholders 
        (e.g., using { {variable_name} } syntax) to be filled with dynamic data.';
COMMENT ON COLUMN public.notification_templates.metadata
    IS 'Additional configuration or metadata. 
        Example: {"sender_profile": "marketing", "unsubscribe_group": "promotions"}';


-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_notification_templates ON public.notification_templates;
CREATE TRIGGER trg_set_timestamp_on_notification_templates
    BEFORE UPDATE ON public.notification_templates
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Templates
-- Index for efficiently finding the right template based on type, channel, language, and status
CREATE INDEX IF NOT EXISTS idx_ntemplates_lookup
    ON public.notification_templates(template_code, language_code, is_active);


-------------------------------------------------------------------------------
-- 1.1 Notification Templates History (notification_templates_history)
-- Description: Audit trail for changes to notification_templates.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_templates_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,          -- User making the change
    template_id     UUID NOT NULL,      -- The template that was changed
    template_data   JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.notification_templates_history
    IS '[VoyaGo][Notifications][History] Audit log capturing changes to notification_templates records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_ntemplates_hist_tid
    ON public.notification_templates_history(template_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 Notification Templates History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_notification_template_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.notification_templates_history
            (action_type, actor_id, template_id, template_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.template_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_notification_template_history()
    IS '[VoyaGo][Notifications][TriggerFn] Logs previous state of notification_templates row to 
        history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_notification_template_history ON public.notification_templates;
CREATE TRIGGER audit_notification_template_history
    AFTER UPDATE OR DELETE ON public.notification_templates
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_notification_template_history();


-------------------------------------------------------------------------------
-- 2. Notifications Queue (notifications) - Partitioned Table - ** booking_created_at ADDED **
-- Description: Queue for storing notifications to be sent. Partitioned by scheduled time.
-- Note: Partitions must be created and managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications (
    -- Partition key must be part of the PK for partitioned tables
    -- Time the notification is scheduled for sending (Partition Key)
    scheduled_at        TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), 
    notification_id     UUID        NOT NULL DEFAULT uuid_generate_v4(), -- Unique ID for the notification instance
    -- Target User
    user_id             UUID        NOT NULL,       -- Recipient user (FK defined later)
    -- Template and Channel
    template_code       VARCHAR(50) NOT NULL,   -- Code of the template to use (language chosen based on user prefs)
    channel_code        public.notification_channel NOT NULL, -- Target channel (ENUM from 001)
    -- Delivery Info
    recipient_address   TEXT        NOT NULL,       -- Actual address (email, phone number, push token)
    -- Context (Optional - Composite FK for booking)
    related_booking_id  UUID        NULL,
    booking_created_at  TIMESTAMPTZ NULL,           -- <<< EKLENEN SÜTUN (Partition Key for FK)
    related_ticket_id   UUID        NULL,
    related_entity_type VARCHAR(50) NULL,           -- For other related entities
    related_entity_id   TEXT        NULL,
    -- Dynamic Content
    -- Data for template placeholders
    payload             JSONB       NULL CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object'), 
    -- Sending Status
    status              public.notification_status NOT NULL DEFAULT 'PENDING', -- Current status (ENUM from 001)
    attempts            SMALLINT    NOT NULL DEFAULT 0, -- Number of delivery attempts made
    last_attempt_at     TIMESTAMPTZ NULL,           -- Timestamp of the last delivery attempt
    last_error          TEXT        NULL,           -- Error message from the last failed attempt
    -- Timestamps
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL,           -- Automatically updated by trigger

    PRIMARY KEY (scheduled_at, notification_id),
    -- Check constraint for composite FK consistency
    CONSTRAINT chk_notif_booking_created_at CHECK (related_booking_id IS NULL OR booking_created_at IS NOT NULL)

) PARTITION BY RANGE (scheduled_at);

COMMENT ON TABLE public.notifications
    IS '[VoyaGo][Notifications] Queue for outgoing notifications, partitioned by scheduled_at time.';
COMMENT ON COLUMN public.notifications.booking_created_at
    IS 'Partition key copied from booking_bookings 
        for composite foreign key (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.notifications.template_code
    IS 'References the notification_templates.template_code. 
        The system selects the appropriate language variant based on user preferences.';
COMMENT ON COLUMN public.notifications.recipient_address
    IS 'The actual delivery address (e.g., email address, 
        phone number with country code, device push token).';
COMMENT ON COLUMN public.notifications.payload
    IS 'JSONB object containing key-value pairs to replace 
        placeholders in the notification template.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_notifications ON public.notifications;
CREATE TRIGGER trg_set_timestamp_on_notifications
    BEFORE UPDATE ON public.notifications
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Notifications Queue (Defined on main table)
-- Index critical for notification worker to find pending jobs
CREATE INDEX IF NOT EXISTS idx_notifications_status_sched
    ON public.notifications(status, scheduled_at)
    WHERE status IN ('PENDING', 'SCHEDULED', 'RETRY');
COMMENT ON INDEX public.idx_notifications_status_sched
    IS '[VoyaGo][Perf] Optimized index for the notification sending worker process.';
-- Index for viewing a user's notification history
CREATE INDEX IF NOT EXISTS idx_notifications_user_time
    ON public.notifications(user_id, scheduled_at DESC);
-- Index for finding notifications related to booking (using composite key)
CREATE INDEX IF NOT EXISTS idx_notifications_booking
    ON public.notifications(related_booking_id, booking_created_at) WHERE related_booking_id IS NOT NULL;
-- Index for finding notifications related to ticket
CREATE INDEX IF NOT EXISTS idx_notifications_ticket
    ON public.notifications(related_ticket_id) WHERE related_ticket_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 2.1 Notifications History (notifications_history)
-- Description: Audit trail for changes to notifications queue records.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notifications_history (
    history_id          BIGSERIAL PRIMARY KEY,
    action_type         public.audit_action NOT NULL,
    action_at           TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id            UUID NULL,
    notification_id     UUID NOT NULL,      -- The notification that was changed
    -- scheduled_at is part of PK in main table, but notification_id should be unique enough here
    notification_data   JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.notifications_history
    IS '[VoyaGo][Notifications][History] Audit log capturing changes to notifications queue records 
        (e.g., cancellations, status updates).';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_notifications_hist_nid
    ON public.notifications_history(notification_id, action_at DESC);

-------------------------------------------------------------------------------
-- 2.2 Notifications History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_notification_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.notifications_history
            (action_type, actor_id, notification_id, notification_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.notification_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_notification_history()
    IS '[VoyaGo][Notifications][TriggerFn] 
        Logs previous state of notifications row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_notification_history ON public.notifications;
CREATE TRIGGER audit_notification_history
    AFTER UPDATE OR DELETE ON public.notifications
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_notification_history();


-------------------------------------------------------------------------------
-- 3. Delivery Attempts Log (notification_delivery_attempts)
-- Description: Logs each attempt to deliver a notification via a specific channel/provider.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.notification_delivery_attempts (
    attempt_id          BIGSERIAL PRIMARY KEY,
    -- Link to the notification being attempted (FK uses notification_id only)
    notification_id     UUID        NOT NULL,
    -- Timestamp of the attempt
    attempt_time        TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- Channel used for this attempt (ENUM from 001)
    channel_code        public.notification_channel NOT NULL,
    -- Outcome of the attempt (ENUM from 001)
    status              public.notification_status NOT NULL, -- Expected values: SENT, FAILED, RETRY
    -- Optional reference ID from the delivery provider (e.g., SendGrid Message ID)
    provider_ref_id     TEXT        NULL,
    -- Optional error details from the provider
    error_code          VARCHAR(50) NULL,
    error_message       TEXT        NULL,
    -- Optional additional metadata returned by the provider
    metadata            JSONB       NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object')
);
COMMENT ON TABLE public.notification_delivery_attempts
    IS '[VoyaGo][Notifications][Log] Logs each attempt made to deliver a notification and the outcome.';
COMMENT ON COLUMN public.notification_delivery_attempts.notification_id
    IS 'References the notification being attempted. 
        Note: FK only needs notification_id as it''s unique across partitions.';
COMMENT ON COLUMN public.notification_delivery_attempts.status
    IS 'Status of this specific delivery attempt (e.g., SENT, FAILED).';

-- Indexes for Delivery Attempts
-- Critical index for retrieving delivery attempts for a specific notification
CREATE INDEX IF NOT EXISTS idx_nd_attempts_nid_time
    ON public.notification_delivery_attempts(notification_id, attempt_time DESC);
CREATE INDEX IF NOT EXISTS idx_nd_attempts_status
    ON public.notification_delivery_attempts(status);


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- notification_templates -> lkp_languages (language_code -> code) [CASCADE]
--
-- notification_templates_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- notification_templates_history -> notification_templates (template_id -> template_id) [CASCADE]
--
-- notifications -> core_user_profiles (user_id -> user_id) [CASCADE]
-- notifications -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [SET NULL] -- COMPOSITE FK
-- notifications -> support_tickets (related_ticket_id -> ticket_id) [SET NULL]
-- Note: notifications.template_code has no direct DB FK.
    --Application logic resolves template_id based on code & user language.
-- Note: FKs for related_entity_id are polymorphic.
--
-- notifications_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- notifications_history -> notifications (notification_id -> notification_id) [CASCADE?] 
    -- Refers to ID part of composite PK
--
-- notification_delivery_attempts -> notifications (notification_id -> notification_id) [CASCADE?] 
    -- Refers to ID part of composite PK
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 019_notification_management.sql (Version 1.2)
-- ============================================================================
