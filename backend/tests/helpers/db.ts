import { createDatabase, type Database } from '../../src/db/client';
import { runMigrations } from '../../src/db/migrate';
import { createApp } from '../../src/app';
import type { AiProvider } from '../../src/ai/interface';
import type { Express } from 'express';

const stubAi: AiProvider = {
  evaluateSentenceCorrection: () =>
    Promise.resolve({ correct: false, feedback: '' }),
};

export interface TestApp {
  app: Express;
  database: Database;
  close: () => Promise<void>;
}

export async function makeTestApp(opts: { ai?: AiProvider } = {}): Promise<TestApp> {
  const database = await createDatabase({ forceMemory: true });
  await runMigrations(database);
  const app = createApp(opts.ai ?? stubAi, { db: database.orm });
  return {
    app,
    database,
    close: () => database.close(),
  };
}
