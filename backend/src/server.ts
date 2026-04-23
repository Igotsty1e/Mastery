import { createApp } from './app';
import { createAiProviderFromEnv } from './ai/factory';

const PORT = process.env.PORT ? parseInt(process.env.PORT) : 3000;
const ai = createAiProviderFromEnv();
const app = createApp(ai);

app.listen(PORT, () => {
  console.log(`mastery-backend listening on :${PORT}`);
});
