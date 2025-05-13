-- ============================================================================
-- Migration: V025.9__Constraints_System_AI_Dispatch.sql (Version 1.1 - Composite FK Fix)
-- Description: Add FK constraints for System, AI & Dispatch modules.
--              Uses composite FKs for references to partitioned tables.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: Migrations defining System/AI/Dispatch tables and referenced tables,
--               including addition of partition key columns to relevant tables.
--               (e.g., 001..005, 008, 009, 010, 014, 022, 023)
-- ============================================================================

-- Note: Explicit BEGIN/COMMIT are removed as Flyway handles transactions.

-------------------------------------------------------------------------------
-- Ensure Idempotency: Drop constraints first if they exist
-------------------------------------------------------------------------------
-- System Drops
ALTER TABLE public.system_feature_flags DROP CONSTRAINT IF EXISTS fk_sff_created_by;
ALTER TABLE public.system_feature_flags DROP CONSTRAINT IF EXISTS fk_sff_updated_by;
ALTER TABLE public.system_job_runs DROP CONSTRAINT IF EXISTS fk_sjr_job;
ALTER TABLE public.system_feature_flags_history DROP CONSTRAINT IF EXISTS fk_sffh_actor;
ALTER TABLE public.system_feature_flags_history DROP CONSTRAINT IF EXISTS fk_sffh_flag;
-- Cannot add FK from partitioned table easily
ALTER TABLE public.audit_log DROP CONSTRAINT IF EXISTS fk_al_actor; 

-- AI Drops
ALTER TABLE public.ai_model_versions DROP CONSTRAINT IF EXISTS fk_amv_model;
ALTER TABLE public.ai_model_versions DROP CONSTRAINT IF EXISTS fk_amv_creator;
ALTER TABLE public.ai_model_registry_history DROP CONSTRAINT IF EXISTS fk_amrh_actor;
ALTER TABLE public.ai_model_registry_history DROP CONSTRAINT IF EXISTS fk_amrh_model;
ALTER TABLE public.ai_inference_requests DROP CONSTRAINT IF EXISTS fk_air_model;
ALTER TABLE public.ai_inference_requests DROP CONSTRAINT IF EXISTS fk_air_version;
ALTER TABLE public.ai_inference_requests DROP CONSTRAINT IF EXISTS fk_air_user;
-- Will be recreated as composite
ALTER TABLE public.ai_inference_responses DROP CONSTRAINT IF EXISTS fk_aires_req; 
ALTER TABLE public.ai_training_jobs DROP CONSTRAINT IF EXISTS fk_atj_model;
ALTER TABLE public.ai_training_runs DROP CONSTRAINT IF EXISTS fk_atr_job;
ALTER TABLE public.ai_training_runs DROP CONSTRAINT IF EXISTS fk_atr_version;
ALTER TABLE public.ai_feature_usage DROP CONSTRAINT IF EXISTS fk_afu_user;
ALTER TABLE public.ai_feature_usage DROP CONSTRAINT IF EXISTS fk_afu_model_version;
-- Will be recreated as composite
ALTER TABLE public.ai_feature_usage DROP CONSTRAINT IF EXISTS fk_afu_ride; 

-- Analysis Drops
ALTER TABLE public.analysis_reports DROP CONSTRAINT IF EXISTS fk_ar_created_by;
ALTER TABLE public.analysis_report_runs DROP CONSTRAINT IF EXISTS fk_arr_report;
ALTER TABLE public.analysis_report_runs DROP CONSTRAINT IF EXISTS fk_arr_run_by;
ALTER TABLE public.analysis_report_snapshots DROP CONSTRAINT IF EXISTS fk_ars_run;

-- Dispatch Drops
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_user;
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_pickup_addr;
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_dropoff_addr;
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_partner;
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_driver;
ALTER TABLE public.dispatch_requests DROP CONSTRAINT IF EXISTS fk_dr_vehicle;
ALTER TABLE public.dispatch_requests_history DROP CONSTRAINT IF EXISTS fk_drh_actor;
ALTER TABLE public.dispatch_requests_history DROP CONSTRAINT IF EXISTS fk_drh_request;
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_request;
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_driver;
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_vehicle;
-- Will be recreated as composite
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_leg; 
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_creator;
ALTER TABLE public.dispatch_assignments DROP CONSTRAINT IF EXISTS fk_da_updater;
ALTER TABLE public.dispatch_assignments_history DROP CONSTRAINT IF EXISTS fk_dah_actor;
ALTER TABLE public.dispatch_assignments_history DROP CONSTRAINT IF EXISTS fk_dah_assignment;
ALTER TABLE public.dispatch_routes DROP CONSTRAINT IF EXISTS fk_droute_assignment;


-------------------------------------------------------------------------------
-- Add Foreign Key Constraints (DEFERRABLE INITIALLY DEFERRED)
-------------------------------------------------------------------------------

-- Section: System Module Relationships
ALTER TABLE public.system_feature_flags
    ADD CONSTRAINT fk_sff_created_by FOREIGN KEY (created_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_sff_updated_by FOREIGN KEY (updated_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.system_feature_flags_history
    ADD CONSTRAINT fk_sffh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_sffh_flag FOREIGN KEY (flag_name) REFERENCES public.system_feature_flags(
        flag_name
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.system_job_runs
    ADD CONSTRAINT fk_sjr_job FOREIGN KEY (job_id) REFERENCES public.system_jobs(
        job_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM audit_log (Partitioned - FKs only added FROM this table TO others)
ALTER TABLE public.audit_log
    ADD CONSTRAINT fk_al_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- Section: AI Module Relationships
ALTER TABLE public.ai_model_versions
    ADD CONSTRAINT fk_amv_model FOREIGN KEY (model_id) REFERENCES public.ai_model_registry(
        model_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_amv_creator FOREIGN KEY (created_by_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.ai_model_registry_history
    ADD CONSTRAINT fk_amrh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_amrh_model FOREIGN KEY (model_id) REFERENCES public.ai_model_registry(
        model_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM ai_inference_requests (to non-partitioned tables)
ALTER TABLE public.ai_inference_requests
    ADD CONSTRAINT fk_air_model FOREIGN KEY (model_id) REFERENCES public.ai_model_registry(
        model_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_air_version FOREIGN KEY (version_id) REFERENCES public.ai_model_versions(
        version_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_air_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM ai_inference_responses (Using COMPOSITE FK to ai_inference_requests)
ALTER TABLE public.ai_inference_responses
    ADD CONSTRAINT fk_aires_req FOREIGN KEY (request_requested_at, request_id) REFERENCES public.ai_inference_requests(
        requested_at, request_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.ai_training_jobs
    ADD CONSTRAINT fk_atj_model FOREIGN KEY (model_id) REFERENCES public.ai_model_registry(
        model_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.ai_training_runs
    ADD CONSTRAINT fk_atr_job FOREIGN KEY (job_id) REFERENCES public.ai_training_jobs(
        job_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_atr_version FOREIGN KEY (model_version_id) REFERENCES public.ai_model_versions(
        version_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM ai_feature_usage (Using COMPOSITE FK to mm_rides)
ALTER TABLE public.ai_feature_usage
    ADD CONSTRAINT fk_afu_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_afu_model_version FOREIGN KEY (model_version_id) REFERENCES public.ai_model_versions(
        version_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_afu_ride FOREIGN KEY (ride_start_time, ride_id) REFERENCES public.mm_rides(
        start_time, ride_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;


-- Section: Analysis Module Relationships
ALTER TABLE public.analysis_reports
    ADD CONSTRAINT fk_ar_created_by FOREIGN KEY (created_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.analysis_report_runs
    ADD CONSTRAINT fk_arr_report FOREIGN KEY (report_id) REFERENCES public.analysis_reports(
        report_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_arr_run_by FOREIGN KEY (run_by_user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.analysis_report_snapshots
    ADD CONSTRAINT fk_ars_run FOREIGN KEY (run_id) REFERENCES public.analysis_report_runs(
        run_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


-- Section: Dispatch Module Relationships
ALTER TABLE public.dispatch_requests
    ADD CONSTRAINT fk_dr_user FOREIGN KEY (user_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dr_pickup_addr FOREIGN KEY (pickup_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dr_dropoff_addr FOREIGN KEY (dropoff_address_id) REFERENCES public.core_addresses(
        address_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dr_partner FOREIGN KEY (assigned_partner_id) REFERENCES public.fleet_partners(
        partner_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dr_driver FOREIGN KEY (preferred_driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dr_vehicle FOREIGN KEY (preferred_vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.dispatch_requests_history
    ADD CONSTRAINT fk_drh_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_drh_request FOREIGN KEY (request_id) REFERENCES public.dispatch_requests(
        request_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- FKs FROM dispatch_assignments (Using COMPOSITE FK to booking_booking_legs)
ALTER TABLE public.dispatch_assignments
    ADD CONSTRAINT fk_da_request FOREIGN KEY (request_id) REFERENCES public.dispatch_requests(
        request_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_da_driver FOREIGN KEY (driver_id) REFERENCES public.fleet_drivers(
        driver_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_da_vehicle FOREIGN KEY (vehicle_id) REFERENCES public.fleet_vehicles(
        vehicle_id
    ) ON DELETE RESTRICT DEFERRABLE INITIALLY DEFERRED,
    -- ADD CONSTRAINT fk_da_leg FOREIGN KEY (booking_created_at, related_booking_leg_id) 
        --REFERENCES public.booking_booking_legs(booking_created_at, leg_id) 
        --ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_da_creator FOREIGN KEY (created_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_da_updater FOREIGN KEY (updated_by) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.dispatch_assignments_history
    ADD CONSTRAINT fk_dah_actor FOREIGN KEY (actor_id) REFERENCES public.core_user_profiles(
        user_id
    ) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT fk_dah_assignment FOREIGN KEY (assignment_id) REFERENCES public.dispatch_assignments(
        assignment_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE public.dispatch_routes
    ADD CONSTRAINT fk_droute_assignment FOREIGN KEY (assignment_id) REFERENCES public.dispatch_assignments(
        assignment_id
    ) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


-- ============================================================================
-- Planned Foreign Key Constraints (Covered in this file)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- system_feature_flags -> core_user_profiles (created_by -> user_id) [SET NULL]
-- system_feature_flags -> core_user_profiles (updated_by -> user_id) [SET NULL]
-- system_feature_flags_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- system_feature_flags_history -> system_feature_flags (flag_name -> flag_name) [CASCADE]
-- system_job_runs -> system_jobs (job_id -> job_id) [CASCADE]
-- audit_log -> core_user_profiles (actor_id -> user_id) [SET NULL] -- FK FROM Partitioned Table
--
-- ai_model_versions -> ai_model_registry (model_id -> model_id) [CASCADE]
-- ai_model_versions -> core_user_profiles (created_by_user_id -> user_id) [SET NULL]
-- ai_model_registry_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- ai_model_registry_history -> ai_model_registry (model_id -> model_id) [CASCADE]
-- ai_inference_requests -> ai_model_registry (model_id -> model_id) [RESTRICT]
-- ai_inference_requests -> ai_model_versions (version_id -> version_id) [RESTRICT]
-- ai_inference_requests -> core_user_profiles (user_id -> user_id) [SET NULL]
-- ai_inference_responses -> ai_inference_requests (request_requested_at, 
    --request_id -> requested_at, request_id) [CASCADE] -- COMPOSITE FK
-- ai_training_jobs -> ai_model_registry (model_id -> model_id) [CASCADE]
-- ai_training_runs -> ai_training_jobs (job_id -> job_id) [CASCADE]
-- ai_training_runs -> ai_model_versions (model_version_id -> version_id) [SET NULL]
-- ai_feature_usage -> core_user_profiles (user_id -> user_id) [SET NULL]
-- ai_feature_usage -> ai_model_versions (model_version_id -> version_id) [SET NULL]
-- ai_feature_usage -> mm_rides (ride_start_time, ride_id -> start_time, 
    --ride_id) [SET NULL?] -- COMPOSITE FK (Example)
--
-- analysis_reports -> core_user_profiles (created_by -> user_id) [SET NULL]
-- analysis_report_runs -> analysis_reports (report_id -> report_id) [CASCADE]
-- analysis_report_runs -> core_user_profiles (run_by_user_id -> user_id) [SET NULL]
-- analysis_report_snapshots -> analysis_report_runs (run_id -> run_id) [CASCADE]
--
-- dispatch_requests -> core_user_profiles (user_id -> user_id) [SET NULL]
-- dispatch_requests -> core_addresses (pickup_address_id -> address_id) [RESTRICT]
-- dispatch_requests -> core_addresses (dropoff_address_id -> address_id) [RESTRICT?]
-- dispatch_requests -> fleet_partners (assigned_partner_id -> partner_id) [SET NULL]
-- dispatch_requests -> fleet_drivers (preferred_driver_id -> driver_id) [SET NULL]
-- dispatch_requests -> fleet_vehicles (preferred_vehicle_id -> vehicle_id) [SET NULL]
-- Note: FK for related_entity_id depends on request_type (Polymorphic).
--
-- dispatch_requests_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- dispatch_requests_history -> dispatch_requests (request_id -> request_id) [CASCADE]
--
-- dispatch_assignments -> dispatch_requests (request_id -> request_id) [CASCADE]
-- dispatch_assignments -> fleet_drivers (driver_id -> driver_id) [RESTRICT]
-- dispatch_assignments -> fleet_vehicles (vehicle_id -> vehicle_id) [RESTRICT]
-- dispatch_assignments -> booking_booking_legs (booking_created_at, 
    --related_booking_leg_id -> booking_created_at, leg_id) [SET NULL?] -- COMPOSITE FK
-- dispatch_assignments -> core_user_profiles (created_by -> user_id) [SET NULL]
-- dispatch_assignments -> core_user_profiles (updated_by -> user_id) [SET NULL]
--
-- dispatch_assignments_history -> core_user_profiles (actor_id -> user_id) [SET NULL]
-- dispatch_assignments_history -> dispatch_assignments (assignment_id -> assignment_id) [CASCADE]
--
-- dispatch_routes -> dispatch_assignments (assignment_id -> assignment_id) [CASCADE]
-- ============================================================================


-- ============================================================================
-- End of Migration: V025.9__Constraints_System_AI_Dispatch.sql (Version 1.1)
-- ============================================================================
