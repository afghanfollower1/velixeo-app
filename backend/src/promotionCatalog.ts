import type { Prisma } from '@prisma/client';

export type PromotionPlatform = 'INSTAGRAM' | 'FACEBOOK';
export type PromotionObjective =
  | 'ENGAGEMENT'
  | 'PROFILE_VISITS'
  | 'MESSAGES'
  | 'WEBSITE_VISITS'
  | 'AWARENESS';

export type PromotionPackage = {
  id: string;
  titleFa: string;
  titleEn: string;
  priceAfn: string;
  adBudgetAfn: string;
  serviceFeeAfn: string;
  durationDays: number;
  enabled: boolean;
  sortOrder: number;
  badgeFa: string;
  badgeEn: string;
  estimateFa: string;
  estimateEn: string;
};

export type PromotionMeta = {
  version: 1;
  platform: PromotionPlatform;
  deliveryMinHours: number;
  deliveryMaxHours: number;
  iconUrl: string;
  instructionsFa: string;
  instructionsEn: string;
  supportedObjectives: PromotionObjective[];
  requirePartnershipAdCode: boolean;
  packages: PromotionPackage[];
};

const platforms = new Set<PromotionPlatform>(['INSTAGRAM', 'FACEBOOK']);
const objectives = new Set<PromotionObjective>([
  'ENGAGEMENT',
  'PROFILE_VISITS',
  'MESSAGES',
  'WEBSITE_VISITS',
  'AWARENESS',
]);

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}
function str(value: unknown, fallback = '') {
  return typeof value === 'string' ? value.trim() : fallback;
}
function int(value: unknown, fallback: number, min = 0, max = 1_000_000) {
  const parsed = Number(value);
  return Number.isInteger(parsed) ? Math.max(min, Math.min(max, parsed)) : fallback;
}
function bool(value: unknown, fallback = false) {
  return typeof value === 'boolean' ? value : fallback;
}
function key(value: unknown, fallback: string) {
  const cleaned = str(value)
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
  return cleaned || fallback;
}

export function parsePromotionMetadata(value: Prisma.JsonValue | unknown): PromotionMeta {
  const root = obj(value);
  const raw = obj(root.promotion ?? root);
  const rawPackages = Array.isArray(raw.packages) ? raw.packages : [];
  const rawObjectives = Array.isArray(raw.supportedObjectives) ? raw.supportedObjectives : [];
  const platformRaw = str(raw.platform, 'INSTAGRAM').toUpperCase() as PromotionPlatform;

  const packages = rawPackages
    .map((item, index): PromotionPackage | null => {
      const row = obj(item);
      const id = key(row.id, `package-${index + 1}`);
      const priceAfn = str(row.priceAfn);
      const adBudgetAfn = str(row.adBudgetAfn, priceAfn);
      const serviceFeeAfn = str(row.serviceFeeAfn, '0');
      if (!/^\d+$/.test(priceAfn) || BigInt(priceAfn) <= 0n) return null;
      if (!/^\d+$/.test(adBudgetAfn) || BigInt(adBudgetAfn) < 0n) return null;
      if (!/^\d+$/.test(serviceFeeAfn) || BigInt(serviceFeeAfn) < 0n) return null;
      return {
        id,
        titleFa: str(row.titleFa, str(row.titleEn, id)),
        titleEn: str(row.titleEn, str(row.titleFa, id)),
        priceAfn,
        adBudgetAfn,
        serviceFeeAfn,
        durationDays: int(row.durationDays, 3, 1, 90),
        enabled: bool(row.enabled, true),
        sortOrder: int(row.sortOrder, (index + 1) * 10, 1, 1_000_000),
        badgeFa: str(row.badgeFa),
        badgeEn: str(row.badgeEn),
        estimateFa: str(row.estimateFa),
        estimateEn: str(row.estimateEn),
      };
    })
    .filter((item): item is PromotionPackage => item !== null)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.titleEn.localeCompare(b.titleEn));

  const supportedObjectives = rawObjectives
    .map((item) => str(item).toUpperCase() as PromotionObjective)
    .filter((item): item is PromotionObjective => objectives.has(item));

  return {
    version: 1,
    platform: platforms.has(platformRaw) ? platformRaw : 'INSTAGRAM',
    deliveryMinHours: int(raw.deliveryMinHours, 1, 0, 720),
    deliveryMaxHours: int(raw.deliveryMaxHours, 12, 1, 720),
    iconUrl: str(raw.iconUrl),
    instructionsFa: str(raw.instructionsFa),
    instructionsEn: str(raw.instructionsEn),
    supportedObjectives: supportedObjectives.length
      ? [...new Set(supportedObjectives)]
      : ['ENGAGEMENT', 'PROFILE_VISITS', 'MESSAGES', 'WEBSITE_VISITS', 'AWARENESS'],
    requirePartnershipAdCode: bool(raw.requirePartnershipAdCode, false),
    packages,
  };
}

export function promotionMetadataJson(meta: PromotionMeta): Prisma.InputJsonValue {
  return {
    promotion: {
      version: 1,
      platform: meta.platform,
      deliveryMinHours: meta.deliveryMinHours,
      deliveryMaxHours: Math.max(meta.deliveryMinHours, meta.deliveryMaxHours),
      iconUrl: meta.iconUrl,
      instructionsFa: meta.instructionsFa,
      instructionsEn: meta.instructionsEn,
      supportedObjectives: meta.supportedObjectives,
      requirePartnershipAdCode: meta.requirePartnershipAdCode,
      packages: meta.packages,
    },
  } as Prisma.InputJsonValue;
}

export function promotionMinPriceAfn(meta: PromotionMeta) {
  const prices = meta.packages.filter((pkg) => pkg.enabled).map((pkg) => BigInt(pkg.priceAfn));
  if (!prices.length) return null;
  return prices.reduce((min, price) => price < min ? price : min);
}

export function promotionPublicProduct(service: {
  id: string;
  slug: string;
  titleFa: string;
  titleEn: string;
  descriptionFa: string | null;
  descriptionEn: string | null;
  featured: boolean;
  sortOrder: number;
  metadata: Prisma.JsonValue | null;
}) {
  const meta = parsePromotionMetadata(service.metadata);
  return {
    id: service.id,
    slug: service.slug,
    titleFa: service.titleFa,
    titleEn: service.titleEn,
    descriptionFa: service.descriptionFa,
    descriptionEn: service.descriptionEn,
    featured: service.featured,
    sortOrder: service.sortOrder,
    platform: meta.platform,
    deliveryMinHours: meta.deliveryMinHours,
    deliveryMaxHours: meta.deliveryMaxHours,
    iconUrl: meta.iconUrl || null,
    instructionsFa: meta.instructionsFa || null,
    instructionsEn: meta.instructionsEn || null,
    supportedObjectives: meta.supportedObjectives,
    requirePartnershipAdCode: meta.requirePartnershipAdCode,
    minPriceAfn: promotionMinPriceAfn(meta)?.toString() ?? null,
    packages: meta.packages.filter((pkg) => pkg.enabled),
  };
}
