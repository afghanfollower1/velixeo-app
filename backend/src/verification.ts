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

const contactChangeSchema = z.object({
  type: z.enum(['EMAIL', 'PHONE']),
  target: z.string().trim().min(5).max(254),
  channel: z.enum(['EMAIL', 'SMS', 'WHATSAPP']),
});

const smtpConfigured = () => Boolean(
  process.env.SMTP_HOST
  && process.env.SMTP_USER
  && process.env.SMTP_PASS
  && process.env.SMTP_FROM,
);

const emailWebhookConfigured = () =>
  Boolean(process.env.OTP_EMAIL_WEBHOOK_URL && process.env.OTP_WEBHOOK_SECRET);

const webhookConfigured = (channel: 'SMS' | 'WHATSAPP') =>
  Boolean(process.env[channel === 'SMS' ? 'OTP_SMS_WEBHOOK_URL' : 'OTP_WHATSAPP_WEBHOOK_URL']);

const twilioVerifyConfigured = () => Boolean(
  process.env.TWILIO_ACCOUNT_SID
  && process.env.TWILIO_AUTH_TOKEN
  && process.env.TWILIO_VERIFY_SERVICE_SID,
);

const twilioChannelEnabled = (channel: 'SMS' | 'WHATSAPP') => {
  if (!twilioVerifyConfigured()) return false;
  const key = channel === 'SMS' ? 'TWILIO_VERIFY_SMS_ENABLED' : 'TWILIO_VERIFY_WHATSAPP_ENABLED';
  return String(process.env[key] || '').toLowerCase() === 'true';
};

function capabilities() {
  const smsTwilio = twilioChannelEnabled('SMS');
  const whatsappTwilio = twilioChannelEnabled('WHATSAPP');
  return {
    email: emailWebhookConfigured() || smtpConfigured(),
    emailMode: emailWebhookConfigured() ? 'HTTPS_RELAY' : smtpConfigured() ? 'SMTP' : null,
    sms: smsTwilio || webhookConfigured('SMS'),
    smsMode: smsTwilio ? 'TWILIO_VERIFY' : webhookConfigured('SMS') ? 'WEBHOOK' : null,
    whatsapp: whatsappTwilio || webhookConfigured('WHATSAPP'),
    whatsappMode: whatsappTwilio ? 'TWILIO_VERIFY' : webhookConfigured('WHATSAPP') ? 'WEBHOOK' : null,
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

async function sendEmailViaHttpsRelay(target: string, code: string) {
  const url = process.env.OTP_EMAIL_WEBHOOK_URL;
  const secret = process.env.OTP_WEBHOOK_SECRET;
  if (!url || !secret) throw new Error('email_otp_not_configured');

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${secret}`,
        'x-velixeo-otp-secret': secret,
      },
      body: JSON.stringify({
        target,
        code,
        channel: 'EMAIL',
        app: 'VELIXEO',
        expiresInSeconds: 600,
        secret,
      }),
      signal: controller.signal,
    });
    if (!response.ok) {
      let relayCode = '';
      try {
        const body = await response.json() as { code?: string };
        relayCode = String(body?.code || '');
      } catch {
        // Ignore non-JSON relay responses.
      }
      console.warn('[otp-email-relay] request failed', {
        status: response.status,
        code: relayCode || undefined,
      });
      if (response.status === 401 || response.status === 403) throw new Error('email_otp_auth_failed');
      if (response.status === 404) throw new Error('email_otp_route_missing');
      if (response.status === 502 && relayCode === 'velixeo_mail_failed') throw new Error('email_otp_mail_failed');
      throw new Error('email_otp_provider_failed');
    }
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') {
      throw new Error('email_otp_timeout');
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function sendEmailOtp(target: string, code: string) {
  if (emailWebhookConfigured()) {
    await sendEmailViaHttpsRelay(target, code);
    return;
  }

  if (!smtpConfigured()) throw new Error('email_otp_not_configured');
  const port = Number(process.env.SMTP_PORT || 587);
  const secure = String(process.env.SMTP_SECURE || '').toLowerCase() === 'true' || port === 465;
  const transporter = nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port,
    secure,
    connectionTimeout: 8_000,
    greetingTimeout: 8_000,
    socketTimeout: 12_000,
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
  try {
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
  } catch (error) {
    if (error instanceof Error && /timeout/i.test(error.message)) {
      throw new Error('email_otp_timeout');
    }
    throw new Error('email_otp_provider_failed');
  }
}

function twilioAuthorization() {
  const accountSid = process.env.TWILIO_ACCOUNT_SID;
  const authToken = process.env.TWILIO_AUTH_TOKEN;
  if (!accountSid || !authToken) throw new Error('otp_provider_failed');
  return `Basic ${Buffer.from(`${accountSid}:${authToken}`).toString('base64')}`;
}

async function sendTwilioVerifyOtp(channel: 'SMS' | 'WHATSAPP', target: string, code: string) {
  const serviceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
  if (!serviceSid || !twilioChannelEnabled(channel)) {
    throw new Error(channel === 'SMS' ? 'sms_otp_not_configured' : 'whatsapp_otp_not_configured');
  }

  const form = new URLSearchParams();
  form.set('To', target);
  form.set('Channel', channel === 'SMS' ? 'sms' : 'whatsapp');
  form.set('CustomCode', code);

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const response = await fetch(
      `https://verify.twilio.com/v2/Services/${encodeURIComponent(serviceSid)}/Verifications`,
      {
        method: 'POST',
        headers: {
          authorization: twilioAuthorization(),
          'content-type': 'application/x-www-form-urlencoded',
          accept: 'application/json',
        },
        body: form.toString(),
        signal: controller.signal,
      },
    );
    if (!response.ok) {
      let providerCode: string | number | undefined;
      let providerMessage = '';
      try {
        const body = await response.json() as { code?: string | number; message?: string };
        providerCode = body.code;
        providerMessage = String(body.message || '');
      } catch {
        // Ignore provider bodies that are not JSON.
      }
      console.warn('[otp-twilio-verify] send failed', {
        channel,
        status: response.status,
        code: providerCode,
        message: providerMessage || undefined,
      });
      throw new Error('otp_provider_failed');
    }
  } catch (error) {
    if (error instanceof Error && error.name === 'AbortError') throw new Error('otp_provider_failed');
    throw error;
  } finally {
    clearTimeout(timeout);
  }
}

async function reportTwilioVerification(
  channel: 'SMS' | 'WHATSAPP',
  target: string,
  code: string,
) {
  const serviceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
  if (!serviceSid || !twilioChannelEnabled(channel)) return;

  const form = new URLSearchParams();
  form.set('To', target);
  form.set('Code', code);

  try {
    const response = await fetch(
      `https://verify.twilio.com/v2/Services/${encodeURIComponent(serviceSid)}/VerificationCheck`,
      {
        method: 'POST',
        headers: {
          authorization: twilioAuthorization(),
          'content-type': 'application/x-www-form-urlencoded',
          accept: 'application/json',
        },
        body: form.toString(),
      },
    );
    if (!response.ok) {
      console.warn('[otp-twilio-verify] verification feedback failed', {
        channel,
        status: response.status,
      });
    }
  } catch (error) {
    console.warn('[otp-twilio-verify] verification feedback error', {
      channel,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

async function sendWebhookOtp(channel: 'SMS' | 'WHATSAPP', target: string, code: string) {
  if (twilioChannelEnabled(channel)) {
    await sendTwilioVerifyOtp(channel, target, code);
    return;
  }

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

  if (challenge.channel === 'SMS' || challenge.channel === 'WHATSAPP') {
    await reportTwilioVerification(challenge.channel, challenge.target, code);
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
    : code === 'email_otp_auth_failed' ? 502
    : code === 'email_otp_route_missing' ? 502
    : code === 'email_otp_mail_failed' ? 502
    : code === 'otp_provider_failed' || code === 'email_otp_provider_failed' ? 502
    : code === 'email_otp_timeout' ? 504
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

  app.post('/api/v1/me/contact-change/request', { preHandler: authenticate }, async (request, reply) => {
    const parsed = contactChangeSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });
    const claims = request.user as { sub: string };
    const user = await prisma.user.findUnique({ where: { id: claims.sub } });
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    const target = normalizeTarget(parsed.data.target, parsed.data.channel);
    if (parsed.data.type === 'EMAIL') {
      if (parsed.data.channel !== 'EMAIL') return reply.code(400).send({ error: 'invalid_channel' });
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(target)) return reply.code(400).send({ error: 'invalid_email' });
      const exists = await prisma.user.findFirst({ where: { email: target, id: { not: user.id } } });
      if (exists) return reply.code(409).send({ error: 'email_already_registered' });
    } else {
      if (parsed.data.channel === 'EMAIL') return reply.code(400).send({ error: 'invalid_channel' });
      if (!/^\+[1-9]\d{6,14}$/.test(target)) return reply.code(400).send({ error: 'invalid_phone' });
      const exists = await prisma.user.findFirst({ where: { phone: target, id: { not: user.id } } });
      if (exists) return reply.code(409).send({ error: 'phone_already_registered' });
    }

    try {
      return await issueVerificationChallenge(prisma, {
        userId: user.id,
        target,
        channel: parsed.data.channel,
        purpose: parsed.data.type === 'EMAIL' ? 'VERIFY_EMAIL' : 'VERIFY_PHONE',
      });
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
