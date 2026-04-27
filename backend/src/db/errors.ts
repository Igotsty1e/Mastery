// Cross-driver error classifiers. Both `pg` (production) and `pglite`
// (tests / dev) surface PostgreSQL SQLSTATE codes on thrown errors via the
// `code` property — `23505` is unique_violation. Service code uses these to
// distinguish a genuine race against a unique index from any other DB
// failure, instead of swallowing every error from a write path.

export function isUniqueViolation(err: unknown): boolean {
  if (!err || typeof err !== 'object') return false;
  const code = (err as { code?: unknown }).code;
  return code === '23505';
}
