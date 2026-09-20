import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  OrderStatus,
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
  WalletEntryStatus,
  WalletEntryType,
} from '@prisma/client';
import { z } from 'zod';
import {
  FiveSimError,
  type FiveSimOrder,
  type FiveSimPrice,
  fiveSimClientForProvider,
} from './fiveSimAdapter.js';

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

type VirtualOffer = {
  serviceId: string;
  product: string;
  country: string;
  operator: string;
  count: number;
  deliveryRate: number | null;
  providerCost: number;
  providerCostAfn: number;
  priceAfn: number;
  providerId: string;
  routeId: string;
  routePriority: number;
  providerPriority: number;
};

const offerQuerySchema = z.object({
  serviceId: z.string().uuid(),
  country: z.string().trim().min(1).max(80),
});

const buySchema = z.object({
  serviceId: z.string().uuid(),
  country: z.string().trim().min(1).max(80),
  operator: z.string().trim().min(1).max(120).default('any'),
  mode: z.enum(['BEST_RATE', 'LOW_PRICE', 'ANY']).default('BEST_RATE'),
  clientRequestId: z.string().uuid(),
});

const orderParamsSchema = z.object({ id: z.string().uuid() });

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

function text(body: AnyBody, key: string) {
  return String(body[key] ?? '').trim();
}

function checked(body: AnyBody, key: string) {
  return body[key] === 'on' || body[key] === 'true' || body[key] === '1';
}
function safeVirtualAdminReturn(body: AnyBody, fallback: string) {
  const value = text(body, 'returnTo');
  return value.startsWith('/admin/v3?section=virtual') ? value : fallback;
}

async function logVirtualAction(
  prisma: PrismaClient,
  orderId: string,
  action: string,
  status: string,
  providerReference?: string | null,
  response?: unknown,
) {
  await prisma.orderActionLog.create({
    data: {
      orderId,
      action,
      status,
      providerReference: providerReference ?? null,
      response: response == null ? undefined : response as Prisma.InputJsonValue,
    },
  }).catch(() => undefined);
}

function slugify(value: string) {
  const normalized = value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 70);
  return normalized || `service-${Date.now()}`;
}

async function settingValue(prisma: PrismaClient, key: string): Promise<unknown> {
  const row = await prisma.systemSetting.findUnique({ where: { key } });
  return row?.value ?? null;
}

async function upsertSetting(
  prisma: PrismaClient,
  key: string,
  value: Prisma.InputJsonValue,
  description: string,
) {
  return prisma.systemSetting.upsert({
    where: { key },
    update: { value, description, category: 'virtual_number' },
    create: { key, value, description, category: 'virtual_number' },
  });
}

async function enabledCountrySet(prisma: PrismaClient) {
  const raw = await settingValue(prisma, 'virtual.enabledCountries');
  if (!Array.isArray(raw) || raw.length === 0) return null;
  return new Set(raw.map((item) => String(item).trim().toLowerCase()).filter(Boolean));
}

async function providerAfnPerUnit(prisma: PrismaClient, providerId: string) {
  const raw = await settingValue(prisma, `virtual.provider.${providerId}.afnPerUnit`);
  if (typeof raw === 'number' && Number.isFinite(raw) && raw > 0) return raw;
  if (typeof raw === 'string') {
    const parsed = Number(raw);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    const parsed = Number((raw as Record<string, unknown>).value);
    if (Number.isFinite(parsed) && parsed > 0) return parsed;
  }
  return null;
}

const pricesCache = new Map<string, { expiresAt: number; rows: FiveSimPrice[] }>();
const countriesCache = new Map<string, { expiresAt: number; data: Record<string, unknown> }>();

async function providerPrices(
  provider: Parameters<typeof fiveSimClientForProvider>[0],
  filters: { country?: string; product?: string } = {},
) {
  const key = `${provider.id}:${filters.country ?? '*'}:${filters.product ?? '*'}`;
  const hit = pricesCache.get(key);
  if (hit && hit.expiresAt > Date.now()) return hit.rows;
  const rows = await fiveSimClientForProvider(provider).prices(filters);
  pricesCache.set(key, { expiresAt: Date.now() + 60_000, rows });
  return rows;
}

async function providerCountries(provider: Parameters<typeof fiveSimClientForProvider>[0]) {
  const hit = countriesCache.get(provider.id);
  if (hit && hit.expiresAt > Date.now()) return hit.data;
  const data = await fiveSimClientForProvider(provider).countries();
  countriesCache.set(provider.id, { expiresAt: Date.now() + 10 * 60_000, data });
  return data;
}

function customerPriceAfn(input: {
  providerCost: number;
  afnPerUnit: number;
  markupPercent: number;
  fixedPriceAfn?: bigint | null;
}) {
  if (input.fixedPriceAfn != null) return Number(input.fixedPriceAfn);
  const raw = input.providerCost * input.afnPerUnit;
  return Math.max(1, Math.ceil(raw * (1 + input.markupPercent / 100)));
}

async function offersForService(
  prisma: PrismaClient,
  serviceId: string,
  country?: string,
): Promise<VirtualOffer[]> {
  const enabledCountries = await enabledCountrySet(prisma);
  const service = await prisma.service.findFirst({
    where: { id: serviceId, category: ServiceCategory.VIRTUAL_NUMBER, enabled: true },
    include: {
      routes: {
        where: {
          enabled: true,
          provider: { enabled: true, kind: ProviderKind.VIRTUAL_NUMBER },
        },
        include: { provider: true },
        orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
      },
    },
  });
  if (!service) return [];
  const product = service.routes[0]?.providerServiceCode || service.slug.replace(/^virtual-/, '');
  const rows: VirtualOffer[] = [];
  for (const route of service.routes) {
    const factor = await providerAfnPerUnit(prisma, route.providerId);
    if (factor == null) continue;
    let providerRows: FiveSimPrice[];
    try {
      providerRows = await providerPrices(route.provider, {
        country: country || undefined,
        product: route.providerServiceCode,
      });
    } catch {
      continue;
    }
    const markup = Number((route.markupPercent ?? route.provider.defaultMarkupPercent).toString());
    for (const row of providerRows) {
      const code = row.country.toLowerCase();
      if (enabledCountries && !enabledCountries.has(code)) continue;
      if (country && code !== country.toLowerCase()) continue;
      if (row.count <= 0 || row.cost <= 0) continue;
      rows.push({
        serviceId: service.id,
        product: route.providerServiceCode || product,
        country: row.country,
        operator: row.operator,
        count: row.count,
        deliveryRate: row.rate,
        providerCost: row.cost,
        providerCostAfn: Math.max(1, Math.ceil(row.cost * factor)),
        priceAfn: customerPriceAfn({
          providerCost: row.cost,
          afnPerUnit: factor,
          markupPercent: markup,
          fixedPriceAfn: service.basePriceAfn,
        }),
        providerId: route.providerId,
        routeId: route.id,
        routePriority: route.priority,
        providerPriority: route.provider.priority,
      });
    }
  }
  return rows;
}

function sortOffers(rows: VirtualOffer[], mode: 'BEST_RATE' | 'LOW_PRICE' | 'ANY') {
  return [...rows].sort((a, b) => {
    if (mode === 'LOW_PRICE') {
      return a.priceAfn - b.priceAfn ||
        (b.deliveryRate ?? -1) - (a.deliveryRate ?? -1) ||
        a.routePriority - b.routePriority ||
        a.providerPriority - b.providerPriority;
    }
    if (mode === 'ANY') {
      return a.routePriority - b.routePriority ||
        a.providerPriority - b.providerPriority ||
        a.priceAfn - b.priceAfn;
    }
    return (b.deliveryRate ?? -1) - (a.deliveryRate ?? -1) ||
      a.priceAfn - b.priceAfn ||
      a.routePriority - b.routePriority ||
      a.providerPriority - b.providerPriority;
  });
}

function publicOffer(row: VirtualOffer) {
  return {
    country: row.country,
    operator: row.operator,
    count: row.count,
    deliveryPercent: row.deliveryRate,
    priceAfn: row.priceAfn,
  };
}

function orderStatus(providerStatus: string, smsCount: number) {
  const value = providerStatus.trim().toUpperCase();
  if (value === 'FINISHED') return OrderStatus.COMPLETED;
  if (value === 'CANCELED' || value === 'CANCELLED') return OrderStatus.CANCELLED;
  if (value === 'TIMEOUT' || value === 'BANNED') return OrderStatus.FAILED;
  if (smsCount > 0 || value === 'RECEIVED') return OrderStatus.PROCESSING;
  return OrderStatus.AWAITING_SMS;
}

function orderJson(order: any) {
  const output = order.output && typeof order.output === 'object'
    ? order.output as Record<string, unknown>
    : {};
  const sms = Array.isArray(output.sms) ? output.sms : [];
  return {
    id: order.id,
    status: order.status,
    totalAmountAfn: Number(order.totalAmountAfn),
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    failureReason: order.failureReason,
    phone: output.phone ?? null,
    product: output.product ?? null,
    country: output.country ?? null,
    operator: output.operator ?? null,
    expires: output.expires ?? null,
    sms,
    providerStatus: output.providerStatus ?? null,
    canCancel: ![OrderStatus.COMPLETED, OrderStatus.CANCELLED, OrderStatus.REFUNDED, OrderStatus.FAILED].includes(order.status),
    canFinish: sms.length > 0 && ![OrderStatus.COMPLETED, OrderStatus.CANCELLED, OrderStatus.REFUNDED].includes(order.status),
    service: order.service ? {
      id: order.service.id,
      titleFa: order.service.titleFa,
      titleEn: order.service.titleEn,
    } : null,
  };
}

async function refundVirtualOrder(
  prisma: PrismaClient,
  order: { id: string; userId: string; totalAmountAfn: bigint },
  reason: string,
) {
  const purchase = await prisma.walletEntry.findFirst({
    where: {
      referenceType: 'ORDER_PURCHASE',
      referenceId: order.id,
      type: WalletEntryType.PURCHASE,
      status: WalletEntryStatus.COMPLETED,
    },
  });
  if (!purchase) return null;
  const key = `virtual-order-refund-${order.id}`;
  return prisma.$transaction(async (tx) => {
    const existing = await tx.walletEntry.findUnique({ where: { idempotencyKey: key } });
    if (existing) return existing;
    const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
    if (!wallet) throw new Error('WALLET_NOT_FOUND');
    const nextBalance = wallet.balanceAfn + order.totalAmountAfn;
    await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: nextBalance } });
    return tx.walletEntry.create({
      data: {
        walletId: wallet.id,
        type: WalletEntryType.REFUND,
        status: WalletEntryStatus.COMPLETED,
        amountAfn: order.totalAmountAfn,
        balanceAfterAfn: nextBalance,
        referenceType: 'VIRTUAL_NUMBER_REFUND',
        referenceId: order.id,
        description: reason,
        idempotencyKey: key,
      },
    });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

async function updateFromProviderOrder(
  prisma: PrismaClient,
  order: any,
  providerOrder: FiveSimOrder,
) {
  const nextStatus = orderStatus(providerOrder.status, providerOrder.sms.length);
  const current = order.output && typeof order.output === 'object'
    ? order.output as Record<string, unknown>
    : {};
  const updated = await prisma.order.update({
    where: { id: order.id },
    data: {
      status: nextStatus,
      completedAt: nextStatus === OrderStatus.COMPLETED ? new Date() : order.completedAt,
      failureReason: nextStatus === OrderStatus.FAILED ? providerOrder.status : null,
      output: {
        ...current,
        phone: providerOrder.phone,
        product: providerOrder.product,
        country: providerOrder.country ?? current.country ?? null,
        operator: providerOrder.operator ?? current.operator ?? null,
        expires: providerOrder.expires ?? null,
        sms: providerOrder.sms as unknown as Prisma.InputJsonValue,
        providerStatus: providerOrder.status,
        lastStatusSyncAt: new Date().toISOString(),
      },
    },
    include: { service: true },
  });
  if (
    (providerOrder.status === 'TIMEOUT' || providerOrder.status === 'CANCELED' || providerOrder.status === 'CANCELLED') &&
    providerOrder.sms.length === 0
  ) {
    await refundVirtualOrder(prisma, order, `Virtual number ${providerOrder.status.toLowerCase()} refund`);
  }
  return updated;
}

async function syncProviderServices(prisma: PrismaClient, providerId: string) {
  const provider = await prisma.provider.findFirst({
    where: { id: providerId, kind: ProviderKind.VIRTUAL_NUMBER },
  });
  if (!provider) throw new Error('PROVIDER_NOT_FOUND');
  const rows = await providerPrices(provider);
  const products = [...new Set(rows.map((row) => row.product).filter(Boolean))].sort();
  let created = 0;
  let updated = 0;
  for (const product of products) {
    const slug = `virtual-${slugify(product)}`;
    const existing = await prisma.service.findUnique({ where: { slug } });
    const service = existing
      ? await prisma.service.update({
          where: { id: existing.id },
          data: {
            category: ServiceCategory.VIRTUAL_NUMBER,
            metadata: { source: 'virtual_provider_sync', product },
          },
        })
      : await prisma.service.create({
          data: {
            category: ServiceCategory.VIRTUAL_NUMBER,
            slug,
            titleFa: product,
            titleEn: product,
            descriptionFa: 'دریافت شماره مجازی و کد SMS',
            descriptionEn: 'Virtual number and SMS activation',
            enabled: false,
            sortOrder: 100,
            priceUnit: 1,
            minQty: 1,
            maxQty: 1,
            metadata: { source: 'virtual_provider_sync', product },
          },
        });
    if (existing) updated += 1; else created += 1;
    await prisma.serviceProviderRoute.upsert({
      where: {
        serviceId_providerId_providerServiceCode: {
          serviceId: service.id,
          providerId: provider.id,
          providerServiceCode: product,
        },
      },
      update: {
        enabled: true,
        priority: provider.priority,
        providerName: provider.name,
        providerType: '5SIM',
        providerCategory: 'activation',
        providerCurrency: 'PROVIDER',
        providerMinQty: 1,
        providerMaxQty: 1,
        lastSyncedAt: new Date(),
      },
      create: {
        serviceId: service.id,
        providerId: provider.id,
        providerServiceCode: product,
        enabled: true,
        priority: provider.priority,
        providerName: provider.name,
        providerType: '5SIM',
        providerCategory: 'activation',
        providerCurrency: 'PROVIDER',
        providerMinQty: 1,
        providerMaxQty: 1,
        lastSyncedAt: new Date(),
      },
    });
  }
  return { total: products.length, created, updated };
}

function adminShell(admin: AdminIdentity, body: string, message = '') {
  return `<!doctype html><html lang="en" dir="ltr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>شماره مجازی — VELIXEO</title><style>:root{--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#18A875;--bad:#E65454}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif}.wrap{max-width:1500px;margin:auto;padding:22px}.top{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.top h1{margin:0}.spacer{flex:1}.card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:17px;margin-top:14px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:14px}.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.muted{color:var(--muted);font-size:12px}.btn,.ghost{border-radius:11px;padding:10px 14px;text-decoration:none;cursor:pointer}.btn{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:#fff;font-weight:800}.ghost{border:1px solid var(--line);background:#fff;color:var(--text)}.field{margin-top:10px}.field label{display:block;font-size:12px;color:var(--muted);margin-bottom:5px}.field input,.field textarea{width:100%;border:1px solid var(--line);border-radius:11px;padding:10px;background:#fff}.field textarea{min-height:90px}.table{overflow:auto}.table table{width:100%;border-collapse:collapse;min-width:900px}th,td{padding:10px;border-bottom:1px solid #EDF3F7;text-align:left;font-size:12px}th{color:var(--muted)}.badge{display:inline-block;padding:4px 8px;border-radius:999px;background:#EDF4F8;font-size:11px}.ok{background:#E7F8F1;color:#0A8B5B}.off{background:#FFF0F0;color:#B33737}.msg{background:#E7F8F1;border:1px solid #C7EFDC;color:#0A8B5B;padding:10px;border-radius:12px;margin-top:12px}.warn{background:#FFF7E8;border:1px solid #FFE3AE;color:#8E5D0C;padding:10px;border-radius:12px;margin-top:12px}.chips{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;direction:ltr;text-align:left}@media(max-width:900px){.grid,.grid3{grid-template-columns:1fr}.wrap{padding:14px}}</style></head><body><main class="wrap"><div class="top"><div><h1>پنل شماره مجازی</h1><div class="muted">5SIM / SMS Activation • Providerها برای مشتری مخفی هستند</div></div><span class="spacer"></span><span class="muted">${esc(admin.fullName || admin.email || admin.phone || 'ADMIN')}</span><a class="ghost" href="/admin">مدیریت اصلی</a><a class="ghost" href="/admin/providers">Provider و API</a></div>${message ? `<div class="msg">${esc(message)}</div>` : ''}${body}</main></body></html>`;
}

export function registerVirtualNumberRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
  resolveAdmin: AdminResolver,
) {
  app.get('/api/v1/virtual-numbers/catalog', async (_request, reply) => {
    const services = await prisma.service.findMany({
      where: { category: ServiceCategory.VIRTUAL_NUMBER, enabled: true },
      include: {
        routes: {
          where: { enabled: true, provider: { enabled: true, kind: ProviderKind.VIRTUAL_NUMBER } },
          include: { provider: true },
          orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
        },
      },
      orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
    });
    const result = [];
    for (const service of services) {
      if (service.routes.length === 0) continue;
      const offers = await offersForService(prisma, service.id);
      const byCountry = new Map<string, { minPriceAfn: number; availableCount: number; maxRate: number | null }>();
      for (const offer of offers) {
        const current = byCountry.get(offer.country);
        if (!current) {
          byCountry.set(offer.country, {
            minPriceAfn: offer.priceAfn,
            availableCount: offer.count,
            maxRate: offer.deliveryRate,
          });
        } else {
          current.minPriceAfn = Math.min(current.minPriceAfn, offer.priceAfn);
          current.availableCount += offer.count;
          if (offer.deliveryRate != null) {
            current.maxRate = current.maxRate == null ? offer.deliveryRate : Math.max(current.maxRate, offer.deliveryRate);
          }
        }
      }
      result.push({
        id: service.id,
        slug: service.slug,
        titleFa: service.titleFa,
        titleEn: service.titleEn,
        descriptionFa: service.descriptionFa,
        descriptionEn: service.descriptionEn,
        featured: service.featured,
        countries: [...byCountry.entries()]
          .map(([code, value]) => ({ code, ...value }))
          .sort((a, b) => a.minPriceAfn - b.minPriceAfn || a.code.localeCompare(b.code)),
      });
    }
    return reply.send({ baseCurrency: 'AFN', services: result });
  });

  app.get('/api/v1/virtual-numbers/offers', async (request, reply) => {
    const parsed = offerQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const rows = await offersForService(prisma, parsed.data.serviceId, parsed.data.country);
    if (rows.length === 0) return reply.code(404).send({ error: 'no_virtual_number_offers' });
    const bestRate = sortOffers(rows, 'BEST_RATE')[0];
    const lowPrice = sortOffers(rows, 'LOW_PRICE')[0];
    const operators = sortOffers(rows, 'BEST_RATE').map(publicOffer);
    return {
      country: parsed.data.country,
      bestRate: bestRate ? publicOffer(bestRate) : null,
      lowPrice: lowPrice ? publicOffer(lowPrice) : null,
      anyOperator: {
        country: parsed.data.country,
        operator: 'any',
        count: rows.reduce((sum, row) => sum + row.count, 0),
        deliveryPercent: bestRate?.deliveryRate ?? null,
        priceAfn: lowPrice?.priceAfn ?? bestRate?.priceAfn ?? 0,
      },
      operators,
    };
  });

  app.get('/api/v1/virtual-numbers/orders', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const orders = await prisma.order.findMany({
      where: { userId, category: ServiceCategory.VIRTUAL_NUMBER },
      include: { service: true },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { orders: orders.map(orderJson) };
  });

  app.post('/api/v1/virtual-numbers/orders', { preHandler: authenticate }, async (request, reply) => {
    const parsed = buySchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const existing = await prisma.order.findUnique({
      where: { clientRequestId: parsed.data.clientRequestId },
      include: { service: true },
    });
    if (existing) {
      if (existing.userId !== userId || existing.category !== ServiceCategory.VIRTUAL_NUMBER) {
        return reply.code(409).send({ error: 'idempotency_conflict' });
      }
      return { order: orderJson(existing), idempotent: true };
    }

    const service = await prisma.service.findFirst({
      where: { id: parsed.data.serviceId, category: ServiceCategory.VIRTUAL_NUMBER, enabled: true },
      include: { routes: { include: { provider: true } } },
    });
    if (!service) return reply.code(404).send({ error: 'service_unavailable' });
    let offers = await offersForService(prisma, service.id, parsed.data.country);
    if (parsed.data.operator !== 'any') {
      offers = offers.filter((row) => row.operator === parsed.data.operator);
    }
    offers = sortOffers(offers, parsed.data.mode);
    if (offers.length === 0) return reply.code(409).send({ error: 'number_not_available' });
    const selected = offers[0];
    const amount = BigInt(selected.priceAfn);

    let order;
    try {
      order = await prisma.$transaction(async (tx) => {
        const duplicate = await tx.order.findUnique({ where: { clientRequestId: parsed.data.clientRequestId } });
        if (duplicate) return duplicate;
        const wallet = await tx.wallet.findUnique({ where: { userId } });
        if (!wallet) throw new Error('WALLET_NOT_FOUND');
        if (wallet.balanceAfn < amount) throw new Error('INSUFFICIENT_FUNDS');
        const created = await tx.order.create({
          data: {
            userId,
            serviceId: service.id,
            category: ServiceCategory.VIRTUAL_NUMBER,
            status: OrderStatus.PENDING,
            quantity: 1,
            baseAmountAfn: amount,
            totalAmountAfn: amount,
            clientRequestId: parsed.data.clientRequestId,
            input: {
              country: parsed.data.country,
              operator: parsed.data.operator,
              mode: parsed.data.mode,
              product: selected.product,
            },
          },
        });
        const nextBalance = wallet.balanceAfn - amount;
        await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: nextBalance } });
        await tx.walletEntry.create({
          data: {
            walletId: wallet.id,
            type: WalletEntryType.PURCHASE,
            status: WalletEntryStatus.COMPLETED,
            amountAfn: -amount,
            balanceAfterAfn: nextBalance,
            referenceType: 'ORDER_PURCHASE',
            referenceId: created.id,
            description: `Virtual number order ${created.id}`,
            idempotencyKey: `order-purchase-${created.id}`,
          },
        });
        return created;
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    } catch (error) {
      if (error instanceof Error && error.message === 'INSUFFICIENT_FUNDS') {
        return reply.code(409).send({ error: 'insufficient_funds' });
      }
      throw error;
    }

    if (order.providerOrderId) {
      const hydrated = await prisma.order.findUnique({ where: { id: order.id }, include: { service: true } });
      return { order: orderJson(hydrated), idempotent: true };
    }

    let lastError = 'provider_rejected';
    for (const candidate of offers) {
      if (candidate.priceAfn > selected.priceAfn) continue;
      const route = service.routes.find((item) => item.id === candidate.routeId);
      if (!route || !route.provider.enabled) continue;
      try {
        const providerOrder = await fiveSimClientForProvider(route.provider).buyActivation({
          country: candidate.country,
          operator: parsed.data.operator === 'any' ? candidate.operator : parsed.data.operator,
          product: route.providerServiceCode,
        });
        order = await prisma.order.update({
          where: { id: order.id },
          data: {
            providerId: route.providerId,
            providerOrderId: providerOrder.id,
            providerCostAfn: BigInt(candidate.providerCostAfn),
            status: orderStatus(providerOrder.status, providerOrder.sms.length),
            failureReason: null,
            output: {
              phone: providerOrder.phone,
              product: providerOrder.product,
              country: providerOrder.country ?? candidate.country,
              operator: providerOrder.operator ?? candidate.operator,
              expires: providerOrder.expires ?? null,
              sms: providerOrder.sms as unknown as Prisma.InputJsonValue,
              providerStatus: providerOrder.status,
              deliveryPercent: candidate.deliveryRate,
            },
            exchangeRateSnapshot: {
              providerCost: candidate.providerCost,
              customerPriceAfn: selected.priceAfn,
            },
          },
          include: { service: true },
        });
        return reply.code(201).send({ order: orderJson(order), idempotent: false });
      } catch (error) {
        if (error instanceof FiveSimError) {
          lastError = error.providerMessage || error.message;
          if (error.uncertain) {
            const updated = await prisma.order.update({
              where: { id: order.id },
              data: {
                providerId: route.providerId,
                status: OrderStatus.PROCESSING,
                failureReason: 'provider_submission_uncertain',
                output: {
                  providerSubmissionUncertain: true,
                  country: candidate.country,
                  operator: candidate.operator,
                  product: candidate.product,
                },
              },
              include: { service: true },
            });
            return reply.code(202).send({ order: orderJson(updated), warning: 'provider_submission_uncertain' });
          }
          continue;
        }
        throw error;
      }
    }

    await refundVirtualOrder(prisma, order, `Provider rejected virtual number order ${order.id}`);
    const failed = await prisma.order.update({
      where: { id: order.id },
      data: { status: OrderStatus.FAILED, failureReason: lastError },
      include: { service: true },
    });
    return reply.code(502).send({ error: 'provider_rejected', order: orderJson(failed) });
  });

  app.post('/api/v1/virtual-numbers/orders/:id/check', { preHandler: authenticate }, async (request, reply) => {
    const parsed = orderParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: parsed.data.id, userId, category: ServiceCategory.VIRTUAL_NUMBER },
      include: { provider: true, service: true },
    });
    if (!order) return reply.code(404).send({ error: 'order_not_found' });
    if (!order.provider || !order.providerOrderId) return reply.code(409).send({ error: 'provider_order_not_available' });
    try {
      const providerOrder = await fiveSimClientForProvider(order.provider).check(order.providerOrderId);
      const updated = await updateFromProviderOrder(prisma, order, providerOrder);
      await logVirtualAction(prisma, order.id, 'VIRTUAL_CHECK', 'SUCCESS', order.providerOrderId, {
        providerStatus: providerOrder.status,
        smsCount: providerOrder.sms.length,
      });
      return { order: orderJson(updated) };
    } catch (error) {
      if (error instanceof FiveSimError) {
        return reply.code(502).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.post('/api/v1/virtual-numbers/orders/:id/cancel', { preHandler: authenticate }, async (request, reply) => {
    const parsed = orderParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: parsed.data.id, userId, category: ServiceCategory.VIRTUAL_NUMBER },
      include: { provider: true, service: true },
    });
    if (!order) return reply.code(404).send({ error: 'order_not_found' });
    if (order.status === OrderStatus.COMPLETED || order.status === OrderStatus.CANCELLED || order.status === OrderStatus.REFUNDED) {
      return reply.code(409).send({ error: 'order_not_cancellable' });
    }
    if (!order.provider || !order.providerOrderId) return reply.code(409).send({ error: 'provider_order_not_available' });
    try {
      const providerOrder = await fiveSimClientForProvider(order.provider).cancel(order.providerOrderId);
      const updated = await updateFromProviderOrder(prisma, order, providerOrder);
      if (providerOrder.status === 'CANCELED' || providerOrder.status === 'CANCELLED') {
        await refundVirtualOrder(prisma, order, `Virtual number cancelled ${order.id}`);
      }
      await logVirtualAction(prisma, order.id, 'VIRTUAL_CANCEL', 'SUCCESS', order.providerOrderId, {
        providerStatus: providerOrder.status,
        smsCount: providerOrder.sms.length,
      });
      return { order: orderJson(updated) };
    } catch (error) {
      if (error instanceof FiveSimError) {
        return reply.code(409).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.post('/api/v1/virtual-numbers/orders/:id/finish', { preHandler: authenticate }, async (request, reply) => {
    const parsed = orderParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;
    const order = await prisma.order.findFirst({
      where: { id: parsed.data.id, userId, category: ServiceCategory.VIRTUAL_NUMBER },
      include: { provider: true, service: true },
    });
    if (!order) return reply.code(404).send({ error: 'order_not_found' });
    if (!order.provider || !order.providerOrderId) return reply.code(409).send({ error: 'provider_order_not_available' });
    try {
      const providerOrder = await fiveSimClientForProvider(order.provider).finish(order.providerOrderId);
      const updated = await updateFromProviderOrder(prisma, order, providerOrder);
      await logVirtualAction(prisma, order.id, 'VIRTUAL_FINISH', 'SUCCESS', order.providerOrderId, {
        providerStatus: providerOrder.status,
        smsCount: providerOrder.sms.length,
      });
      return { order: orderJson(updated) };
    } catch (error) {
      if (error instanceof FiveSimError) {
        return reply.code(409).send({ error: error.message, details: error.providerMessage });
      }
      throw error;
    }
  });

  app.get('/admin/virtual-numbers', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const query = (request.query ?? {}) as Record<string, unknown>;
    const message = String(query.msg ?? '');
    const providers = await prisma.provider.findMany({
      where: { kind: ProviderKind.VIRTUAL_NUMBER },
      orderBy: [{ enabled: 'desc' }, { priority: 'asc' }, { name: 'asc' }],
    });
    const services = await prisma.service.findMany({
      where: { category: ServiceCategory.VIRTUAL_NUMBER },
      include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } },
      orderBy: [{ enabled: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
      take: 800,
    });
    const enabledCountriesRaw = await settingValue(prisma, 'virtual.enabledCountries');
    const enabledCountries = Array.isArray(enabledCountriesRaw)
      ? enabledCountriesRaw.map((item) => String(item)).join(', ')
      : '';

    const providerCards = [];
    const countryCodes = new Set<string>();
    for (const provider of providers) {
      let status = 'آماده بررسی';
      let balance = '—';
      try {
        const profile = await fiveSimClientForProvider(provider).profile();
        balance = `${profile.balance}`;
        const countryData = await providerCountries(provider);
        for (const code of Object.keys(countryData)) countryCodes.add(code);
        status = 'اتصال API موفق';
      } catch (error) {
        status = error instanceof Error ? error.message : 'اتصال ناموفق';
      }
      const factor = await providerAfnPerUnit(prisma, provider.id);
      providerCards.push(`<div class="card"><div class="row"><b>${esc(provider.name)}</b><span class="badge ${provider.enabled ? 'ok' : 'off'}">${provider.enabled ? 'Active' : 'خاموش'}</span><span class="badge">Balance: ${esc(balance)}</span><span class="spacer"></span><form method="post" action="/admin/virtual-numbers/sync"><input type="hidden" name="providerId" value="${esc(provider.id)}"><button class="btn" type="submit">Sync Services</button></form></div><div class="muted" style="margin-top:6px">${esc(status)} • ${esc(provider.baseUrl || 'https://5sim.net')}</div><form method="post" action="/admin/virtual-numbers/provider-rate" class="row" style="margin-top:12px"><input type="hidden" name="providerId" value="${esc(provider.id)}"><label>هر 1 واحد قیمت Provider = <input name="afnPerUnit" inputmode="decimal" value="${esc(factor ?? '')}" placeholder="مثلاً 0.85" style="width:120px;border:1px solid #DCE8F1;border-radius:9px;padding:7px"> AFN</label><button class="ghost" type="submit">Save نرخ</button></form></div>`);
    }

    const body = `${providers.length === 0 ? '<div class="warn">ابتدا از بخش Provider و API یک Provider با نوع VIRTUAL_NUMBER بساز، Base URL را https://5sim.net قرار بده و Token را در Secret Save کن.</div>' : providerCards.join('')}<div class="grid"><div class="card"><h3>Countries</h3><p class="muted">خالی = همه Countriesی موجود Active. برای محدودکردن، کد Countries را با کاما جدا کن.</p><form method="post" action="/admin/virtual-numbers/countries"><div class="field"><label>Enabled country codes</label><textarea class="mono" name="countries" placeholder="afghanistan, england, germany">${esc(enabledCountries)}</textarea></div><button class="btn" type="submit">Save Countries</button></form><div class="chips">${[...countryCodes].sort().slice(0, 220).map((code) => `<span class="badge">${esc(code)}</span>`).join('')}</div></div><div class="card"><h3>منطق Pricing</h3><p class="muted">قیمت مشتری = قیمت زنده Provider × نرخ تبدیل به AFN × Markup. Markup از Route یا Provider گرفته می‌شود؛ قیمت پایه Service در صورت ثبت، قیمت ثابت مشتری است.</p><div class="warn">نام Provider در API موبایل برگردانده نمی‌شود.</div></div></div><div class="card"><div class="row"><h3 style="margin:0">Services</h3><span class="badge">${services.length} سرویس</span></div><div class="table"><table><thead><tr><th>سرویس</th><th>Provider Route</th><th>وضعیت مشتری</th><th>ویژه</th><th>کنترل</th></tr></thead><tbody>${services.length ? services.map((service) => `<tr><td><b>${esc(service.titleFa)}</b><br><span class="muted">${esc(service.titleEn)}</span><br><span class="mono">${esc(service.slug)}</span></td><td>${service.routes.map((route) => `${esc(route.provider.name)} / ${esc(route.providerServiceCode)}`).join('<br>') || '—'}</td><td><span class="badge ${service.enabled ? 'ok' : 'off'}">${service.enabled ? 'Active' : 'خاموش'}</span></td><td>${service.featured ? '⭐' : '—'}</td><td><form method="post" action="/admin/virtual-numbers/service-toggle" class="row"><input type="hidden" name="serviceId" value="${esc(service.id)}"><input type="hidden" name="enabled" value="${service.enabled ? '0' : '1'}"><button class="ghost" type="submit">${service.enabled ? 'غیرActive' : 'Active'}</button><a class="ghost" href="/admin/services?edit=${encodeURIComponent(service.id)}">ویرایش کامل</a></form></td></tr>`).join('') : '<tr><td colspan="5">هنوز Sync انجام نشده است.</td></tr>'}</tbody></table></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell(admin, body, message));
  });

  app.post('/admin/virtual-numbers/sync', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const adminBody = request.body as AnyBody;
    const providerId = text(adminBody, 'providerId');
    const returnTo = safeVirtualAdminReturn(adminBody, '/admin/virtual-numbers');
    try {
      const result = await syncProviderServices(prisma, providerId);
      await prisma.adminAuditLog.create({
        data: {
          adminUserId: admin.id,
          action: 'VIRTUAL_NUMBER_SYNC',
          entityType: 'Provider',
          entityId: providerId,
          summary: `Synced ${result.total} virtual-number products`,
          metadata: result,
        },
      });
      pricesCache.clear();
      const joiner = returnTo.includes('?') ? '&' : '?';
      return reply.code(303).redirect(`${returnTo}${joiner}msg=${encodeURIComponent(`Sync complete: ${result.total} services`)}`);
    } catch (error) {
      const joiner = returnTo.includes('?') ? '&' : '?';
      return reply.code(303).redirect(`${returnTo}${joiner}err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'sync_failed')}`);
    }
  });

  app.post('/admin/virtual-numbers/provider-rate', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const body = request.body as AnyBody;
    const returnTo = safeVirtualAdminReturn(body, '/admin/virtual-numbers');
    const providerId = text(body, 'providerId');
    const rate = Number(text(body, 'afnPerUnit'));
    if (!providerId || !Number.isFinite(rate) || rate <= 0) {
      return reply.code(303).redirect(returnTo + (returnTo.includes('?') ? '&' : '?') + 'err=1&msg=invalid_rate');
    }
    await upsertSetting(
      prisma,
      `virtual.provider.${providerId}.afnPerUnit`,
      rate,
      'AFN value of one provider price unit for virtual-number pricing',
    );
    pricesCache.clear();
    await prisma.adminAuditLog.create({
      data: {
        adminUserId: admin.id,
        action: 'VIRTUAL_NUMBER_PROVIDER_RATE',
        entityType: 'Provider',
        entityId: providerId,
        summary: `Virtual provider conversion rate set to ${rate} AFN`,
      },
    });
    return reply.code(303).redirect(returnTo + (returnTo.includes('?') ? '&' : '?') + 'msg=rate_saved');
  });

  app.post('/admin/virtual-numbers/countries', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const countryBody = request.body as AnyBody;
    const returnTo = safeVirtualAdminReturn(countryBody, '/admin/virtual-numbers');
    const raw = text(countryBody, 'countries');
    const countries = [...new Set(raw.split(/[\s,]+/).map((item) => item.trim().toLowerCase()).filter(Boolean))];
    await upsertSetting(prisma, 'virtual.enabledCountries', countries, 'Enabled countries for virtual-number catalog; empty means all');
    pricesCache.clear();
    await prisma.adminAuditLog.create({
      data: {
        adminUserId: admin.id,
        action: 'VIRTUAL_NUMBER_COUNTRIES',
        entityType: 'SystemSetting',
        entityId: null,
        summary: countries.length ? `${countries.length} virtual-number countries enabled` : 'All virtual-number countries enabled',
      },
    });
    return reply.code(303).redirect(returnTo + (returnTo.includes('?') ? '&' : '?') + 'msg=countries_saved');
  });

  app.post('/admin/virtual-numbers/service-toggle', async (request, reply) => {
    const admin = await resolveAdmin(request);
    if (!admin) return reply.code(303).redirect('/admin');
    const body = request.body as AnyBody;
    const returnTo = safeVirtualAdminReturn(body, '/admin/virtual-numbers');
    const serviceId = text(body, 'serviceId');
    const enabled = checked(body, 'enabled');
    const service = await prisma.service.findFirst({
      where: { id: serviceId, category: ServiceCategory.VIRTUAL_NUMBER },
    });
    if (!service) return reply.code(303).redirect(returnTo + (returnTo.includes('?') ? '&' : '?') + 'err=1&msg=service_not_found');
    await prisma.service.update({ where: { id: service.id }, data: { enabled } });
    await prisma.adminAuditLog.create({
      data: {
        adminUserId: admin.id,
        action: 'VIRTUAL_NUMBER_SERVICE_TOGGLE',
        entityType: 'Service',
        entityId: service.id,
        summary: `${service.slug} enabled=${enabled}`,
      },
    });
    return reply.code(303).redirect(returnTo + (returnTo.includes('?') ? '&' : '?') + 'msg=saved');
  });
}
