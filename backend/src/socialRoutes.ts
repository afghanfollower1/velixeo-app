import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  OrderStatus,
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
  WalletEntryType,
  WalletEntryStatus,
} from '@prisma/client';
import { z } from 'zod';
import {
  SmmProviderError,
  type SmmService,
  smmClientForProvider,
} from './smmPanelAdapter.js';
import { claimCoupon, quoteCoupon, releaseCoupon } from './couponPricing.js';
import { loadSocialBrands, normalizeBrandKey } from './socialBrands.js';
import { getSocialOrderSettings } from './socialOrderSettings.js';
import { normalizeCurrencyCode } from './currency.js';
import { sendAdminOrderAlert, sendAdminRefundAlert } from './adminTelegramEvents.js';
import { providerStartEtaFromMetadata } from './socialEta.js';

type AuthenticateHook = (
  request: FastifyRequest,
  reply: FastifyReply,
) => Promise<unknown>;

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};

type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type JwtClaims = { sub: string };
type AnyBody = Record<string, unknown>;

type OrderField = {
  key: string;
  type: 'text' | 'number' | 'multiline' | 'select' | 'date';
  required: boolean;
  labelFa: string;
  labelEn: string;
  hintFa?: string;
  hintEn?: string;
  options?: Array<{ value: string; labelFa: string; labelEn: string }>;
};

const createOrderSchema = z.object({
  serviceId: z.string().uuid(),
  clientRequestId: z.string().uuid(),
  termsAccepted: z.literal(true),
  couponCode: z.string().trim().max(80).optional().nullable(),
  parameters: z.record(
    z.string(),
    z.union([z.string(), z.number(), z.boolean(), z.null()]),
  ),
});

const quoteSchema = z.object({
  serviceId: z.string().uuid(),
  couponCode: z.string().trim().max(80).optional().nullable(),
  parameters: z.record(
    z.string(),
    z.union([z.string(), z.number(), z.boolean(), z.null()]),
  ),
});

const orderParamsSchema = z.object({ id: z.string().uuid() });
const actionParamsSchema = z.object({ id: z.string().uuid(), actionId: z.string().uuid() });

function text(body: AnyBody, key: string) {
  return String(body[key] ?? '').trim();
}

function checked(body: AnyBody, key: string) {
  return body[key] === 'on' || body[key] === 'true' || body[key] === '1';
}

function intOrNull(value: unknown) {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  if (!/^-?\d+$/.test(raw)) throw new Error('INVALID_INTEGER');
  return Number.parseInt(raw, 10);
}

function decimalOrNull(value: unknown) {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  if (!/^\d+(\.\d{1,8})?$/.test(raw)) throw new Error('INVALID_DECIMAL');
  return new Prisma.Decimal(raw);
}

function providerEtaFromMetadata(
  value: Prisma.JsonValue | null | undefined,
  fallbackName?: string | null,
) {
  return providerStartEtaFromMetadata(value, fallbackName)?.text ?? null;
}

function orderDisplayId(order: {
  id: string;
  providerOrderId?: string | null;
  publicOrderNumber?: bigint | null;
  output?: Prisma.JsonValue | null;
}) {
  const output = order.output && typeof order.output === 'object' && !Array.isArray(order.output)
    ? order.output as Record<string, unknown>
    : {};
  const explicit = output.displayOrderId;
  if (typeof explicit === 'string' && explicit.trim()) return explicit.trim();
  if (order.publicOrderNumber != null) return order.publicOrderNumber.toString();
  if (order.providerOrderId?.trim()) return order.providerOrderId.trim();
  return order.id.slice(0, 8);
}

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

function inferPlatform(value: string) {
  const text = value.toLowerCase();
  if (text.includes('instagram') || text.includes(' insta ') || text.startsWith('insta')) return 'INSTAGRAM';
  if (text.includes('facebook') || text.includes(' fb ')) return 'FACEBOOK';
  if (text.includes('tiktok') || text.includes('tik tok')) return 'TIKTOK';
  if (text.includes('youtube') || text.includes('youtu')) return 'YOUTUBE';
  if (text.includes('telegram')) return 'TELEGRAM';
  if (text.includes('twitter') || text.includes(' x ')) return 'X';
  if (text.includes('threads')) return 'THREADS';
  if (text.includes('spotify')) return 'SPOTIFY';
  if (text.includes('soundcloud')) return 'SOUNDCLOUD';
  if (text.includes('linkedin')) return 'LINKEDIN';
  if (text.includes('snapchat')) return 'SNAPCHAT';
  if (text.includes('pinterest')) return 'PINTEREST';
  if (text.includes('discord')) return 'DISCORD';
  return 'OTHER';
}

function inferGroup(value: string) {
  const text = value.toLowerCase();
  if (text.includes('follower') || text.includes('subscriber') || text.includes('member')) return 'FOLLOWERS';
  if (text.includes('like')) return 'LIKES';
  if (text.includes('view') || text.includes('watch')) return 'VIEWS';
  if (text.includes('comment')) return 'COMMENTS';
  if (text.includes('share') || text.includes('repost')) return 'SHARES';
  if (text.includes('save')) return 'SAVES';
  if (text.includes('reach') || text.includes('impression')) return 'REACH';
  if (text.includes('poll') || text.includes('vote')) return 'POLL';
  if (text.includes('traffic')) return 'TRAFFIC';
  return 'OTHER';
}

function defaultPriceUnit(providerType: string) {
  const type = providerType.toLowerCase();
  if (type === 'package' || type.includes('subscription')) return 1;
  return 1000;
}

function orderFields(providerType: string, dripFeedSupported = true): OrderField[] {
  const link: OrderField = {
    key: 'link', type: 'text', required: true,
    labelFa: 'لینک', labelEn: 'Link',
    hintFa: 'لینک صفحه، پست یا محتوا', hintEn: 'Page, post or content URL',
  };
  const quantity: OrderField = {
    key: 'quantity', type: 'number', required: true,
    labelFa: 'تعداد', labelEn: 'Quantity',
  };
  const runs: OrderField = {
    key: 'runs', type: 'number', required: false,
    labelFa: 'تعداد اجرا (Drip-feed)', labelEn: 'Runs (Drip-feed)',
  };
  const interval: OrderField = {
    key: 'interval', type: 'number', required: false,
    labelFa: 'فاصله اجرا به دقیقه', labelEn: 'Interval in minutes',
  };

  switch (providerType.trim().toLowerCase()) {
    case 'package':
      return [link];
    case 'seo':
      return [
        link,
        quantity,
        {
          key: 'keywords', type: 'multiline', required: true,
          labelFa: 'کلمات کلیدی', labelEn: 'Keywords',
          hintFa: 'هر مورد را در یک خط وارد کنید', hintEn: 'One item per line',
        },
      ];
    case 'custom comments':
    case 'custom comments package':
      return [
        link,
        {
          key: 'comments', type: 'multiline', required: true,
          labelFa: 'کامنت‌ها', labelEn: 'Comments',
          hintFa: 'هر کامنت را در یک خط جدا بنویسید؛ تعداد سفارش از تعداد خطوط محاسبه می‌شود', hintEn: 'Enter one comment per line; quantity is calculated from the number of lines',
        },
      ];
    case 'mentions with hashtags':
      return [
        link,
        quantity,
        {
          key: 'usernames', type: 'multiline', required: true,
          labelFa: 'نام‌های کاربری', labelEn: 'Usernames',
          hintFa: 'هر نام کاربری در یک خط', hintEn: 'One username per line',
        },
        {
          key: 'hashtags', type: 'multiline', required: true,
          labelFa: 'هشتگ‌ها', labelEn: 'Hashtags',
          hintFa: 'هر هشتگ در یک خط', hintEn: 'One hashtag per line',
        },
      ];
    case 'mentions custom list':
      return [
        link,
        {
          key: 'usernames', type: 'multiline', required: true,
          labelFa: 'نام‌های کاربری', labelEn: 'Usernames',
          hintFa: 'هر نام کاربری در یک خط', hintEn: 'One username per line',
        },
      ];
    case 'mentions hashtag':
      return [
        link,
        quantity,
        { key: 'hashtag', type: 'text', required: true, labelFa: 'هشتگ', labelEn: 'Hashtag' },
      ];
    case 'mentions user followers':
      return [
        link,
        quantity,
        { key: 'username', type: 'text', required: true, labelFa: 'کاربر مبدا', labelEn: 'Source username / URL' },
      ];
    case 'mentions media likers':
      return [
        link,
        quantity,
        { key: 'media', type: 'text', required: true, labelFa: 'لینک مدیا', labelEn: 'Media URL' },
      ];
    case 'comment likes':
      return [
        link,
        quantity,
        { key: 'username', type: 'text', required: true, labelFa: 'نام صاحب کامنت', labelEn: 'Comment owner username' },
      ];
    case 'poll':
      return [
        link,
        quantity,
        { key: 'answer_number', type: 'number', required: true, labelFa: 'شماره پاسخ', labelEn: 'Answer number' },
      ];
    case 'comment replies':
      return [
        link,
        { key: 'username', type: 'text', required: true, labelFa: 'نام کاربری', labelEn: 'Username' },
        {
          key: 'comments', type: 'multiline', required: true,
          labelFa: 'پاسخ‌ها', labelEn: 'Replies',
          hintFa: 'هر پاسخ را در یک خط جدا بنویسید؛ تعداد سفارش از تعداد خطوط محاسبه می‌شود', hintEn: 'Enter one reply per line; quantity is calculated from the number of lines',
        },
      ];
    case 'invites from groups':
      return [
        link,
        quantity,
        {
          key: 'groups', type: 'multiline', required: true,
          labelFa: 'گروه‌ها', labelEn: 'Groups',
          hintFa: 'هر گروه در یک خط', hintEn: 'One group per line',
        },
      ];
    case 'subscriptions':
      return [
        { key: 'username', type: 'text', required: true, labelFa: 'نام کاربری', labelEn: 'Username' },
        { key: 'min', type: 'number', required: true, labelFa: 'حداقل', labelEn: 'Minimum' },
        { key: 'max', type: 'number', required: true, labelFa: 'حداکثر', labelEn: 'Maximum' },
        { key: 'posts', type: 'number', required: false, labelFa: 'تعداد پست‌های آینده', labelEn: 'Future posts limit' },
        { key: 'old_posts', type: 'number', required: false, labelFa: 'پست‌های قبلی', labelEn: 'Existing posts' },
        {
          key: 'delay', type: 'select', required: true,
          labelFa: 'تاخیر به دقیقه', labelEn: 'Delay in minutes',
          options: [0,5,10,15,20,30,40,50,60,90,120,150,180,210,240,270,300,360,420,480,540,600]
            .map((value) => ({ value: String(value), labelFa: `${value} دقیقه`, labelEn: `${value} min` })),
        },
        { key: 'expiry', type: 'date', required: false, labelFa: 'تاریخ پایان', labelEn: 'Expiry date' },
      ];
    case 'web traffic':
      return [
        link,
        quantity,
        ...(dripFeedSupported ? [runs, interval] : []),
        { key: 'country', type: 'text', required: true, labelFa: 'کشور', labelEn: 'Country' },
        {
          key: 'device', type: 'select', required: true,
          labelFa: 'دستگاه', labelEn: 'Device',
          options: [
            { value: '1', labelFa: 'دسکتاپ', labelEn: 'Desktop' },
            { value: '2', labelFa: 'موبایل Android', labelEn: 'Mobile Android' },
            { value: '3', labelFa: 'موبایل iOS', labelEn: 'Mobile iOS' },
            { value: '4', labelFa: 'موبایل ترکیبی', labelEn: 'Mixed Mobile' },
            { value: '5', labelFa: 'موبایل و دسکتاپ', labelEn: 'Mixed Mobile & Desktop' },
          ],
        },
        {
          key: 'type_of_traffic', type: 'select', required: true,
          labelFa: 'نوع ترافیک', labelEn: 'Traffic type',
          options: [
            { value: '1', labelFa: 'Google Keyword', labelEn: 'Google Keyword' },
            { value: '2', labelFa: 'Custom Referrer', labelEn: 'Custom Referrer' },
            { value: '3', labelFa: 'بدون Referrer', labelEn: 'Blank Referrer' },
          ],
        },
        { key: 'google_keyword', type: 'text', required: false, labelFa: 'Google Keyword', labelEn: 'Google Keyword' },
        { key: 'referring_url', type: 'text', required: false, labelFa: 'Referring URL', labelEn: 'Referring URL' },
      ];
    default:
      return dripFeedSupported ? [link, quantity, runs, interval] : [link, quantity];
  }
}

function normalizeParameters(
  providerType: string,
  raw: Record<string, string | number | boolean | null>,
  dripFeedSupported = true,
) {
  const specs = orderFields(providerType, dripFeedSupported);
  const allowed = new Set(specs.map((field) => field.key));
  const out: Record<string, string | number> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (!allowed.has(key) || value == null || value === '') continue;
    if (typeof value === 'boolean') out[key] = value ? 1 : 0;
    else out[key] = value;
  }
  for (const field of specs) {
    const value = out[field.key];
    if (field.required && (value == null || String(value).trim() === '')) {
      throw new Error(`FIELD_REQUIRED:${field.key}`);
    }
  }

  if (providerType.trim().toLowerCase() === 'web traffic') {
    const trafficType = String(out.type_of_traffic ?? '');
    if (trafficType === '1' && !String(out.google_keyword ?? '').trim()) {
      throw new Error('FIELD_REQUIRED:google_keyword');
    }
    if (trafficType === '2' && !String(out.referring_url ?? '').trim()) {
      throw new Error('FIELD_REQUIRED:referring_url');
    }
  }

  if (out.expiry) {
    const value = String(out.expiry);
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (match) out.expiry = `${match[3]}/${match[2]}/${match[1]}`;
  }
  return out;
}

function linesCount(value: unknown) {
  return String(value ?? '')
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean).length;
}

function positiveInt(value: unknown) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function pricingQuantity(providerType: string, parameters: Record<string, string | number>) {
  switch (providerType.trim().toLowerCase()) {
    case 'package':
      return 1;
    case 'custom comments':
    case 'custom comments package':
    case 'comment replies':
      return linesCount(parameters.comments);
    case 'mentions custom list':
      return linesCount(parameters.usernames);
    case 'subscriptions':
      return positiveInt(parameters.max) ?? 0;
    default:
      return positiveInt(parameters.quantity) ?? 0;
  }
}

function dripFeedRuns(parameters: Record<string, string | number>) {
  return Math.max(1, positiveInt(parameters.runs) ?? 1);
}

function billedQuantity(providerType: string, parameters: Record<string, string | number>) {
  const unitQuantity = pricingQuantity(providerType, parameters);
  const runs = parameters.runs != null ? dripFeedRuns(parameters) : 1;
  return { unitQuantity, runs, totalQuantity: unitQuantity * runs };
}

function ceilDiv(numerator: bigint, denominator: bigint) {
  return (numerator + denominator - 1n) / denominator;
}

function decimalToScaled(value: Prisma.Decimal, scale = 1_000_000n) {
  const text = value.toFixed(6);
  const [whole, fraction = ''] = text.split('.');
  return BigInt(whole) * scale + BigInt((fraction + '000000').slice(0, 6));
}

async function providerRateAfn(
  prisma: PrismaClient,
  route: {
    providerRate: Prisma.Decimal | null;
    providerCurrency: string | null;
    markupPercent: Prisma.Decimal | null;
    provider: { defaultMarkupPercent: Prisma.Decimal };
  },
) {
  if (!route.providerRate) return null;
  const currency = normalizeCurrencyCode(route.providerCurrency || 'USD') || 'USD';
  const rateScaled = decimalToScaled(route.providerRate);
  let afnPerCurrencyScaled = 1_000_000n;
  if (currency !== 'AFN') {
    const exchange = await prisma.exchangeRate.findUnique({ where: { code: currency } });
    if (!exchange) return null;
    afnPerCurrencyScaled = decimalToScaled(exchange.afnPerUnit);
  }
  const rawAfnScaled = ceilDiv(rateScaled * afnPerCurrencyScaled, 1_000_000n);
  const markup = route.markupPercent ?? route.provider.defaultMarkupPercent;
  const markupScaled = decimalToScaled(markup);
  const withMarkupScaled = ceilDiv(
    rawAfnScaled * (100_000_000n + markupScaled),
    100_000_000n,
  );
  return ceilDiv(withMarkupScaled, 1_000_000n);
}

async function customerRateAfn(
  prisma: PrismaClient,
  service: { basePriceAfn: bigint | null },
  route: Parameters<typeof providerRateAfn>[1],
) {
  return service.basePriceAfn ?? providerRateAfn(prisma, route);
}

async function providerCostAfn(
  prisma: PrismaClient,
  route: Parameters<typeof providerRateAfn>[1],
  quantity: number,
  priceUnit: number,
) {
  if (!route.providerRate) return null;
  const currency = normalizeCurrencyCode(route.providerCurrency || 'USD') || 'USD';
  let afnPerCurrencyScaled = 1_000_000n;
  if (currency !== 'AFN') {
    const exchange = await prisma.exchangeRate.findUnique({ where: { code: currency } });
    if (!exchange) return null;
    afnPerCurrencyScaled = decimalToScaled(exchange.afnPerUnit);
  }
  const providerRateScaled = decimalToScaled(route.providerRate);
  const fullScaled = ceilDiv(
    providerRateScaled * afnPerCurrencyScaled * BigInt(quantity),
    1_000_000n * BigInt(Math.max(1, priceUnit)),
  );
  return ceilDiv(fullScaled, 1_000_000n);
}

function mapProviderStatus(raw: string) {
  const value = raw.trim().toLowerCase();
  if (value === 'completed') return OrderStatus.COMPLETED;
  if (value === 'partial') return OrderStatus.PARTIAL;
  if (value === 'canceled' || value === 'cancelled') return OrderStatus.CANCELLED;
  if (value === 'in progress' || value === 'processing' || value === 'inprogress') return OrderStatus.PROCESSING;
  if (value === 'error' || value === 'failed') return OrderStatus.FAILED;
  return OrderStatus.PENDING;
}

function providerRefillAvailableAt(message: string | undefined) {
  if (!message) return null;
  const text = message.toLowerCase();
  let milliseconds = 0;
  const matches = text.matchAll(/(\d+)\s*(day|days|hour|hours|hr|hrs|minute|minutes|min|mins)/g);
  for (const match of matches) {
    const amount = Number.parseInt(match[1] ?? '0', 10);
    const unit = match[2] ?? '';
    if (!Number.isFinite(amount) || amount < 0) continue;
    if (unit.startsWith('day')) milliseconds += amount * 24 * 60 * 60 * 1000;
    else if (unit.startsWith('hour') || unit === 'hr' || unit === 'hrs') milliseconds += amount * 60 * 60 * 1000;
    else milliseconds += amount * 60 * 1000;
  }
  if (milliseconds <= 0) return null;
  return new Date(Date.now() + milliseconds);
}

function providerBool(value: unknown) {
  if (value === true || value === 1) return true;
  const text = String(value ?? '').trim().toLowerCase();
  return ['1','true','yes','on','enabled','available'].includes(text);
}

function providerText(row: Record<string, unknown>, ...keys: string[]) {
  for (const key of keys) {
    const value = row[key];
    if (value != null && String(value).trim()) return String(value).trim();
  }
  return null;
}

function routeDripFeedSupported(route: { metadata?: Prisma.JsonValue | null; providerType?: string | null }) {
  const metadata = route.metadata && typeof route.metadata === 'object' && !Array.isArray(route.metadata)
    ? route.metadata as Record<string, unknown>
    : {};
  if (typeof metadata._velixeoDripFeedOverride === 'boolean') {
    return metadata._velixeoDripFeedOverride;
  }
  if (typeof metadata._providerDripFeedDetected === 'boolean') {
    return metadata._providerDripFeedDetected;
  }
  return providerBool(metadata.dripfeed ?? metadata.drip_feed)
    || String(route.providerType ?? '').trim().toLowerCase() === 'drip-feed';
}

function dripFeedSnapshot(order: {
  status: OrderStatus;
  createdAt: Date;
  quantity: number | null;
  input: Prisma.JsonValue | null;
  output: Prisma.JsonValue | null;
}) {
  const input = order.input && typeof order.input === 'object' && !Array.isArray(order.input)
    ? order.input as Record<string, unknown>
    : {};
  const output = order.output && typeof order.output === 'object' && !Array.isArray(order.output)
    ? order.output as Record<string, unknown>
    : {};
  const params = input.parameters && typeof input.parameters === 'object' && !Array.isArray(input.parameters)
    ? input.parameters as Record<string, unknown>
    : {};
  const runs = Math.max(1, Number(input.runs ?? params.runs ?? 1) || 1);
  const interval = Math.max(0, Number(input.intervalMinutes ?? params.interval ?? 0) || 0);
  const unitQuantity = Math.max(0, Number(input.unitQuantity ?? params.quantity ?? order.quantity ?? 0) || 0);
  const totalQuantity = Math.max(0, Number(input.totalQuantity ?? (unitQuantity * runs)) || 0);
  const isDripFeed = input.dripFeed === true || runs > 1;
  if (!isDripFeed) return null;

  const raw = output.providerRawStatus && typeof output.providerRawStatus === 'object' && !Array.isArray(output.providerRawStatus)
    ? output.providerRawStatus as Record<string, unknown>
    : {};
  const rawStatus = providerText(raw, 'status_name', 'drip_feed_status', 'dripfeed_status');
  const rawRunsCurrent = Number(raw.runs_current ?? raw.current_run ?? raw.run ?? NaN);
  const rawRunsAll = Number(raw.runs_all ?? raw.runs ?? NaN);
  const rawTotal = Number(raw.total_quantity ?? NaN);
  const rawInterval = Number(raw.interval ?? NaN);

  const elapsedMinutes = Math.max(0, (Date.now() - order.createdAt.getTime()) / 60_000);
  const scheduledCurrent = interval > 0
    ? Math.min(runs, Math.max(1, Math.floor(elapsedMinutes / interval) + 1))
    : 1;

  let status = rawStatus;
  if (!status) {
    if (order.status === OrderStatus.CANCELLED || order.status === OrderStatus.FAILED || order.status === OrderStatus.REFUNDED) status = 'Stopped';
    else status = 'Active';
  }

  return {
    status,
    runsCurrent: Number.isFinite(rawRunsCurrent) ? Math.max(0, Math.min(runs, rawRunsCurrent)) : scheduledCurrent,
    runsAll: Number.isFinite(rawRunsAll) ? Math.max(1, rawRunsAll) : runs,
    interval: Number.isFinite(rawInterval) ? Math.max(0, rawInterval) : interval,
    totalQuantity: Number.isFinite(rawTotal) ? Math.max(0, rawTotal) : totalQuantity,
    unitQuantity,
  };
}

function dripFeedRunSnapshots(order: {
  status: OrderStatus;
  createdAt: Date;
  quantity: number | null;
  input: Prisma.JsonValue | null;
  output: Prisma.JsonValue | null;
}) {
  const drip = dripFeedSnapshot(order);
  if (!drip) return [];
  const normalized = String(drip.status ?? '').trim().toLowerCase();
  const finished = ['finished', 'completed', 'complete'].includes(normalized);
  const stopped = ['stopped', 'cancelled', 'canceled', 'failed', 'refunded'].includes(normalized);
  const current = Math.max(0, Math.min(drip.runsAll, drip.runsCurrent));
  const perRun = Math.max(0, drip.unitQuantity);
  const rows = [];
  for (let index = 1; index <= drip.runsAll; index += 1) {
    let status: OrderStatus;
    if (finished) status = OrderStatus.COMPLETED;
    else if (stopped) status = index < current ? OrderStatus.COMPLETED : OrderStatus.CANCELLED;
    else if (index < current) status = OrderStatus.COMPLETED;
    else if (index === current && current > 0) status = OrderStatus.PROCESSING;
    else status = OrderStatus.PENDING;
    rows.push({
      id: `${String((order as any).id ?? 'drip')}:run:${index}`,
      runIndex: index,
      runsAll: drip.runsAll,
      quantity: perRun,
      status,
      scheduledAt: new Date(order.createdAt.getTime() + Math.max(0, index - 1) * drip.interval * 60_000),
    });
  }
  return rows;
}

async function audit(
  prisma: PrismaClient,
  adminId: string,
  action: string,
  entityType: string,
  entityId: string | null,
  summary: string,
  metadata?: Prisma.InputJsonValue,
) {
  await prisma.adminAuditLog.create({
    data: { adminUserId: adminId, action, entityType, entityId, summary, metadata },
  });
}

async function refundOrderAmount(
  prisma: PrismaClient,
  orderId: string,
  userId: string,
  amountAfn: bigint,
  reason: string,
) {
  if (amountAfn <= 0n) return null;
  return prisma.$transaction(
    async (tx) => {
      const key = `order-refund-${orderId}`;
      const existing = await tx.walletEntry.findUnique({ where: { idempotencyKey: key } });
      if (existing) return existing;
      const wallet = await tx.wallet.findUnique({ where: { userId } });
      if (!wallet) throw new Error('WALLET_NOT_FOUND');
      const nextBalance = wallet.balanceAfn + amountAfn;
      await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: nextBalance } });
      return tx.walletEntry.create({
        data: {
          walletId: wallet.id,
          type: WalletEntryType.REFUND,
          status: WalletEntryStatus.COMPLETED,
          amountAfn,
          balanceAfterAfn: nextBalance,
          referenceType: 'ORDER_REFUND',
          referenceId: orderId,
          description: reason,
          idempotencyKey: key,
        },
      });
    },
    { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
  );
}

async function maybeApplyTerminalRefund(
  prisma: PrismaClient,
  order: {
    id: string;
    userId: string;
    quantity: number | null;
    totalAmountAfn: bigint;
  },
  status: OrderStatus,
  remainsRaw: string | undefined,
) {
  if (
    status !== OrderStatus.PARTIAL &&
    status !== OrderStatus.CANCELLED &&
    status !== OrderStatus.FAILED
  ) return null;
  const quantity = order.quantity ?? 0;
  const remains = Math.max(0, Number.parseInt(remainsRaw ?? '', 10) || 0);
  if (quantity <= 0) {
    if (status === OrderStatus.FAILED) {
      return refundOrderAmount(prisma, order.id, order.userId, order.totalAmountAfn, `Social order ${order.id} failed`);
    }
    return null;
  }
  const capped = Math.min(quantity, remains || (status === OrderStatus.FAILED ? quantity : 0));
  if (capped <= 0) return null;
  const amount = (order.totalAmountAfn * BigInt(capped)) / BigInt(quantity);
  return refundOrderAmount(prisma, order.id, order.userId, amount, `Unfulfilled quantity refund for order ${order.id}`);
}

function socialOrderJson(order: any) {
  const output = order.output && typeof order.output === 'object' ? order.output : {};
  const refillAvailableAt = typeof output.refillAvailableAt === 'string'
    ? new Date(output.refillAvailableAt)
    : null;
  const activeRefill = (order.actions ?? []).find((action: any) =>
    action.action === 'REFILL'
    && !['COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED'].includes(String(action.status ?? '').toUpperCase()),
  );
  const refillCheckable = output.refillSupported === true
    && order.status === OrderStatus.COMPLETED
    && !activeRefill;
  const providerRefillReady = output.providerRefillReady === true;
  const canRefill = refillCheckable && (
    providerRefillReady
    || (refillAvailableAt != null
      && !Number.isNaN(refillAvailableAt.getTime())
      && refillAvailableAt.getTime() <= Date.now())
  );
  const dripFeed = dripFeedSnapshot(order);
  return {
    id: order.id,
    displayOrderId: orderDisplayId(order),
    status: order.status,
    quantity: order.quantity,
    totalAmountAfn: order.totalAmountAfn.toString(),
    baseAmountAfn: order.baseAmountAfn.toString(),
    failureReason: order.failureReason,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    completedAt: order.completedAt,
    refillAvailableAt,
    refillAvailabilityMessage: output.refillAvailabilityMessage ?? null,
    refillCheckable,
    canRefill,
    dripFeed,
    dripRuns: dripFeedRunSnapshots(order),
    canCancel: output.cancelSupported === true && (
      dripFeed != null
        ? !['finished', 'completed', 'stopped', 'cancelled', 'canceled', 'failed', 'refunded']
            .includes(String(dripFeed.status ?? '').trim().toLowerCase())
        : ![OrderStatus.COMPLETED, OrderStatus.PARTIAL, OrderStatus.CANCELLED, OrderStatus.FAILED, OrderStatus.REFUNDED].includes(order.status)
    ),
    input: order.input,
    output,
    service: order.service
      ? {
          id: order.service.id,
          titleFa: order.service.titleFa,
          titleEn: order.service.titleEn,
          socialPlatform: order.service.socialPlatform,
          socialGroup: order.service.socialGroup,
          refillDays: order.service.refillDays,
        }
      : null,
    actions: (order.actions ?? []).map((action: any) => ({
      id: action.id,
      action: action.action,
      status: action.status,
      providerReference: action.providerReference,
      response: action.response,
      createdAt: action.createdAt,
      updatedAt: action.updatedAt,
    })),
  };
}

function socialAdminShell(title: string, admin: AdminIdentity, body: string, message?: string) {
  return `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(title)} — VELIXEO</title><style>body{margin:0;background:#F7FBFF;color:#102235;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif}.wrap{max-width:1500px;margin:auto;padding:20px}.top{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.top a{color:#0D6EFD;text-decoration:none}.spacer{flex:1}.card{background:#fff;border:1px solid #DCE8F1;border-radius:18px;padding:16px;margin-top:14px}.grid{display:grid;grid-template-columns:1.2fr .8fr;gap:14px}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:10px}.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.field{margin-top:9px}.field label{display:block;font-size:12px;color:#607487;margin-bottom:5px}.field input,.field select,.field textarea{width:100%;box-sizing:border-box;border:1px solid #DCE8F1;border-radius:11px;padding:10px;background:#fff}.field textarea{min-height:82px}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.btn{border:0;border-radius:10px;padding:10px 14px;background:#0D78C8;color:#fff;font-weight:800;cursor:pointer;text-decoration:none}.ghost{border:1px solid #DCE8F1;border-radius:10px;padding:9px 12px;background:#fff;color:#102235;text-decoration:none}.badge{display:inline-block;padding:4px 8px;border-radius:999px;background:#EDF4F8;font-size:11px}.ok{background:#E7F8F1;color:#0A8B5B}.off{background:#FFF0F0;color:#B33737}.muted{color:#607487;font-size:12px}.table{overflow:auto}.table table{width:100%;border-collapse:collapse;min-width:1050px}th,td{padding:9px;border-bottom:1px solid #EDF3F7;text-align:right;font-size:12px;vertical-align:top}th{color:#607487}.msg{background:#E7F8F1;border:1px solid #C7EFDC;color:#0A8B5B;padding:10px;border-radius:12px;margin-top:12px}.warn{background:#FFF7E8;border:1px solid #FFE3AE;color:#8E5D0C;padding:10px;border-radius:12px}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;direction:ltr;text-align:left}@media(max-width:950px){.grid,.grid2,.grid3{grid-template-columns:1fr}}</style></head><body><main class="wrap"><div class="top"><b style="font-size:22px">VELIXEO • خدمات شبکه‌های اجتماعی</b><span class="spacer"></span><span class="muted">${esc(admin.fullName || admin.email || admin.phone || 'ADMIN')}</span><a class="ghost" href="/admin">مدیریت اصلی</a></div>${message ? `<div class="msg">${esc(message)}</div>` : ''}${body}</main></body></html>`;
}

async function syncProviderServices(prisma: PrismaClient, providerId: string) {
  const provider = await prisma.provider.findFirst({
    where: { id: providerId, kind: ProviderKind.SOCIAL },
  });
  if (!provider) throw new Error('PROVIDER_NOT_FOUND');
  const client = smmClientForProvider(provider);
  const [services, balance] = await Promise.all([
    client.services(),
    client.balance().catch(() => ({ balance: '0', currency: 'USD' })),
  ]);
  const existingRoutes = await prisma.serviceProviderRoute.findMany({
    where: { providerId },
    include: { service: true },
  });
  const byCode = new Map(existingRoutes.map((route) => [route.providerServiceCode, route]));
  let created = 0;
  let updated = 0;
  const now = new Date();

  for (const row of services) {
    const current = byCode.get(row.service);
    const routeData = {
      providerName: row.name,
      providerType: row.type,
      providerCategory: row.category,
      providerRate: new Prisma.Decimal(row.rate || '0'),
      providerCurrency: normalizeCurrencyCode(provider.currencyCode || balance.currency || 'USD') || 'USD',
      providerMinQty: row.min || null,
      providerMaxQty: row.max || null,
      providerRefill: row.refill,
      providerCancel: row.cancel,
      lastSyncedAt: now,
      metadata: row.raw as Prisma.InputJsonValue,
    };
    if (current) {
      await prisma.serviceProviderRoute.update({ where: { id: current.id }, data: routeData });
      updated += 1;
      continue;
    }

    const combined = `${row.category} ${row.name}`;
    const slug = `social-${provider.slug}-${row.service}`.toLowerCase().replace(/[^a-z0-9_-]+/g, '-').slice(0, 180);
    await prisma.service.create({
      data: {
        category: ServiceCategory.SOCIAL,
        slug,
        titleFa: row.name,
        titleEn: row.name,
        descriptionFa: null,
        descriptionEn: null,
        enabled: false,
        featured: false,
        sortOrder: 100,
        basePriceAfn: null,
        priceUnit: defaultPriceUnit(row.type),
        minQty: row.min || null,
        maxQty: row.max || null,
        socialPlatform: inferPlatform(combined),
        socialGroup: inferGroup(combined),
        metadata: {
          source: 'provider_sync',
          providerType: row.type,
          providerCategory: row.category,
          rawCatalog: true,
          pricingMode: 'AUTO_MARKUP',
        },
        routes: {
          create: {
            providerId: provider.id,
            providerServiceCode: row.service,
            enabled: true,
            priority: provider.priority,
            ...routeData,
          },
        },
      },
    });
    created += 1;
  }
  return { created, updated, total: services.length, balance };
}

async function syncSocialOrderRecord(prisma: PrismaClient, order: any) {
  if (!order?.provider || !order.providerOrderId) return null;
  const status = await smmClientForProvider(order.provider).status(order.providerOrderId);
  const providerMappedStatus = mapProviderStatus(status.status);
  let actualCostAfn: bigint | undefined;
  const chargeCurrency = normalizeCurrencyCode(order.provider.currencyCode || status.currency || 'USD') || 'USD';
  if (status.charge) {
    const rate = chargeCurrency === 'AFN'
      ? null
      : await prisma.exchangeRate.findUnique({ where: { code: chargeCurrency } });
    if (chargeCurrency === 'AFN') {
      actualCostAfn = BigInt(Math.ceil(Number(status.charge)));
    } else if (rate) {
      actualCostAfn = BigInt(Math.ceil(Number(status.charge) * Number(rate.afnPerUnit.toString())));
    }
  }
  const currentOutput = order.output && typeof order.output === 'object' && !Array.isArray(order.output)
    ? order.output as Record<string, unknown>
    : {};
  const adminOverride = currentOutput.adminStatusOverride === true;
  const effectiveStatus = adminOverride ? order.status : providerMappedStatus;
  await prisma.order.update({
    where: { id: order.id },
    data: {
      status: effectiveStatus,
      providerCostAfn: actualCostAfn ?? order.providerCostAfn,
      completedAt: !adminOverride && providerMappedStatus === OrderStatus.COMPLETED
        ? (order.completedAt ?? new Date())
        : order.completedAt,
      failureReason: !adminOverride && providerMappedStatus === OrderStatus.FAILED ? status.status : order.failureReason,
      output: {
        ...currentOutput,
        providerStatus: status.status,
        providerMappedStatus,
        providerRawStatus: status.raw as Prisma.InputJsonValue,
        charge: status.charge ?? null,
        startCount: status.startCount ?? null,
        remains: status.remains ?? null,
        providerCurrency: chargeCurrency,
        providerRefillReady: providerBool(status.raw.refill),
        providerCancelReady: providerBool(status.raw.cancel),
        refillAvailabilityMessage: providerText(status.raw, 'refillAvailableTime', 'refill_available_time', 'refill_available'),
        refillAvailableAt: (() => {
          const message = providerText(status.raw, 'refillAvailableTime', 'refill_available_time', 'refill_available');
          const parsed = providerRefillAvailableAt(message ?? undefined);
          return parsed?.toISOString() ?? currentOutput.refillAvailableAt ?? null;
        })(),
        lastStatusSyncAt: new Date().toISOString(),
        lastStatusSyncSource: 'PROVIDER_API',
      },
    },
  });
  if (!adminOverride) {
    await maybeApplyTerminalRefund(prisma, order, providerMappedStatus, status.remains);
  }
  return prisma.order.findUnique({
    where: { id: order.id },
    include: { service: true, provider: true, actions: { orderBy: { createdAt: 'desc' } } },
  });
}

async function syncRefillActionRecord(prisma: PrismaClient, action: any) {
  if (!action?.providerReference || !action.order?.provider) return null;
  const result = await smmClientForProvider(action.order.provider).refillStatus(action.providerReference);
  return prisma.orderActionLog.update({
    where: { id: action.id },
    data: {
      status: result.status.toUpperCase(),
      response: result.raw as Prisma.InputJsonValue,
    },
  });
}

export function registerSocialRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
  resolveAdmin: AdminResolver,
) {
  app.get('/api/v1/social/order-config', async () => {
    const settings = await getSocialOrderSettings(prisma);
    return {
      orderIdMode: settings.orderIdMode,
      termsFa: settings.termsFa,
      termsEn: settings.termsEn,
      refillWindowHours: settings.refillWindowHours,
    };
  });

  app.get('/api/v1/social/catalog', async () => {
    const services = await prisma.service.findMany({
      where: { category: ServiceCategory.SOCIAL, enabled: true },
      include: {
        routes: {
          where: { enabled: true, provider: { enabled: true, kind: ProviderKind.SOCIAL } },
          include: { provider: true },
          orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
        },
      },
      orderBy: [{ socialPlatform: 'asc' }, { socialGroup: 'asc' }, { featured: 'desc' }, { sortOrder: 'asc' }],
    });

    const rows = [];
    for (const service of services) {
      const meta = service.metadata && typeof service.metadata === 'object' && !Array.isArray(service.metadata)
        ? service.metadata as Record<string, unknown>
        : {};
      const addedToVelixeo = meta.addedToVelixeo === true
        || typeof meta.publishedAt === 'string'
        || typeof meta.publishedFromProviderId === 'string';
      if (!addedToVelixeo) continue;
      const route = service.routes[0];
      if (!route) continue;
      const rateAfn = await customerRateAfn(prisma, service, route);
      if (rateAfn == null) continue;
      const providerType = route.providerType || 'Default';
      rows.push({
        id: service.id,
        slug: service.slug,
        titleFa: service.titleFa,
        titleEn: service.titleEn,
        descriptionFa: service.descriptionFa,
        descriptionEn: service.descriptionEn,
        platform: service.socialPlatform || 'OTHER',
        group: service.socialGroup || 'OTHER',
        featured: service.featured,
        sortOrder: service.sortOrder,
        priceRateAfn: rateAfn.toString(),
        priceUnit: service.priceUnit,
        minQty: service.minQty ?? route.providerMinQty,
        maxQty: service.maxQty ?? route.providerMaxQty,
        estimatedMinMinutes: service.estimatedMinMinutes,
        estimatedMaxMinutes: service.estimatedMaxMinutes,
        refillSupported: route.providerRefill,
        cancelSupported: route.providerCancel,
        refillDays: service.refillDays,
        providerEta: providerEtaFromMetadata(route.metadata, route.providerName),
        providerType,
        dripFeedSupported: routeDripFeedSupported(route),
        orderFields: orderFields(providerType, routeDripFeedSupported(route)),
      });
    }
    const [categorySettings, allBrands, catalogSortSetting] = await Promise.all([
      prisma.systemSetting.findMany({
        where: { category: 'social-category' },
        orderBy: { key: 'asc' },
      }),
      loadSocialBrands(prisma),
      prisma.systemSetting.findUnique({ where: { key: 'social.catalog.sort_mode' } }),
    ]);
    const brands = allBrands
      .filter((brand) => brand.enabled)
      .map((brand) => ({
        key: brand.key,
        titleFa: brand.titleFa,
        titleEn: brand.titleEn,
        iconType: brand.iconType,
        iconValue: brand.iconValue,
        sortOrder: brand.sortOrder,
      }));
    const activeBrandKeys = new Set(brands.map((brand) => brand.key));
    const categories = categorySettings.flatMap((setting) => {
      const value = setting.value;
      if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
      const item = value as Record<string, unknown>;
      const slug = typeof item.slug === 'string'
        ? item.slug
        : setting.key.replace(/^social\.category\./, '');
      const platform = normalizeBrandKey(typeof item.platform === 'string' ? item.platform : 'OTHER');
      if (!slug || item.enabled === false || !activeBrandKeys.has(platform)) return [];
      return [{
        slug,
        titleFa: typeof item.titleFa === 'string' ? item.titleFa : slug,
        titleEn: typeof item.titleEn === 'string' ? item.titleEn : slug,
        platform,
        descriptionFa: typeof item.descriptionFa === 'string' ? item.descriptionFa : null,
        descriptionEn: typeof item.descriptionEn === 'string' ? item.descriptionEn : null,
        sortOrder: Number.isFinite(Number(item.sortOrder)) ? Number(item.sortOrder) : 100,
      }];
    }).sort((a, b) => a.sortOrder - b.sortOrder);
    const configuredCategorySlugs = new Set(categorySettings.flatMap((setting) => {
      const value = setting.value;
      if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
      const item = value as Record<string, unknown>;
      const slug = typeof item.slug === 'string'
        ? item.slug
        : setting.key.replace(/^social\.category\./, '');
      return slug ? [slug] : [];
    }));
    const activeCategorySlugs = new Set(categories.map((category) => category.slug));
    const visibleRows = rows.filter((service) =>
      activeBrandKeys.has(normalizeBrandKey(service.platform))
      && (!configuredCategorySlugs.has(service.group) || activeCategorySlugs.has(service.group)),
    );
    const sortValue = catalogSortSetting?.value && typeof catalogSortSetting.value === 'object' && !Array.isArray(catalogSortSetting.value)
      ? catalogSortSetting.value as Record<string, unknown>
      : {};
    const rawSortMode = String(sortValue.mode || 'PRICE_ASC').toUpperCase();
    const sortMode = rawSortMode === 'PRICE_DESC' || rawSortMode === 'MANUAL' ? rawSortMode : 'PRICE_ASC';
    const sortedRows = sortMode === 'MANUAL'
      ? visibleRows
      : [...visibleRows].sort((a, b) => {
          if (a.platform !== b.platform || a.group !== b.group) return 0;
          const ap = Number(a.priceRateAfn);
          const bp = Number(b.priceRateAfn);
          const priceCompare = Number.isFinite(ap) && Number.isFinite(bp) ? ap - bp : 0;
          if (priceCompare !== 0) return sortMode === 'PRICE_DESC' ? -priceCompare : priceCompare;
          return a.sortOrder - b.sortOrder || a.titleFa.localeCompare(b.titleFa);
        });
    return { baseCurrency: 'AFN', sortMode, brands, categories, services: sortedRows };
  });

  app.post('/api/v1/social/quote', { preHandler: authenticate }, async (request, reply) => {
    const parsed = quoteSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const service = await prisma.service.findFirst({
      where: { id: parsed.data.serviceId, category: ServiceCategory.SOCIAL, enabled: true },
      include: {
        routes: {
          where: { enabled: true, provider: { enabled: true, kind: ProviderKind.SOCIAL } },
          include: { provider: true },
          orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
        },
      },
    });
    if (!service || !service.routes[0]) return reply.code(404).send({ error: 'service_unavailable' });
    const route = service.routes[0];
    const providerType = route.providerType || 'Default';
    let parameters: Record<string, string | number>;
    try {
      parameters = normalizeParameters(providerType, parsed.data.parameters, routeDripFeedSupported(route));
    } catch (error) {
      return reply.code(400).send({ error: error instanceof Error ? error.message : 'invalid_parameters' });
    }
    const { unitQuantity, runs, totalQuantity } = billedQuantity(providerType, parameters);
    const minQty = service.minQty ?? route.providerMinQty ?? 1;
    const maxQty = service.maxQty ?? route.providerMaxQty ?? Number.MAX_SAFE_INTEGER;
    if (unitQuantity < minQty || unitQuantity > maxQty) {
      return reply.code(400).send({ error: 'quantity_out_of_range', minQty, maxQty });
    }
    const rateAfn = await customerRateAfn(prisma, service, route);
    if (rateAfn == null) return reply.code(409).send({ error: 'service_price_unavailable' });
    const subtotalAmountAfn = ceilDiv(rateAfn * BigInt(totalQuantity), BigInt(Math.max(1, service.priceUnit)));
    let couponPrice;
    try {
      couponPrice = await quoteCoupon(prisma, parsed.data.couponCode, subtotalAmountAfn);
    } catch (error) {
      const code = error instanceof Error ? error.message.toLowerCase() : 'coupon_invalid';
      return reply.code(409).send({ error: code });
    }
    return {
      quantity: unitQuantity,
      runs,
      totalQuantity,
      rateAfn: rateAfn.toString(),
      priceUnit: service.priceUnit,
      subtotalAmountAfn: couponPrice.subtotalAfn.toString(),
      discountAmountAfn: couponPrice.discountAfn.toString(),
      totalAmountAfn: couponPrice.totalAfn.toString(),
      couponCode: couponPrice.couponCode,
    };
  });

  app.get('/api/v1/social/orders', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const orders = await prisma.order.findMany({
      where: { userId, category: ServiceCategory.SOCIAL },
      include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { orders: orders.map(socialOrderJson) };
  });

  app.post('/api/v1/social/orders', { preHandler: authenticate }, async (request, reply) => {
    const parsed = createOrderSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const orderSettings = await getSocialOrderSettings(prisma);

    const existing = await prisma.order.findUnique({
      where: { clientRequestId: parsed.data.clientRequestId },
      include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
    });
    if (existing) {
      if (existing.userId !== userId) return reply.code(409).send({ error: 'idempotency_conflict' });
      return { order: socialOrderJson(existing), idempotent: true };
    }

    const service = await prisma.service.findFirst({
      where: { id: parsed.data.serviceId, category: ServiceCategory.SOCIAL, enabled: true },
      include: {
        routes: {
          where: { enabled: true, provider: { enabled: true, kind: ProviderKind.SOCIAL } },
          include: { provider: true },
          orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
        },
      },
    });
    if (!service || service.routes.length === 0) return reply.code(404).send({ error: 'service_unavailable' });

    const firstRoute = service.routes[0];
    const providerType = firstRoute.providerType || 'Default';
    let parameters: Record<string, string | number>;
    try {
      parameters = normalizeParameters(providerType, parsed.data.parameters, routeDripFeedSupported(firstRoute));
    } catch (error) {
      return reply.code(400).send({ error: error instanceof Error ? error.message : 'invalid_parameters' });
    }
    const { unitQuantity, runs, totalQuantity } = billedQuantity(providerType, parameters);
    const minQty = service.minQty ?? firstRoute.providerMinQty ?? 1;
    const maxQty = service.maxQty ?? firstRoute.providerMaxQty ?? Number.MAX_SAFE_INTEGER;
    if (unitQuantity < minQty || unitQuantity > maxQty) {
      return reply.code(400).send({ error: 'quantity_out_of_range', minQty, maxQty });
    }
    const customerRate = await customerRateAfn(prisma, service, firstRoute);
    if (customerRate == null) return reply.code(409).send({ error: 'service_price_unavailable' });
    const subtotalAmountAfn = ceilDiv(
      customerRate * BigInt(totalQuantity),
      BigInt(Math.max(1, service.priceUnit)),
    );
    if (subtotalAmountAfn <= 0n) return reply.code(409).send({ error: 'service_price_invalid' });
    let couponPrice;
    try {
      couponPrice = await quoteCoupon(prisma, parsed.data.couponCode, subtotalAmountAfn);
    } catch (error) {
      const code = error instanceof Error ? error.message.toLowerCase() : 'coupon_invalid';
      return reply.code(409).send({ error: code });
    }
    const totalAmountAfn = couponPrice.totalAfn;

    let order;
    try {
      order = await prisma.$transaction(
        async (tx) => {
          const duplicate = await tx.order.findUnique({ where: { clientRequestId: parsed.data.clientRequestId } });
          if (duplicate) return duplicate;
          await claimCoupon(tx, couponPrice);
          const wallet = await tx.wallet.findUnique({ where: { userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');
          if (wallet.balanceAfn < totalAmountAfn) throw new Error('INSUFFICIENT_FUNDS');
          let publicOrderNumber: bigint | null = null;
          if (orderSettings.orderIdMode === 'SEQUENTIAL') {
            await tx.$executeRaw`SELECT pg_advisory_xact_lock(764208315)`;
            const latest = await tx.order.findFirst({
              where: { publicOrderNumber: { not: null } },
              orderBy: { publicOrderNumber: 'desc' },
              select: { publicOrderNumber: true },
            });
            const start = BigInt(orderSettings.startNumber);
            publicOrderNumber = latest?.publicOrderNumber != null && latest.publicOrderNumber >= start
              ? latest.publicOrderNumber + 1n
              : start;
          }
          const created = await tx.order.create({
            data: {
              userId,
              serviceId: service.id,
              category: ServiceCategory.SOCIAL,
              status: OrderStatus.PENDING,
              quantity: totalQuantity,
              baseAmountAfn: customerRate,
              totalAmountAfn,
              publicOrderNumber,
              clientRequestId: parsed.data.clientRequestId,
              input: {
                parameters,
                providerType,
                customerRateAfn: customerRate.toString(),
                priceUnit: service.priceUnit,
                unitQuantity,
                runs,
                intervalMinutes: positiveInt(parameters.interval),
                totalQuantity,
                dripFeed: runs > 1,
                refillDays: service.refillDays,
                termsAccepted: true,
                termsAcceptedAt: new Date().toISOString(),
                couponCode: couponPrice.couponCode,
                couponId: couponPrice.couponId,
                subtotalAmountAfn: couponPrice.subtotalAfn.toString(),
                discountAmountAfn: couponPrice.discountAfn.toString(),
              },
            },
          });
          const nextBalance = wallet.balanceAfn - totalAmountAfn;
          await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: nextBalance } });
          await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.PURCHASE,
              status: WalletEntryStatus.COMPLETED,
              amountAfn: -totalAmountAfn,
              balanceAfterAfn: nextBalance,
              referenceType: 'ORDER_PURCHASE',
              referenceId: created.id,
              description: `Social order ${created.id}`,
              idempotencyKey: `order-purchase-${created.id}`,
            },
          });
          return created;
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (error instanceof Error && error.message === 'INSUFFICIENT_FUNDS') {
        return reply.code(409).send({ error: 'insufficient_funds' });
      }
      throw error;
    }

    try {
      await sendAdminOrderAlert(prisma, order.id, 'Wallet charged; provider submission is starting.');
    } catch (error) {
      request.log.warn({ error, orderId: order.id }, 'admin Telegram social order alert failed');
    }

    if (order.providerOrderId) {
      const hydrated = await prisma.order.findUnique({
        where: { id: order.id }, include: { service: true, actions: true },
      });
      return { order: socialOrderJson(hydrated), idempotent: true };
    }

    let explicitFailure = 'provider_rejected';
    for (const route of service.routes) {
      const candidateType = route.providerType || providerType;
      if (candidateType.toLowerCase() !== providerType.toLowerCase()) continue;
      const expectedCost = await providerCostAfn(prisma, route, totalQuantity, service.priceUnit);
      if (expectedCost != null && expectedCost > subtotalAmountAfn && service.routes.length > 1) continue;
      try {
        const client = smmClientForProvider(route.provider);
        const result = await client.addOrder({
          service: route.providerServiceCode,
          ...parameters,
        });
        order = await prisma.order.update({
          where: { id: order.id },
          data: {
            providerId: route.providerId,
            providerOrderId: result.orderId,
            providerCostAfn: expectedCost,
            status: OrderStatus.PENDING,
            failureReason: null,
            output: {
              providerStatus: 'Pending',
              refillSupported: route.providerRefill,
              cancelSupported: route.providerCancel,
              providerEta: providerEtaFromMetadata(route.metadata, route.providerName),
              refillWindowHours: orderSettings.refillWindowHours,
              displayOrderId: orderSettings.orderIdMode === 'PROVIDER'
                ? result.orderId
                : (order.publicOrderNumber?.toString() ?? order.id.slice(0, 8)),
              providerType: candidateType,
              providerResponse: result.raw as Prisma.InputJsonValue,
            },
            exchangeRateSnapshot: {
              providerCurrency: route.providerCurrency,
              providerRate: route.providerRate?.toString() ?? null,
              expectedProviderCostAfn: expectedCost?.toString() ?? null,
            },
          },
        });
        const hydrated = await prisma.order.findUnique({
          where: { id: order.id },
          include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
        });
        return reply.code(201).send({ order: socialOrderJson(hydrated), idempotent: false });
      } catch (error) {
        if (error instanceof SmmProviderError) {
          explicitFailure = error.providerMessage || error.message;
          if (error.uncertain) {
            await prisma.order.update({
              where: { id: order.id },
              data: {
                providerId: route.providerId,
                status: OrderStatus.PROCESSING,
                failureReason: 'provider_submission_uncertain',
                output: {
                  providerSubmissionUncertain: true,
                  providerMessage: explicitFailure,
                  refillSupported: route.providerRefill,
                  cancelSupported: route.providerCancel,
                  providerEta: providerEtaFromMetadata(route.metadata, route.providerName),
                  refillWindowHours: orderSettings.refillWindowHours,
                  displayOrderId: order.publicOrderNumber?.toString() ?? order.id.slice(0, 8),
                  providerType: candidateType,
                },
              },
            });
            const hydrated = await prisma.order.findUnique({
              where: { id: order.id },
              include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
            });
            return reply.code(202).send({
              order: socialOrderJson(hydrated),
              warning: 'provider_submission_uncertain',
            });
          }
          continue;
        }
        throw error;
      }
    }

    await refundOrderAmount(
      prisma,
      order.id,
      userId,
      totalAmountAfn,
      `Provider rejected social order ${order.id}`,
    );
    await prisma.order.update({
      where: { id: order.id },
      data: { status: OrderStatus.FAILED, failureReason: explicitFailure },
    });
    await releaseCoupon(prisma, couponPrice.couponId);
    const hydrated = await prisma.order.findUnique({
      where: { id: order.id },
      include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
    });
    try {
      await sendAdminRefundAlert(prisma, order.id, explicitFailure);
    } catch (error) {
      request.log.warn({ error, orderId: order.id }, 'admin Telegram social refund alert failed');
    }
    return reply.code(502).send({ error: 'provider_rejected', order: socialOrderJson(hydrated) });
  });

  app.post('/api/v1/social/orders/:id/refresh', { preHandler: authenticate }, async (request, reply) => {
    const params = orderParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: params.data.id, userId, category: ServiceCategory.SOCIAL },
      include: { service: true, provider: true, actions: { orderBy: { createdAt: 'desc' } } },
    });
    if (!order) return reply.code(404).send({ error: 'order_not_found' });
    if (!order.provider || !order.providerOrderId) {
      return reply.code(409).send({ error: 'provider_order_not_available' });
    }
    try {
      const hydrated = await syncSocialOrderRecord(prisma, order);
      return { order: socialOrderJson(hydrated) };
    } catch (error) {
      if (error instanceof SmmProviderError) {
        return reply.code(502).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.post('/api/v1/social/orders/sync', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const active = await prisma.order.findMany({
      where: {
        userId,
        category: ServiceCategory.SOCIAL,
        providerOrderId: { not: null },
        createdAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
        status: { notIn: [OrderStatus.CANCELLED, OrderStatus.FAILED, OrderStatus.REFUNDED] },
      },
      include: { provider: true, service: true, actions: { orderBy: { createdAt: 'desc' } } },
      orderBy: { createdAt: 'desc' },
      take: 25,
    });
    for (const order of active) {
      try { await syncSocialOrderRecord(prisma, order); } catch { /* next order */ }
    }
    const refillActions = await prisma.orderActionLog.findMany({
      where: {
        action: 'REFILL',
        status: { notIn: ['COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED'] },
        order: { userId, category: ServiceCategory.SOCIAL },
      },
      include: { order: { include: { provider: true } } },
      orderBy: { createdAt: 'desc' },
      take: 25,
    });
    for (const action of refillActions) {
      try { await syncRefillActionRecord(prisma, action); } catch { /* next action */ }
    }
    const orders = await prisma.order.findMany({
      where: { userId, category: ServiceCategory.SOCIAL },
      include: { service: true, actions: { orderBy: { createdAt: 'desc' } } },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { orders: orders.map(socialOrderJson), syncedAt: new Date() };
  });

  app.post('/api/v1/social/orders/:id/refill', { preHandler: authenticate }, async (request, reply) => {
    const params = orderParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: params.data.id, userId, category: ServiceCategory.SOCIAL },
      include: {
        provider: true,
        service: true,
        actions: { orderBy: { createdAt: 'desc' } },
      },
    });
    if (!order || !order.provider || !order.providerOrderId) return reply.code(404).send({ error: 'order_not_found' });
    const output = order.output && typeof order.output === 'object'
      ? order.output as Record<string, unknown>
      : {};
    if (output.refillSupported !== true) return reply.code(409).send({ error: 'refill_not_supported' });
    if (order.status !== OrderStatus.COMPLETED || !order.completedAt) {
      return reply.code(409).send({ error: 'refill_not_available' });
    }
    const knownAvailableAt = typeof output.refillAvailableAt === 'string'
      ? new Date(output.refillAvailableAt)
      : null;
    if (knownAvailableAt && !Number.isNaN(knownAvailableAt.getTime()) && knownAvailableAt.getTime() > Date.now()) {
      return reply.code(409).send({
        error: 'refill_not_ready',
        details: output.refillAvailabilityMessage ?? 'Refill is not available yet.',
        availableAt: knownAvailableAt,
      });
    }
    try {
      const result = await smmClientForProvider(order.provider).refill(order.providerOrderId);
      const action = await prisma.orderActionLog.create({
        data: {
          orderId: order.id,
          action: 'REFILL',
          providerReference: result.refillId,
          status: 'PENDING',
          response: result.raw as Prisma.InputJsonValue,
        },
      });
      await prisma.order.update({
        where: { id: order.id },
        data: {
          output: {
            ...output,
            refillAvailableAt: null,
            refillAvailabilityMessage: null,
            lastRefillRequestedAt: new Date().toISOString(),
          },
        },
      });
      return reply.code(201).send({
        action: {
          id: action.id,
          action: action.action,
          status: action.status,
          providerReference: action.providerReference,
          createdAt: action.createdAt,
        },
      });
    } catch (error) {
      if (error instanceof SmmProviderError) {
        const availableAt = providerRefillAvailableAt(error.providerMessage);
        if (availableAt) {
          await prisma.order.update({
            where: { id: order.id },
            data: {
              output: {
                ...output,
                refillAvailableAt: availableAt.toISOString(),
                refillAvailabilityMessage: error.providerMessage ?? 'Refill is not available yet.',
                refillLastCheckedAt: new Date().toISOString(),
              },
            },
          });
          return reply.code(409).send({
            error: 'refill_not_ready',
            details: error.providerMessage,
            availableAt,
          });
        }
        return reply.code(409).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.post('/api/v1/social/orders/:id/actions/:actionId/refresh', { preHandler: authenticate }, async (request, reply) => {
    const params = actionParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const action = await prisma.orderActionLog.findFirst({
      where: { id: params.data.actionId, orderId: params.data.id, order: { userId, category: ServiceCategory.SOCIAL } },
      include: { order: { include: { provider: true } } },
    });
    if (!action || action.action !== 'REFILL' || !action.providerReference || !action.order.provider) {
      return reply.code(404).send({ error: 'refill_not_found' });
    }
    try {
      const result = await smmClientForProvider(action.order.provider).refillStatus(action.providerReference);
      const updated = await prisma.orderActionLog.update({
        where: { id: action.id },
        data: { status: result.status.toUpperCase(), response: result.raw as Prisma.InputJsonValue },
      });
      return { action: { id: updated.id, action: updated.action, status: updated.status, providerReference: updated.providerReference, updatedAt: updated.updatedAt } };
    } catch (error) {
      if (error instanceof SmmProviderError) {
        return reply.code(502).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.post('/api/v1/social/orders/:id/cancel', { preHandler: authenticate }, async (request, reply) => {
    const params = orderParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: params.data.id, userId, category: ServiceCategory.SOCIAL },
      include: { provider: true, service: true, actions: { orderBy: { createdAt: 'desc' } } },
    });
    if (!order || !order.provider || !order.providerOrderId) return reply.code(404).send({ error: 'order_not_found' });
    const output = order.output && typeof order.output === 'object'
      ? order.output as Record<string, unknown>
      : {};
    if (output.cancelSupported !== true) return reply.code(409).send({ error: 'cancel_not_supported' });
    const dripFeed = dripFeedSnapshot(order);
    const dripStatus = String(dripFeed?.status ?? '').trim().toLowerCase();
    const dripTerminal = [
      'finished',
      'completed',
      'complete',
      'stopped',
      'cancelled',
      'canceled',
      'failed',
      'refunded',
    ].includes(dripStatus);
    const normalTerminal =
      order.status === OrderStatus.COMPLETED ||
      order.status === OrderStatus.CANCELLED ||
      order.status === OrderStatus.PARTIAL ||
      order.status === OrderStatus.REFUNDED ||
      order.status === OrderStatus.FAILED;
    // A drip-feed parent can have an underlying order status of COMPLETED after
    // the first child run while the provider master is still Active. In that
    // case the master remains cancellable until the provider reports a terminal
    // drip-feed state.
    if ((dripFeed && dripTerminal) || (!dripFeed && normalTerminal)) {
      return reply.code(409).send({ error: 'order_not_cancellable' });
    }
    try {
      const result = await smmClientForProvider(order.provider).cancel(order.providerOrderId);
      await prisma.orderActionLog.create({
        data: {
          orderId: order.id,
          action: 'CANCEL',
          status: 'ACCEPTED',
          response: result.raw as Prisma.InputJsonValue,
        },
      });
      const currentOutput = order.output && typeof order.output === 'object'
        ? order.output as Record<string, unknown>
        : {};
      await prisma.order.update({
        where: { id: order.id },
        data: { output: { ...currentOutput, cancelRequestedAt: new Date().toISOString() } },
      });
      return { accepted: true };
    } catch (error) {
      if (error instanceof SmmProviderError) {
        return reply.code(409).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  let backgroundSyncRunning = false;
  const socialSyncTimer = setInterval(async () => {
    if (backgroundSyncRunning) return;
    backgroundSyncRunning = true;
    try {
      const activeOrders = await prisma.order.findMany({
        where: {
          category: ServiceCategory.SOCIAL,
          providerOrderId: { not: null },
          createdAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
          status: { notIn: [OrderStatus.CANCELLED, OrderStatus.FAILED, OrderStatus.REFUNDED] },
        },
        include: { provider: true, service: true, actions: { orderBy: { createdAt: 'desc' } } },
        orderBy: { updatedAt: 'asc' },
        take: 60,
      });
      for (const order of activeOrders) {
        try { await syncSocialOrderRecord(prisma, order); } catch { /* provider failure retries next minute */ }
      }

      const refillActions = await prisma.orderActionLog.findMany({
        where: {
          action: 'REFILL',
          status: { notIn: ['COMPLETED', 'REJECTED', 'FAILED', 'CANCELLED'] },
          order: { category: ServiceCategory.SOCIAL },
        },
        include: { order: { include: { provider: true } } },
        orderBy: { updatedAt: 'asc' },
        take: 60,
      });
      for (const action of refillActions) {
        try { await syncRefillActionRecord(prisma, action); } catch { /* retry later */ }
      }
    } finally {
      backgroundSyncRunning = false;
    }
  }, 60_000);
  socialSyncTimer.unref?.();

  app.get('/admin/social-services', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const query = (request.query ?? {}) as Record<string, unknown>;
    const q = String(query.q ?? '').trim();
    const platform = String(query.platform ?? '').trim();
    const editId = String(query.edit ?? '').trim();
    const balanceProviderId = String(query.balance ?? '').trim();
    const where: Prisma.ServiceWhereInput = {
      category: ServiceCategory.SOCIAL,
      ...(platform ? { socialPlatform: platform } : {}),
      ...(q ? {
        OR: [
          { titleFa: { contains: q, mode: 'insensitive' } },
          { titleEn: { contains: q, mode: 'insensitive' } },
          { slug: { contains: q, mode: 'insensitive' } },
        ],
      } : {}),
    };
    const [providers, services, selected] = await Promise.all([
      prisma.provider.findMany({ where: { kind: ProviderKind.SOCIAL }, orderBy: [{ enabled: 'desc' }, { priority: 'asc' }] }),
      prisma.service.findMany({
        where,
        include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } },
        orderBy: [{ socialPlatform: 'asc' }, { socialGroup: 'asc' }, { sortOrder: 'asc' }],
        take: 500,
      }),
      editId ? prisma.service.findUnique({ where: { id: editId }, include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } } }) : Promise.resolve(null),
    ]);
    let balanceMessage = '';
    if (balanceProviderId) {
      const provider = providers.find((item) => item.id === balanceProviderId);
      if (provider) {
        try {
          const balance = await smmClientForProvider(provider).balance();
          balanceMessage = `${provider.name}: ${balance.balance} ${balance.currency}`;
        } catch (error) {
          balanceMessage = error instanceof SmmProviderError
            ? `${provider.name}: ${error.providerMessage || error.message}`
            : `${provider.name}: اتصال ناموفق`;
        }
      }
    }

    const platforms = ['INSTAGRAM','FACEBOOK','TIKTOK','YOUTUBE','TELEGRAM','X','THREADS','SPOTIFY','SOUNDCLOUD','LINKEDIN','SNAPCHAT','PINTEREST','DISCORD','OTHER'];
    const providerCards = providers.map((provider) => `<div class="card"><div class="row"><b>${esc(provider.name)}</b><span class="badge">${esc(provider.slug)}</span><span class="badge ${provider.enabled ? 'ok' : 'off'}">${provider.enabled ? 'فعال' : 'خاموش'}</span><span class="spacer"></span><a class="ghost" href="/admin/social-services?balance=${encodeURIComponent(provider.id)}">Balance</a><form method="post" action="/admin/social-services/sync"><input type="hidden" name="providerId" value="${esc(provider.id)}"><button class="btn" type="submit">Sync Services</button></form></div><div class="muted" style="margin-top:7px">${esc(provider.baseUrl || 'Base URL ثبت نشده')} • API Secret از بخش Provider و API مدیریت می‌شود.</div></div>`).join('');

    const tableRows = services.map((service) => {
      const route = service.routes[0];
      return `<tr><td><b>${esc(service.titleFa)}</b><br><span class="muted">${esc(service.titleEn)}</span><br><span class="mono">${esc(service.slug)}</span></td><td>${esc(service.socialPlatform || 'OTHER')}<br><span class="muted">${esc(service.socialGroup || 'OTHER')}</span></td><td>${service.basePriceAfn == null ? '<span class="badge">Dynamic</span>' : `${esc(service.basePriceAfn)} AFN / ${service.priceUnit}`}</td><td>${esc(service.minQty ?? route?.providerMinQty ?? '—')} – ${esc(service.maxQty ?? route?.providerMaxQty ?? '—')}</td><td>${service.estimatedMinMinutes || service.estimatedMaxMinutes ? `${esc(service.estimatedMinMinutes ?? '—')}–${esc(service.estimatedMaxMinutes ?? '—')} دقیقه` : '—'}</td><td>${route?.providerRefill ? `<span class="badge ok">Refill${service.refillDays ? ` ${service.refillDays}d` : ''}</span>` : '<span class="badge">No refill</span>'}<br>${route?.providerCancel ? '<span class="badge ok">Cancel</span>' : ''}</td><td>${route ? `${esc(route.provider.name)}<br><span class="muted">${esc(route.providerRate?.toString() ?? '—')} ${esc(route.providerCurrency || '')}</span>` : '—'}</td><td><span class="badge ${service.enabled ? 'ok' : 'off'}">${service.enabled ? 'ON' : 'OFF'}</span></td><td><a class="ghost" href="/admin/social-services?edit=${encodeURIComponent(service.id)}">ویرایش</a></td></tr>`;
    }).join('');

    const s = selected;
    const editPanel = s ? `<div class="card"><h3>ویرایش سرویس مشتری</h3><form method="post" action="/admin/social-services/save"><input type="hidden" name="id" value="${esc(s.id)}"><div class="grid2"><div class="field"><label>نام فارسی</label><input name="titleFa" value="${esc(s.titleFa)}" required></div><div class="field"><label>English name</label><input name="titleEn" value="${esc(s.titleEn)}" required></div></div><div class="grid2"><div class="field"><label>Platform</label><select name="socialPlatform">${platforms.map((x) => `<option${x === s.socialPlatform ? ' selected' : ''}>${x}</option>`).join('')}</select></div><div class="field"><label>Group</label><input name="socialGroup" value="${esc(s.socialGroup || 'OTHER')}"></div></div><div class="grid3"><div class="field"><label>قیمت مشتری AFN</label><input name="basePriceAfn" type="number" min="0" value="${esc(s.basePriceAfn?.toString() || '')}" placeholder="خالی = Dynamic"></div><div class="field"><label>واحد قیمت</label><input name="priceUnit" type="number" min="1" value="${esc(s.priceUnit)}"></div><div class="field"><label>ترتیب</label><input name="sortOrder" type="number" value="${esc(s.sortOrder)}"></div></div><div class="grid2"><div class="field"><label>حداقل سفارش مشتری</label><input name="minQty" type="number" min="1" value="${esc(s.minQty ?? '')}"></div><div class="field"><label>حداکثر سفارش مشتری</label><input name="maxQty" type="number" min="1" value="${esc(s.maxQty ?? '')}"></div></div><div class="grid3"><div class="field"><label>زمان تقریبی حداقل (دقیقه)</label><input name="estimatedMinMinutes" type="number" min="0" value="${esc(s.estimatedMinMinutes ?? '')}"></div><div class="field"><label>زمان تقریبی حداکثر (دقیقه)</label><input name="estimatedMaxMinutes" type="number" min="0" value="${esc(s.estimatedMaxMinutes ?? '')}"></div><div class="field"><label>روز جبران ریزش</label><input name="refillDays" type="number" min="0" value="${esc(s.refillDays ?? '')}"></div></div><div class="field"><label>توضیح فارسی</label><textarea name="descriptionFa">${esc(s.descriptionFa || '')}</textarea></div><div class="field"><label>English description</label><textarea name="descriptionEn">${esc(s.descriptionEn || '')}</textarea></div><div class="row" style="margin-top:10px"><label><input type="checkbox" name="enabled"${s.enabled ? ' checked' : ''}> فعال برای مشتری</label><label><input type="checkbox" name="featured"${s.featured ? ' checked' : ''}> ویژه</label><button class="btn" type="submit">ذخیره</button></div></form></div>${s.routes.map((route) => `<div class="card"><div class="row"><b>${esc(route.provider.name)}</b><span class="badge">ID ${esc(route.providerServiceCode)}</span><span class="badge">${esc(route.providerType || 'Default')}</span><span class="spacer"></span><span class="muted">${esc(route.providerRate?.toString() ?? '—')} ${esc(route.providerCurrency || '')}</span></div><div class="muted" style="margin-top:6px">Provider: ${esc(route.providerName || '')} • Category: ${esc(route.providerCategory || '')} • Range ${esc(route.providerMinQty ?? '—')}–${esc(route.providerMaxQty ?? '—')}</div><form method="post" action="/admin/social-routes/save" class="row" style="margin-top:10px"><input type="hidden" name="routeId" value="${esc(route.id)}"><input type="hidden" name="serviceId" value="${esc(s.id)}"><label>Priority <input style="width:75px" name="priority" type="number" value="${esc(route.priority)}"></label><label>Markup % <input style="width:85px" name="markup" inputmode="decimal" value="${esc(route.markupPercent?.toString() || '')}"></label><label><input type="checkbox" name="enabled"${route.enabled ? ' checked' : ''}> Route فعال</label><button class="ghost" type="submit">ذخیره Route</button></form></div>`).join('')}` : '<div class="card muted">یک سرویس را برای ویرایش انتخاب کن. سرویس‌های تازه Sync شده به‌صورت پیش‌فرض برای مشتری خاموش هستند تا خودت نام، قیمت و زمان را تنظیم کنی.</div>';

    const body = `${balanceMessage ? `<div class="msg">${esc(balanceMessage)}</div>` : ''}<div class="warn" style="margin-top:14px">Sync فقط اطلاعات Provider مثل نام اصلی، Rate، Min/Max، Refill و Cancel را تازه می‌کند؛ نام و قیمت مشتری که خودت تنظیم کرده‌ای بازنویسی نمی‌شود.</div>${providerCards}<div class="grid"><div class="card"><form method="get" action="/admin/social-services" class="row"><input name="q" value="${esc(q)}" placeholder="جستجوی سرویس"><select name="platform"><option value="">همه پلتفرم‌ها</option>${platforms.map((x) => `<option value="${x}"${x === platform ? ' selected' : ''}>${x}</option>`).join('')}</select><button class="ghost" type="submit">فیلتر</button></form><div class="table" style="margin-top:10px"><table><thead><tr><th>سرویس</th><th>پلتفرم / گروه</th><th>قیمت مشتری</th><th>Min/Max</th><th>زمان تقریبی</th><th>Refill / Cancel</th><th>Provider</th><th>وضعیت</th><th></th></tr></thead><tbody>${tableRows || '<tr><td colspan="9">سرویسی وجود ندارد.</td></tr>'}</tbody></table></div></div><div>${editPanel}</div></div>`;
    return reply.type('text/html; charset=utf-8').send(socialAdminShell('پنل خدمات شبکه‌های اجتماعی', admin, body, String(query.msg ?? '')));
  });

  app.post('/admin/social-services/sync', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const providerId = text(request.body as AnyBody, 'providerId');
    try {
      const result = await syncProviderServices(prisma, providerId);
      await audit(prisma, admin.id, 'SOCIAL_PROVIDER_SYNC', 'Provider', providerId, `Synced ${result.total} services`, { created: result.created, updated: result.updated, currency: result.balance.currency });
      return reply.code(303).redirect(`/admin/social-services?msg=${encodeURIComponent(`Sync شد: ${result.total} سرویس، ${result.created} جدید`)}`);
    } catch (error) {
      const message = error instanceof SmmProviderError ? error.providerMessage || error.message : error instanceof Error ? error.message : 'sync_failed';
      return reply.code(303).redirect(`/admin/social-services?msg=${encodeURIComponent(`Sync ناموفق: ${message}`)}`);
    }
  });

  app.post('/admin/social-services/save', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const body = request.body as AnyBody;
    const id = text(body, 'id');
    if (!id) return reply.code(303).redirect('/admin/social-services?msg=invalid');
    try {
      const minQty = intOrNull(body.minQty);
      const maxQty = intOrNull(body.maxQty);
      const estimatedMinMinutes = intOrNull(body.estimatedMinMinutes);
      const estimatedMaxMinutes = intOrNull(body.estimatedMaxMinutes);
      if (minQty != null && maxQty != null && minQty > maxQty) throw new Error('MIN_MAX_INVALID');
      if (estimatedMinMinutes != null && estimatedMaxMinutes != null && estimatedMinMinutes > estimatedMaxMinutes) throw new Error('ETA_INVALID');
      const basePriceAfnRaw = intOrNull(body.basePriceAfn);
      const saved = await prisma.service.update({
        where: { id },
        data: {
          titleFa: text(body, 'titleFa'),
          titleEn: text(body, 'titleEn'),
          descriptionFa: text(body, 'descriptionFa') || null,
          descriptionEn: text(body, 'descriptionEn') || null,
          socialPlatform: text(body, 'socialPlatform') || 'OTHER',
          socialGroup: text(body, 'socialGroup') || 'OTHER',
          basePriceAfn: basePriceAfnRaw == null ? null : BigInt(basePriceAfnRaw),
          priceUnit: Math.max(1, intOrNull(body.priceUnit) ?? 1000),
          minQty,
          maxQty,
          estimatedMinMinutes,
          estimatedMaxMinutes,
          refillDays: intOrNull(body.refillDays),
          sortOrder: intOrNull(body.sortOrder) ?? 100,
          enabled: checked(body, 'enabled'),
          featured: checked(body, 'featured'),
        },
      });
      await audit(prisma, admin.id, 'SOCIAL_SERVICE_UPDATE', 'Service', id, `${saved.titleEn} / ${saved.titleFa}`);
      return reply.code(303).redirect(`/admin/social-services?edit=${encodeURIComponent(id)}&msg=${encodeURIComponent('سرویس ذخیره شد')}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social-services?edit=${encodeURIComponent(id)}&msg=${encodeURIComponent(error instanceof Error ? error.message : 'invalid')}`);
    }
  });

  app.post('/admin/social-routes/save', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const body = request.body as AnyBody;
    const routeId = text(body, 'routeId');
    const serviceId = text(body, 'serviceId');
    if (!routeId || !serviceId) return reply.code(303).redirect('/admin/social-services?msg=invalid');
    try {
      const route = await prisma.serviceProviderRoute.update({
        where: { id: routeId },
        data: {
          priority: intOrNull(body.priority) ?? 100,
          markupPercent: decimalOrNull(body.markup),
          enabled: checked(body, 'enabled'),
        },
      });
      await audit(prisma, admin.id, 'SOCIAL_ROUTE_UPDATE', 'ServiceProviderRoute', routeId, `Route ${route.providerServiceCode} updated`);
      return reply.code(303).redirect(`/admin/social-services?edit=${encodeURIComponent(serviceId)}&msg=${encodeURIComponent('Route ذخیره شد')}`);
    } catch {
      return reply.code(303).redirect(`/admin/social-services?edit=${encodeURIComponent(serviceId)}&msg=invalid`);
    }
  });
}
