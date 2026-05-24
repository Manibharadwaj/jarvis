-- 011: Chat support — add medium column, expand call_transcripts

-- Add medium column to call_logs to distinguish voice vs text
ALTER TABLE public.call_logs ADD COLUMN IF NOT EXISTS medium text NOT NULL DEFAULT 'voice'
  CHECK (medium IN ('voice', 'text'));

-- Add call_type and room_name columns if missing (from 009, safe to re-run)
-- (skipped — 009 already added these, and migration 009 has been applied)

-- Expand call_transcripts role constraint to support tool messages
ALTER TABLE public.call_transcripts DROP CONSTRAINT IF EXISTS call_transcripts_role_check;
ALTER TABLE public.call_transcripts ADD CONSTRAINT call_transcripts_role_check
  CHECK (role IN ('user', 'assistant', 'tool', 'system'));

-- Add tool call metadata columns
ALTER TABLE public.call_transcripts ADD COLUMN IF NOT EXISTS tool_call_id text;
ALTER TABLE public.call_transcripts ADD COLUMN IF NOT EXISTS tool_name text;

-- Index for loading conversation history by call_log_id in order
CREATE INDEX IF NOT EXISTS idx_transcripts_call_log_id_created
  ON public.call_transcripts(call_log_id, created_at);