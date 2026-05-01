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

  // Default bumped 2026-05-01: gpt-4o-mini was too lenient for the
  // short_free_sentence evaluator — prod probes saw it accept
  // gibberish, off-trigger answers, and ungrammatical strings as
  // correct=true even after a step-by-step "default to false"
  // prompt rewrite (see commit adb4dcf). gpt-4o follows the
  // multi-step instructions and rejects the same probes. Operators
  // can still override via OPENAI_MODEL env var (e.g. for
  // gpt-4.1-mini, o3-mini, or a cheaper-but-strict alternative).
  const model = env('OPENAI_MODEL') ?? 'gpt-4o';
  const baseUrl = env('OPENAI_BASE_URL') ?? undefined;
  return new OpenAiProvider({ apiKey, model, baseUrl });
}

