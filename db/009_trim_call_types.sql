-- 009: Trim call types — keep only wakeup, night, jarvis, manual
-- Removed: checkin-morning, checkin-midday, checkin-afternoon, evening

ALTER TABLE public.call_queue DROP CONSTRAINT call_queue_call_type_check;
ALTER TABLE public.call_queue ADD CONSTRAINT call_queue_call_type_check
  CHECK (call_type IN ('wakeup', 'night', 'jarvis', 'manual'));