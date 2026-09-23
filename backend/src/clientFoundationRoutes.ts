import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  NotificationAudience,
  NotificationType,
  OrderStatus,
  PrismaClient,
  ServiceCategory,
  SupportStatus,
} from '@prisma/client';
import { z } from 'zod';
import { firebaseClientConfig } from './pushNotifications.js';

type AuthHandler = (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>;
type JwtClaims = { sub: string };

const ticketCreateSchema = z.object({
  subject: z.string().trim().min(3).max(180),
  message: z.string().trim().min(1).max(5000),
});

const ticketMessageSchema = z.object({
  message: z.string().trim().min(1).max(5000),
});

const ticketParamsSchema = z.object({ id: z.string().uuid() });
const notificationParamsSchema = z.object({ id: z.string().uuid() });
const pushDeviceSchema = z.object({
  token: z.string().trim().min(20).max(4096),
  platform: z.enum(['ANDROID', 'IOS']).default('ANDROID'),
});

function orderJsonObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function clientOrderRows(order: any) {
  const base = {
    id: order.id,
    category: order.category,
    status: order.status,
    quantity: order.quantity,
    baseAmountAfn: order.baseAmountAfn.toString(),
    totalAmountAfn: order.totalAmountAfn.toString(),
    input: order.input,
    output: order.output,
    failureReason: order.failureReason,
    createdAt: order.createdAt,
    updatedAt: order.updatedAt,
    completedAt: order.completedAt,
    service: order.service,
  };
  if (String(order.category) !== 'SOCIAL') return [base];

  const input = orderJsonObject(order.input);
  const params = orderJsonObject(input.parameters);
  const runs = Math.max(1, Number(input.runs ?? params.runs ?? 1) || 1);
  if (input.dripFeed !== true && runs <= 1) return [base];

  const interval = Math.max(0, Number(input.intervalMinutes ?? params.interval ?? 0) || 0);
  const unitQuantity = Math.max(0, Number(input.unitQuantity ?? params.quantity ?? order.quantity ?? 0) || 0);
  const output = orderJsonObject(order.output);
  const raw = orderJsonObject(output.providerRawStatus);
  const explicitCurrent = Number(raw.runs_current ?? raw.current_run ?? raw.run ?? NaN);
  const elapsed = Math.max(0, Date.now() - new Date(order.createdAt).getTime());
  const scheduledCurrent = interval > 0
    ? Math.min(runs, Math.max(1, Math.floor(elapsed / (interval * 60_000)) + 1))
    : 1;
  const current = Number.isFinite(explicitCurrent)
    ? Math.max(0, Math.min(runs, explicitCurrent))
    : scheduledCurrent;
  const dripStatus = String(raw.status_name ?? raw.drip_feed_status ?? raw.dripfeed_status ?? 'Active')
    .trim()
    .toLowerCase();
  const finished = ['finished', 'completed', 'complete'].includes(dripStatus);
  const stopped = ['stopped', 'cancelled', 'canceled', 'failed', 'refunded'].includes(dripStatus);
  const totalAmount = BigInt(order.totalAmountAfn);
  const baseAmount = BigInt(order.baseAmountAfn);
  const divisor = BigInt(runs);
  const totalShare = totalAmount / divisor;
  const baseShare = baseAmount / divisor;

  return Array.from({ length: runs }, (_, offset) => {
    const index = offset + 1;
    let status: OrderStatus;
    if (finished) status = OrderStatus.COMPLETED;
    else if (stopped) status = index < current ? OrderStatus.COMPLETED : OrderStatus.CANCELLED;
    else if (index < current) status = OrderStatus.COMPLETED;
    else if (index === current && current > 0) status = OrderStatus.PROCESSING;
    else status = OrderStatus.PENDING;
    const scheduledAt = new Date(new Date(order.createdAt).getTime() + offset * interval * 60_000);
    const runTotal = index === runs ? totalAmount - (totalShare * BigInt(runs - 1)) : totalShare;
    const runBase = index === runs ? baseAmount - (baseShare * BigInt(runs - 1)) : baseShare;
    return {
      ...base,
      id: `${order.id}:run:${index}`,
      status,
      quantity: unitQuantity,
      baseAmountAfn: runBase.toString(),
      totalAmountAfn: runTotal.toString(),
      createdAt: scheduledAt,
      dripRun: {
        parentOrderId: order.id,
        runIndex: index,
        runsAll: runs,
        interval,
        scheduledAt,
      },
    };
  });
}

export function registerClientFoundationRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthHandler,
) {
  app.get('/api/v1/catalog/services', async () => {
    const services = await prisma.service.findMany({
      where: { enabled: true, category: { notIn: [ServiceCategory.PROMOTION, ServiceCategory.MOBILE_TOPUP] } },
      orderBy: [{ featured: 'desc' }, { category: 'asc' }, { sortOrder: 'asc' }],
      select: {
        id: true,
        category: true,
        slug: true,
        titleFa: true,
        titleEn: true,
        descriptionFa: true,
        descriptionEn: true,
        featured: true,
        sortOrder: true,
        basePriceAfn: true,
        minQty: true,
        maxQty: true,
        metadata: true,
      },
    });
    return {
      baseCurrency: 'AFN',
      services: services.map((service) => ({
        ...service,
        basePriceAfn: service.basePriceAfn?.toString() ?? null,
      })),
    };
  });

  app.get('/api/v1/content/banners', async () => {
    const now = new Date();
    const banners = await prisma.banner.findMany({
      where: {
        enabled: true,
        NOT: { actionUrl: { in: ['velixeo://promotions', 'velixeo://promotion'] } },
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gt: now } }] },
        ],
      },
      orderBy: [{ placement: 'asc' }, { sortOrder: 'asc' }],
    });
    return { banners };
  });

  app.get('/api/v1/content/push-config', async () => firebaseClientConfig());

  app.get(
    '/api/v1/content/notifications',
    { preHandler: authenticate },
    async (request) => {
      const claims = request.user as JwtClaims;
      const now = new Date();
      const notifications = await prisma.notification.findMany({
        where: {
          enabled: true,
          type: { not: NotificationType.PROMOTION },
          publishAt: { lte: now },
          AND: [
            { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
            {
              OR: [
                { audience: NotificationAudience.ALL },
                { audience: NotificationAudience.USER, userId: claims.sub },
              ],
            },
          ],
        },
        include: {
          reads: {
            where: { userId: claims.sub },
            select: { readAt: true },
            take: 1,
          },
        },
        orderBy: { publishAt: 'desc' },
        take: 100,
      });
      return {
        notifications: notifications.map(({ reads, ...notification }) => ({
          ...notification,
          isRead: reads.length > 0,
          readAt: reads[0]?.readAt ?? null,
        })),
        unreadCount: notifications.reduce((count, notification) => count + (notification.reads.length === 0 ? 1 : 0), 0),
      };
    },
  );

  app.post('/api/v1/content/notifications/:id/read', { preHandler: authenticate }, async (request, reply) => {
    const params = notificationParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as JwtClaims;
    const now = new Date();
    const notification = await prisma.notification.findFirst({
      where: {
        id: params.data.id,
        enabled: true,
        type: { not: NotificationType.PROMOTION },
        publishAt: { lte: now },
        AND: [
          { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
          {
            OR: [
              { audience: NotificationAudience.ALL },
              { audience: NotificationAudience.USER, userId: claims.sub },
            ],
          },
        ],
      },
      select: { id: true },
    });
    if (!notification) return reply.code(404).send({ error: 'notification_not_found' });
    const read = await prisma.notificationRead.upsert({
      where: { notificationId_userId: { notificationId: notification.id, userId: claims.sub } },
      create: { notificationId: notification.id, userId: claims.sub, readAt: now },
      update: { readAt: now },
    });
    return { id: notification.id, isRead: true, readAt: read.readAt };
  });

  app.post('/api/v1/content/notifications/read-all', { preHandler: authenticate }, async (request) => {
    const claims = request.user as JwtClaims;
    const now = new Date();
    const visible = await prisma.notification.findMany({
      where: {
        enabled: true,
        type: { not: NotificationType.PROMOTION },
        publishAt: { lte: now },
        AND: [
          { OR: [{ expiresAt: null }, { expiresAt: { gt: now } }] },
          {
            OR: [
              { audience: NotificationAudience.ALL },
              { audience: NotificationAudience.USER, userId: claims.sub },
            ],
          },
        ],
      },
      select: { id: true },
      take: 100,
    });
    await prisma.$transaction(
      visible.map((notification) => prisma.notificationRead.upsert({
        where: { notificationId_userId: { notificationId: notification.id, userId: claims.sub } },
        create: { notificationId: notification.id, userId: claims.sub, readAt: now },
        update: { readAt: now },
      })),
    );
    return { markedRead: visible.length, readAt: now };
  });

  app.post('/api/v1/push/devices', { preHandler: authenticate }, async (request, reply) => {
    const parsed = pushDeviceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as JwtClaims;
    const device = await prisma.pushDevice.upsert({
      where: { token: parsed.data.token },
      create: {
        userId: claims.sub,
        token: parsed.data.token,
        platform: parsed.data.platform,
        enabled: true,
        lastSeenAt: new Date(),
      },
      update: {
        userId: claims.sub,
        platform: parsed.data.platform,
        enabled: true,
        lastSeenAt: new Date(),
      },
    });
    return { registered: true, deviceId: device.id };
  });

  app.post('/api/v1/push/devices/unregister', { preHandler: authenticate }, async (request, reply) => {
    const parsed = pushDeviceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as JwtClaims;
    await prisma.pushDevice.updateMany({
      where: { token: parsed.data.token, userId: claims.sub },
      data: { enabled: false, lastSeenAt: new Date() },
    });
    return { unregistered: true };
  });

  app.get('/api/v1/orders', { preHandler: authenticate }, async (request) => {
    const claims = request.user as JwtClaims;
    const orders = await prisma.order.findMany({
      where: { userId: claims.sub, category: { not: ServiceCategory.PROMOTION } },
      include: {
        service: {
          select: { slug: true, titleFa: true, titleEn: true, category: true },
        },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return {
      orders: orders.flatMap(clientOrderRows).slice(0, 100),
    };
  });

  app.get('/api/v1/support/tickets', { preHandler: authenticate }, async (request) => {
    const claims = request.user as JwtClaims;
    const tickets = await prisma.supportTicket.findMany({
      where: { userId: claims.sub },
      orderBy: { lastMessageAt: 'desc' },
      include: { messages: { orderBy: { createdAt: 'asc' } } },
      take: 50,
    });
    return { tickets };
  });

  app.post('/api/v1/support/tickets', { preHandler: authenticate }, async (request, reply) => {
    const parsed = ticketCreateSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as JwtClaims;
    const ticket = await prisma.supportTicket.create({
      data: {
        userId: claims.sub,
        subject: parsed.data.subject,
        status: SupportStatus.PENDING_ADMIN,
        messages: {
          create: {
            senderUserId: claims.sub,
            isAdmin: false,
            content: parsed.data.message,
          },
        },
      },
      include: { messages: true },
    });
    return reply.code(201).send({ ticket });
  });

  app.post('/api/v1/support/tickets/:id/messages', { preHandler: authenticate }, async (request, reply) => {
    const params = ticketParamsSchema.safeParse(request.params);
    const parsed = ticketMessageSchema.safeParse(request.body);
    if (!params.success || !parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as JwtClaims;
    const ticket = await prisma.supportTicket.findFirst({ where: { id: params.data.id, userId: claims.sub } });
    if (!ticket) return reply.code(404).send({ error: 'ticket_not_found' });
    if (ticket.status === SupportStatus.CLOSED) return reply.code(409).send({ error: 'ticket_closed' });
    const [message] = await prisma.$transaction([
      prisma.supportMessage.create({
        data: {
          ticketId: ticket.id,
          senderUserId: claims.sub,
          isAdmin: false,
          content: parsed.data.message,
        },
      }),
      prisma.supportTicket.update({
        where: { id: ticket.id },
        data: { status: SupportStatus.PENDING_ADMIN, lastMessageAt: new Date() },
      }),
    ]);
    return reply.code(201).send({ message });
  });

  app.get('/api/v1/system/public-config', async () => {
    const settings = await prisma.systemSetting.findMany({
      where: { key: { startsWith: 'public.' } },
      orderBy: { key: 'asc' },
      select: { key: true, value: true, updatedAt: true },
    });
    return { settings };
  });
}
