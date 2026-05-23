-- 008: Update call_queue constraint to support new call types
-- Old: wakeup, checkin, evening, manual
-- New: wakeup, checkin-morning, checkin-midday, checkin-afternoon, evening, night, manual

ALTER TABLE public.call_queue DROP CONSTRAINT call_queue_call_type_check;
ALTER TABLE public.call_queue ADD CONSTRAINT call_queue_call_type_check
  CHECK (call_type IN ('wakeup', 'checkin-morning', 'checkin-midday', 'checkin-afternoon', 'evening', 'night', 'manual'));