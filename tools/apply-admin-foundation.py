from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Missing anchor: {label}")
    return text.replace(old, new, 1)


index_path = Path('backend/src/index.ts')
text = index_path.read_text()

text = replace_once(
    text,
    "  UserRole,\n  WalletEntryType,",
    "  UserRole,\n  UserStatus,\n  WalletEntryType,",
    'UserStatus import',
)
text = replace_once(
    text,
    "import { adminDashboardHtml, adminLoginHtml } from './adminPage.js';",
    "import { adminDashboardHtml, adminLoginHtml } from './adminPage.js';\nimport { registerExtendedAdminRoutes } from './adminExtended.js';\nimport { registerClientFoundationRoutes } from './clientFoundationRoutes.js';",
    'extended imports',
)

text = replace_once(
    text,
    "async function authenticate(request: FastifyRequest, reply: FastifyReply) {\n  try {\n    await request.jwtVerify();\n  } catch {\n    return reply.code(401).send({ error: 'unauthorized' });\n  }\n}",
    "async function authenticate(request: FastifyRequest, reply: FastifyReply) {\n  try {\n    await request.jwtVerify();\n  } catch {\n    return reply.code(401).send({ error: 'unauthorized' });\n  }\n  const claims = request.user as JwtClaims;\n  const account = await prisma.user.findUnique({\n    where: { id: claims.sub },\n    select: { status: true },\n  });\n  if (!account) return reply.code(401).send({ error: 'unauthorized' });\n  if (account.status !== UserStatus.ACTIVE) {\n    return reply.code(403).send({ error: 'account_suspended' });\n  }\n}",
    'authenticate status guard',
)

text = replace_once(
    text,
    "  role: UserRole;\n  locale: AppLocale;",
    "  role: UserRole;\n  status: UserStatus;\n  locale: AppLocale;",
    'public user status type',
)
text = replace_once(
    text,
    "    role: user.role,\n    locale: user.locale,",
    "    role: user.role,\n    status: user.status,\n    locale: user.locale,",
    'public user status value',
)

text = replace_once(
    text,
    "    return prisma.user.findFirst({\n      where: { id: claims.sub, role: UserRole.ADMIN },",
    "    return prisma.user.findFirst({\n      where: { id: claims.sub, role: UserRole.ADMIN, status: UserStatus.ACTIVE },",
    'admin web active guard',
)

login_anchor = "  if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {\n    return reply.code(401).send({ error: 'invalid_credentials' });\n  }\n\n  const session = await createSession(user);"
login_new = "  if (!user || !user.passwordHash || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {\n    return reply.code(401).send({ error: 'invalid_credentials' });\n  }\n  if (user.status !== UserStatus.ACTIVE) {\n    return reply.code(403).send({ error: 'account_suspended' });\n  }\n\n  const session = await createSession(user);"
text = replace_once(text, login_anchor, login_new, 'login suspended guard')

google_anchor = "    const session = await createSession(user);\n    return { user: publicUser(user), ...session };\n  } catch (error) {\n    request.log.warn({ error }, 'google token verification failed');"
google_new = "    if (user.status !== UserStatus.ACTIVE) {\n      return reply.code(403).send({ error: 'account_suspended' });\n    }\n    const session = await createSession(user);\n    return { user: publicUser(user), ...session };\n  } catch (error) {\n    request.log.warn({ error }, 'google token verification failed');"
text = replace_once(text, google_anchor, google_new, 'google suspended guard')

refresh_anchor = "  if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) {\n    return reply.code(401).send({ error: 'invalid_refresh_token' });\n  }\n\n  const nextRefreshToken = newRefreshToken();"
refresh_new = "  if (!stored || stored.revokedAt || stored.expiresAt <= new Date()) {\n    return reply.code(401).send({ error: 'invalid_refresh_token' });\n  }\n  if (stored.user.status !== UserStatus.ACTIVE) {\n    return reply.code(403).send({ error: 'account_suspended' });\n  }\n\n  const nextRefreshToken = newRefreshToken();"
text = replace_once(text, refresh_anchor, refresh_new, 'refresh suspended guard')

wallet_web_anchor = "    await applyWalletDelta({\n      userId: parsed.data.userId,"
wallet_web_new = "    const entry = await applyWalletDelta({\n      userId: parsed.data.userId,"
text = replace_once(text, wallet_web_anchor, wallet_web_new, 'web wallet entry capture')
wallet_web_return = "    return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=wallet_updated`);"
wallet_web_audit = "    await prisma.adminAuditLog.create({\n      data: {\n        adminUserId: admin.id,\n        action: 'WALLET_MANUAL_ADJUST',\n        entityType: 'WalletEntry',\n        entityId: entry.id,\n        summary: `${parsed.data.amountAfn} AFN — ${parsed.data.reason}`,\n        metadata: { userId: parsed.data.userId },\n      },\n    });\n    return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=wallet_updated`);"
text = replace_once(text, wallet_web_return, wallet_web_audit, 'web wallet audit')

rate_web_return = "  return reply.code(303).redirect('/admin?view=rates&msg=rate_updated');"
rate_web_audit = "  await prisma.adminAuditLog.create({\n    data: {\n      adminUserId: admin.id,\n      action: 'EXCHANGE_RATE_UPDATE',\n      entityType: 'ExchangeRate',\n      entityId: parsed.data.code,\n      summary: `${parsed.data.code} = ${parsed.data.afnPerUnit} AFN`,\n    },\n  });\n  return reply.code(303).redirect('/admin?view=rates&msg=rate_updated');"
text = replace_once(text, rate_web_return, rate_web_audit, 'web rate audit')

register_anchor = "app.setErrorHandler((error: unknown, request, reply) => {"
register_new = "registerExtendedAdminRoutes(app, prisma, adminWebUser);\nregisterClientFoundationRoutes(app, prisma, authenticate);\n\napp.setErrorHandler((error: unknown, request, reply) => {"
text = replace_once(text, register_anchor, register_new, 'route registration')

index_path.write_text(text)

admin_path = Path('backend/src/adminPage.ts')
admin_text = admin_path.read_text()
nav_anchor = "${nav('dashboard','داشبورد')}${nav('users','کاربران')}${nav('rates','نرخ ارز')}${nav('providers','API و Providerها')}<form class=\"inline-form\" method=\"post\" action=\"/admin/logout\">"
nav_new = "${nav('dashboard','داشبورد')}${nav('users','کاربران')}${nav('rates','نرخ ارز')}<a href=\"/admin/overview\">نمای کلی کامل</a><a href=\"/admin/services\">خدمات و قیمت‌ها</a><a href=\"/admin/providers\">Provider و API</a><a href=\"/admin/orders\">سفارش‌ها</a><a href=\"/admin/payments\">پرداخت‌ها</a><a href=\"/admin/banners\">بنرها</a><a href=\"/admin/coupons\">کد تخفیف</a><a href=\"/admin/notifications\">اعلان‌ها</a><a href=\"/admin/support\">پشتیبانی</a><a href=\"/admin/settings\">تنظیمات</a><a href=\"/admin/audit\">Audit Log</a><form class=\"inline-form\" method=\"post\" action=\"/admin/logout\">"
admin_text = replace_once(admin_text, nav_anchor, nav_new, 'admin navigation')
admin_path.write_text(admin_text)
