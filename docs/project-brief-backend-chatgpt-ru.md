# Mastery — подробный бриф проекта для отдельного чата про backend

Этот файл нужен как стартовый контекст для отдельного разговора с ChatGPT на телефоне, чтобы обсуждать архитектуру бэкенда параллельно с основной работой в репозитории.

## 1. Что это за продукт

`Mastery` — мобильное приложение для спокойной, структурированной практики английской грамматики.

Основная идея продукта:

- один урок = одно грамматическое правило
- короткое объяснение правила
- затем серия целевых упражнений
- после каждого ответа пользователь сразу получает проверку
- в конце урока видит аккуратный summary с ошибками и коротким debrief

Это не Duolingo-клон и не чат-репетитор.

Осознанно исключено:

- streaks
- badges
- points
- social/feed механики
- chat UI
- adaptive branching
- шумная геймификация

Продуктовая тональность: взрослый, спокойный, премиальный grammar coach.

## 2. Текущий статус проекта

Состояние на `2026-04-26`:

- дизайн-система и HTML mockups проработаны
- Flutter-клиент существует
- backend существует и уже реализует API для уроков, проверки ответов, summary/debrief и auth foundation
- auth foundation на backend уже shipped
- Flutter-клиент пока не подключён к auth flow
- прогресс уроков и last lesson report пока не имеют полноценной серверной персистентности уровня production user history

Ключевая особенность проекта: backend считается педагогическим источником истины. Именно сервер решает:

- что считается правильным ответом
- какой canonical answer возвращать
- какое explanation отдавать
- когда нужен AI fallback, а когда нет

## 3. Основной пользовательский flow

Текущий основной flow выглядит так:

1. Пользователь попадает на onboarding/home.
2. Видит следующий урок на dashboard.
3. Открывает lesson intro.
4. Проходит фиксированную линейную последовательность упражнений.
5. После каждого ответа получает моментальную проверку.
6. В конце получает итоговый summary:
   - score
   - mistakes review
   - short debrief
7. Возвращается на dashboard.

Flow намеренно линейный:

- без ветвления
- без пропуска шагов
- без “choose your own path”
- без чата

## 4. Что уже видно по дизайну и макетам

Mockups лежат в `docs/design-mockups/`.

Они показывают уже зафиксированные экраны:

- onboarding
- dashboard/home
- lesson intro
- exercise active
- exercise result reveal
- fill-in-the-blank
- sentence correction
- summary
- dashboard study desk v2

Из этих макетов следует важная backend-картина:

- у урока есть `level`, `title`, `intro_rule`, `intro_examples`
- у урока есть фиксированный массив упражнений
- у каждого упражнения есть тип и своя схема данных
- на summary нужно показывать не только score, но и список ошибок с правильным ответом и объяснением
- dashboard в перспективе должен уметь показывать persistent `last lesson report`

Важно: сейчас часть dashboard-memory логики уже есть в продуктовой идее, но полноценная серверная persistence-модель для “истории последнего урока” ещё не доведена до конца.

## 5. Текущий backend stack

Backend находится в `backend/`.

Текущий стек:

- `Node.js`
- `TypeScript`
- `Express`
- `Zod` для схем
- `Drizzle ORM`
- `Postgres-compatible storage`
- `pg` для production
- `@electric-sql/pglite` для local dev / tests
- `OpenAI Responses API` для ограниченного AI-поведения

Скрипты и tooling:

- `npm run dev`
- `npm run build`
- `npm start`
- `npm test`
- `npm run gen:audio`
- `npm run gen:image`

## 6. Что backend уже умеет

### Lessons API

Сейчас backend имеет минимум такие endpoints:

- `GET /health`
- `GET /lessons`
- `GET /lessons/:lessonId`
- `POST /lessons/:lessonId/answers`
- `GET /lessons/:lessonId/result`

Что важно:

- backend скрывает “секреты” lesson fixture от клиента
- accepted answers / correct options не отдаются на клиент
- explanation возвращается только как часть результата проверки

### Auth / identity foundation

Уже есть foundation для авторизации и identity:

- `POST /auth/apple/stub/login`
- `POST /auth/refresh`
- `POST /auth/logout`
- `POST /auth/logout-all`
- `GET /me`
- `PATCH /me/profile`
- `DELETE /me`

Но это важно понимать правильно:

- backend foundation готов
- Flutter-клиент пока к этому не подключён
- текущий UX приложения по сути ещё живёт в почти-anonymous mode

### Static assets

Backend уже раздаёт:

- `/audio/...` для listening exercises
- `/images/...` для visual context layer

Оба типа ассетов предполагают offline generation и long-lived immutable caching.

## 7. Текущая модель lesson content

Lesson fixtures лежат в `backend/data/lessons/*.json`.

Примерно у lesson есть поля:

- `lesson_id`
- `title`
- `language`
- `level`
- `intro_rule`
- `intro_examples`
- `exercises`

Поддерживаемые типы упражнений сейчас:

- `fill_blank`
- `multiple_choice`
- `sentence_correction`
- `listening_discrimination`

Типы и их смысл:

- `fill_blank`: детерминированная проверка по нормализованному ответу
- `multiple_choice`: детерминированная проверка по `option_id`
- `sentence_correction`: сначала deterministic gate, затем при некоторых пограничных случаях AI fallback
- `listening_discrimination`: выбор правильного варианта на основе аудио и transcript

Каждое упражнение может содержать:

- instruction
- prompt или audio
- options
- accepted answers / accepted corrections / correct option
- feedback explanation
- optional image

Важно: authoring metadata для image есть внутри lesson schema, но на клиент она не должна уходить.

## 8. Как сейчас устроена проверка ответов

### Детерминированный приоритет

Общий принцип системы:

- сначала deterministic evaluation
- AI используется только там, где это действительно нужно
- AI не должен становиться основным judge-слоем

### По типам

`fill_blank`

- exact-ish match после normalization
- без AI

`multiple_choice`

- сравнение `user_answer` с `correct_option_id`
- без AI

`listening_discrimination`

- тоже полностью deterministic
- без AI

`sentence_correction`

- сначала идёт deterministic comparison
- если deterministic gate не дал уверенного ответа, включается AI fallback
- AI fallback ограничен rate limit-ом и кешируется

### Почему это важно архитектурно

Система строится вокруг идеи:

- deterministic first
- AI as exception layer
- backend remains explainable and testable

То есть проект не хочет зависеть от LLM на каждой проверке ответа.

## 9. Где сейчас используется AI

AI используется только в двух местах:

1. пограничная проверка `sentence_correction`
2. генерация короткого post-lesson debrief

При этом есть важные guardrails:

- есть timeout
- есть fallback copy
- есть кеширование
- есть rate limiting
- perfect-score debrief вообще не требует AI

Идеология проекта:

- AI помогает, но не управляет core loop
- центр системы — структура урока и детерминированные правила

## 10. Текущее хранение данных: что уже persistent, а что ещё нет

### Уже persistent

Через Drizzle/Postgres-compatible слой уже есть таблицы:

- `users`
- `auth_identities`
- `auth_sessions`
- `user_profiles`
- `audit_events`
- `integration_events`

Это уже реальный foundation.

### Пока не доведено до production persistence

Lesson runtime storage всё ещё partly in-memory.

Сейчас в memory store живут:

- lesson attempts
- AI evaluation cache
- debrief cache

Ограничения текущего подхода:

- TTL около 4 часов
- LRU cap
- сброс при рестарте сервера
- не подходит как окончательная модель user learning history

Это прямой архитектурный долг, потому что:

- result и summary пока завязаны на runtime memory
- last lesson report на dashboard требует более надёжной persistence-модели
- будущая история прогресса и resume потребуют нормальных таблиц

## 11. Что уже явно запланировано как следующий backend wave

По текущим планам и документации следующий важный шаг — перенос lesson runtime state в нормальную persistence-модель.

Явно напрашиваются сущности уровня:

- `lesson_sessions`
- `exercise_attempts`
- возможно `lesson_results`
- возможно `user_progress` или агрегаты для dashboard

Также впереди:

- реальный Sign in with Apple вместо stub login
- wiring Flutter-клиента к auth flow
- привязка lesson progress к authenticated user
- настоящая persistence для last lesson report
- multi-lesson / multi-unit progression

## 12. Архитектурные ограничения, которые нельзя ломать

Ниже список принципов, которые для проекта выглядят почти как invariants:

- backend — источник истины для correctness
- клиент не должен знать секретные accepted answers
- lesson flow должен оставаться линейным и предсказуемым
- AI нельзя делать обязательным для каждого ответа
- summary должен быть explainable, не магическим
- продукт не должен превращаться в chat-first experience
- архитектура должна поддерживать adult premium UX, а не growth-hacking loops

## 13. Ключевые backend-задачи, которые сейчас хочется обсудить

Вот список тем, по которым нужен сильный архитектурный разбор:

1. Как правильно спроектировать persistence для lesson runtime:
   - `lesson_sessions`
   - `exercise_attempts`
   - completion state
   - summary snapshots

2. Как связать anonymous / pre-auth flow с будущим authenticated user flow:
   - нужен ли guest session
   - как делать merge после логина
   - надо ли вообще поддерживать pre-auth progress migration

3. Как хранить “last lesson report” так, чтобы dashboard всегда мог его показать:
   - вычислять on read
   - хранить denormalized summary snapshot
   - хранить debrief отдельно или пересобирать

4. Как проектировать idempotency и повторные отправки ответов:
   - повторный submit
   - network retries
   - late responses
   - duplicate attempt handling

5. Как разделить:
   - canonical lesson content
   - runtime attempts
   - aggregated progress
   - cached AI artifacts

6. Как сделать переход от in-memory store к Postgres без болезненной миграции API-контракта.

7. Как лучше строить auth-aware API для Flutter:
   - access token
   - refresh rotation
   - secure mobile storage
   - 401 retry strategy

8. Нужно ли хранить result/debrief как snapshot на момент завершения урока, чтобы UI всегда показывал один и тот же historical report, даже если потом lesson content немного изменится.

## 14. Риски, которые я уже вижу

Вот главные архитектурные риски:

- слишком долго держать learning runtime в memory store
- смешать domain content и runtime progress в одну неаккуратную схему
- слишком рано тащить AI в критический path
- не продумать merge anonymous state и logged-in state
- не решить, summary — это computed view или persisted artifact
- не разделить authoring content, evaluation artifacts и user history

## 15. Мой текущий взгляд на желаемую целевую архитектуру

Это не финальное решение, а рабочая гипотеза.

### Domain layers

Стоит держать как минимум 4 слоя:

1. `content layer`
   - уроки
   - упражнения
   - explanations
   - audio/image metadata

2. `evaluation layer`
   - deterministic evaluators
   - AI fallback orchestration
   - scoring policy

3. `runtime progress layer`
   - lesson sessions
   - exercise attempts
   - completion
   - retry / idempotency

4. `account layer`
   - users
   - identities
   - sessions
   - profile

### Read models

Отдельно, скорее всего, понадобятся read models / projections для:

- dashboard home
- last lesson report
- lesson summary history
- maybe unit progress cards

### AI artifacts

AI лучше рассматривать как отдельный прикладной слой артефактов:

- cached borderline evaluation
- debrief text
- возможно future content QA artifacts

Но не как главный persistence layer продукта.

## 16. Что полезно считать source of truth

Если в отдельном чате будут спрашивать “откуда это взято”, то текущие главные опорные файлы такие:

- `README.md`
- `DESIGN.md`
- `docs/plans/auth-foundation.md`
- `docs/plans/roadmap.md`
- `docs/plans/dashboard-study-desk.md`
- `backend/README.md`
- `backend/src/routes/lessons.ts`
- `backend/src/db/schema.ts`
- `backend/src/store/memory.ts`
- `backend/src/data/lessonSchema.ts`
- `backend/data/lessons/b2-lesson-001.json`

## 17. Готовый промпт для нового чата

Ниже текст, который можно использовать в новом чате как стартовую инструкцию.

---

Ты мой архитектурный советник по backend для проекта `Mastery`.

Контекст проекта:

- `Mastery` — mobile-first приложение для структурированной практики английской грамматики.
- Один урок учит одному правилу.
- Flow линейный: dashboard -> lesson intro -> exercises -> summary.
- Backend — source of truth для correctness, canonical answers и explanations.
- Стек backend: Node.js, TypeScript, Express, Zod, Drizzle ORM, Postgres-compatible storage.
- AI используется ограниченно: только для borderline `sentence_correction` и post-lesson `debrief`.
- Сейчас auth foundation уже реализован, но Flutter client ещё не подключён к нему.
- Сейчас lesson runtime state частично живёт в in-memory store, и это нужно перевести в нормальную persistent architecture.

Что уже есть:

- lesson content в JSON fixtures
- exercise types: `fill_blank`, `multiple_choice`, `sentence_correction`, `listening_discrimination`
- endpoints: `/lessons`, `/lessons/:id`, `/lessons/:id/answers`, `/lessons/:id/result`
- auth endpoints: login/refresh/logout/logout-all/me/profile/delete
- Postgres tables: `users`, `auth_identities`, `auth_sessions`, `user_profiles`, `audit_events`, `integration_events`

Что мне нужно от тебя:

1. Помогай продумывать backend architecture без упрощений.
2. Когда предлагаешь схему, разделяй:
   - content model
   - runtime progress model
   - auth/account model
   - derived read models
3. Всегда учитывай, что backend должен оставаться deterministic-first, а AI — only fallback.
4. Не предлагай chat-first UX и не предлагай превращать продукт в generative tutor.
5. Если обсуждаем таблицы или API, показывай:
   - сущности
   - связи
   - ответственность слоя
   - компромиссы
   - риски миграции
6. Если видишь архитектурный риск или неявную связность, прямо указывай на это.
7. Помогай выбирать между:
   - computed vs persisted summary
   - guest vs auth session model
   - append-only attempts vs mutable lesson session state
   - normalized schema vs denormalized dashboard projections

Начни с того, что предложи 2-3 разумных варианта целевой backend-архитектуры для lesson progress persistence и dashboard last lesson report, с trade-offs.

---

## 18. Как лучше использовать этот файл

Лучший режим работы с отдельным чатом такой:

1. Сначала загрузить этот файл.
2. Потом отдельно задать один узкий вопрос, например:
   - “Спроектируй таблицы для lesson_sessions и exercise_attempts”
   - “Нужен ли summary snapshot или его лучше собирать на лету?”
   - “Как сделать merge guest progress после логина?”
   - “Как спроектировать dashboard last lesson report?”
3. Просить не абстрактные советы, а конкретные варианты схем, API и trade-offs.

Если нужно, этот файл можно дальше дробить на более узкие брифы:

- только auth
- только lesson persistence
- только dashboard projections
- только AI boundary design

