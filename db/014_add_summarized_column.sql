-- 014: Add `summarized` tracking column to call_logs
--
-- Migration 013 assumed a pgvector-based `memories` schema that was never
-- actually enabled (pgvector extension isn't available on this DB). The
-- `memories` table in production has a simpler, embedding-free schema
-- (type/active/source_call_log_id/times_referenced) that was created by hand
-- instead. This migration just adds the one column consolidation still needs
-- to track which calls have already been processed.

alter table public.call_logs
  add column if not exists summarized boolean not null default false;
