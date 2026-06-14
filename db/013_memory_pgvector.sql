-- 013: Persistent Memory — pgvector + memories table
--
-- Enables cross-call memory for Jarvis:
--   1. Activate pgvector extension
--   2. Create `memories` table for vector-searchable episodic memory
--   3. Add embedding columns to call_transcripts and call_logs
--   4. Add `summarized` flag to call_logs for consolidation tracking
--   5. Indexes and RLS for the new table
--
-- The existing `user_context` table (key-value store) stays as-is;
-- the memory code will now read/write it alongside the new `memories` table.

-- 1. Enable pgvector
create extension if not exists vector;

-- 2. Memories table — vector-searchable episodic/semantic/preference memory
create table if not exists public.memories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  call_log_id uuid references public.call_logs(id) on delete set null,
  content     text not null,
  memory_type text not null default 'episodic'
              check (memory_type in ('episodic', 'semantic', 'preference')),
  importance  int not null default 3 check (importance between 1 and 5),
  embedding   vector(768),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 3. Add embedding column to call_transcripts (schema comment already planned this)
alter table public.call_transcripts
  add column if not exists embedding vector(768);

-- 4. Add embedding metadata to call_logs
alter table public.call_logs
  add column if not exists embedding_model text;

alter table public.call_logs
  add column if not exists summarized boolean not null default false;

-- 5. Indexes
create index if not exists idx_memories_user
  on public.memories(user_id);

create index if not exists idx_memories_type
  on public.memories(memory_type);

-- IVFFlat index for cosine similarity search on memories
-- (requires rows to exist first for training; created deferred so empty tables don't error)
create index if not exists idx_memories_vector
  on public.memories using ivfflat (embedding vector_cosine_ops) with (lists = 100);

-- IVFFlat index on call_transcripts embedding
create index if not exists idx_transcripts_vector
  on public.call_transcripts using ivfflat (embedding vector_cosine_ops) with (lists = 100);

-- 6. Row Level Security
alter table public.memories enable row level security;

create policy "Users own their memories"
  on public.memories for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 7. Auto-update trigger for memories.updated_at
create trigger trg_memories_updated_at
  before update on public.memories for each row
  execute function public.set_updated_at();