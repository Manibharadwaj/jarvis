-- ============================================================
-- Jarvis - AI Accountability Companion
-- Database Schema for Supabase (PostgreSQL + pgvector)
-- ============================================================

-- 0. Extensions
-- Enable these from Supabase Dashboard → Database → Extensions:
--   - pgcrypto (usually enabled by default)
--   - vector   (search "vector", enable it)
-- Or run in Supabase SQL Editor:
--   create extension if not exists "pgcrypto";
--   create extension if not exists "vector";

-- 1. Profiles (extends Supabase auth.users)
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  name          text not null default '',
  passphrase    text not null default 'I am Tony Stark',
  timezone      text not null default 'UTC',
  wake_hour     int  not null default 7 check (wake_hour between 0 and 23),
  sleep_hour    int  not null default 23 check (sleep_hour between 0 and 23),
  phone         text,
  avatar_url    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- 2. Schedules (routine calls)
create table if not exists public.schedules (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  title           text not null,
  cron_expr       text not null,
  purpose         text not null default 'check-in',
  prompt_template text,
  active          boolean not null default true,
  last_run_at     timestamptz,
  next_run_at     timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- 3. Call Logs
create type call_status as enum ('ringing', 'missed', 'connected', 'ended', 'failed');

create table if not exists public.call_logs (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references public.profiles(id) on delete cascade,
  schedule_id      uuid references public.schedules(id) on delete set null,
  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  duration_seconds int,
  status           call_status not null default 'ringing',
  summary          text,
  mood             text,
  created_at       timestamptz not null default now()
);

-- 4. Call Transcripts
create table if not exists public.call_transcripts (
  id          uuid primary key default gen_random_uuid(),
  call_log_id uuid not null references public.call_logs(id) on delete cascade,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null,
  created_at  timestamptz not null default now()
);
-- Note: Add embedding column after enabling pgvector:
--   alter table public.call_transcripts add column embedding vector(768);

-- 5. Tasks / Action Items
create type task_priority as enum ('low', 'medium', 'high', 'critical');
create type task_status  as enum ('pending', 'in_progress', 'completed', 'cancelled');

create table if not exists public.tasks (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  title          text not null,
  description    text,
  priority       task_priority not null default 'medium',
  status         task_status not null default 'pending',
  due_date       timestamptz,
  completed_at   timestamptz,
  source_call_id uuid references public.call_logs(id) on delete set null,
  tags           text[] default '{}',
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- 6. Reminders
create table if not exists public.reminders (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles(id) on delete cascade,
  task_id           uuid references public.tasks(id) on delete cascade,
  title             text not null,
  message           text not null,
  remind_at         timestamptz not null,
  notified          boolean not null default false,
  repeat_interval   interval,
  source_call_id    uuid references public.call_logs(id) on delete set null,
  created_at        timestamptz not null default now()
);

-- 7. Daily Summaries
create table if not exists public.daily_summaries (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  date            date not null,
  summary_text    text not null,
  key_points      text[] default '{}',
  mood_trend      text,
  tasks_completed int not null default 0,
  tasks_created   int not null default 0,
  call_count      int not null default 0,
  created_at      timestamptz not null default now(),
  unique(user_id, date)
);
-- Note: Add embedding column after enabling pgvector:
--   alter table public.daily_summaries add column embedding vector(768);

-- 8. User Context (persistent memory store)
create table if not exists public.user_context (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references public.profiles(id) on delete cascade,
  key            text not null,
  value          text not null,
  source_call_id uuid references public.call_logs(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique(user_id, key)
);

-- ============================================================
-- INDEXES
-- ============================================================

create index idx_schedules_user     on public.schedules(user_id);
create index idx_schedules_next_run on public.schedules(next_run_at) where active = true;

create index idx_call_logs_user     on public.call_logs(user_id);
create index idx_call_logs_started  on public.call_logs(started_at desc);
create index idx_call_logs_status   on public.call_logs(status);

create index idx_transcripts_call   on public.call_transcripts(call_log_id);
-- Add after enabling pgvector:
-- create index idx_transcripts_vector on public.call_transcripts using ivfflat (embedding vector_cosine_ops) with (lists = 100);

create index idx_tasks_user         on public.tasks(user_id);
create index idx_tasks_status       on public.tasks(status);
create index idx_tasks_due          on public.tasks(due_date) where status != 'completed';

create index idx_reminders_user     on public.reminders(user_id);
create index idx_reminders_at       on public.reminders(remind_at) where notified = false;

create index idx_summaries_user     on public.daily_summaries(user_id);
create index idx_summaries_date     on public.daily_summaries(date desc);

create index idx_context_user       on public.user_context(user_id);

-- ============================================================
-- TRIGGER: auto-update updated_at
-- ============================================================

create or replace function public.set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_profiles_updated_at
  before update on public.profiles for each row execute function public.set_updated_at();

create trigger trg_schedules_updated_at
  before update on public.schedules for each row execute function public.set_updated_at();

create trigger trg_tasks_updated_at
  before update on public.tasks for each row execute function public.set_updated_at();

create trigger trg_user_context_updated_at
  before update on public.user_context for each row execute function public.set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.profiles          enable row level security;
alter table public.schedules         enable row level security;
alter table public.call_logs         enable row level security;
alter table public.call_transcripts  enable row level security;
alter table public.tasks             enable row level security;
alter table public.reminders         enable row level security;
alter table public.daily_summaries   enable row level security;
alter table public.user_context      enable row level security;

-- Users can only access their own data
create policy "Users own their profile"
  on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);

create policy "Users own their schedules"
  on public.schedules for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their call logs"
  on public.call_logs for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their transcripts"
  on public.call_transcripts for all
  using (exists (select 1 from public.call_logs where call_logs.id = call_transcripts.call_log_id and call_logs.user_id = auth.uid()));

create policy "Users own their tasks"
  on public.tasks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their reminders"
  on public.reminders for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their summaries"
  on public.daily_summaries for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "Users own their context"
  on public.user_context for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

-- Seed default schedules for a new user
create or replace function public.seed_default_schedules(p_user_id uuid)
returns void as $$
begin
  insert into public.schedules (user_id, title, cron_expr, purpose, prompt_template) values
    (p_user_id, 'Morning Check-in', '0 8 * * *', 'morning_routine',
     'Good morning. Let us review your plan for today.'),
    (p_user_id, 'Evening Review', '0 22 * * *', 'evening_review',
     'Good evening. Let us review how your day went.');
end;
$$ language plpgsql;

-- On new profile creation, auto-seed schedules
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name) values (new.id, '');
  perform public.seed_default_schedules(new.id);
  return new;
end;
$$ language plpgsql;

-- Trigger: auto-create profile when auth user signs up
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- End of schema
-- ============================================================
