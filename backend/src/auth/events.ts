import type { AppDatabase } from '../db/client';
import { auditEvents, integrationEvents } from '../db/schema';

export interface AuditEventInput {
  userId?: string | null;
  eventType: string;
  payload?: Record<string, unknown>;
}

export async function logAuditEvent(
  db: AppDatabase,
  input: AuditEventInput
): Promise<void> {
  await db.insert(auditEvents).values({
    userId: input.userId ?? null,
    eventType: input.eventType,
    payload: input.payload ?? {},
  });
}

export interface IntegrationEventInput {
  source: string;
  eventType: string;
  externalId?: string | null;
  payload?: Record<string, unknown>;
  processedAt?: Date | null;
}

export async function recordIntegrationEvent(
  db: AppDatabase,
  input: IntegrationEventInput
): Promise<void> {
  await db.insert(integrationEvents).values({
    source: input.source,
    eventType: input.eventType,
    externalId: input.externalId ?? null,
    payload: input.payload ?? {},
    processedAt: input.processedAt ?? null,
  });
}
