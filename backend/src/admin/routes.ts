import { Router } from 'express';
import { requireAdmin } from './auth';
import { cohortRetention } from './retention';
import type { AppDatabase } from '../db/client';

/// Wave 14.1 — admin surface for the founder. Currently exposes one
/// resource: the D1/D7 cohort retention table backed by
/// `users.created_at` + `exercise_attempts.submitted_at`.
///
/// All routes are gated by `requireAdmin` (env `ADMIN_USER_IDS`); the
/// dashboard and the JSON endpoint share the same gate. The HTML page
/// is a vanilla `<table>` rendered server-side from the same query —
/// no React, no separate Flutter screen, no auth flow on a separate
/// origin to reason about.
///
/// Why HTML and JSON together: the JSON endpoint is the source of
/// truth and is what scripts / curl / future tooling read; the HTML
/// page exists so the founder can bookmark a single URL on the Render
/// production host and read the table from a phone without juggling
/// jq.

export function makeAdminRouter(db: AppDatabase): Router {
  const router = Router();
  const gate = requireAdmin(db);

  router.get('/admin/retention', gate, async (req, res, next) => {
    try {
      const window = parseWindow(req.query.window);
      const rows = await cohortRetention(db, { windowDays: window });
      res.json({ window_days: window, cohorts: rows });
    } catch (err) {
      next(err);
    }
  });

  router.get('/admin/retention.html', gate, async (req, res, next) => {
    try {
      const window = parseWindow(req.query.window);
      const rows = await cohortRetention(db, { windowDays: window });
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.send(renderRetentionPage(rows, window));
    } catch (err) {
      next(err);
    }
  });

  return router;
}

function parseWindow(raw: unknown): number {
  if (typeof raw !== 'string') return 30;
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n)) return 30;
  return Math.max(1, Math.min(180, n));
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function fmtRate(rate: number | null, complete: boolean): string {
  if (rate === null) return '—';
  const pct = (rate * 100).toFixed(1) + '%';
  return complete ? pct : `<span class="pending">${pct}*</span>`;
}

function renderRetentionPage(
  rows: Awaited<ReturnType<typeof cohortRetention>>,
  windowDays: number
): string {
  const tableRows = rows
    .map((r) => {
      const day = escapeHtml(r.cohortDay);
      const size = r.cohortSize.toString();
      const d1 = `${r.d1Active} / ${r.cohortSize}`;
      const d7 = `${r.d7Active} / ${r.cohortSize}`;
      return `<tr>
  <td>${day}</td>
  <td class="num">${size}</td>
  <td class="num">${d1}</td>
  <td class="num">${fmtRate(r.d1Rate, r.d1Complete)}</td>
  <td class="num">${d7}</td>
  <td class="num">${fmtRate(r.d7Rate, r.d7Complete)}</td>
</tr>`;
    })
    .join('\n');
  const updatedAt = new Date().toISOString();
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mastery — D1/D7 Retention</title>
<style>
  :root {
    --fg: #1a1413;
    --fg-muted: #6c605d;
    --bg: #faf6f3;
    --row: #ffffff;
    --border: #e5dcd6;
    --pending: #c08a3a;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    padding: 32px 20px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
    color: var(--fg);
    background: var(--bg);
  }
  h1 { margin: 0 0 8px; font-size: 22px; }
  .meta { color: var(--fg-muted); font-size: 13px; margin-bottom: 24px; }
  table {
    width: 100%;
    max-width: 760px;
    border-collapse: collapse;
    background: var(--row);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
  }
  th, td {
    padding: 10px 14px;
    text-align: left;
    border-bottom: 1px solid var(--border);
    font-size: 14px;
  }
  th {
    background: #f4ece6;
    font-weight: 600;
    color: var(--fg-muted);
    text-transform: uppercase;
    font-size: 11px;
    letter-spacing: 0.6px;
  }
  td.num { text-align: right; font-variant-numeric: tabular-nums; }
  tr:last-child td { border-bottom: 0; }
  .pending { color: var(--pending); }
  .legend { color: var(--fg-muted); font-size: 12px; margin-top: 12px; max-width: 760px; }
  .empty { padding: 24px; color: var(--fg-muted); font-size: 14px; }
</style>
</head>
<body>
<h1>D1/D7 Retention</h1>
<div class="meta">
  Cohort window: last ${windowDays} days · activity = at least one
  exercise attempt on the target day · updated ${updatedAt}
</div>
${
  rows.length === 0
    ? '<div class="empty">No cohorts in window.</div>'
    : `<table>
<thead>
<tr>
  <th>Cohort day</th>
  <th class="num">Size</th>
  <th class="num">D1 active</th>
  <th class="num">D1 rate</th>
  <th class="num">D7 active</th>
  <th class="num">D7 rate</th>
</tr>
</thead>
<tbody>
${tableRows}
</tbody>
</table>
<div class="legend">
  * = window not closed yet (cohort younger than the Dn boundary).
  Rate is computed against the not-yet-final activity total.
</div>`
}
</body>
</html>`;
}
