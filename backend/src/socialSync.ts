import {
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
  type Provider,
  type Service,
  type ServiceProviderRoute,
} from '@prisma/client';
import { smmClientForProvider } from './smmPanelAdapter.js';
import { normalizeCurrencyCode } from './currency.js';

const SCALE = 1_000_000n;
const DEFAULT_SYNC_MINUTES = 10;
const MIN_SYNC_MINUTES = 1;
const MAX_SYNC_MINUTES = 1440;

export type SocialProviderSyncConfig = {
  autoSync: boolean;
  syncMinutes: number;
  lastSyncAt: string | null;
  lastSyncStatus: 'idle' | 'ok' | 'error';
  lastSyncError: string | null;
  lastServiceCount: number;
  lastCreatedCount: number;
  lastUpdatedCount: number;
};

export type SocialSyncResult = {
  providerId: string;
  providerName: string;
  total: number;
  created: number;
  updated: number;
  currency: string;
  balance: string;
  syncedAt: string;
};

type RouteForPrice = Pick<
  ServiceProviderRoute,
  'providerRate' | 'providerCurrency' | 'markupPercent'
> & {
  provider: Pick<Provider, 'defaultMarkupPercent'>;
};

function jsonObject(value: Prisma.JsonValue | null | undefined): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function clampSyncMinutes(value: unknown) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return DEFAULT_SYNC_MINUTES;
  return Math.min(MAX_SYNC_MINUTES, Math.max(MIN_SYNC_MINUTES, parsed));
}

function syncSettingKey(providerId: string) {
  return `social.provider.sync.${providerId}`;
}

export async function getSocialProviderSyncConfig(
  prisma: PrismaClient,
  providerId: string,
): Promise<SocialProviderSyncConfig> {
  const setting = await prisma.systemSetting.findUnique({
    where: { key: syncSettingKey(providerId) },
  });
  const row = jsonObject(setting?.value);
  return {
    autoSync: row.autoSync !== false,
    syncMinutes: clampSyncMinutes(row.syncMinutes),
    lastSyncAt: typeof row.lastSyncAt === 'string' ? row.lastSyncAt : null,
    lastSyncStatus:
      row.lastSyncStatus === 'ok' || row.lastSyncStatus === 'error'
        ? row.lastSyncStatus
        : 'idle',
    lastSyncError: typeof row.lastSyncError === 'string' ? row.lastSyncError : null,
    lastServiceCount: Number.isFinite(Number(row.lastServiceCount))
      ? Number(row.lastServiceCount)
      : 0,
    lastCreatedCount: Number.isFinite(Number(row.lastCreatedCount))
      ? Number(row.lastCreatedCount)
      : 0,
    lastUpdatedCount: Number.isFinite(Number(row.lastUpdatedCount))
      ? Number(row.lastUpdatedCount)
      : 0,
  };
}

export async function saveSocialProviderSyncConfig(
  prisma: PrismaClient,
  providerId: string,
  patch: Partial<SocialProviderSyncConfig>,
) {
  const current = await getSocialProviderSyncConfig(prisma, providerId);
  const next: SocialProviderSyncConfig = {
    ...current,
    ...patch,
    syncMinutes: clampSyncMinutes(patch.syncMinutes ?? current.syncMinutes),
  };
  await prisma.systemSetting.upsert({
    where: { key: syncSettingKey(providerId) },
    create: {
      key: syncSettingKey(providerId),
      category: 'social-provider-sync',
      description: 'Automatic social provider synchronization state and schedule.',
      value: next as unknown as Prisma.InputJsonValue,
    },
    update: {
      category: 'social-provider-sync',
      value: next as unknown as Prisma.InputJsonValue,
    },
  });
  return next;
}

function decimalToScaled(value: Prisma.Decimal | string | number) {
  const decimal = value instanceof Prisma.Decimal ? value : new Prisma.Decimal(value);
  const text = decimal.toFixed(6);
  const [whole, fraction = ''] = text.split('.');
  const sign = whole.startsWith('-') ? -1n : 1n;
  const wholeAbs = whole.startsWith('-') ? whole.slice(1) : whole;
  return sign * (
    BigInt(wholeAbs || '0') * SCALE + BigInt((fraction + '000000').slice(0, 6))
  );
}

function ceilDiv(a: bigint, b: bigint) {
  if (b <= 0n) throw new Error('INVALID_DIVISOR');
  if (a <= 0n) return a / b;
  return (a + b - 1n) / b;
}

async function afnPerCurrencyScaled(prisma: PrismaClient, currency: string) {
  const normalized = normalizeCurrencyCode(currency) || 'USD';
  if (normalized === 'AFN') return SCALE;
  const exchange = await prisma.exchangeRate.findUnique({ where: { code: normalized } });
  if (!exchange) return null;
  return decimalToScaled(exchange.afnPerUnit);
}

export async function convertSocialPriceToAfn(
  prisma: PrismaClient,
  amount: Prisma.Decimal | string | number,
  currency: string,
) {
  const fx = await afnPerCurrencyScaled(prisma, currency);
  if (fx == null) throw new Error(`EXCHANGE_RATE_MISSING:${currency.toUpperCase()}`);
  const amountScaled = decimalToScaled(amount);
  const afnScaled = ceilDiv(amountScaled * fx, SCALE);
  return ceilDiv(afnScaled, SCALE);
}

export async function socialRouteSaleRateAfn(
  prisma: PrismaClient,
  service: Pick<Service, 'basePriceAfn'>,
  route: RouteForPrice,
) {
  if (service.basePriceAfn != null) return service.basePriceAfn;
  if (!route.providerRate) return null;
  const currency = normalizeCurrencyCode(route.providerCurrency || 'USD') || 'USD';
  const fx = await afnPerCurrencyScaled(prisma, currency);
  if (fx == null) return null;

  const providerRateScaled = decimalToScaled(route.providerRate);
  const rawAfnScaled = ceilDiv(providerRateScaled * fx, SCALE);
  const markup = route.markupPercent ?? route.provider.defaultMarkupPercent;
  const markupScaled = decimalToScaled(markup);
  const withMarkupScaled = ceilDiv(
    rawAfnScaled * (100n * SCALE + markupScaled),
    100n * SCALE,
  );
  return ceilDiv(withMarkupScaled, SCALE);
}

export function inferSocialPlatform(value: string) {
  const text = ` ${value.toLowerCase()} `;
  if (text.includes('instagram') || text.includes(' insta ')) return 'INSTAGRAM';
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
  if (text.includes('whatsapp')) return 'WHATSAPP';
  return 'OTHER';
}

export function inferSocialGroup(value: string) {
  const text = value.toLowerCase();
  if (text.includes('follower') || text.includes('subscriber') || text.includes('member')) {
    return 'FOLLOWERS';
  }
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
  const type = providerType.trim().toLowerCase();
  return type === 'package' || type.includes('subscription') ? 1 : 1000;
}

function safeSlugPart(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 90) || 'service';
}

export async function syncSocialProviderCatalog(
  prisma: PrismaClient,
  providerId: string,
): Promise<SocialSyncResult> {
  const provider = await prisma.provider.findFirst({
    where: { id: providerId, kind: ProviderKind.SOCIAL },
  });
  if (!provider) throw new Error('SOCIAL_PROVIDER_NOT_FOUND');

  try {
    const client = smmClientForProvider(provider);
    const [services, balance] = await Promise.all([client.services(), client.balance()]);
    const routes = await prisma.serviceProviderRoute.findMany({
      where: { providerId: provider.id },
      include: { service: true },
    });
    const byCode = new Map(routes.map((route) => [route.providerServiceCode, route]));
    const currency = normalizeCurrencyCode(provider.currencyCode || balance.currency || 'USD') || 'USD';
    const fx = await afnPerCurrencyScaled(prisma, currency);
    let created = 0;
    let updated = 0;
    const syncedAt = new Date();

    for (const [catalogIndex, row] of services.entries()) {
      const current = byCode.get(row.service);
      const currentRouteMeta = jsonObject(current?.metadata);
      const refillOverride = typeof currentRouteMeta._velixeoRefillOverride === 'boolean'
        ? currentRouteMeta._velixeoRefillOverride
        : null;
      const providerRate = new Prisma.Decimal(row.rate || '0');
      const providerRateScaled = decimalToScaled(providerRate);
      const costAfn = fx == null
        ? null
        : ceilDiv(ceilDiv(providerRateScaled * fx, SCALE), SCALE);
      const routeData = {
        providerName: row.name,
        providerType: row.type,
        providerCategory: row.category,
        providerRate,
        providerCurrency: currency,
        providerMinQty: row.min || null,
        providerMaxQty: row.max || null,
        providerRefill: refillOverride ?? row.refill,
        providerCancel: row.cancel,
        costAfn,
        lastSyncedAt: syncedAt,
        metadata: {
          ...row.raw,
          _velixeoCatalogIndex: catalogIndex,
          _providerRefillDetected: row.refill,
          ...(refillOverride == null ? {} : { _velixeoRefillOverride: refillOverride }),
        } as Prisma.InputJsonValue,
      };

      if (current) {
        await prisma.serviceProviderRoute.update({
          where: { id: current.id },
          data: routeData,
        });
        updated += 1;
        continue;
      }

      const combined = `${row.category} ${row.name}`;
      const platform = inferSocialPlatform(combined);
      const group = inferSocialGroup(combined);
      const baseSlug = `social-${safeSlugPart(provider.slug)}-${safeSlugPart(row.service)}`;
      let slug = baseSlug;
      let suffix = 1;
      while (await prisma.service.findUnique({ where: { slug } })) {
        suffix += 1;
        slug = `${baseSlug}-${suffix}`;
      }

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
          socialPlatform: platform,
          socialGroup: group,
          metadata: {
            source: 'SMM_PROVIDER',
            importedFromProviderId: provider.id,
            rawCatalog: true,
            pricingMode: 'AUTO_MARKUP',
          },
          routes: {
            create: {
              providerId: provider.id,
              providerServiceCode: row.service,
              enabled: true,
              priority: provider.priority,
              markupPercent: null,
              ...routeData,
            },
          },
        },
      });
      created += 1;
    }

    const result: SocialSyncResult = {
      providerId: provider.id,
      providerName: provider.name,
      total: services.length,
      created,
      updated,
      currency,
      balance: balance.balance,
      syncedAt: syncedAt.toISOString(),
    };

    await saveSocialProviderSyncConfig(prisma, provider.id, {
      lastSyncAt: result.syncedAt,
      lastSyncStatus: 'ok',
      lastSyncError: null,
      lastServiceCount: result.total,
      lastCreatedCount: created,
      lastUpdatedCount: updated,
    });
    return result;
  } catch (error) {
    await saveSocialProviderSyncConfig(prisma, provider.id, {
      lastSyncAt: new Date().toISOString(),
      lastSyncStatus: 'error',
      lastSyncError: error instanceof Error ? error.message.slice(0, 500) : 'sync_failed',
    }).catch(() => undefined);
    throw error;
  }
}

const syncing = new Set<string>();

export function startSocialAutoSync(
  prisma: PrismaClient,
  logger?: { info: (...args: unknown[]) => void; warn: (...args: unknown[]) => void },
) {
  if (process.env.NODE_ENV === 'test') return () => undefined;
  let stopped = false;

  const tick = async () => {
    if (stopped) return;
    const providers = await prisma.provider.findMany({
      where: { kind: ProviderKind.SOCIAL, enabled: true },
      orderBy: [{ priority: 'asc' }, { name: 'asc' }],
    });

    for (const provider of providers) {
      if (syncing.has(provider.id)) continue;
      const config = await getSocialProviderSyncConfig(prisma, provider.id);
      if (!config.autoSync) continue;
      const last = config.lastSyncAt ? new Date(config.lastSyncAt).getTime() : 0;
      const dueAt = last + config.syncMinutes * 60_000;
      if (last && Date.now() < dueAt) continue;

      syncing.add(provider.id);
      try {
        const result = await syncSocialProviderCatalog(prisma, provider.id);
        logger?.info(
          { providerId: provider.id, total: result.total, created: result.created },
          'social provider auto-sync complete',
        );
      } catch (error) {
        logger?.warn(
          { providerId: provider.id, error: error instanceof Error ? error.message : String(error) },
          'social provider auto-sync failed',
        );
      } finally {
        syncing.delete(provider.id);
      }
    }
  };

  const initial = setTimeout(() => void tick(), 20_000);
  initial.unref();
  const timer = setInterval(() => void tick(), 60_000);
  timer.unref();

  return () => {
    stopped = true;
    clearTimeout(initial);
    clearInterval(timer);
  };
}
