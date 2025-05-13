-- ============================================================================
-- Migration: 008_api_management.sql
-- Description: Creates tables for managing third-party API integrations and
--              VoyaGo's own API access (Clients, Keys, Permissions, Usage Logs).
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql, 002_lookup_data_*.sql,
--               003_core_user.sql, 004_core_organization.sql,
--               005_fleet_management.sql (for partner relationship),
--               lkp_api_permissions (from 005_lookup_data_part4.sql assumed)
-- ============================================================================

-- Ensure pgcrypto extension is available for hashing API keys.
-- It might have been created in migration 001 already.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
COMMENT ON EXTENSION pgcrypto 
    IS '[VoyaGo][Required by API Mgmt] Provides cryptographic functions, e.g., for hashing API Keys.';


BEGIN;

-- Prefix 'system_' denotes internal system configuration tables.
-- Prefix 'api_' denotes tables related to VoyaGo's public/partner API management.

-------------------------------------------------------------------------------
-- 1. Third-Party API Integrations (system_api_integrations)
-- Description: Configuration and status monitoring for external APIs used by VoyaGo
--              (e.g., Maps, Payment Gateways, Telematics).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.system_api_integrations (
    integration_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Optional link if this is a partner-specific integration override (FK defined later)
    partner_id              UUID NULL,
    -- Identifier for the provider (e.g., 'GoogleMaps', 'Stripe', 'SomeTelematicsProvider')
    provider_name           VARCHAR(50) NOT NULL,
    service_type            VARCHAR(30) NOT NULL -- Type of service provided
    CHECK (
        service_type IN (
            'MAPS',
            'PAYMENT',
            'FLEET_TELEMATICS',
            'PUBLIC_TRANSPORT_INFO',
            'WEATHER',
            'IDENTITY_VERIFICATION',
            'OTHER'
        )
    ),
    -- Authentication method used
    auth_type               VARCHAR(20) CHECK (auth_type IN ('API_KEY', 'OAUTH2', 'BASIC', 'BEARER', 'NONE')),
    -- Reference to the secret in Supabase Vault (e.g., API Key, Client Secret)
    credentials_vault_ref   TEXT NULL,
    base_url                TEXT NULL,          -- Base URL for the API endpoint (optional)
    status                  VARCHAR(20) DEFAULT 'ACTIVE' NOT NULL
    CHECK (status IN ('ACTIVE', 'INACTIVE', 'ERROR', 'CONFIG_PENDING', 'DEPRECATED')), -- Current operational status
    -- Rate limiting details (e.g., requests/min)
    rate_limit_info         JSONB NULL CHECK (rate_limit_info IS NULL OR jsonb_typeof(rate_limit_info) = 'object'),
    last_success_at         TIMESTAMPTZ NULL,   -- Timestamp of the last successful interaction
    last_error_at           TIMESTAMPTZ NULL,   -- Timestamp of the last encountered error
    last_error_message      TEXT NULL,          -- Details of the last error
    -- Additional configuration or notes specific to the integration
    metadata                JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.system_api_integrations
    IS '[VoyaGo][System] Manages configuration and status of third-party API integrations.';
COMMENT ON COLUMN public.system_api_integrations.credentials_vault_ref
    IS '[VoyaGo][Security] Reference (name) of the secret stored in 
        Supabase Vault containing sensitive credentials (API keys, secrets).';
COMMENT ON COLUMN public.system_api_integrations.rate_limit_info
    IS '[VoyaGo] Stores rate limit information. 
        Example: {"requests_per_minute": 100, "quota_per_day": 5000}';
COMMENT ON COLUMN public.system_api_integrations.metadata
    IS '[VoyaGo] Additional configuration or notes as JSONB. 
        Example: {"default_map_style": "satellite", "requires_user_consent": true}';

-- Indexes for API Integrations
CREATE INDEX IF NOT EXISTS idx_sys_api_integrations_partner ON public.system_api_integrations(
    partner_id
) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_sys_api_integrations_provider_type ON public.system_api_integrations(
    provider_name, service_type
);
CREATE INDEX IF NOT EXISTS idx_sys_api_integrations_status ON public.system_api_integrations(status);


-------------------------------------------------------------------------------
-- 2. API Clients (api_clients)
-- Description: Represents external applications or partners consuming the VoyaGo API.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_clients (
    client_id       UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    partner_id      UUID NULL,          -- Optional link if this client belongs to a specific partner (FK defined later)
    -- Descriptive name for the client (e.g., 'Partner X Integration', 'Mobile App Backend')
    client_name     VARCHAR(100) NOT NULL UNIQUE,
    description     TEXT NULL,
    -- Technical contact
    contact_email   TEXT NULL CHECK (
        contact_email IS NULL OR contact_email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
    ),
    allowed_origins TEXT[] NULL,        -- Array of allowed origins for CORS (if applicable)
    -- Client status
    status          VARCHAR(15) DEFAULT 'ACTIVE' NOT NULL CHECK (status IN ('ACTIVE', 'INACTIVE', 'REVOKED')),
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.api_clients
IS '[VoyaGo][API] Registers external clients (applications, partners) that consume the VoyaGo API.';
COMMENT ON COLUMN public.api_clients.allowed_origins
IS 'Array of allowed domains for Cross-Origin Resource Sharing (CORS), relevant for browser-based clients.';

-- Indexes for API Clients
CREATE INDEX IF NOT EXISTS idx_api_clients_partner ON public.api_clients(partner_id) WHERE partner_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_api_clients_status ON public.api_clients(status);


-------------------------------------------------------------------------------
-- 3. API Keys (api_keys)
-- Description: Stores API keys assigned to clients (hashed, not plaintext).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_keys (
    key_id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    client_id       UUID NOT NULL,        -- Client this key belongs to (FK defined later, ON DELETE CASCADE)
    -- First part of the key for identification (e.g., 'vgk_'). MUST be unique.
    key_prefix      VARCHAR(7) NOT NULL UNIQUE,
    key_hash        TEXT NOT NULL,        -- Cryptographic hash of the actual API key. is NEVER stored.
    description     TEXT NULL,            -- Purpose or description of the key
    expires_at      TIMESTAMPTZ NULL,     -- Expiration timestamp (NULL for non-expiring keys)
    last_used_at    TIMESTAMPTZ NULL,     -- Timestamp of the last successful usage
    -- Key status
    status          VARCHAR(15) DEFAULT 'ACTIVE' NOT NULL CHECK (
        status IN ('ACTIVE', 'INACTIVE', 'REVOKED', 'EXPIRED')
    ),
    created_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at      TIMESTAMPTZ NULL
);
COMMENT ON TABLE public.api_keys
    IS '[VoyaGo][API][Security] Stores API keys assigned to clients. 
        Only a HASH of the key is stored, never the key itself!';
COMMENT ON COLUMN public.api_keys.key_prefix
    IS 'First 7 characters of the API key, used for easy 
        identification and logging (must be unique).';
COMMENT ON COLUMN public.api_keys.key_hash
    IS 'Secure cryptographic hash (e.g., SHA256) of the API key, 
        used for verification during requests.';
COMMENT ON COLUMN public.api_keys.last_used_at
    IS 'Timestamp automatically updated upon successful key usage 
        (can be handled by API gateway or application logic).';

-- Indexes for API Keys
CREATE INDEX IF NOT EXISTS idx_api_keys_client ON public.api_keys(client_id);
-- Critical for key lookup during authentication
CREATE INDEX IF NOT EXISTS idx_api_keys_prefix ON public.api_keys(key_prefix);
-- Find active/expiring keys
CREATE INDEX IF NOT EXISTS idx_api_keys_status_expiry ON public.api_keys(status, expires_at);


-------------------------------------------------------------------------------
-- 4. Client Permissions (api_client_permissions) - M2M
-- Description: Maps API clients to the permissions they are granted.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_client_permissions (
    client_id       UUID NOT NULL,          -- FK to api_clients (defined later, ON DELETE CASCADE)
    permission_code VARCHAR(100) NOT NULL,  -- FK to lkp_api_permissions (defined later, ON DELETE CASCADE)
    granted_at      TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    PRIMARY KEY (client_id, permission_code)
);
COMMENT ON TABLE public.api_client_permissions
IS '[VoyaGo][API] Many-to-many mapping assigning specific API permissions (from lkp_api_permissions) to API clients.';
-- Note: Composite primary key usually provides sufficient indexing.


-------------------------------------------------------------------------------
-- 5. API Usage Logs (api_usage_logs) - PARTITIONED TABLE
-- Description: Detailed logs of VoyaGo API calls. Partitioned by timestamp for manageability.
-- Note: Partitions need to be created and managed separately (e.g., via cron or pg_partman).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_usage_logs (
    log_id              BIGSERIAL NOT NULL, -- Changed from just BIGSERIAL to NOT NULL
    api_key_id          UUID NULL,        -- Key used for the request (if applicable)
    client_id           UUID NULL,        -- Client making the request (derived from key)
    user_id             UUID NULL,        -- Authenticated user associated with the request (if applicable)
    timestamp           TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), -- Partition Key: Time of the request
    http_method         VARCHAR(10) NOT NULL, -- GET, POST, PUT, DELETE, etc.
    endpoint_path       TEXT NOT NULL,        -- API endpoint path requested
    -- URL query parameters
    query_params        JSONB NULL CHECK (query_params IS NULL OR jsonb_typeof(query_params) = 'object'),
    -- Hash of the request body (optional, for tracing without storing large/sensitive data)
    request_body_hash   TEXT NULL,
    response_status_code INT NOT NULL,       -- HTTP status code returned
    latency_ms          INTEGER NULL,     -- Request processing time in milliseconds
    ip_address          INET NULL,        -- Client IP address
    user_agent          TEXT NULL,        -- Client user agent string
    -- Structured error details, if any
    error_details       JSONB NULL CHECK (error_details IS NULL OR jsonb_typeof(error_details) = 'object'),
    -- Additional context (e.g., correlation ID)
    context             JSONB NULL CHECK (context IS NULL OR jsonb_typeof(context) = 'object'),
    PRIMARY KEY (timestamp, log_id) -- Composite primary key including the partition key
) PARTITION BY RANGE (timestamp);

COMMENT ON TABLE public.api_usage_logs
    IS '[VoyaGo][API][Log] Stores detailed logs of API usage. 
        Partitioned by timestamp for performance and data management.';
COMMENT ON COLUMN public.api_usage_logs.timestamp
    IS 'Timestamp of the request, used as the partitioning key.';
COMMENT ON COLUMN public.api_usage_logs.request_body_hash
    IS 'Optional hash of the request body for integrity checks or tracing, 
        avoiding storage of potentially sensitive payload.';
COMMENT ON COLUMN public.api_usage_logs.context
    IS '[VoyaGo] Additional contextual information for tracing and debugging, e.g., 
        correlation IDs, session info.';
COMMENT ON CONSTRAINT api_usage_logs_pkey ON public.api_usage_logs
    IS 'Composite primary key including the partition key (timestamp) is 
        required for partitioned tables.';


-- Indexes for API Usage Logs (Defined on the main table, propagated to partitions)
-- The primary key already indexes (timestamp, log_id).
-- CREATE INDEX IF NOT EXISTS idx_api_usage_logs_time ON public.api_usage_logs(timestamp DESC); -- Covered by PK
CREATE INDEX IF NOT EXISTS idx_api_usage_logs_key ON public.api_usage_logs(api_key_id) WHERE api_key_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_api_usage_logs_client ON public.api_usage_logs(client_id) WHERE client_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_api_usage_logs_user ON public.api_usage_logs(user_id) WHERE user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_api_usage_logs_endpoint_status ON public.api_usage_logs(
    endpoint_path text_pattern_ops, response_status_code
);
COMMENT ON INDEX public.idx_api_usage_logs_endpoint_status 
    IS 'Index to query logs by endpoint path (prefix) and status code.';
CREATE INDEX IF NOT EXISTS idx_gin_api_usage_logs_context ON public.api_usage_logs USING gin(
    context
) WHERE context IS NOT NULL;
COMMENT ON INDEX public.idx_gin_api_usage_logs_context 
    IS '[VoyaGo][Perf] GIN index for searching within the JSONB context field.';


-- ============================================================================
-- Triggers (Common updated_at triggers)
-- ============================================================================

-- Trigger for system_api_integrations
DROP TRIGGER IF EXISTS trg_set_timestamp_on_system_api_integrations ON public.system_api_integrations;
CREATE TRIGGER trg_set_timestamp_on_system_api_integrations
BEFORE UPDATE ON public.system_api_integrations
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for api_clients
DROP TRIGGER IF EXISTS trg_set_timestamp_on_api_clients ON public.api_clients;
CREATE TRIGGER trg_set_timestamp_on_api_clients
BEFORE UPDATE ON public.api_clients
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Trigger for api_keys
DROP TRIGGER IF EXISTS trg_set_timestamp_on_api_keys ON public.api_keys;
CREATE TRIGGER trg_set_timestamp_on_api_keys
BEFORE UPDATE ON public.api_keys
FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Note: No updated_at trigger needed for api_client_permissions (M2M table).
-- Note: No updated_at trigger needed for api_usage_logs (append-only log table).


-- ============================================================================
-- Foreign Key Constraints (Placeholders - To be defined later, DEFERRABLE)
-- ============================================================================

-- TODO in Migration 025: Add DEFERRABLE FK 
    --from system_api_integrations.partner_id to fleet_partners.partner_id (ON DELETE SET NULL?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_clients.partner_id to fleet_partners.partner_id (ON DELETE SET NULL?)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_keys.client_id to api_clients.client_id (ON DELETE CASCADE) -- Delete keys if client deleted
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_client_permissions.client_id to api_clients.client_id (ON DELETE CASCADE)
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_client_permissions.permission_code to lkp_api_permissions.permission_code (ON DELETE CASCADE) 
    -- Need lkp_api_permissions table from lookups
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_usage_logs.api_key_id to api_keys.key_id (ON DELETE SET NULL?) 
    -- Keep logs even if key deleted?
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_usage_logs.client_id to api_clients.client_id (ON DELETE SET NULL?) 
    -- Keep logs even if client deleted?
-- TODO in Migration 025: Add DEFERRABLE FK 
    --from api_usage_logs.user_id to core_user_profiles.user_id (ON DELETE SET NULL?) 
    -- Keep logs even if user deleted?


COMMIT;

-- ============================================================================
-- End of Migration: 008_api_management.sql
-- ============================================================================
