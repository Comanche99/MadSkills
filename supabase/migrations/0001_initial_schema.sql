-- Initial schema for the BuJo SaaS app.
-- Resolves wayfinder ticket "Data model / schema" (issue #7).
-- See CONTEXT.md for the domain model this schema implements, and
-- docs/adr/0002-nextjs-supabase-stack-rls-tenant-isolation.md and
-- docs/adr/0003-schema-conventions.md for the decisions behind its shape.

-- ============================================================
-- bullets: the single polymorphic table for Task / Event / Note
-- ============================================================
create table public.bullets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,

  type text not null check (type in ('task', 'event', 'note')),
  text text not null,

  -- scope + month + date together encode where a bullet lives:
  --   day-scoped:   date is the bullet's day (required); month is that day's month.
  --   month-scoped: date is the optional day-anchor (mirrors into that day's Daily
  --                 Log when set); month is the month it belongs to.
  -- Daily Log for a date is simply `where date = :date`, regardless of scope.
  scope text not null check (scope in ('day', 'month')),
  month date not null,
  date date,
  constraint bullets_date_required_when_day_scoped
    check (scope = 'month' or date is not null),

  -- task lifecycle; null for event/note
  status text check (status in ('open', 'complete', 'cancelled')),
  constraint bullets_status_only_for_tasks
    check ((type = 'task') = (status is not null)),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index bullets_daily_log_idx on public.bullets (user_id, date);
create index bullets_monthly_log_idx on public.bullets (user_id, scope, month);
create index bullets_migration_candidates_idx on public.bullets (user_id, type, status, month);

alter table public.bullets enable row level security;
create policy "own bullets" on public.bullets
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- task_migrations: audit trail of a task's month-to-month moves
-- ============================================================
create table public.task_migrations (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.bullets(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  from_month date not null,
  to_month date not null,
  migrated_at timestamptz not null default now()
);

create index task_migrations_task_idx on public.task_migrations (task_id);

alter table public.task_migrations enable row level security;
create policy "own task_migrations" on public.task_migrations
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- habits: persistent habit definitions
-- ============================================================
create table public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.habits enable row level security;
create policy "own habits" on public.habits
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- monthly_habit_selection: which habits are tracked in a given month
-- ============================================================
create table public.monthly_habit_selection (
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  month date not null,
  primary key (habit_id, month)
);

create index monthly_habit_selection_user_month_idx on public.monthly_habit_selection (user_id, month);

alter table public.monthly_habit_selection enable row level security;
create policy "own monthly_habit_selection" on public.monthly_habit_selection
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============================================================
-- habit_checks: existence-based daily habit completion
-- a row means "done" for that habit on that date; delete to undo
-- ============================================================
create table public.habit_checks (
  habit_id uuid not null references public.habits(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  primary key (habit_id, date)
);

create index habit_checks_user_date_idx on public.habit_checks (user_id, date);

alter table public.habit_checks enable row level security;
create policy "own habit_checks" on public.habit_checks
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
