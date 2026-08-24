# Schema conventions: polymorphic bullets, audit tables, denormalized tenant id

Designing the Postgres schema (Supabase, per ADR-0002) for the domain model in `CONTEXT.md` — Bullet/Task/Event/Note, Day/Month scope, migration, habit tracker — raised several real forks, each considered and resolved deliberately:

**One polymorphic `bullets` table**, not one table per type. Task/Event/Note share the same core fields (scope, month, date, text), and the Daily Log query mixes all three constantly — a single table keeps that a one-clause `WHERE`, not a `UNION` across type tables. Only tasks get a nullable `status` column for their lifecycle.

**A separate `task_migrations` audit table** (task_id, from_month, to_month, migrated_at), not a JSONB history array on the bullet row. Migration history is meant to be queried (the domain model explicitly treats migration count as a signal to reconsider a task) — a real table supports that with a plain indexed `COUNT(*)`; a JSONB array would need unpacking on every read.

**Existence-based `habit_checks`** — a row means "done," delete to undo — instead of a boolean column that would need pre-populated rows for every habit×day whether checked or not.

**`user_id` denormalized onto every table**, including child tables (`task_migrations`, `monthly_habit_selection`, `habit_checks`), so every RLS policy is a direct `user_id = auth.uid()` check with no join. This follows Supabase's own documented guidance that joins/subqueries inside RLS policies are a real, measured performance cost ([RLS Performance and Best Practices](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv), [Performance and Security Advisors](https://supabase.com/docs/guides/database/database-advisors?queryGroups=lint&lint=0003_auth_rls_initplan)). The cost is one extra indexed column per table, set once at insert and never mutated — not the usual risk profile of denormalized data.

**Scope encoding**: every bullet has `scope` (day/month), a `month` column (first-of-month `date`, populated even for day-scoped rows so migration-boundary queries are a plain `WHERE month = X`), and a `date` column required when day-scoped and optional when month-scoped (the day-anchor). This makes "Daily Log for date X" a single `WHERE date = X` regardless of scope. Months are a real `date`, not `'YYYY-MM'` text, so range queries and month arithmetic use native date operations.

All constraints and RLS tenant isolation were verified by running the resulting migration (`supabase/migrations/0001_initial_schema.sql`) against a real local Postgres — including confirming two different tenants only ever see their own rows, and an unauthenticated session sees none — not just reviewed by eye.
