import type { Prisma } from '@prisma/client';

export type PremiumDeliveryType = 'MANUAL_ACTIVATION' | 'MANUAL_DELIVERY' | 'CUSTOM_REQUEST';
export type PremiumGroup = 'MESSAGING' | 'SOCIAL' | 'VPN' | 'STREAMING' | 'AI' | 'OTHER';
export type PremiumFieldType = 'TEXT' | 'USERNAME' | 'PHONE' | 'EMAIL' | 'SELECT' | 'TEXTAREA';

export type PremiumPackage = {
  id: string;
  titleFa: string;
  titleEn: string;
  durationFa: string;
  durationEn: string;
  priceAfn: string;
  enabled: boolean;
  sortOrder: number;
  stock: number | null;
  badgeFa: string;
  badgeEn: string;
};

export type PremiumFormField = {
  key: string;
  type: PremiumFieldType;
  labelFa: string;
  labelEn: string;
  placeholderFa: string;
  placeholderEn: string;
  required: boolean;
  options: string[];
};

export type PremiumProductMeta = {
  version: 1;
  group: PremiumGroup;
  deliveryType: PremiumDeliveryType;
  deliveryMinHours: number;
  deliveryMaxHours: number;
  iconUrl: string;
  instructionsFa: string;
  instructionsEn: string;
  packages: PremiumPackage[];
  formFields: PremiumFormField[];
};

const deliveryTypes = new Set<PremiumDeliveryType>([
  'MANUAL_ACTIVATION',
  'MANUAL_DELIVERY',
  'CUSTOM_REQUEST',
]);
const groups = new Set<PremiumGroup>([
  'MESSAGING',
  'SOCIAL',
  'VPN',
  'STREAMING',
  'AI',
  'OTHER',
]);
const fieldTypes = new Set<PremiumFieldType>([
  'TEXT',
  'USERNAME',
  'PHONE',
  'EMAIL',
  'SELECT',
  'TEXTAREA',
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

export function parsePremiumMetadata(value: Prisma.JsonValue | unknown): PremiumProductMeta {
  const root = obj(value);
  const raw = obj(root.premium ?? root);
  const rawPackages = Array.isArray(raw.packages) ? raw.packages : [];
  const rawFields = Array.isArray(raw.formFields) ? raw.formFields : [];

  const packages = rawPackages
    .map((item, index): PremiumPackage | null => {
      const row = obj(item);
      const id = key(row.id, `package-${index + 1}`);
      const price = str(row.priceAfn);
      if (!/^\d+$/.test(price) || BigInt(price) <= 0n) return null;
      const rawStock = row.stock;
      let stock: number | null = null;
      if (rawStock !== null && rawStock !== undefined && String(rawStock).trim() !== '') {
        const parsed = Number(rawStock);
        if (Number.isInteger(parsed) && parsed >= 0) stock = parsed;
      }
      return {
        id,
        titleFa: str(row.titleFa, str(row.titleEn, id)),
        titleEn: str(row.titleEn, str(row.titleFa, id)),
        durationFa: str(row.durationFa),
        durationEn: str(row.durationEn),
        priceAfn: price,
        enabled: bool(row.enabled, true),
        sortOrder: int(row.sortOrder, (index + 1) * 10, 1, 1_000_000),
        stock,
        badgeFa: str(row.badgeFa),
        badgeEn: str(row.badgeEn),
      };
    })
    .filter((item): item is PremiumPackage => item !== null)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.titleEn.localeCompare(b.titleEn));

  const formFields = rawFields
    .map((item, index): PremiumFormField | null => {
      const row = obj(item);
      const fieldKey = key(row.key, `field-${index + 1}`);
      const rawType = str(row.type, 'TEXT').toUpperCase() as PremiumFieldType;
      const type = fieldTypes.has(rawType) ? rawType : 'TEXT';
      const options = Array.isArray(row.options)
        ? row.options.map((option) => str(option)).filter(Boolean).slice(0, 50)
        : [];
      return {
        key: fieldKey,
        type,
        labelFa: str(row.labelFa, str(row.labelEn, fieldKey)),
        labelEn: str(row.labelEn, str(row.labelFa, fieldKey)),
        placeholderFa: str(row.placeholderFa),
        placeholderEn: str(row.placeholderEn),
        required: bool(row.required, false),
        options,
      };
    })
    .filter((item): item is PremiumFormField => item !== null)
    .slice(0, 20);

  const rawDeliveryType = str(raw.deliveryType, 'MANUAL_ACTIVATION').toUpperCase() as PremiumDeliveryType;
  const rawGroup = str(raw.group, 'OTHER').toUpperCase() as PremiumGroup;

  return {
    version: 1,
    group: groups.has(rawGroup) ? rawGroup : 'OTHER',
    deliveryType: deliveryTypes.has(rawDeliveryType) ? rawDeliveryType : 'MANUAL_ACTIVATION',
    deliveryMinHours: int(raw.deliveryMinHours, 1, 0, 720),
    deliveryMaxHours: int(raw.deliveryMaxHours, 12, 1, 720),
    iconUrl: str(raw.iconUrl),
    instructionsFa: str(raw.instructionsFa),
    instructionsEn: str(raw.instructionsEn),
    packages,
    formFields,
  };
}

export function premiumMetadataJson(meta: PremiumProductMeta): Prisma.InputJsonValue {
  return {
    premium: {
      version: 1,
      group: meta.group,
      deliveryType: meta.deliveryType,
      deliveryMinHours: meta.deliveryMinHours,
      deliveryMaxHours: Math.max(meta.deliveryMinHours, meta.deliveryMaxHours),
      iconUrl: meta.iconUrl,
      instructionsFa: meta.instructionsFa,
      instructionsEn: meta.instructionsEn,
      packages: meta.packages.map((pkg) => ({
        id: pkg.id,
        titleFa: pkg.titleFa,
        titleEn: pkg.titleEn,
        durationFa: pkg.durationFa,
        durationEn: pkg.durationEn,
        priceAfn: pkg.priceAfn,
        enabled: pkg.enabled,
        sortOrder: pkg.sortOrder,
        stock: pkg.stock,
        badgeFa: pkg.badgeFa,
        badgeEn: pkg.badgeEn,
      })),
      formFields: meta.formFields.map((field) => ({
        key: field.key,
        type: field.type,
        labelFa: field.labelFa,
        labelEn: field.labelEn,
        placeholderFa: field.placeholderFa,
        placeholderEn: field.placeholderEn,
        required: field.required,
        options: field.options,
      })),
    },
  } as Prisma.InputJsonValue;
}

export function premiumMinPriceAfn(meta: PremiumProductMeta) {
  const prices = meta.packages
    .filter((pkg) => pkg.enabled && (pkg.stock == null || pkg.stock > 0))
    .map((pkg) => BigInt(pkg.priceAfn));
  if (!prices.length) return null;
  return prices.reduce((min, price) => price < min ? price : min);
}

export function premiumPublicProduct(service: {
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
  const premium = parsePremiumMetadata(service.metadata);
  return {
    id: service.id,
    slug: service.slug,
    titleFa: service.titleFa,
    titleEn: service.titleEn,
    descriptionFa: service.descriptionFa,
    descriptionEn: service.descriptionEn,
    featured: service.featured,
    sortOrder: service.sortOrder,
    group: premium.group,
    deliveryType: premium.deliveryType,
    deliveryMinHours: premium.deliveryMinHours,
    deliveryMaxHours: premium.deliveryMaxHours,
    iconUrl: premium.iconUrl || null,
    instructionsFa: premium.instructionsFa || null,
    instructionsEn: premium.instructionsEn || null,
    minPriceAfn: premiumMinPriceAfn(premium)?.toString() ?? null,
    packages: premium.packages.filter((pkg) => pkg.enabled),
    formFields: premium.formFields,
  };
}

export function validatePremiumOrderFields(
  fields: PremiumFormField[],
  submitted: Record<string, unknown>,
) {
  const out: Record<string, string> = {};
  for (const field of fields) {
    const value = str(submitted[field.key]).slice(0, field.type === 'TEXTAREA' ? 2000 : 500);
    if (field.required && !value) throw new Error(`required_field:${field.key}`);
    if (!value) continue;
    if (field.type === 'EMAIL' && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) {
      throw new Error(`invalid_email:${field.key}`);
    }
    if (field.type === 'SELECT' && field.options.length && !field.options.includes(value)) {
      throw new Error(`invalid_option:${field.key}`);
    }
    out[field.key] = value;
  }
  return out;
}

export function premiumPackageAvailable(pkg: PremiumPackage) {
  return pkg.enabled && (pkg.stock == null || pkg.stock > 0);
}
