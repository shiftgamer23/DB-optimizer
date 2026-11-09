# DBDoctor: Database Query Performance Agent — Implementation Plan

> "DBDoctor" is a working title only. Rename freely.
> This file is the handover for Claude Code. Items marked **[Decided]** were chosen by the owner and should not be changed without asking. Items marked **[Proposed]** are sensible defaults that may be adjusted if there is a good reason; note the reason in an ADR.

---

## 1. What this is (plain terms)

A doctor for slow database queries.

1. A user gives it a slow query (or a database with several slow queries).
2. The agent asks Postgres how it plans to run the query (the query plan) and finds where the time goes.
3. It proposes a fix (usually an index, sometimes a query rewrite).
4. It **tests the fix on a throwaway copy** of the database and measures the result.
5. It reports: before/after time, before/after plan, confirmation that the results are identical, and the one command to apply the fix.

**Core idea [Decided]:** the agent does not just guess. It proves each fix by measurement and checks the answers did not change.

**Design pattern [Decided]:** *plant a known fault, let the agent fix it, verify the fix by measurement.* Because we plant the faults ourselves, we know the correct answer, so evaluation numbers are honest and free.

**Why this project [Decided]:** the owner is an AIML intern targeting Forward Deployed Engineer (FDE) / Applied AI + Full Stack roles. The project must show real backend depth (FastAPI, job queue, safe SQL execution, stored runs, auth), a React frontend, measurable evals (Langfuse), and a live deployed demo.

**Scope of the first job [Decided]:** through Phase 7 the agent does exactly one job: fixing slow queries. A second job, fixing wrong queries (errors and logic bugs), is planned as Phase 8 and must not be started earlier.

**Standalone [Decided]:** this project is NOT linked to the owner's earlier projects (no MCP integration with the RAG project, ReviewCrew, triage agent or MCP hub).

---

## 2. Owner context and constraints

- **Environment [Decided]:** Windows, with Docker Desktop (WSL2). Prefer commands that work in PowerShell, and use WSL2 where Linux tooling is easier. Check free disk and RAM before loading large datasets.
- **Stack [Decided]:** FastAPI backend, React frontend, Postgres, Langfuse for evals/tracing.
- **LLMs [Decided]:** free-tier Gemini API and free-tier Groq API only. "Free enough for testing and local/portfolio use" is the bar. No paid keys.
- **Hosting [Decided]:** Vercel (frontend), Render or Railway (backend + worker), Supabase. Pick Render vs Railway when deploying; check current free-tier limits first because they change often (Railway has moved away from a permanent free tier).
- **Frontend [Decided]:** React. Vite is the proposed tooling. (The owner has said they do not want to become a frontend specialist, so keep the UI simple and clean, built with an off-the-shelf component library, and generate the API client from OpenAPI.)
- **Claude Code is available** and is expected to do most of the implementation. Keep the owner in the loop on design decisions and explain what you build, because learning along the way is a goal.
- **Motivation matters:** the owner has had a long break from personal coding. Ship small, visible wins early. Do not front-load infrastructure.

---

## 3. Scope and phases

### What is out of scope for v1
- Bring-your-own-database live connections (late phase).
- Any agent that edits real cloud deployments.
- Kubernetes, microservices, complex auth. Use a **modular monolith plus one worker**.

### Phase 0 — Repo skeleton and first manual scenario (one or two sessions)

**Skeleton [Proposed]:**
- Folder structure (section 4), `ruff`, `mypy` (or `pyright`), `pre-commit`, `.env.example`, `docker-compose.yml`, one passing test, one GitHub Actions workflow (lint + types + tests).

**First manual scenario (do this by hand before any agent code) [Decided as the first exercise]:**
1. Start Postgres in Docker Compose.
2. Generate an `orders` table with about one million rows, with skew (a few users with very many orders).
3. Run a query filtering on `user_id` with no index; time it with `EXPLAIN ANALYZE`.
4. Add the index and time it again.

Everything the agent does is an automation of these four steps. Done when the owner has seen the before/after numbers themselves.

### Phase 1 — Version 1: local agent loop, no web app (a couple of weeks of evenings)

**Goal [Decided]:** prove the core idea locally.
- Postgres in Docker.
- Synthetic e-commerce dataset (section 5).
- **5 planted-fault scenarios** (section 6).
- Agent loop: read the plan, propose a fix, test it on a copy, report before/after timings.
- Results logged to Langfuse with a score per scenario.
- CLI entry point is enough. No web UI yet.

**Done when:** running one command executes all 5 scenarios, prints a scoreboard, and logs traces and scores to Langfuse.

### Phase 2 — Backend API and worker
- FastAPI service with versioned routes (`/v1/...`).
- Job queue and background worker: the API enqueues work and returns a job ID; the UI polls or streams progress.
- Store scenarios, runs, steps and findings in the app database (Postgres; Supabase in production).
- Idempotent jobs, cleanup of orphaned clones.

### Phase 3 — React frontend [Decided features]
- List of slow queries / scenarios.
- "Analyze" button.
- **Side-by-side plan viewer** (before vs after).
- Proposed fix shown **ready to copy** (a migration the user can run).
- Run history.
- Live progress for a running job.
- Handle loading, error and empty states everywhere.

### Phase 4 — Deploy sandbox mode (hosted)
- Vercel (frontend), Render/Railway (API + worker), Supabase (Auth + Postgres for app data).
- Hosted demo databases with planted problems; visitors pick a scenario and watch the agent diagnose and fix it with measured before/after.
- Keep the hosted demo database to a few hundred thousand rows (free tiers are small, but this is enough for a missing index to change the plan visibly). Larger datasets stay local.
- Pair the live demo with **recorded runs** so it works even when free-tier services are asleep or LLM quota is exhausted.
- Per-user rate limits on the demo so one visitor cannot exhaust the free LLM quota.

### Phase 5 — Auth and saved runs
- Supabase Auth. Google sign-in is proposed (the owner has already chosen Supabase Auth with Google for another project).
- Row-level security so each user sees only their own runs.

### Phase 6 — Offline paste mode (bring-your-own-database, safe version)
- User pastes `pg_dump --schema-only` output and an `EXPLAIN (FORMAT JSON)` result. The agent analyzes those.
- No credentials, no connections, no SSRF risk, and mostly the same agent logic.

### Phase 7 — Live bring-your-own-database connections (last)
See section 9. Only build this if Phases 1–6 are solid.

### Phase 8 — Correctness mode: fixing broken queries (second job, later) [Decided as a later phase]

**Context [Decided]:** through Phase 7 the agent has exactly one job, fixing **slow** queries (indexes and performance rewrites). That focus is deliberate: it lets the core loop be built and measured end to end first. Phase 8 adds a second job, fixing **wrong** queries. Do not start it until the performance doctor works and is deployed. The existing pieces (scenario definition, agent loop, sandboxed clone, verifier, Langfuse scoring) are reused; correctness mode is a new module, not a rewrite.

**8a. Error fixer (build first, easy win)**
- Input: a query that fails to run (missing column, column missing from `GROUP BY`, ambiguous column, type mismatch).
- The agent reads the error message plus the schema, proposes a corrected query, and **verifies by running it on the clone**.

**8b. Logic-bug fixer (harder)**
- Input: a query that runs but returns the wrong results.
- **Intent is required.** The agent cannot know what is correct without it. The user supplies one of: a plain-English description of what the query should return, a small expected output, or a reference query known to be right.
- **Without intent, the agent only flags suspected bugs** (e.g. "this join has no condition, so every row pairs with every row; is that intended?") and **never silently rewrites**.
- Bug catalogue to detect and fix: missing join condition (cartesian product); `INNER JOIN` where `LEFT JOIN` was intended (rows silently dropped); `NOT IN` with NULLs; `= NULL` instead of `IS NULL`; join fan-out that duplicates rows and inflates sums; `COUNT(*)` vs `COUNT(DISTINCT ...)`; date ranges off by a day (`BETWEEN` with timestamps); `WHERE` vs `HAVING` mix-ups.

**Safety rules for correctness mode [Decided]**
- The performance rule "same rows before and after" **does not apply**, because a correctness fix is supposed to change the results.
- Instead: always show the **result difference** (before vs after) and require the user to **confirm the intent matches** before presenting a fix as correct. Never auto-apply.
- The main risk is the agent confidently "fixing" a query into something that does not match what the user meant. Design the UI and the prompts around that risk.
- All existing safety rules still apply (sandbox clone only, `sqlglot` validation, statement timeouts, LLM output untrusted).

**Evaluation for correctness mode [Decided approach: plant faults, verify with ground truth]**
- Start from **known-correct queries** over the e-commerce schema and apply **bug mutations** (drop a join condition, turn a LEFT JOIN into INNER, remove `DISTINCT`, `= NULL`, `NOT IN` with NULLs, `BETWEEN` on timestamps, `WHERE` vs `HAVING`, `COUNT` vs `COUNT(DISTINCT)`). Record which mutation was applied to each scenario.
- The agent receives only the buggy query plus a plain-English description of intent.
- **Differential testing:** run the agent's fixed query and the original correct query on the same data and compare results. Seed the dataset with **edge cases** (NULLs in nullable foreign keys, duplicate rows, boundary timestamps) so wrong fixes are exposed.
- Metrics: **fixed-correctly rate**; **false-fix rate** (changed a query that was not broken; include control scenarios with already-correct queries); and, for scenarios without intent, **flagged-without-rewriting rate**.
- Keep a held-out scenario set, log everything to Langfuse, and run it in CI alongside the performance benchmark.

**UI additions:** an input for the intent description, and a result-diff viewer next to the plan viewer.

### Optional later extensions [not part of v1]
- **Dockerfile optimizer** as a CLI warm-up (decided: it is a CLI with fixture apps, no web backend or frontend, because it does not need one). If built, it should share the sandbox runner, scenario generator, verifier and Langfuse scoring, forming a small "fault-injection benchmark for engineering agents".
- Other "doctor" modules with the same pattern: data quality doctor, dependency upgrade agent, API performance doctor, vulnerability patcher (own planted demo code only, isolated).
- A deployment-fixer module only as a **local Docker** version. Do not build one that touches real cloud accounts.

---

## 4. Proposed repository layout [Proposed]

```
dbdoctor/
  backend/
    app/
      api/            # thin route handlers, versioned /v1
      core/           # config (pydantic-settings), logging, security
      services/       # analysis orchestration, clone manager, SQL validator,
                      # plan parser, metrics/timing, scoring
      agent/          # agent loop, tools, prompts, step/budget limits
        llm/          # provider interface + Gemini + Groq + cache/replay
      db/             # SQLAlchemy models, Alembic migrations
      workers/        # background job runner
    tests/
  frontend/           # React (Vite), generated API client
  scenarios/          # seed scripts, fault definitions (YAML/JSON), fixtures
  evals/              # eval runner, scorers, Langfuse dataset integration
  docs/               # architecture diagram, ADRs
  docker-compose.yml  # api, worker, postgres, redis
  .github/workflows/  # CI
  README.md
```

Layers: API routes stay thin; logic lives in the service layer; database access and LLM calls sit behind small interfaces so they can be swapped or faked in tests.

---

## 5. Data

**Primary: synthetic e-commerce data [Decided]**, generated inside Postgres with `generate_series`, or with Faker.
- Tables: `users`, `products`, `orders`, `order_items`, `reviews`.
- **Add skew deliberately** (a Zipf-like distribution: a few users with thousands of orders). Uniform random data makes the planner behave unrealistically; skew is what makes plans go wrong in practice.
- Local size: about a million-plus rows in the big tables. Hosted demo size: a few hundred thousand rows.

**Real data for credibility (later, as a held-out "realistic" test set) [Proposed]:**
- Instacart market basket (Kaggle), or a small Stack Exchange data dump (the DBA Stack Exchange is a good thematic fit; check size and Creative Commons attribution terms).
- Stretch: IMDb public datasets (the Join Order Benchmark is built on them and is known to trip planners; IMDb terms restrict commercial use, fine for personal projects).
- Quick starts: `pgbench -i -s 50`, TPC-H with a chosen scale factor.
- Tiny sample databases (Pagila, Chinook, Northwind) are too small for performance work.
- Hugging Face is a poor fit (mostly text/parquet, not relational tables).
- Always check file sizes and licenses before downloading.

---

## 6. Planted-fault scenarios

**First five [Decided]:**
1. **Missing index** on a frequently filtered column (e.g. `orders.user_id`).
2. **Function applied to an indexed column** that defeats the index (e.g. `WHERE lower(email) = ...` or `date(created_at) = ...`).
3. **Redundant/duplicate index** (extra write cost, no read benefit).
4. **Bad join pattern** (e.g. missing join index, or a join that causes a huge intermediate result).
5. **Type mismatch that blocks index use** (e.g. comparing a text column to a numeric value, forcing a cast).

More scenarios can follow the same shape.

**Scenario definition format [Proposed]:** one YAML/JSON per scenario with `id`, seed script reference, the slow query, fault type, accepted fix classes, and acceptance criteria.

**Splits [Proposed]:** tune prompts on some scenarios and report results on held-out ones, otherwise the numbers are flattering. Verify every scenario runs and the slow query is actually slow *before* the agent touches it, so failures are always the agent's.

---

## 7. The agent

### Tools available to the agent
- Read the query plan (`EXPLAIN`, `EXPLAIN (ANALYZE)` only on the clone).
- List indexes; view table statistics.
- Run queries and DDL on the **cloned** database only.

### Loop
Hypothesis → test on the clone → measure → report with before/after plans. Enforce a **maximum step count and a cost/token budget** per run. "No safe improvement found" is a valid, honest result. A run must never be stuck in "running".

### Output to the user
Before/after times, before/after plans, confirmation results are identical, and the single command (migration) to apply the fix.

---

## 8. The copy/clone mechanism and measurement

### Flow per analysis [Decided]
1. Make a copy of the database.
2. Run the slow query on the copy; record time and plan (the "before").
3. Apply the proposed fix **to the copy only**.
4. Run the same query again; record time and plan (the "after").
5. **Check the result sets are identical** (a faster query returning wrong rows is a failure).
6. Delete the copy. Keep only the report.

### How to copy
- **v1 [Decided]: re-seed from the generation script into a fresh container.** Simplest, fully reproducible, no copy logic.
- Later: template clone (`CREATE DATABASE clone_x TEMPLATE original;`), which is fast but needs the source to have no active connections.
- Alternative: `pg_dump` / `pg_restore` into a throwaway database or container.

### Fair measurement [Decided]
- Run `ANALYZE` on the clone after copying so planner statistics are fresh.
- Run each query **several times and use the median** (the first run is slower while caches warm).
- Compare **relative** changes (e.g. 8 s → 40 ms), not absolute numbers.
- `EXPLAIN ANALYZE` actually executes the query. Only run it on the clone or on safe SELECTs.

### Safety [Decided]
- **Two database roles:** read-only for anything real; a separate role allowed to create indexes only on the clone.
- `statement_timeout` on every query so a bad suggestion cannot hang the database.
- Unique clone names per run so analyses do not interfere.
- **Validate SQL before running it** with `sqlglot`: allowlist (e.g. only `CREATE INDEX` and SELECT-style rewrites on the clone); block `DROP`, `DELETE`, and anything touching other schemas.
- **Treat LLM output as untrusted input**, exactly like user input.
- Cleanup task for stale/orphan clones; retries must not create duplicates.

---

## 9. Bring-your-own-database mode (late phase)

**Feature [Decided as desired]:** users can link their own Postgres database (paste a connection URL). Build offline paste mode first (Phase 6), live connections last (Phase 7).

### How live mode works [Proposed]
1. User signs in and pastes a connection string.
2. A **safety check** verifies SSL is used, the role is read-only (not a superuser, no write privileges), and which extensions are available.
3. The agent collects **metadata only**: schema, table statistics, existing indexes, slow queries (from `pg_stat_statements` if enabled, or queries the user pastes).
4. It returns recommendations with evidence. **It never applies anything to their database.**

### Requirements
- **Credentials:** do not ask for a superuser URL. Show a copy-paste snippet to create a dedicated read-only role. Keep the string in memory for the session, or encrypt at rest if stored. **Never log it** (redact connection strings in logs).
- **SSRF protection:** since the server connects to a user-supplied host, block private/internal addresses: localhost, `10.x`, `192.168.x`, and the cloud metadata address `169.254.169.254`. **Resolve DNS yourself and connect to the resolved IP** so a hostname cannot be switched to an internal address after the check.
- **Strict connection limits:** one or two connections, `statement_timeout`, `lock_timeout`, session set to read-only.
- **Privacy:** query literals can contain personal data. **Normalize queries** (replace values with placeholders, using `sqlglot`) and send the LLM only structure and stats, never row data. Tell users exactly what is sent. On the free Gemini tier, inputs may be used to improve Google's products, so do not send real user schemas to it, or at least warn the user clearly.
- **Isolation and abuse controls:** login required, per-user data access (Supabase row-level security), rate limits, retention limits, logging. A connect-to-any-host feature can be abused as a port scanner, so rate limit and audit it.
- **Consent notice:** "only analyze databases you are authorized to."

### Limitations to be honest about in the UI
- Cannot clone a stranger's database, so evidence is weaker. Use plain `EXPLAIN`, not `EXPLAIN ANALYZE`.
- `hypopg` (hypothetical indexes) is useful but needs an extension many managed hosts do not allow.
- Label results **"estimated"** (BYO mode) vs **"measured"** (sandbox mode).
- The user's database must be reachable from the internet; free hosting rarely provides fixed outbound IPs, so databases behind IP allowlists will not work.

---

## 10. LLM layer

**Providers [Decided]:** free Gemini API and free Groq API.

### Design
- **LLM provider interface [Decided design]** with Gemini and Groq as two implementations, and **automatic fallback to the other on a 429 (rate limit)** error.
- **Trim what is sent:** summarize plans, send only relevant schema. This also improves the agent.
- **Cache and replay [Decided design]:** save every LLM response keyed by its input. Tests and re-runs cost nothing, and the hosted demo can replay recorded runs when quota is exhausted.
- Timeouts, retries with backoff, and a step/cost budget on every call.

### Which model for what [Proposed]
- **Gemini Flash-class model:** main model for diagnosis (better structured output, more context for large plans).
- **Groq (e.g. gpt-oss or a Llama model):** fast, cheap steps and quick development loops.
- **Avoid Gemini 2.5 models** (one listing says they are scheduled for shutdown on 16 October 2026) and **do not depend on Pro models** (removed from the free tier around April 2026; sources disagree on whether light free use remains). Use a current Flash or Flash-Lite model; **check the exact model names in Google AI Studio**.
- Groq limits are per model and apply per organization (extra keys do not help). One published example for `gpt-oss-120b`: 30 requests/min, 1,000/day, 8,000 tokens/min, 200,000 tokens/day. **The token limits are the real constraint**: a plan plus schema can be thousands of tokens and each analysis needs several calls.
- A full benchmark run (many scenarios × several calls × repeats) can consume a day's quota, so use the cache/replay layer and run full evals sparingly.
- **Free-tier terms change often. Verify limits in AI Studio and on Groq's limits page before building around any number.**
- **Model comparison is a feature [Decided]:** run the same benchmark on both providers and report fix-success rate, measured speedup and cost per scenario. This table is a portfolio asset.

---

## 11. Evaluation (Langfuse)

### Per-scenario score [Decided metrics]
- Did the agent find an **acceptable fix**?
- **Measured speedup** (before vs after, median of repeated runs).
- **Same rows returned** before and after.
- Did it ever suggest something **destructive without flagging it**?

### Aggregates [Proposed]
Pass rate, median speedup, unsafe-suggestion count, cost/tokens per scenario, per provider/model/prompt version.

### Practice
- One Langfuse trace per run (each agent step, tool call, token cost, latency), plus dataset-based eval runs repeatable after every change.
- Define "acceptable fix" objectively (e.g. the plan changes from a sequential scan to an index scan **and** speedup exceeds a threshold such as 5×). The threshold is a proposal; set it per scenario in the scenario file.
- Track the benchmark score per commit. CI should fail if the score drops.
- Keep a held-out scenario set (section 6).

---

## 12. Engineering practices

### From day one [Decided as a set]
- Clear layering (thin routes → services → interfaces for DB/LLM).
- **Typed everything:** Pydantic models for requests, responses and the agent's structured outputs; `ruff`; `mypy` or `pyright`.
- **Config and secrets in environment variables** via `pydantic-settings`; commit `.env.example`, ignore `.env`. No keys in the repo, ever.
- **Alembic migrations** for the app's own tables.
- **Git hygiene:** small commits, conventional commit messages, `pre-commit` hooks for lint/format.
- **Docker Compose** bringing up API, worker, Postgres and Redis with one command.

### Testing
- Unit tests for pure logic (plan parsing, speedup calculation).
- **Integration tests against a real Postgres** in a throwaway container (Testcontainers), not mocks.
- **Record and replay LLM calls** so tests are fast, free and deterministic; keep a separate, optional live-model test run.
- Property-style checks: after any fix, the result set must equal the original, asserted across many generated scenarios.
- The planted-fault benchmark doubles as a regression suite.
- A few end-to-end tests with Playwright for the main flow (pick a scenario, run, see the result).

### Reliability
- Background jobs, not long requests; API returns a job ID.
- Idempotency; cleanup of orphaned clones; no run left stuck "running".
- Timeouts, retries with backoff, step limits and cost budgets.

### Security
- Least-privilege database roles, statement timeouts, SQL allowlist (`sqlglot`), LLM output treated as untrusted.
- Supabase row-level security; rate limiting; per-user LLM budget caps; no secrets in logs.

### Observability
- Structured JSON logs with a **run ID on every line**; Langfuse traces; a health endpoint; basic metrics (queue length, job duration, failure rate).

### API and frontend
- Consistent error format; versioned routes (`/v1/...`).
- **Generate the TypeScript API client from the OpenAPI schema** so frontend and backend cannot silently drift.
- React Query for server state; loading/error/empty states everywhere.

### Process and docs
- **CI (GitHub Actions):** lint, type check, tests, and a small eval run on every pull request; **fail the build if the benchmark score drops**.
- **Short Architecture Decision Records** (half a page each), e.g. "why clone by re-seeding", "why a queue".
- **Strong README:** architecture diagram, how to run, benchmark results, honest limitations.

---

## 13. Proposed app data model [Proposed — refine freely]

- `users` (Supabase Auth identity)
- `scenarios` (id, name, fault type, config)
- `runs` (id, user_id, scenario_id or source type, status, provider/model, started/finished, cost)
- `run_steps` (run_id, step index, tool, input, output, duration)
- `findings` (run_id, proposed fix SQL, before/after times and plans, rows_equal, speedup, safe flag)

Proposed endpoints (all under `/v1`): create analysis job, get job status/stream progress, list runs, get run detail, list scenarios, health.

---

## 14. Hosting notes and risks

- **Free tiers shape the plan.** Typically: small database size, projects pause when idle, free web services sleep (cold starts). Check current limits before choosing a host.
- Supabase offers an index advisor. **Differentiate:** DBDoctor *verifies* fixes by measurement and covers more than indexes (query rewrites, join problems). Make that the pitch in the README.
- Public demo runs **only pre-built scenarios in isolation**, never arbitrary user SQL or code.
- Windows: Postgres plus a large dataset needs RAM and disk; check before loading.

---

## 15. Working agreements for Claude Code

- Work phase by phase; do not start a later phase before the current one meets its "done when".
- Keep PRs/commits small and focused. Run lint, types and tests before each commit.
- Explain non-obvious design choices briefly as you go; the owner wants to learn.
- Do not change a **[Decided]** item silently. Ask first, and record the change in an ADR.
- Never log or commit secrets or connection strings.
- If a free-tier limit or model name differs from this plan, verify against the provider's current page and note the finding in the README.

---

## 16. Open questions for the owner

1. Render or Railway for the backend (decide at deploy time after checking current free limits).
2. Exact Gemini and Groq model names (check AI Studio and Groq's limits page).
3. Which real dataset to add as the held-out "realistic" set (Instacart, a small Stack Exchange dump, or IMDb).
4. Whether to build live BYO-database connections (Phase 7) or stop at offline paste mode.
5. Whether to do the Dockerfile CLI warm-up first or start directly on this project.
6. Final project name.
7. Phase 8 (correctness mode): whether to start with the error fixer only, or go straight to logic bugs.

---

## 17. First session checklist (start here)

1. Create the repo skeleton: folders, `ruff`, `mypy`, `pre-commit`, `.env.example`, `docker-compose.yml` (Postgres, Redis), one passing test, one CI workflow.
2. Start Postgres via Compose.
3. Generate the million-row skewed `orders` table.
4. Time a `user_id` filter query without an index using `EXPLAIN ANALYZE`; add the index; time it again.
5. Write down both numbers. This is scenario #1 and the foundation of the whole project.
