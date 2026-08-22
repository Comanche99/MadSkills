# Research: stack & free-tier hosting fit

Research for issue #3, feeding the BuJo SaaS learning-app design doc (issue #1). Scope: a
mobile-responsive, multi-tenant SaaS web app built as a **personal learning project** — load is
one developer's own usage plus light testing traffic, not real customer load. All claims below are
sourced from official docs/pricing pages only (no blogs, no third-party comparison sites), fetched
live in August 2026.

## Summary comparison

| Stack | Hosting | Free-tier ceiling | Auth story | Deploy friction | Biggest gotcha |
|---|---|---|---|---|---|
| **1. Next.js on Vercel + Neon/Supabase Postgres** | Vercel Hobby (frontend/API) + Neon or Supabase (DB) | 100GB data transfer/mo, 1M function invocations, 0.5GB (Neon) or 500MB (Supabase) DB storage | Better Auth (self-hosted lib, successor to Auth.js) or Supabase Auth/Clerk as bolt-on | Git push → auto preview + prod deploy, zero config | Hobby plan is **non-commercial only**; Neon/Supabase DB compute suspends after 5 min idle (cold start on wake) |
| **2. SvelteKit on Cloudflare Workers/Pages + D1 (or Hyperdrive+external PG)** | Cloudflare Workers Free / Pages Free | 100k requests/day, 10ms CPU/invocation, D1: 5GB storage / 5M row-reads/day / 100k row-writes/day | Bring-your-own (Better Auth, or Supabase Auth against an external Postgres) — no built-in auth service | Git push via Workers Builds, or Wrangler CLI/GitHub Actions | D1 free DB capped at **500MB per database**, 10 databases per account; 10ms CPU/invocation is easy to blow past with ORMs |
| **3. Supabase-centric (Supabase Auth + Postgres + Edge Functions), any frontend host** | Supabase Free project + Vercel/Netlify/Cloudflare Pages frontend | 500MB DB, 1GB file storage, 5GB egress, 50k MAU auth, 500k Edge Function invocations | Built-in Supabase Auth, tightly coupled to Postgres Row Level Security — ideal for multi-tenant isolation | `supabase db push`/CLI or dashboard; frontend deploy is git-push via chosen host | Free project **pauses after 1 week of inactivity** — exactly the usage pattern of a solo learner |
| **4. Fly.io or Railway Dockerized full-stack + Postgres** | Fly.io (no real free tier as of 2026) or Railway (Trial then Hobby $5/mo) | Fly: 7-day/2-VM-hour trial only; Railway: one-time $5 trial credit, then $1/mo free credit | Bring-your-own (Better Auth, etc.) — no platform auth service | Fly: CLI-driven (`fly deploy`, Dockerfile/fly.toml), needs GitHub Actions for git-push CI/CD; Railway: git-push via Nixpacks/Railpack or Dockerfile, no config needed | **No meaningful free tier**: Fly Managed Postgres starts at $38/mo; Railway's $1/mo free credit won't cover an always-on service, and its Trial-account volumes are **deleted 30 days** after credit expiry |

## Recommendation

For a solo learner building a multi-tenant SaaS app with only personal/testing traffic, **stack 1
(Next.js on Vercel + Neon Postgres)** or **stack 3 (Supabase-centric)** are the strongest fits, and
in practice they blend well together (Vercel frontend + Supabase or Neon backend). Both give a
permanently-free tier with zero credit-card requirement, git-push deploys with zero CI/CD
authoring, and a database story sized correctly for one developer's data. Supabase edges ahead
specifically for the "multi-tenant" requirement because Auth is pre-wired to Postgres Row Level
Security, which is the natural mechanism for per-tenant data isolation and saves hand-rolling
tenant-scoping logic — at the cost of the free project auto-pausing after a week of inactivity
(a nuisance, not a wall, since a paused project just needs a dashboard click to resume). Vercel +
Neon is the better fit if the priority is deploy ergonomics and staying inside the mainstream
Next.js ecosystem, and it now inherits Vercel's own auth story since Vercel acquired Better Auth
(the maintenance-mode successor to Auth.js) in July 2026. **Stack 2 (Cloudflare Workers + D1)** is
viable and has a genuinely generous free tier, but its 500MB-per-database D1 cap, 10ms CPU budget
per invocation, and lack of any built-in auth service add real friction for a learning project
whose point is the app, not the platform. **Stack 4 (Fly.io/Railway) should be avoided** for this
project: neither platform has a durable, no-cost way to keep an always-on app *and* a Postgres
database running — Fly's Managed Postgres starts at $38/month with no free tier, and Railway's
free allowance ($1/month after the one-time trial) is too small to sustain even a small always-on
service, with unpaid Trial volumes deleted after 30 days. Docker-based hosts are worth revisiting
only if the learning goal shifts toward containers/ops themselves.

---

## 1. Next.js on Vercel + Neon or Supabase Postgres

### Hosting / free-tier limits

Vercel's Hobby plan includes **100 GB/month of Fast Data Transfer**, **10 GB/month of Fast Origin
Transfer**, **1M edge requests/month**, **1M function invocations/month**, **4 Active CPU
hours/month**, **360 GB-hrs/month of provisioned memory**, and **unlimited deployments**, with a
**45-minute build cap** and **100 deployments/day** — but the plan is explicitly **"for personal,
non-commercial use"** and usage caps cannot be paid past on Hobby ([Vercel Pricing](https://vercel.com/pricing)).

Native "Vercel Postgres" no longer exists: Vercel states *"Vercel Postgres is no longer available.
If you had an existing Vercel Postgres database, we automatically moved it to Neon in December
2024. For new projects, install a Postgres integration from the Marketplace"* ([Postgres on Vercel](https://vercel.com/docs/postgres)).

**Neon** free plan: **0.5 GB storage/project**, **100 compute-hours/project/month**, up to **100
projects** with **10 branches each**, autoscaling capped at **2 CU (8 GB RAM)**, a **6-hour
point-in-time-restore window (1 GB limit)**, and automatic **scale-to-zero after 5 minutes of
inactivity** (suspended compute is not charged) ([Neon Pricing](https://neon.com/pricing)). A
0.25 CU free-tier compute supports roughly **104 max Postgres connections (97 usable)**, and
Neon's built-in PgBouncer pooler accepts up to **10,000 concurrent client connections**, giving
plenty of headroom for a side project ([Neon connection pooling docs](https://neon.com/docs/connect/connection-pooling)).

**Supabase** free plan (alternative managed Postgres for this stack): **500 MB database
storage**, **1 GB file storage**, **5 GB egress + 5 GB cached egress**, **50,000 monthly active
auth users**, **500,000 Edge Function invocations**, **2 active projects**, and Free projects are
**"paused after 1 week of inactivity"** ([Supabase Pricing](https://supabase.com/pricing)).

### Auth story

Auth.js (formerly NextAuth.js) is now in **maintenance mode**: *"the Better Auth team continues to
handle security patches and critical issues for Auth.js... if you're starting a new project... we
strongly recommend using Better Auth"* ([Auth.js migration guide](https://authjs.dev/getting-started/migrate-to-better-auth)).
Better Auth is a free, open-source, **self-hosted-by-default** TypeScript auth framework supporting
Next.js and 20+ other frameworks, with built-in credentials/session/email-verification flows,
30+ social providers, and multi-tenancy primitives (teams, roles, invitations) ([Better Auth](https://www.better-auth.com/)).
Notably, **Vercel acquired Better Auth in 2026**, tightening the Vercel/Next.js + auth pairing
further (per the same Auth.js migration page and Better Auth's own announcement). Alternatively,
Supabase Auth or Clerk can bolt on regardless of DB choice — Clerk's free Hobby plan covers
**50,000 monthly retained users** and **100 monthly retained organizations**, with no credit card
required, though it excludes SMS, passkeys, and MFA on the free tier ([Clerk Pricing](https://clerk.com/pricing)).

### Deploy friction

Vercel deploys automatically on every Git push: a push to a non-production branch creates a
**Preview Deployment**, and a merge to the production branch (`main` by default) creates a
**Production Deployment** — configured entirely by connecting a GitHub/GitLab/Bitbucket repo
through the dashboard, no YAML required ([Deploying Git Repositories with Vercel](https://vercel.com/docs/git)).

### Hard walls / gotchas

- Hobby plan is licensed for **non-commercial use only**; any revenue-generating deployment
  requires upgrading to Pro ([Vercel Pricing](https://vercel.com/pricing)).
- Neon free-tier compute **suspends after 5 minutes idle**, meaning the first request after a gap
  pays a cold-start cost to resume the Postgres instance ([Neon Pricing](https://neon.com/pricing)).
- Neon free storage is capped at **0.5 GB/project** and point-in-time restore only covers a
  **6-hour window** ([Neon Pricing](https://neon.com/pricing)).
- If using Supabase as the DB instead, the free project **pauses entirely after 7 days of no
  activity** and must be manually resumed from the dashboard ([Supabase Pricing](https://supabase.com/pricing)).
- Vercel Hobby function invocations are capped at **1,000,000/month** and Active CPU at **4
  hours/month** — generous for solo use but a real ceiling if load-testing scripts are run against
  it ([Vercel Pricing](https://vercel.com/pricing)).

---

## 2. SvelteKit on Cloudflare Workers/Pages + D1 (or Hyperdrive + external Postgres)

### Hosting / free-tier limits

Cloudflare Workers Free plan: **100,000 requests/day**, **10 ms CPU time per invocation**,
**Workers KV**: 100k reads/day, 1k writes/day, 1k deletes/day, 1 GB stored; **Hyperdrive** (for
connecting Workers to an external Postgres): **100,000 database queries/day**; **Durable Objects**:
100,000 requests/day, 13,000 GB-s/day duration; the paid plan has a **$5/month minimum** ([Cloudflare Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)).

Cloudflare **D1** (Cloudflare's native SQLite-based DB) free tier: **5 million rows read/day**,
**100,000 rows written/day**, **5 GB total storage per account** ([Cloudflare D1 Pricing](https://developers.cloudflare.com/d1/platform/pricing/)), with a **500 MB max size per
individual database** and a cap of **10 databases per account** on the Free plan ([Cloudflare D1 Limits](https://developers.cloudflare.com/d1/platform/limits/)).

Cloudflare **Pages** free tier: **500 builds/month**, builds **timeout after 20 minutes**, up to
**100 custom domains per project**, **20,000 files per deployment** on Free (100,000 on paid) ([Cloudflare Pages Limits](https://developers.cloudflare.com/pages/platform/limits/)).

### Auth story

Cloudflare has no built-in application-auth service comparable to Supabase Auth. The realistic
options are the same bolt-on libraries as elsewhere: Better Auth (framework-agnostic, works with
SvelteKit/Hono on Workers) ([Better Auth](https://www.better-auth.com/)), or Supabase Auth pointed
at an external Postgres reached via Hyperdrive, or a third-party hosted provider like Clerk
([Clerk Pricing](https://clerk.com/pricing)).

### Deploy simplicity

SvelteKit's official `adapter-cloudflare` builds for **Cloudflare Workers Static Assets and
Cloudflare Pages**, is the default target when using `adapter-auto`, and supports all SvelteKit
features ([SvelteKit adapter-cloudflare docs](https://svelte.dev/docs/kit/adapter-cloudflare)).
Cloudflare's own **Workers Builds** CI/CD auto-deploys **"every time you push a change"** to a
connected GitHub/GitLab repo, with build status surfaced back to the Git provider via checks/PR
comments — comparable git-push-to-deploy ergonomics to Vercel ([Cloudflare Workers Git Integration](https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/)).

### Hard walls / gotchas

- **10 ms of CPU time per invocation** on the free plan is easy to exceed with a typical ORM-driven
  SSR request; this is a CPU-time budget, not wall-clock, but it's still a tight ceiling for a
  Node-style backend ([Cloudflare Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)).
- D1 free databases are capped at **500 MB each**, only **10 databases per account**, and 5 GB
  total storage account-wide — multi-tenant schemas that grow past that need a paid plan or a
  switch to an external Postgres via Hyperdrive ([Cloudflare D1 Limits](https://developers.cloudflare.com/d1/platform/limits/)).
- Requests are capped at **100,000/day** account-wide on the free plan ([Cloudflare Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)).
- No built-in auth or user-management service — everything must be assembled from libraries,
  raising initial setup friction relative to Supabase or Clerk-based stacks.

---

## 3. Supabase-centric stack (Supabase Auth + Postgres + Edge Functions), any frontend host

### Hosting / free-tier limits

Supabase Free plan: **500 MB database storage** (shared CPU, 500 MB RAM), **1 GB file storage**,
**5 GB egress + 5 GB cached egress**, **50,000 monthly active users** for Auth (also 50,000 for
third-party auth MAUs), **500,000 Edge Function invocations**, **200 concurrent Realtime
connections**, **2 million Realtime messages**, a limit of **2 active projects**, **1-hour** audit
log retention, and community-only support; **free projects pause after 1 week of inactivity**
([Supabase Pricing](https://supabase.com/pricing)).

### Auth story

Supabase Auth is Supabase's built-in service: it stores users in a dedicated Postgres schema
("Auth uses your project's Postgres database under the hood... storing user data... in a special
schema") and supports email/password, magic links/OTP, OAuth (Google, GitHub, Discord, etc.), and
SAML 2.0 SSO. It issues JWTs that flow directly into Postgres Row Level Security policies, so
per-tenant data isolation can be enforced **in the database layer** rather than the app layer —
directly relevant to a multi-tenant SaaS design ([Supabase Auth docs](https://supabase.com/docs/guides/auth)).

### Deploy simplicity

The frontend can be hosted anywhere (Vercel, Netlify, Cloudflare Pages) using that host's own
git-push deploy flow — see stacks 1 and 2 above for the mechanics. The backend (schema, RLS
policies, Edge Functions) is managed via the Supabase CLI or dashboard. Edge Functions run on a
**Deno-compatible runtime**, are deployed via dashboard/CLI/MCP, and Supabase's own guidance is to
design them for **"short-lived, idempotent operations"** since **cold starts are possible** and
Postgres should be treated as **"a remote, pooled service"** from within a function ([Supabase Edge Functions docs](https://supabase.com/docs/guides/functions)).

### Hard walls / gotchas

- **Free projects pause after 7 days without activity** — for a solo learner who might not touch
  the app daily, this is the single most likely limit to actually get hit, though resuming is a
  one-click dashboard action, not a rebuild ([Supabase Pricing](https://supabase.com/pricing)).
- Database storage is capped at **500 MB** and file storage at **1 GB** — fine for a bullet-journal
  app's own data, tight if attachments/images accumulate ([Supabase Pricing](https://supabase.com/pricing)).
- Only **2 active projects** allowed on the free plan, which matters if separate dev/staging
  Supabase projects are wanted ([Supabase Pricing](https://supabase.com/pricing)).
- Edge Functions are not suited to long-running jobs; heavier background work needs to move
  elsewhere per Supabase's own guidance ([Supabase Edge Functions docs](https://supabase.com/docs/guides/functions)).

---

## 4. Fly.io or Railway — Dockerized full-stack + Postgres

### Hosting / free-tier limits

**Fly.io** has **no permanent free tier as of 2026**. New accounts get a trial limited to
**2 hours of machine runtime or 7 days, whichever comes first**, up to **10 machines**, **20 GB**
volume storage, **2 vCPUs / 4 GB memory per machine**, and trial machines **auto-stop after 5
minutes of running**; no credit card is required to start the trial, but *"if you don't add a
payment method by the end of your 7-day trial, or if you use up the included resources, your apps
will stop running"* ([Fly.io Free Trial docs](https://fly.io/docs/about/free-trial/)). A minimal
always-on `shared-cpu-1x`/256 MB machine costs roughly **$2/month** once past the trial ([Fly.io Pricing](https://fly.io/docs/about/pricing/)). Fly's **Managed Postgres** has no free tier at all: the
cheapest plan (**Basic**, shared-2x CPU / 1 GB memory) is **$38.00/month**, plus **$0.28 per
provisioned GB/month** for storage ([Fly.io Managed Postgres docs](https://fly.io/docs/mpg/)).

**Railway**: new accounts get a **one-time $5 trial credit** (expires after 30 days or when spent,
whichever first), with Trial-tier resource caps of **1 GB RAM**, **2 vCPU**, **2 replicas**, **1 GB
ephemeral storage**, **0.5 GB volume storage** per service, and **restricted outbound network
access** unless GitHub-verified ([Railway Pricing Plans docs](https://docs.railway.com/pricing/plans)). After the trial, the account **"automatically transitions to Railway's Free plan, which
provides $1 of free credit per month"** — not enough to keep a small always-on service running
continuously — and *"Railway deletes stateful volumes created by Trial accounts 30 days after the
expiration of your credits"* unless upgraded ([Railway Free Trial docs](https://docs.railway.com/pricing/free-trial)). The paid **Hobby** plan starts at **$5/month** minimum
subscription regardless of actual usage ([Railway Pricing Plans docs](https://docs.railway.com/pricing/plans)).

### Auth story

Neither platform provides a built-in auth service — both are general-purpose compute/container
hosts. The realistic choice is the same self-hosted library approach as stacks 1/2: Better Auth
(free, open-source, self-hosted) ([Better Auth](https://www.better-auth.com/)), or a hosted
provider such as Clerk bolted on regardless of backend host ([Clerk Pricing](https://clerk.com/pricing)).

### Deploy friction

**Fly.io**: deployment is **CLI-driven** — `fly deploy` builds/fetches a Docker image (from a
`Dockerfile` in the project root, or an explicit `--image`) and updates Machines; `fly launch`
detects a Dockerfile and deploys it. There is no built-in git-push-to-deploy; automatic
CI/CD on push requires wiring up GitHub Actions separately ([Fly.io Deploy an app docs](https://fly.io/docs/launch/deploy/), [Fly.io Dockerfile docs](https://fly.io/docs/languages-and-frameworks/dockerfile/)).

**Railway**: connecting a GitHub repo and clicking Deploy is enough — Railway auto-detects the
stack and builds via **Railpack/Nixpacks** with zero configuration, or uses a root-level
`Dockerfile` automatically if one is present, giving genuine git-push-to-deploy ergonomics
comparable to Vercel/Cloudflare ([Railway Dockerfiles docs](https://docs.railway.com/builds/dockerfiles)).

### Hard walls / gotchas

- **Fly.io**: no meaningful free tier — trial is capped at **2 machine-hours or 7 days**, and a
  payment method is required to keep anything running past that ([Fly.io Free Trial docs](https://fly.io/docs/about/free-trial/)).
- **Fly.io Managed Postgres starts at $38/month** with no free plan, making "Postgres on Fly at
  zero cost" not realistically achievable through the managed product ([Fly.io Managed Postgres docs](https://fly.io/docs/mpg/)).
- **Railway**: the ongoing free allowance after the trial is only **$1/month in credit** — far
  below what an always-on web service + Postgres would consume — and **Trial-account volumes are
  deleted 30 days** after the trial credit runs out if not upgraded, risking silent data loss for
  an inactive learning project ([Railway Free Trial docs](https://docs.railway.com/pricing/free-trial)).
- **Railway** database storage is metered at **$0.15/GB** and network egress at **$0.05/GB** once
  past free credit, on top of the **$5/month** Hobby subscription floor ([Railway Pricing Plans docs](https://docs.railway.com/pricing/plans)).

---

## Sources

- [Vercel Pricing](https://vercel.com/pricing)
- [Postgres on Vercel](https://vercel.com/docs/postgres)
- [Deploying Git Repositories with Vercel](https://vercel.com/docs/git)
- [Neon Pricing](https://neon.com/pricing)
- [Neon connection pooling docs](https://neon.com/docs/connect/connection-pooling)
- [Supabase Pricing](https://supabase.com/pricing)
- [Supabase Auth docs](https://supabase.com/docs/guides/auth)
- [Supabase Edge Functions docs](https://supabase.com/docs/guides/functions)
- [Auth.js migration to Better Auth guide](https://authjs.dev/getting-started/migrate-to-better-auth)
- [Auth.js getting started](https://authjs.dev/getting-started)
- [Better Auth](https://www.better-auth.com/)
- [Lucia Auth (project status)](https://lucia-auth.com/)
- [Clerk Pricing](https://clerk.com/pricing)
- [Cloudflare Workers Pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- [Cloudflare D1 Pricing](https://developers.cloudflare.com/d1/platform/pricing/)
- [Cloudflare D1 Limits](https://developers.cloudflare.com/d1/platform/limits/)
- [Cloudflare Pages Limits](https://developers.cloudflare.com/pages/platform/limits/)
- [Cloudflare Workers Git Integration](https://developers.cloudflare.com/workers/ci-cd/builds/git-integration/)
- [SvelteKit adapter-cloudflare docs](https://svelte.dev/docs/kit/adapter-cloudflare)
- [Fly.io Pricing](https://fly.io/docs/about/pricing/)
- [Fly.io Free Trial docs](https://fly.io/docs/about/free-trial/)
- [Fly.io Managed Postgres docs](https://fly.io/docs/mpg/)
- [Fly.io Deploy an app docs](https://fly.io/docs/launch/deploy/)
- [Fly.io Dockerfile docs](https://fly.io/docs/languages-and-frameworks/dockerfile/)
- [Railway Pricing Plans docs](https://docs.railway.com/pricing/plans)
- [Railway Free Trial docs](https://docs.railway.com/pricing/free-trial)
- [Railway Dockerfiles docs](https://docs.railway.com/builds/dockerfiles)
- [Railway PostgreSQL docs](https://docs.railway.com/databases/postgresql)
