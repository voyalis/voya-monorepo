-- Migration to create the 'messages' table
BEGIN;

CREATE TABLE IF NOT EXISTS public.messages (
    id uuid NOT NULL DEFAULT uuid_generate_v4(),
    text text NOT NULL,
    "createdAt" timestamp NOT NULL DEFAULT now(),
    CONSTRAINT "PK_messages_id" PRIMARY KEY (id)
);

COMMENT ON TABLE public.messages IS '[VoyaGo][App] Stores simple messages for testing purposes.';

COMMIT;
