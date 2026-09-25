import type { Prisma } from '@prisma/client';

export type ProviderStartEta = {
  text: string;
  minMinutes: number | null;
  maxMinutes: number | null;
  source: 'field' | 'name';
};

export type ProviderAverageEta = {
  text: string;
  minMinutes: number | null;
  maxMinutes: number | null;
  source: 'provider';
};

function jsonObject(value: Prisma.JsonValue | null | undefined): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function unitMinutes(unitRaw: string) {
  const unit = unitRaw.trim().toLowerCase();
  if (/^(m|min|mins|minute|minutes)$/.test(unit)) return 1;
  if (/^(h|hr|hrs|hour|hours)$/.test(unit)) return 60;
  if (/^(d|day|days)$/.test(unit)) return 1440;
  return null;
}

export function parseEtaMinutes(textRaw: string) {
  const text = textRaw.trim();
  if (!text || /^(not enough data|n\/a|na|unknown|—|-)$/i.test(text)) {
    return { minMinutes: null, maxMinutes: null };
  }
  if (/^(instant|instantly|immediate|immediately|now)$/i.test(text)) {
    return { minMinutes: 0, maxMinutes: 0 };
  }

  const range = text.match(/(\d+(?:\.\d+)?)\s*(?:-|–|—|to)\s*(\d+(?:\.\d+)?)\s*(m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)\b/i);
  if (range) {
    const multiplier = unitMinutes(range[3] ?? '');
    if (multiplier != null) {
      return {
        minMinutes: Math.round(Number(range[1]) * multiplier),
        maxMinutes: Math.round(Number(range[2]) * multiplier),
      };
    }
  }

  // Provider panels often return compound live averages such as
  // "1 hour 22 minutes" or "2 days 3 hours". Preserve the whole value.
  let totalMinutes = 0;
  let matchedCompound = false;
  const compound = /(\d+(?:\.\d+)?)\s*(d|day|days|h|hr|hrs|hour|hours|m|min|mins|minute|minutes)\b/gi;
  for (const match of text.matchAll(compound)) {
    const multiplier = unitMinutes(match[2] ?? '');
    if (multiplier == null) continue;
    totalMinutes += Number(match[1]) * multiplier;
    matchedCompound = true;
  }
  if (matchedCompound && Number.isFinite(totalMinutes)) {
    const minutes = Math.round(totalMinutes);
    return { minMinutes: minutes, maxMinutes: minutes };
  }

  return { minMinutes: null, maxMinutes: null };
}

function startCandidateFromFields(row: Record<string, unknown>) {
  const keys = [
    '_providerStartTimeText',
    'start_time',
    'startTime',
    'estimated_start_time',
    'estimatedStartTime',
    'estimated_time',
    'estimatedTime',
  ];
  for (const key of keys) {
    const value = row[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return null;
}

function averageCandidateFromFields(row: Record<string, unknown>) {
  const keys = [
    '_providerAverageTimeText',
    'average_time',
    'averageTime',
    'avg_time',
    'avgTime',
    'average_delivery_time',
    'averageDeliveryTime',
    'average_completion_time',
    'averageCompletionTime',
  ];
  for (const key of keys) {
    const value = row[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return null;
}

function candidateFromName(name: string) {
  const match = name.match(/\[\s*(?:start\s*time|start)\s*:\s*([^\]]+)\]/i);
  return match?.[1]?.trim() || null;
}

export function providerAverageEtaFromMetadata(
  value: Prisma.JsonValue | null | undefined,
): ProviderAverageEta | null {
  const row = jsonObject(value);
  const text = averageCandidateFromFields(row);
  if (!text) return null;
  const parsed = parseEtaMinutes(text);
  return { text, ...parsed, source: 'provider' };
}

export function providerStartEtaFromMetadata(
  value: Prisma.JsonValue | null | undefined,
  fallbackName?: string | null,
): ProviderStartEta | null {
  const row = jsonObject(value);
  const fromField = startCandidateFromFields(row);
  if (fromField) {
    const parsed = parseEtaMinutes(fromField);
    return { text: fromField, ...parsed, source: 'field' };
  }

  const names = [
    typeof row.name === 'string' ? row.name : null,
    typeof row.service_name === 'string' ? row.service_name : null,
    typeof row.serviceName === 'string' ? row.serviceName : null,
    fallbackName ?? null,
  ].filter((item): item is string => Boolean(item?.trim()));

  for (const name of names) {
    const text = candidateFromName(name);
    if (!text) continue;
    const parsed = parseEtaMinutes(text);
    return { text, ...parsed, source: 'name' };
  }

  return null;
}
