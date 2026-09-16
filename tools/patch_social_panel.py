from pathlib import Path
import subprocess


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:160]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# Disabled custom categories must disappear from the client immediately, without an APK update.
replace_once(
    'backend/src/socialRoutes.ts',
    "    return { baseCurrency: 'AFN', categories, services: rows };",
    "    const configuredCategorySlugs = new Set(categorySettings.flatMap((setting) => {\n      const value = setting.value;\n      if (!value || typeof value !== 'object' || Array.isArray(value)) return [];\n      const item = value as Record<string, unknown>;\n      const slug = typeof item.slug === 'string'\n        ? item.slug\n        : setting.key.replace(/^social\\.category\\./, '');\n      return slug ? [slug] : [];\n    }));\n    const activeCategorySlugs = new Set(categories.map((category) => category.slug));\n    const visibleRows = rows.filter((service) =>\n      !configuredCategorySlugs.has(service.group) || activeCategorySlugs.has(service.group),\n    );\n    return { baseCurrency: 'AFN', categories, services: visibleRows };",
)

# Moving a category to another platform updates all services assigned to that category.
replace_once(
    'backend/src/socialAdminV2.ts',
    "    });\n    await audit(prisma, admin.id, 'SOCIAL_CATEGORY_SAVE', 'SocialCategory', slug, `${platform} → ${titleFa}`);",
    "    });\n    await prisma.service.updateMany({\n      where: { category: ServiceCategory.SOCIAL, socialGroup: slug },\n      data: { socialPlatform: platform },\n    });\n    await audit(prisma, admin.id, 'SOCIAL_CATEGORY_SAVE', 'SocialCategory', slug, `${platform} → ${titleFa}`);",
)

subprocess.run([
    'git', 'add',
    'backend/src/socialRoutes.ts',
    'backend/src/socialAdminV2.ts',
], check=True)

print('Social category visibility and platform propagation applied.')
