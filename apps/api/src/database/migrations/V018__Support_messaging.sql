-- ============================================================================
-- Migration: 018_support_messaging.sql (Version 1.1 - Added Partition Keys for FKs)
-- Description: VoyaGo - Support & Messaging Module: Tickets, Reports, Ratings,
--              Chat Rooms, and Messages. Adds partition key columns for composite FKs.
-- Schema: public
-- Author: VoyaGo Team
-- Date: 2025-05-04 -- Updated based on current time
-- Dependencies: 001_core_initial_setup.sql (ENUMs), 002_lookup_data_*.sql (Lookups),
--               003_core_user.sql (Users), 010_booking_core.sql (Bookings),
--               011_payment_wallet.sql (Payments), 014_micromobility.sql (Rides)
-- ============================================================================

BEGIN;

-- Prefixes 'support_' and 'msg_' denote tables related to their respective modules.

-------------------------------------------------------------------------------
-- 1. Support Tickets (support_tickets) - ** booking_created_at ADDED **
-- Description: Stores user-submitted support requests (tickets).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_tickets (
    ticket_id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- User-friendly ticket identifier
    ticket_number           VARCHAR(20) NOT NULL UNIQUE 
        DEFAULT ('TKT' || upper(substr(replace(uuid_generate_v4()::text, '-', ''), 1, 8))),
    -- User who created the ticket
    user_id                 UUID NOT NULL,
    -- Optional links to related entities (Composite FK for booking)
    related_booking_id      UUID NULL,
    booking_created_at      TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    related_payment_id      UUID NULL,
    -- Polymorphic link to other entities (e.g., vehicle, property)
    related_entity_type     VARCHAR(50) NULL,
    related_entity_id       TEXT NULL,
    -- Ticket details
    subject                 TEXT NOT NULL,
    description             TEXT NOT NULL,
    -- Category of the support request (FK defined later)
    category_code           VARCHAR(50) NULL,
    -- Priority level (ENUM from 001)
    priority                public.support_ticket_priority DEFAULT 'MEDIUM' NOT NULL,
    -- Current status (ENUM from 001)
    status                  public.support_ticket_status DEFAULT 'NEW' NOT NULL,
    -- Assigned support agent (FK defined later)
    assigned_agent_id       UUID NULL,
    -- Resolution details
    resolution_notes        TEXT NULL,
    -- Tags for categorization
    tags                    TEXT[] NULL,
    -- Timestamps
    created_at              TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    updated_at              TIMESTAMPTZ NULL, -- Automatically updated by trigger
    resolved_at             TIMESTAMPTZ NULL,
    closed_at               TIMESTAMPTZ NULL,

    CONSTRAINT chk_st_booking_created_at CHECK (related_booking_id IS NULL OR booking_created_at IS NOT NULL)
);
COMMENT ON TABLE public.support_tickets
    IS '[VoyaGo][Support] Stores user support requests (tickets) and their status.';
COMMENT ON COLUMN public.support_tickets.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key 
        (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.support_tickets.related_entity_type
    IS 'Indicates the type of entity (e.g., ''fleet_vehicles'', 
        ''acc_properties'') related to the ticket, used with related_entity_id.';
COMMENT ON COLUMN public.support_tickets.related_entity_id
    IS 'The ID (UUID or other format) of the entity referenced in related_entity_type.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_support_tickets ON public.support_tickets;
CREATE TRIGGER trg_set_timestamp_on_support_tickets
    BEFORE UPDATE ON public.support_tickets
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Tickets
CREATE INDEX IF NOT EXISTS idx_support_tickets_user_status ON public.support_tickets(user_id, status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_agent_status
    ON public.support_tickets(assigned_agent_id, status) WHERE assigned_agent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON public.support_tickets(status);
-- Index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_support_tickets_booking
    ON public.support_tickets(related_booking_id, booking_created_at) WHERE related_booking_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_support_tickets_tags
    ON public.support_tickets USING GIN (tags) WHERE tags IS NOT NULL;


-------------------------------------------------------------------------------
-- 2. Support Ticket Replies (support_ticket_replies)
-- Description: Stores messages and internal notes related to a support ticket.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_ticket_replies (
    reply_id            BIGSERIAL PRIMARY KEY,
    -- Link to the parent ticket (FK defined later, ON DELETE CASCADE)
    ticket_id           UUID NOT NULL,
    -- User who wrote the reply (Customer or Support Agent) (FK defined later)
    user_id             UUID NOT NULL,
    message             TEXT NOT NULL,      -- Content of the reply
    -- Flag for internal-only notes visible only to support staff
    is_internal_note    BOOLEAN DEFAULT FALSE NOT NULL,
    -- Optional attachments (e.g., screenshots) stored as JSONB array
    attachments         JSONB NULL CHECK (attachments IS NULL OR jsonb_typeof(attachments) = 'array'),
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL
    -- updated_at is generally not needed for replies
);
COMMENT ON TABLE public.support_ticket_replies
    IS '[VoyaGo][Support] Stores individual replies and internal notes 
        associated with a support ticket.';
COMMENT ON COLUMN public.support_ticket_replies.attachments
    IS '[VoyaGo] Array of attachment metadata as JSONB. 
        Example: [{ "name": "screenshot.png", "url": "storage://...", "size_bytes": 12345 }]';

-- Indexes for Replies
-- Critical index for retrieving replies for a ticket, ordered chronologically
CREATE INDEX IF NOT EXISTS idx_ticket_replies_ticket_time
    ON public.support_ticket_replies(ticket_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_ticket_replies_user ON public.support_ticket_replies(user_id);


-------------------------------------------------------------------------------
-- 3. User Reports (support_user_reports) - ** booking_created_at, ride_start_time ADDED **
-- Description: Allows users to report issues regarding other entities (users, drivers, etc.).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_user_reports (
    report_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- User submitting the report (FK defined later)
    reporter_user_id    UUID NOT NULL,
    -- Polymorphic link to the entity being reported
    reported_entity_type VARCHAR(20) NOT NULL CHECK (
        reported_entity_type IN ('USER', 'DRIVER', 'VEHICLE', 'BOOKING', 'PROPERTY', 'OTHER')
    ),
    reported_entity_id  TEXT NULL,        -- ID of the reported entity
    -- Optional links to context (Composite FKs defined later)
    related_booking_id  UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    related_ride_id     UUID NULL,        -- Could be mm_rides.ride_id etc.
    ride_start_time     TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN (Partition Key for mm_rides FK)
    -- Reason for the report (FK to lkp_report_reasons defined later)
    reason_code         VARCHAR(50) NULL,
    details             TEXT NULL,        -- User's detailed description of the issue
    report_time         TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- Status of the report investigation (ENUM from 001)
    status              public.report_status DEFAULT 'NEW' NOT NULL,
    -- Resolution details
    resolution_notes    TEXT NULL,
    -- Admin/Support user who resolved the report (FK defined later)
    resolved_by_user_id UUID NULL,
    resolved_at         TIMESTAMPTZ NULL,
    updated_at          TIMESTAMPTZ NULL, -- Automatically updated by trigger

    CONSTRAINT chk_sur_booking_created_at CHECK (related_booking_id IS NULL 
        OR booking_created_at IS NOT NULL),
    CONSTRAINT chk_sur_ride_start_time CHECK (related_ride_id IS NULL OR ride_start_time IS NOT NULL)
);
COMMENT ON TABLE public.support_user_reports
    IS '[VoyaGo][Support] Records reports submitted by users about other entities or experiences.';
COMMENT ON COLUMN public.support_user_reports.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key 
        (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.support_user_reports.ride_start_time
    IS 'Partition key copied from related ride table (e.g., mm_rides) 
        for composite foreign key (if related_ride_id is not NULL).';
COMMENT ON COLUMN public.support_user_reports.reported_entity_type
    IS 'Type of entity being reported (e.g., USER, DRIVER, VEHICLE, BOOKING, PROPERTY).';
COMMENT ON COLUMN public.support_user_reports.reported_entity_id
    IS 'The ID (UUID or text) of the specific entity being reported.';

-- Trigger for updated_at
DROP TRIGGER IF EXISTS trg_set_timestamp_on_support_user_reports ON public.support_user_reports;
CREATE TRIGGER trg_set_timestamp_on_support_user_reports
    BEFORE UPDATE ON public.support_user_reports
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for User Reports
CREATE INDEX IF NOT EXISTS idx_user_reports_reporter
    ON public.support_user_reports(reporter_user_id, report_time DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported
    ON public.support_user_reports(reported_entity_type, reported_entity_id);
CREATE INDEX IF NOT EXISTS idx_user_reports_status
    ON public.support_user_reports(status);
-- Index for composite FK lookup to bookings
CREATE INDEX IF NOT EXISTS idx_user_reports_booking
    ON public.support_user_reports(related_booking_id, booking_created_at) 
        WHERE related_booking_id IS NOT NULL;
-- Index for potential composite FK lookup to rides
CREATE INDEX IF NOT EXISTS idx_user_reports_ride
    ON public.support_user_reports(related_ride_id, ride_start_time) 
        WHERE related_ride_id IS NOT NULL;


-------------------------------------------------------------------------------
-- 4. Ratings (support_ratings) - ** booking_created_at, ride_start_time ADDED **
-- Description: Stores ratings submitted for various entities within the platform.
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.support_ratings (
    rating_id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Context of the rating (Composite FKs defined later)
    booking_id          UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    ride_id             UUID NULL,        -- Could be mm_rides.ride_id etc.
    ride_start_time     TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    related_ticket_id   UUID NULL,        -- Related support ticket (if rating support)
    -- Who rated?
    rater_user_id       UUID NOT NULL,      -- User giving the rating (FK defined later)
    -- What/Who is being rated? (Polymorphic)
    rated_entity_type   public.rated_entity_type NOT NULL, -- Type of entity (ENUM from 001)
    rated_entity_id     TEXT NOT NULL,      -- ID of the rated entity (UUID or text)
    -- Rating details
    rating_score        SMALLINT NOT NULL CHECK (rating_score BETWEEN 1 AND 5), -- e.g., 1 to 5 stars
    comment             TEXT NULL,        -- User's textual feedback
    tags                TEXT[] NULL,      -- Optional tags (e.g., ['Clean', 'Polite', 'Late'])
    -- Visibility & Admin
    is_visible          BOOLEAN DEFAULT TRUE NOT NULL, -- Should the rating/comment be publicly visible?
    admin_notes         TEXT NULL,        -- Internal notes by moderators/admins
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- updated_at is rarely needed for ratings

    CONSTRAINT chk_sr_booking_created_at CHECK (booking_id IS NULL OR booking_created_at IS NOT NULL),
    CONSTRAINT chk_sr_ride_start_time CHECK (ride_id IS NULL OR ride_start_time IS NOT NULL)
);
COMMENT ON TABLE public.support_ratings
    IS '[VoyaGo][Support][Feedback] Stores ratings and comments submitted for drivers, 
        users, bookings, support interactions, etc.';
COMMENT ON COLUMN public.support_ratings.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key (if booking_id is not NULL).';
COMMENT ON COLUMN public.support_ratings.ride_start_time
    IS 'Partition key copied from related ride table (e.g., mm_rides) 
        for composite foreign key (if ride_id is not NULL).';
COMMENT ON COLUMN public.support_ratings.rated_entity_type
    IS 'Specifies the type of entity being rated (e.g., DRIVER, BOOKING, SUPPORT_AGENT).';
COMMENT ON COLUMN public.support_ratings.rated_entity_id
    IS 'The ID (UUID or potentially other format) of the specific entity being rated.';
COMMENT ON COLUMN public.support_ratings.tags
    IS 'Optional tags selected by the rater to categorize feedback aspects.';

-- Indexes for Ratings
CREATE INDEX IF NOT EXISTS idx_ratings_rated_entity
    ON public.support_ratings(rated_entity_type, rated_entity_id, rating_score);
COMMENT ON INDEX public.idx_ratings_rated_entity
    IS '[VoyaGo][Perf] Efficiently retrieves ratings for calculating averages for specific entities.';
CREATE INDEX IF NOT EXISTS idx_ratings_rater ON public.support_ratings(rater_user_id);
-- Index for composite FK lookup to bookings
CREATE INDEX IF NOT EXISTS idx_ratings_booking
    ON public.support_ratings(booking_id, booking_created_at) WHERE booking_id IS NOT NULL;
-- Index for potential composite FK lookup to rides
CREATE INDEX IF NOT EXISTS idx_ratings_ride
    ON public.support_ratings(ride_id, ride_start_time) WHERE ride_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ratings_ticket
    ON public.support_ratings(related_ticket_id) WHERE related_ticket_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_ratings_tags
    ON public.support_ratings USING GIN (tags) WHERE tags IS NOT NULL;


-------------------------------------------------------------------------------
-- 5. Chat Rooms (msg_chats) - ** booking_created_at ADDED **
-- Description: Represents a conversation thread (Booking, Support, or Direct).
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.msg_chats (
    chat_id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Link to context, ensures a chat is specific to one context or is a direct chat
    -- Link to booking (Composite FK defined later). UNIQUE ensures one chat per booking.
    related_booking_id  UUID NULL,
    booking_created_at  TIMESTAMPTZ NULL, -- <<< EKLENEN SÜTUN
    -- Link to support ticket (FK defined later). UNIQUE ensures one chat per ticket.
    related_ticket_id   UUID NULL UNIQUE,
    -- Type of chat
    chat_type           VARCHAR(20) NOT NULL CHECK (chat_type IN ('BOOKING', 'SUPPORT', 'DIRECT')), 
    -- Denormalized timestamp of the last message for sorting/UI optimization
    last_message_at     TIMESTAMPTZ NULL,
    created_at          TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- updated_at useful for tracking when last message was sent
    updated_at          TIMESTAMPTZ NULL,

    -- Ensure chat is linked if not DIRECT type
    CONSTRAINT chk_chat_link CHECK (chat_type = 'DIRECT' 
        OR num_nonnulls(related_booking_id, related_ticket_id) >= 1),
    -- Ensure uniqueness for booking link including partition key
    CONSTRAINT uq_msg_chats_booking UNIQUE (related_booking_id, booking_created_at),
    -- Ensure partition key consistency
    CONSTRAINT chk_chat_booking_created_at CHECK (related_booking_id IS NULL 
        OR booking_created_at IS NOT NULL)

);
COMMENT ON TABLE public.msg_chats
    IS '[VoyaGo][Messaging] Represents conversation threads, linked to bookings, 
        support tickets, or direct messages.';
COMMENT ON COLUMN public.msg_chats.booking_created_at
    IS 'Partition key copied from booking_bookings for composite foreign key 
        (if related_booking_id is not NULL).';
COMMENT ON COLUMN public.msg_chats.last_message_at
    IS 'Denormalized timestamp of the last message sent in this chat, used for sorting chat lists.';
COMMENT ON CONSTRAINT chk_chat_link ON public.msg_chats
    IS 'Ensures non-DIRECT chats are linked to at least one related entity (Booking or Ticket).';
COMMENT ON CONSTRAINT uq_msg_chats_booking ON public.msg_chats
    IS 'Ensures only one chat thread exists per booking instance.';


-- Trigger for updated_at (useful for last_message_at update)
DROP TRIGGER IF EXISTS trg_set_timestamp_on_msg_chats ON public.msg_chats;
CREATE TRIGGER trg_set_timestamp_on_msg_chats
    BEFORE UPDATE ON public.msg_chats
    FOR EACH ROW EXECUTE FUNCTION public.vg_trigger_set_timestamp();

-- Indexes for Chats
-- Add index for composite FK lookup
CREATE INDEX IF NOT EXISTS idx_msg_chats_booking
    ON public.msg_chats(related_booking_id, booking_created_at) WHERE related_booking_id IS NOT NULL;
-- Unique constraint creates index for related_ticket_id
CREATE INDEX IF NOT EXISTS idx_msg_chats_last_message
    ON public.msg_chats(last_message_at DESC NULLS LAST); -- For sorting chats by recent activity


-------------------------------------------------------------------------------
-- 6. Chat Participants (msg_chat_participants)
-- Description: Links users to chat rooms and tracks their status within the chat.
-------------------------------------------------------------------------------
-- (No changes needed in this table definition)
CREATE TABLE IF NOT EXISTS public.msg_chat_participants (
    chat_id         UUID NOT NULL,      -- Link to the chat room (FK defined later, ON DELETE CASCADE)
    user_id         UUID NOT NULL,      -- Link to the user profile (FK defined later, ON DELETE CASCADE)
    joined_at       TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    -- Timestamp when the user last read messages in this chat
    last_read_at    TIMESTAMPTZ NULL,
    -- User-specific flags
    is_blocked      BOOLEAN DEFAULT FALSE NOT NULL, -- Has the user blocked this chat?
    is_archived     BOOLEAN DEFAULT FALSE NOT NULL, -- Has the user archived this chat?
    PRIMARY KEY (chat_id, user_id)
);
COMMENT ON TABLE public.msg_chat_participants
    IS '[VoyaGo][Messaging] Links users to chat rooms 
        and stores user-specific state like last read time.';
COMMENT ON COLUMN public.msg_chat_participants.last_read_at
    IS 'Timestamp indicating the point up to which the user has read messages in this chat.';

-- Indexes for Participants
CREATE INDEX IF NOT EXISTS idx_msg_chat_participants_user
    ON public.msg_chat_participants(user_id, is_archived, last_read_at);


-------------------------------------------------------------------------------
-- 7. Messages (msg_messages)
-- Description: Stores individual messages within chat rooms.
-- Note: Potential candidate for partitioning by sent_at if volume is high.
-------------------------------------------------------------------------------
-- (No changes needed in this table definition)
CREATE TABLE IF NOT EXISTS public.msg_messages (
    message_id          BIGSERIAL PRIMARY KEY,
    -- Chat this message belongs to (FK defined later, ON DELETE CASCADE)
    chat_id             UUID NOT NULL,      
    sender_id           UUID NOT NULL,      -- User who sent the message (FK defined later)
    content_type        VARCHAR(20) DEFAULT 'TEXT' NOT NULL
        CHECK (content_type IN ('TEXT', 'IMAGE', 'FILE', 'LOCATION', 'SYSTEM')), -- Type of message content
    content             TEXT NOT NULL,      -- Text content, or reference (e.g., URL) for non-text types
    -- Metadata for attached files/images
    attachments         JSONB NULL CHECK (attachments IS NULL OR jsonb_typeof(attachments) = 'array'), 
    status              public.message_status DEFAULT 'SENT' NOT NULL, -- Delivery status (ENUM from 001)
    sent_at             TIMESTAMPTZ DEFAULT clock_timestamp() NOT NULL,
    delivered_at        TIMESTAMPTZ NULL,   -- Optional: Timestamp when delivered to recipient(s)
    -- Optional: Timestamp when read by recipient(s) - last_read_at in participants is often preferred
    read_at             TIMESTAMPTZ NULL,   
    reply_to_message_id BIGINT NULL,      -- Link to the message being replied to (FK to self)
    -- Additional message metadata (e.g., system message details)
    metadata            JSONB NULL CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object') 
);
COMMENT ON TABLE public.msg_messages
    IS '[VoyaGo][Messaging] Stores individual messages within chat rooms. 
        Consider partitioning by sent_at for high volume.';
COMMENT ON COLUMN public.msg_messages.content
    IS 'Text content for TEXT type, or a reference 
        (e.g., Storage URL, coordinates) for other types like IMAGE, FILE, LOCATION.';
COMMENT ON COLUMN public.msg_messages.attachments
    IS '[VoyaGo] Array of attachment metadata as JSONB. 
        Example: [{"type": "image", "url": "...", "thumbnail_url": "...", "size_bytes": 10240}]';
COMMENT ON COLUMN public.msg_messages.read_at
    IS 'Timestamp when the message was read. Tracking read status per participant 
        via msg_chat_participants.last_read_at is often more scalable.';

-- Indexes for Messages
CREATE INDEX IF NOT EXISTS idx_msg_messages_chat_time
    ON public.msg_messages(chat_id, sent_at DESC);
COMMENT ON INDEX public.idx_msg_messages_chat_time 
    IS '[VoyaGo][Perf] Essential index for loading chat message history efficiently.';
CREATE INDEX IF NOT EXISTS idx_msg_messages_sender ON public.msg_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_msg_messages_reply
    ON public.msg_messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_gin_msg_messages_attachments
    ON public.msg_messages USING GIN (attachments) WHERE attachments IS NOT NULL;


-- ============================================================================
-- Foreign Key Constraints Placeholder (Standardized Format)
-- ============================================================================
-- Format: Source Table -> Target Table (Source Columns -> Target Columns) [ON DELETE Action?]
-- FKs referencing partitioned tables use composite keys (partition_key, id).
-- --------------------------------------------------------------------------------------------------
-- support_tickets -> core_user_profiles (user_id -> user_id) [RESTRICT?]
-- support_tickets -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [SET NULL] -- COMPOSITE FK
-- support_tickets -> pmt_payments (related_payment_id -> payment_id) [SET NULL]
-- support_tickets -> lkp_support_categories (category_code -> category_code) [SET NULL] 
    -- Need lookup table
-- support_tickets -> core_user_profiles (assigned_agent_id -> user_id) [SET NULL]
--
-- support_ticket_replies -> support_tickets (ticket_id -> ticket_id) [CASCADE]
-- support_ticket_replies -> core_user_profiles (user_id -> user_id) [RESTRICT? SET NULL?]
--
-- support_user_reports -> core_user_profiles (reporter_user_id -> user_id) [CASCADE?]
-- support_user_reports -> booking_bookings (booking_created_at, related_booking_id -> created_at, booking_id) 
    --[SET NULL] -- COMPOSITE FK
-- support_user_reports -> mm_rides (ride_start_time, related_ride_id -> start_time, ride_id) [SET NULL] 
    -- COMPOSITE FK (Example for mm_rides)
-- support_user_reports -> ??? (related_ride_id -> other ride tables?) [Polymorphic]
-- support_user_reports -> lkp_report_reasons (reason_code -> reason_code) [SET NULL] 
    -- Need lookup table
-- support_user_reports -> core_user_profiles (resolved_by_user_id -> user_id) [SET NULL]
-- Note: FK for reported_entity_id depends on reported_entity_type.
--
-- support_ratings -> booking_bookings (booking_created_at, booking_id -> 
    --created_at, booking_id) [SET NULL?] -- COMPOSITE FK
-- support_ratings -> mm_rides (ride_start_time, ride_id -> start_time, ride_id) [SET NULL?]
    -- COMPOSITE FK (Example for mm_rides)
-- support_ratings -> ??? (ride_id -> other ride tables?) [Polymorphic]
-- support_ratings -> support_tickets (related_ticket_id -> ticket_id) [SET NULL?]
-- support_ratings -> core_user_profiles (rater_user_id -> user_id) [CASCADE?]
-- Note: FK for rated_entity_id depends on rated_entity_type.
--
-- msg_chats -> booking_bookings (booking_created_at, related_booking_id -> 
    --created_at, booking_id) [CASCADE?] -- COMPOSITE FK
-- msg_chats -> support_tickets (related_ticket_id -> ticket_id) [CASCADE?]
--
-- msg_chat_participants -> msg_chats (chat_id -> chat_id) [CASCADE]
-- msg_chat_participants -> core_user_profiles (user_id -> user_id) [CASCADE]
--
-- msg_messages -> msg_chats (chat_id -> chat_id) [CASCADE]
-- msg_messages -> core_user_profiles (sender_id -> user_id) [RESTRICT? SET NULL?]
-- msg_messages -> msg_messages (reply_to_message_id -> message_id) [SET NULL]
-- ============================================================================


COMMIT;

-- ============================================================================
-- End of Migration: 018_support_messaging.sql (Version 1.1)
-- ============================================================================
