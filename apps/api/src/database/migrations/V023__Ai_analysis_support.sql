-- ============================================================================
-- Migration: 023_ai_analysis_support.sql (Version 1.2 - Added Partition Keys for FKs)
-- Description: VoyaGo - AI Model Registry, Inference & Training Logs,
--              Feature Usage Tracking, Analytics Reports & Snapshots.
--              Adds partition key columns for composite FKs.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 003_core_user.sql (Users),
--               010_booking_core.sql, 014_micromobility.sql,
--               022_system_management.sql (Jobs Ref?)
-- ============================================================================

BEGIN;

-- Prefixes 'ai_' and 'analysis_' denote tables related to AI/ML and Analytics modules.

-------------------------------------------------------------------------------
-- 1. AI Model Registry (ai_model_registry & ai_model_versions)
-- Description: Manages registered AI/ML models and their versions.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_model_registry (
    model_id        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_name      VARCHAR(100) NOT NULL UNIQUE, -- User-friendly name for the model group
    model_type      public.ai_model_type NOT NULL, -- Type/purpose of the model (ENUM from 001)
    description     TEXT NULL,
    tags            TEXT[] NULL,        -- Tags for categorization (e.g., ['pricing', 'recommendation'])
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL    -- Automatically updated by trigger
);
COMMENT ON TABLE public.ai_model_registry
    IS '[VoyaGo][AI] Registry for grouping AI/ML models used within the platform.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_ai_model_registry ON public.ai_model_registry;
CREATE TRIGGER trg_set_timestamp_on_ai_model_registry
    BEFORE UPDATE ON public.ai_model_registry
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Model Registry
CREATE INDEX IF NOT EXISTS idx_ai_mr_type ON public.ai_model_registry(model_type);
CREATE INDEX IF NOT EXISTS idx_gin_ai_mr_tags
    ON public.ai_model_registry USING GIN(tags) WHERE tags IS NOT NULL;


-- Stores specific versions of registered models
CREATE TABLE IF NOT EXISTS public.ai_model_versions (
    version_id          BIGSERIAL       PRIMARY KEY,
    model_id            UUID            NOT NULL,   -- Link to the parent model registry entry (FK defined later)
    version_tag         VARCHAR(50)     NOT NULL,   -- Version identifier (e.g., 'v1.0.0', '2025-04-20-exp1')
    artifact_uri        TEXT            NOT NULL,   -- URI pointing to the model artifact (e.g., S3 path, Docker image)
    -- Reference to the dataset version used for training (e.g., DVC tag, Git hash)
    training_data_ref   TEXT            NULL,       
    -- Evaluation metrics
    metrics             JSONB           NULL CHECK (metrics IS NULL OR jsonb_typeof(metrics) = 'object'), 
    -- Key hyperparameters used
    parameters          JSONB           NULL CHECK (parameters IS NULL OR jsonb_typeof(parameters) = 'object'), 
    -- Is this version currently active/deployed for inference?
    is_active           BOOLEAN         DEFAULT FALSE NOT NULL,
    is_experimental     BOOLEAN         DEFAULT FALSE NOT NULL, -- Is this version used for experiments/A-B testing?
    created_at          TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    created_by_user_id  UUID            NULL,       -- User who registered this version (FK defined later)
    -- updated_at is less relevant, new versions are typically created

    CONSTRAINT uq_ai_model_version_tag UNIQUE (model_id, version_tag) -- Version tag must be unique per model
);
COMMENT ON TABLE public.ai_model_versions
    IS '[VoyaGo][AI] Stores specific versions of registered AI models, including artifacts, metrics, and status.';
COMMENT ON COLUMN public.ai_model_versions.artifact_uri
    IS 'Uniform Resource Identifier pointing to the location of the trained model artifact 
        (e.g., S3 path, container registry URI).';
COMMENT ON COLUMN public.ai_model_versions.training_data_ref
    IS 'Identifier referencing the specific dataset version used to train this model version 
        (e.g., DVC tag, S3 version ID, Git commit hash).';
COMMENT ON COLUMN public.ai_model_versions.metrics
    IS 'Key evaluation metrics for this model version as JSONB. Example: {"accuracy": 0.92, "precision": 0.88}';
COMMENT ON COLUMN public.ai_model_versions.parameters
    IS 'Key hyperparameters used during training for this model version as JSONB.';
COMMENT ON COLUMN public.ai_model_versions.is_active
    IS 'Indicates if this model version is the primary one used for production inference.';

-- Indexes for Model Versions
-- Index to find the latest active version for a model
CREATE INDEX IF NOT EXISTS idx_ai_mv_model_active
    ON public.ai_model_versions(model_id, is_active DESC, created_at DESC);
-- UNIQUE constraint implicitly creates index on (model_id, version_tag)


-------------------------------------------------------------------------------
-- 1.1 AI Model Registry History (ai_model_registry_history)
-- Description: Audit trail for changes to ai_model_registry.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_model_registry_history (
    history_id      BIGSERIAL PRIMARY KEY,
    action_type     public.audit_action NOT NULL,
    action_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    actor_id        UUID NULL,
    model_id        UUID NOT NULL,      -- The model registry entry that was changed
    registry_data   JSONB NOT NULL        -- Row data before UPDATE/DELETE
);
COMMENT ON TABLE public.ai_model_registry_history
    IS '[VoyaGo][AI][History] Audit log capturing changes to ai_model_registry records.';

-- Index for History
CREATE INDEX IF NOT EXISTS idx_ai_mrh_model
    ON public.ai_model_registry_history(model_id, action_at DESC);

-------------------------------------------------------------------------------
-- 1.2 AI Model Registry History Trigger Function
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.vg_log_ai_model_registry_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER -- Requires careful review
AS $$
DECLARE v_actor UUID; v_data JSONB;
BEGIN
    BEGIN v_actor := auth.uid(); EXCEPTION WHEN OTHERS THEN v_actor := NULL; END;
    IF (TG_OP = 'UPDATE' OR TG_OP = 'DELETE') THEN
        v_data := to_jsonb(OLD);
        INSERT INTO public.ai_model_registry_history
            (action_type, actor_id, model_id, registry_data)
        VALUES
            (TG_OP::public.audit_action, v_actor, OLD.model_id, v_data);
    END IF;
    IF TG_OP = 'UPDATE' THEN RETURN NEW; ELSIF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NULL;
END;
$$;
COMMENT ON FUNCTION public.vg_log_ai_model_registry_history()
    IS '[VoyaGo][AI][TriggerFn] Logs previous state of ai_model_registry row to history table on UPDATE or DELETE.';

-- Attach the trigger
DROP TRIGGER IF EXISTS audit_ai_model_registry_history ON public.ai_model_registry;
CREATE TRIGGER audit_ai_model_registry_history
    AFTER UPDATE OR DELETE ON public.ai_model_registry
    FOR EACH ROW EXECUTE FUNCTION public.vg_log_ai_model_registry_history();


-------------------------------------------------------------------------------
-- 2. Inference Requests & Responses (Partitioned Logs)
-- Description: Logs requests made to AI models and the corresponding responses.
-- Note: Partitioned by time. Partitions must be managed separately.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_inference_requests (
    request_id      UUID        DEFAULT uuid_generate_v4(),
    model_id        UUID        NOT NULL,   -- Model being called (FK defined later)
    version_id      BIGINT      NOT NULL,   -- Specific model version used (FK defined later)
    user_id         UUID        NULL,       -- User context, if applicable (FK defined later)
    -- Input data sent to the model
    input_payload   JSONB       NOT NULL CHECK (
        jsonb_typeof(input_payload) = 'object' OR jsonb_typeof(input_payload) = 'array'
    ), 
    requested_at    TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, -- Time of request (Partition Key & part of PK)
    status          public.ai_inference_status NOT NULL DEFAULT 'REQUESTED', -- Request status (ENUM from 001)
    -- Additional request metadata
    metadata        JSONB       NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'), 

    PRIMARY KEY (requested_at, request_id)

) PARTITION BY RANGE (requested_at);

COMMENT ON TABLE public.ai_inference_requests
    IS '[VoyaGo][AI][Log] Logs requests made to AI models for inference. Partitioned by requested_at.';

-- Indexes for Inference Requests (Defined on main table)
CREATE INDEX IF NOT EXISTS idx_ai_inf_req_model_time
    ON public.ai_inference_requests(model_id, version_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_inf_req_user_time
    ON public.ai_inference_requests(user_id, requested_at DESC) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_inf_req_status
    ON public.ai_inference_requests(status);


-- ** request_requested_at ADDED **
CREATE TABLE IF NOT EXISTS public.ai_inference_responses (
    response_id         BIGSERIAL,      -- Sequence for ordering within partition
    -- Link to the corresponding request (Composite FK defined later)
    request_id          UUID        NOT NULL,   
    request_requested_at TIMESTAMPTZ NOT NULL, -- (Partition Key for FK)
    output_payload      JSONB       NOT NULL CHECK (jsonb_typeof(output_payload) = 'object' 
        OR jsonb_typeof(output_payload) = 'array'), -- Output received from the model
    -- Performance metrics (e.g., {"latency_ms": 150})
    metrics             JSONB       NULL CHECK (metrics IS NULL OR jsonb_typeof(metrics) = 'object'), 
    -- Time response received (Partition Key & part of PK)
    completed_at        TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL, 
    error_message       TEXT        NULL,       -- Error details if inference failed

    PRIMARY KEY (completed_at, response_id)
    -- Note: Removed UNIQUE constraint on request_id as per v1.1

) PARTITION BY RANGE (completed_at);

COMMENT ON TABLE public.ai_inference_responses
    IS '[VoyaGo][AI][Log] Logs responses received from AI model inference requests. 
        Partitioned by completed_at.';
COMMENT ON COLUMN public.ai_inference_responses.request_requested_at
    IS 'Partition key copied from ai_inference_requests for composite foreign key.';
COMMENT ON COLUMN public.ai_inference_responses.request_id
    IS 'Links to the ai_inference_requests table using the composite key 
        (request_requested_at, request_id).';
COMMENT ON COLUMN public.ai_inference_responses.metrics
    IS 'Performance or evaluation metrics associated with the inference response, 
        e.g., latency, confidence scores.';

-- Indexes for Inference Responses (Defined on main table)
-- Index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_ai_inf_resp_req
    ON public.ai_inference_responses(request_id, request_requested_at);
CREATE INDEX IF NOT EXISTS idx_ai_inf_resp_time
    ON public.ai_inference_responses(completed_at DESC);


-------------------------------------------------------------------------------
-- 3. AI Training Jobs & Runs
-- Description: Defines and tracks AI model training processes.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_training_jobs (
    job_id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    model_id            UUID NOT NULL,      -- Model being trained (FK defined later)
    target_version_tag  VARCHAR(50) NOT NULL, -- Version tag to assign upon successful completion
    schedule            TEXT NULL,          -- Optional schedule (CRON or RRULE) for recurring training
    job_handler         TEXT NOT NULL,      -- Identifier for the training script/function
    -- Parameters for the training job
    payload             JSONB NULL CHECK (payload IS NULL OR jsonb_typeof(payload) = 'object'), 
    -- Job status (ENABLED/DISABLED) - Uses ENUM from 022
    status              public.job_status NOT NULL DEFAULT 'ENABLED', 
    last_run_at         TIMESTAMPTZ NULL,
    next_run_at         TIMESTAMPTZ NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at          TIMESTAMPTZ NULL    -- Automatically updated by trigger
);
COMMENT ON TABLE public.ai_training_jobs
    IS '[VoyaGo][AI] Defines scheduled or manually triggered AI model training jobs.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_ai_training_jobs ON public.ai_training_jobs;
CREATE TRIGGER trg_set_timestamp_on_ai_training_jobs
    BEFORE UPDATE ON public.ai_training_jobs
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Training Jobs
CREATE INDEX IF NOT EXISTS idx_ai_tr_jobs_model ON public.ai_training_jobs(model_id);
CREATE INDEX IF NOT EXISTS idx_ai_tr_jobs_status_next
    ON public.ai_training_jobs(status, next_run_at ASC NULLS FIRST); -- Find due training jobs


-- Tracks individual executions of training jobs
CREATE TABLE IF NOT EXISTS public.ai_training_runs (
    run_id              BIGSERIAL PRIMARY KEY,
    job_id              UUID NOT NULL,      -- Link to the training job definition (FK defined later)
    model_version_id    BIGINT NULL,        -- Link to the resulting model version if successful (FK defined later)
    triggered_at        TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    started_at          TIMESTAMPTZ NULL,
    finished_at         TIMESTAMPTZ NULL,
    status              public.ai_training_status NOT NULL DEFAULT 'PENDING', -- Training run status (ENUM from 001)
    logs_uri            TEXT NULL,          -- URI for detailed training logs (e.g., S3 path)
    -- Final metrics from this training run
    metrics             JSONB NULL CHECK (metrics IS NULL OR jsonb_typeof(metrics) = 'object'),
    error_message       TEXT NULL           -- Error details if status is FAILED
);
COMMENT ON TABLE public.ai_training_runs
    IS '[VoyaGo][AI] Logs each execution instance of an AI model training job.';

-- Indexes for Training Runs
CREATE INDEX IF NOT EXISTS idx_ai_tr_runs_job_time
    ON public.ai_training_runs(job_id, triggered_at DESC); -- Find runs for a job
CREATE INDEX IF NOT EXISTS idx_ai_tr_runs_status ON public.ai_training_runs(status);
CREATE INDEX IF NOT EXISTS idx_ai_tr_runs_version
    -- Find run that produced a version
    ON public.ai_training_runs(model_version_id) WHERE model_version_id IS NOT NULL; 


-------------------------------------------------------------------------------
-- 4. AI Feature Usage Tracking (ai_feature_usage) - ** ride_start_time ADDED **
-- Description: Logs when specific AI-powered features are invoked.
-- Note: Consider partitioning by invoked_at for high volume.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_feature_usage (
    usage_id            BIGSERIAL       PRIMARY KEY,
    feature_name        VARCHAR(100)    NOT NULL,   -- Name of the AI feature used (e.g., 'SURGE_PRICE_LOOKUP')
    user_id             UUID            NULL,       -- User triggering the feature (FK defined later)
    model_version_id    BIGINT          NULL,       -- Specific model version used, if applicable (FK defined later)
    request_payload     JSONB           NULL CHECK (request_payload IS NULL OR jsonb_typeof(request_payload) = 'object' 
        OR jsonb_typeof(request_payload) = 'array'), -- Input to the feature
    session_id          UUID            NULL,       -- Optional user session identifier
    -- Optional link to a ride (Composite FK defined later)
    ride_id             UUID            NULL,
    ride_start_time     TIMESTAMPTZ     NULL,       -- <<< EKLENEN SÜTUN
    invoked_at          TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL, -- Time of invocation
    -- Additional context (booking ID, location etc.)

context             JSONB           NULL CHECK (context IS NULL OR jsonb_typeof(context) = 'object'), 
    CONSTRAINT chk_afu_ride_start_time CHECK (ride_id IS NULL OR ride_start_time IS NOT NULL)
);
COMMENT ON TABLE public.ai_feature_usage
    IS '[VoyaGo][AI][Log] Tracks invocations of specific AI-powered features. Consider partitioning by invoked_at.';
COMMENT ON COLUMN public.ai_feature_usage.ride_start_time
    IS 'Partition key copied from related ride table (e.g., mm_rides) for composite foreign key 
        (if ride_id is not NULL).';
COMMENT ON COLUMN public.ai_feature_usage.feature_name
    IS 'Identifier for the specific AI-driven feature that was used.';
COMMENT ON COLUMN public.ai_feature_usage.context
    IS 'Additional context relevant to the feature usage as JSONB, e.g., {"booking_id": "...", "location_geo": "..."}.';

-- Indexes for Feature Usage
CREATE INDEX IF NOT EXISTS idx_ai_fu_feature_time ON public.ai_feature_usage(feature_name, invoked_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_fu_user_time ON public.ai_feature_usage(
    user_id, invoked_at DESC
) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_ai_fu_context ON public.ai_feature_usage USING GIN (
    context
) WHERE context IS NOT NULL;
-- Index for potential composite FK lookup to rides
CREATE INDEX IF NOT EXISTS idx_ai_fu_ride
    ON public.ai_feature_usage(ride_id, ride_start_time) WHERE ride_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 5. Analysis Report Definitions (analysis_reports)
-- Description: Defines reusable analytical reports.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.analysis_reports (
    report_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    report_name         VARCHAR(100) NOT NULL UNIQUE, -- Unique name for the report
    report_type         public.report_type NOT NULL, -- Type of report (ENUM from 001)
    description         TEXT NULL,
    -- Default or required parameters
    parameters          JSONB NULL CHECK (parameters IS NULL OR jsonb_typeof(parameters) = 'object'), 
    query_or_definition TEXT NULL,          -- SQL query or definition used to generate the report (optional)
    schedule            TEXT NULL,          -- Optional schedule (CRON or RRULE) for automatic generation
    is_active           BOOLEAN DEFAULT TRUE NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    created_by          UUID NULL,          -- User who created the report definition (FK defined later)
    updated_at          TIMESTAMPTZ NULL    -- Automatically updated by trigger
);
COMMENT ON TABLE public.analysis_reports
    IS '[VoyaGo][Analytics] Definitions for recurring or on-demand analytical reports.';
COMMENT ON COLUMN public.analysis_reports.parameters
    IS 'Defines parameters the report accepts as JSONB. 
        Example: {"period": "7d", "zone_id": "uuid", "default_format": "csv"}';
COMMENT ON COLUMN public.analysis_reports.query_or_definition
    IS 'Optional: The actual SQL query or definition used by the report generation engine.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_analysis_reports ON public.analysis_reports;
CREATE TRIGGER trg_set_timestamp_on_analysis_reports
    BEFORE UPDATE ON public.analysis_reports
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Reports
CREATE INDEX IF NOT EXISTS idx_ar_active_schedule
    ON public.analysis_reports(is_active, schedule) WHERE schedule IS NOT NULL; -- Find active scheduled reports


-------------------------------------------------------------------------------
-- 6. Report Runs (analysis_report_runs)
-- Description: Logs executions of defined analysis reports.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.analysis_report_runs (
    run_id              BIGSERIAL       PRIMARY KEY,
    report_id           UUID            NOT NULL,   -- Link to the report definition (FK defined later)
    triggered_at        TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    started_at          TIMESTAMPTZ     NULL,
    finished_at         TIMESTAMPTZ     NULL,
    status              public.analysis_report_status NOT NULL DEFAULT 'PENDING', -- Run status (ENUM from 001)
    output_uri          TEXT            NULL,       -- URI of the generated report output (e.g., S3 path)
    error_message       TEXT            NULL,       -- Error details if run failed
    run_by_user_id      UUID            NULL,       -- User who initiated manual run (FK defined later)
    run_duration_ms     INTEGER         NULL CHECK (run_duration_ms IS NULL OR run_duration_ms >= 0)
);
COMMENT ON TABLE public.analysis_report_runs
    IS '[VoyaGo][Analytics] Logs execution history and status for generated analysis reports.';
COMMENT ON COLUMN public.analysis_report_runs.output_uri
    IS 'Location (e.g., S3 path, internal storage reference) where the generated report file is stored.';

-- Indexes for Report Runs
CREATE INDEX IF NOT EXISTS idx_ar_runs_report_time
    ON public.analysis_report_runs(report_id, triggered_at DESC); -- Find runs for a specific report
CREATE INDEX IF NOT EXISTS idx_ar_runs_status ON public.analysis_report_runs(status);


-------------------------------------------------------------------------------
-- 7. Report Snapshots (analysis_report_snapshots)
-- Description: Stores results or summaries of generated reports for quick access.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.analysis_report_snapshots (
    snapshot_id     BIGSERIAL       PRIMARY KEY,
    run_id          BIGINT          NOT NULL,   -- Link to the specific report run (FK defined later)
    snapshot_time   TIMESTAMPTZ     DEFAULT clock_timestamp() NOT NULL,
    -- Report data/summary as JSONB, or a reference to external storage
    data            JSONB   NOT NULL CHECK (jsonb_typeof(data) = 'object' OR jsonb_typeof(data) = 'array')
);
COMMENT ON TABLE public.analysis_report_snapshots
    IS '[VoyaGo][Analytics] Stores snapshots (results or summaries) of generated reports, 
        possibly linking to larger files.';
COMMENT ON COLUMN public.analysis_report_snapshots.data
    IS 'Contains either the report data itself (for smaller reports) or metadata referencing 
        an external file (e.g., {"file_type": "csv", "s3_uri": "...", "row_count": 10000}).';

-- Index for Snapshots
CREATE INDEX IF NOT EXISTS idx_ars_run ON public.analysis_report_snapshots(run_id);


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- ai_model_versions -> ai_model_registry (model_id -> model_id) [CASCADE]
-- ai_model_versions -> core_user_profiles (created_by_user_id -> user_id) [SET NULL]
--
-- ai_model_registry_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- ai_model_registry_history -> ai_model_registry (model_id -> model_id) [CASCADE]
--
-- ai_inference_requests -> ai_model_registry (model_id -> model_id) [RESTRICT]
-- ai_inference_requests -> ai_model_versions (version_id -> version_id) [RESTRICT]
-- ai_inference_requests -> core_user_profiles (user_id -> user_id) [SET NULL]
--
-- ai_inference_responses -> ai_inference_requests (request_requested_at, request_id -> 
    --requested_at, request_id) [CASCADE] -- COMPOSITE FK
--
-- ai_training_jobs -> ai_model_registry (model_id -> model_id) [CASCADE]
--
-- ai_training_runs -> ai_training_jobs (job_id -> job_id) [CASCADE]
-- ai_training_runs -> ai_model_versions (model_version_id -> version_id) [SET NULL]
--
-- ai_feature_usage -> core_user_profiles (user_id -> user_id) [SET NULL]
-- ai_feature_usage -> ai_model_versions (model_version_id -> version_id) [SET NULL]
-- ai_feature_usage -> mm_rides (ride_start_time, ride_id -> start_time, ride_id) [SET NULL?] 
    -- COMPOSITE FK (Example for mm_rides)
-- ai_feature_usage -> ??? (ride_id -> other ride tables?) [Polymorphic]
--
-- analysis_reports -> core_user_profiles (created_by -> user_id) [SET NULL]
--
-- analysis_report_runs -> analysis_reports (report_id -> report_id) [CASCADE]
-- analysis_report_runs -> core_user_profiles (run_by_user_id -> user_id) [SET NULL]
--
-- analysis_report_snapshots -> analysis_report_runs (run_id -> run_id) [CASCADE]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 023_ai_analysis_support.sql (Version 1.2)
-- ============================================================================
 