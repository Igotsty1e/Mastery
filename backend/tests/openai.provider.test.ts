import { describe, it, expect } from 'vitest';
import { extractOutputText, OpenAiProvider } from '../src/ai/openai';

describe('extractOutputText', () => {
  it('reads output_text when present', () => {
    const r = extractOutputText({ output_text: '{"correct":true,"feedback":""}' });
    expect(r).toEqual({ text: '{"correct":true,"feedback":""}', refusal: null });
  });

  it('reads output message content parts', () => {
    const r = extractOutputText({
      output: [
        {
          type: 'message',
          role: 'assistant',
          content: [
            { type: 'output_text', text: '{"correct":false,"feedback":"No."}' },
          ],
        },
      ],
    });
    expect(r.text).toBe('{"correct":false,"feedback":"No."}');
    expect(r.refusal).toBeNull();
  });

  it('captures refusal content', () => {
    const r = extractOutputText({
      output: [
        {
          type: 'message',
          role: 'assistant',
          content: [{ type: 'refusal', refusal: 'No' }],
        },
      ],
    });
    expect(r.refusal).toBe('No');
  });

  it('returns empty text for non-object input', () => {
    expect(extractOutputText(null)).toEqual({ text: '', refusal: null });
    expect(extractOutputText(undefined)).toEqual({ text: '', refusal: null });
    expect(extractOutputText('raw string')).toEqual({ text: '', refusal: null });
  });

  it('returns empty text when output array has no message items', () => {
    const r = extractOutputText({ output: [{ type: 'other' }] });
    expect(r.text).toBe('');
    expect(r.refusal).toBeNull();
  });
});

describe('OpenAiProvider.evaluateSentenceCorrection', () => {
  it('throws on empty response body (no output text)', async () => {
    const provider = new OpenAiProvider({ apiKey: 'sk-test', model: 'gpt-4o-mini' });
    // Patch fetch to return a response with no output content
    const mockFetch = async () => ({
      ok: true,
      json: async () => ({ output: [] }),
    });
    const origFetch = globalThis.fetch;
    globalThis.fetch = mockFetch as any;
    try {
      await expect(
        provider.evaluateSentenceCorrection({
          exercisePrompt: 'Fix this.',
          acceptedCorrections: ['Fixed.'],
          userAnswer: 'fixed',
        })
      ).rejects.toThrow('empty response body');
    } finally {
      globalThis.fetch = origFetch;
    }
  });

  it('throws on non-ok HTTP response', async () => {
    const provider = new OpenAiProvider({ apiKey: 'sk-test', model: 'gpt-4o-mini' });
    const mockFetch = async () => ({ ok: false, status: 429, statusText: 'Too Many Requests' });
    const origFetch = globalThis.fetch;
    globalThis.fetch = mockFetch as any;
    try {
      await expect(
        provider.evaluateSentenceCorrection({
          exercisePrompt: 'Fix this.',
          acceptedCorrections: ['Fixed.'],
          userAnswer: 'fixed',
        })
      ).rejects.toThrow('429');
    } finally {
      globalThis.fetch = origFetch;
    }
  });
});

