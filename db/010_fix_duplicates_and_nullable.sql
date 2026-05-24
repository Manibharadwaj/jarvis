-- Migration 010: Fix duplicate tasks + nullable gym booleans + day-of-week filtering
-- Run after 009_call_events.sql

-- 1. Remove duplicate daily_tasks that overlap between migration 005 and 007
-- Keep the 007 versions (Gym Workout, Protein Shake, Creatine, Code Session, Reading, Office)
-- Remove the 005 versions that duplicate them
DELETE FROM public.daily_tasks
WHERE title IN (
  'Hit the gym',          -- replaced by "Gym Workout"
  'Take protein',         -- replaced by "Protein Shake"
  'Code session (2+ hours)', -- replaced by "Code Session"
  'Read 10 pages',        -- replaced by "Reading"
  'Reach office by 9:20 AM' -- replaced by "Office"
);

-- 2. Make gym/code boolean fields nullable so NULL = "not yet asked", false = "explicitly no"
-- This fixes the issue where gym_done defaults to false even when never asked
ALTER TABLE public.daily_log ALTER COLUMN gym_done DROP NOT NULL;
ALTER TABLE public.daily_log ALTER COLUMN gym_done DROP DEFAULT;
ALTER TABLE public.daily_log ALTER COLUMN gym_protein DROP NOT NULL;
ALTER TABLE public.daily_log ALTER COLUMN gym_protein DROP DEFAULT;
ALTER TABLE public.daily_log ALTER COLUMN gym_creatine DROP NOT NULL;
ALTER TABLE public.daily_log ALTER COLUMN gym_creatine DROP DEFAULT;
ALTER TABLE public.daily_log ALTER COLUMN code_done DROP NOT NULL;
ALTER TABLE public.daily_log ALTER COLUMN code_done DROP DEFAULT;

-- Set existing false values to NULL where they were never explicitly set
-- (We can't distinguish, but going forward NULL means "not asked")
UPDATE public.daily_log SET gym_done = NULL WHERE gym_done = false;
UPDATE public.daily_log SET gym_protein = NULL WHERE gym_protein = false;
UPDATE public.daily_log SET gym_creatine = NULL WHERE gym_creatine = false;
UPDATE public.daily_log SET code_done = NULL WHERE code_done = false;

-- 3. Add day_filter column to daily_tasks for day-of-week scheduling
-- NULL = every day, 'sunday' = only Sunday, 'weekday' = Mon-Sat
ALTER TABLE public.daily_tasks ADD COLUMN IF NOT EXISTS day_filter text
  check (day_filter is null or day_filter in ('sunday', 'weekday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'));

-- Set day filters for gym-related tasks
UPDATE public.daily_tasks SET day_filter = 'weekday' WHERE title = 'Gym Workout';
UPDATE public.daily_tasks SET day_filter = 'weekday' WHERE title = 'Protein Shake';
UPDATE public.daily_tasks SET day_filter = 'weekday' WHERE title = 'Creatine';
UPDATE public.daily_tasks SET day_filter = 'sunday' WHERE title = 'Sunday Sport';

-- Clean up any leftover duplicate tasks in master_schedule for today
DELETE FROM public.master_schedule a USING public.master_schedule b
WHERE a.id > b.id
  AND a.user_id = b.user_id
  AND a.date = b.date
  AND a.title = b.title;