import 'dotenv/config';
import Fastify, { FastifyReply, FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import rateLimit from '@fastify/rate-limit';
import bcrypt from 'bcryptjs';
import { OAuth2Client } from 'google-auth-library';
import { createHash, randomBytes } from 'node:crypto';
import {
  AppLocale,
  DisplayCurrency,
  Prisma,
  PrismaClient,
  UserRole,
  UserStatus,
  WalletEntryType,
} from '@prisma/client';
import { z } from 'zod';
import { adminLoginHtml } from './adminPage.js';
import { registerClientFoundationRoutes } from './clientFoundationRoutes.js';
import { registerPaymentRoutes } from './paymentRoutes.js';
import { registerHesabPayWebhookRoutes } from './hesabPayWebhookRoutes.js';
import { registerAdminCsrfGuard } from './adminSecurity.js';
import { registerSocialRoutes } from './socialRoutes.js';
import { startSocialAutoSync } from './socialSync.js';
import { registerVirtualNumberRoutes } from './virtualNumberRoutes.js';
import {
  recordReferralRegistration,
  registerReferralRoutes,
  resolveReferralCode,
} from './referralRoutes.js';
import {
  isPhonePermanentlyBlocked,
  resolveEffectiveUserAccess,
  softDeleteUserAccount,
} from './accountControl.js';
import { registerAdminV3 } from './adminV3.js';
import { startNotificationPushScheduler } from './pushNotifications.js';
import {
  completeInboundWhatsAppChallenge,
  ensureMetaWhatsAppSubscription,
  issueInboundWhatsAppChallenge,
  issueVerificationChallenge,
  registerVerificationRoutes,
  verificationCapabilities,
  verifyVerificationChallenge,
} from './verification.js';

const env = z
  .object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PORT: z.coerce.number().int().positive().default(8080),
    DATABASE_URL: z.string().min(1),
    JWT_SECRET: z.string().min(32),
    CORS_ORIGINS: z.string().default(''),
    ACCESS_TOKEN_TTL: z.string().default('15m'),
    REFRESH_TOKEN_DAYS: z.coerce.number().int().positive().default(30),
    GOOGLE_WEB_CLIENT_ID: z.string().trim().min(1).optional(),
  })
  .parse(process.env);

const prisma = new PrismaClient();
const googleOAuth = new OAuth2Client();
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

registerAdminCsrfGuard(app);

app.addContentTypeParser(
  'application/x-www-form-urlencoded',
  { parseAs: 'string' },
  (_request, body, done) => {
    try {
      done(null, Object.fromEntries(new URLSearchParams(String(body))));
    } catch (error) {
      done(error as Error, undefined);
    }
  },
);

const registerSchema = z
  .object({
    fullName: z.string().trim().min(2).max(120),
    email: z.string().trim().email().optional(),
    phone: z.string().trim().min(7).max(32).optional(),
    password: z.string().min(8).max(128),
    locale: z.enum(['FA', 'EN']).default('FA'),
    verificationToken: z.string().trim().min(20).optional(),
    referralCode: z.string().trim().min(4).max(40).optional(),
  })
  .refine((data) => Boolean(data.email || data.phone), {
    message: 'email_or_phone_required',
  });

const loginSchema = z.object({
  identifier: z.string().trim().min(3).max(254),
  password: z.string().min(1).max(128),
  whatsappInbound: z.boolean().optional(),
});

const loginTwoFactorSchema = z.object({
  loginToken: z.string().trim().min(20),
  challengeId: z.string().uuid(),
  code: z.string().regex(/^\d{6}$/),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(40),
});

const googleAuthSchema = z.object({
  idToken: z.string().min(20),
  locale: z.enum(['FA', 'EN']).default('FA'),
  whatsappInbound: z.boolean().optional(),
});

const preferenceSchema = z
  .object({
    locale: z.enum(['FA', 'EN']).optional(),
    displayCurrency: z.enum(['AFN', 'USD', 'TOMAN']).optional(),
  })
  .refine((data) => data.locale !== undefined || data.displayCurrency !== undefined, {
    message: 'no_changes_requested',
  });

const profileSchema = z.object({
  fullName: z.string().trim().min(2).max(120),
  websiteUrl: z.string().trim().url().max(300).nullable().optional(),
  countryCode: z.string().trim().regex(/^[A-Z]{2}$/).nullable().optional(),
  avatarPreset: z.string().trim().regex(/^avatar_(0[1-9]|1[0-6])$/).nullable().optional(),
  avatarUrl: z.string().trim().url().max(1000).nullable().optional(),
  avatarData: z.string().trim().max(500000).regex(/^data:image\/(png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/).nullable().optional(),
  email: z.string().trim().email().nullable().optional(),
  phone: z.string().trim().min(7).max(32).nullable().optional(),
  emailVerificationToken: z.string().trim().min(20).optional(),
  phoneVerificationToken: z.string().trim().min(20).optional(),
});

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: z.string().min(8).max(128),
});

const setPasswordSchema = z.object({
  newPassword: z.string().min(8).max(128),
});

const twoFactorEnableSchema = z.object({
  method: z.enum(['EMAIL', 'SMS', 'WHATSAPP']),
  verificationToken: z.string().trim().min(20),
});

const twoFactorDisableSchema = z.object({
  password: z.string().min(1).max(128).optional(),
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

const adminUsersQuerySchema = z.object({
  q: z.string().trim().max(120).optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const adminUserParamsSchema = z.object({
  id: z.string().uuid(),
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
  const claims = request.user as JwtClaims;
  const account = await prisma.user.findUnique({
    where: { id: claims.sub },
    select: { id: true, status: true },
  });
  if (!account) return reply.code(401).send({ error: 'unauthorized' });
  const access = await resolveEffectiveUserAccess(prisma, account as any);
  if (!access.allowed) {
    return reply.code(403).send({
      error: access.code,
      state: access.state,
      until: 'until' in access ? access.until : null,
      reason: 'reason' in access ? access.reason : null,
    });
  }
}

async function requireAdmin(request: FastifyRequest, reply: FastifyReply) {
  const authResult = await authenticate(request, reply);
  if (authResult) return authResult;
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({
    where: { id: claims.sub },
    select: { role: true },
  });
  if (!user || user.role !== UserRole.ADMIN) {
    return reply.code(403).send({ error: 'admin_required' });
  }
}

function publicUser(user: {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
  role: UserRole;
  status: UserStatus;
  locale: AppLocale;
  displayCurrency: DisplayCurrency;
  websiteUrl?: string | null;
  countryCode?: string | null;
  avatarPreset?: string | null;
  avatarUrl?: string | null;
  avatarData?: string | null;
  emailVerifiedAt?: Date | null;
  phoneVerifiedAt?: Date | null;
  twoFactorEnabled?: boolean;
  twoFactorMethod?: string | null;
  twoFactorVerifiedAt?: Date | null;
  createdAt: Date;
  passwordHash?: string | null;
}) {
  return {
    id: user.id,
    fullName: user.fullName,
    email: user.email,
    phone: user.phone,
    role: user.role,
    status: user.status,
    locale: user.locale,
    displayCurrency: user.displayCurrency,
    websiteUrl: user.websiteUrl ?? null,
    countryCode: user.countryCode ?? null,
    avatarPreset: user.avatarPreset ?? 'avatar_01',
    avatarUrl: user.avatarUrl ?? null,
    avatarData: user.avatarData ?? null,
    emailVerified: Boolean(user.emailVerifiedAt),
    phoneVerified: Boolean(user.phoneVerifiedAt),
    twoFactorEnabled: Boolean(user.twoFactorEnabled),
    twoFactorMethod: user.twoFactorMethod ?? null,
    twoFactorVerifiedAt: user.twoFactorVerifiedAt ?? null,
    hasPassword: Boolean(user.passwordHash),
    createdAt: user.createdAt,
  };
}

function verificationClaims(token?: string) {
  if (!token) return null;
  try {
    const claims = app.jwt.verify<{
      kind?: string;
      challengeId?: string;
      userId?: string | null;
      target?: string;
      channel?: string;
      purpose?: string;
    }>(token);
    return claims.kind === 'verification' ? claims : null;
  } catch {
    return null;
  }
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

const adminWebCookieName = 'velixeo_admin';

type AdminWebClaims = JwtClaims & { scope?: string };

function parseCookies(header?: string) {
  const out: Record<string, string> = {};
  for (const part of (header ?? '').split(';')) {
    const index = part.indexOf('=');
    if (index <= 0) continue;
    const key = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    try {
      out[key] = decodeURIComponent(value);
    } catch {
      out[key] = value;
    }
  }
  return out;
}

async function adminWebUser(request: FastifyRequest) {
  const token = parseCookies(request.headers.cookie)[adminWebCookieName];
  if (!token) return null;
  try {
    const claims = app.jwt.verify<AdminWebClaims>(token);
    if (claims.scope !== 'admin-web' || claims.role !== UserRole.ADMIN) return null;
    return prisma.user.findFirst({
      where: { id: claims.sub, role: UserRole.ADMIN, status: UserStatus.ACTIVE },
      include: { wallet: true },
    });
  } catch {
    return null;
  }
}

function adminCookie(token: string, maxAge = 8 * 60 * 60) {
  return `${adminWebCookieName}=${encodeURIComponent(token)}; Path=/admin; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;
}

app.get('/admin', async (request, reply) => {
  const url = new URL(request.raw.url || '/admin', 'http://velixeo.local');
  const view = url.searchParams.get('view');
  const section = view === 'users' ? 'users'
    : view === 'rates' ? 'settings'
    : view === 'providers' ? 'social'
    : '';
  return reply.code(303).redirect(section ? '/admin/v3?section=' + section : '/admin/v3');
});

app.get('/admin/login', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (admin) return reply.code(303).redirect('/admin/v3');
  return reply.type('text/html; charset=utf-8').send(adminLoginHtml());
});

const legacyAdminGetRedirects: Record<string, string> = {
  '/admin/v2': '/admin/v3',
  '/admin/overview': '/admin/v3',
  '/admin/users-control': '/admin/v3?section=users',
  '/admin/social': '/admin/v3?section=social',
  '/admin/providers': '/admin/v3?section=social',
  '/admin/virtual-numbers': '/admin/v3?section=virtual',
  '/admin/orders': '/admin/v3?section=orders',
  '/admin/payments': '/admin/v3?section=payments',
  '/admin/coupons': '/admin/v3?section=coupons',
  '/admin/banners': '/admin/v3?section=banners',
  '/admin/notifications': '/admin/v3?section=notifications',
  '/admin/support': '/admin/v3?section=support',
  '/admin/settings': '/admin/v3?section=settings',
  '/admin/readiness': '/admin/v3?section=settings',
  '/admin/reports': '/admin/v3',
  '/admin/audit': '/admin/v3?section=audit',
};

app.addHook('onRequest', async (request, reply) => {
  if (request.method !== 'GET') return;
  const url = new URL(request.raw.url || '/', 'http://velixeo.local');
  if (url.pathname === '/admin/services') {
    const category = url.searchParams.get('category');
    const section = category === 'PREMIUM' ? 'premium'
      : category === 'MOBILE_TOPUP' ? 'topup'
      : category === 'DIGITAL_ACCOUNT' ? 'accounts'
      : category === 'PROMOTION' ? 'promotions'
      : 'social';
    return reply.code(303).redirect('/admin/v3?section=' + section);
  }
  const target = legacyAdminGetRedirects[url.pathname];
  if (target) return reply.code(303).redirect(target);
});

app.post('/admin/login', async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).type('text/html; charset=utf-8').send(adminLoginHtml('ایمیل/شماره و رمز را درست وارد کنید.'));
  }
  const rawIdentifier = parsed.data.identifier;
  const emailIdentifier = rawIdentifier.includes('@') ? rawIdentifier.toLowerCase() : '__not_an_email__';
  const phoneIdentifier = normalizePhone(rawIdentifier) ?? rawIdentifier;
  const user = await prisma.user.findFirst({
    where: { OR: [{ email: emailIdentifier }, { phone: phoneIdentifier }] },
  });
  if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return reply.code(401).type('text/html; charset=utf-8').send(adminLoginHtml('ایمیل/شماره یا رمز عبور نادرست است.'));
  }
  if (user.role !== UserRole.ADMIN) {
    return reply.code(403).type('text/html; charset=utf-8').send(adminLoginHtml('این حساب دسترسی مدیر ندارد.'));
  }
  const token = app.jwt.sign(
    { sub: user.id, role: user.role, scope: 'admin-web' },
    { expiresIn: '8h' },
  );
  reply.header('Set-Cookie', adminCookie(token));
  return reply.code(303).redirect('/admin/v3');
});

app.post('/admin/logout', async (_request, reply) => {
  reply.header('Set-Cookie', adminCookie('', 0));
  return reply.code(303).redirect('/admin/login');
});

app.post('/admin/wallet-adjust', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (!admin) return reply.code(303).redirect('/admin');
  const parsed = adminAdjustmentSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(303).redirect('/admin?view=users&msg=invalid_request');
  const amountAfn = BigInt(parsed.data.amountAfn);
  if (amountAfn === 0n) return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=invalid_request`);
  try {
    const entry = await applyWalletDelta({
      userId: parsed.data.userId,
      amountAfn,
      type: amountAfn > 0n ? WalletEntryType.MANUAL_CREDIT : WalletEntryType.MANUAL_DEBIT,
      description: parsed.data.reason,
      idempotencyKey: `admin-web-${admin.id}-${Date.now()}-${randomBytes(6).toString('hex')}`,
      referenceType: 'ADMIN_ADJUSTMENT',
      referenceId: admin.id,
    });
    await prisma.adminAuditLog.create({
      data: {
        adminUserId: admin.id,
        action: 'WALLET_MANUAL_ADJUST',
        entityType: 'WalletEntry',
        entityId: entry.id,
        summary: `${parsed.data.amountAfn} AFN — ${parsed.data.reason}`,
        metadata: { userId: parsed.data.userId },
      },
    });
    return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=wallet_updated`);
  } catch (error) {
    if (error instanceof Error && error.message === 'INSUFFICIENT_FUNDS') {
      return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=insufficient_funds`);
    }
    throw error;
  }
});

app.post('/admin/rates', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (!admin) return reply.code(303).redirect('/admin');
  const parsed = rateSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(303).redirect('/admin?view=rates&msg=invalid_request');
  await prisma.exchangeRate.upsert({
    where: { code: parsed.data.code },
    update: { afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit) },
    create: { code: parsed.data.code, afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit) },
  });
  await prisma.adminAuditLog.create({
    data: {
      adminUserId: admin.id,
      action: 'EXCHANGE_RATE_UPDATE',
      entityType: 'ExchangeRate',
      entityId: parsed.data.code,
      summary: `${parsed.data.code} = ${parsed.data.afnPerUnit} AFN`,
    },
  });
  return reply.code(303).redirect('/admin/v3?section=settings&msg=rate_updated');
});

app.post('/api/v1/auth/register', async (request, reply) => {
  const parsed = registerSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).send({ error: 'invalid_request', details: parsed.error.flatten() });
  }

  const email = normalizeEmail(parsed.data.email);
  const phone = normalizePhone(parsed.data.phone);
  const verified = verificationClaims(parsed.data.verificationToken);
  const requireRegistrationVerification = process.env.AUTH_REQUIRE_REGISTRATION_VERIFICATION === 'true';
  if (phone && !verified) {
    return reply.code(403).send({ error: 'whatsapp_verification_required' });
  }
  if (!phone && requireRegistrationVerification && !verified) {
    return reply.code(403).send({ error: 'verification_required' });
  }
  if (verified) {
    if (verified.purpose !== 'REGISTER') return reply.code(400).send({ error: 'invalid_verification_token' });
    if (email && !phone && (verified.channel !== 'EMAIL' || verified.target !== email)) {
      return reply.code(400).send({ error: 'verification_target_mismatch' });
    }
    if (phone && !email && (verified.channel !== 'WHATSAPP' || verified.target !== phone)) {
      return reply.code(403).send({ error: 'whatsapp_verification_required' });
    }
    if (email && phone) {
      const matchesEmail = verified.channel === 'EMAIL' && verified.target === email;
      const matchesWhatsApp = verified.channel === 'WHATSAPP' && verified.target === phone;
      if (!matchesEmail && !matchesWhatsApp) {
        return reply.code(400).send({ error: 'verification_target_mismatch' });
      }
    }
  }

  if (email) {
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return reply.code(409).send({ error: 'email_already_registered' });
  }
  if (phone && await isPhonePermanentlyBlocked(prisma, phone)) {
    return reply.code(403).send({ error: 'phone_permanently_blocked' });
  }
  if (phone) {
    const existing = await prisma.user.findUnique({ where: { phone } });
    if (existing) return reply.code(409).send({ error: 'phone_already_registered' });
  }

  let referral: Awaited<ReturnType<typeof resolveReferralCode>> = null;
  if (parsed.data.referralCode) {
    try {
      referral = await resolveReferralCode(prisma, parsed.data.referralCode);
    } catch (error) {
      const code = error instanceof Error ? error.message : 'invalid_referral_code';
      return reply.code(400).send({ error: code });
    }
  }

  const passwordHash = await bcrypt.hash(parsed.data.password, 12);
  const user = await prisma.user.create({
    data: {
      fullName: parsed.data.fullName.trim(),
      email: email ?? null,
      phone: phone ?? null,
      passwordHash,
      locale: parsed.data.locale as AppLocale,
      emailVerifiedAt: verified?.channel === 'EMAIL' && verified.target === email ? new Date() : null,
      phoneVerifiedAt: verified?.channel === 'WHATSAPP' && verified.target === phone ? new Date() : null,
      wallet: { create: {} },
    },
  });

  if (referral) {
    try {
      await recordReferralRegistration(prisma, {
        inviteeId: user.id,
        inviterId: referral.inviterId,
        code: referral.code,
        settings: referral.settings,
      });
    } catch (error) {
      request.log.error({ error, inviteeId: user.id }, 'referral registration recording failed');
    }
  }

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

  if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return reply.code(401).send({ error: 'invalid_credentials' });
  }
  const loginAccess = await resolveEffectiveUserAccess(prisma, user);
  if (!loginAccess.allowed) {
    return reply.code(403).send({
      error: loginAccess.code,
      state: loginAccess.state,
      until: 'until' in loginAccess ? loginAccess.until : null,
      reason: 'reason' in loginAccess ? loginAccess.reason : null,
    });
  }

  if (user.twoFactorEnabled) {
    const method = String(user.twoFactorMethod || '');
    const channel = method === 'EMAIL' ? 'EMAIL' : method === 'SMS' ? 'SMS' : method === 'WHATSAPP' ? 'WHATSAPP' : null;
    if (!channel) return reply.code(503).send({ error: 'two_factor_method_unavailable' });
    const target = channel === 'EMAIL' ? user.email : user.phone;
    const verified = channel === 'EMAIL' ? user.emailVerifiedAt : user.phoneVerifiedAt;
    if (!target || !verified) return reply.code(503).send({ error: 'two_factor_contact_unavailable' });
    try {
      const challenge = channel === 'WHATSAPP' && parsed.data.whatsappInbound
        ? await issueInboundWhatsAppChallenge(prisma, {
            userId: user.id,
            target,
            purpose: 'LOGIN_2FA',
          })
        : await issueVerificationChallenge(prisma, {
            userId: user.id,
            target,
            channel,
            purpose: 'LOGIN_2FA',
          });
      const loginToken = app.jwt.sign(
        { kind: 'two_factor_login', userId: user.id, challengeId: challenge.challengeId },
        { expiresIn: '10m' },
      );
      return reply.code(202).send({
        requiresTwoFactor: true,
        loginToken,
        ...challenge,
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : 'two_factor_send_failed';
      const status = code.endsWith('_not_configured') ? 503 : code === 'otp_provider_failed' ? 502 : code === 'otp_rate_limited' || code === 'otp_resend_too_soon' ? 429 : 400;
      return reply.code(status).send({ error: code });
    }
  }

  const session = await createSession(user);
  return { user: publicUser(user), ...session };
});

app.post('/api/v1/auth/login/2fa', async (request, reply) => {
  const parsed = loginTwoFactorSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  let loginClaims: { kind?: string; userId?: string; challengeId?: string };
  try {
    loginClaims = app.jwt.verify(parsed.data.loginToken);
  } catch {
    return reply.code(401).send({ error: 'invalid_two_factor_login_token' });
  }
  if (
    loginClaims.kind !== 'two_factor_login'
    || !loginClaims.userId
    || loginClaims.challengeId !== parsed.data.challengeId
  ) {
    return reply.code(401).send({ error: 'invalid_two_factor_login_token' });
  }
  try {
    const verified = await verifyVerificationChallenge(
      app,
      prisma,
      parsed.data.challengeId,
      parsed.data.code,
      loginClaims.userId,
    );
    if (verified.purpose !== 'LOGIN_2FA') {
      return reply.code(400).send({ error: 'invalid_two_factor_challenge' });
    }
    const user = await prisma.user.findUnique({ where: { id: loginClaims.userId } });
    if (!user) return reply.code(401).send({ error: 'invalid_credentials' });
    const access = await resolveEffectiveUserAccess(prisma, user);
    if (!access.allowed) return reply.code(403).send({ error: access.code, state: access.state });
    const session = await createSession(user);
    return { user: publicUser(user), ...session };
  } catch (error) {
    return reply.code(400).send({ error: error instanceof Error ? error.message : 'two_factor_verification_failed' });
  }
});

app.post('/api/v1/auth/login/2fa/whatsapp/status', async (request, reply) => {
  const parsed = z.object({
    loginToken: z.string().trim().min(20),
    challengeId: z.string().uuid(),
  }).safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  let loginClaims: { kind?: string; userId?: string; challengeId?: string };
  try {
    loginClaims = app.jwt.verify(parsed.data.loginToken);
  } catch {
    return reply.code(401).send({ error: 'invalid_two_factor_login_token' });
  }
  if (
    loginClaims.kind !== 'two_factor_login'
    || !loginClaims.userId
    || loginClaims.challengeId !== parsed.data.challengeId
  ) {
    return reply.code(401).send({ error: 'invalid_two_factor_login_token' });
  }

  try {
    const verified = await completeInboundWhatsAppChallenge(
      app,
      prisma,
      parsed.data.challengeId,
      loginClaims.userId,
    );
    if (verified.status === 'PENDING') {
      return reply.code(202).send({ status: 'PENDING' });
    }
    if (verified.purpose !== 'LOGIN_2FA') {
      return reply.code(400).send({ error: 'invalid_two_factor_challenge' });
    }

    const user = await prisma.user.findUnique({ where: { id: loginClaims.userId } });
    if (!user) return reply.code(401).send({ error: 'invalid_credentials' });
    const access = await resolveEffectiveUserAccess(prisma, user);
    if (!access.allowed) return reply.code(403).send({ error: access.code, state: access.state });
    const session = await createSession(user);
    return reply.code(200).send({ status: 'VERIFIED', user: publicUser(user), ...session });
  } catch (error) {
    return reply.code(400).send({
      error: error instanceof Error ? error.message : 'two_factor_verification_failed',
    });
  }
});

app.post('/api/v1/auth/google', async (request, reply) => {
  if (!env.GOOGLE_WEB_CLIENT_ID) {
    return reply.code(503).send({ error: 'google_auth_not_configured' });
  }

  const parsed = googleAuthSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  try {
    const ticket = await googleOAuth.verifyIdToken({
      idToken: parsed.data.idToken,
      audience: env.GOOGLE_WEB_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    const googleSubject = payload?.sub;
    const email = normalizeEmail(payload?.email);
    if (!googleSubject || !email || payload?.email_verified !== true) {
      return reply.code(401).send({ error: 'invalid_google_identity' });
    }

    let user = await prisma.user.findUnique({ where: { googleSubject } });
    if (!user) {
      const existing = await prisma.user.findUnique({ where: { email } });
      if (existing?.googleSubject && existing.googleSubject !== googleSubject) {
        return reply.code(409).send({ error: 'google_account_conflict' });
      }

      if (existing) {
        user = await prisma.user.update({
          where: { id: existing.id },
          data: {
            googleSubject,
            fullName: existing.fullName?.trim() ? existing.fullName : payload?.name?.trim() || null,
            emailVerifiedAt: existing.emailVerifiedAt ?? new Date(),
          },
        });
      } else {
        user = await prisma.user.create({
          data: {
            fullName: payload?.name?.trim() || email.split('@')[0],
            email,
            googleSubject,
            emailVerifiedAt: new Date(),
            passwordHash: null,
            locale: parsed.data.locale as AppLocale,
            wallet: { create: {} },
          },
        });
      }
    }

    const googleAccess = await resolveEffectiveUserAccess(prisma, user);
    if (!googleAccess.allowed) {
      return reply.code(403).send({
        error: googleAccess.code,
        state: googleAccess.state,
        until: 'until' in googleAccess ? googleAccess.until : null,
        reason: 'reason' in googleAccess ? googleAccess.reason : null,
      });
    }
    if (user.twoFactorEnabled) {
      const method = String(user.twoFactorMethod || '');
      const channel = method === 'EMAIL' ? 'EMAIL' : method === 'SMS' ? 'SMS' : method === 'WHATSAPP' ? 'WHATSAPP' : null;
      if (!channel) return reply.code(503).send({ error: 'two_factor_method_unavailable' });
      const target = channel === 'EMAIL' ? user.email : user.phone;
      const verified = channel === 'EMAIL' ? user.emailVerifiedAt : user.phoneVerifiedAt;
      if (!target || !verified) return reply.code(503).send({ error: 'two_factor_contact_unavailable' });
      const challenge = channel === 'WHATSAPP' && parsed.data.whatsappInbound
        ? await issueInboundWhatsAppChallenge(prisma, {
            userId: user.id,
            target,
            purpose: 'LOGIN_2FA',
          })
        : await issueVerificationChallenge(prisma, {
            userId: user.id,
            target,
            channel,
            purpose: 'LOGIN_2FA',
          });
      const loginToken = app.jwt.sign(
        { kind: 'two_factor_login', userId: user.id, challengeId: challenge.challengeId },
        { expiresIn: '10m' },
      );
      return reply.code(202).send({ requiresTwoFactor: true, loginToken, ...challenge });
    }
    const session = await createSession(user);
    return { user: publicUser(user), ...session };
  } catch (error) {
    request.log.warn({ error }, 'google token verification failed');
    return reply.code(401).send({ error: 'invalid_google_token' });
  }
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
  const refreshAccess = await resolveEffectiveUserAccess(prisma, stored.user);
  if (!refreshAccess.allowed) {
    return reply.code(403).send({
      error: refreshAccess.code,
      state: refreshAccess.state,
      until: 'until' in refreshAccess ? refreshAccess.until : null,
      reason: 'reason' in refreshAccess ? refreshAccess.reason : null,
    });
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

app.patch(
  '/api/v1/me/profile',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = profileSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const current = await prisma.user.findUnique({ where: { id: claims.sub } });
    if (!current) return reply.code(404).send({ error: 'user_not_found' });

    const nextEmail = parsed.data.email === undefined ? current.email : normalizeEmail(parsed.data.email ?? undefined) ?? null;
    const nextPhone = parsed.data.phone === undefined ? current.phone : normalizePhone(parsed.data.phone ?? undefined) ?? null;
    let emailVerifiedAt = current.emailVerifiedAt;
    let phoneVerifiedAt = current.phoneVerifiedAt;

    if (nextEmail !== current.email) {
      if (nextEmail) {
        const token = verificationClaims(parsed.data.emailVerificationToken);
        if (!token || token.userId !== current.id || token.target !== nextEmail || token.purpose !== 'VERIFY_EMAIL' || token.channel !== 'EMAIL') {
          return reply.code(403).send({ error: 'email_verification_required' });
        }
        const taken = await prisma.user.findFirst({ where: { email: nextEmail, id: { not: current.id } } });
        if (taken) return reply.code(409).send({ error: 'email_already_registered' });
        emailVerifiedAt = new Date();
      } else {
        emailVerifiedAt = null;
      }
    }

    if (nextPhone !== current.phone) {
      if (nextPhone) {
        if (await isPhonePermanentlyBlocked(prisma, nextPhone)) {
          return reply.code(403).send({ error: 'phone_permanently_blocked' });
        }
        const token = verificationClaims(parsed.data.phoneVerificationToken);
        if (!token || token.userId !== current.id || token.target !== nextPhone || token.purpose !== 'VERIFY_PHONE' || token.channel !== 'WHATSAPP') {
          return reply.code(403).send({ error: 'phone_verification_required' });
        }
        const taken = await prisma.user.findFirst({ where: { phone: nextPhone, id: { not: current.id } } });
        if (taken) return reply.code(409).send({ error: 'phone_already_registered' });
        phoneVerifiedAt = new Date();
      } else {
        phoneVerifiedAt = null;
      }
    }

    const user = await prisma.user.update({
      where: { id: claims.sub },
      data: {
        fullName: parsed.data.fullName,
        websiteUrl: parsed.data.websiteUrl === undefined ? undefined : parsed.data.websiteUrl,
        countryCode: parsed.data.countryCode === undefined ? undefined : parsed.data.countryCode,
        avatarPreset: parsed.data.avatarPreset === undefined ? undefined : parsed.data.avatarPreset,
        avatarUrl: parsed.data.avatarUrl === undefined ? undefined : parsed.data.avatarUrl,
        avatarData: parsed.data.avatarData === undefined ? undefined : parsed.data.avatarData,
        email: nextEmail,
        phone: nextPhone,
        emailVerifiedAt,
        phoneVerifiedAt,
      },
    });
    return { user: publicUser(user) };
  },
);

app.post(
  '/api/v1/me/change-password',
  { preHandler: authenticate },
  async (request, reply) => {
    const parsed = changePasswordSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const claims = request.user as JwtClaims;
    const user = await prisma.user.findUnique({ where: { id: claims.sub } });
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    if (!user.passwordHash) return reply.code(400).send({ error: 'password_not_set' });
    const matches = await bcrypt.compare(parsed.data.currentPassword, user.passwordHash);
    if (!matches) return reply.code(400).send({ error: 'incorrect_current_password' });
    if (parsed.data.currentPassword == parsed.data.newPassword) {
      return reply.code(400).send({ error: 'new_password_must_differ' });
    }

    const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
    const revokedAt = new Date();
    const updated = await prisma.$transaction(async (tx) => {
      const nextUser = await tx.user.update({
        where: { id: claims.sub },
        data: { passwordHash },
      });
      await tx.refreshToken.updateMany({
        where: { userId: claims.sub, revokedAt: null },
        data: { revokedAt },
      });
      return nextUser;
    });
    const session = await createSession(updated);
    return { ok: true, user: publicUser(updated), ...session };
  },
);

app.get('/api/v1/me/security', { preHandler: authenticate }, async (request, reply) => {
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });
  return {
    hasPassword: Boolean(user.passwordHash),
    email: user.email,
    phone: user.phone,
    emailVerified: Boolean(user.emailVerifiedAt),
    phoneVerified: Boolean(user.phoneVerifiedAt),
    twoFactorEnabled: user.twoFactorEnabled,
    twoFactorMethod: user.twoFactorMethod,
    verification: verificationCapabilities(),
  };
});

app.post('/api/v1/me/security/verify-contact', { preHandler: authenticate }, async (request, reply) => {
  const parsed = z.object({ verificationToken: z.string().trim().min(20) }).safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const claims = request.user as JwtClaims;
  const token = verificationClaims(parsed.data.verificationToken);
  if (!token || token.userId !== claims.sub) return reply.code(400).send({ error: 'invalid_verification_token' });
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });

  if (token.purpose === 'VERIFY_EMAIL' && token.channel === 'EMAIL' && token.target === user.email) {
    const updated = await prisma.user.update({ where: { id: user.id }, data: { emailVerifiedAt: new Date() } });
    return { user: publicUser(updated) };
  }
  if (token.purpose === 'VERIFY_PHONE' && token.channel === 'WHATSAPP' && token.target === user.phone) {
    const updated = await prisma.user.update({ where: { id: user.id }, data: { phoneVerifiedAt: new Date() } });
    return { user: publicUser(updated) };
  }
  return reply.code(400).send({ error: 'verification_target_mismatch' });
});

app.post('/api/v1/me/security/2fa/enable', { preHandler: authenticate }, async (request, reply) => {
  const parsed = twoFactorEnableSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });
  const token = verificationClaims(parsed.data.verificationToken);
  if (!token || token.userId !== user.id || token.purpose !== 'ENABLE_2FA' || token.channel !== parsed.data.method) {
    return reply.code(400).send({ error: 'invalid_verification_token' });
  }
  const expectedTarget = parsed.data.method === 'EMAIL' ? user.email : user.phone;
  const verifiedContact = parsed.data.method === 'EMAIL' ? user.emailVerifiedAt : user.phoneVerifiedAt;
  if (!expectedTarget || !verifiedContact || token.target !== expectedTarget) {
    return reply.code(400).send({ error: 'verified_contact_required' });
  }
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { twoFactorEnabled: true, twoFactorMethod: parsed.data.method, twoFactorVerifiedAt: new Date() },
  });
  return { user: publicUser(updated) };
});

app.post('/api/v1/me/security/2fa/disable', { preHandler: authenticate }, async (request, reply) => {
  const parsed = twoFactorDisableSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });
  if (user.passwordHash) {
    if (!parsed.data.password || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
      return reply.code(400).send({ error: 'incorrect_current_password' });
    }
  }
  const updated = await prisma.user.update({
    where: { id: user.id },
    data: { twoFactorEnabled: false, twoFactorMethod: null, twoFactorVerifiedAt: null },
  });
  return { user: publicUser(updated) };
});

app.post('/api/v1/me/set-password', { preHandler: authenticate }, async (request, reply) => {
  const parsed = setPasswordSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });
  if (user.passwordHash) return reply.code(409).send({ error: 'password_already_set' });
  const passwordHash = await bcrypt.hash(parsed.data.newPassword, 12);
  const updated = await prisma.user.update({ where: { id: user.id }, data: { passwordHash } });
  const session = await createSession(updated);
  return { ok: true, user: publicUser(updated), ...session };
});

app.post('/api/v1/me/delete-account', { preHandler: authenticate }, async (request, reply) => {
  const parsed = z.object({
    confirmation: z.literal('DELETE'),
    password: z.string().min(1).max(128).optional(),
    reason: z.string().trim().max(300).optional(),
  }).safeParse(request.body);
  if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

  const claims = request.user as JwtClaims;
  const user = await prisma.user.findUnique({ where: { id: claims.sub } });
  if (!user) return reply.code(404).send({ error: 'user_not_found' });
  if (user.role === UserRole.ADMIN) {
    return reply.code(403).send({ error: 'admin_account_delete_not_allowed' });
  }
  if (user.passwordHash) {
    if (!parsed.data.password || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
      return reply.code(400).send({ error: 'incorrect_current_password' });
    }
  }
  await softDeleteUserAccount(
    prisma,
    user,
    'USER',
    user.id,
    parsed.data.reason || 'Deleted from VELIXEO app',
  );
  return { ok: true };
});

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

app.get(
  '/api/v1/admin/stats',
  { preHandler: requireAdmin },
  async () => {
    const dayStart = new Date();
    dayStart.setUTCHours(0, 0, 0, 0);

    const [totalUsers, usersToday, totalAdmins, walletAggregate, recentUsers] =
      await Promise.all([
        prisma.user.count(),
        prisma.user.count({ where: { createdAt: { gte: dayStart } } }),
        prisma.user.count({ where: { role: UserRole.ADMIN } }),
        prisma.wallet.aggregate({ _sum: { balanceAfn: true } }),
        prisma.user.findMany({
          orderBy: { createdAt: 'desc' },
          take: 8,
          include: { wallet: true },
        }),
      ]);

    return {
      totalUsers,
      usersToday,
      totalAdmins,
      totalWalletBalanceAfn: (walletAggregate._sum.balanceAfn ?? 0n).toString(),
      recentUsers: recentUsers.map((user) => ({
        ...publicUser(user),
        balanceAfn: (user.wallet?.balanceAfn ?? 0n).toString(),
      })),
    };
  },
);

app.get(
  '/api/v1/admin/users',
  { preHandler: requireAdmin },
  async (request, reply) => {
    const parsed = adminUsersQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const { q, page, limit } = parsed.data;
    const where: Prisma.UserWhereInput = q
      ? {
          OR: [
            { fullName: { contains: q, mode: 'insensitive' } },
            { email: { contains: q, mode: 'insensitive' } },
            { phone: { contains: q, mode: 'insensitive' } },
          ],
        }
      : {};

    const [total, users] = await Promise.all([
      prisma.user.count({ where }),
      prisma.user.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
        include: { wallet: true },
      }),
    ]);

    return {
      total,
      page,
      limit,
      users: users.map((user) => ({
        ...publicUser(user),
        balanceAfn: (user.wallet?.balanceAfn ?? 0n).toString(),
      })),
    };
  },
);

app.get(
  '/api/v1/admin/users/:id',
  { preHandler: requireAdmin },
  async (request, reply) => {
    const parsed = adminUserParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

    const user = await prisma.user.findUnique({
      where: { id: parsed.data.id },
      include: {
        wallet: {
          include: {
            entries: {
              orderBy: { createdAt: 'desc' },
              take: 30,
            },
          },
        },
      },
    });
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    return {
      user: {
        ...publicUser(user),
        balanceAfn: (user.wallet?.balanceAfn ?? 0n).toString(),
        walletEntries: (user.wallet?.entries ?? []).map((entry) => ({
          id: entry.id,
          type: entry.type,
          status: entry.status,
          amountAfn: entry.amountAfn.toString(),
          balanceAfterAfn: entry.balanceAfterAfn.toString(),
          description: entry.description,
          createdAt: entry.createdAt,
        })),
      },
    };
  },
);

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

registerAdminV3(app, prisma, adminWebUser);
registerVerificationRoutes(app, prisma, authenticate);
void ensureMetaWhatsAppSubscription(app);
registerClientFoundationRoutes(app, prisma, authenticate);
registerPaymentRoutes(app, prisma, authenticate);
registerHesabPayWebhookRoutes(app, prisma, authenticate);
registerSocialRoutes(app, prisma, authenticate, adminWebUser);
registerVirtualNumberRoutes(app, prisma, authenticate, adminWebUser);
registerReferralRoutes(app, prisma, authenticate);
startSocialAutoSync(prisma, app.log as any);
startNotificationPushScheduler(prisma, app.log as any);

app.setErrorHandler((error: unknown, request, reply) => {
  request.log.error(error);
  const statusCode =
    typeof error === 'object' &&
    error !== null &&
    'statusCode' in error &&
    typeof (error as { statusCode?: unknown }).statusCode === 'number'
      ? (error as { statusCode: number }).statusCode
      : 500;
  const status = statusCode >= 400 ? statusCode : 500;
  const message = error instanceof Error ? error.message : 'unknown_error';
  reply.code(status).send({
    error: status >= 500 ? 'internal_server_error' : message,
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
