-- Fix profile
update public.profiles set
  name = 'Mani Bharadwaj',
  passphrase = 'I am Tony Stark',
  timezone = 'Asia/Kolkata',
  wake_hour = 5,
  sleep_hour = 23,
  phone = '+91-XXXXXXXXXX'
where name = '' or name is null;

-- Remove auto-seeded defaults (from trigger), keep custom schedules
delete from public.schedules where purpose in ('morning_routine', 'evening_review');
