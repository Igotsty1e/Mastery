# Postgres cutover — Render free-tier → LevelChannel VPS

> **Status:** Drafted 2026-05-14. Cutover target window opens
> 2026-05-20; current Render Postgres free instance auto-deletes
> 2026-05-27. **Operator-driven** — requires SSH access to the
> LevelChannel VPS (key: `~/.ssh/levelchannel_timeweb_ed25519`,
> per memory `levelchannel-deploy.md`) and Render dashboard access.

## Why

Mastery's current backend persistence lives on a Render free-tier
Postgres (`dpg-d7ngmh37uimc73bd2eig-a`, region `oregon`, db
`mastery_postgres_igotsty1e`). The free tier expires **2026-05-27**.
Decision 2026-05-14: do not upgrade on Render; co-locate with the
LevelChannel Timeweb VPS instead. Single operations surface, single
SSH path, no second $7/month line item.

## Topology — two viable paths

### Option A — DB-only move, Mastery backend stays on Render

- **VPS side:** new Postgres database + role for Mastery.
- **Render side:** flip `DATABASE_URL` on `mastery-backend-igotsty1e`
  to the VPS public endpoint.
- **Network:** VPS Postgres must accept connections from Render's
  egress. Render free tier has **dynamic outbound IPs** — no static
  allowlist possible without upgrading. Practical implications:
  - Either accept `0.0.0.0/0` in `pg_hba.conf` (public Postgres,
    security risk; needs strong password + TLS-required + fail2ban
    or rate limiting at the firewall),
  - Or set up a VPN/tunnel (Tailscale, WireGuard, Cloudflare Tunnel)
    between Render and the VPS. Adds an operational dependency.
- **Latency:** Render Oregon → VPS Russia is ~150ms RTT per query.
  Mastery hits Postgres on every authenticated request. The cutover
  to A is functional but felt.

### Option B (recommended) — Full move, Postgres + backend on the VPS

- **VPS side:** new Postgres database + role for Mastery, **and** a
  new systemd unit (`mastery.service`) running the Mastery backend
  on a free localhost port (e.g. `127.0.0.1:3001`, leaving `:3000`
  for LevelChannel).
- **Public web:** `https://mastery-web-igotsty1e.onrender.com` stays
  on Render (static-site builds are cheap and the free tier is
  fine for static); its `API_BASE_URL` build-time var flips to the
  new VPS-served API origin.
- **Render side:** decommission the Render web service +
  Render Postgres free instance once smoke confirms the VPS path
  is healthy. Keep the static-site Render service for the web bundle.
- **Network:** Postgres stays bound to `127.0.0.1:5432` (same as
  LevelChannel today). Mastery backend connects via local socket —
  no public Postgres exposure, no VPN setup.
- **Latency:** local socket. Sub-1ms per query.

**Recommendation:** Option B. The security simplification (no
public-Postgres exposure, no Render-IP allowlist guessing) plus
the latency win plus single-ops surface justify the slightly larger
cutover scope. Option A's only advantage is "don't have to set up
systemd for Mastery backend," which is a 30-minute mirror of the
LevelChannel pattern.

The rest of this runbook assumes **Option B**. If the operator
chooses A, sections §3.3-§3.5 (systemd unit, nginx routing, deploy
flow) are skipped and replaced with a single `DATABASE_URL` flip
plus `pg_hba.conf` + firewall hardening.

## 1. Pre-flight checklist

Before the cutover window opens (target: **2026-05-20**):

- [ ] Operator can SSH the VPS as root via
      `ssh -i ~/.ssh/levelchannel_timeweb_ed25519 root@<host>`.
- [ ] LevelChannel is healthy (`curl http://127.0.0.1:3000/api/health`
      on the box). Cutover should not touch LevelChannel; this is the
      sanity gate that the box is otherwise good.
- [ ] Mastery's GitHub repo is cloneable on the VPS (the box already
      has GitHub credentials for LevelChannel — Mastery is on the same
      `Igotsty1e` org so the same SSH/PAT works).
- [ ] Render dashboard access confirmed; the operator can read the
      current env vars on `srv-d7lmbpfavr4c73elv5n0`.
- [ ] No active production users mid-session (the cutover involves a
      brief API downtime; today's traffic is dev/test so any window
      after-hours ICT is fine).

## 2. Inventory of what moves

### 2.1 Schema (from `backend/src/db/migrate.ts`)

12 migrations, all idempotent (`IF NOT EXISTS`), embedded as inline TS:

| # | id | What it creates |
|---|---|---|
| 0001 | `init` | `users`, `auth_identities`, `auth_sessions`, `user_profiles`, `audit_events`, `integration_events` + indexes |
| 0002 | `lesson_sessions` | `lesson_sessions`, `exercise_attempts`, `lesson_progress` + indexes |
| 0003 | `attempt_idempotency` | `exercise_attempts.client_attempt_id` + partial unique idx |
| 0004 | `attempt_review_snapshot` | `prompt_snapshot`, `explanation_snapshot` columns |
| 0005 | `learner_state` | `learner_skills`, `learner_review_schedule` + indexes |
| 0006 | `observability_v1` | `decision_log`, `exercise_stats`, `friction_event` column |
| 0007 | `mastery_v1` | mastery counter columns on `learner_skills` |
| 0008 | `dynamic_sessions` | sentinel-id-aware unique index on `lesson_sessions` |
| 0009 | `diagnostic_runs` | placement-probe table + active-run partial unique idx |
| 0010 | `feedback_responses` | feedback-prompt outcome table |
| 0011 | `ui_language` | `user_profiles.ui_language` + CHECK constraint |
| 0012 | `analytics_events` | analytics event log |

`pgcrypto` extension is created at the top of `runMigrations` for
`gen_random_uuid()` on Postgres < 13 (no-op on newer). PGlite path
skips it. The migration runner uses a `_migrations` tracking table.

### 2.2 No data carry-over

Per the decision in `~/.claude/projects/<slug>/memory/postgres-free-expiry.md`,
the current Render Postgres holds dev/test rows only. The cutover is
a **fresh DB** — `pg_dump`/`pg_restore` is intentionally not used.
Acceptable because:
- Apple Sign-In was never shipped to real users (`apple_stub` rows
  are dev installs).
- Lesson-session / attempt history is dev traffic.
- Learner-state rows are tied to dev users.

If the operator decides to preserve data after all, a `pg_dump`
between §3.2 (DB exists) and §3.3 (backend points at new DB) is the
insertion point; the migration script is a superset of any older
schema, so `pg_restore --data-only` against the freshly-migrated DB
should work cleanly. **Out of scope for this runbook.**

### 2.3 Env vars to carry over

From `srv-d7lmbpfavr4c73elv5n0` (Render), inventory expected:

| Var | Notes |
|---|---|
| `DATABASE_URL` | flipped (will point at the new VPS Postgres) |
| `AUTH_SECRET` | **carry as-is** — sessions issued under the old key keep working until they expire (30-day refresh window) |
| `GOOGLE_STUB_ENABLED` | carry as-is (`=1` to keep the stub login route registered in production) |
| `AI_PROVIDER` | carry as-is (`openai` in prod) |
| `OPENAI_API_KEY` | carry as-is |
| `OPENAI_MODEL` | carry as-is (`gpt-4o`) |
| `OPENAI_BASE_URL` | carry if set; otherwise default applies |
| `NODE_ENV` | set to `production` on the systemd unit |
| `PORT` | new — `3001` so `:3000` stays free for LevelChannel |
| `ADMIN_USER_IDS` | carry as-is if set |
| `PUBLIC_WEB_ORIGIN` | **set to the public web URL** — used by CORS allowlist (`backend/src/app.ts:46`). After cutover the public web is still served from Render static site at `https://mastery-web-igotsty1e.onrender.com`, so this value stays the same |
| `ALLOWED_ORIGINS` | comma-separated CORS allowlist override; carry as-is if set |

`APPLE_STUB_ENABLED` (legacy) — **drop**. Per the post-merge note on
PR #69, it's still set on Render as dead metadata. Decommissioning
the Render service decommissions it implicitly.

## 3. Cutover sequence (Option B)

### 3.1 Provision Postgres role + database on VPS

SSH the VPS. As `postgres` user (or via `sudo -u postgres`):

```sh
psql <<'SQL'
CREATE ROLE mastery_app LOGIN PASSWORD '<generate strong password>';
CREATE DATABASE mastery_prod OWNER mastery_app;
\c mastery_prod
-- pgcrypto must be created here (as postgres superuser) because the
-- migration runner also tries to create it on every boot; running
-- as the unprivileged `mastery_app` role that boot-time call would
-- fail without superuser. Pre-creation makes the runner's
-- `CREATE EXTENSION IF NOT EXISTS pgcrypto` a no-op.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
GRANT CONNECT ON DATABASE mastery_prod TO mastery_app;
GRANT USAGE ON SCHEMA public TO mastery_app;
-- PG15+ revokes CREATE on public schema by default; this restores it
-- so the migration runner can create tables under mastery_app.
GRANT CREATE ON SCHEMA public TO mastery_app;
SQL
```

Save the password to `/etc/mastery.env` (next step). Confirm:

```sh
PGPASSWORD='<pw>' psql -h 127.0.0.1 -U mastery_app -d mastery_prod -c 'SELECT 1;'
```

### 3.2 Clone Mastery repo + install + run migrations

Mirror the LevelChannel pattern. Create a system user `mastery`
(parallel to `levelchannel`) so the systemd unit + filesystem
ownership stay clean:

```sh
useradd --system --shell /usr/sbin/nologin --home-dir /var/www/mastery --create-home mastery
chown mastery:mastery /var/www/mastery
# Clone the working tree INTO /var/www/mastery so the path is
# stable: /var/www/mastery/backend/dist/server.js is what systemd
# launches.
sudo -u mastery git clone https://github.com/Igotsty1e/Mastery.git /var/www/mastery
cd /var/www/mastery
sudo -u mastery git checkout main
cd backend
sudo -u mastery npm install --include=dev
sudo -u mastery npm run build
```

(All subsequent `sudo -u <unix-user>` invocations below use this
`mastery` user. The `<unix-user>` placeholder in code blocks is
intentional so the operator can swap names if `mastery` is already
taken.)

**`useradd --create-home` gotcha:** the flag also `chown`s the home
directory. If `useradd` already ran and created the directory, the
subsequent `git clone` into a non-empty directory will fail. If
that happens, `rm -rf /var/www/mastery/{.,}*` before the clone (or
clone into `/tmp/mastery-clone` and `mv`).

Create `/etc/mastery.env`:

```
NODE_ENV=production
DATABASE_URL=postgres://mastery_app:<pw>@127.0.0.1:5432/mastery_prod
AUTH_SECRET=<copy from Render>
GOOGLE_STUB_ENABLED=1
AI_PROVIDER=openai
OPENAI_API_KEY=<copy from Render>
OPENAI_MODEL=gpt-4o
ADMIN_USER_IDS=<copy from Render if set>
PORT=3001
PUBLIC_WEB_ORIGIN=https://mastery-web-igotsty1e.onrender.com
# ALLOWED_ORIGINS only if set on Render (comma-separated)
```

Permissions: `chown root:<unix-user>` and `chmod 640`.

Run migrations explicitly (the server runs them on boot too, but we
want a clean separate gate before flipping the public DNS). The
backend exports `createDatabase` from `dist/db/client.js`:

```sh
cd /var/www/mastery/backend
sudo -u <unix-user> sh -c 'set -a; . /etc/mastery.env; set +a; node -e "
  Promise.all([
    import(\"./dist/db/client.js\"),
    import(\"./dist/db/migrate.js\"),
  ]).then(async ([client, migrate]) => {
    const db = await client.createDatabase();
    await migrate.runMigrations(db);
    console.log(\"migrations applied\");
    await db.close();
    process.exit(0);
  }).catch((e) => { console.error(e); process.exit(1); });
"'
```

Alternative for operator simplicity: just start the systemd unit
(§3.3) — the backend runs migrations on its first boot via the
same `runMigrations` call inside the app bootstrap. The explicit
run above is a pre-flight safety so any migration failure surfaces
before the service tries to serve traffic.

Verify:

```sh
PGPASSWORD='<pw>' psql -h 127.0.0.1 -U mastery_app -d mastery_prod -c '\dt'
PGPASSWORD='<pw>' psql -h 127.0.0.1 -U mastery_app -d mastery_prod -c 'SELECT id FROM _migrations ORDER BY id;'
```

Expect all 12 migration ids present, all tables created.

### 3.3 Create the systemd unit

`/etc/systemd/system/mastery.service`:

```ini
[Unit]
Description=Mastery backend
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=<unix-user>
WorkingDirectory=/var/www/mastery/backend
EnvironmentFile=/etc/mastery.env
ExecStart=/usr/bin/node dist/server.js
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```sh
systemctl daemon-reload
systemctl enable mastery.service
systemctl start mastery.service
systemctl status mastery.service
journalctl -u mastery.service -n 50 --no-pager
```

Verify the service is listening:

```sh
curl -s http://127.0.0.1:3001/health
```

Expect `{"status":"ok"}` or equivalent.

### 3.4 Expose via nginx

The VPS already has nginx in front for `levelchannel.ru`. Add a
server block for the Mastery API host. The simplest path: a new
subdomain like `api.mastery.<your-domain>` pointing at the VPS IP
(operator configures DNS), with TLS via certbot + nginx.

Skeleton (adapt to actual domain + TLS setup):

```nginx
server {
    listen 443 ssl http2;
    server_name api.mastery.<your-domain>;

    # TLS via certbot — same pattern as LevelChannel.
    ssl_certificate     /etc/letsencrypt/live/api.mastery.<domain>/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.mastery.<domain>/privkey.pem;

    location / {
        proxy_pass         http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto https;
    }
}
```

`nginx -t && systemctl reload nginx`. Confirm:

```sh
curl -s https://api.mastery.<domain>/health
```

### 3.5 Repoint the public web bundle

The static-site Render service builds the Flutter web bundle with
`API_BASE_URL` baked in at build time. Flip the env var in the
Render static-site dashboard:

```
API_BASE_URL=https://api.mastery.<your-domain>
```

Trigger a redeploy. Once it goes live, the public web build talks
to the VPS backend.

### 3.6 Smoke

From an outside terminal (not the VPS):

```sh
BASE=https://api.mastery.<your-domain>
curl -s $BASE/health
LOGIN=$(curl -s -X POST $BASE/auth/google/stub/login \
  -H 'Content-Type: application/json' \
  -d '{"subject":"vps-cutover-smoke-001"}')
TOKEN=$(echo $LOGIN | jq -r '.accessToken')
curl -s -X POST $BASE/diagnostic/start -H "Authorization: Bearer $TOKEN" | jq
curl -s -X POST $BASE/sessions/start -H "Authorization: Bearer $TOKEN" | jq '.session_id, .next_exercise.type'
```

Expect: `/health` 200, login 200 with `user.id`, diagnostic 201
with first item, dynamic session start 200 with `next_exercise`.

### 3.7 Decommission Render Postgres

**Only after** §3.6 is green and the public web (browser-tested) is
healthy on the new backend.

1. On Render dashboard, **suspend** (not delete) the Render web
   service `mastery-backend-igotsty1e`. Keeps the env vars and
   service ID available in case rollback is needed.
2. Wait 24h. Confirm no live traffic regression on the VPS.
3. **Delete** the Render Postgres `dpg-d7ngmh37uimc73bd2eig-a` and
   the suspended web service. Note: deletion is irreversible; the
   24h soak is the safety margin.

## 4. Rollback procedure

If §3.6 smoke fails or post-deploy issues surface within 24h:

1. **Revert DNS / API_BASE_URL** — flip the static-site env var
   back to the original Render backend URL
   (`https://mastery-backend-igotsty1e.onrender.com`); trigger
   redeploy. Public web bundles re-pin to Render.
2. **Un-suspend** the Render service if §3.7 step 1 has run.
3. **Investigate** on VPS side without time pressure. The VPS
   service stays up but unused; the original Render service +
   Render Postgres are now the live path again.
4. **Postgres free-tier expiry still applies** — fix the VPS path
   before 2026-05-27 or the rollback ends in data loss anyway.

The cutover should be staged so it can be paused at any point
without breaking the live path:
- §3.1-§3.4 are VPS-side only; Render keeps serving.
- §3.5 is the live-traffic flip; **this is the only step that
  affects the live path.** Test the new endpoint via §3.6 before
  doing 3.5.
- §3.7 is irreversible; defer until the operator is confident.

## 5. Post-cutover follow-ups

- Update `~/.claude/projects/-Users-ivankhanaev-Mastery/memory/postgres-free-expiry.md` — mark deadline closed, mention the new VPS topology.
- Update `~/.claude/projects/-Users-ivankhanaev-Mastery/memory/levelchannel-deploy.md` — add the Mastery section now that the VPS hosts both projects.
- Update `CLAUDE.md §Deploy Configuration` to mention the dual-project VPS topology (without leaking secrets).
- Decide on a deploy flow: today LevelChannel deploys via
  `git fetch && git reset --hard origin/main && npm install && npm run build && systemctl restart`. Mirror that for Mastery — add a `scripts/deploy-vps.sh` if useful, or leave manual.
- Consider running both DBs on a single Postgres cluster (today already true — `127.0.0.1:5432` serves both `levelchannel` and `mastery_prod`). Resource ceiling on the VPS: confirm RAM + disk margin is fine for two app schemas + two app processes.

## 6. Out of scope

- Migrating data from Render Postgres to VPS Postgres (intentional —
  see §2.2). If product reality changes and there are real users to
  preserve, add a §2.4 `pg_dump`/`pg_restore` step here.
- Switching the Mastery static web bundle off Render (it's free,
  pulls from `main` automatically, and there's no win in self-
  hosting it).
- Adding observability/monitoring to the VPS systemd unit beyond
  `journalctl`. Separate runbook.
- High-availability / replication on the VPS Postgres. Out of scope
  for the MVP cutover; single-instance + nightly logical backup is
  the operational baseline.
