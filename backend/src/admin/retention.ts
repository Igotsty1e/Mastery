import { sql } from 'drizzle-orm';
import type { AppDatabase } from '../db/client';

/// Wave 14.1 — D1/D7 cohort retention.
///
/// Definition:
///   - `cohort_day` = UTC calendar day of `users.created_at`.
///   - `cohort_size` = number of distinct users that signed up that day.
///   - `d1_active` = number of those users with at least one
///     `exercise_attempts` row submitted on `cohort_day + 1`.
///   - `d7_active` = same window for `cohort_day + 7`.
///
/// We use `exercise_attempts.submitted_at` (the wall-clock at submit
/// time) rather than `created_at` — `submitted_at` matches the user's
/// real activity moment and is what the engine writes.
///
/// Cohorts whose Dn window has not closed yet are NOT excluded. The
/// SQL just returns 0 for the not-yet-active count and lets the caller
/// decide whether to show "n/a" — the dashboard adds an `is_complete`
/// flag based on `now`.
///
/// Reads are bounded by `windowDays` (default 30) to keep the page
/// fast on a Postgres without aggressive partitioning. Older cohorts
/// are still queryable by raising the window.

export interface CohortRow {
  cohortDay: string; // ISO 'YYYY-MM-DD'
  cohortSize: number;
  d1Active: number;
  d7Active: number;
  d1Rate: number | null; // 0..1, null when cohortSize == 0
  d7Rate: number | null;
  d1Complete: boolean; // true when cohort_day + 1d <= now
  d7Complete: boolean;
}

export interface RetentionOptions {
  /// Cohorts to include, counting back from `now`. Default 30.
  windowDays?: number;
  /// Reference point for cohort completeness flags. Defaults to wall
  /// clock; tests inject a fixed UTC instant.
  now?: Date;
}

interface RawRow extends Record<string, unknown> {
  cohort_day: string | Date;
  cohort_size: string | number;
  d1_active: string | number;
  d7_active: string | number;
}

function toIsoDay(value: string | Date): string {
  if (value instanceof Date) {
    return value.toISOString().slice(0, 10);
  }
  // Postgres returns 'YYYY-MM-DD' for ::date casts; pg-mem can return
  // the full timestamp string. Normalise.
  return value.slice(0, 10);
}

function toInt(value: string | number): number {
  return typeof value === 'string' ? Number.parseInt(value, 10) : value;
}

function dayDiff(later: Date, earlier: Date): number {
  const ms = later.getTime() - earlier.getTime();
  return Math.floor(ms / 86_400_000);
}

export async function cohortRetention(
  db: AppDatabase,
  opts: RetentionOptions = {}
): Promise<CohortRow[]> {
  const windowDays = opts.windowDays ?? 30;
  const nowUtc = opts.now ?? new Date();

  // Use raw SQL: the cohort + lateral joins are easier to reason about
  // here than driving them through Drizzle's relational helpers, and
  // the result shape is small + stable.
  const result = await db.execute<RawRow>(sql`
    WITH cohort AS (
      SELECT
        u.id AS user_id,
        (u.created_at AT TIME ZONE 'UTC')::date AS cohort_day
      FROM users u
      WHERE u.created_at >= NOW() - (${windowDays}::int + 8) * INTERVAL '1 day'
    ),
    activity AS (
      SELECT
        a.user_id,
        (a.submitted_at AT TIME ZONE 'UTC')::date AS activity_day
      FROM exercise_attempts a
      GROUP BY a.user_id, (a.submitted_at AT TIME ZONE 'UTC')::date
    )
    SELECT
      c.cohort_day::text AS cohort_day,
      COUNT(DISTINCT c.user_id) AS cohort_size,
      COUNT(DISTINCT CASE
        WHEN a.activity_day = c.cohort_day + INTERVAL '1 day'
        THEN c.user_id END) AS d1_active,
      COUNT(DISTINCT CASE
        WHEN a.activity_day = c.cohort_day + INTERVAL '7 day'
        THEN c.user_id END) AS d7_active
    FROM cohort c
    LEFT JOIN activity a ON a.user_id = c.user_id
    WHERE c.cohort_day >= (NOW() AT TIME ZONE 'UTC')::date
                          - ${windowDays}::int * INTERVAL '1 day'
    GROUP BY c.cohort_day
    ORDER BY c.cohort_day DESC
  `);

  // Drizzle's pg driver returns `{ rows: [...] }`; pg-mem returns the
  // array directly. Normalise either shape.
  const rows: RawRow[] = Array.isArray(result)
    ? (result as RawRow[])
    : ((result as { rows: RawRow[] }).rows ?? []);

  const today = new Date(
    Date.UTC(
      nowUtc.getUTCFullYear(),
      nowUtc.getUTCMonth(),
      nowUtc.getUTCDate()
    )
  );

  return rows.map((r): CohortRow => {
    const cohortDayIso = toIsoDay(r.cohort_day);
    const cohortDay = new Date(`${cohortDayIso}T00:00:00.000Z`);
    const cohortSize = toInt(r.cohort_size);
    const d1Active = toInt(r.d1_active);
    const d7Active = toInt(r.d7_active);
    const ageDays = dayDiff(today, cohortDay);
    return {
      cohortDay: cohortDayIso,
      cohortSize,
      d1Active,
      d7Active,
      d1Rate: cohortSize === 0 ? null : d1Active / cohortSize,
      d7Rate: cohortSize === 0 ? null : d7Active / cohortSize,
      d1Complete: ageDays >= 2,
      d7Complete: ageDays >= 8,
    };
  });
}
