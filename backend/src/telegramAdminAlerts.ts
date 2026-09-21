import type { PrismaClient } from '@prisma/client';

type PremiumAlertSettings = {
  enabled: boolean;
  chatId: string;
  tokenConfigured: boolean;
};

function objectValue(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export async function premiumTelegramSettings(prisma: PrismaClient): Promise<PremiumAlertSettings> {
  const row = await prisma.systemSetting.findUnique({ where: { key: 'premium.telegram.admin' } });
  const value = objectValue(row?.value);
  const token = process.env.PREMIUM_TELEGRAM_BOT_TOKEN?.trim() || '';
  const chatId = String(value.chatId ?? process.env.PREMIUM_TELEGRAM_CHAT_ID ?? '').trim();
  return {
    enabled: value.enabled !== false,
    chatId,
    tokenConfigured: token.length > 20,
  };
}

export async function savePremiumTelegramSettings(
  prisma: PrismaClient,
  input: { enabled: boolean; chatId: string },
) {
  const value = {
    enabled: input.enabled,
    chatId: input.chatId.trim(),
  };
  await prisma.systemSetting.upsert({
    where: { key: 'premium.telegram.admin' },
    create: {
      key: 'premium.telegram.admin',
      category: 'premium',
      description: 'Telegram chat used for paid Premium order alerts. Bot token stays in Railway environment.',
      value,
    },
    update: {
      category: 'premium',
      description: 'Telegram chat used for paid Premium order alerts. Bot token stays in Railway environment.',
      value,
    },
  });
  return value;
}

export async function sendPremiumTelegramMessage(
  prisma: PrismaClient,
  message: string,
) {
  const settings = await premiumTelegramSettings(prisma);
  if (!settings.enabled) return { configured: false, sent: false, reason: 'disabled' };
  const token = process.env.PREMIUM_TELEGRAM_BOT_TOKEN?.trim() || '';
  if (!settings.tokenConfigured || !settings.chatId) {
    return { configured: false, sent: false, reason: 'missing_configuration' };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        chat_id: settings.chatId,
        text: message.slice(0, 3900),
        disable_web_page_preview: true,
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      const text = (await response.text()).slice(0, 500);
      throw new Error(`telegram_http_${response.status}:${text}`);
    }
    return { configured: true, sent: true, reason: null };
  } finally {
    clearTimeout(timeout);
  }
}

export function premiumPaidOrderTelegramText(input: {
  orderId: string;
  publicOrderNumber?: string | null;
  customer: string;
  customerContact: string;
  product: string;
  packageTitle: string;
  amountAfn: string;
  deliveryHours: number;
  fields: Array<{ label: string; value: string }>;
}) {
  const id = input.publicOrderNumber || input.orderId.slice(0, 8);
  const details = input.fields.length
    ? input.fields.map((field) => `• ${field.label}: ${field.value}`).join('\n')
    : '• No extra customer fields';

  return [
    '🔔 VELIXEO — Paid Premium Order',
    '',
    `Invoice: #${id}`,
    `Customer: ${input.customer}`,
    `Contact: ${input.customerContact || '—'}`,
    `Service: ${input.product}`,
    `Package: ${input.packageTitle}`,
    `Paid: ${input.amountAfn} AFN`,
    `Delivery target: up to ${input.deliveryHours} hour(s)`,
    '',
    'Customer details:',
    details,
    '',
    '✅ Wallet payment completed before this alert was sent.',
  ].join('\n');
}
