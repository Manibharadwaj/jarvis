-- Master daily routine for Mani Stark
-- These are the 5 pillars + daily non-negotiables

-- Get the user ID (assumes single user)
-- Insert default daily tasks for the 5 pillars

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Gym Workout'::text,
    'Hit the gym. No excuses. Sundays = sport instead.'::text,
    'gym'::text,
    true,
    'morning'::text,
    '06:00'::time,
    NULL,
    NULL,
    1,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Protein Shake'::text,
    'Mandatory protein shake after gym.'::text,
    'gym'::text,
    true,
    'morning'::text,
    '07:30'::time,
    NULL,
    NULL,
    2,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Creatine'::text,
    'Daily creatine supplement.'::text,
    'gym'::text,
    true,
    'morning'::text,
    '07:30'::time,
    NULL,
    NULL,
    3,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Food — 3000 cal pure veg'::text,
    'Track all meals. Target 3000 calories, pure vegetarian.'::text,
    'food'::text,
    true,
    'afternoon'::text,
    NULL,
    3000,
    'calories'::text,
    4,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Office'::text,
    '9:30 AM to 6:30 PM. Track in and out times.'::text,
    'work'::text,
    true,
    'morning'::text,
    '09:30'::time,
    NULL,
    NULL,
    5,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Code Session'::text,
    '6:30 PM to 10:30 PM. Deep work coding.'::text,
    'growth'::text,
    true,
    'evening'::text,
    '18:30'::time,
    NULL,
    NULL,
    6,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Reading'::text,
    'Read a book. Track title, pages, and key insight.'::text,
    'growth'::text,
    true,
    'night'::text,
    '22:00'::time,
    NULL,
    NULL,
    7,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);

-- Sunday sport task (will be filtered by agent on Sundays)
INSERT INTO daily_tasks (user_id, title, description, category, default_daily, schedule_window, target_time, target_value, target_unit, sort_order, active)
SELECT
    id,
    'Sunday Sport'::text,
    'Sundays: play a sport instead of gym.'::text,
    'gym'::text,
    true,
    'morning'::text,
    '07:00'::time,
    NULL,
    NULL,
    8,
    true
FROM profiles WHERE id = (SELECT id FROM profiles LIMIT 1);