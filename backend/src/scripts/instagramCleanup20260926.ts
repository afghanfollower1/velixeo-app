import 'dotenv/config';
import { Prisma, PrismaClient, ServiceCategory, UserRole } from '@prisma/client';

const prisma = new PrismaClient();
const MARKER_KEY = 'migration.instagram-cleanup.2026-09-26.v1';

type J = Record<string, unknown>;

function obj(value: Prisma.JsonValue | null | undefined): J {
  return value && typeof value === 'object' && !Array.isArray(value) ? value as J : {};
}

function categoryKey(slug: string) {
  return 'social.category.' + slug;
}

async function audit(summary: string, metadata: Prisma.InputJsonValue) {
  const admin = await prisma.user.findFirst({
    where: { role: UserRole.ADMIN },
    orderBy: { createdAt: 'asc' },
    select: { id: true },
  });
  if (!admin) return;
  await prisma.adminAuditLog.create({
    data: {
      adminUserId: admin.id,
      action: 'CONFIRMED_INSTAGRAM_CLEANUP_20260926',
      entityType: 'SocialCatalog',
      entityId: null,
      summary,
      metadata,
    },
  });
}

async function returnCategoryToProvider(slug: string, reason: string) {
  const services = await prisma.service.findMany({
    where: { category: ServiceCategory.SOCIAL, socialGroup: slug },
    select: { id: true, metadata: true },
  });

  for (const service of services) {
    const metadata = obj(service.metadata);
    await prisma.service.update({
      where: { id: service.id },
      data: {
        enabled: false,
        basePriceAfn: null,
        socialPlatform: null,
        socialGroup: null,
        metadata: {
          ...metadata,
          rawCatalog: true,
          addedToVelixeo: false,
          pricingMode: 'AUTO_MARKUP',
          categorySlug: null,
          removedFromVelixeoAt: new Date().toISOString(),
          removedFromVelixeoReason: reason,
          managedByChatGPT: true,
        } as Prisma.InputJsonValue,
      },
    });
  }

  await prisma.systemSetting.deleteMany({
    where: { key: categoryKey(slug) },
  });

  return services.length;
}

async function updateCategory(
  slug: string,
  patch: { titleFa?: string; titleEn?: string; descriptionFa?: string; descriptionEn?: string },
) {
  const key = categoryKey(slug);
  const row = await prisma.systemSetting.findUnique({ where: { key } });
  if (!row) throw new Error('CATEGORY_NOT_FOUND:' + slug);
  const value = obj(row.value);
  const next = {
    ...value,
    ...(patch.titleFa !== undefined ? { titleFa: patch.titleFa } : {}),
    ...(patch.titleEn !== undefined ? { titleEn: patch.titleEn } : {}),
    ...(patch.descriptionFa !== undefined ? { descriptionFa: patch.descriptionFa } : {}),
    ...(patch.descriptionEn !== undefined ? { descriptionEn: patch.descriptionEn } : {}),
  };
  await prisma.systemSetting.update({
    where: { key },
    data: { value: next as Prisma.InputJsonValue },
  });
}

function suffixFromTitle(title: string) {
  const index = title.indexOf('[');
  return index >= 0 ? ' ' + title.slice(index).trim() : '';
}

async function main() {
  const existingMarker = await prisma.systemSetting.findUnique({ where: { key: MARKER_KEY } });
  if (existingMarker) {
    console.log(JSON.stringify({ migration: MARKER_KEY, skipped: true, reason: 'already_applied' }));
    return;
  }

  const report: J = {
    migration: MARKER_KEY,
    deletedCategories: {},
    mentionsMoved: 0,
    otherCategoryDeleted: false,
    storyServicesRenamed: 0,
    categoryGuidesUpdated: [],
  };

  const backlinksReturned = await returnCategoryToProvider('instagram-backlinks', 'ADMIN_CONFIRMED_INSTAGRAM_BACKLINKS_REMOVAL');
  const growthReturned = await returnCategoryToProvider('instagram-growth-packages', 'ADMIN_CONFIRMED_INSTAGRAM_GROWTH_PACKAGES_REMOVAL');
  report.deletedCategories = {
    'instagram-backlinks': backlinksReturned,
    'instagram-growth-packages': growthReturned,
  };

  const otherServices = await prisma.service.findMany({
    where: {
      category: ServiceCategory.SOCIAL,
      socialGroup: 'instagram-other',
    },
    include: {
      routes: {
        select: { providerName: true, providerServiceCode: true },
      },
    },
  });

  let mentionsMoved = 0;
  for (const service of otherServices) {
    const routeText = service.routes.map(route => route.providerName || '').join(' ');
    const looksLikeMention = /instagram\s+mentions?/i.test(service.titleEn || '')
      || /منشن\s+اینستاگرام/i.test(service.titleFa || '')
      || /instagram\s+mentions?/i.test(routeText);
    if (!looksLikeMention) continue;
    const metadata = obj(service.metadata);
    await prisma.service.update({
      where: { id: service.id },
      data: {
        socialPlatform: 'INSTAGRAM',
        socialGroup: 'instagram-mentions',
        metadata: {
          ...metadata,
          rawCatalog: false,
          addedToVelixeo: true,
          categorySlug: 'instagram-mentions',
          managedByChatGPT: true,
        } as Prisma.InputJsonValue,
      },
    });
    mentionsMoved += 1;
  }
  report.mentionsMoved = mentionsMoved;

  const remainingOther = await prisma.service.count({
    where: {
      category: ServiceCategory.SOCIAL,
      socialGroup: 'instagram-other',
    },
  });
  if (remainingOther === 0) {
    await prisma.systemSetting.deleteMany({
      where: { key: categoryKey('instagram-other') },
    });
    report.otherCategoryDeleted = true;
  } else {
    report.otherCategoryRemainingServices = remainingOther;
  }

  const storyGuideFa = 'این بخش برای افزایش ریچ و تعامل روی استوری اینستاگرام است؛ مانند بازدید پروفایل از استوری، کلیک روی لینک، کلیک روی تگ، سوایپ آپ و ترند استوری در سرویس‌هایی که این قابلیت را دارند. سرویس را دقیق بر اساس کاری که می‌خواهید انتخاب کنید و همان لینک استوری یا محتوایی را وارد کنید که فرم سفارش درخواست می‌کند. قبل از ثبت سفارش، حداقل و حداکثر، زمان شروع و نوع تعامل را بررسی کنید. این سرویس‌ها برای ایجاد تعامل روی استوری هستند و به معنی تضمین رشد فالوور یا فروش نیستند.';
  const storyGuideEn = 'Use this section for Instagram Story reach and engagement actions such as profile visits from a Story, link clicks, tag clicks, swipe-up actions, and Story trend services where supported. Choose the service that matches the exact action you want and enter the precise Story or content link requested by the order form. Check the minimum, maximum, start time, and action type before ordering. These are Story interaction services and do not guarantee follower growth or sales.';

  const mentionsGuideFa = 'این بخش برای منشن‌کردن حساب‌ها در اینستاگرام است. در سرویس‌های «فهرست دلخواه»، لینک پست یا محتوای هدف را دقیق وارد کنید و اگر فرم فهرست نام کاربری می‌خواهد، هر نام کاربری را جداگانه و دقیق مطابق فرم وارد کنید. در سرویس‌های مربوط به هشتگ، هشتگ یا هشتگ‌های موردنظر را دقیق بنویسید. بهتر است نام‌های کاربری معتبر باشند و حساب یا محتوای هدف در زمان اجرای سفارش قابل دسترس باشد.';
  const mentionsGuideEn = 'Use this section for Instagram mentions. For Custom List services, enter the exact target post or content link and, when the form asks for a username list, provide each username exactly as requested. For hashtag-based services, enter the required hashtag or hashtags precisely. Usernames should be valid and the target account/content should remain accessible while the order is being processed.';

  const channelMembersGuideFa = 'این بخش برای افزایش اعضای کانال اینستاگرام است. لینک دقیق کانال را مطابق فیلد سفارش وارد کنید و اگر سرویس کشور یا نوع مخاطب مشخصی دارد، گزینه مناسب را انتخاب کنید. پیش از سفارش، حداقل و حداکثر تعداد، زمان شروع، سرعت و وضعیت جبران ریزش همان سرویس را بررسی کنید. در زمان اجرای سفارش، کانال و لینک آن باید قابل دسترس باشد.';
  const channelMembersGuideEn = 'Use this section to add members to an Instagram channel. Enter the exact channel link requested by the order form and choose the correct country or audience targeting when a service provides it. Before ordering, check the service minimum and maximum, start time, speed, and refill status. Keep the channel and its link accessible while the order is running.';

  const channelCommentsGuideFa = 'این بخش برای افزودن کامنت به محتوای کانال اینستاگرام است. لینک دقیق پست یا محتوای کانال را وارد کنید. اگر فرم متن کامنت، نام کاربری یا ورودی دیگری خواست، همان اطلاعات را دقیق در فیلد مربوط وارد کنید. پیش از ثبت سفارش، نوع کامنت، تعداد قابل سفارش و زمان شروع سرویس را بررسی کنید.';
  const channelCommentsGuideEn = 'Use this section to add comments to Instagram channel content. Enter the exact channel post or content link. If the order form asks for comment text, usernames, or another input, provide it exactly in the matching field. Check the comment type, supported quantity, and start time before placing the order.';

  const refillGuideFa = 'این بخش مربوط به فالوورهای اینستاگرام دارای جبران ریزش است. لینک دقیق پروفایل هدف را وارد کنید و تعداد را داخل حداقل و حداکثر همان سرویس انتخاب کنید. زمان شروع و سرعت سرویس را قبل از سفارش بررسی کنید. اگر بعد از تکمیل سفارش ریزش واجد شرایط رخ دهد، جبران فقط در بازه جبران اعلام‌شده برای همان سرویس قابل درخواست است؛ سرویس‌هایی که بازه یا شرایط متفاوت دارند مطابق مشخصات خودشان عمل می‌کنند.';
  const refillGuideEn = 'These Instagram follower services include refill support. Enter the exact target profile link and choose a quantity within that service’s minimum and maximum. Check the start time and delivery speed before ordering. If an eligible drop occurs after completion, refill is available only during the refill window stated for that specific service and remains subject to that service’s own refill conditions.';

  const noRefillGuideFa = 'این بخش مربوط به فالوورهای اینستاگرام بدون ضمانت جبران ریزش است. لینک دقیق پروفایل هدف را وارد کنید، تعداد را داخل حداقل و حداکثر سرویس انتخاب کنید و زمان شروع و سرعت را قبل از سفارش بررسی کنید. در این گروه، اگر پس از تکمیل سفارش ریزش رخ دهد، جبران رایگان شامل سفارش نمی‌شود؛ بنابراین قبل از ثبت سفارش مشخصات سرویس را با دقت بخوانید.';
  const noRefillGuideEn = 'These Instagram follower services do not include free refill coverage. Enter the exact target profile link, choose a quantity within the service minimum and maximum, and check the start time and speed before ordering. If followers drop after completion, a free refill is not included for this category, so review the service details carefully before placing the order.';

  await updateCategory('instagram-story-actions', {
    titleFa: 'ریچ و تعامل استوری اینستاگرام',
    titleEn: 'Instagram Story Reach & Engagement',
    descriptionFa: storyGuideFa,
    descriptionEn: storyGuideEn,
  });
  report.categoryGuidesUpdated = ['instagram-story-actions'];

  const guideUpdates = [
    ['instagram-mentions', mentionsGuideFa, mentionsGuideEn],
    ['instagram-channel-members', channelMembersGuideFa, channelMembersGuideEn],
    ['instagram-channel-comments', channelCommentsGuideFa, channelCommentsGuideEn],
    ['1', refillGuideFa, refillGuideEn],
    ['2', noRefillGuideFa, noRefillGuideEn],
  ] as const;

  for (const [slug, descriptionFa, descriptionEn] of guideUpdates) {
    const exists = await prisma.systemSetting.findUnique({ where: { key: categoryKey(slug) } });
    if (!exists) {
      console.log(JSON.stringify({ warning: 'category_missing_for_guide', slug }));
      continue;
    }
    await updateCategory(slug, { descriptionFa, descriptionEn });
    (report.categoryGuidesUpdated as string[]).push(slug);
  }

  const storyTitleMap: Record<string, { fa: string; en: string }> = {
    '3274': { fa: 'سوایپ آپ استوری اینستاگرام', en: 'Instagram Story Swipe Up' },
    '3275': { fa: 'بازدید پروفایل از استوری اینستاگرام', en: 'Instagram Story Profile Visits' },
    '3429': { fa: 'بازدید پروفایل از استوری اینستاگرام', en: 'Instagram Story Profile Visits' },
    '3745': { fa: 'ترند استوری اینستاگرام', en: 'Instagram Story Trend' },
    '6596': { fa: 'کلیک لینک استیکر استوری اینستاگرام', en: 'Instagram Story Sticker Link Clicks' },
    '7577': { fa: 'کلیک تگ استوری اینستاگرام', en: 'Instagram Story Tag Clicks' },
    '8465': { fa: 'کلیک لینک استوری اینستاگرام', en: 'Instagram Story Link Clicks' },
  };

  const storyServices = await prisma.service.findMany({
    where: {
      category: ServiceCategory.SOCIAL,
      socialGroup: 'instagram-story-actions',
    },
    include: {
      routes: {
        select: { providerServiceCode: true },
      },
    },
  });

  let storyServicesRenamed = 0;
  const storyRenamed: J[] = [];
  for (const service of storyServices) {
    const code = service.routes.map(route => route.providerServiceCode).find(value => storyTitleMap[value]);
    if (!code) continue;
    const mapped = storyTitleMap[code];
    const nextFa = mapped.fa + suffixFromTitle(service.titleFa || '');
    const nextEn = mapped.en + suffixFromTitle(service.titleEn || '');
    if (nextFa === service.titleFa && nextEn === service.titleEn) continue;
    await prisma.service.update({
      where: { id: service.id },
      data: {
        titleFa: nextFa,
        titleEn: nextEn,
      },
    });
    storyServicesRenamed += 1;
    storyRenamed.push({ serviceId: service.id, providerServiceCode: code, titleFa: nextFa, titleEn: nextEn });
  }
  report.storyServicesRenamed = storyServicesRenamed;
  report.storyRenamed = storyRenamed;

  await prisma.systemSetting.upsert({
    where: { key: MARKER_KEY },
    create: {
      key: MARKER_KEY,
      category: 'migration',
      description: 'Confirmed Instagram social catalog cleanup 2026-09-26.',
      value: {
        appliedAt: new Date().toISOString(),
        report,
      } as Prisma.InputJsonValue,
    },
    update: {
      value: {
        appliedAt: new Date().toISOString(),
        report,
      } as Prisma.InputJsonValue,
    },
  });

  await audit(
    'Applied administrator-confirmed Instagram category cleanup, mention move, Story naming cleanup, and guide updates.',
    report as Prisma.InputJsonValue,
  );

  console.log(JSON.stringify({ ok: true, ...report }));
}

main()
  .catch(error => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
