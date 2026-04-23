const BOUNDARY_PUNCT = /[.,!?;:'"]+$/;

export function normalize(input: string): string {
  return input
    .normalize('NFC')
    .trim()
    .replace(/\s+/g, ' ')
    .replace(/[’‘]/g, "'")
    .replace(/[“”]/g, '"')
    .toLowerCase()
    .replace(BOUNDARY_PUNCT, '');
}
