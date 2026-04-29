# USER — Mastery project status

> Полный профиль Ивана и стиль работы — в `~/.claude/COMPANY.md`
> (раздел `User profile`, loaded automatically per `~/.claude/CLAUDE.md` bootstrap).
> Этот файл — только Mastery-specific статус и нюансы.

## Текущий статус проекта (на 2026-04-28)

- V1 MVP отгружен: 5 уроков × 10 упражнений = 50 items, 5 скиллов с graph edges, диагностика, Decision Engine с pacing-профилями, MAX_NEW_SKILLS_PER_SESSION cap, Rules card on dashboard, post-mistake "See full rule →" bridge.
- Развёрнут на Render (auto-deploy с `main`).
- Postgres free tier истекает 2026-05-27 — нужно апгрейдить до Basic 256MB ($7/мес) до 2026-05-20.

## Mastery-specific напоминания

- **MVP first.** Простое работающее решение лучше идеального плана. (Общее правило в COMPANY.md, но в Mastery особенно остро — мы строим продукт, не платформу.)
- **Не редизайнить продукт.** Концепция зафиксирована в `CLAUDE.md`, `DESIGN.md`, `GRAM_STRATEGY.md`, `LEARNING_ENGINE.md`. AI исполняет, не предлагает альтернативные направления.
- **Документация — часть фичи.** Каждая шипнутая фича обновляет затронутые `.md` файлы в той же сессии — Mastery doc layout (canon/contracts/plans/authoring/refs/history) описан в `CLAUDE.md § Documentation Maintenance`.

Tone reference, language preference, default execution mode — все общие правила в `~/.claude/COMPANY.md`.
