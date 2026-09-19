import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import type { PrismaClient } from '@prisma/client';
import { createHmac, randomInt, randomUUID } from 'node:crypto';
import nodemailer from 'nodemailer';
import { z } from 'zod';

type AuthHandler = (request: FastifyRequest, reply: FastifyReply) => Promise<unknown>;

const publicRequestSchema = z.object({
  target: z.string().trim().min(5).max(254),
  channel: z.enum(['EMAIL', 'SMS', 'WHATSAPP']),
  purpose: z.literal('REGISTER'),
});

const authRequestSchema = z.object({
  channel: z.enum(['EMAIL', 'SMS', 'WHATSAPP']),
  purpose: z.enum(['VERIFY_EMAIL', 'VERIFY_PHONE', 'ENABLE_2FA']),
});

const verifySchema = z.object({
  challengeId: z.string().uuid(),
  code: z.string().regex(/^\d{6}$/),
});

const smtpConfigured = () => Boolean(
  process.env.SMTP_HOST
  && process.env.SMTP_USER
  && process.env.SMTP_PASS
  && process.env.SMTP_FROM,
);

const webhookConfigured = (channel: 'SMS' | 'WHATSAPP') =>
  Boolean(process.env[channel === 'SMS' ? 'OTP_SMS_WEBHOOK_URL' : 'OTP_WHATSAPP_WEBHOOK_URL']);

function capabilities() {
  return {
    email: smtpConfigured(),
    sms: webhookConfigured('SMS'),
    whatsapp: webhookConfigured('WHATSAPP'),
    registrationVerificationRequired: process.env.AUTH_REQUIRE_REGISTRATION_VERIFICATION === 'true',
    resendCooldownSeconds: 60,
    expiresInSeconds: 600,
  };
}

function codeHash(code: string) {
  const secret = process.env.OTP_SECRET || process.env.JWT_SECRET || 'velixeo-otp-fallback';
  return createHmac('sha256', secret).update(code).digest('hex');
}

function normalizeTarget(target: string, channel: 'EMAIL' | 'SMS' | 'WHATSAPP') {
  if (channel === 'EMAIL') return target.trim().toLowerCase();
  return target.replace(/[\s()-]/g, '');
}

function maskTarget(target: string, channel: 'EMAIL' | 'SMS' | 'WHATSAPP') {
  if (channel === 'EMAIL') {
    const [local, domain] = target.split('@');
    if (!local || !domain) return target;
    return `${local.slice(0, 2)}***@${domain}`;
  }
  if (target.length <= 6) return target;
  return `${target.slice(0, 3)}***${target.slice(-3)}`;
}

async function sendEmailOtp(target: string, code: string) {
  if (!smtpConfigured()) throw new Error('email_otp_not_configured');
  const port = Number(process.env.SMTP_PORT || 587);
  const secure = String(process.env.SMTP_SECURE || '').toLowerCase() === 'true' || port === 465;
  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  await transporter.sendMail({
    from: process.env.SMTP_FROM,
    to: target,
    subject: 'VELIXEO verification code',
    text: `Your VELIXEO verification code is ${code}. It expires in 10 minutes. Do not share this code.`,
    html: `
      <div style="font-family:Arial,sans-serif;background:#f4f8fc;padding:28px">
        <div style="max-width:520px;margin:auto;background:#fff;border:1px solid #e2eaf2;border-radius:22px;padding:26px">
          <div style="font-weight:900;color:#0b315d;font-size:23px;letter-spacing:1px">VELIXEO</div>
          <h2 style="color:#17263a;margin:24px 0 8px">Verification code</h2>
          <p style="color:#617489;line-height:1.6">Use this code to continue. It expires in 10 minutes.</p>
          <div style="background:linear-gradient(135deg,#0f71d9,#23aaff);color:#fff;font-weight:900;font-size:34px;letter-spacing:8px;text-align:center;padding:18px;border-radius:16px;margin:22px 0">${code}</div>
          <p style="color:#8b99a8;font-size:12px">If you did not request this code, you can ignore this email.</p>
        </div>
      </div>`,
  });
}

async function sendWebhookOtp(channel: 'SMS' | 'WHATSAPP', target: string, code: string) {
  const url = process.env[channel === 'SMS' ? 'OTP_SMS_WEBHOOK_URL' : 'OTP_WHATSAPP_WEBHOOK_URL'];
  if (!url) throw new Error(channel === 'SMS' ? 'sms_otp_not_configured' : 'whatsapp_otp_not_configured');
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(process.env.OTP_WEBHOOK_SECRET ? { authorization: `Bearer ${process.env.OTP_WEBHOOK_SECRET}` } : {}),
    },
    body: JSON.stringify({
      target,
      code,
      channel,
      app: 'VELIXEO',
      expiresInSeconds: 600,
    }),
  });
  if (!response.ok) throw new Error('otp_provider_failed');
}

export async function issueVerificationChallenge(
  prisma: PrismaClient,
  input: {
    userId?: string | null;
    target: string;
    channel: 'EMAIL' | 'SMS' | 'WHATSAPP';
    purpose: string;
  },
) {
  const target = normalizeTarget(input.target, input.channel);
  const now = new Date();
  const lastMinute = new Date(now.getTime() - 60_000);
  const lastHour = new Date(now.getTime() - 3_600_000);

  const [recent, hourly] = await Promise.all([
    prisma.verificationChallenge.findFirst({
      where: { target, purpose: input.purpose, createdAt: { gte: lastMinute } },
      orderBy: { createdAt: 'desc' },
    }),
    prisma.verificationChallenge.count({
      where: { target, purpose: input.purpose, createdAt: { gte: lastHour } },
    }),
  ]);
  if (recent) throw new Error('otp_resend_too_soon');
  if (hourly >= 5) throw new Error('otp_rate_limited');

  const code = randomInt(100000, 1000000).toString();
  const challenge = await prisma.verificationChallenge.create({
    data: {
      id: randomUUID(),
      userId: input.userId ?? null,
      target,
      channel: input.channel,
      purpose: input.purpose,
      codeHash: codeHash(code),
      expiresAt: new Date(now.getTime() + 10 * 60_000),
      maxAttempts: 5,
    },
  });

  try {
    if (input.channel === 'EMAIL') await sendEmailOtp(target, code);
    else await sendWebhookOtp(input.channel, target, code);
  } catch (error) {
    await prisma.verificationChallenge.delete({ where: { id: challenge.id } }).catch(() => undefined);
    throw error;
  }

  return {
    challengeId: challenge.id,
    maskedTarget: maskTarget(target, input.channel),
    channel: input.channel,
    purpose: input.purpose,
    expiresInSeconds: 600,
    resendAfterSeconds: 60,
  };
}

export async function verifyVerificationChallenge(
  app: FastifyInstance,
  prisma: PrismaClient,
  challengeId: string,
  code: string,
  expectedUserId?: string,
) {
  const challenge = await prisma.verificationChallenge.findUnique({ where: { id: challengeId } });
  if (!challenge) throw new Error('otp_not_found');
  if (expectedUserId && challenge.userId !== expectedUserId) throw new Error('otp_not_found');
  if (challenge.consumedAt) throw new Error('otp_already_used');
  if (challenge.expiresAt <= new Date()) throw new Error('otp_expired');
  if (challenge.attempts >= challenge.maxAttempts) throw new Error('otp_attempts_exceeded');

  if (challenge.codeHash !== codeHash(code)) {
    await prisma.verificationChallenge.update({
      where: { id: challenge.id },
      data: { attempts: { increment: 1 } },
    });
    throw new Error('otp_invalid');
  }

  const consumed = await prisma.verificationChallenge.update({
    where: { id: challenge.id },
    data: { consumedAt: new Date(), attempts: { increment: 1 } },
  });
  const verificationToken = app.jwt.sign(
    {
      kind: 'verification',
      challengeId: consumed.id,
      userId: consumed.userId,
      target: consumed.target,
      channel: consumed.channel,
      purpose: consumed.purpose,
    },
    { expiresIn: '10m' },
  );
  return {
    ok: true,
    verificationToken,
    target: consumed.target,
    channel: consumed.channel,
    purpose: consumed.purpose,
  };
}

function errorReply(reply: FastifyReply, error: unknown) {
  const code = error instanceof Error ? error.message : 'otp_failed';
  const status = code === 'otp_resend_too_soon' || code === 'otp_rate_limited' ? 429
    : code.endsWith('_not_configured') ? 503
    : code === 'otp_provider_failed' ? 502
    : 400;
  return reply.code(status).send({ error: code });
}

export function registerVerificationRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthHandler,
) {
  app.get('/api/v1/auth/verification-capabilities', async () => capabilities());

  app.post('/api/v1/auth/verification/request', async (request, reply) => {
    const parsed = publicRequestSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const target = normalizeTarget(parsed.data.target, parsed.data.channel);
    if (parsed.data.channel === 'EMAIL' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(target)) {
      return reply.code(400).send({ error: 'invalid_email' });
    }
    if (parsed.data.channel !== 'EMAIL' && !/^\+[1-9]\d{6,14}$/.test(target)) {
      return reply.code(400).send({ error: 'invalid_phone' });
    }
    try {
      return await issueVerificationChallenge(prisma, parsed.data);
    } catch (error) {
      return errorReply(reply, error);
    }
  });

  app.post('/api/v1/auth/verification/verify', async (request, reply) => {
    const parsed = verifySchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    try {
      return await verifyVerificationChallenge(app, prisma, parsed.data.challengeId, parsed.data.code);
    } catch (error) {
      return errorReply(reply, error);
    }
  });

  app.post('/api/v1/me/verification/request', { preHandler: authenticate }, async (request, reply) => {
    const parsed = authRequestSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as { sub: string };
    const user = await prisma.user.findUnique({ where: { id: claims.sub } });
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    let target: string | null = null;
    if (parsed.data.channel === 'EMAIL') target = user.email;
    else target = user.phone;
    if (!target) return reply.code(400).send({ error: parsed.data.channel === 'EMAIL' ? 'email_required' : 'phone_required' });

    if (parsed.data.purpose === 'VERIFY_EMAIL' && parsed.data.channel !== 'EMAIL') {
      return reply.code(400).send({ error: 'invalid_channel' });
    }
    if (parsed.data.purpose === 'VERIFY_PHONE' && parsed.data.channel === 'EMAIL') {
      return reply.code(400).send({ error: 'invalid_channel' });
    }
    try {
      return await issueVerificationChallenge(prisma, {
        userId: user.id,
        target,
        channel: parsed.data.channel,
        purpose: parsed.data.purpose,
      });
    } catch (error) {
      return errorReply(reply, error);
    }
  });

  app.post('/api/v1/me/verification/verify', { preHandler: authenticate }, async (request, reply) => {
    const parsed = verifySchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as { sub: string };
    try {
      return await verifyVerificationChallenge(app, prisma, parsed.data.challengeId, parsed.data.code, claims.sub);
    } catch (error) {
      return errorReply(reply, error);
    }
  });
}

export { capabilities as verificationCapabilities };
