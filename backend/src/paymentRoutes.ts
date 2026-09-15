import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { PaymentStatus, Prisma, PrismaClient } from '@prisma/client';
import { createHash } from 'node:crypto';
import { z } from 'zod';

type AuthenticateHook = (
  request: FastifyRequest,
  reply: FastifyReply,
) => Promise<unknown>;

type JwtClaims = { sub: string };

const createSessionSchema = z.object({
  amountAfn: z.union([
    z.number().int().positive().max(100_000_000),
    z.string().regex(/^\d{1,9}$/),
  ]),
  idempotencyKey: z.string().trim().min(8).max(200),
});

const paymentParamsSchema = z.object({
  id: z.string().uuid(),
});

const hesabPayResponseSchema = z
  .object({
    success: z.boolean().optional(),
    url: z.string().url().optional(),
    message: z.string().optional(),
    status_code: z.number().optional(),
  })
  .passthrough();

function paymentConfig() {
  const parsed = z
    .object({
      HESABPAY_ENVIRONMENT: z.enum(['sandbox', 'production']).default('sandbox'),
      HESABPAY_API_KEY: z.string().trim().min(1).optional(),
      HESABPAY_API_BASE_URL: z.string().url().optional(),
      HESABPAY_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(15_000),
      PUBLIC_BASE_URL: z.string().url().optional(),
    })
    .safeParse(process.env);

  if (!parsed.success) {
    return {
      configured: false as const,
      error: 'hesabpay_configuration_invalid',
    };
  }

  const value = parsed.data;
  const baseUrl =
    value.HESABPAY_API_BASE_URL ??
    (value.HESABPAY_ENVIRONMENT === 'production'
      ? 'https://api.hesab.com'
      : 'https://api-sandbox.hesab.com');

  if (!value.HESABPAY_API_KEY) {
    return {
      configured: false as const,
      error: 'hesabpay_not_configured',
    };
  }

  return {
    configured: true as const,
    environment: value.HESABPAY_ENVIRONMENT,
    apiKey: value.HESABPAY_API_KEY,
    baseUrl: baseUrl.replace(/\/$/, ''),
    timeoutMs: value.HESABPAY_TIMEOUT_MS,
    publicBaseUrl: value.PUBLIC_BASE_URL?.replace(/\/$/, ''),
  };
}

function idempotencyHash(userId: string, rawKey: string) {
  return createHash('sha256').update(`${userId}:${rawKey}`).digest('hex');
}

function amountFromInput(value: number | string) {
  const amount = BigInt(String(value));
  if (amount < 1n || amount > 100_000_000n) {
    throw new Error('INVALID_AMOUNT');
  }
  return amount;
}

function paymentJson(payment: {
  id: string;
  gateway: string;
  status: PaymentStatus;
  amountAfn: bigint;
  checkoutUrl: string | null;
  externalId: string | null;
  failureReason: string | null;
  createdAt: Date;
  updatedAt: Date;
  paidAt: Date | null;
  verifiedAt: Date | null;
}) {
  return {
    id: payment.id,
    gateway: payment.gateway,
    status: payment.status,
    amountAfn: payment.amountAfn.toString(),
    checkoutUrl: payment.checkoutUrl,
    externalId: payment.externalId,
    failureReason: payment.failureReason,
    createdAt: payment.createdAt,
    updatedAt: payment.updatedAt,
    paidAt: payment.paidAt,
    verifiedAt: payment.verifiedAt,
  };
}

function redirectUrl(base: string | undefined, path: string, paymentId: string) {
  if (!base) return undefined;
  const url = new URL(path, `${base}/`);
  url.searchParams.set('payment', paymentId);
  return url.toString();
}

function returnPage(kind: 'success' | 'failure') {
  const success = kind === 'success';
  const title = success ? 'پرداخت دریافت شد' : 'پرداخت تکمیل نشد';
  const body = success
    ? 'نتیجه پرداخت برای بررسی امن به سرور ارسال می‌شود. موجودی فقط پس از تأیید معتبر HesabPay شارژ خواهد شد. می‌توانید به VELIXEO برگردید.'
    : 'پرداخت لغو شد یا موفق نبود. هیچ مبلغی از سمت VELIXEO به کیف پول اضافه نشده است. می‌توانید به برنامه برگردید و دوباره تلاش کنید.';
  return `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${title} — VELIXEO</title><style>body{margin:0;background:#F7FBFF;color:#102235;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;display:grid;min-height:100vh;place-items:center;padding:24px}.card{max-width:560px;background:#fff;border:1px solid #DFF0FA;border-radius:24px;padding:28px;box-shadow:0 18px 60px rgba(13,110,253,.08)}h1{margin:0 0 12px;font-size:25px}p{color:#607487;line-height:1.9;margin:0}.brand{color:#0D6EFD;font-weight:900;margin-bottom:18px}</style></head><body><main class="card"><div class="brand">VELIXEO</div><h1>${title}</h1><p>${body}</p></main></body></html>`;
}

async function findExistingByIdempotency(
  prisma: PrismaClient,
  userId: string,
  idempotencyKey: string,
) {
  const existing = await prisma.paymentTransaction.findUnique({
    where: { idempotencyKey },
  });
  if (!existing) return null;
  if (existing.userId !== userId) throw new Error('IDEMPOTENCY_CONFLICT');
  return existing;
}

export function registerPaymentRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
) {
  app.get('/payments/hesabpay/return/success', async (_request, reply) =>
    reply.type('text/html; charset=utf-8').send(returnPage('success')),
  );

  app.get('/payments/hesabpay/return/failure', async (_request, reply) =>
    reply.type('text/html; charset=utf-8').send(returnPage('failure')),
  );

  app.get(
    '/api/v1/payments',
    { preHandler: authenticate },
    async (request) => {
      const userId = (request.user as JwtClaims).sub;
      const payments = await prisma.paymentTransaction.findMany({
        where: { userId },
        orderBy: { createdAt: 'desc' },
        take: 50,
      });
      return { payments: payments.map(paymentJson) };
    },
  );

  app.get(
    '/api/v1/payments/:id',
    { preHandler: authenticate },
    async (request, reply) => {
      const params = paymentParamsSchema.safeParse(request.params);
      if (!params.success) return reply.code(400).send({ error: 'invalid_request' });
      const userId = (request.user as JwtClaims).sub;
      const payment = await prisma.paymentTransaction.findFirst({
        where: { id: params.data.id, userId },
      });
      if (!payment) return reply.code(404).send({ error: 'payment_not_found' });
      return { payment: paymentJson(payment) };
    },
  );

  app.post(
    '/api/v1/payments/hesabpay/session',
    { preHandler: authenticate },
    async (request, reply) => {
      const parsed = createSessionSchema.safeParse(request.body);
      if (!parsed.success) return reply.code(400).send({ error: 'invalid_request' });

      let amountAfn: bigint;
      try {
        amountAfn = amountFromInput(parsed.data.amountAfn);
      } catch {
        return reply.code(400).send({ error: 'invalid_amount' });
      }

      const config = paymentConfig();
      if (!config.configured) {
        return reply.code(503).send({ error: config.error });
      }

      const userId = (request.user as JwtClaims).sub;
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { id: true, email: true },
      });
      if (!user) return reply.code(401).send({ error: 'unauthorized' });

      const hashedKey = idempotencyHash(userId, parsed.data.idempotencyKey);
      try {
        const existing = await findExistingByIdempotency(prisma, userId, hashedKey);
        if (existing) {
          if (existing.status === PaymentStatus.PENDING && existing.checkoutUrl) {
            return reply.code(200).send({
              payment: paymentJson(existing),
              checkoutUrl: existing.checkoutUrl,
              idempotent: true,
            });
          }
          if (existing.status === PaymentStatus.PENDING) {
            return reply.code(202).send({
              payment: paymentJson(existing),
              error: 'payment_session_initializing',
              idempotent: true,
            });
          }
          return reply.code(409).send({
            error: 'idempotency_key_already_used',
            payment: paymentJson(existing),
          });
        }
      } catch (error) {
        if (error instanceof Error && error.message === 'IDEMPOTENCY_CONFLICT') {
          return reply.code(409).send({ error: 'idempotency_conflict' });
        }
        throw error;
      }

      let payment;
      try {
        payment = await prisma.paymentTransaction.create({
          data: {
            userId,
            gateway: 'HESABPAY',
            status: PaymentStatus.PENDING,
            amountAfn,
            idempotencyKey: hashedKey,
            metadata: {
              purpose: 'WALLET_TOPUP',
              gatewayEnvironment: config.environment,
              sessionState: 'creating',
            },
          },
        });
      } catch (error) {
        if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
          const raced = await findExistingByIdempotency(prisma, userId, hashedKey);
          if (raced) {
            return reply.code(raced.checkoutUrl ? 200 : 202).send({
              payment: paymentJson(raced),
              checkoutUrl: raced.checkoutUrl,
              idempotent: true,
            });
          }
        }
        throw error;
      }

      const gatewayBody: Record<string, unknown> = {
        user_id: payment.id,
        items: [
          {
            id: payment.id,
            name: 'VELIXEO Wallet Top-up',
            price: Number(amountAfn),
          },
        ],
      };
      if (user.email) gatewayBody.email = user.email;

      const successUrl = redirectUrl(
        config.publicBaseUrl,
        '/payments/hesabpay/return/success',
        payment.id,
      );
      const failureUrl = redirectUrl(
        config.publicBaseUrl,
        '/payments/hesabpay/return/failure',
        payment.id,
      );
      if (successUrl) gatewayBody.redirect_success_url = successUrl;
      if (failureUrl) gatewayBody.redirect_failure_url = failureUrl;

      try {
        const response = await fetch(`${config.baseUrl}/api/v1/payment/create-session`, {
          method: 'POST',
          headers: {
            Authorization: `API-KEY ${config.apiKey}`,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: JSON.stringify(gatewayBody),
          signal: AbortSignal.timeout(config.timeoutMs),
        });

        const raw = await response.json().catch(() => null);
        const gateway = hesabPayResponseSchema.safeParse(raw);
        if (!response.ok || !gateway.success || gateway.data.success !== true || !gateway.data.url) {
          const message =
            gateway.success && gateway.data.message
              ? gateway.data.message.slice(0, 300)
              : `HesabPay session request failed with HTTP ${response.status}`;
          const failed = await prisma.paymentTransaction.update({
            where: { id: payment.id },
            data: {
              status: PaymentStatus.FAILED,
              failureReason: message,
              metadata: {
                purpose: 'WALLET_TOPUP',
                gatewayEnvironment: config.environment,
                sessionState: 'failed',
                gatewayHttpStatus: response.status,
              },
            },
          });
          request.log.warn(
            { paymentId: payment.id, statusCode: response.status },
            'HesabPay create-session failed',
          );
          return reply.code(502).send({
            error: 'hesabpay_session_failed',
            payment: paymentJson(failed),
          });
        }

        const updated = await prisma.paymentTransaction.update({
          where: { id: payment.id },
          data: {
            checkoutUrl: gateway.data.url,
            failureReason: null,
            metadata: {
              purpose: 'WALLET_TOPUP',
              gatewayEnvironment: config.environment,
              sessionState: 'created',
              gatewayStatusCode: gateway.data.status_code ?? null,
            },
          },
        });

        return reply.code(201).send({
          payment: paymentJson(updated),
          checkoutUrl: gateway.data.url,
          idempotent: false,
        });
      } catch (error) {
        const message = error instanceof Error ? error.message.slice(0, 300) : 'gateway_request_failed';
        const failed = await prisma.paymentTransaction.update({
          where: { id: payment.id },
          data: {
            status: PaymentStatus.FAILED,
            failureReason: message,
            metadata: {
              purpose: 'WALLET_TOPUP',
              gatewayEnvironment: config.environment,
              sessionState: 'failed',
            },
          },
        });
        request.log.warn({ paymentId: payment.id, error }, 'HesabPay create-session request error');
        return reply.code(502).send({
          error: 'hesabpay_unavailable',
          payment: paymentJson(failed),
        });
      }
    },
  );
}
