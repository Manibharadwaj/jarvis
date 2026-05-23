-- 009: Add call_type, room_name, identity_verified to call_logs for call event tracking
-- The call_logs table exists from migration 001 but is never written to.
-- These columns let the agent log call start/end and the app read call history.

ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS call_type text;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS room_name text;
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS identity_verified boolean DEFAULT false;

-- Add 'access_denied' to the call_status enum if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid
                 WHERE t.typname = 'call_status' AND e.enumlabel = 'access_denied') THEN
    ALTER TYPE public.call_status ADD VALUE 'access_denied';
  END IF;
END$$;

-- Add 'disconnected' to the call_status enum if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON e.enumtypid = t.oid
                 WHERE t.typname = 'call_status' AND e.enumlabel = 'disconnected') THEN
    ALTER TYPE public.call_status ADD VALUE 'disconnected';
  END IF;
END$$;

-- Indexes for call history queries
CREATE INDEX IF NOT EXISTS idx_call_logs_call_type ON public.call_logs(call_type);
CREATE INDEX IF NOT EXISTS idx_call_logs_started_at ON public.call_logs(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_logs_room_name ON public.call_logs(room_name);