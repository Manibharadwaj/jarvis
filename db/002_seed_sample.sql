-- ============================================================
-- Jarvis - Sample Seed Data
-- Run this AFTER 001_schema.sql to test with demo data
-- ============================================================

-- This is meant to be run after a real user is created via auth
-- It shows the structure of what gets inserted

-- Sample schedule entries (seeded automatically for new users):
-- insert into public.schedules (user_id, title, cron_expr, purpose, prompt_template)
-- values
--   ('<USER_UUID>', 'Morning Check-in',    '0 8 * * *',  'morning_routine',
--    'Good morning. Let us review your plan for today.'),
--   ('<USER_UUID>', 'Evening Review',      '0 22 * * *', 'evening_review',
--    'Good evening. Let us review how your day went.'),
--   ('<USER_UUID>', 'Mid-day Pulse',       '0 14 * * *', 'check-in',
--    'Checking in. How is your day progressing?'),
--   ('<USER_UUID>', 'Weekend Reflection',  '0 10 * * 6', 'weekly_review',
--    'Weekend review. Let us look back at this week.');

-- Sample call log entry:
-- insert into public.call_logs (user_id, schedule_id, started_at, ended_at, duration_seconds, status, summary)
-- values (
--   '<USER_UUID>', '<SCHEDULE_UUID>',
--   now() - interval '2 hours',
--   now() - interval '1 hour',
--   3600,
--   'connected',
--   'Morning check-in. User planned to work on project X and call John.'
-- );

-- Sample task:
-- insert into public.tasks (user_id, title, description, priority, status, due_date, tags)
-- values (
--   '<USER_UUID>',
--   'Call John about project',
--   'Discuss the timeline for the new feature rollout',
--   'high',
--   'pending',
--   now() + interval '1 day',
--   array['work', 'follow-up']
-- );

-- Sample reminder:
-- insert into public.reminders (user_id, task_id, title, message, remind_at)
-- values (
--   '<USER_UUID>', '<TASK_UUID>',
--   'Call John reminder',
--   'Hey, remember to call John about the project timeline.',
--   now() + interval '1 day' - interval '1 hour'
-- );

-- Sample context entries:
-- insert into public.user_context (user_id, key, value) values
--   ('<USER_UUID>', 'user_name', 'Tony'),
--   ('<USER_UUID>', 'job_role', 'Engineer'),
--   ('<USER_UUID>', 'important_note', 'Always remind about morning standup at 9 AM');

-- Sample daily summary:
-- insert into public.daily_summaries (user_id, date, summary_text, key_points, tasks_completed, tasks_created, call_count)
-- values (
--   '<USER_UUID>',
--   current_date,
--   'Productive day. Morning check-in was on time. Completed project X research.',
--   array['Completed project X research', 'Scheduled meeting with John', 'Morning check-in done'],
--   2, 1, 1
-- );
