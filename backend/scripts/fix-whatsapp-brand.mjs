import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const legacyBrandKey = 'social.brand.1';
const duplicateBrandKey = 'social.brand.whatsapp';
const categoryKeys = [
  'social.category.whatsapp-channel-members',
  'social.category.whatsapp-channel-reactions',
];
const groups = ['whatsapp-channel-members', 'whatsapp-channel-reactions'];

const asObject = (value) =>
  value && typeof value === 'object' && !Array.isArray(value) ? value : {};

try {
  const before = await prisma.$transaction(async (tx) => {
    const [legacyBrand, duplicateBrand, categories, memberCount, reactionCount, duplicateServiceCount] =
      await Promise.all([
        tx.systemSetting.findUnique({ where: { key: legacyBrandKey } }),
        tx.systemSetting.findUnique({ where: { key: duplicateBrandKey } }),
        tx.systemSetting.findMany({ where: { key: { in: categoryKeys } } }),
        tx.service.count({ where: { category: 'SOCIAL', socialGroup: 'whatsapp-channel-members' } }),
        tx.service.count({ where: { category: 'SOCIAL', socialGroup: 'whatsapp-channel-reactions' } }),
        tx.service.count({
          where: {
            category: 'SOCIAL',
            socialGroup: { in: groups },
            socialPlatform: 'WHATSAPP',
          },
        }),
      ]);

    if (!legacyBrand) {
      throw new Error('LEGACY_WHATSAPP_BRAND_NOT_FOUND');
    }

    if (categories.length !== categoryKeys.length) {
      throw new Error('WHATSAPP_CATEGORY_SETTINGS_MISSING');
    }

    for (const category of categories) {
      const value = asObject(category.value);
      await tx.systemSetting.update({
        where: { key: category.key },
        data: { value: { ...value, platform: '1' } },
      });
    }

    const moved = await tx.service.updateMany({
      where: {
        category: 'SOCIAL',
        socialGroup: { in: groups },
        socialPlatform: 'WHATSAPP',
      },
      data: { socialPlatform: '1' },
    });

    let duplicateDeleted = false;
    if (duplicateBrand) {
      await tx.systemSetting.delete({ where: { key: duplicateBrandKey } });
      duplicateDeleted = true;
    }

    return {
      legacyBrandExists: true,
      duplicateBrandExisted: Boolean(duplicateBrand),
      duplicateBrandDeleted: duplicateDeleted,
      categoryCount: categories.length,
      memberCount,
      reactionCount,
      duplicateServiceCount,
      movedServiceCount: moved.count,
    };
  });

  const [legacyBrandAfter, duplicateBrandAfter, categoriesAfter, memberPlatform1, reactionPlatform1, remainingDuplicate] =
    await Promise.all([
      prisma.systemSetting.findUnique({ where: { key: legacyBrandKey } }),
      prisma.systemSetting.findUnique({ where: { key: duplicateBrandKey } }),
      prisma.systemSetting.findMany({ where: { key: { in: categoryKeys } } }),
      prisma.service.count({
        where: {
          category: 'SOCIAL',
          socialGroup: 'whatsapp-channel-members',
          socialPlatform: '1',
        },
      }),
      prisma.service.count({
        where: {
          category: 'SOCIAL',
          socialGroup: 'whatsapp-channel-reactions',
          socialPlatform: '1',
        },
      }),
      prisma.service.count({
        where: {
          category: 'SOCIAL',
          socialGroup: { in: groups },
          socialPlatform: 'WHATSAPP',
        },
      }),
    ]);

  const platforms = categoriesAfter.map((row) => ({
    key: row.key,
    platform: asObject(row.value).platform,
  }));

  console.log(
    JSON.stringify({
      ok: true,
      before,
      after: {
        legacyBrandExists: Boolean(legacyBrandAfter),
        duplicateBrandExists: Boolean(duplicateBrandAfter),
        categoryPlatforms: platforms,
        memberPlatform1,
        reactionPlatform1,
        remainingDuplicate,
      },
    }),
  );

  if (
    !legacyBrandAfter ||
    duplicateBrandAfter ||
    remainingDuplicate !== 0 ||
    platforms.some((row) => row.platform !== '1')
  ) {
    throw new Error('WHATSAPP_BRAND_FIX_VERIFICATION_FAILED');
  }
} finally {
  await prisma.$disconnect();
}
