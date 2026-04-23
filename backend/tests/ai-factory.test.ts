import { describe, it, expect, vi, afterEach } from 'vitest';
import { createAiProviderFromEnv } from '../src/ai/factory';
import { StubAiProvider } from '../src/ai/stub';
import { OpenAiProvider } from '../src/ai/openai';

afterEach(() => {
  delete process.env.AI_PROVIDER;
  delete process.env.OPENAI_API_KEY;
  delete process.env.OPENAI_MODEL;
  delete process.env.OPENAI_BASE_URL;
});

describe('createAiProviderFromEnv', () => {
  it('returns StubAiProvider by default (no env vars)', () => {
    const p = createAiProviderFromEnv();
    expect(p).toBeInstanceOf(StubAiProvider);
  });

  it('returns StubAiProvider when AI_PROVIDER=stub', () => {
    process.env.AI_PROVIDER = 'stub';
    const p = createAiProviderFromEnv();
    expect(p).toBeInstanceOf(StubAiProvider);
  });

  it('returns StubAiProvider and warns when AI_PROVIDER=openai but no key', () => {
    process.env.AI_PROVIDER = 'openai';
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const p = createAiProviderFromEnv();
    expect(p).toBeInstanceOf(StubAiProvider);
    expect(warn).toHaveBeenCalledOnce();
    expect(warn.mock.calls[0][0]).toMatch(/OPENAI_API_KEY/);
    warn.mockRestore();
  });

  it('returns OpenAiProvider when AI_PROVIDER=openai and key is set', () => {
    process.env.AI_PROVIDER = 'openai';
    process.env.OPENAI_API_KEY = 'sk-test-key';
    const p = createAiProviderFromEnv();
    expect(p).toBeInstanceOf(OpenAiProvider);
  });

  it('ignores blank OPENAI_API_KEY and falls back to stub', () => {
    process.env.AI_PROVIDER = 'openai';
    process.env.OPENAI_API_KEY = '   ';
    const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    const p = createAiProviderFromEnv();
    expect(p).toBeInstanceOf(StubAiProvider);
    warn.mockRestore();
  });
});
