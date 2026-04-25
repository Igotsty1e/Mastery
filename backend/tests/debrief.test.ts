import { describe, it, expect, vi } from 'vitest';
import {
  buildDebrief,
  buildMissedItems,
  fallbackDebrief,
  pickDebriefType,
} from '../src/debrief/debrief';
import type { AiProvider } from '../src/ai/interface';
import type { Lesson } from '../src/data/lessons';
import type { AttemptRecord } from '../src/store/memory';

const LESSON: Lesson = {
  lesson_id: 'a1b2c3d4-0001-4000-8000-000000000001',
  title: 'Present Perfect: Continuous vs Simple',
  language: 'en',
  level: 'B2',
  intro_rule:
    'Use the continuous form (been + verb-ing) for duration. Use the simple form for completed results.',
  intro_examples: ['I have been working all morning.', 'I have finished the report.'],
  exercises: [
    {
      exercise_id: 'ex-1',
      type: 'fill_blank',
      instruction: 'Fill the gap.',
      prompt: 'I ___ here for five years.',
      accepted_answers: ['have been working'],
      feedback: {
        explanation:
          'You wrote a simpler form, but the correct answer is "have been working" because the action started five years ago and continues now.',
      },
    },
    {
      exercise_id: 'ex-2',
      type: 'multiple_choice',
      instruction: 'Choose one.',
      prompt: 'Look — I ___ all the dishes.',
      options: [
        { id: 'a', text: 'have washed' },
        { id: 'b', text: 'have been washing' },
      ],
      correct_option_id: 'a',
      feedback: {
        explanation:
          'You chose the continuous form, but the correct answer is "have washed" because the focus is the result.',
      },
    },
    {
      exercise_id: 'ex-3',
      type: 'fill_blank',
      instruction: 'Fill the gap.',
      prompt: 'She ___ since 2020.',
      accepted_answers: ['has been studying'],
      feedback: {
        explanation:
          'The action started in 2020 and is still ongoing, so use "has been studying".',
      },
    },
  ],
};

function attempt(
  exerciseId: string,
  correct: boolean,
  canonical: string
): AttemptRecord {
  return {
    exercise_id: exerciseId,
    correct,
    evaluation_source: 'deterministic',
    feedback: null,
    canonical_answer: canonical,
  };
}

function makeAi(): AiProvider & {
  evaluateSentenceCorrection: ReturnType<typeof vi.fn>;
  generateDebrief: ReturnType<typeof vi.fn>;
} {
  return {
    evaluateSentenceCorrection: vi.fn().mockResolvedValue({ correct: false, feedback: '' }),
    generateDebrief: vi.fn(),
  } as any;
}

describe('pickDebriefType', () => {
  it('strong only at full score', () => {
    expect(pickDebriefType(10, 10)).toBe('strong');
    expect(pickDebriefType(9, 10)).toBe('mixed');
  });
  it('mixed at >=60%', () => {
    expect(pickDebriefType(6, 10)).toBe('mixed');
    expect(pickDebriefType(8, 10)).toBe('mixed');
  });
  it('needs_work below 60%', () => {
    expect(pickDebriefType(5, 10)).toBe('needs_work');
    expect(pickDebriefType(0, 10)).toBe('needs_work');
  });
  it('zero total maps to needs_work', () => {
    expect(pickDebriefType(0, 0)).toBe('needs_work');
  });
});

describe('buildMissedItems', () => {
  it('only includes incorrect attempts that have an explanation', () => {
    const attempts = [
      attempt('ex-1', false, 'have been working'),
      attempt('ex-2', true, 'a'),
      attempt('ex-3', false, 'has been studying'),
    ];
    const missed = buildMissedItems(LESSON, attempts);
    expect(missed).toHaveLength(2);
    expect(missed[0].canonical_answer).toBe('have been working');
    expect(missed[1].canonical_answer).toBe('has been studying');
    expect(missed[0].explanation.length).toBeGreaterThan(0);
  });

  it('skips attempts whose exercise has no feedback explanation', () => {
    const lessonNoFeedback: Lesson = {
      ...LESSON,
      exercises: LESSON.exercises.map(e => ({ ...e, feedback: undefined })),
    };
    const attempts = [attempt('ex-1', false, 'have been working')];
    expect(buildMissedItems(lessonNoFeedback, attempts)).toHaveLength(0);
  });
});

describe('buildDebrief — zero error short-circuit', () => {
  it('does NOT call AI when correct equals total', async () => {
    const ai = makeAi();
    const attempts = [
      attempt('ex-1', true, 'have been working'),
      attempt('ex-2', true, 'a'),
      attempt('ex-3', true, 'has been studying'),
    ];

    const result = await buildDebrief(ai, LESSON, attempts, 3, 3);
    expect(ai.generateDebrief).not.toHaveBeenCalled();
    expect(result.debrief_type).toBe('strong');
    expect(result.source).toBe('deterministic_perfect');
    expect(result.headline.length).toBeGreaterThan(0);
    expect(result.body.length).toBeGreaterThan(0);
    expect(result.body).toContain(LESSON.title);
  });
});

describe('buildDebrief — happy AI path', () => {
  it('returns AI debrief when provider succeeds and fields are valid', async () => {
    const ai = makeAi();
    ai.generateDebrief.mockResolvedValue({
      headline: 'Continuous trips you up',
      body:
        'You picked the simple form when duration was the cue. Reread the rule and watch for "for + period" / "since + point" — those signal continuous.',
      watch_out: 'Cue words first, form second.',
      next_step: 'Redo items below.',
    });

    const attempts = [
      attempt('ex-1', false, 'have been working'),
      attempt('ex-2', true, 'a'),
      attempt('ex-3', false, 'has been studying'),
    ];
    const result = await buildDebrief(ai, LESSON, attempts, 1, 3);

    expect(ai.generateDebrief).toHaveBeenCalledTimes(1);
    expect(result.source).toBe('ai');
    expect(result.debrief_type).toBe('needs_work');
    expect(result.headline).toBe('Continuous trips you up');
    expect(result.watch_out).toBe('Cue words first, form second.');
    expect(result.next_step).toBe('Redo items below.');
  });

  it('passes only canonical_answer + curated explanation to AI (groundedness)', async () => {
    const ai = makeAi();
    ai.generateDebrief.mockResolvedValue({
      headline: 'h',
      body: 'b body text here',
      watch_out: null,
      next_step: null,
    });

    const attempts = [
      attempt('ex-1', false, 'have been working'),
      attempt('ex-3', false, 'has been studying'),
    ];
    await buildDebrief(ai, LESSON, attempts, 0, 3);

    const call = ai.generateDebrief.mock.calls[0][0];
    expect(call.lessonTitle).toBe(LESSON.title);
    expect(call.level).toBe('B2');
    expect(call.targetRule.length).toBeGreaterThan(0);
    expect(call.missedItems).toHaveLength(2);
    // Only the curated fields should reach the model — no raw user-typed text.
    for (const item of call.missedItems) {
      expect(Object.keys(item).sort()).toEqual(
        ['canonical_answer', 'explanation'].sort()
      );
    }
    expect(call.missedItems[0].canonical_answer).toBe('have been working');
  });
});

describe('buildDebrief — failure modes', () => {
  it('falls back deterministically when AI throws (malformed response)', async () => {
    const ai = makeAi();
    ai.generateDebrief.mockRejectedValue(new Error('schema mismatch'));

    const attempts = [attempt('ex-1', false, 'have been working')];
    const result = await buildDebrief(ai, LESSON, attempts, 0, 3);
    expect(result.source).toBe('fallback');
    expect(result.debrief_type).toBe('needs_work');
    expect(result.headline.length).toBeGreaterThan(0);
    expect(result.body.length).toBeGreaterThan(0);
  });

  it('falls back when AI returns empty headline/body', async () => {
    const ai = makeAi();
    ai.generateDebrief.mockResolvedValue({
      headline: '   ',
      body: '',
      watch_out: null,
      next_step: null,
    });
    const attempts = [attempt('ex-1', false, 'have been working')];
    const result = await buildDebrief(ai, LESSON, attempts, 0, 3);
    expect(result.source).toBe('fallback');
  });

  it('falls back deterministically when AI exceeds the timeout', async () => {
    const ai = makeAi();
    let aborted = false;
    ai.generateDebrief.mockImplementation((args: any) => {
      return new Promise((resolve, reject) => {
        // Listen for abort so we can confirm the timeout cancels the call.
        args.signal?.addEventListener('abort', () => {
          aborted = true;
          reject(new Error('aborted'));
        });
        // Resolve after 1s — should be cancelled by the 50ms timeout.
        setTimeout(
          () =>
            resolve({
              headline: 'late',
              body: 'late body',
              watch_out: null,
              next_step: null,
            }),
          1000
        );
      });
    });

    const attempts = [attempt('ex-1', false, 'have been working')];
    const result = await buildDebrief(ai, LESSON, attempts, 0, 3, {
      aiEnabled: true,
      timeoutMs: 50,
    });
    expect(result.source).toBe('fallback');
    expect(aborted).toBe(true);
  });

  it('falls back when AI is disabled (stub provider mode)', async () => {
    const ai = makeAi();
    const attempts = [attempt('ex-1', false, 'have been working')];
    const result = await buildDebrief(ai, LESSON, attempts, 0, 3, {
      aiEnabled: false,
    });
    expect(ai.generateDebrief).not.toHaveBeenCalled();
    expect(result.source).toBe('fallback');
  });
});

describe('fallbackDebrief', () => {
  it('strong fallback references the lesson title', () => {
    const out = fallbackDebrief('strong', 'Articles');
    expect(out.body).toContain('Articles');
    expect(out.debrief_type).toBe('strong');
    expect(out.source).toBe('deterministic_perfect');
  });
  it('mixed and needs_work fallbacks return non-empty body and a tail', () => {
    const m = fallbackDebrief('mixed', 'X');
    const n = fallbackDebrief('needs_work', 'X');
    for (const d of [m, n]) {
      expect(d.headline.length).toBeGreaterThan(0);
      expect(d.body.length).toBeGreaterThan(0);
      expect(d.next_step).toBeTruthy();
    }
  });
});
