-- Jarvis Accountability System — Migration 006
-- Run this in Supabase SQL Editor after 005_daily_tasks.sql

-- 1. Daily metrics log (5 tracked metrics + day score)
create table if not exists public.daily_log (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  date              date not null,
  -- Food: 3000 cal pure veg target
  food_calories     int,
  food_notes        text,
  -- Gym: daily + Sunday sport + protein/creatine
  gym_done          boolean not null default false,
  gym_notes         text,
  gym_protein       boolean not null default false,
  gym_creatine      boolean not null default false,
  -- Code: 6:30-10:30 PM sessions
  code_done         boolean not null default false,
  code_start_time   time,
  code_end_time     time,
  code_notes        text,
  -- Office: 9:30 AM - 6:30 PM
  office_in_time    time,
  office_out_time   time,
  -- Books: what/pages/insights
  books_title       text,
  books_pages       int,
  books_insights    text,
  -- End-of-day score
  day_score         int check (day_score between 1 and 10),
  day_notes         text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique(user_id, date)
);

-- 2. Call queue — scheduled calls with retry tracking
create table if not exists public.call_queue (
  id              uuid primary key default gen_random_uuid(),
  call_type       text not null check (call_type in ('wakeup', 'checkin', 'evening', 'manual')),
  scheduled_at    timestamptz not null,
  status          text not null default 'sent' check (status in ('sent', 'answered', 'missed', 'cancelled')),
  room_name       text unique,
  answered_at     timestamptz,
  call_log_id     uuid references public.call_logs(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 3. Master schedule — day's tasks created during wakeup call
create table if not exists public.master_schedule (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  date              date not null,
  time_slot         text,
  title             text not null,
  category          text check (category in ('work', 'code', 'gym', 'food', 'books', 'personal', 'other')),
  done              boolean not null default false,
  skipped           boolean not null default false,
  skip_reason       text,
  rescheduled_to    date,
  source_call_id    uuid references public.call_logs(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

-- 4. Discussion log — morning topic discussions
create table if not exists public.discussion_log (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  date        date not null,
  topic       text not null,
  summary     text,
  call_log_id uuid references public.call_logs(id) on delete set null,
  created_at  timestamptz not null default now()
);

-- Indexes
create index if not exists idx_daily_log_user   on public.daily_log(user_id, date desc);
create index if not exists idx_call_queue_type  on public.call_queue(call_type, created_at desc);
create index if not exists idx_call_queue_room  on public.call_queue(room_name);
create index if not exists idx_master_schedule_user on public.master_schedule(user_id, date desc);
create index if not exists idx_master_schedule_date on public.master_schedule(date, done);
create index if not exists idx_discussion_log_user  on public.discussion_log(user_id, date desc);

-- Updated_at triggers
create trigger trg_daily_log_updated_at
  before update on public.daily_log for each row execute function public.set_updated_at();

create trigger trg_call_queue_updated_at
  before update on public.call_queue for each row execute function public.set_updated_at();

create trigger trg_master_schedule_updated_at
  before update on public.master_schedule for each row execute function public.set_updated_at();

-- RLS
alter table public.daily_log         enable row level security;
alter table public.master_schedule    enable row level security;
alter table public.discussion_log     enable row level security;
-- call_queue is server-managed (no RLS — accessed via postgres owner credentials)

create policy "Users own their daily log"
  on public.daily_log for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their master schedule"
  on public.master_schedule for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their discussion log"
  on public.discussion_log for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
