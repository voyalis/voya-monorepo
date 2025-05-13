-- ============================================================================
-- Migration: 024_partition_creation.sql (Version 1.3 - Standardized Formatting)
-- Description: VoyaGo - Creates the initial physical partitions for high-volume tables.
--              This script manually creates monthly partitions for April, May,
--              and June 2025. Subsequent partitions should be managed automatically
--              by the 'vg_maintain_partitions' procedure (defined in Migration 022)
--              via a scheduled job (defined in system_jobs).
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining the parent partitioned tables:
--               008_api_management.sql (api_usage_logs)
--               009_geo_location.sql (fleet_vehicle_location_history)
--               010_booking_core.sql (booking_bookings)
--               013_cargo_logistics.sql (cargo_tracking_events)
--               014_micromobility.sql (mm_rides)
--               010b_rental_schema.sql (rental_vehicle_availability)
--               022_system_management.sql (audit_log)
--               023_ai_analysis_support.sql (ai_inference_requests, ai_inference_responses)
-- ============================================================================

BEGIN;

-- Timezone Note: All partition boundaries below are defined assuming +03 (e.g., Europe/Istanbul) timezone.
-- If your database server or application primarily uses UTC or another timezone,
-- update the '+03' offsets consistently in the TIMESTAMPTZ literals below (e.g., use '+00' for UTC).

-------------------------------------------------------------------------------
-- 1. Create Partitions for: public.audit_log
--    Partition Key: timestamp (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_log_y2025m04 PARTITION OF public.audit_log
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.audit_log_y2025m04
    IS '[Partition][Monthly] Data Audit Logs for April 2025.';

CREATE TABLE IF NOT EXISTS public.audit_log_y2025m05 PARTITION OF public.audit_log
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.audit_log_y2025m05
    IS '[Partition][Monthly] Data Audit Logs for May 2025.';

CREATE TABLE IF NOT EXISTS public.audit_log_y2025m06 PARTITION OF public.audit_log
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.audit_log_y2025m06
    IS '[Partition][Monthly] Data Audit Logs for June 2025.';

-------------------------------------------------------------------------------
-- 2. Create Partitions for: public.fleet_vehicle_location_history
--    Partition Key: recorded_at (TIMESTAMPTZ) -- Corrected Key Name
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.fleet_vehicle_location_history_y2025m04
    PARTITION OF public.fleet_vehicle_location_history
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.fleet_vehicle_location_history_y2025m04
    IS '[Partition][Monthly] Vehicle Location History for April 2025.';

CREATE TABLE IF NOT EXISTS public.fleet_vehicle_location_history_y2025m05
    PARTITION OF public.fleet_vehicle_location_history
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.fleet_vehicle_location_history_y2025m05
    IS '[Partition][Monthly] Vehicle Location History for May 2025.';

CREATE TABLE IF NOT EXISTS public.fleet_vehicle_location_history_y2025m06
    PARTITION OF public.fleet_vehicle_location_history
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.fleet_vehicle_location_history_y2025m06
    IS '[Partition][Monthly] Vehicle Location History for June 2025.';

-------------------------------------------------------------------------------
-- 3. Create Partitions for: public.booking_bookings
--    Partition Key: created_at (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.booking_bookings_y2025m04 PARTITION OF public.booking_bookings
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.booking_bookings_y2025m04
    IS '[Partition][Monthly] Bookings created in April 2025.';

CREATE TABLE IF NOT EXISTS public.booking_bookings_y2025m05 PARTITION OF public.booking_bookings
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.booking_bookings_y2025m05
    IS '[Partition][Monthly] Bookings created in May 2025.';

CREATE TABLE IF NOT EXISTS public.booking_bookings_y2025m06 PARTITION OF public.booking_bookings
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.booking_bookings_y2025m06
    IS '[Partition][Monthly] Bookings created in June 2025.';

-------------------------------------------------------------------------------
-- 4. Create Partitions for: public.ai_inference_requests
--    Partition Key: requested_at (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_inference_requests_y2025m04 PARTITION OF public.ai_inference_requests
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_requests_y2025m04
    IS '[Partition][Monthly] AI Inference Requests for April 2025.';

CREATE TABLE IF NOT EXISTS public.ai_inference_requests_y2025m05 PARTITION OF public.ai_inference_requests
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_requests_y2025m05
    IS '[Partition][Monthly] AI Inference Requests for May 2025.';

CREATE TABLE IF NOT EXISTS public.ai_inference_requests_y2025m06 PARTITION OF public.ai_inference_requests
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_requests_y2025m06
    IS '[Partition][Monthly] AI Inference Requests for June 2025.';

-------------------------------------------------------------------------------
-- 5. Create Partitions for: public.ai_inference_responses
--    Partition Key: completed_at (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.ai_inference_responses_y2025m04 PARTITION OF public.ai_inference_responses
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_responses_y2025m04
    IS '[Partition][Monthly] AI Inference Responses completed in April 2025.';

CREATE TABLE IF NOT EXISTS public.ai_inference_responses_y2025m05 PARTITION OF public.ai_inference_responses
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_responses_y2025m05
    IS '[Partition][Monthly] AI Inference Responses completed in May 2025.';

CREATE TABLE IF NOT EXISTS public.ai_inference_responses_y2025m06 PARTITION OF public.ai_inference_responses
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.ai_inference_responses_y2025m06
    IS '[Partition][Monthly] AI Inference Responses completed in June 2025.';

-------------------------------------------------------------------------------
-- 6. Create Partitions for: public.api_usage_logs
--    Partition Key: timestamp (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.api_usage_logs_y2025m04 PARTITION OF public.api_usage_logs
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.api_usage_logs_y2025m04
    IS '[Partition][Monthly] API Usage Logs for April 2025.';

CREATE TABLE IF NOT EXISTS public.api_usage_logs_y2025m05 PARTITION OF public.api_usage_logs
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.api_usage_logs_y2025m05
    IS '[Partition][Monthly] API Usage Logs for May 2025.';

CREATE TABLE IF NOT EXISTS public.api_usage_logs_y2025m06 PARTITION OF public.api_usage_logs
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.api_usage_logs_y2025m06
    IS '[Partition][Monthly] API Usage Logs for June 2025.';

-------------------------------------------------------------------------------
-- 7. Create Partitions for: public.mm_rides
--    Partition Key: start_time (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.mm_rides_y2025m04 PARTITION OF public.mm_rides
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.mm_rides_y2025m04
    IS '[Partition][Monthly] Micromobility Rides started in April 2025.';

CREATE TABLE IF NOT EXISTS public.mm_rides_y2025m05 PARTITION OF public.mm_rides
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.mm_rides_y2025m05
    IS '[Partition][Monthly] Micromobility Rides started in May 2025.';

CREATE TABLE IF NOT EXISTS public.mm_rides_y2025m06 PARTITION OF public.mm_rides
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.mm_rides_y2025m06
    IS '[Partition][Monthly] Micromobility Rides started in June 2025.';

-------------------------------------------------------------------------------
-- 8. Create Partitions for: public.cargo_tracking_events
--    Partition Key: event_time (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cargo_tracking_events_y2025m04 PARTITION OF public.cargo_tracking_events
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.cargo_tracking_events_y2025m04
    IS '[Partition][Monthly] Cargo Tracking Events for April 2025.';

CREATE TABLE IF NOT EXISTS public.cargo_tracking_events_y2025m05 PARTITION OF public.cargo_tracking_events
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.cargo_tracking_events_y2025m05
    IS '[Partition][Monthly] Cargo Tracking Events for May 2025.';

CREATE TABLE IF NOT EXISTS public.cargo_tracking_events_y2025m06 PARTITION OF public.cargo_tracking_events
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.cargo_tracking_events_y2025m06
    IS '[Partition][Monthly] Cargo Tracking Events for June 2025.';

-------------------------------------------------------------------------------
-- 9. Create Partitions for: public.rental_vehicle_availability
--    Partition Key: start_time (TIMESTAMPTZ)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.rental_vehicle_availability_y2025m04 
    PARTITION OF public.rental_vehicle_availability
    FOR VALUES FROM ('2025-04-01 00:00:00+03') TO ('2025-05-01 00:00:00+03');
COMMENT ON TABLE public.rental_vehicle_availability_y2025m04
    IS '[Partition][Monthly] Rental Vehicle Availability for April 2025.';

CREATE TABLE IF NOT EXISTS public.rental_vehicle_availability_y2025m05 
    PARTITION OF public.rental_vehicle_availability
    FOR VALUES FROM ('2025-05-01 00:00:00+03') TO ('2025-06-01 00:00:00+03');
COMMENT ON TABLE public.rental_vehicle_availability_y2025m05
    IS '[Partition][Monthly] Rental Vehicle Availability for May 2025.';

CREATE TABLE IF NOT EXISTS public.rental_vehicle_availability_y2025m06 
    PARTITION OF public.rental_vehicle_availability
    FOR VALUES FROM ('2025-06-01 00:00:00+03') TO ('2025-07-01 00:00:00+03');
COMMENT ON TABLE public.rental_vehicle_availability_y2025m06
    IS '[Partition][Monthly] Rental Vehicle Availability for June 2025.';


COMMIT;

-- ============================================================================
-- End of Migration: 024_partition_creation.sql (Version 1.3)
-- ============================================================================
-- IMPORTANT NOTE: This script only creates the initial partitions.
-- Future partitions (and dropping old ones) must be managed automatically
-- by regularly executing the 'vg_maintain_partitions' procedure (defined in 022)
-- via a scheduled job (e.g., using the 'system_jobs' table defined in 022).
-- ============================================================================
