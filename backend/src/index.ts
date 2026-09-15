import 'dotenv/config';
import Fastify, { FastifyReply, FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import bcrypt from 'bcryptjs';
import { createHash, randomBytes } from 'node:crypto';
import {
  AppLocale,
  DisplayCurrency,
  Prisma,
  PrismaClient,
  UserRole,
  WalletEntryType,
} from '@prisma/client';
import { z } from 'zod';

const env = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(8080),
    DATABASE_URL: z.string().min(1),
    JWT_SECRET: z.string().min(32),
    CORS_ORIGINS: z.string().default(''),
    ACCESS_TOKEN_TTL: z.string().default('15m'),
    REFRESH_TOKEN_DAYS: z.coerce.number().int().positive().default(30),
  })
  .parse(process.env);

const prisma = new PrismaClient();
const app = Fastify({
  logger: true,
  trustProxy: true,
});

const allowedOrigins = env.CORS_ORIGINS.split(',')
  .map((value) => value.trim())
  .filter(Boolean);

await app.register(cors, {
  origin: env.NODE_ENV === 'production' ? allowedOrigins : true,
  credentials: true,
});
await app.register(jwt, { secret: env.JWT_SECRET });
await app.register(rateLimit, {
  max: 120,
  timeWindow: '1 minute',
});

const registerSchema = z
  .object({
    email: z.string().trim().email().optional(),
    phone: z.string().trim().min(7).max(32).optional(),
    password: z.string().min(8).max(128),
    locale: z.enum(['FA', 'EN']).default('FA'),
  })
  .refine((data) => Boolean(data.email || data.phone), {
    message: 'email_or_phone_required',
  });

const loginSchema = z.object({
  identifier: z.string().trim().min(3).max(254),
  password: z.string().min(1).max(128),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(40),
});

const preferenceSchema = z
  .object({
    locale: z.enum(['FA', 'EN']).optional(),
    displayCurrency: z.enum(['AFN', 'USD', 'TOMAN']).optional(),
  })
  .refine((data) => data.locale !== undefined || data.displayCurrency !== undefined, {
    message: 'no_changes_requested',
  });

const adminAdjustmentSchema = z.object({
  userId: z.string().uuid(),
  amountAfn: z.string().regex(/^-?\d+$/),
  reason: z.string().trim().min(3).max(300),
  idempotencyKey: z.string().trim().min(8).max(200).optional(),
});

const rateSchema = z.object({
  code: z.enum(['USD', 'TOMAN']),
  afnPerUnit: z.string().regex(/^\d+(\.\d{1,8})?$/),
});

type JwtClaims = {
  sub: string;
  role: UserRole;
};

function normalizeEmail(email?: string) {
  return email?.trim().toLowerCase();
}

function normalizePhone(phone?: string) {
  return phone?.replace(/\s+/g, '');
}

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}

function newRefreshToken() {
  return randomBytes(48).toString('base64url');
}

function accessTokenFor(user: { id: string; role: UserRole }) {
  return app.jwt.sign(
    { sub: user.id, role: user.role },
    { expiresIn: env.ACCESS_TOKEN_TTL },
  );
}

async function createSession(user: { id: string; role: UserRole }) {
  const refreshToken = newRefreshToken();
  const expiresAt = new Date(
    Date.now() + env.REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000,
  );

  await prisma.refreshToken.create({
    data: {
      userId: user.id,
      tokenHash: hashToken(refreshToken),
      expiresAt,
    },
  });

  return {
    accessToken: accessTokenFor(user),
    refreshToken,
    expiresIn: env.ACCESS_TOKEN_TTL,
  };
}

async function authenticate(request: FastifyRequest, reply: FastifyReply) {
  try {
    await request.jwtVerify();
  } catch {
    return reply.code(401).send({ error: 'unauthorized' });
  }
}

async function requireAdmin(request: FastifyRequest, reply: FastifyReply) {
  const authResult = await authenticate(request, reply);
  if (authResult) return authResult;
  const claims = request.user as JwtClaims;
  if (claims.role !== UserRole.ADMIN) {
    return reply.code(403).send({ error: 'admin_required' });
  }
}

function publicUser(user: {
  id: string;
  email: string | null;
  phone: string | null;
  role: UserRole;
  locale: AppLocale;
  displayCurrency: DisplayCurrency;
  createdAt: Date;
}) {
  return {
    id: user.id,
    email: user.email,
    phone: user.phone,
    role: user.role,
    locale: user.locale,
    displayCurrency: user.displayCurrency,
    createdAt: user.createdAt,
  };
}

async function applyWalletDelta(input: {
  userId: string;
  amountAfn: bigint;
  type: WalletEntryType;
  description: string;
  idempotencyKey?: string;
  referenceType?: string;
  referenceId?: string;
}) {
  if (input.amountAfn === 0n) throw new Error('ZERO_AMOUNT');

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await prisma.$transaction(
        async (tx) => {
          if (input.idempotencyKey) {
            const existing = await tx.walletEntry.findUnique({
              where: { idempotencyKey: input.idempotencyKey },
            });
            if (existing) return existing;
          }

          const wallet = await tx.wallet.findUnique({
            where: { userId: input.userId },
          });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');

          const nextBalance = wallet.balanceAfn + input.amountAfn;
          if (nextBalance < 0n) throw new Error('INSUFFICIENT_FUNDS');

          await tx.wallet.update({
            where: { id: wallet.id },
            data: { balanceAfn: nextBalance },
          });

          return tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: input.type,
              amountAfn: input.amountAfn,
              balanceAfterAfn: nextBalance,
              description: input.description,
              idempotencyKey: input.idempotencyKey,
              referenceType: input.referenceType,
              referenceId: input.referenceId,
            },
          });
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2034' &&
        attempt < 3
      ) {
        continue;
      }
      throw error;
    }
  }

  throw new Error('WALLET_TRANSACTION_FAILED');
}

app.get('/health', async (_request, reply) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    return { status: 'ok', service: 'velixeo-api' };
  } catch {
    return reply.code(503).send({ status: 'degraded', service: 'velixeo-api' });
  }
});

app.post('/api/v1/auth/register', async (request, reply) => {
  const parsed = registerSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'invalid_request', details: parsed.error.flatten() });
  }

  const email = normalizeEmail(parsed.data.email);
  const phone = normalizePhone(parsed.data.phone);

  if (email) {
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return reply.code(409).send({ error: 'email_already_registered' });
  }
  if (phone) {
    const existing = await prisma.user.findUnique({ where: { phone } });
    if (existing) return reply.code(409).send({ error: 'phone_already_registered' });
  }

  const passwordHash = await bcrypt.hash(parsed.data.password, 12);
  const user = await prisma.user.create({
    data: {
      email: email ?? null,
      phone: phone ?? null,
      passwordHash,
      locale: parsed.data.locale as AppLocale,
      wallet: { create: {} },
    },
  });

  const session = await createSession(user);
  return reply.code(201).send({
    user: publicUser(user),
    ...session,
  });
});

app.post('/api/v1/auth/login', async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  const rawIdentifier = parsed.data.identifier;
  const emailIdentifier = rawIdentifier.includes('@')
    ? rawIdentifier.toLowerCase()
    : '__not_an_email__';
  const phoneIdentifier = normalizePhone(rawIdentifier) ?? rawIdentifier;

  const user = await prisma.user.findFirst({
    where: {
      OR: [{ email: emailIdentifier }, { phone: phoneIdentifier }],
    },
  });

  if (!user || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return reply.code(401).send({ error: 'invalid_credentials' });
  }

  const session = await createSession(user);
  return { user: publicUser(user), ...session };
});

app.post('/api/v1/auth/refresh', async (request, reply) => {
  const parsed = refreshSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  const stored = await prisma.refreshToken.findUnique({
    where: { tokenHash: hashToken(parsed.data.refreshToken) },
    include: { user: true },
  });

  if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) {
    return reply.code(401).send({ error: 'invalid_refresh_token' });
  }

  const nextRefreshToken = newRefreshToken();
  const nextExpiry = new Date(
    Date.now() + env.REFRESH_TOKEN_DAYS * 24 * 60 * 60 * 1000,
  );

  await prisma.$transaction([
    prisma.refreshToken.update({
      where: { id: stored.id },
      data: { revokedAt: new Date() },
    }),
    prisma.refreshToken.create({
      data: {
        userId: stored.userId,
        tokenHash: hashToken(nextRefreshToken),
        expiresAt: nextExpiry,
      },
    }),
  ]);

  return {
    accessToken: accessTokenFor(stored.user),
    refreshToken: nextRefreshToken,
    expiresIn: env.ACCESS_TOKEN_TTL,
  };
});

app.post(
  '/api/v1/auth/logout',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = refreshSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    await prisma.refreshToken.updateMany({
      where: { tokenHash: hashToken(parsed.data.refreshToken), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return reply.code(204).send();
  },
);

app.get('/api/v1/me', { preHandler: authenticate }, async (request, reply) => {
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({
    where: { id: claims.sub },
    include: { wallet: true },
  });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });

  return {
    user: publicUser(user),
    wallet: {
      balanceAfn: (user.wallet?.balanceAfn ?? 0n).toString(),
    },
  };
});

app.patch(
  '/api/v1/me/preferences',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = preferenceSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const user = await prisma.user.update({
      where: { id: claims.sub },
      data: {
        locale: parsed.data.locale as AppLocale | undefined,
        displayCurrency: parsed.data.displayCurrency as DisplayCurrency | undefined,
      },
    });
    return { user: publicUser(user) };
  },
);

app.get('/api/v1/wallet', { preHandler: authenticate }, async (request, reply) => {
  const claims = request.user as JwtClaims;
  const wallet = await prisma.wallet.findUnique({ where: { userId: claims.sub } });
  if (!wallet) return reply.code(404).send({ error: 'wallet_not_found' });
  return { balanceAfn: wallet.balanceAfn.toString() };
});

app.get(
  '/api/v1/wallet/entries',
  { preHandler: authenticate },
  async (request, reply) => {
    const claims = request.user as JwtClaims;
    const wallet = await prisma.wallet.findUnique({ where: { userId: claims.sub } });
    if (!wallet) return reply.code(404).send({ error: 'wallet_not_found' });

    const entries = await prisma.walletEntry.findMany({
      where: { walletId: wallet.id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });

    return {
      entries: entries.map((entry) => ({
        id: entry.id,
        type: entry.type,
        status: entry.status,
        amountAfn: entry.amountAfn.toString(),
        balanceAfterAfn: entry.balanceAfterAfn.toString(),
        description: entry.description,
        referenceType: entry.referenceType,
        referenceId: entry.referenceId,
        createdAt: entry.createdAt,
      })),
    };
  },
);

app.get('/api/v1/rates', async () => {
  const rates = await prisma.exchangeRate.findMany({ orderBy: { code: 'asc' } });
  return {
    baseCurrency: 'AFN',
    rates: rates.map((rate) => ({
      code: rate.code,
      afnPerUnit: rate.afnPerUnit.toString(),
      updatedAt: rate.updatedAt,
    })),
  };
});

app.put(
  '/api/v1/admin/rates',
  { preHandler: requireAdmin },
  async (request, reply) => {
    const parsed = rateSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const rate = await prisma.exchangeRate.upsert({
      where: { code: parsed.data.code },
      update: { afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit) },
      create: {
        code: parsed.data.code,
        afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit),
      },
    });

    return {
      code: rate.code,
      afnPerUnit: rate.afnPerUnit.toString(),
      updatedAt: rate.updatedAt,
    };
  },
);

app.post(
  '/api/v1/admin/wallet-adjustments',
  { preHandler: requireAdmin },
  async (request, reply) => {
    const parsed = adminAdjustmentSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const amountAfn = BigInt(parsed.data.amountAfn);
    if (amountAfn === 0n) return reply.code(400).send({ error: 'zero_amount' });

    try {
      const entry = await applyWalletDelta({
        userId: parsed.data.userId,
        amountAfn,
        type:
          amountAfn > 0n
            ? WalletEntryType.MANUAL_CREDIT
            : WalletEntryType.MANUAL_DEBIT,
        description: parsed.data.reason,
        idempotencyKey: parsed.data.idempotencyKey,
        referenceType: 'ADMIN_ADJUSTMENT',
      });

      return reply.code(201).send({
        entry: {
          id: entry.id,
          amountAfn: entry.amountAfn.toString(),
          balanceAfterAfn: entry.balanceAfterAfn.toString(),
          type: entry.type,
          createdAt: entry.createdAt,
        },
      });
    } catch (error) {
      if (error instanceof Error && error.message === 'INSUFFICIENT_FUNDS') {
        return reply.code(409).send({ error: 'insufficient_funds' });
      }
      if (error instanceof Error && error.message === 'WALLET_NOT_FOUND') {
        return reply.code(404).send({ error: 'wallet_not_found' });
      }
      throw error;
    }
  },
);

app.setErrorHandler((error, request, reply) => {
  request.log.error(error);
  const status = error.statusCode && error.statusCode >= 400 ? error.statusCode : 500;
  reply.code(status).send({
    error: status >= 500 ? 'internal_server_error' : error.message,
  });
});

const shutdown = async () => {
  await app.close();
  await prisma.$disconnect();
};

process.on('SIGINT', () => void shutdown());
process.on('SIGTERM', () => void shutdown());

try {
  await app.listen({ host: '0.0.0.0', port: env.PORT });
} catch (error) {
  app.log.error(error);
  await prisma.$disconnect();
  process.exit(1);
}
