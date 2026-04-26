import { createApp } from './app';
import { createAiProviderFromEnv } from './ai/factory';
import { createDatabase } from './db/client';
import { runMigrations } from './db/migrate';
import { assertAuthSecretConfigured } from './auth/tokens';

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;

async function main() {
  // Fail before listening if production is missing AUTH_SECRET, instead of
  // silently signing tokens with the dev fallback key.
  assertAuthSecretConfigured();
  const ai = createAiProviderFromEnv();
  const database = await createDatabase();
  await runMigrations(database);
  const app = createApp(ai, { db: database.orm });
  app.listen(PORT, () => {
    console.log(
      `mastery-backend listening on :${PORT} (db=${database.driver})`
    );
  });
}

main().catch((err) => {
  console.error('failed to start backend', err);
  process.exit(1);
});
