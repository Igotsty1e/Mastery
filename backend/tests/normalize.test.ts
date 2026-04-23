import { describe, it, expect } from 'vitest';
import { normalize } from '../src/evaluators/normalize';

describe('normalize', () => {
  it('exact match passthrough', () => expect(normalize('walks')).toBe('walks'));
  it('trims whitespace', () => expect(normalize('  walks  ')).toBe('walks'));
  it('lowercases', () => expect(normalize('Walks')).toBe('walks'));
  it('strips trailing period', () => expect(normalize('walks.')).toBe('walks'));
  it('strips trailing exclamation', () => expect(normalize('Hello, world!')).toBe('hello, world'));
  it('collapses internal spaces', () => expect(normalize('hello   world')).toBe('hello world'));
  it('preserves mid-word apostrophe', () => expect(normalize("don't")).toBe("don't"));
  it('preserves leading ellipsis', () => expect(normalize('...hello')).toBe('...hello'));
  it('strips trailing dots', () => expect(normalize('hello...')).toBe('hello'));
  it('NFC normalization', () => expect(normalize('café')).toBe('café'));
  it('tab and newline as whitespace', () => expect(normalize('\twalks\n')).toBe('walks'));
  it("it's a cat", () => expect(normalize("  It's A Cat. ")).toBe("it's a cat"));
  it('smart apostrophe normalized to ASCII apostrophe', () =>
    expect(normalize("it\u2019s fine")).toBe("it's fine"));
  it('strips trailing quote', () => expect(normalize("it's a cat\"")).toBe("it's a cat"));
  it('sentence correction case', () =>
    expect(normalize("She doesn't like coffee.")).toBe("she doesn't like coffee"));
  it('empty string', () => expect(normalize('')).toBe(''));
  it('whitespace only', () => expect(normalize('   ')).toBe(''));
});
