# BuJo SaaS

A bullet-journal-style journaling web app: rapid logging of tasks, events, and notes, organized into daily and monthly logs, with the bullet journal method's migration ritual and a habit tracker.

## Language

**Bullet**:
A single logged entry. Every bullet has a type, fixed at creation: Task, Event, or Note.

**Task**:
A bullet representing an actionable item. Lifecycle: `Open → Complete`, `Open → Cancelled` (both terminal), or `Open → Migrated` (non-terminal — the same Task moves forward, it does not end its life or spawn a new Task).
_Avoid_: To-do, item.

**Event**:
A bullet recording something scheduled or that happened on a date. No lifecycle; immutable once logged. Never migrates.

**Note**:
A bullet recording a thought, fact, or reference on a date. No lifecycle; immutable once logged. Never migrates.

**Migration**:
The month-end review of every still-Open Task, day-scoped or month-scoped. For each, a one-tap decision: Migrate, Cancel, or Complete. A Migrate decision appends `{from, to, timestamp}` to the Task's own history — it is not a new Task.
_Avoid_: Carry-forward, rollover (these imply automatic/silent movement; migration here is always a deliberate per-Task decision at month-end).

**Scope**:
Whether a bullet belongs to a single day or to a month. Day-scoped bullets belong to exactly one date and appear only in that date's Daily Log. Month-scoped bullets belong to a month and may optionally carry a day-anchor.

**Day-anchor**:
An optional specific date attached to a month-scoped bullet. A day-anchored bullet mirrors into that date's Daily Log in addition to appearing in the Monthly Log. The mirroring is one-way: a day-scoped bullet created directly in a Daily Log never appears in the Monthly Log.

**Daily Log**:
The bullets belonging to one specific day: its native day-scoped bullets, plus any month-scoped bullets day-anchored to that date.

**Monthly Log**:
The view for one month, with three parts: the Calendar (month-scoped bullets that have a day-anchor), the Task list (month-scoped bullets without one), and the Habit tracker grid for that month. Mirrors the paper method's Calendar Page / Task Page split.

**Habit**:
A persistent, user-defined thing being tracked (e.g. "exercise", "read") — name, created date, and an archived flag. Archiving removes it from future month selection without deleting past check data.
_Avoid_: Tracker (ambiguous with the habit-tracker feature as a whole), goal.

**Monthly habit selection**:
Which Habits are active on a given month's Calendar. Defaults to carrying forward the prior month's selection; freely editable per month without altering the central Habit list itself.

**Daily habit check**:
A boolean — was a given Habit done on a given day — shown as a checkbox on the Monthly Log's Calendar, for each Habit in that month's selection.

## Deferred (not v1)

Index, Future Log, custom Collections/trackers beyond the Habit tracker, and the priority/inspiration signifiers.
