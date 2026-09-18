import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  PaymentStatus,
  Prisma,
  PrismaClient,
  WalletEntryType,
} from '@prisma/client';
import { z } from 'zod';
import { NotificationPriority, NotificationType } from '@prisma/client';
import { publishUserNotification } from './pushNotifications.js';

// Payment webhooks publish one typed in-app + FCM notification only on the first verified state transition.

type AuthenticateHook = (
  request: FastifyRequest,
  reply: FastifyReply,
) => Promise<unknown>;

type JwtClaims = { sub: string };

const webhookItemSchema = z
  .object({
    id: z.string().trim().min(1).max(200),
    name: z.string().optional(),
    price: z.union([z.number(), z.string()]).optional(),
  })
  .passthrough();

const webhookSchema = z
  .object({
    status_code: z.number().optional(),
    success: z.boolean(),
    message: z.string().max(500).optional(),
    sender_account: z.union([z.string(), z.number()]).optional(),
    transaction_id: z.string().trim().min(1).max(200).optional(),
    amount: z.union([z.number(), z.string()]).optional(),
    signature: z.string().trim().min(1).max(500),
    timestamp: z.union([z.string().trim().min(1).max(100), z.number()]),
    user_id: z.string().trim().max(200).optional(),
    items: z.array(webhookItemSchema).max(100).optional(),
    email: z.string().max(320).optional(),
  })
  .passthrough();

const verificationResponseSchema = z
  .object({
    success: z.boolean(),
    message: z.string().optional(),
    status_code: z.number().optional(),
  })
  .passthrough();

function config() {
  const parsed = z
    .object({
      HESABPAY_ENVIRONMENT: z.enum(['sandbox', 'production']).default('sandbox'),
      HESABPAY_API_KEY: z.string().trim().min(1).optional(),
      HESABPAY_API_BASE_URL: z.string().url().optional(),
      HESABPAY_TIMEOUT_MS: z.coerce.number().int().min(1000).max(60_000).default(15_000),
      PUBLIC_BASE_URL: z.string().url().optional(),
    })
    .safeParse(process.env);

  if (!parsed.success || !parsed.data.HESABPAY_API_KEY) {
    return { configured: false as const };
  }

  const value = parsed.data;
  const baseUrl =
    value.HESABPAY_API_BASE_URL ??
    (value.HESABPAY_ENVIRONMENT === 'production'
      ? 'https://api.hesab.com'
      : 'https://api-sandbox.hesab.com');

  return {
    configured: true as const,
    environment: value.HESABPAY_ENVIRONMENT,
    apiKey: value.HESABPAY_API_KEY,
    baseUrl: baseUrl.replace(/\/$/, ''),
    timeoutMs: value.HESABPAY_TIMEOUT_MS,
    publicBaseUrl: value.PUBLIC_BASE_URL?.replace(/\/$/, ''),
  };
}

function webhookUrl(publicBaseUrl?: string) {
  if (!publicBaseUrl) return null;
  return `${publicBaseUrl}/api/v1/payments/hesabpay/webhook`;
}

function paymentIdFromPayload(payload: z.infer<typeof webhookSchema>) {
  const candidates = [
    payload.user_id,
    ...(payload.items ?? []).map((item) => item.id),
  ].filter((value): value is string => typeof value === 'string');

  for (const candidate of candidates) {
    const normalized = candidate.startsWith('VLX-') ? candidate.slice(4) : candidate;
    if (z.string().uuid().safeParse(normalized).success) return normalized;
  }
  return null;
}

function amountAfnFromPayload(value: number | string | undefined) {
  if (value === undefined) return null;
  const numeric = typeof value === 'number' ? value : Number(value);
  if (!Number.isSafeInteger(numeric) || numeric <= 0) return null;
  return BigInt(numeric);
}

async function verifyWebhookSignature(
  gateway: Extract<ReturnType<typeof config>, { configured: true }>,
  signature: string,
  timestamp: string,
) {
  const response = await fetch(
    `${gateway.baseUrl}/api/v1/hesab/webhooks/verify-signature`,
    {
      method: 'POST',
      headers: {
        Authorization: `API-KEY ${gateway.apiKey}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
      },
      body: JSON.stringify({ signature, timestamp }),
      signal: AbortSignal.timeout(gateway.timeoutMs),
    },
  );

  const raw = await response.json().catch(() => null);
  const parsed = verificationResponseSchema.safeParse(raw);
  if (!response.ok || !parsed.success) {
    return { verified: false as const, upstreamError: true as const };
  }
  return {
    verified: parsed.data.success === true,
    upstreamError: false as const,
    message: parsed.data.message,
  };
}

async function creditVerifiedPayment(
  prisma: PrismaClient,
  input: {
    paymentId: string;
    amountAfn: bigint;
    transactionId: string;
  },
) {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      return await prisma.$transaction(
        async (tx) => {
          const payment = await tx.paymentTransaction.findUnique({
            where: { id: input.paymentId },
          });
          if (!payment || payment.gateway !== 'HESABPAY') {
            throw new Error('PAYMENT_NOT_FOUND');
          }

          if (payment.status === PaymentStatus.PAID) {
            if (payment.externalId && payment.externalId !== input.transactionId) {
              throw new Error('TRANSACTION_MISMATCH');
            }
            return { payment, idempotent: true };
          }

          if (payment.status !== PaymentStatus.PENDING) {
            throw new Error('PAYMENT_NOT_PENDING');
          }
          if (payment.amountAfn !== input.amountAfn) {
            throw new Error('AMOUNT_MISMATCH');
          }

          const transactionOwner = await tx.paymentTransaction.findUnique({
            where: { externalId: input.transactionId },
          });
          if (transactionOwner && transactionOwner.id !== payment.id) {
            throw new Error('TRANSACTION_ALREADY_USED');
          }

          const wallet = await tx.wallet.findUnique({
            where: { userId: payment.userId },
          });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');

          const idempotencyKey = `hesabpay-credit-${payment.id}`;
          const existingCredit = await tx.walletEntry.findUnique({
            where: { idempotencyKey },
          });
          if (existingCredit) {
            const paid = await tx.paymentTransaction.update({
              where: { id: payment.id },
              data: {
                status: PaymentStatus.PAID,
                externalId: input.transactionId,
                paidAt: payment.paidAt ?? new Date(),
                verifiedAt: payment.verifiedAt ?? new Date(),
                failureReason: null,
              },
            });
            return { payment: paid, idempotent: true };
          }

          const nextBalance = wallet.balanceAfn + payment.amountAfn;
          await tx.wallet.update({
            where: { id: wallet.id },
            data: { balanceAfn: nextBalance },
          });
          await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.DEPOSIT,
              amountAfn: payment.amountAfn,
              balanceAfterAfn: nextBalance,
              description: 'HesabPay wallet top-up',
              idempotencyKey,
              referenceType: 'PAYMENT',
              referenceId: payment.id,
              metadata: {
                gateway: 'HESABPAY',
                transactionId: input.transactionId,
              },
            },
          });

          const paid = await tx.paymentTransaction.update({
            where: { id: payment.id },
            data: {
              status: PaymentStatus.PAID,
              externalId: input.transactionId,
              paidAt: new Date(),
              verifiedAt: new Date(),
              failureReason: null,
            },
          });
          return { payment: paid, idempotent: false };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        (error.code === 'P2034' || error.code === 'P2002') &&
        attempt < 3
      ) {
        continue;
      }
      throw error;
    }
  }

  throw new Error('PAYMENT_CREDIT_FAILED');
}

async function markVerifiedFailure(
  prisma: PrismaClient,
  paymentId: string,
  reason: string,
) {
  const payment = await prisma.paymentTransaction.findUnique({
    where: { id: paymentId },
  });
  if (!payment || payment.gateway !== 'HESABPAY') throw new Error('PAYMENT_NOT_FOUND');
  if (payment.status === PaymentStatus.PAID || payment.status === PaymentStatus.REFUNDED) {
    return { payment, idempotent: true };
  }
  if (payment.status === PaymentStatus.FAILED) {
    return { payment, idempotent: true };
  }
  const failed = await prisma.paymentTransaction.update({
    where: { id: payment.id },
    data: {
      status: PaymentStatus.FAILED,
      failureReason: reason.slice(0, 300),
      verifiedAt: new Date(),
    },
  });
  return { payment: failed, idempotent: false };
}

export function registerHesabPayWebhookRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  authenticate: AuthenticateHook,
) {
  app.get(
    '/api/v1/payments/capabilities',
    { preHandler: authenticate },
    async (request) => {
      const gateway = config();
      return {
        baseCurrency: 'AFN',
        gateways: {
          HESABPAY: {
            configured: gateway.configured,
            environment: gateway.configured ? gateway.environment : null,
          },
        },
        webhookPath: '/api/v1/payments/hesabpay/webhook',
        webhookUrl: gateway.configured ? webhookUrl(gateway.publicBaseUrl) : null,
        userId: (request.user as JwtClaims).sub,
      };
    },
  );

  app.post('/api/v1/payments/hesabpay/webhook', async (request, reply) => {
    const parsed = webhookSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ error: 'invalid_webhook_payload' });

    const gateway = config();
    if (!gateway.configured) {
      return reply.code(503).send({ error: 'hesabpay_not_configured' });
    }

    let verification;
    try {
      verification = await verifyWebhookSignature(
        gateway,
        parsed.data.signature,
        String(parsed.data.timestamp),
      );
    } catch (error) {
      request.log.warn({ error }, 'HesabPay signature verification request failed');
      return reply.code(502).send({ error: 'hesabpay_signature_verification_unavailable' });
    }

    if (verification.upstreamError) {
      return reply.code(502).send({ error: 'hesabpay_signature_verification_failed' });
    }
    if (!verification.verified) {
      return reply.code(401).send({ error: 'invalid_webhook_signature' });
    }

    const paymentId = paymentIdFromPayload(parsed.data);
    if (!paymentId) return reply.code(400).send({ error: 'payment_reference_missing' });

    try {
      if (parsed.data.success) {
        const amountAfn = amountAfnFromPayload(parsed.data.amount);
        if (amountAfn === null) {
          return reply.code(400).send({ error: 'invalid_webhook_amount' });
        }
        const transactionId = parsed.data.transaction_id?.trim();
        if (!transactionId) {
          return reply.code(400).send({ error: 'transaction_id_missing' });
        }

        const result = await creditVerifiedPayment(prisma, {
          paymentId,
          amountAfn,
          transactionId,
        });
        if (!result.idempotent) {
          await publishUserNotification(prisma,result.payment.userId,{
            type:NotificationType.PAYMENT,priority:NotificationPriority.HIGH,
            titleEn:'Payment successful',titleFa:'پرداخت موفق بود',
            bodyEn:`${amountAfn.toLocaleString('en-US')} AFN was added to your VELIXEO wallet.`,
            bodyFa:`${amountAfn.toLocaleString('en-US')} افغانی با موفقیت به کیف پول VELIXEO شما اضافه شد.`,
            actionRoute:'wallet',actionEntityId:result.payment.id,actionLabelEn:'Open wallet',actionLabelFa:'مشاهده کیف پول',
          });
        }
        return reply.code(200).send({
          ok: true,
          paymentId: result.payment.id,
          status: result.payment.status,
          idempotent: result.idempotent,
        });
      }

      const result = await markVerifiedFailure(
        prisma,
        paymentId,
        parsed.data.message || 'HesabPay reported payment failure',
      );
      if (!result.idempotent) {
        await publishUserNotification(prisma,result.payment.userId,{
          type:NotificationType.PAYMENT,priority:NotificationPriority.HIGH,
          titleEn:'Payment was not completed',titleFa:'پرداخت تکمیل نشد',
          bodyEn:'Your HesabPay payment could not be completed. Your wallet was not charged.',
          bodyFa:'پرداخت حساب‌پی تکمیل نشد و مبلغی به کیف پول شما اضافه نگردید.',
          actionRoute:'wallet',actionEntityId:result.payment.id,actionLabelEn:'View payments',actionLabelFa:'مشاهده پرداخت‌ها',
        });
      }
      return reply.code(200).send({
        ok: true,
        paymentId: result.payment.id,
        status: result.payment.status,
        idempotent: result.idempotent,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'UNKNOWN';
      if (message === 'PAYMENT_NOT_FOUND') {
        return reply.code(404).send({ error: 'payment_not_found' });
      }
      if (message === 'AMOUNT_MISMATCH') {
        request.log.warn({ paymentId }, 'Rejected HesabPay webhook amount mismatch');
        return reply.code(409).send({ error: 'payment_amount_mismatch' });
      }
      if (message === 'PAYMENT_NOT_PENDING') {
        return reply.code(409).send({ error: 'payment_not_pending' });
      }
      if (message === 'TRANSACTION_MISMATCH' || message === 'TRANSACTION_ALREADY_USED') {
        request.log.warn({ paymentId }, 'Rejected HesabPay webhook transaction mismatch');
        return reply.code(409).send({ error: 'payment_transaction_conflict' });
      }
      if (message === 'WALLET_NOT_FOUND') {
        return reply.code(409).send({ error: 'wallet_not_found' });
      }
      throw error;
    }
  });
}
