import type { AiProvider } from './interface';
import { StubAiProvider } from './stub';
import { OpenAiProvider } from './openai';

type AiProviderKind = 'stub' | 'openai';

function env(name: string): string | null {
  const v = process.env[name];
  return v && v.trim() ? v.trim() : null;
}

export function createAiProviderFromEnv(): AiProvider {
  const kind = (env('AI_PROVIDER') ?? 'stub') as AiProviderKind;
  if (kind !== 'openai') return new StubAiProvider();

  const apiKey = env('OPENAI_API_KEY');
  if (!apiKey) {
    console.warn('[ai] AI_PROVIDER=openai but OPENAI_API_KEY is missing — falling back to stub');
    return new StubAiProvider();
  }

  const model = env('OPENAI_MODEL') ?? 'gpt-4o-mini';
  const baseUrl = env('OPENAI_BASE_URL') ?? undefined;
  return new OpenAiProvider({ apiKey, model, baseUrl });
}

