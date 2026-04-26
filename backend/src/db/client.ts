import { drizzle as drizzlePglite } from 'drizzle-orm/pglite';
import { drizzle as drizzlePg } from 'drizzle-orm/node-postgres';
import { PGlite } from '@electric-sql/pglite';
import type { PgDatabase, PgQueryResultHKT } from 'drizzle-orm/pg-core';
import type { ExtractTablesWithRelations } from 'drizzle-orm';
import pg from 'pg';
import * as schema from './schema';

type Schema = typeof schema;
// Both NodePgDatabase and PgliteDatabase extend PgDatabase. Using the
// parent shape lets routes/services accept either driver without TS
// collapsing the union to "no compatible overload".
export type AppDatabase = PgDatabase<
  PgQueryResultHKT,
  Schema,
  ExtractTablesWithRelations<Schema>
>;

export interface Database {
  orm: AppDatabase;
  exec(sql: string): Promise<void>;
  query<T = Record<string, unknown>>(sql: string): Promise<T[]>;
  close(): Promise<void>;
  /** Diagnostic — which driver is active. */
  driver: 'pglite' | 'pg';
}

export interface CreateDatabaseOptions {
  /** Postgres connection string. Falls back to DATABASE_URL env var. */
  url?: string;
  /**
   * Force the in-memory pglite driver regardless of env. Used by tests so
   * that each suite gets a fresh isolated database.
   */
  forceMemory?: boolean;
}

export async function createDatabase(
  opts: CreateDatabaseOptions = {}
): Promise<Database> {
  const url = opts.forceMemory ? undefined : opts.url ?? process.env.DATABASE_URL;

  if (url) {
    const pool = new pg.Pool({ connectionString: url });
    const orm = drizzlePg(pool, { schema });
    return {
      orm,
      driver: 'pg',
      exec: async (sql: string) => {
        await pool.query(sql);
      },
      query: async <T,>(sql: string) => {
        const r = await pool.query(sql);
        return r.rows as T[];
      },
      close: async () => {
        await pool.end();
      },
    };
  }

  const pglite = new PGlite();
  await pglite.waitReady;
  const orm = drizzlePglite(pglite, { schema });
  return {
    orm,
    driver: 'pglite',
    exec: async (sql: string) => {
      await pglite.exec(sql);
    },
    query: async <T,>(sql: string) => {
      const r = await pglite.query<T>(sql);
      return r.rows as T[];
    },
    close: async () => {
      await pglite.close();
    },
  };
}
