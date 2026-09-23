import type { PrismaClient } from '@prisma/client';
import { premiumTelegramSettings, sendPremiumTelegramMessage } from './telegramAdminAlerts.js';

function clean(value: unknown, max = 600) {
  return String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, max);
}

function categoryName(category: string) {
  const names: Record<string, string> = {
    SOCIAL: 'Social Media',
    VIRTUAL_NUMBER: 'Virtual Number',
    PREMIUM: 'Premium / Subscription',
    DIGITAL_ACCOUNT: 'Digital Account',
    MOBILE_TOPUP: 'Mobile Top-up',
    PROMOTION: 'Promotion',
  };
  return names[category] ?? category.replaceAll('_', ' ');
}

export async function sendAdminRegistrationAlert(
  prisma: PrismaClient,
  input: { userId: string; method: 'PASSWORD' | 'GOOGLE'; referralCode?: string | null },
) {
  const settings = await premiumTelegramSettings(prisma);
  if (!settings.enabled) return { sent: false, reason: 'disabled' };
  const user = await prisma.user.findUnique({ where: { id: input.userId } });
  if (!user) return { sent: false, reason: 'user_not_found' };
  return sendPremiumTelegramMessage(prisma, [
    '👤 VELIXEO — New Registration',
    '',
    `Customer: ${clean(user.fullName || '—')}`,
    `Email: ${clean(user.email || '—')}`,
    `Phone: ${clean(user.phone || '—')}`,
    `Method: ${input.method}`,
    `Language: ${clean(user.locale)}`,
    `Referral: ${clean(input.referralCode || '—')}`,
    `User ID: ${user.id}`,
    `Created: ${user.createdAt.toISOString()}`,
  ].join('\n'));
}

export async function sendAdminWalletTopupAlert(
  prisma: PrismaClient,
  input: { paymentId: string; transactionId?: string | null },
) {
  const payment = await prisma.paymentTransaction.findUnique({
    where: { id: input.paymentId },
    include: { user: { include: { wallet: true } } },
  });
  if (!payment) return { sent: false, reason: 'payment_not_found' };
  return sendPremiumTelegramMessage(prisma, [
    '💰 VELIXEO — Wallet Top-up Successful',
    '',
    `Customer: ${clean(payment.user.fullName || '—')}`,
    `Contact: ${clean(payment.user.email || payment.user.phone || '—')}`,
    `Amount: ${payment.amountAfn.toLocaleString('en-US')} AFN`,
    `New balance: ${(payment.user.wallet?.balanceAfn ?? 0n).toLocaleString('en-US')} AFN`,
    `Gateway: ${clean(payment.gateway)}`,
    `Transaction: ${clean(input.transactionId || payment.externalId || '—')}`,
    `Payment ID: ${payment.id}`,
    '',
    '✅ Payment was verified before the wallet was credited.',
  ].join('\n'));
}

export async function sendAdminWalletAdjustmentAlert(
  prisma: PrismaClient,
  input: { userId: string; amountAfn: bigint; balanceAfterAfn: bigint; reason: string; adminName?: string | null },
) {
  const user = await prisma.user.findUnique({ where: { id: input.userId } });
  if (!user) return { sent: false, reason: 'user_not_found' };
  return sendPremiumTelegramMessage(prisma, [
    input.amountAfn >= 0n ? '➕ VELIXEO — Manual Wallet Credit' : '➖ VELIXEO — Manual Wallet Debit',
    '',
    `Customer: ${clean(user.fullName || '—')}`,
    `Contact: ${clean(user.email || user.phone || '—')}`,
    `Amount: ${input.amountAfn.toLocaleString('en-US')} AFN`,
    `New balance: ${input.balanceAfterAfn.toLocaleString('en-US')} AFN`,
    `Reason: ${clean(input.reason)}`,
    `Admin: ${clean(input.adminName || 'Administrator')}`,
  ].join('\n'));
}

export async function sendAdminOrderAlert(
  prisma: PrismaClient,
  orderId: string,
  note?: string,
) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { user: true, service: true, provider: true },
  });
  if (!order) return { sent: false, reason: 'order_not_found' };

  const rawInput = order.input && typeof order.input === 'object' && !Array.isArray(order.input)
    ? order.input as Record<string, unknown>
    : {};
  const rawOutput = order.output && typeof order.output === 'object' && !Array.isArray(order.output)
    ? order.output as Record<string, unknown>
    : {};
  const params = rawInput.parameters && typeof rawInput.parameters === 'object' && !Array.isArray(rawInput.parameters)
    ? rawInput.parameters as Record<string, unknown>
    : {};
  const pkg = rawInput.package && typeof rawInput.package === 'object' && !Array.isArray(rawInput.package)
    ? rawInput.package as Record<string, unknown>
    : {};
  const fields = rawInput.submittedFields && typeof rawInput.submittedFields === 'object' && !Array.isArray(rawInput.submittedFields)
    ? rawInput.submittedFields as Record<string, unknown>
    : {};

  const details: string[] = [];
  if (order.category === 'SOCIAL') {
    const target = params.link ?? params.username ?? params.url;
    if (target) details.push(`Target: ${clean(target)}`);
    if (rawInput.providerType) details.push(`Type: ${clean(rawInput.providerType)}`);
    if (rawInput.runs && Number(rawInput.runs) > 1) details.push(`Drip runs: ${clean(rawInput.runs)}`);
  }
  if (order.category === 'VIRTUAL_NUMBER') {
    const country = rawOutput.country ?? rawInput.selectedCountry ?? rawInput.country;
    const operator = rawOutput.operator ?? rawInput.selectedOperator ?? rawInput.operator;
    if (country) details.push(`Country: ${clean(country)}`);
    if (operator) details.push(`Operator: ${clean(operator)}`);
    if (rawOutput.phone) details.push(`Number: ${clean(rawOutput.phone)}`);
    if (rawInput.mode) details.push(`Mode: ${clean(rawInput.mode)}`);
  }
  if (order.category === 'PREMIUM') {
    const packageTitle = pkg.titleEn ?? pkg.titleFa ?? pkg.id;
    if (packageTitle) details.push(`Package: ${clean(packageTitle)}`);
    for (const [key, value] of Object.entries(fields).slice(0, 12)) {
      if (String(value ?? '').trim()) details.push(`${clean(key, 80)}: ${clean(value)}`);
    }
  }
  if (order.category === 'PROMOTION') {
    const packageTitle = pkg.titleEn ?? pkg.titleFa ?? pkg.id;
    if (packageTitle) details.push(`Package: ${clean(packageTitle)}`);
    if (rawInput.platform) details.push(`Platform: ${clean(rawInput.platform)}`);
    if (rawInput.instagramUsername) details.push(`Instagram: @${clean(rawInput.instagramUsername, 120)}`);
    if (rawInput.instagramPageName) details.push(`Facebook Page: ${clean(rawInput.instagramPageName, 180)}`);
    if (rawInput.instagramMediaId) details.push(`Instagram media ID: ${clean(rawInput.instagramMediaId, 160)}`);
    if (rawInput.metaAdvertisingReady) details.push('Meta page task: ADVERTISE ✅');
    if (rawInput.postUrl) details.push(`Post: ${clean(rawInput.postUrl, 1000)}`);
    if (rawInput.partnershipAdCode) details.push(`Ad code: ${clean(rawInput.partnershipAdCode, 1200)}`);
    if (rawInput.objective) details.push(`Objective: ${clean(rawInput.objective)}`);
    if (Array.isArray(rawInput.targetCountries) && rawInput.targetCountries.length) {
      details.push(`Target: ${clean(rawInput.targetCountries.join(', '), 500)}`);
    }
    if (rawInput.audienceNotes) details.push(`Audience: ${clean(rawInput.audienceNotes, 700)}`);
    if (rawInput.websiteUrl) details.push(`Website: ${clean(rawInput.websiteUrl, 1000)}`);
    if (pkg.durationDays) details.push(`Duration: ${clean(pkg.durationDays)} day(s)`);
    if (pkg.adBudgetAfn) details.push(`Ad budget: ${clean(pkg.adBudgetAfn)} AFN`);
  }
  if (order.providerOrderId) details.push(`Provider order: ${clean(order.providerOrderId)}`);
  if (note) details.push(`Note: ${clean(note, 700)}`);

  const invoice = order.publicOrderNumber?.toString() ?? order.id.slice(0, 8);
  return sendPremiumTelegramMessage(prisma, [
    '🧾 VELIXEO — New Paid Order',
    '',
    `Invoice: #${invoice}`,
    `Section: ${categoryName(order.category)}`,
    `Customer: ${clean(order.user.fullName || '—')}`,
    `Contact: ${clean(order.user.email || order.user.phone || '—')}`,
    `Service: ${clean(order.service?.titleEn || order.service?.titleFa || order.serviceId || '—')}`,
    `Quantity: ${order.quantity?.toLocaleString('en-US') ?? '—'}`,
    `Paid: ${order.totalAmountAfn.toLocaleString('en-US')} AFN`,
    `Status: ${clean(order.status)}`,
    `Provider: ${clean(order.provider?.name || '—')}`,
    ...(details.length ? ['', ...details] : []),
    '',
    '✅ Customer wallet payment was completed before this alert was sent.',
  ].join('\n'));
}

export async function sendAdminRefundAlert(
  prisma: PrismaClient,
  orderId: string,
  reason?: string,
) {
  const order = await prisma.order.findUnique({
    where: { id: orderId },
    include: { user: true, service: true },
  });
  if (!order) return { sent: false, reason: 'order_not_found' };
  const invoice = order.publicOrderNumber?.toString() ?? order.id.slice(0, 8);
  return sendPremiumTelegramMessage(prisma, [
    '↩️ VELIXEO — Order Refunded',
    '',
    `Invoice: #${invoice}`,
    `Section: ${categoryName(order.category)}`,
    `Customer: ${clean(order.user.fullName || '—')}`,
    `Service: ${clean(order.service?.titleEn || order.service?.titleFa || '—')}`,
    `Refund: ${order.totalAmountAfn.toLocaleString('en-US')} AFN`,
    `Reason: ${clean(reason || order.failureReason || 'Refunded')}`,
    '',
    '✅ Refund was returned to the customer wallet.',
  ].join('\n'));
}
