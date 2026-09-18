import { Prisma, PrismaClient, ServiceCategory } from '@prisma/client';

export type SocialBrand = {
  key: string;
  titleEn: string;
  titleFa: string;
  iconType: 'DEFAULT' | 'URL' | 'UPLOAD';
  iconValue: string;
  sortOrder: number;
  enabled: boolean;
};

export const defaultBrandIcons = [
  'instagram','facebook','tiktok','youtube','telegram','whatsapp','x','threads',
  'snapchat','linkedin','pinterest','discord','spotify','soundcloud','generic',
] as const;

const jsonObject = (value: Prisma.JsonValue | null | undefined): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};

export function normalizeBrandKey(value: string) {
  return value.trim().toUpperCase().replace(/[^A-Z0-9_]+/g, '_').replace(/^_+|_+$/g, '').slice(0, 60);
}

export function brandSettingKey(key: string) {
  return 'social.brand.' + normalizeBrandKey(key).toLowerCase();
}

export function parseBrand(setting: { key: string; value: Prisma.JsonValue }): SocialBrand | null {
  const row = jsonObject(setting.value);
  const fallback = setting.key.replace(/^social\.brand\./, '').toUpperCase();
  const key = normalizeBrandKey(typeof row.key === 'string' ? row.key : fallback);
  if (!key) return null;
  const rawType = typeof row.iconType === 'string' ? row.iconType.toUpperCase() : 'DEFAULT';
  const iconType: SocialBrand['iconType'] = rawType === 'URL' || rawType === 'UPLOAD' ? rawType : 'DEFAULT';
  return {
    key,
    titleEn: typeof row.titleEn === 'string' ? row.titleEn : key,
    titleFa: typeof row.titleFa === 'string' ? row.titleFa : (typeof row.titleEn === 'string' ? row.titleEn : key),
    iconType,
    iconValue: typeof row.iconValue === 'string' && row.iconValue ? row.iconValue : key.toLowerCase(),
    sortOrder: Number.isFinite(Number(row.sortOrder)) ? Number(row.sortOrder) : 100,
    enabled: row.enabled !== false,
  };
}

export function validateBrandIcon(type: SocialBrand['iconType'], value: string) {
  if (type === 'DEFAULT') {
    const icon = value.trim().toLowerCase();
    return (defaultBrandIcons as readonly string[]).includes(icon) ? icon : 'generic';
  }
  if (type === 'URL') {
    const url = new URL(value);
    if (!['https:','http:'].includes(url.protocol)) throw new Error('Brand icon URL must use http or https.');
    return url.toString();
  }
  if (!/^data:image\/(?:png|jpeg|webp);base64,[A-Za-z0-9+/=]+$/.test(value)) {
    throw new Error('Uploaded brand icon must be PNG, JPG or WebP.');
  }
  if (value.length > 550000) throw new Error('Uploaded brand icon is too large. Keep it below about 400 KB.');
  return value;
}

export async function loadSocialBrands(prisma: PrismaClient): Promise<SocialBrand[]> {
  const rows = await prisma.systemSetting.findMany({
    where: { category: 'social-brand' },
    orderBy: { key: 'asc' },
  });
  const configured = rows.map(parseBrand).filter((item): item is SocialBrand => item !== null);
  const configuredKeys = new Set(configured.map(item => item.key));
  const [categories, services] = await Promise.all([
    prisma.systemSetting.findMany({ where: { category: 'social-category' }, select: { value: true } }),
    prisma.service.findMany({ where: { category: ServiceCategory.SOCIAL }, select: { socialPlatform: true } }),
  ]);
  const inferred = new Set<string>();
  for (const setting of categories) {
    const row = jsonObject(setting.value);
    const key = normalizeBrandKey(typeof row.platform === 'string' ? row.platform : '');
    if (key) inferred.add(key);
  }
  for (const service of services) {
    const key = normalizeBrandKey(service.socialPlatform || '');
    if (key) inferred.add(key);
  }
  for (const key of inferred) {
    if (configuredKeys.has(key)) continue;
    configured.push({
      key,
      titleEn: key.split('_').map(part => part.charAt(0) + part.slice(1).toLowerCase()).join(' '),
      titleFa: key,
      iconType: 'DEFAULT',
      iconValue: key.toLowerCase(),
      sortOrder: 100,
      enabled: true,
    });
  }
  return configured.sort((a,b)=>a.sortOrder-b.sortOrder || a.titleEn.localeCompare(b.titleEn));
}