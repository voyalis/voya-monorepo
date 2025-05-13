-- ============================================================================
-- Migration: 022_system_management.sql (Version 1.3 - Standardized Formatting)
-- Description: VoyaGo - System Management: Data Audit Config & Log (Partitioned),
--              System/Event Logs, Feature Flags, Scheduled Jobs & Runs,
--              and ALL Helper Functions/Procedures definitions. (Syntax Fix in Audit Trigger confirmed)
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs, base functions),
--               003_core_user.sql (core_user_profiles for actor_id)
-- ============================================================================

BEGIN;

-- Prefixes 'audit_', 'system_' denote tables related to system-wide auditing,
-- logging, configuration, and job scheduling.

-------------------------------------------------------------------------------
-- 1. Data Audit Trigger Configuration (audit_trigger_config)
-- Description: Configures which table changes should be audited by the dynamic trigger.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_trigger_config (
    config_id           SERIAL PRIMARY KEY,
    target_schema       NAME NOT NULL DEFAULT 'public', -- Schema of the table to audit
    target_table        NAME NOT NULL,      -- Name of the table to audit
    enabled             BOOLEAN NOT NULL DEFAULT TRUE, -- Is auditing enabled for this table?
    excluded_columns    TEXT[] DEFAULT ARRAY['updated_at']::TEXT[], -- Columns to exclude from audit diffs
    track_inserts       BOOLEAN NOT NULL DEFAULT TRUE,
    track_updates       BOOLEAN NOT NULL DEFAULT TRUE,
    track_deletes       BOOLEAN NOT NULL DEFAULT TRUE,
    last_synced_at      TIMESTAMPTZ NULL,   -- Last time vg_sync_audit_triggers checked this config
    UNIQUE (target_schema, target_table)
);
COMMENT ON TABLE public.audit_trigger_config
    IS '[VoyaGo][System][Audit] Configures which table modifications are logged to the audit_log.';
COMMENT ON COLUMN public.audit_trigger_config.excluded_columns
    IS 'Array of column names to ignore when logging changes (e.g., updated_at).';


-------------------------------------------------------------------------------
-- 2. Data Audit Log (audit_log) - Partitioned Table
-- Description: Detailed log of data changes in audited tables.
-- Note: Partitioned by timestamp. Partitions must be managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log (
    log_id              BIGSERIAL,
    timestamp           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), -- Time of change (Partition Key & part of PK)
    action              public.audit_action NOT NULL, -- INSERT, UPDATE, DELETE (ENUM from 001)
    schema_name         NAME NOT NULL,      -- Schema of the changed table
    table_name          NAME NOT NULL,      -- Name of the changed table
    primary_key_data    JSONB NULL,         -- JSONB containing primary key column(s) and value(s)
    old_data            JSONB NULL,         -- Changed data (before) for UPDATE/DELETE (only changed columns)
    new_data            JSONB NULL,         -- Changed data (after) for INSERT/UPDATE (only changed columns)
    actor_id            UUID NULL,          -- User performing the action (from auth.uid() if available)
    request_id          UUID NULL,          -- Associated API request ID (if available)
    ip_address          INET NULL,          -- Client IP address (if available)
    original_ip_hash    TEXT NULL,          -- Hash of the original IP (for privacy/uniqueness check)
    comment             TEXT NULL,          -- Optional comment about the change
    PRIMARY KEY (timestamp, log_id)         -- Composite PK including partition key

) PARTITION BY RANGE (timestamp);

COMMENT ON TABLE public.audit_log
    IS '[VoyaGo][System][Audit] Detailed audit trail of data modifications in configured tables. 
        Partitioned by timestamp.';
COMMENT ON COLUMN public.audit_log.primary_key_data
    IS 'JSONB object containing the primary key(s) and value(s) of the affected row.';
COMMENT ON COLUMN public.audit_log.old_data
    IS 'JSONB object containing only the columns that changed, showing their values before an UPDATE or DELETE.';
COMMENT ON COLUMN public.audit_log.new_data
    IS 'JSONB object containing only the columns that changed (for UPDATE) 
        or all included columns (for INSERT), showing their new values.';
COMMENT ON COLUMN public.audit_log.original_ip_hash
    IS 'MD5 hash of the client IP address, potentially used for tracking without storing the raw IP long-term.';

-- Indexes for Audit Log (Defined on main table)
CREATE INDEX IF NOT EXISTS idx_audit_log_entity
    ON public.audit_log(schema_name, table_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_time
    ON public.audit_log(actor_id, timestamp DESC) WHERE actor_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_request
    ON public.audit_log(request_id) WHERE request_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_audit_log_time_brin ON public.audit_log USING BRIN(timestamp);
COMMENT ON INDEX public.idx_audit_log_time_brin
    IS '[VoyaGo][Perf] BRIN index suitable for range queries on the timestamp partition key.';


-------------------------------------------------------------------------------
-- 3. System/Application Logs (system_logs)
-- Description: General purpose logging table for application events.
-- Note: Consider partitioning or log rotation/archiving for high volume.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_logs (
    log_id      BIGSERIAL       PRIMARY KEY,
    timestamp   TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    level       public.system_log_level NOT NULL, -- Log level (ENUM from 001)
    source      VARCHAR(100)    NULL,       -- Origin of the log (e.g., 'AuthService', 'Job:Payouts')
    message     TEXT            NOT NULL,   -- The log message
    -- Additional structured context
    metadata    JSONB           NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    exception   TEXT            NULL        -- Exception details (stack trace etc.) if it's an error log
);
COMMENT ON TABLE public.system_logs
    IS '[VoyaGo][Logging] General application and system logs (DEBUG, INFO, WARN, ERROR...). 
        Consider partitioning/archiving.';
COMMENT ON COLUMN public.system_logs.metadata
    IS 'Additional structured context as JSONB, e.g., user_id, request_id, trace_id.';

-- Indexes for System Logs
CREATE INDEX IF NOT EXISTS idx_sls_level_time ON public.system_logs(level, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sls_source ON public.system_logs(source text_pattern_ops);
CREATE INDEX IF NOT EXISTS idx_sls_metadata ON public.system_logs USING GIN (metadata) WHERE metadata IS NOT NULL;


-------------------------------------------------------------------------------
-- 4. Semantic Audit Events (system_audit_events)
-- Description: Logs high-level business or security significant events.
-- Note: Consider partitioning for high volume.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_audit_events (
    event_id            BIGSERIAL   PRIMARY KEY,
    event_type          VARCHAR(100) NOT NULL,  -- Type identifier (e.g., 'USER_LOGIN_SUCCESS', 'PAYOUT_APPROVED')
    -- Source system/module emitting the event (e.g., 'API:/login', 'AdminUI')
    source              VARCHAR(100) NULL,
    actor_id            UUID         NULL,      -- User performing the action (FK defined later)
    -- Optional target entity involved in the event
    target_entity_type  VARCHAR(50)  NULL,
    target_entity_id    TEXT         NULL,
    -- Event-specific details
    details             JSONB        NULL CHECK (details IS NULL OR jsonb_typeof(details) = 'object'),
    timestamp           TIMESTAMPTZ  DEFAULT clock_timestamp() NOT NULL
);
COMMENT ON TABLE public.system_audit_events
    IS '[VoyaGo][Audit] Tracks significant business or security events (semantic logging). Consider partitioning.';
COMMENT ON COLUMN public.system_audit_events.event_type
    IS 'Categorizes the type of high-level event that occurred.';
COMMENT ON COLUMN public.system_audit_events.details
    IS 'Additional structured details relevant to the specific event type.';

-- Indexes for Audit Events
CREATE INDEX IF NOT EXISTS idx_sae_event_time ON public.system_audit_events(event_type, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sae_actor_time ON public.system_audit_events(actor_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sae_target ON public.system_audit_events(target_entity_type, target_entity_id);


-------------------------------------------------------------------------------
-- 5. Feature Flags (system_feature_flags) & History
-- Description: Manages feature flags for controlled rollouts.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_feature_flags (
    flag_name           VARCHAR(50)     PRIMARY KEY, -- Unique name for the feature flag
    description         TEXT            NULL,
    is_enabled          BOOLEAN         DEFAULT FALSE NOT NULL, -- Master switch for the flag
    -- Rollout controls
    rollout_percentage  SMALLINT        DEFAULT 0 NOT NULL CHECK (rollout_percentage BETWEEN 0 AND 100),
    target_users        UUID[]          NULL,       -- Array of specific user IDs to enable for
    target_groups       TEXT[]          NULL,       -- Array of group names/IDs to enable for
    -- Metadata & Audit
    metadata            JSONB           NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_by          UUID            NULL,       -- User who created the flag (FK defined later)
    updated_by          UUID            NULL,       -- User who last updated the flag (FK defined later)
    created_at          TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ     NULL        -- Automatically updated by trigger
);
COMMENT ON TABLE public.system_feature_flags
    IS '[VoyaGo][System] Manages feature flags for enabling/disabling features or controlled rollouts.';
COMMENT ON COLUMN public.system_feature_flags.rollout_percentage
    IS 'Percentage of users (0-100) for whom the flag should be randomly enabled (if not targeted specifically).';
COMMENT ON COLUMN public.system_feature_flags.target_users
    IS 'Array of specific user UUIDs for whom the flag is always enabled (if active).';
COMMENT ON COLUMN public.system_feature_flags.target_groups
    IS 'Array of group identifiers (e.g., user roles, organization types) 
        for whom the flag is always enabled (if active).';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_system_feature_flags ON public.system_feature_flags;
CREATE TRIGGER trg_set_timestamp_on_system_feature_flags
    BEFORE UPDATE ON public.system_feature_flags
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Feature Flags
CREATE INDEX IF NOT EXISTS idx_sff_enabled ON public.system_feature_flags(is_enabled);
CREATE INDEX IF NOT EXISTS idx_gin_sff_users ON public.system_feature_flags USING GIN (
    target_users
) WHERE target_users IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_sff_groups ON public.system_feature_flags USING GIN (
    target_groups
) WHERE target_groups IS NOT NULL;

-- History Table for Feature Flags
CREATE TABLE IF NOT EXISTS public.system_feature_flags_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    flag_name       VARCHAR(50) NOT NULL, -- The flag that was changed
    flag_data       JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.system_feature_flags_history
    IS '[VoyaGo][System][History] Audit log capturing changes to feature flag configurations.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_sff_hist_fn
    ON public.system_feature_flags_history(flag_name, action_at DESC);

-- Feature Flag History Trigger Function
CREATE OR REPLACE FUNCTION public.vg_log_feature_flag_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.system_feature_flags_history
            (action_type, actor_id, flag_name, flag_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.flag_name, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_feature_flag_history()
    IS '[VoyaGo][System][TriggerFn] Logs previous state of system_feature_flags row 
        to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_feature_flag_history ON public.system_feature_flags;
CREATE TRIGGER audit_feature_flag_history
    AFTER UPDATE OR DELETE ON public.system_feature_flags
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_feature_flag_history();


-------------------------------------------------------------------------------
-- 6. Scheduled Jobs (system_jobs & system_job_runs)
-- Description: Framework for defining and tracking scheduled background tasks.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_jobs (
    job_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_name            VARCHAR(100) NOT NULL UNIQUE, -- Unique name identifying the job
    description         TEXT         NULL,
    job_handler         TEXT         NOT NULL,       -- Identifier for the code/function/procedure that executes the job
    -- Schedule definition (e.g., CRON expression: '0 5 * * *', or iCal RRULE)
    schedule            TEXT         NOT NULL,
    timezone            TEXT         NOT NULL DEFAULT 'UTC', -- Timezone for interpreting the schedule
    -- Default parameters for the job handler
    default_payload     JSONB        NULL CHECK (default_payload IS NULL OR jsonb_typeof(default_payload) = 'object'),
    timeout_seconds     INTEGER      NULL CHECK (timeout_seconds IS NULL OR timeout_seconds > 0), -- Max execution time
    max_retries         SMALLINT     DEFAULT 3 NOT NULL CHECK (max_retries >= 0), -- Max number of retries on failure
    retry_delay_seconds INTEGER      DEFAULT 60 NOT NULL CHECK (retry_delay_seconds > 0), -- Delay between retries
    last_run_at         TIMESTAMPTZ  NULL,       -- Timestamp of the last successful/failed run start
    next_run_at         TIMESTAMPTZ  NULL,       -- Calculated next scheduled run time
    status              public.job_status NOT NULL DEFAULT 'ENABLED', -- Job status (ENABLED/DISABLED) (ENUM from 001)
    metadata            JSONB        NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at          TIMESTAMPTZ  DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ  NULL        -- Automatically updated by trigger
);
COMMENT ON TABLE public.system_jobs
    IS '[VoyaGo][System] Defines scheduled jobs (cron-like tasks) to be executed periodically.';
COMMENT ON COLUMN public.system_jobs.job_handler
    IS 'Identifier pointing to the actual code/function responsible for executing the job''s logic.';
COMMENT ON COLUMN public.system_jobs.schedule
    IS 'Job schedule definition, typically a CRON expression or potentially an iCal RRULE string.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_system_jobs ON public.system_jobs;
CREATE TRIGGER trg_set_timestamp_on_system_jobs
    BEFORE UPDATE ON public.system_jobs
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Index for job runner to find due jobs
CREATE INDEX IF NOT EXISTS idx_sj_status_next_run
    ON public.system_jobs(status, next_run_at ASC NULLS FIRST);
COMMENT ON INDEX public.idx_sj_status_next_run IS '[VoyaGo][Perf] Efficiently finds enabled jobs that are due to run.';
CREATE INDEX IF NOT EXISTS idx_sj_handler ON public.system_jobs(job_handler);

-- Table to log executions of scheduled jobs
CREATE TABLE IF NOT EXISTS public.system_job_runs (
    run_id              BIGSERIAL       PRIMARY KEY,
    job_id              UUID            NOT NULL,   -- Link to the job definition (FK defined later)
    -- When the job was scheduled/triggered to run
    trigger_time        TIMESTAMPTZ     NOT NULL DEFAULT clock_timestamp(),
    started_at          TIMESTAMPTZ     NULL,       -- When the job execution actually started
    finished_at         TIMESTAMPTZ     NULL,       -- When the job execution finished (successfully or not)
    status              public.job_run_status NOT NULL DEFAULT 'PENDING', -- Outcome status (ENUM from 001)
    result_payload      JSONB           NULL CHECK (result_payload IS NULL OR jsonb_typeof(result_payload) = 'object'), 
    -- Optional result data from the job
    error_message       TEXT            NULL,       -- Error message if status is FAILED
    -- Execution time in milliseconds
    run_duration_ms     INTEGER         NULL CHECK (run_duration_ms IS NULL OR run_duration_ms >= 0) 
);
COMMENT ON TABLE public.system_job_runs
    IS '[VoyaGo][System] Logs each execution instance of a scheduled job and its outcome.';
COMMENT ON COLUMN public.system_job_runs.result_payload
    IS 'Optional JSONB data returned by a successful job execution.';

-- Indexes for Job Runs
CREATE INDEX IF NOT EXISTS idx_sjr_job_time
    ON public.system_job_runs(job_id, trigger_time DESC);
CREATE INDEX IF NOT EXISTS idx_sjr_status ON public.system_job_runs(status);
CREATE INDEX IF NOT EXISTS idx_sjr_error ON public.system_job_runs(status) WHERE status = 'FAILED';


-------------------------------------------------------------------------------
-- 7. Helper Functions/Procedures (Full Definitions)
-------------------------------------------------------------------------------

-- System Logging Procedure
CREATE OR REPLACE PROCEDURE public.vg_log_system_event(
    p_log_level     public.system_log_level,
    p_source        VARCHAR,
    p_message       TEXT,
    p_metadata      JSONB DEFAULT NULL,
    p_exception     TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO public.system_logs (level, source, message, metadata, exception)
    VALUES (p_log_level, p_source, p_message, p_metadata, p_exception);
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[vg_log_system_event] Logging failed! Level=%, Source=%, Msg=%', p_log_level, p_source, p_message;
    RAISE WARNING '[vg_log_system_event] Logging error: %', SQLERRM;
END;
$$;
COMMENT ON PROCEDURE public.vg_log_system_event(public.system_log_level, VARCHAR, TEXT, JSONB, TEXT)
    IS '[VoyaGo][Helper][Log] Writes structured system logs to the system_logs table.';

-- Data Audit Trigger Function (Syntax Fixed)
CREATE OR REPLACE FUNCTION public.vg_audit_trigger_func()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review and ownership by a trusted role (e.g., postgres)
SET search_path = public -- Explicitly set search path
AS $$
DECLARE
    v_audit_enabled     BOOLEAN := true;
    v_config            RECORD;
    v_old_data          JSONB := NULL;
    v_new_data          JSONB := NULL;
    v_actor_id          UUID;
    v_request_id        UUID;
    v_ip_address        INET;
    v_excluded_columns  TEXT[];
    v_pk_columns        TEXT[];
    v_pk_data           JSONB := '{}'::jsonb;
    v_action            public.audit_action;
    r                   RECORD;
    v_changed_old       JSONB := '{}';
    v_changed_new       JSONB := '{}';
    v_has_changes       BOOLEAN := FALSE;
    v_pk_val            TEXT; -- Variable to hold PK value text representation
    error_rec           RECORD;
    v_err_context       TEXT;
BEGIN
    -- Attempt to get context information, gracefully handle if unavailable
    BEGIN v_actor_id := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor_id := NULL; END;
    BEGIN v_request_id := current_setting('app.request_id', true)::UUID; EXCEPTION WHEN OTHERS THEN v_request_id := NULL; END;
    BEGIN v_ip_address := inet_client_addr(); EXCEPTION WHEN OTHERS THEN v_ip_address := NULL; END;

    -- Check audit configuration for the target table
    BEGIN
        SELECT enabled, excluded_columns, track_inserts, track_updates, track_deletes
        INTO v_config
        FROM public.audit_trigger_config
        WHERE target_schema = TG_TABLE_SCHEMA AND target_table = TG_TABLE_NAME;

        IF NOT FOUND OR v_config IS NULL THEN RETURN NULL; END IF;
        IF (TG_OP = 'INSERT' AND NOT v_config.track_inserts) OR
           (TG_OP = 'UPDATE' AND NOT v_config.track_updates) OR
           (TG_OP = 'DELETE' AND NOT v_config.track_deletes) THEN
            RETURN NULL;
        END IF;

        v_audit_enabled := COALESCE(v_config.enabled, true);
        v_excluded_columns := COALESCE(v_config.excluded_columns, ARRAY[]::TEXT[]);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[vg_audit_trigger_func] Audit config lookup error %.%: %', TG_TABLE_SCHEMA, TG_TABLE_NAME, SQLERRM;
        v_audit_enabled := true;
        v_excluded_columns := ARRAY[]::TEXT[];
    END;

    IF NOT v_audit_enabled THEN RETURN NULL; END IF;

    v_action := TG_OP::public.audit_action;

    -- Get primary key columns and values
    BEGIN
        SELECT array_agg(a.attname ORDER BY a.attnum)
        INTO v_pk_columns
        FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = TG_RELID AND i.indisprimary;

        IF v_pk_columns IS NOT NULL THEN
            -- ** SYNTAX FIX: Use FOR loop correctly **
            FOR r IN SELECT unnest(v_pk_columns) AS col LOOP
                IF TG_OP = 'DELETE' THEN
                     EXECUTE format('SELECT $1.%I::text', r.col) INTO v_pk_val USING OLD;
                ELSE
                     EXECUTE format('SELECT $1.%I::text', r.col) INTO v_pk_val USING NEW;
                END IF;
                 -- Build JSON object piece by piece
                 v_pk_data := v_pk_data || jsonb_build_object(r.col, v_pk_val);
            END LOOP;
        ELSE
             v_pk_data := jsonb_build_object('ctid', CASE WHEN TG_OP = 'DELETE' THEN OLD.ctid ELSE NEW.ctid END);
        END IF;
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING '[vg_audit_trigger_func] PK Find Error %.%: %', TG_TABLE_SCHEMA, TG_TABLE_NAME, SQLERRM;
        v_pk_data := jsonb_build_object('ctid', CASE WHEN TG_OP = 'DELETE' THEN OLD.ctid ELSE NEW.ctid END);
    END;

    -- Prepare OLD and NEW data (only changed columns for UPDATE)
    IF (v_action = 'UPDATE') THEN
        v_old_data = to_jsonb(OLD);
        v_new_data = to_jsonb(NEW);
        FOR r IN SELECT key, value FROM jsonb_each(v_new_data) LOOP
            IF NOT (r.key = ANY(v_excluded_columns)) AND (r.value IS DISTINCT FROM (v_old_data->r.key)) THEN
                v_changed_new := jsonb_set(v_changed_new, ARRAY[r.key], r.value);
                v_changed_old := jsonb_set(v_changed_old, ARRAY[r.key], v_old_data->r.key);
                v_has_changes := TRUE;
            END IF;
        END LOOP;
        IF NOT v_has_changes THEN RETURN NULL; END IF; -- Don't log if no relevant columns changed
        v_old_data := v_changed_old;
        v_new_data := v_changed_new;
    ELSIF (v_action = 'DELETE') THEN
        v_old_data = to_jsonb(OLD);
        IF array_length(v_excluded_columns, 1) > 0 THEN v_old_data := v_old_data - v_excluded_columns; END IF;
        v_new_data := NULL;
    ELSIF (v_action = 'INSERT') THEN
        v_new_data = to_jsonb(NEW);
        IF array_length(v_excluded_columns, 1) > 0 THEN v_new_data := v_new_data - v_excluded_columns; END IF;
        v_old_data := NULL;
    END IF;

    -- Insert the audit record
    BEGIN
        INSERT INTO public.audit_log
            (action, schema_name, table_name, primary_key_data, old_data, new_data, actor_id, request_id, ip_address, original_ip_hash, timestamp)
        VALUES
            (v_action, TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk_data, v_old_data, v_new_data, v_actor_id, v_request_id, v_ip_address,
             md5(coalesce(v_ip_address::text,'NULL_IP')),
             clock_timestamp());
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS error_rec.message = MESSAGE_TEXT, error_rec.sqlstate = RETURNED_SQLSTATE, v_err_context = PG_EXCEPTION_CONTEXT;
        CALL public.vg_log_system_event(
            'ERROR',
            'vg_audit_trigger_func',
            'AUDIT_INSERT_FAIL: Failed to insert audit log record.',
            jsonb_build_object('table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME, 'pk', v_pk_data, 'original_error', error_rec.message, 'sqlstate', error_rec.sqlstate),
            v_err_context
        );
        RAISE WARNING '[vg_audit_trigger_func] Audit log insert error: %', error_rec.message;
    END;

    RETURN NULL; -- This is an AFTER trigger

EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_rec.message = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
    RAISE WARNING '[vg_audit_trigger_func] Unexpected error in audit trigger for %.%: % --- Context: %',
        TG_TABLE_SCHEMA, TG_TABLE_NAME, error_rec.message, v_err_context;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_audit_trigger_func()
    IS '[VoyaGo][Helper][Audit] Generic trigger function to log data changes (delta) 
        to audit_log based on audit_trigger_config. Uses SECURITY DEFINER.';
-- Note: Ownership should ideally be set to a trusted superuser, e.g., postgres.
-- ALTER FUNCTION public.vg_audit_trigger_func() OWNER TO postgres;


-- Audit Trigger Synchronization Procedure (Ensure definition exists)
CREATE OR REPLACE PROCEDURE public.vg_sync_audit_triggers()
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review and ownership
SET search_path = public
AS $$
DECLARE
    cfg             RECORD;
    v_trigger_name  TEXT;
    v_trigger_exists BOOLEAN;
    v_sql           TEXT;
    error_rec       RECORD;
    v_err_context   TEXT;
BEGIN
    RAISE NOTICE '[vg_sync_audit_triggers] Starting audit trigger synchronization...';
    FOR cfg IN SELECT * FROM public.audit_trigger_config LOOP
        v_trigger_name := 'audit_trigger_for_' || cfg.target_table;
        SELECT EXISTS (
            SELECT 1 FROM pg_trigger t
            JOIN pg_class c ON t.tgrelid = c.oid JOIN pg_namespace n ON c.relnamespace = n.oid
            WHERE t.tgname = v_trigger_name AND n.nspname = cfg.target_schema AND c.relname = cfg.target_table AND NOT t.tgisinternal
        ) INTO v_trigger_exists;

        BEGIN
            IF cfg.enabled AND (cfg.track_inserts OR cfg.track_updates OR cfg.track_deletes) THEN
                IF NOT v_trigger_exists THEN
                    v_sql := format(
                        'CREATE TRIGGER %I AFTER INSERT OR UPDATE OR DELETE ON %I.%I FOR EACH ROW EXECUTE FUNCTION public.vg_audit_trigger_func();',
                        v_trigger_name, cfg.target_schema, cfg.target_table
                    );
                    RAISE NOTICE '[vg_sync_audit_triggers] Creating trigger: %', v_sql; EXECUTE v_sql;
                    RAISE NOTICE '[vg_sync_audit_triggers] CREATED trigger % on %.%', v_trigger_name, cfg.target_schema, cfg.target_table;
                ELSE
                    RAISE DEBUG '[vg_sync_audit_triggers] Trigger % on %.% already exists and is enabled in config.', v_trigger_name, cfg.target_schema, cfg.target_table;
                END IF;
            ELSE
                IF v_trigger_exists THEN
                    v_sql := format('DROP TRIGGER IF EXISTS %I ON %I.%I;', v_trigger_name, cfg.target_schema, cfg.target_table);
                    RAISE NOTICE '[vg_sync_audit_triggers] Dropping trigger: %', v_sql; EXECUTE v_sql;
                    RAISE NOTICE '[vg_sync_audit_triggers] DROPPED trigger % from %.%', v_trigger_name, cfg.target_schema, cfg.target_table;
                ELSE
                     RAISE DEBUG '[vg_sync_audit_triggers] Trigger % on %.% does not exist and is disabled in config.', v_trigger_name, cfg.target_schema, cfg.target_table;
                END IF;
            END IF;
            UPDATE public.audit_trigger_config SET last_synced_at = clock_timestamp() WHERE config_id = cfg.config_id;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS error_rec.message = MESSAGE_TEXT, error_rec.sqlstate = RETURNED_SQLSTATE, v_err_context = PG_EXCEPTION_CONTEXT;
            RAISE WARNING '[vg_sync_audit_triggers] Trigger sync error on %.%: %', cfg.target_schema, cfg.target_table, error_rec.message;
            CALL public.vg_log_system_event('ERROR','vg_sync_audit_triggers','TRIGGER_SYNC_FAIL', 'Trigger sync failed for ' || cfg.target_schema||'.'||cfg.target_table || ': ' || error_rec.message, jsonb_build_object('table', cfg.target_schema||'.'||cfg.target_table, 'error', error_rec.message, 'sqlstate', error_rec.sqlstate), v_err_context);
        END;
    END LOOP;
    RAISE NOTICE '[vg_sync_audit_triggers] Finished audit trigger synchronization.';
END;
$$;
COMMENT ON PROCEDURE public.vg_sync_audit_triggers()
    IS '[VoyaGo][Helper][Audit] Dynamically creates or drops data 
        audit triggers on tables based on the audit_trigger_config table. Uses SECURITY DEFINER.';
-- Note: Ownership should ideally be set to a trusted superuser.
-- ALTER PROCEDURE public.vg_sync_audit_triggers() OWNER TO postgres;


-- Partition Maintenance Procedure (Ensure definition exists)
CREATE OR REPLACE PROCEDURE public.vg_maintain_partitions(
    p_table_schema      NAME,
    p_table_name        NAME,
    p_retention_months  INTEGER,
    p_premake_months    INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review and ownership
AS $$
DECLARE
    v_current_month_start   DATE := date_trunc('month', current_date);
    v_partition_name        TEXT;
    v_partition_start       TIMESTAMPTZ;
    v_partition_end         TIMESTAMPTZ;
    v_sql                   TEXT;
    v_retention_cutoff_date DATE;
    rec                     RECORD;
    error_rec               RECORD;
    v_err_context           TEXT;
BEGIN
    RAISE NOTICE '[vg_maintain_partitions] Checking future partitions for %.% (Premake: % months)', p_table_schema, p_table_name, p_premake_months;
    FOR i IN 0..p_premake_months LOOP
        v_partition_start := date_trunc('month', v_current_month_start + (interval '1 month' * i));
        v_partition_end := (v_partition_start + interval '1 month');
        v_partition_name := format('%s_y%sm%s', p_table_name, to_char(v_partition_start, 'YYYY'), to_char(v_partition_start, 'MM'));
        IF NOT EXISTS ( SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r' AND c.relispartition AND n.nspname = p_table_schema AND c.relname = v_partition_name ) THEN
            BEGIN
                v_sql := format('CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L);', p_table_schema, v_partition_name, p_table_schema, p_table_name, v_partition_start, v_partition_end);
                RAISE NOTICE '[vg_maintain_partitions] Creating partition: %', v_sql; EXECUTE v_sql;
                v_sql := format('COMMENT ON TABLE %I.%I IS %L;', p_table_schema, v_partition_name, format('[Partition] %s partition for %s', p_table_name, to_char(v_partition_start, 'YYYY-MM')));
                EXECUTE v_sql;
            EXCEPTION WHEN OTHERS THEN RAISE WARNING '[vg_maintain_partitions] Failed to create partition %: %', v_partition_name, SQLERRM; END;
        ELSE RAISE DEBUG '[vg_maintain_partitions] Partition % already exists.', v_partition_name; END IF;
    END LOOP;

    RAISE NOTICE '[vg_maintain_partitions] Checking old partitions for %.% (Retention: % months)', p_table_schema, p_table_name, p_retention_months;
    v_retention_cutoff_date := date_trunc('month', v_current_month_start - (interval '1 month' * p_retention_months));
    RAISE DEBUG '[vg_maintain_partitions] Retention cutoff date: %', v_retention_cutoff_date;
    FOR rec IN SELECT nmsp_child.nspname AS child_schema, child.relname AS child_table FROM pg_inherits JOIN pg_class parent ON pg_inherits.inhparent = parent.oid JOIN pg_class child ON pg_inherits.inhrelid = child.oid JOIN pg_namespace nmsp_parent ON nmsp_parent.oid = parent.relnamespace JOIN pg_namespace nmsp_child ON nmsp_child.oid = child.relnamespace WHERE parent.relname = p_table_name AND nmsp_parent.nspname = p_table_schema AND child.relispartition
    LOOP
        DECLARE v_part_year INTEGER; v_part_month INTEGER; v_part_start_date DATE;
        BEGIN
            v_part_year := substring(rec.child_table from '_y(\d{4})')::INTEGER; v_part_month := substring(rec.child_table from '_y\d{4}m(\d{2})')::INTEGER;
            IF v_part_year IS NOT NULL AND v_part_month IS NOT NULL THEN
                v_part_start_date := make_date(v_part_year, v_part_month, 1);
                IF v_part_start_date < v_retention_cutoff_date THEN
                    BEGIN v_sql := format('DROP TABLE IF EXISTS %I.%I;', rec.child_schema, rec.child_table); RAISE NOTICE '[vg_maintain_partitions] Dropping old partition: %', v_sql; EXECUTE v_sql; EXCEPTION WHEN OTHERS THEN RAISE WARNING '[vg_maintain_partitions] Failed to drop partition %: %', rec.child_table, SQLERRM; END;
                ELSE RAISE DEBUG '[vg_maintain_partitions] Keeping partition % (Start date: %)', rec.child_table, v_part_start_date; END IF;
            ELSE RAISE WARNING '[vg_maintain_partitions] Could not parse date from partition name: %', rec.child_table; END IF;
        EXCEPTION WHEN others THEN RAISE WARNING '[vg_maintain_partitions] Error processing partition % for dropping: %', rec.child_table, SQLERRM; END;
    END LOOP;
    RAISE NOTICE '[vg_maintain_partitions] Finished maintenance for %.%', p_table_schema, p_table_name;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS error_rec.message = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT;
    CALL public.vg_log_system_event('ERROR', 'vg_maintain_partitions', 'Partition maintenance failed for ' || p_table_schema || '.' || p_table_name, jsonb_build_object('schema', p_table_schema, 'table', p_table_name, 'error', error_rec.message), v_err_context);
    RAISE WARNING '[vg_maintain_partitions] Error maintaining partitions for %.%: %', p_table_schema, p_table_name, error_rec.message;
END;
$$;
COMMENT ON PROCEDURE public.vg_maintain_partitions(NAME, NAME, INTEGER, INTEGER)
    IS '[VoyaGo][Helper][System] Creates future monthly partitions and drops old ones 
        for a specified range-partitioned table.';
-- Note: Ownership should ideally be set to a trusted superuser.
-- ALTER PROCEDURE public.vg_maintain_partitions(NAME, NAME, INTEGER, INTEGER) OWNER TO postgres;


-- Scheduled Job Processor Procedure (Ensure definition exists and is up-to-date - v1.2 fix included)
CREATE OR REPLACE PROCEDURE public.vg_process_scheduled_jobs()
LANGUAGE plpgsql
AS $$
DECLARE
    rec_job         RECORD;
    v_run_id        BIGINT;
    v_start_time    TIMESTAMPTZ;
    v_end_time      TIMESTAMPTZ;
    v_duration_ms   INTEGER;
    v_result        JSONB;
    v_error         TEXT;
    v_err_context   TEXT;
    job_failed      BOOLEAN := FALSE;
    v_next_run      TIMESTAMPTZ;
    v_job_payload   JSONB;
BEGIN
    RAISE NOTICE '[vg_process_scheduled_jobs] Starting job processing cycle...';
    FOR rec_job IN SELECT * FROM public.system_jobs WHERE status = 'ENABLED' AND (next_run_at IS NULL OR next_run_at <= clock_timestamp()) ORDER BY next_run_at ASC NULLS FIRST FOR UPDATE SKIP LOCKED
    LOOP
        v_start_time := clock_timestamp(); v_result := NULL; v_error := NULL; job_failed := FALSE; v_job_payload := rec_job.default_payload;
        INSERT INTO public.system_job_runs (job_id, trigger_time, started_at, status) VALUES (rec_job.job_id, COALESCE(rec_job.next_run_at, v_start_time), v_start_time, 'RUNNING') RETURNING run_id INTO v_run_id;
        RAISE NOTICE '[vg_process_scheduled_jobs] Running job % (ID: %, RunID: %)', rec_job.job_name, rec_job.job_id, v_run_id;

        -- *** Placeholder for actual job execution logic ***
        BEGIN
            v_result := jsonb_build_object('status', 'dummy_success', 'message', 'Handler logic for ' || rec_job.job_name || ' not implemented yet.');
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT, v_err_context = PG_EXCEPTION_CONTEXT; job_failed := TRUE;
            RAISE WARNING '[vg_process_scheduled_jobs] EXCEPTION during job % (RunID: %): %', rec_job.job_name, v_run_id, v_error;
            CALL public.vg_log_system_event('ERROR','vg_process_scheduled_jobs','Job handler threw exception: ' || rec_job.job_name, jsonb_build_object('job_id', rec_job.job_id, 'run_id', v_run_id, 'handler', rec_job.job_handler), v_error || E'\nContext: ' || v_err_context);
        END;
        -- *** End of placeholder execution logic ***

        v_end_time := clock_timestamp(); v_duration_ms := GREATEST(0, EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER);
        IF job_failed THEN
            UPDATE public.system_job_runs SET finished_at = v_end_time, status = 'FAILED', error_message = v_error, run_duration_ms = v_duration_ms WHERE run_id = v_run_id;
            UPDATE public.system_jobs SET last_run_at = v_start_time WHERE job_id = rec_job.job_id;
        ELSE
            UPDATE public.system_job_runs SET finished_at = v_end_time, status = 'SUCCESS', result_payload = v_result, run_duration_ms = v_duration_ms WHERE run_id = v_run_id;
            BEGIN v_next_run := v_start_time + interval '1 hour'; EXCEPTION WHEN OTHERS THEN RAISE WARNING '[vg_process_scheduled_jobs] Could not calculate next run time for job % (ID: %): %', rec_job.job_name, rec_job.job_id, SQLERRM; v_next_run := v_start_time + interval '1 day'; END;
            UPDATE public.system_jobs SET last_run_at = v_start_time, next_run_at = v_next_run WHERE job_id = rec_job.job_id;
            RAISE NOTICE '[vg_process_scheduled_jobs] Job % (RunID: %) finished successfully in % ms. Next run scheduled for: %', rec_job.job_name, v_run_id, v_duration_ms, v_next_run;
        END IF;
    END LOOP;
    RAISE NOTICE '[vg_process_scheduled_jobs] Finished job processing cycle.';
END;
$$;
COMMENT ON PROCEDURE public.vg_process_scheduled_jobs()
    IS '[VoyaGo][Helper][Jobs] Finds due scheduled jobs, 
    executes their handlers (placeholder logic), logs results, and schedules next run.';
-- Note: Ownership should ideally be set to a trusted superuser.
-- ALTER PROCEDURE public.vg_process_scheduled_jobs() OWNER TO postgres;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- audit_log -> core_user_profiles (actor_id -> user_id) [SET NULL]
--
-- system_audit_events -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- Note: FK for target_entity_id depends on target_entity_type.
--
-- system_feature_flags -> core_user_profiles (created_by -> user_id) [SET NULL]
-- system_feature_flags -> core_user_profiles (updated_by -> user_id) [SET NULL]
-- Note: target_users array contains user UUIDs, but cannot have direct FK.
--
-- system_feature_flags_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- system_feature_flags_history -> system_feature_flags (flag_name -> flag_name) [CASCADE]
--
-- system_job_runs -> system_jobs (job_id -> job_id) [CASCADE] -- Delete runs if job definition deleted
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 022_system_management.sql (Version 1.3 - Standardized Formatting)
-- ============================================================================
