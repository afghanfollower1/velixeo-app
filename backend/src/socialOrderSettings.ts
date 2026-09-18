import { Prisma, PrismaClient } from '@prisma/client';

export type SocialOrderIdMode = 'PROVIDER' | 'SEQUENTIAL';

export type SocialOrderSettings = {
  orderIdMode: SocialOrderIdMode;
  startNumber: number;
  refillWindowHours: number;
  termsFa: string;
  termsEn: string;
};

export const SOCIAL_ORDER_SETTINGS_KEY = 'social.order.settings';

export const DEFAULT_SOCIAL_ORDER_SETTINGS: SocialOrderSettings = {
  orderIdMode: 'SEQUENTIAL',
  startNumber: 100063,
  refillWindowHours: 24,
  termsFa: 'با ثبت سفارش تأیید می‌کنم لینک و تعداد را درست وارد کرده‌ام، از شرایط سرویس آگاه هستم و می‌دانم زمان انجام و قابلیت جبران یا لغو به شرایط همان سرویس و ارائه‌دهنده وابسته است.',
  termsEn: 'By placing this order, I confirm that the link and quantity are correct, I understand the service conditions, and I understand that completion time, refill and cancellation depend on the selected service and provider.',
};

function asObject(value: Prisma.JsonValue | null | undefined): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export async function getSocialOrderSettings(prisma: PrismaClient): Promise<SocialOrderSettings> {
  const row = await prisma.systemSetting.findUnique({ where: { key: SOCIAL_ORDER_SETTINGS_KEY } });
  const value = asObject(row?.value);
  const mode = value.orderIdMode === 'PROVIDER' ? 'PROVIDER' : 'SEQUENTIAL';
  const startRaw = Number(value.startNumber ?? DEFAULT_SOCIAL_ORDER_SETTINGS.startNumber);
  const refillRaw = Number(value.refillWindowHours ?? DEFAULT_SOCIAL_ORDER_SETTINGS.refillWindowHours);
  return {
    orderIdMode: mode,
    startNumber: Number.isSafeInteger(startRaw) && startRaw > 0 ? startRaw : DEFAULT_SOCIAL_ORDER_SETTINGS.startNumber,
    refillWindowHours: Number.isFinite(refillRaw) && refillRaw > 0 && refillRaw <= 720
      ? Math.floor(refillRaw)
      : DEFAULT_SOCIAL_ORDER_SETTINGS.refillWindowHours,
    termsFa: typeof value.termsFa === 'string' && value.termsFa.trim()
      ? value.termsFa.trim()
      : DEFAULT_SOCIAL_ORDER_SETTINGS.termsFa,
    termsEn: typeof value.termsEn === 'string' && value.termsEn.trim()
      ? value.termsEn.trim()
      : DEFAULT_SOCIAL_ORDER_SETTINGS.termsEn,
  };
}

export async function saveSocialOrderSettings(
  prisma: PrismaClient,
  settings: SocialOrderSettings,
) {
  const clean: SocialOrderSettings = {
    orderIdMode: settings.orderIdMode === 'PROVIDER' ? 'PROVIDER' : 'SEQUENTIAL',
    startNumber: Math.max(1, Math.trunc(settings.startNumber)),
    refillWindowHours: Math.max(1, Math.min(720, Math.trunc(settings.refillWindowHours))),
    termsFa: settings.termsFa.trim() || DEFAULT_SOCIAL_ORDER_SETTINGS.termsFa,
    termsEn: settings.termsEn.trim() || DEFAULT_SOCIAL_ORDER_SETTINGS.termsEn,
  };
  await prisma.systemSetting.upsert({
    where: { key: SOCIAL_ORDER_SETTINGS_KEY },
    create: {
      key: SOCIAL_ORDER_SETTINGS_KEY,
      category: 'social-order',
      description: 'Customer-facing social order ID, terms and refill window settings.',
      value: clean as unknown as Prisma.InputJsonValue,
    },
    update: {
      category: 'social-order',
      value: clean as unknown as Prisma.InputJsonValue,
    },
  });
  return clean;
}
