from pathlib import Path
import re
import subprocess


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def regex_once(path: str, pattern: str, replacement: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count == 0:
        raise RuntimeError(f'Regex anchor not found in {path}: {pattern[:120]!r}')
    p.write_text(updated, encoding='utf-8')


# 1) Register the new modular Social Admin and the automatic provider sync scheduler.
replace_once(
    'backend/src/index.ts',
    "import { registerSocialRoutes } from './socialRoutes.js';\nimport { registerVirtualNumberRoutes } from './virtualNumberRoutes.js';",
    "import { registerSocialRoutes } from './socialRoutes.js';\nimport { registerSocialAdminV2 } from './socialAdminV2.js';\nimport { startSocialAutoSync } from './socialSync.js';\nimport { registerVirtualNumberRoutes } from './virtualNumberRoutes.js';",
)
replace_once(
    'backend/src/index.ts',
    "registerSocialRoutes(app, prisma, authenticate, adminWebUser);\nregisterVirtualNumberRoutes(app, prisma, authenticate, adminWebUser);",
    "registerSocialRoutes(app, prisma, authenticate, adminWebUser);\nregisterSocialAdminV2(app, prisma, adminWebUser);\nregisterVirtualNumberRoutes(app, prisma, authenticate, adminWebUser);\nstartSocialAutoSync(prisma, app.log as any);",
)

# 2) Main Admin navigation: Social now opens its own module. The generic provider page
# remains available by direct URL for legacy/admin recovery, but is removed from the main menu.
replace_once(
    'backend/src/adminExtended.ts',
    "    ['/admin/services', 'خدمات و قیمت‌ها', 'services'],\n    ['/admin/providers', 'Provider و API', 'providers'],\n    ['/admin/social-services', 'پنل شبکه‌های اجتماعی', 'social'],\n    ['/admin/virtual-numbers', 'شماره مجازی و SMS', 'virtual'],",
    "    ['/admin/services', 'خدمات', 'services'],\n    ['/admin/social', 'شبکه‌های اجتماعی', 'social'],\n    ['/admin/virtual-numbers', 'شماره مجازی و SMS', 'virtual'],",
)

# 3) Send Admin-created category definitions to the app catalog. Existing clients ignore
# the extra field safely, while the upgraded client uses localized labels/sort order.
replace_once(
    'backend/src/socialRoutes.ts',
    "    return { baseCurrency: 'AFN', services: rows };",
    "    const categorySettings = await prisma.systemSetting.findMany({\n      where: { category: 'social-category' },\n      orderBy: { key: 'asc' },\n    });\n    const categories = categorySettings.flatMap((setting) => {\n      const value = setting.value;\n      if (!value || typeof value !== 'object' || Array.isArray(value)) return [];\n      const item = value as Record<string, unknown>;\n      const slug = typeof item.slug === 'string'\n        ? item.slug\n        : setting.key.replace(/^social\\.category\\./, '');\n      if (!slug || item.enabled === false) return [];\n      return [{\n        slug,\n        titleFa: typeof item.titleFa === 'string' ? item.titleFa : slug,\n        titleEn: typeof item.titleEn === 'string' ? item.titleEn : slug,\n        platform: typeof item.platform === 'string' ? item.platform : 'OTHER',\n        descriptionFa: typeof item.descriptionFa === 'string' ? item.descriptionFa : null,\n        descriptionEn: typeof item.descriptionEn === 'string' ? item.descriptionEn : null,\n        sortOrder: Number.isFinite(Number(item.sortOrder)) ? Number(item.sortOrder) : 100,\n      }];\n    }).sort((a, b) => a.sortOrder - b.sortOrder);\n    return { baseCurrency: 'AFN', categories, services: rows };",
)

# 4) Upgrade Flutter catalog model so categories are fully server-driven.
regex_once(
    'lib/social/social_models.dart',
    r"class SocialCatalog \{.*?\n\}\n\nclass SocialQuote",
    """class SocialCategory {\n  const SocialCategory({\n    required this.slug,\n    required this.titleFa,\n    required this.titleEn,\n    required this.platform,\n    required this.sortOrder,\n    this.descriptionFa,\n    this.descriptionEn,\n  });\n\n  final String slug;\n  final String titleFa;\n  final String titleEn;\n  final String platform;\n  final int sortOrder;\n  final String? descriptionFa;\n  final String? descriptionEn;\n\n  factory SocialCategory.fromJson(Map<String, dynamic> json) => SocialCategory(\n        slug: (json['slug'] as String?) ?? '',\n        titleFa: (json['titleFa'] as String?) ?? (json['slug'] as String? ?? ''),\n        titleEn: (json['titleEn'] as String?) ?? (json['slug'] as String? ?? ''),\n        platform: (json['platform'] as String?) ?? 'OTHER',\n        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 100,\n        descriptionFa: json['descriptionFa'] as String?,\n        descriptionEn: json['descriptionEn'] as String?,\n      );\n}\n\nclass SocialCatalog {\n  const SocialCatalog({this.services = const [], this.categories = const []});\n  final List<SocialService> services;\n  final List<SocialCategory> categories;\n\n  factory SocialCatalog.fromJson(Map<String, dynamic> json) => SocialCatalog(\n        services: ((json['services'] as List<dynamic>?) ?? const [])\n            .map((item) => SocialService.fromJson(Map<String, dynamic>.from(item as Map)))\n            .toList(growable: false),\n        categories: ((json['categories'] as List<dynamic>?) ?? const [])\n            .map((item) => SocialCategory.fromJson(Map<String, dynamic>.from(item as Map)))\n            .where((item) => item.slug.isNotEmpty)\n            .toList(growable: false),\n      );\n}\n\nclass SocialQuote""",
)

# 5) Category ordering/labels in the app now come from Admin. Unknown/new categories and
# networks still work without another APK update because services remain server-driven.
regex_once(
    'lib/social/social_panel.dart',
    r"  List<String> get availableGroups \{.*?\n  \}\n\n  List<SocialService> get visibleServices",
    """  List<String> get availableGroups {\n    final values = catalog.services\n        .where((e) => selectedPlatform == null || e.platform == selectedPlatform)\n        .map((e) => e.group)\n        .toSet()\n        .toList();\n    final serverOrder = <String, int>{\n      for (final category in catalog.categories)\n        if (selectedPlatform == null || category.platform == selectedPlatform)\n          category.slug: category.sortOrder,\n    };\n    const preferred = ['FOLLOWERS','LIKES','VIEWS','COMMENTS','SHARES','SAVES','REACH','POLL','TRAFFIC','OTHER'];\n    values.sort((a, b) {\n      final sa = serverOrder[a];\n      final sb = serverOrder[b];\n      if (sa != null || sb != null) {\n        return (sa ?? 999999).compareTo(sb ?? 999999);\n      }\n      final ia = preferred.indexOf(a);\n      final ib = preferred.indexOf(b);\n      return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);\n    });\n    return values;\n  }\n\n  List<SocialService> get visibleServices""",
)
replace_once(
    'lib/social/social_panel.dart',
    "  String groupLabel(String group) {\n    const faLabels = {",
    "  String groupLabel(String group) {\n    for (final category in catalog.categories) {\n      if (category.slug == group) {\n        return fa ? category.titleFa : category.titleEn;\n      }\n    }\n    const faLabels = {",
)

# Stage every file touched by this migration, including the two new implementation files.
subprocess.run([
    'git', 'add',
    'backend/src/index.ts',
    'backend/src/adminExtended.ts',
    'backend/src/socialRoutes.ts',
    'backend/src/socialSync.ts',
    'backend/src/socialAdminV2.ts',
    'lib/social/social_models.dart',
    'lib/social/social_panel.dart',
], check=True)

print('Modular Social Admin, live categories and automatic price synchronization applied.')
