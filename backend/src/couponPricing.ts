import { Prisma, PrismaClient } from '@prisma/client';

export type CouponPrice = {
  subtotalAfn: bigint;
  discountAfn: bigint;
  totalAfn: bigint;
  couponId: string | null;
  couponCode: string | null;
};

function decimalToScaled(value: Prisma.Decimal, scale = 1_000_000n) {
  const text = value.toFixed(6);
  const [whole, fraction = ''] = text.split('.');
  return BigInt(whole) * scale + BigInt(fraction.padEnd(6, '0').slice(0, 6));
}

export async function quoteCoupon(
  prisma: PrismaClient,
  code: string | null | undefined,
  subtotalAfn: bigint,
): Promise<CouponPrice> {
  const normalized = code?.trim().toUpperCase() || null;
  if (!normalized) {
    return { subtotalAfn, discountAfn: 0n, totalAfn: subtotalAfn, couponId: null, couponCode: null };
  }
  const coupon = await prisma.coupon.findUnique({ where: { code: normalized } });
  if (!coupon || !coupon.active) throw new Error('COUPON_INVALID');
  const now = new Date();
  if (coupon.startsAt && coupon.startsAt > now) throw new Error('COUPON_NOT_STARTED');
  if (coupon.endsAt && coupon.endsAt <= now) throw new Error('COUPON_EXPIRED');
  if (coupon.usageLimit != null && coupon.usedCount >= coupon.usageLimit) throw new Error('COUPON_USAGE_LIMIT');
  if (subtotalAfn < coupon.minOrderAfn) throw new Error('COUPON_MIN_ORDER');

  let discountAfn = 0n;
  if (coupon.discountType === 'PERCENT') {
    const percentScaled = decimalToScaled(coupon.discountValue);
    discountAfn = (subtotalAfn * percentScaled) / (100n * 1_000_000n);
  } else {
    discountAfn = decimalToScaled(coupon.discountValue) / 1_000_000n;
  }
  if (coupon.maxDiscountAfn != null && discountAfn > coupon.maxDiscountAfn) {
    discountAfn = coupon.maxDiscountAfn;
  }
  if (discountAfn > subtotalAfn) discountAfn = subtotalAfn;
  if (discountAfn < 0n) discountAfn = 0n;

  return {
    subtotalAfn,
    discountAfn,
    totalAfn: subtotalAfn - discountAfn,
    couponId: coupon.id,
    couponCode: coupon.code,
  };
}

export async function claimCoupon(tx: Prisma.TransactionClient, price: CouponPrice) {
  if (!price.couponId) return;
  const coupon = await tx.coupon.findUnique({ where: { id: price.couponId } });
  if (!coupon || !coupon.active) throw new Error('COUPON_INVALID');
  const now = new Date();
  if (coupon.startsAt && coupon.startsAt > now) throw new Error('COUPON_NOT_STARTED');
  if (coupon.endsAt && coupon.endsAt <= now) throw new Error('COUPON_EXPIRED');
  if (coupon.usageLimit != null) {
    const claimed = await tx.coupon.updateMany({
      where: { id: coupon.id, active: true, usedCount: { lt: coupon.usageLimit } },
      data: { usedCount: { increment: 1 } },
    });
    if (claimed.count != 1) throw new Error('COUPON_USAGE_LIMIT');
  } else {
    await tx.coupon.update({ where: { id: coupon.id }, data: { usedCount: { increment: 1 } } });
  }
}

export async function releaseCoupon(prisma: PrismaClient, couponId: string | null | undefined) {
  if (!couponId) return;
  await prisma.coupon.updateMany({
    where: { id: couponId, usedCount: { gt: 0 } },
    data: { usedCount: { decrement: 1 } },
  });
}
