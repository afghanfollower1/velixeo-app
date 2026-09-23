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
  parsePremiumMetadata,
  premiumMetadataJson,
  premiumPackageAvailable,
  premiumPublicProduct,
  validatePremiumOrderFields,
} from './premiumCatalog.js';
import { decryptProviderSecret } from './providerSecrets.js';
import { publishUserNotification } from './pushNotifications.js';
import {
  premiumPaidOrderTelegramText,
  sendPremiumTelegramMessage,
} from './telegramAdminAlerts.js';

type AuthHandler = (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
type JwtClaims = { sub: string };

const createPremiumOrderSchema = z.object({
  serviceId: z.string().uuid(),
  packageId: z.string().trim().min(1).max(80),
  fields: z.record(z.string(), z.unknown()).default({}),
  clientRequestId: z.string().uuid(),
  termsAccepted: z.literal(true),
});

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function premiumState(order: {
  status: OrderStatus;
  output: Prisma.JsonValue | null;
}) {
  const output = obj(order.output);
  const custom = typeof output.premiumState === 'string' ? output.premiumState : '';
  if (custom) return custom;
  if (order.status === OrderStatus.PROCESSING) return 'PROCESSING';
  if (order.status === OrderStatus.COMPLETED) return 'COMPLETED';
  if (order.status === OrderStatus.REFUNDED) return 'REFUNDED';
  if (order.status === OrderStatus.CANCELLED) return 'CANCELLED';
  if (order.status === OrderStatus.FAILED) return 'FAILED';
  return 'PENDING';
}

function deliveryText(outputValue: Prisma.JsonValue | null) {
  const output = obj(outputValue);
  const encrypted = obj(output.deliverySecret);
  if (!encrypted.ciphertext || !encrypted.iv || !encrypted.tag) return null;
  try {
    return decryptProviderSecret({
      secretCiphertext: String(encrypted.ciphertext),
      secretIv: String(encrypted.iv),
      secretTag: String(encrypted.tag),
    });
  } catch {
    return null;
  }
}

function premiumOrderJson(order: any) {
  const input = obj(order.input);
  const output = obj(order.output);
  const service = order.service;
  return {
    id: order.id,
    publicOrderNumber: order.publicOrderNumber?.toString() ?? null,
    category: order.category,
    status: order.status,
    premiumState: premiumState(order),
    totalAmountAfn: order.totalAmountAfn.toString(),
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    completedAt: order.completedAt,
    service: service ? {
      id: service.id,
      slug: service.slug,
      titleFa: service.titleFa,
      titleEn: service.titleEn,
    } : null,
    package: input.package ?? null,
    submittedFields: input.submittedFields ?? {},
    deliveryMinHours: input.deliveryMinHours ?? null,
    deliveryMaxHours: input.deliveryMaxHours ?? null,
    adminMessageFa: typeof output.adminMessageFa === 'string' ? output.adminMessageFa : null,
    adminMessageEn: typeof output.adminMessageEn === 'string' ? output.adminMessageEn : null,
    deliveryText: deliveryText(order.output),
  };
}

async function sendPaidOrderAlerts(prisma: PrismaClient, order: any) {
  const input = obj(order.input);
  const packageSnapshot = obj(input.package);
  const fieldLabels = obj(input.fieldLabels);
  const submitted = obj(input.submittedFields);
  const user = order.user;
  const fields = Object.entries(submitted)
    .filter(([, value]) => typeof value === 'string' && value.trim())
    .slice(0, 20)
    .map(([key, value]) => ({
      label: String(fieldLabels[key] ?? key),
      value: String(value),
    }));

  let result: { configured: boolean; sent: boolean; reason: string | null | undefined };
  try {
    result = await sendPremiumTelegramMessage(
      prisma,
      premiumPaidOrderTelegramText({
        orderId: order.id,
        publicOrderNumber: order.publicOrderNumber?.toString() ?? null,
        customer: user.fullName || user.email || user.phone || 'VELIXEO customer',
        customerContact: user.email || user.phone || '',
        product: order.service?.titleEn || order.service?.titleFa || 'Premium',
        packageTitle: String(packageSnapshot.titleEn ?? packageSnapshot.titleFa ?? packageSnapshot.id ?? 'Package'),
        amountAfn: order.totalAmountAfn.toString(),
        deliveryHours: Number(input.deliveryMaxHours ?? 12),
        fields,
      }),
    );
  } catch (error) {
    result = {
      configured: true,
      sent: false,
      reason: error instanceof Error ? error.message.slice(0, 500) : 'telegram_failed',
    };
  }

  await prisma.orderActionLog.create({
    data: {
      orderId: order.id,
      action: 'ADMIN_ALERT',
      status: result.sent ? 'SENT' : 'NOT_SENT',
      response: {
        channel: 'TELEGRAM',
        configured: result.configured,
        sent: result.sent,
        reason: result.reason ?? null,
      },
    },
  });

  return result;
}

export function registerPremiumRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthHandler,
) {
  app.get('/api/v1/premium/catalog', async () => {
    const [services, banner] = await Promise.all([
      prisma.service.findMany({
        where: { category: ServiceCategory.PREMIUM, enabled: true },
        orderBy: [{ featured: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
      }),
      prisma.banner.findFirst({
        where: {
          placement: BannerPlacement.SERVICES_TOP,
          enabled: true,
          actionUrl: 'velixeo://premium',
        },
        orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }],
      }),
    ]);

    return {
      baseCurrency: 'AFN',
      banner,
      products: services
        .map(premiumPublicProduct)
        .filter((product) => ['MESSAGING', 'SOCIAL', 'OTHER'].includes(product.group))
        .filter((product) => product.packages.length > 0),
    };
  });

  app.get('/api/v1/premium/orders', { preHandler: authenticate }, async (request) => {
    const userId = (request.user as JwtClaims).sub;
    const orders = await prisma.order.findMany({
      where: { userId, category: ServiceCategory.PREMIUM },
      include: { service: true },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return { orders: orders.map(premiumOrderJson) };
  });

  app.post('/api/v1/premium/orders', { preHandler: authenticate }, async (request, reply) => {
    const parsed = createPremiumOrderSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const userId = (request.user as JwtClaims).sub;

    const existing = await prisma.order.findUnique({
      where: { clientRequestId: parsed.data.clientRequestId },
      include: { service: true },
    });
    if (existing) {
      if (existing.userId !== userId || existing.category !== ServiceCategory.PREMIUM) {
        return reply.code(409).send({ error: 'idempotency_conflict' });
      }
      const wallet = await prisma.wallet.findUnique({ where: { userId } });
      return {
        order: premiumOrderJson(existing),
        balanceAfn: (wallet?.balanceAfn ?? 0n).toString(),
        idempotent: true,
      };
    }

    const service = await prisma.service.findFirst({
      where: {
        id: parsed.data.serviceId,
        category: ServiceCategory.PREMIUM,
        enabled: true,
      },
    });
    if (!service) return reply.code(404).send({ error: 'service_unavailable' });

    const initialMeta = parsePremiumMetadata(service.metadata);
    const initialPackage = initialMeta.packages.find((pkg) => pkg.id === parsed.data.packageId);
    if (!initialPackage || !premiumPackageAvailable(initialPackage)) {
      return reply.code(409).send({ error: 'package_unavailable' });
    }

    let submittedFields: Record<string, string>;
    try {
      submittedFields = validatePremiumOrderFields(initialMeta.formFields, parsed.data.fields);
    } catch (error) {
      return reply.code(400).send({
        error: error instanceof Error ? error.message : 'invalid_order_fields',
      });
    }

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

          const meta = parsePremiumMetadata(lockedService.metadata);
          const packageIndex = meta.packages.findIndex((pkg) => pkg.id === parsed.data.packageId);
          if (packageIndex < 0) throw new Error('PACKAGE_UNAVAILABLE');
          const pkg = meta.packages[packageIndex];
          if (!premiumPackageAvailable(pkg)) throw new Error('PACKAGE_UNAVAILABLE');

          const priceAfn = BigInt(pkg.priceAfn);
          if (priceAfn <= 0n) throw new Error('INVALID_PRICE');

          const wallet = await tx.wallet.findUnique({ where: { userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');
          if (wallet.balanceAfn < priceAfn) throw new Error('INSUFFICIENT_FUNDS');

          await tx.$executeRaw`SELECT pg_advisory_xact_lock(764208315)`;
          const latest = await tx.order.findFirst({
            where: { publicOrderNumber: { not: null } },
            orderBy: { publicOrderNumber: 'desc' },
            select: { publicOrderNumber: true },
          });
          const publicOrderNumber = (latest?.publicOrderNumber ?? 100000n) + 1n;

          const fieldLabels = Object.fromEntries(
            meta.formFields.map((field) => [field.key, field.labelEn || field.labelFa || field.key]),
          );
          const created = await tx.order.create({
            data: {
              userId,
              serviceId: lockedService.id,
              category: ServiceCategory.PREMIUM,
              status: OrderStatus.PENDING,
              quantity: 1,
              baseAmountAfn: priceAfn,
              totalAmountAfn: priceAfn,
              publicOrderNumber,
              clientRequestId: parsed.data.clientRequestId,
              input: {
                packageId: pkg.id,
                package: {
                  id: pkg.id,
                  titleFa: pkg.titleFa,
                  titleEn: pkg.titleEn,
                  durationFa: pkg.durationFa,
                  durationEn: pkg.durationEn,
                  priceAfn: pkg.priceAfn,
                },
                deliveryType: meta.deliveryType,
                deliveryMinHours: meta.deliveryMinHours,
                deliveryMaxHours: meta.deliveryMaxHours,
                submittedFields,
                fieldLabels,
                termsAccepted: true,
                termsAcceptedAt: new Date().toISOString(),
                paymentSource: 'WALLET',
              },
              output: {
                premiumState: 'PENDING',
                paidAt: new Date().toISOString(),
              },
            },
          });

          const nextBalance = wallet.balanceAfn - priceAfn;
          await tx.wallet.update({
            where: { id: wallet.id },
            data: { balanceAfn: nextBalance },
          });
          await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.PURCHASE,
              status: WalletEntryStatus.COMPLETED,
              amountAfn: -priceAfn,
              balanceAfterAfn: nextBalance,
              referenceType: 'PREMIUM_ORDER_PURCHASE',
              referenceId: created.id,
              description: `Premium order #${publicOrderNumber.toString()}`,
              idempotencyKey: `premium-order-purchase-${created.id}`,
            },
          });

          if (pkg.stock != null) {
            meta.packages[packageIndex] = { ...pkg, stock: Math.max(0, pkg.stock - 1) };
            await tx.service.update({
              where: { id: lockedService.id },
              data: {
                metadata: premiumMetadataJson(meta),
                basePriceAfn: meta.packages
                  .filter((item) => premiumPackageAvailable(item))
                  .map((item) => BigInt(item.priceAfn))
                  .sort((a, b) => a < b ? -1 : a > b ? 1 : 0)[0] ?? null,
              },
            });
          }

          return { order: created, balanceAfn: nextBalance, idempotent: false };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      const code = error instanceof Error ? error.message : 'premium_order_failed';
      if (code === 'INSUFFICIENT_FUNDS') return reply.code(409).send({ error: 'insufficient_funds' });
      if (code === 'WALLET_NOT_FOUND') return reply.code(404).send({ error: 'wallet_not_found' });
      if (code === 'PACKAGE_UNAVAILABLE') return reply.code(409).send({ error: 'package_unavailable' });
      throw error;
    }

    const order = await prisma.order.findUnique({
      where: { id: result.order.id },
      include: { service: true, user: true },
    });
    if (!order) return reply.code(500).send({ error: 'order_not_found_after_create' });

    if (!result.idempotent) {
      try {
        await publishUserNotification(prisma, userId, {
          type: NotificationType.ORDER,
          priority: NotificationPriority.HIGH,
          titleFa: 'سفارش پریمیوم ثبت شد',
          titleEn: 'Premium order received',
          bodyFa: `پرداخت سفارش #${order.publicOrderNumber?.toString() ?? order.id.slice(0, 8)} انجام شد و سفارش در صف فعال‌سازی قرار گرفت.`,
          bodyEn: `Payment for order #${order.publicOrderNumber?.toString() ?? order.id.slice(0, 8)} is complete and your order is now queued for fulfillment.`,
          actionRoute: 'orders',
          actionEntityId: order.id,
          actionLabelFa: 'مشاهده سفارش',
          actionLabelEn: 'View order',
        });
      } catch {
        // The paid order remains valid even if push/in-app notification publishing fails.
      }
      await sendPaidOrderAlerts(prisma, order);
    }

    return reply.code(result.idempotent ? 200 : 201).send({
      order: premiumOrderJson(order),
      balanceAfn: result.balanceAfn.toString(),
      idempotent: result.idempotent,
    });
  });
}
