import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  BannerPlacement,
  NotificationPriority,
  NotificationType,
  OrderStatus,
  Prisma,
  PrismaClient,
  ServiceCategory,
  WalletEntryStatus,
  WalletEntryType,
} from '@prisma/client';
import { z } from 'zod';
import {
  parsePromotionMetadata,
  promotionPublicProduct,
  type PromotionObjective,
} from './promotionCatalog.js';
import { publishUserNotification } from './pushNotifications.js';
import { sendAdminOrderAlert } from './adminTelegramEvents.js';

type AuthenticateHook = (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
type JwtClaims = { sub: string };

const createOrderSchema = z.object({
  serviceId: z.string().uuid(),
  packageId: z.string().trim().min(1).max(80),
  postUrl: z.string().url().max(1200),
  partnershipAdCode: z.string().trim().max(1200).optional().default(''),
  objective: z.enum(['ENGAGEMENT', 'PROFILE_VISITS', 'MESSAGES', 'WEBSITE_VISITS', 'AWARENESS']),
  targetCountries: z.array(z.string().trim().min(2).max(80)).min(1).max(10),
  audienceNotes: z.string().trim().max(1200).optional().default(''),
  websiteUrl: z.string().url().max(1200).optional().or(z.literal('')).default(''),
  metaConnectionId: z.string().uuid().optional(),
  instagramMediaId: z.string().trim().max(120).optional(),
  clientRequestId: z.string().uuid(),
  termsAccepted: z.literal(true),
});

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function stateOf(order: { status: OrderStatus; output: Prisma.JsonValue | null }) {
  const output = obj(order.output);
  const custom = typeof output.promotionState === 'string' ? output.promotionState : '';
  if (custom) return custom;
  if (order.status === OrderStatus.PROCESSING) return 'PROCESSING';
  if (order.status === OrderStatus.COMPLETED) return 'COMPLETED';
  if (order.status === OrderStatus.REFUNDED) return 'REFUNDED';
  if (order.status === OrderStatus.CANCELLED) return 'CANCELLED';
  if (order.status === OrderStatus.FAILED) return 'FAILED';
  return 'PENDING';
}

function orderJson(order: any) {
  const input = obj(order.input);
  const output = obj(order.output);
  return {
    id: order.id,
    publicOrderNumber: order.publicOrderNumber?.toString() ?? null,
    category: order.category,
    status: order.status,
    promotionState: stateOf(order),
    totalAmountAfn: order.totalAmountAfn.toString(),
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    completedAt: order.completedAt,
    service: order.service ? {
      id: order.service.id,
      slug: order.service.slug,
      titleFa: order.service.titleFa,
      titleEn: order.service.titleEn,
    } : null,
    package: input.package ?? null,
    platform: input.platform ?? null,
    postUrl: input.postUrl ?? null,
    objective: input.objective ?? null,
    targetCountries: input.targetCountries ?? [],
    audienceNotes: input.audienceNotes ?? null,
    websiteUrl: input.websiteUrl ?? null,
    metaConnectionId: input.metaConnectionId ?? null,
    instagramMediaId: input.instagramMediaId ?? null,
    instagramUsername: input.instagramUsername ?? null,
    instagramPageName: input.instagramPageName ?? null,
    partnershipAdCode: input.partnershipAdCode ?? null,
    deliveryMinHours: input.deliveryMinHours ?? null,
    deliveryMaxHours: input.deliveryMaxHours ?? null,
    adminMessageFa: typeof output.adminMessageFa === 'string' ? output.adminMessageFa : null,
    adminMessageEn: typeof output.adminMessageEn === 'string' ? output.adminMessageEn : null,
    metaCampaignId: typeof output.metaCampaignId === 'string' ? output.metaCampaignId : null,
    metaAdId: typeof output.metaAdId === 'string' ? output.metaAdId : null,
    resultSummaryFa: typeof output.resultSummaryFa === 'string' ? output.resultSummaryFa : null,
    resultSummaryEn: typeof output.resultSummaryEn === 'string' ? output.resultSummaryEn : null,
  };
}

export function registerPromotionRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
) {
  app.get('/api/v1/promotions/catalog', async () => {
    const [services, banner] = await Promise.all([
      prisma.service.findMany({
        where: { category: ServiceCategory.PROMOTION, enabled: true },
        orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
      }),
      prisma.banner.findFirst({
        where: {
          placement: BannerPlacement.SERVICES_TOP,
          enabled: true,
          actionUrl: 'velixeo://promotions',
        },
        orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }],
      }),
    ]);
    return {
      baseCurrency: 'AFN',
      fulfillmentMode: 'MANUAL_META_ADS_V1',
      banner,
      products: services
        .map(promotionPublicProduct)
        .filter((product) => product.packages.length > 0),
    };
  });

  app.get('/api/v1/promotions/orders', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const orders = await prisma.order.findMany({
      where: { userId, category: ServiceCategory.PROMOTION },
      include: { service: true },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { orders: orders.map(orderJson) };
  });

  app.post('/api/v1/promotions/orders', { preHandler: authenticate }, async (request, reply) => {
    const parsed = createOrderSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;

    const existing = await prisma.order.findUnique({
      where: { clientRequestId: parsed.data.clientRequestId },
      include: { service: true },
    });
    if (existing) {
      if (existing.userId !== userId || existing.category !== ServiceCategory.PROMOTION) {
        return reply.code(409).send({ error: 'idempotency_conflict' });
      }
      const wallet = await prisma.wallet.findUnique({ where: { userId } });
      return {
        order: orderJson(existing),
        balanceAfn: (wallet?.balanceAfn ?? 0n).toString(),
        idempotent: true,
      };
    }

    const service = await prisma.service.findFirst({
      where: {
        id: parsed.data.serviceId,
        category: ServiceCategory.PROMOTION,
        enabled: true,
      },
    });
    if (!service) return reply.code(404).send({ error: 'service_unavailable' });

    const meta = parsePromotionMetadata(service.metadata);
    const pkg = meta.packages.find((item) => item.id === parsed.data.packageId && item.enabled);
    if (!pkg) return reply.code(409).send({ error: 'package_unavailable' });
    if (!meta.supportedObjectives.includes(parsed.data.objective as PromotionObjective)) {
      return reply.code(400).send({ error: 'objective_unavailable' });
    }
    if (meta.requirePartnershipAdCode && !parsed.data.partnershipAdCode.trim() && !parsed.data.metaConnectionId) {
      return reply.code(400).send({ error: 'partnership_ad_code_required' });
    }
    if (parsed.data.objective === 'WEBSITE_VISITS' && !parsed.data.websiteUrl.trim()) {
      return reply.code(400).send({ error: 'website_url_required' });
    }

    let metaConnection: any = null;
    if (parsed.data.metaConnectionId) {
      metaConnection = await prisma.metaConnection.findFirst({
        where: { id: parsed.data.metaConnectionId, userId, status: 'CONNECTED' },
      });
      if (!metaConnection) return reply.code(409).send({ error: 'meta_connection_unavailable' });
    }

    const priceAfn = BigInt(pkg.priceAfn);
    let result;
    try {
      result = await prisma.$transaction(
        async (tx) => {
          const duplicate = await tx.order.findUnique({
            where: { clientRequestId: parsed.data.clientRequestId },
          });
          if (duplicate) {
            const wallet = await tx.wallet.findUnique({ where: { userId } });
            return { order: duplicate, balanceAfn: wallet?.balanceAfn ?? 0n, idempotent: true };
          }

          await tx.$executeRaw`SELECT 1 FROM "Service" WHERE id = ${service.id} FOR UPDATE`;
          const lockedService = await tx.service.findUnique({ where: { id: service.id } });
          if (!lockedService || !lockedService.enabled) throw new Error('PACKAGE_UNAVAILABLE');
          const lockedMeta = parsePromotionMetadata(lockedService.metadata);
          const lockedPackage = lockedMeta.packages.find((item) => item.id === parsed.data.packageId && item.enabled);
          if (!lockedPackage) throw new Error('PACKAGE_UNAVAILABLE');
          const lockedPrice = BigInt(lockedPackage.priceAfn);

          const wallet = await tx.wallet.findUnique({ where: { userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');
          if (wallet.balanceAfn < lockedPrice) throw new Error('INSUFFICIENT_FUNDS');

          await tx.$executeRaw`SELECT pg_advisory_xact_lock(764208315)`;
          const latest = await tx.order.findFirst({
            where: { publicOrderNumber: { not: null } },
            orderBy: { publicOrderNumber: 'desc' },
            select: { publicOrderNumber: true },
          });
          const publicOrderNumber = (latest?.publicOrderNumber ?? 100000n) + 1n;

          const created = await tx.order.create({
            data: {
              userId,
              serviceId: lockedService.id,
              category: ServiceCategory.PROMOTION,
              status: OrderStatus.PENDING,
              quantity: 1,
              baseAmountAfn: lockedPrice,
              totalAmountAfn: lockedPrice,
              publicOrderNumber,
              clientRequestId: parsed.data.clientRequestId,
              input: {
                platform: lockedMeta.platform,
                packageId: lockedPackage.id,
                package: {
                  id: lockedPackage.id,
                  titleFa: lockedPackage.titleFa,
                  titleEn: lockedPackage.titleEn,
                  priceAfn: lockedPackage.priceAfn,
                  adBudgetAfn: lockedPackage.adBudgetAfn,
                  serviceFeeAfn: lockedPackage.serviceFeeAfn,
                  durationDays: lockedPackage.durationDays,
                },
                postUrl: parsed.data.postUrl,
                partnershipAdCode: parsed.data.partnershipAdCode.trim(),
                objective: parsed.data.objective,
                targetCountries: parsed.data.targetCountries,
                audienceNotes: parsed.data.audienceNotes,
                websiteUrl: parsed.data.websiteUrl,
                metaConnectionId: metaConnection?.id ?? null,
                instagramMediaId: parsed.data.instagramMediaId ?? null,
                instagramUsername: metaConnection?.instagramUsername ?? null,
                instagramUserId: metaConnection?.instagramUserId ?? null,
                instagramPageId: metaConnection?.pageId ?? null,
                instagramPageName: metaConnection?.pageName ?? null,
                metaAdvertisingReady: Boolean(
                  metaConnection && Array.isArray(metaConnection.pageTasks) && metaConnection.pageTasks.includes('ADVERTISE'),
                ),
                deliveryMinHours: lockedMeta.deliveryMinHours,
                deliveryMaxHours: lockedMeta.deliveryMaxHours,
                termsAccepted: true,
                termsAcceptedAt: new Date().toISOString(),
                paymentSource: 'WALLET',
                fulfillmentMode: 'MANUAL_META_ADS_V1',
              },
              output: {
                promotionState: 'PENDING_REVIEW',
                paidAt: new Date().toISOString(),
              },
            },
          });

          const nextBalance = wallet.balanceAfn - lockedPrice;
          await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: nextBalance } });
          await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.PURCHASE,
              status: WalletEntryStatus.COMPLETED,
              amountAfn: -lockedPrice,
              balanceAfterAfn: nextBalance,
              referenceType: 'PROMOTION_ORDER_PURCHASE',
              referenceId: created.id,
              description: `Promotion order #${publicOrderNumber.toString()}`,
              idempotencyKey: `promotion-order-purchase-${created.id}`,
            },
          });

          return { order: created, balanceAfn: nextBalance, idempotent: false };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      const code = error instanceof Error ? error.message : 'promotion_order_failed';
      if (code === 'INSUFFICIENT_FUNDS') return reply.code(409).send({ error: 'insufficient_funds' });
      if (code === 'WALLET_NOT_FOUND') return reply.code(404).send({ error: 'wallet_not_found' });
      if (code === 'PACKAGE_UNAVAILABLE') return reply.code(409).send({ error: 'package_unavailable' });
      throw error;
    }

    const order = await prisma.order.findUnique({
      where: { id: result.order.id },
      include: { service: true },
    });
    if (!order) return reply.code(500).send({ error: 'order_not_found_after_create' });

    if (!result.idempotent) {
      try {
        await publishUserNotification(prisma, userId, {
          type: NotificationType.PROMOTION,
          priority: NotificationPriority.HIGH,
          titleFa: 'سفارش تبلیغ ثبت شد',
          titleEn: 'Promotion order received',
          bodyFa: `پرداخت سفارش #${order.publicOrderNumber?.toString() ?? order.id.slice(0, 8)} انجام شد و سفارش برای بررسی مجوز تبلیغ وارد صف شد.`,
          bodyEn: `Payment for order #${order.publicOrderNumber?.toString() ?? order.id.slice(0, 8)} is complete and the ad authorization is queued for review.`,
          actionRoute: 'orders',
          actionEntityId: order.id,
          actionLabelFa: 'مشاهده سفارش',
          actionLabelEn: 'View order',
        });
      } catch {}
      try {
        await sendAdminOrderAlert(prisma, order.id, 'Promotion order paid; review the connected Instagram account and selected post, then launch the ad manually in Meta Ads Manager.');
      } catch (error) {
        request.log.warn({ error, orderId: order.id }, 'admin Telegram promotion order alert failed');
      }
    }

    return reply.code(result.idempotent ? 200 : 201).send({
      order: orderJson(order),
      balanceAfn: result.balanceAfn.toString(),
      idempotent: result.idempotent,
    });
  });
}
