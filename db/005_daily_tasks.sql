-- Daily Must-Do Tasks — Jarvis checks these every call and scores against them

create table if not exists public.daily_tasks (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  title           text not null,
  description     text,
  category        text not null check (category in ('gym', 'food', 'work', 'spiritual', 'habits', 'growth', 'bonus')),
  default_daily   boolean not null default true,
  schedule_window text not null check (schedule_window in ('early_morning', 'morning', 'afternoon', 'evening', 'night')),
  target_time     time,
  target_value    numeric,
  target_unit     text,
  sort_order      int not null default 0,
  active          boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

alter table public.daily_tasks enable row level security;

create policy "Users own their daily tasks"
  on public.daily_tasks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create index idx_daily_tasks_user  on public.daily_tasks(user_id);
create index idx_daily_tasks_window on public.daily_tasks(schedule_window) where active = true;

create trigger trg_daily_tasks_updated_at
  before update on public.daily_tasks for each row execute function public.set_updated_at();

-- Seed Mani's daily must-do tasks
with user_ref as (
  select id from auth.users where email = 'mani@jarvis.ai'
)
insert into public.daily_tasks (user_id, title, description, category, schedule_window, target_time, target_value, target_unit, sort_order)
select
  (select id from user_ref),
  title, description, category, schedule_window, target_time, target_value, target_unit, sort_order
from (values
  -- EARLY MORNING (wake up ~ 5 AM routine)
  ('Wake up on time',           'Wake up at 5 AM without snoozing',                   'habits',    'early_morning', '05:00'::time, null,   null,       10),
  ('Hit the gym',               'Complete full workout session',                      'gym',       'early_morning', null,           null,   null,       20),
  ('Take protein',              'Post-workout protein shake',                         'food',      'early_morning', null,           1,     'servings', 25),
  ('Consume 700 calories',      'Reach 700 calorie intake before 9 AM',               'food',      'early_morning', '09:00'::time, 700,   'calories', 30),
  ('Do puja',                   'Morning spiritual practice',                         'spiritual', 'early_morning', null,           null,   null,       35),

  -- MORNING (post-gym, pre-office)
  ('Reach office by 9:20 AM',   'Be in office before the target time',                'work',      'morning',       '09:20'::time, null,   null,       40),
  ('Plan the day',              'Review today''s plan with Jarvis',                   'habits',    'morning',       null,           null,   null,       45),

  -- AFTERNOON
  ('Eat a balanced lunch',      'Healthy lunch with proper nutrition',                'food',      'afternoon',     null,           null,   null,       50),
  ('Complete morning tasks',    'Finish at least 3 major tasks from morning plan',    'work',      'afternoon',     null,           3,     'tasks',    55),

  -- EVENING
  ('Code session (2+ hours)',   'Dedicated coding time for projects',                 'growth',    'evening',       null,           120,   'minutes',  60),
  ('Hydrate (8+ glasses)',      'Drink enough water throughout the day',              'habits',    'evening',       null,           8,     'glasses',  65),

  -- NIGHT
  ('Night review with Jarvis',  'End-of-day review and scoring',                      'habits',    'night',         '22:00'::time, null,   null,       70),
  ('Plan tomorrow',             'Set 2-3 key tasks for the next day',                 'habits',    'night',         null,           2,     'tasks',    75),
  ('Sleep by 11 PM',            'In bed by 11 PM for 6 hours of sleep',               'habits',    'night',         '23:00'::time, null,   null,       80),

  -- BONUS (flexible, user can opt in)
  ('Read 10 pages',             'Read 10 pages of a book (any topic)',                 'growth',    'evening',       null,           10,    'pages',   200),
  ('No phone 30 min after wake','Avoid scrolling after wake-up',                      'habits',    'early_morning', null,           30,    'minutes',  205)
) as t(title, description, category, schedule_window, target_time, target_value, target_unit, sort_order)
where not exists (
  select 1 from public.daily_tasks dt
  where dt.user_id = (select id from user_ref) and dt.title = t.title
);
