import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  NotificationAudience,
  PrismaClient,
  SupportStatus,
} from '@prisma/client';
import { z } from 'zod';

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

export function registerClientFoundationRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthHandler,
) {
  app.get('/api/v1/catalog/services', async () => {
    const services = await prisma.service.findMany({
      where: { enabled: true },
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
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gt: now } }] },
        ],
      },
      orderBy: [{ placement: 'asc' }, { sortOrder: 'asc' }],
    });
    return { banners };
  });

  app.get(
    '/api/v1/content/notifications',
    { preHandler: authenticate },
    async (request) => {
      const claims = request.user as JwtClaims;
      const now = new Date();
      const notifications = await prisma.notification.findMany({
        where: {
          enabled: true,
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
        orderBy: { publishAt: 'desc' },
        take: 100,
      });
      return { notifications };
    },
  );

  app.get('/api/v1/orders', { preHandler: authenticate }, async (request) => {
    const claims = request.user as JwtClaims;
    const orders = await prisma.order.findMany({
      where: { userId: claims.sub },
      include: {
        service: {
          select: { slug: true, titleFa: true, titleEn: true, category: true },
        },
      },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
    return {
      orders: orders.map((order) => ({
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
      })),
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
