-- 012: Widen call_queue.status CHECK constraint
--
-- The constraint added in 006_accountability.sql only allows
-- ('sent', 'answered', 'missed', 'cancelled'), but the application code
-- (server.js, on call end) also writes 'ended' (via statusMap), and the
-- agent's call-end path can write 'connected', 'disconnected', and
-- 'access_denied'. This produced repeated:
--   "new row for relation 'call_queue' violates check constraint
--    'call_queue_status_check'"
-- in logs/backend-error.log on every call end.
--
-- Drop the old constraint and re-add it with the full set the code uses.
-- Already-applied migrations are immutable by convention, so this lives
-- in a new file (db/012_*.sql) and db/run_migration.js picks it up.

ALTER TABLE public.call_queue
  DROP CONSTRAINT IF EXISTS call_queue_status_check;

ALTER TABLE public.call_queue
  ADD CONSTRAINT call_queue_status_check
  CHECK (status IN (
    'sent',
    'answered',
    'missed',
    'cancelled',
    'ended',
    'disconnected',
    'access_denied',
    'connected'
  ));
