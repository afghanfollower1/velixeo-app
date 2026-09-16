import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  BannerPlacement,
  CouponDiscountType,
  NotificationAudience,
  OrderStatus,
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
  SupportStatus,
  UserRole,
  UserStatus,
  WalletEntryStatus,
  WalletEntryType,
} from '@prisma/client';
import { randomBytes } from 'node:crypto';
import {
  encryptProviderSecret,
  providerSecretEncryptionConfigured,
} from './providerSecrets.js';

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};

type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;

type AnyBody = Record<string, unknown>;

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const text = (body: AnyBody, key: string) => String(body[key] ?? '').trim();
const checked = (body: AnyBody, key: string) => body[key] === 'on' || body[key] === 'true' || body[key] === '1';
const intValue = (body: AnyBody, key: string, fallback = 0) => {
  const value = Number.parseInt(text(body, key), 10);
  return Number.isFinite(value) ? value : fallback;
};
const decimalValue = (body: AnyBody, key: string, fallback = '0') => {
  const raw = text(body, key);
  return /^-?\d+(\.\d{1,8})?$/.test(raw) ? raw : fallback;
};
const bigIntOrNull = (body: AnyBody, key: string) => {
  const raw = text(body, key);
  if (!raw) return null;
  if (!/^-?\d+$/.test(raw)) throw new Error(`INVALID_${key.toUpperCase()}`);
  return BigInt(raw);
};
const dateOrNull = (body: AnyBody, key: string) => {
  const raw = text(body, key);
  if (!raw) return null;
  const value = new Date(raw);
  if (Number.isNaN(value.getTime())) throw new Error(`INVALID_${key.toUpperCase()}`);
  return value;
};

const faDate = (value: Date | string | null | undefined) => {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('fa-IR');
  } catch {
    return '—';
  }
};

const fmtAfn = (value: bigint | number | string | null | undefined) =>
  `${Number(value ?? 0).toLocaleString('en-US')} AFN`;

const selectOptions = (items: readonly string[], current?: string) =>
  items.map((item) => `<option value="${esc(item)}"${item === current ? ' selected' : ''}>${esc(item)}</option>`).join('');

function adminShell(input: {
  title: string;
  admin: AdminIdentity;
  active: string;
  body: string;
  message?: string;
  error?: boolean;
}) {
  const nav = [
    ['/admin', 'داشبورد', 'dashboard'],
    ['/admin/users-control', 'کاربران', 'users'],
    ['/admin/services', 'خدمات و قیمت‌ها', 'services'],
    ['/admin/providers', 'Provider و API', 'providers'],
    ['/admin/social-services', 'پنل شبکه‌های اجتماعی', 'social'],
    ['/admin/orders', 'سفارش‌ها', 'orders'],
    ['/admin/payments', 'پرداخت‌ها', 'payments'],
    ['/admin/banners', 'بنرها', 'banners'],
    ['/admin/coupons', 'کد تخفیف', 'coupons'],
    ['/admin/notifications', 'اعلان‌ها', 'notifications'],
    ['/admin/support', 'پشتیبانی', 'support'],
    ['/admin/settings', 'تنظیمات سیستم', 'settings'],
    ['/admin/readiness', 'آمادگی سیستم', 'readiness'],
    ['/admin/reports', 'گزارش مالی', 'reports'],
    ['/admin/audit', 'گزارش مدیر', 'audit'],
  ] as const;

  return `<!doctype html><html lang="fa" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(input.title)} — VELIXEO</title><style>
:root{--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;--card:#fff;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#18A875;--bad:#E65454;--warn:#A96812;--nav:#0D2640}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;background:var(--bg);color:var(--text)}a{color:inherit}button,input,select,textarea{font:inherit}.app{display:grid;grid-template-columns:270px minmax(0,1fr);min-height:100vh}.side{background:var(--nav);color:#fff;padding:18px;position:sticky;top:0;height:100vh;overflow:auto}.brand{display:flex;gap:12px;align-items:center;margin-bottom:22px}.logo{width:44px;height:44px;border-radius:14px;background:linear-gradient(145deg,#4DB8FF,#0D78C8);display:grid;place-items:center;font-weight:900;font-size:21px}.brand small{display:block;color:#9fc2db}.nav a,.nav button{display:block;width:100%;border:0;background:transparent;color:#cfe8fa;text-align:right;padding:11px 12px;border-radius:11px;margin:3px 0;cursor:pointer;text-decoration:none}.nav a.active,.nav a:hover,.nav button:hover{background:rgba(49,168,255,.16);color:#fff}.logout{color:#ffced0!important}.main{padding:24px;min-width:0}.top{display:flex;justify-content:space-between;gap:12px;align-items:center;margin-bottom:18px}.top h1{margin:0;font-size:24px}.muted{color:var(--muted);font-size:13px}.chip{font-size:12px;padding:7px 10px;border-radius:999px;background:#eaf6ff;color:var(--p)}.card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px;margin-bottom:16px}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.field{margin-top:12px}.field label{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}.field input,.field select,.field textarea{width:100%;border:1px solid var(--line);border-radius:12px;padding:10px 12px;background:#fff;outline:none}.field input,.field select{height:44px}.field textarea{min-height:90px;resize:vertical}.field input:focus,.field select:focus,.field textarea:focus{border-color:var(--p);box-shadow:0 0 0 3px rgba(13,120,200,.08)}.row{display:flex;gap:10px;align-items:center;flex-wrap:wrap}.primary,.ghost,.danger{height:42px;border-radius:11px;padding:0 14px;cursor:pointer;text-decoration:none;display:inline-grid;place-items:center}.primary{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:#fff;font-weight:800}.ghost{border:1px solid var(--line);background:#fff}.danger{border:1px solid #ffd4d4;background:#fff4f4;color:var(--bad)}.table{overflow:auto}.table table{width:100%;border-collapse:collapse;min-width:850px}th,td{padding:11px 9px;border-bottom:1px solid #edf3f7;text-align:right;font-size:13px;vertical-align:top}th{color:var(--muted)}.badge{display:inline-block;padding:4px 8px;border-radius:999px;background:#eef3f7;font-size:11px}.okbadge{background:#e8f8f1;color:#0b8a5c}.badbadge{background:#fff0f0;color:#b33737}.warn{background:#fff7e8;border:1px solid #ffe3ae;color:var(--warn);padding:10px 12px;border-radius:12px;font-size:13px}.success,.error{padding:10px 12px;border-radius:12px;margin-bottom:14px;font-size:13px}.success{background:#e8f8f1;border:1px solid #c7efdc;color:#0b8a5c}.error{background:#fff0f0;border:1px solid #ffdada;color:var(--bad)}.statgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.stat{background:#fff;border:1px solid var(--line);border-radius:18px;padding:16px}.stat small{color:var(--muted)}.stat b{display:block;font-size:22px;margin-top:7px}.code{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;direction:ltr;text-align:left}.split{display:grid;grid-template-columns:minmax(0,1fr) minmax(320px,.65fr);gap:16px}.check{display:flex;gap:8px;align-items:center;margin-top:14px}.check input{width:18px;height:18px}.inline{display:inline}.section{font-size:17px;font-weight:900;margin:0 0 12px}.actions{display:flex;gap:7px;flex-wrap:wrap}.note{background:#f7fbff;border:1px solid var(--line);padding:12px;border-radius:12px}.secret{background:#f7fbff;border:1px dashed #b8d8ed;border-radius:12px;padding:12px}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;direction:ltr;text-align:left}@media(max-width:980px){.app{grid-template-columns:1fr}.side{position:static;height:auto}.nav{display:flex;gap:4px;overflow:auto}.nav a,.nav button{white-space:nowrap;width:auto}.split{grid-template-columns:1fr}.statgrid{grid-template-columns:1fr 1fr}.main{padding:16px}}@media(max-width:580px){.grid2,.grid3,.statgrid{grid-template-columns:1fr}.top{align-items:flex-start;flex-direction:column}}
</style></head><body><section class="app"><aside class="side"><div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><small>Admin Console</small></div></div><nav class="nav">${nav.map(([href,label,key]) => `<a href="${href}" class="${input.active === key ? 'active' : ''}">${label}</a>`).join('')}<form method="post" action="/admin/logout"><button class="logout" type="submit">خروج</button></form></nav></aside><main class="main"><div class="top"><div><h1>${esc(input.title)}</h1><div class="muted">مدیریت مرکزی VELIXEO — عملیات مدیریتی در Audit Log ثبت می‌شود</div></div><span class="chip">${esc(input.admin.fullName || input.admin.email || input.admin.phone || 'ADMIN')}</span></div>${input.message ? `<div class="${input.error ? 'error' : 'success'}">${esc(input.message)}</div>` : ''}${input.body}</main></section></body></html>`;
}

async function audit(
  prisma: PrismaClient,
  adminId: string,
  action: string,
  entityType: string,
  entityId: string | null,
  summary: string,
  metadata?: Prisma.InputJsonValue,
) {
  await prisma.adminAuditLog.create({
    data: {
      adminUserId: adminId,
      action,
      entityType,
      entityId,
      summary,
      metadata,
    },
  });
}

function messageFromQuery(query: unknown) {
  const q = (query ?? {}) as Record<string, unknown>;
  const key = String(q.msg ?? '');
  const messages: Record<string, [string, boolean]> = {
    saved: ['با موفقیت ذخیره شد.', false],
    deleted: ['با موفقیت حذف/غیرفعال شد.', false],
    secret_saved: ['کلید محرمانه به‌صورت رمزگذاری‌شده ذخیره شد.', false],
    secret_cleared: ['کلید محرمانه پاک شد.', false],
    invalid: ['اطلاعات واردشده معتبر نیست.', true],
    not_found: ['مورد موردنظر پیدا نشد.', true],
    encryption_missing: ['کلید رمزگذاری Provider در سرور تنظیم نشده است.', true],
    self_protected: ['نمی‌توانی حساب مدیریتی خودت را تعلیق یا از نقش ADMIN خارج کنی.', true],
    refunded: ['مبلغ سفارش با Ledger به کیف پول کاربر برگشت داده شد.', false],
    already_refunded: ['این سفارش قبلاً Refund شده است.', true],
    refund_not_charged: ['برای این سفارش هیچ Ledger Purchase معتبر پیدا نشد؛ Refund مالی متوقف شد.', true],
    user_not_found: ['کاربر پیدا نشد.', true],
  };
  return messages[key] ?? ['', false] as [string, boolean];
}

async function requireAdmin(
  request: FastifyRequest,
  reply: FastifyReply,
  resolveAdmin: AdminResolver,
) {
  const admin = await resolveAdmin(request);
  if (!admin) {
    reply.code(303).redirect('/admin');
    return null;
  }
  return admin;
}

export function registerExtendedAdminRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  resolveAdmin: AdminResolver,
) {
  app.get('/admin/users-control', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const q = String(query.q ?? '').trim();
    const where: Prisma.UserWhereInput = q
      ? { OR: [
          { fullName: { contains: q, mode: 'insensitive' } },
          { email: { contains: q, mode: 'insensitive' } },
          { phone: { contains: q, mode: 'insensitive' } },
        ] }
      : {};
    const users = await prisma.user.findMany({
      where,
      include: { wallet: true },
      orderBy: { createdAt: 'desc' },
      take: 150,
    });
    const [message, error] = messageFromQuery(request.query);
    const body = `<div class="card"><form method="get" action="/admin/users-control" class="row"><div class="field" style="flex:1;min-width:240px;margin:0"><label>جستجو</label><input name="q" value="${esc(q)}" placeholder="نام، ایمیل یا شماره"></div><button class="primary" type="submit">جستجو</button><a class="ghost" href="/admin/users-control">پاک کردن</a></form></div><div class="card table"><table><thead><tr><th>کاربر</th><th>وضعیت</th><th>نقش</th><th>ورود</th><th>Wallet</th><th>مدیریت</th></tr></thead><tbody>${users.map((u) => `<tr><td><b>${esc(u.fullName || '—')}</b><br><span class="muted">${esc(u.email || u.phone || '—')}</span></td><td><span class="badge ${u.status === UserStatus.ACTIVE ? 'okbadge' : 'badbadge'}">${u.status}</span></td><td>${u.role}</td><td>${u.googleSubject ? 'Google' : ''}${u.googleSubject && u.passwordHash ? ' + ' : ''}${u.passwordHash ? 'Password' : ''}</td><td><b>${fmtAfn(u.wallet?.balanceAfn)}</b></td><td><form method="post" action="/admin/users-control/save" class="actions"><input type="hidden" name="userId" value="${esc(u.id)}"><select name="status"><option value="ACTIVE"${u.status === UserStatus.ACTIVE ? ' selected' : ''}>ACTIVE</option><option value="SUSPENDED"${u.status === UserStatus.SUSPENDED ? ' selected' : ''}>SUSPENDED</option></select><select name="role"><option value="USER"${u.role === UserRole.USER ? ' selected' : ''}>USER</option><option value="ADMIN"${u.role === UserRole.ADMIN ? ' selected' : ''}>ADMIN</option></select><button class="ghost" type="submit">ذخیره</button></form></td></tr>`).join('')}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'مدیریت کاربران', admin, active: 'users', body, message, error }));
  });

  app.post('/admin/users-control/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const userId = text(body, 'userId');
    const status = text(body, 'status') as UserStatus;
    const role = text(body, 'role') as UserRole;
    if (!userId || !Object.values(UserStatus).includes(status) || !Object.values(UserRole).includes(role)) {
      return reply.code(303).redirect('/admin/users-control?msg=invalid');
    }
    if (userId === admin.id && (status !== UserStatus.ACTIVE || role !== UserRole.ADMIN)) {
      return reply.code(303).redirect('/admin/users-control?msg=self_protected');
    }
    const existing = await prisma.user.findUnique({ where: { id: userId } });
    if (!existing) return reply.code(303).redirect('/admin/users-control?msg=user_not_found');
    await prisma.$transaction([
      prisma.user.update({ where: { id: userId }, data: { status, role } }),
      ...(status === UserStatus.SUSPENDED
        ? [prisma.refreshToken.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } })]
        : []),
    ]);
    await audit(prisma, admin.id, 'USER_ACCESS_UPDATE', 'User', userId, `User status=${status}, role=${role}`, { previousStatus: existing.status, previousRole: existing.role });
    return reply.code(303).redirect('/admin/users-control?msg=saved');
  });

  app.get('/admin/providers', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const editId = String(query.edit ?? '');
    const [providers, selected] = await Promise.all([
      prisma.provider.findMany({ orderBy: [{ kind: 'asc' }, { priority: 'asc' }, { name: 'asc' }] }),
      editId ? prisma.provider.findUnique({ where: { id: editId } }) : Promise.resolve(null),
    ]);
    const [message, error] = messageFromQuery(request.query);
    const p = selected;
    const body = `<div class="split"><div class="card"><h3 class="section">Providerها</h3><div class="table"><table><thead><tr><th>نام</th><th>نوع</th><th>وضعیت</th><th>اولویت</th><th>Markup</th><th>Secret</th><th></th></tr></thead><tbody>${providers.map((x) => `<tr><td><b>${esc(x.name)}</b><br><span class="muted code">${esc(x.slug)}</span></td><td>${x.kind}</td><td><span class="badge ${x.enabled ? 'okbadge' : 'badbadge'}">${x.enabled ? 'فعال' : 'خاموش'}</span></td><td>${x.priority}</td><td>${x.defaultMarkupPercent.toString()}%</td><td>${x.secretCiphertext ? '<span class="badge okbadge">Configured</span>' : '<span class="badge">Empty</span>'}</td><td><a class="ghost" href="/admin/providers?edit=${encodeURIComponent(x.id)}">ویرایش</a></td></tr>`).join('')}</tbody></table></div></div><div><div class="card"><h3 class="section">${p ? 'ویرایش Provider' : 'Provider جدید'}</h3><form method="post" action="/admin/providers/save">${p ? `<input type="hidden" name="id" value="${esc(p.id)}">` : ''}<div class="grid2"><div class="field"><label>نام</label><input name="name" value="${esc(p?.name || '')}" required></div><div class="field"><label>Slug یکتا</label><input class="mono" name="slug" value="${esc(p?.slug || '')}" pattern="[a-z0-9_-]+" required></div></div><div class="grid2"><div class="field"><label>نوع</label><select name="kind">${selectOptions(Object.values(ProviderKind), p?.kind)}</select></div><div class="field"><label>Base URL</label><input class="mono" name="baseUrl" value="${esc(p?.baseUrl || '')}"></div></div><div class="grid3"><div class="field"><label>اولویت (کمتر = بالاتر)</label><input name="priority" type="number" value="${esc(p?.priority ?? 100)}"></div><div class="field"><label>Markup پیش‌فرض %</label><input name="markup" inputmode="decimal" value="${esc(p?.defaultMarkupPercent?.toString() ?? '0')}"></div><div class="field"><label>Timeout ثانیه</label><input name="timeoutSeconds" type="number" min="5" max="180" value="${esc(p?.timeoutSeconds ?? 30)}"></div></div><div class="field"><label>یادداشت داخلی</label><textarea name="notes">${esc(p?.notes || '')}</textarea></div><label class="check"><input type="checkbox" name="enabled"${p?.enabled !== false ? ' checked' : ''}>فعال باشد</label><div class="row" style="margin-top:14px"><button class="primary" type="submit">ذخیره Provider</button>${p ? '<a class="ghost" href="/admin/providers">Provider جدید</a>' : ''}</div></form></div>${p ? `<div class="card"><h3 class="section">Secret / API Key</h3><div class="secret">${providerSecretEncryptionConfigured() ? 'رمزگذاری AES-256-GCM روی سرور فعال است. مقدار Secret بعد از ذخیره دوباره نمایش داده نمی‌شود.' : 'ابتدا متغیر ADMIN_SECRET_ENCRYPTION_KEY را در Railway تنظیم کن؛ تا آن زمان ذخیره Secret غیرفعال است.'}</div><form method="post" action="/admin/providers/secret"><input type="hidden" name="id" value="${esc(p.id)}"><div class="field"><label>Credential JSON / Secret</label><textarea class="mono" name="secret" placeholder='{"apiKey":"...","secret":"..."}' required></textarea></div><button class="primary" type="submit"${providerSecretEncryptionConfigured() ? '' : ' disabled'}>رمزگذاری و ذخیره</button></form>${p.secretCiphertext ? `<form method="post" action="/admin/providers/secret-clear" style="margin-top:10px"><input type="hidden" name="id" value="${esc(p.id)}"><button class="danger" type="submit">پاک کردن Secret</button></form>` : ''}</div>` : ''}</div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'Provider و API', admin, active: 'providers', body, message, error }));
  });

  app.post('/admin/providers/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const id = text(body, 'id');
      const name = text(body, 'name');
      const slug = text(body, 'slug').toLowerCase();
      const kind = text(body, 'kind') as ProviderKind;
      if (name.length < 2 || !/^[a-z0-9_-]{2,80}$/.test(slug) || !Object.values(ProviderKind).includes(kind)) throw new Error('INVALID');
      const data = {
        name,
        slug,
        kind,
        baseUrl: text(body, 'baseUrl') || null,
        enabled: checked(body, 'enabled'),
        priority: intValue(body, 'priority', 100),
        defaultMarkupPercent: new Prisma.Decimal(decimalValue(body, 'markup', '0')),
        timeoutSeconds: Math.min(180, Math.max(5, intValue(body, 'timeoutSeconds', 30))),
        notes: text(body, 'notes') || null,
      };
      const saved = id
        ? await prisma.provider.update({ where: { id }, data })
        : await prisma.provider.create({ data });
      await audit(prisma, admin.id, id ? 'PROVIDER_UPDATE' : 'PROVIDER_CREATE', 'Provider', saved.id, `${saved.name} (${saved.slug})`);
      return reply.code(303).redirect(`/admin/providers?edit=${encodeURIComponent(saved.id)}&msg=saved`);
    } catch {
      return reply.code(303).redirect('/admin/providers?msg=invalid');
    }
  });

  app.post('/admin/providers/secret', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const id = text(body, 'id');
    const secret = text(body, 'secret');
    if (!providerSecretEncryptionConfigured()) return reply.code(303).redirect(`/admin/providers?edit=${encodeURIComponent(id)}&msg=encryption_missing`);
    if (!id || secret.length < 3) return reply.code(303).redirect('/admin/providers?msg=invalid');
    try {
      const encrypted = encryptProviderSecret(secret);
      await prisma.provider.update({ where: { id }, data: encrypted });
      await audit(prisma, admin.id, 'PROVIDER_SECRET_REPLACE', 'Provider', id, 'Provider secret replaced securely');
      return reply.code(303).redirect(`/admin/providers?edit=${encodeURIComponent(id)}&msg=secret_saved`);
    } catch {
      return reply.code(303).redirect(`/admin/providers?edit=${encodeURIComponent(id)}&msg=invalid`);
    }
  });

  app.post('/admin/providers/secret-clear', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const id = text(request.body as AnyBody, 'id');
    if (!id) return reply.code(303).redirect('/admin/providers?msg=invalid');
    await prisma.provider.update({ where: { id }, data: { secretCiphertext: null, secretIv: null, secretTag: null } });
    await audit(prisma, admin.id, 'PROVIDER_SECRET_CLEAR', 'Provider', id, 'Provider secret cleared');
    return reply.code(303).redirect(`/admin/providers?edit=${encodeURIComponent(id)}&msg=secret_cleared`);
  });

  app.get('/admin/services', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const editId = String(query.edit ?? '');
    const [services, providers, selected] = await Promise.all([
      prisma.service.findMany({ include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } }, orderBy: [{ category: 'asc' }, { sortOrder: 'asc' }] }),
      prisma.provider.findMany({ orderBy: [{ enabled: 'desc' }, { priority: 'asc' }, { name: 'asc' }] }),
      editId ? prisma.service.findUnique({ where: { id: editId }, include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } } }) : Promise.resolve(null),
    ]);
    const [message, error] = messageFromQuery(request.query);
    const s = selected;
    const body = `<div class="split"><div class="card"><h3 class="section">کاتالوگ خدمات</h3><div class="table"><table><thead><tr><th>خدمت</th><th>دسته</th><th>قیمت پایه</th><th>Route</th><th>وضعیت</th><th></th></tr></thead><tbody>${services.map((x) => `<tr><td><b>${esc(x.titleFa)}</b><br><span class="muted">${esc(x.titleEn)}</span><br><span class="muted code">${esc(x.slug)}</span></td><td>${x.category}</td><td>${x.basePriceAfn == null ? 'Dynamic' : fmtAfn(x.basePriceAfn)}</td><td>${x.routes.filter((r) => r.enabled).length}/${x.routes.length}</td><td><span class="badge ${x.enabled ? 'okbadge' : 'badbadge'}">${x.enabled ? 'فعال' : 'خاموش'}</span></td><td><a class="ghost" href="/admin/services?edit=${encodeURIComponent(x.id)}">ویرایش</a></td></tr>`).join('')}</tbody></table></div></div><div><div class="card"><h3 class="section">${s ? 'ویرایش خدمت' : 'خدمت جدید'}</h3><form method="post" action="/admin/services/save">${s ? `<input type="hidden" name="id" value="${esc(s.id)}">` : ''}<div class="grid2"><div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(s?.titleFa || '')}" required></div><div class="field"><label>English title</label><input name="titleEn" value="${esc(s?.titleEn || '')}" required></div></div><div class="grid2"><div class="field"><label>Slug</label><input class="mono" name="slug" value="${esc(s?.slug || '')}" pattern="[a-z0-9_-]+" required></div><div class="field"><label>دسته</label><select name="category">${selectOptions(Object.values(ServiceCategory), s?.category)}</select></div></div><div class="grid3"><div class="field"><label>قیمت پایه AFN</label><input name="basePriceAfn" type="number" min="0" value="${esc(s?.basePriceAfn?.toString() || '')}" placeholder="خالی = Dynamic"></div><div class="field"><label>حداقل تعداد</label><input name="minQty" type="number" min="1" value="${esc(s?.minQty ?? '')}"></div><div class="field"><label>حداکثر تعداد</label><input name="maxQty" type="number" min="1" value="${esc(s?.maxQty ?? '')}"></div></div><div class="field"><label>توضیح فارسی</label><textarea name="descriptionFa">${esc(s?.descriptionFa || '')}</textarea></div><div class="field"><label>English description</label><textarea name="descriptionEn">${esc(s?.descriptionEn || '')}</textarea></div><div class="field"><label>Metadata JSON (تنظیمات پیشرفته سرویس)</label><textarea class="mono" name="metadata" placeholder='{"country":"afghanistan","operator":"..."}'>${esc(s?.metadata ? JSON.stringify(s.metadata, null, 2) : '')}</textarea></div><div class="field"><label>ترتیب نمایش</label><input name="sortOrder" type="number" value="${esc(s?.sortOrder ?? 100)}"></div><div class="row"><label class="check"><input type="checkbox" name="enabled"${s?.enabled !== false ? ' checked' : ''}>فعال</label><label class="check"><input type="checkbox" name="featured"${s?.featured ? ' checked' : ''}>ویژه</label></div><div class="row" style="margin-top:14px"><button class="primary" type="submit">ذخیره خدمت</button>${s ? '<a class="ghost" href="/admin/services">خدمت جدید</a>' : ''}</div></form></div>${s ? `<div class="card"><h3 class="section">Provider Route</h3><div class="muted">برای Failover می‌توانی چند Provider برای یک خدمت تعریف کنی. اولویت کمتر زودتر انتخاب می‌شود.</div>${s.routes.length ? `<div class="table"><table><thead><tr><th>Provider</th><th>Code</th><th>Priority</th><th>Cost</th><th>Markup</th><th>وضعیت</th></tr></thead><tbody>${s.routes.map((r) => `<tr><td>${esc(r.provider.name)}</td><td class="code">${esc(r.providerServiceCode)}</td><td>${r.priority}</td><td>${r.costAfn == null ? 'API' : fmtAfn(r.costAfn)}</td><td>${r.markupPercent?.toString() ?? 'Default'}%</td><td>${r.enabled ? 'ON' : 'OFF'}</td></tr>`).join('')}</tbody></table></div>` : '<p class="muted">هنوز Route ثبت نشده است.</p>'}<form method="post" action="/admin/routes/save"><input type="hidden" name="serviceId" value="${esc(s.id)}"><div class="grid2"><div class="field"><label>Provider</label><select name="providerId" required><option value="">انتخاب...</option>${providers.map((p) => `<option value="${esc(p.id)}">${esc(p.name)} — ${p.kind}</option>`).join('')}</select></div><div class="field"><label>Provider service code</label><input class="mono" name="providerServiceCode" required></div></div><div class="grid3"><div class="field"><label>Priority</label><input name="priority" type="number" value="100"></div><div class="field"><label>Cost AFN اختیاری</label><input name="costAfn" type="number" min="0"></div><div class="field"><label>Markup % اختیاری</label><input name="markup" inputmode="decimal"></div></div><div class="field"><label>Route Metadata JSON</label><textarea class="mono" name="metadata" placeholder='{"countryCode":"af","operator":"any"}'></textarea></div><label class="check"><input type="checkbox" name="enabled" checked>فعال</label><button class="primary" type="submit" style="margin-top:12px">افزودن Route</button></form></div>` : ''}</div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'خدمات و قیمت‌ها', admin, active: 'services', body, message, error }));
  });

  app.post('/admin/services/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const id = text(body, 'id');
      const titleFa = text(body, 'titleFa');
      const titleEn = text(body, 'titleEn');
      const slug = text(body, 'slug').toLowerCase();
      const category = text(body, 'category') as ServiceCategory;
      if (titleFa.length < 2 || titleEn.length < 2 || !/^[a-z0-9_-]{2,100}$/.test(slug) || !Object.values(ServiceCategory).includes(category)) throw new Error('INVALID');
      const minRaw = text(body, 'minQty');
      const maxRaw = text(body, 'maxQty');
      const data = {
        titleFa,
        titleEn,
        slug,
        category,
        descriptionFa: text(body, 'descriptionFa') || null,
        descriptionEn: text(body, 'descriptionEn') || null,
        enabled: checked(body, 'enabled'),
        featured: checked(body, 'featured'),
        sortOrder: intValue(body, 'sortOrder', 100),
        basePriceAfn: bigIntOrNull(body, 'basePriceAfn'),
        minQty: minRaw ? Math.max(1, intValue(body, 'minQty', 1)) : null,
        maxQty: maxRaw ? Math.max(1, intValue(body, 'maxQty', 1)) : null,
        metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,
      };
      const saved = id ? await prisma.service.update({ where: { id }, data }) : await prisma.service.create({ data });
      await audit(prisma, admin.id, id ? 'SERVICE_UPDATE' : 'SERVICE_CREATE', 'Service', saved.id, `${saved.titleEn} (${saved.slug})`);
      return reply.code(303).redirect(`/admin/services?edit=${encodeURIComponent(saved.id)}&msg=saved`);
    } catch {
      return reply.code(303).redirect('/admin/services?msg=invalid');
    }
  });

  app.post('/admin/routes/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const serviceId = text(body, 'serviceId');
      const providerId = text(body, 'providerId');
      const providerServiceCode = text(body, 'providerServiceCode');
      if (!serviceId || !providerId || !providerServiceCode) throw new Error('INVALID');
      const route = await prisma.serviceProviderRoute.upsert({
        where: { serviceId_providerId_providerServiceCode: { serviceId, providerId, providerServiceCode } },
        update: {
          enabled: checked(body, 'enabled'),
          priority: intValue(body, 'priority', 100),
          costAfn: bigIntOrNull(body, 'costAfn'),
          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,
          metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,
        },
        create: {
          serviceId,
          providerId,
          providerServiceCode,
          enabled: checked(body, 'enabled'),
          priority: intValue(body, 'priority', 100),
          costAfn: bigIntOrNull(body, 'costAfn'),
          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body, 'markup')) : null,
          metadata: text(body, 'metadata') ? JSON.parse(text(body, 'metadata')) as Prisma.InputJsonValue : Prisma.JsonNull,
        },
      });
      await audit(prisma, admin.id, 'SERVICE_ROUTE_UPSERT', 'ServiceProviderRoute', route.id, providerServiceCode);
      return reply.code(303).redirect(`/admin/services?edit=${encodeURIComponent(serviceId)}&msg=saved`);
    } catch {
      return reply.code(303).redirect('/admin/services?msg=invalid');
    }
  });

  app.get('/admin/orders', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const filter = String(query.status ?? '');
    const where: Prisma.OrderWhereInput = Object.values(OrderStatus).includes(filter as OrderStatus) ? { status: filter as OrderStatus } : {};
    const orders = await prisma.order.findMany({ where, include: { user: true, service: true, provider: true }, orderBy: { createdAt: 'desc' }, take: 200 });
    const [message, error] = messageFromQuery(request.query);
    const body = `<div class="card"><div class="row"><b>آخرین سفارش‌ها</b><span class="muted">Wallet-only purchase foundation</span><form method="get" action="/admin/orders" class="row" style="margin-right:auto"><select name="status"><option value="">همه وضعیت‌ها</option>${selectOptions(Object.values(OrderStatus), filter)}</select><button class="ghost" type="submit">فیلتر</button></form></div><div class="warn" style="margin-top:12px">REFUNDED فقط باید همراه Ledger Refund اجرا شود؛ این صفحه فعلاً برای وضعیت عملیاتی سفارش است.</div><div class="table"><table><thead><tr><th>ID</th><th>کاربر</th><th>خدمت</th><th>مبلغ</th><th>Provider</th><th>وضعیت</th><th>زمان</th></tr></thead><tbody>${orders.length ? orders.map((o) => `<tr><td class="code">${esc(o.id.slice(0, 8))}</td><td>${esc(o.user.fullName || o.user.email || o.user.phone || '—')}</td><td>${esc(o.service?.titleFa || o.category)}</td><td>${fmtAfn(o.totalAmountAfn)}</td><td>${esc(o.provider?.name || '—')}</td><td><form method="post" action="/admin/orders/status" class="row"><input type="hidden" name="id" value="${esc(o.id)}"><select name="status">${selectOptions(Object.values(OrderStatus).filter((x) => x !== 'REFUNDED'), o.status)}</select><button class="ghost" type="submit">ثبت</button></form>${o.status !== OrderStatus.REFUNDED ? `<form method="post" action="/admin/orders/refund" style="margin-top:6px"><input type="hidden" name="id" value="${esc(o.id)}"><button class="danger" type="submit">Refund کامل</button></form>` : '<span class="badge okbadge">Refunded</span>'}</td><td>${faDate(o.createdAt)}</td></tr>`).join('') : '<tr><td colspan="7" class="muted">هنوز سفارشی ثبت نشده است.</td></tr>'}</tbody></table></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'سفارش‌ها', admin, active: 'orders', body, message, error }));
  });

  app.post('/admin/orders/status', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const id = text(body, 'id');
    const status = text(body, 'status') as OrderStatus;
    if (!id || !Object.values(OrderStatus).includes(status) || status === OrderStatus.REFUNDED) return reply.code(303).redirect('/admin/orders?msg=invalid');
    const order = await prisma.order.update({ where: { id }, data: { status, completedAt: status === OrderStatus.COMPLETED ? new Date() : undefined } });
    await audit(prisma, admin.id, 'ORDER_STATUS_UPDATE', 'Order', id, `Order status changed to ${status}`, { previousUpdatedAt: order.updatedAt.toISOString() });
    return reply.code(303).redirect('/admin/orders?msg=saved');
  });

  app.post('/admin/orders/refund', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const orderId = text(request.body as AnyBody, 'id');
    if (!orderId) return reply.code(303).redirect('/admin/orders?msg=invalid');
    try {
      const refund = await prisma.$transaction(
        async (tx) => {
          const order = await tx.order.findUnique({ where: { id: orderId } });
          if (!order) throw new Error('ORDER_NOT_FOUND');
          if (order.status === OrderStatus.REFUNDED) throw new Error('ALREADY_REFUNDED');

          const existing = await tx.walletEntry.findUnique({
            where: { idempotencyKey: `order-refund-${order.id}` },
          });
          if (existing) throw new Error('ALREADY_REFUNDED');

          const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
          if (!wallet) throw new Error('WALLET_NOT_FOUND');

          // A refund must reverse a real, completed wallet purchase for this exact order.
          // This prevents an admin-created or malformed order from minting wallet balance.
          const purchaseEntry = await tx.walletEntry.findFirst({
            where: {
              walletId: wallet.id,
              type: WalletEntryType.PURCHASE,
              status: WalletEntryStatus.COMPLETED,
              referenceType: 'ORDER_PURCHASE',
              referenceId: order.id,
              amountAfn: -order.totalAmountAfn,
            },
            orderBy: { createdAt: 'desc' },
          });
          if (!purchaseEntry) throw new Error('ORDER_NOT_CHARGED');

          const nextBalance = wallet.balanceAfn + order.totalAmountAfn;

          await tx.wallet.update({
            where: { id: wallet.id },
            data: { balanceAfn: nextBalance },
          });
          const entry = await tx.walletEntry.create({
            data: {
              walletId: wallet.id,
              type: WalletEntryType.REFUND,
              amountAfn: order.totalAmountAfn,
              balanceAfterAfn: nextBalance,
              description: `Refund order ${order.id}`,
              idempotencyKey: `order-refund-${order.id}`,
              referenceType: 'ORDER_REFUND',
              referenceId: order.id,
              metadata: { adminUserId: admin.id },
            },
          });
          await tx.order.update({
            where: { id: order.id },
            data: { status: OrderStatus.REFUNDED },
          });
          return { order, entry };
        },
        { isolationLevel: 'Serializable' },
      );
      await audit(
        prisma,
        admin.id,
        'ORDER_REFUND',
        'Order',
        orderId,
        `Refunded ${refund.order.totalAmountAfn.toString()} AFN`,
        { walletEntryId: refund.entry.id, userId: refund.order.userId, invariant: 'ORDER_PURCHASE_LEDGER_REQUIRED' },
      );
      return reply.code(303).redirect('/admin/orders?msg=refunded');
    } catch (error) {
      if (error instanceof Error && error.message === 'ALREADY_REFUNDED') {
        return reply.code(303).redirect('/admin/orders?msg=already_refunded');
      }
      if (error instanceof Error && error.message === 'ORDER_NOT_FOUND') {
        return reply.code(303).redirect('/admin/orders?msg=not_found');
      }
      if (error instanceof Error && error.message === 'ORDER_NOT_CHARGED') {
        return reply.code(303).redirect('/admin/orders?msg=refund_not_charged');
      }
      throw error;
    }
  });

  app.get('/admin/payments', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const payments = await prisma.paymentTransaction.findMany({ include: { user: true, provider: true }, orderBy: { createdAt: 'desc' }, take: 200 });
    const body = `<div class="card"><h3 class="section">تراکنش‌های پرداخت</h3><div class="warn">اعتبار Wallet فقط بعد از Verify/Webhook معتبر باید اضافه شود. Redirect به‌تنهایی هرگز موجودی را تغییر نمی‌دهد.</div><div class="table"><table><thead><tr><th>ID</th><th>کاربر</th><th>Gateway</th><th>مبلغ</th><th>وضعیت</th><th>External ID</th><th>تأیید Backend</th><th>زمان</th></tr></thead><tbody>${payments.length ? payments.map((p) => `<tr><td class="code">${esc(p.id.slice(0, 8))}</td><td>${esc(p.user.fullName || p.user.email || p.user.phone || '—')}</td><td>${esc(p.gateway || p.provider?.name || '—')}</td><td>${fmtAfn(p.amountAfn)}</td><td><span class="badge ${p.status === 'PAID' ? 'okbadge' : p.status === 'FAILED' ? 'badbadge' : ''}">${p.status}</span></td><td class="code">${esc(p.externalId || p.referenceId || '—')}</td><td>${p.verifiedAt ? `<span class="badge okbadge">Verified</span><br><span class="muted">${faDate(p.verifiedAt)}</span>` : '<span class="badge">Not verified</span>'}${p.failureReason ? `<br><span class="muted">${esc(p.failureReason)}</span>` : ''}</td><td>${faDate(p.createdAt)}</td></tr>`).join('') : '<tr><td colspan="8" class="muted">هنوز تراکنش پرداختی ثبت نشده است.</td></tr>'}</tbody></table></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'پرداخت‌ها', admin, active: 'payments', body }));
  });

  app.get('/admin/banners', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const editId = String(query.edit ?? '');
    const [items, selected] = await Promise.all([
      prisma.banner.findMany({ orderBy: [{ placement: 'asc' }, { sortOrder: 'asc' }, { createdAt: 'desc' }] }),
      editId ? prisma.banner.findUnique({ where: { id: editId } }) : Promise.resolve(null),
    ]);
    const [message, error] = messageFromQuery(request.query);
    const b = selected;
    const body = `<div class="split"><div class="card table"><table><thead><tr><th>جایگاه</th><th>عنوان</th><th>وضعیت</th><th>ترتیب</th><th></th></tr></thead><tbody>${items.map((x) => `<tr><td>${x.placement}</td><td>${esc(x.titleFa || x.titleEn || 'بدون عنوان')}<br><span class="muted code">${esc(x.imageUrl)}</span></td><td>${x.enabled ? 'ON' : 'OFF'}</td><td>${x.sortOrder}</td><td><a class="ghost" href="/admin/banners?edit=${encodeURIComponent(x.id)}">ویرایش</a></td></tr>`).join('')}</tbody></table></div><div class="card"><h3 class="section">${b ? 'ویرایش بنر' : 'بنر جدید'}</h3><form method="post" action="/admin/banners/save">${b ? `<input type="hidden" name="id" value="${esc(b.id)}">` : ''}<div class="grid2"><div class="field"><label>جایگاه</label><select name="placement">${selectOptions(Object.values(BannerPlacement), b?.placement)}</select></div><div class="field"><label>ترتیب</label><input name="sortOrder" type="number" value="${esc(b?.sortOrder ?? 100)}"></div></div><div class="field"><label>Image URL</label><input class="mono" name="imageUrl" value="${esc(b?.imageUrl || '')}" required></div><div class="grid2"><div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(b?.titleFa || '')}"></div><div class="field"><label>English title</label><input name="titleEn" value="${esc(b?.titleEn || '')}"></div></div><div class="grid2"><div class="field"><label>زیرعنوان فارسی</label><input name="subtitleFa" value="${esc(b?.subtitleFa || '')}"></div><div class="field"><label>English subtitle</label><input name="subtitleEn" value="${esc(b?.subtitleEn || '')}"></div></div><div class="grid2"><div class="field"><label>CTA فارسی</label><input name="actionLabelFa" value="${esc(b?.actionLabelFa || '')}"></div><div class="field"><label>CTA English</label><input name="actionLabelEn" value="${esc(b?.actionLabelEn || '')}"></div></div><div class="field"><label>Action URL / deep link</label><input class="mono" name="actionUrl" value="${esc(b?.actionUrl || '')}"></div><label class="check"><input type="checkbox" name="enabled"${b?.enabled !== false ? ' checked' : ''}>فعال</label><div class="row" style="margin-top:14px"><button class="primary" type="submit">ذخیره بنر</button>${b ? '<a class="ghost" href="/admin/banners">بنر جدید</a>' : ''}</div></form></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'بنرها', admin, active: 'banners', body, message, error }));
  });

  app.post('/admin/banners/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const id = text(body, 'id');
      const placement = text(body, 'placement') as BannerPlacement;
      const imageUrl = text(body, 'imageUrl');
      if (!Object.values(BannerPlacement).includes(placement) || imageUrl.length < 5) throw new Error('INVALID');
      const data = { placement, imageUrl, titleFa: text(body, 'titleFa') || null, titleEn: text(body, 'titleEn') || null, subtitleFa: text(body, 'subtitleFa') || null, subtitleEn: text(body, 'subtitleEn') || null, actionLabelFa: text(body, 'actionLabelFa') || null, actionLabelEn: text(body, 'actionLabelEn') || null, actionUrl: text(body, 'actionUrl') || null, enabled: checked(body, 'enabled'), sortOrder: intValue(body, 'sortOrder', 100) };
      const saved = id ? await prisma.banner.update({ where: { id }, data }) : await prisma.banner.create({ data });
      await audit(prisma, admin.id, id ? 'BANNER_UPDATE' : 'BANNER_CREATE', 'Banner', saved.id, `${saved.placement}: ${saved.titleEn || saved.titleFa || saved.imageUrl}`);
      return reply.code(303).redirect(`/admin/banners?edit=${encodeURIComponent(saved.id)}&msg=saved`);
    } catch {
      return reply.code(303).redirect('/admin/banners?msg=invalid');
    }
  });

  app.get('/admin/coupons', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const editId = String(query.edit ?? '');
    const [items, selected] = await Promise.all([
      prisma.coupon.findMany({ orderBy: { createdAt: 'desc' } }),
      editId ? prisma.coupon.findUnique({ where: { id: editId } }) : Promise.resolve(null),
    ]);
    const [message, error] = messageFromQuery(request.query);
    const c = selected;
    const body = `<div class="split"><div class="card table"><table><thead><tr><th>Code</th><th>تخفیف</th><th>استفاده</th><th>وضعیت</th><th></th></tr></thead><tbody>${items.map((x) => `<tr><td class="code"><b>${esc(x.code)}</b></td><td>${x.discountType === CouponDiscountType.PERCENT ? `${x.discountValue.toString()}%` : `${x.discountValue.toString()} AFN`}</td><td>${x.usedCount}/${x.usageLimit ?? '∞'}</td><td>${x.active ? 'ON' : 'OFF'}</td><td><a class="ghost" href="/admin/coupons?edit=${encodeURIComponent(x.id)}">ویرایش</a></td></tr>`).join('')}</tbody></table></div><div class="card"><h3 class="section">${c ? 'ویرایش کد' : 'کد تخفیف جدید'}</h3><form method="post" action="/admin/coupons/save">${c ? `<input type="hidden" name="id" value="${esc(c.id)}">` : ''}<div class="grid2"><div class="field"><label>Code</label><input class="mono" name="code" value="${esc(c?.code || '')}" required></div><div class="field"><label>عنوان داخلی</label><input name="title" value="${esc(c?.title || '')}"></div></div><div class="grid2"><div class="field"><label>نوع</label><select name="discountType">${selectOptions(Object.values(CouponDiscountType), c?.discountType)}</select></div><div class="field"><label>مقدار</label><input name="discountValue" inputmode="decimal" value="${esc(c?.discountValue?.toString() || '')}" required></div></div><div class="grid3"><div class="field"><label>حداقل سفارش AFN</label><input name="minOrderAfn" type="number" min="0" value="${esc(c?.minOrderAfn?.toString() || '0')}"></div><div class="field"><label>سقف تخفیف AFN</label><input name="maxDiscountAfn" type="number" min="0" value="${esc(c?.maxDiscountAfn?.toString() || '')}"></div><div class="field"><label>Usage limit</label><input name="usageLimit" type="number" min="1" value="${esc(c?.usageLimit ?? '')}"></div></div><label class="check"><input type="checkbox" name="active"${c?.active !== false ? ' checked' : ''}>فعال</label><div class="row" style="margin-top:14px"><button class="primary" type="submit">ذخیره</button>${c ? '<a class="ghost" href="/admin/coupons">کد جدید</a>' : ''}</div></form></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'کدهای تخفیف', admin, active: 'coupons', body, message, error }));
  });

  app.post('/admin/coupons/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const id = text(body, 'id');
      const code = text(body, 'code').toUpperCase();
      const discountType = text(body, 'discountType') as CouponDiscountType;
      if (!/^[A-Z0-9_-]{3,40}$/.test(code) || !Object.values(CouponDiscountType).includes(discountType)) throw new Error('INVALID');
      const limitRaw = text(body, 'usageLimit');
      const data = { code, title: text(body, 'title') || null, discountType, discountValue: new Prisma.Decimal(decimalValue(body, 'discountValue')), minOrderAfn: bigIntOrNull(body, 'minOrderAfn') ?? 0n, maxDiscountAfn: bigIntOrNull(body, 'maxDiscountAfn'), usageLimit: limitRaw ? Math.max(1, intValue(body, 'usageLimit', 1)) : null, active: checked(body, 'active') };
      const saved = id ? await prisma.coupon.update({ where: { id }, data }) : await prisma.coupon.create({ data });
      await audit(prisma, admin.id, id ? 'COUPON_UPDATE' : 'COUPON_CREATE', 'Coupon', saved.id, saved.code);
      return reply.code(303).redirect(`/admin/coupons?edit=${encodeURIComponent(saved.id)}&msg=saved`);
    } catch {
      return reply.code(303).redirect('/admin/coupons?msg=invalid');
    }
  });

  app.get('/admin/notifications', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const items = await prisma.notification.findMany({ include: { user: true }, orderBy: { createdAt: 'desc' }, take: 150 });
    const [message, error] = messageFromQuery(request.query);
    const body = `<div class="card"><h3 class="section">اعلان جدید</h3><form method="post" action="/admin/notifications/save"><div class="grid2"><div class="field"><label>Audience</label><select name="audience">${selectOptions(Object.values(NotificationAudience), 'ALL')}</select></div><div class="field"><label>کاربر خاص (ایمیل/شماره) — فقط برای USER</label><input name="target" placeholder="user@example.com"></div></div><div class="grid2"><div class="field"><label>عنوان فارسی</label><input name="titleFa" required></div><div class="field"><label>English title</label><input name="titleEn" required></div></div><div class="grid2"><div class="field"><label>متن فارسی</label><textarea name="bodyFa" required></textarea></div><div class="field"><label>English body</label><textarea name="bodyEn" required></textarea></div></div><label class="check"><input type="checkbox" name="enabled" checked>فعال</label><button class="primary" type="submit" style="margin-top:12px">انتشار اعلان</button></form></div><div class="card table"><table><thead><tr><th>عنوان</th><th>Audience</th><th>کاربر</th><th>وضعیت</th><th>زمان</th></tr></thead><tbody>${items.map((n) => `<tr><td><b>${esc(n.titleFa)}</b><br><span class="muted">${esc(n.titleEn)}</span></td><td>${n.audience}</td><td>${esc(n.user?.email || n.user?.phone || 'همه')}</td><td>${n.enabled ? 'ON' : 'OFF'}</td><td>${faDate(n.publishAt)}</td></tr>`).join('')}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'اعلان‌ها', admin, active: 'notifications', body, message, error }));
  });

  app.post('/admin/notifications/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const audience = text(body, 'audience') as NotificationAudience;
      if (!Object.values(NotificationAudience).includes(audience)) throw new Error('INVALID');
      let userId: string | null = null;
      if (audience === NotificationAudience.USER) {
        const target = text(body, 'target');
        const user = await prisma.user.findFirst({ where: { OR: [{ email: target.toLowerCase() }, { phone: target.replace(/\s+/g, '') }] } });
        if (!user) return reply.code(303).redirect('/admin/notifications?msg=user_not_found');
        userId = user.id;
      }
      const titleFa = text(body, 'titleFa');
      const titleEn = text(body, 'titleEn');
      const bodyFa = text(body, 'bodyFa');
      const bodyEn = text(body, 'bodyEn');
      if (!titleFa || !titleEn || !bodyFa || !bodyEn) throw new Error('INVALID');
      const saved = await prisma.notification.create({ data: { audience, userId, titleFa, titleEn, bodyFa, bodyEn, enabled: checked(body, 'enabled') } });
      await audit(prisma, admin.id, 'NOTIFICATION_CREATE', 'Notification', saved.id, `${audience}: ${titleEn}`);
      return reply.code(303).redirect('/admin/notifications?msg=saved');
    } catch {
      return reply.code(303).redirect('/admin/notifications?msg=invalid');
    }
  });

  app.get('/admin/support', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const ticketId = String(query.ticket ?? '');
    const [tickets, selected] = await Promise.all([
      prisma.supportTicket.findMany({ include: { user: true }, orderBy: { lastMessageAt: 'desc' }, take: 150 }),
      ticketId ? prisma.supportTicket.findUnique({ where: { id: ticketId }, include: { user: true, messages: { include: { senderUser: true }, orderBy: { createdAt: 'asc' } } } }) : Promise.resolve(null),
    ]);
    const [message, error] = messageFromQuery(request.query);
    const body = `<div class="split"><div class="card table"><table><thead><tr><th>موضوع</th><th>کاربر</th><th>وضعیت</th><th>آخرین پیام</th><th></th></tr></thead><tbody>${tickets.length ? tickets.map((t) => `<tr><td>${esc(t.subject)}</td><td>${esc(t.user.fullName || t.user.email || t.user.phone || '—')}</td><td>${t.status}</td><td>${faDate(t.lastMessageAt)}</td><td><a class="ghost" href="/admin/support?ticket=${encodeURIComponent(t.id)}">باز کردن</a></td></tr>`).join('') : '<tr><td colspan="5" class="muted">تیکتی وجود ندارد.</td></tr>'}</tbody></table></div>${selected ? `<div><div class="card"><h3 class="section">${esc(selected.subject)}</h3><div class="muted">${esc(selected.user.fullName || selected.user.email || selected.user.phone || '')}</div><div style="margin-top:14px">${selected.messages.map((m) => `<div class="note" style="margin-bottom:8px"><b>${m.isAdmin ? 'VELIXEO Support' : esc(m.senderUser?.fullName || m.senderUser?.email || 'کاربر')}</b><div style="white-space:pre-wrap;margin-top:5px">${esc(m.content)}</div><small class="muted">${faDate(m.createdAt)}</small></div>`).join('') || '<div class="muted">بدون پیام</div>'}</div><form method="post" action="/admin/support/reply"><input type="hidden" name="ticketId" value="${esc(selected.id)}"><div class="field"><label>پاسخ</label><textarea name="content" required></textarea></div><button class="primary" type="submit">ارسال پاسخ</button></form><form method="post" action="/admin/support/status" class="row" style="margin-top:12px"><input type="hidden" name="ticketId" value="${esc(selected.id)}"><select name="status">${selectOptions(Object.values(SupportStatus), selected.status)}</select><button class="ghost" type="submit">تغییر وضعیت</button></form></div></div>` : '<div class="card muted">برای مشاهده گفتگو یک تیکت را انتخاب کن.</div>'}</div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'پشتیبانی', admin, active: 'support', body, message, error }));
  });

  app.post('/admin/support/reply', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const ticketId = text(body, 'ticketId');
    const content = text(body, 'content');
    if (!ticketId || content.length < 1 || content.length > 5000) return reply.code(303).redirect('/admin/support?msg=invalid');
    await prisma.$transaction([
      prisma.supportMessage.create({ data: { ticketId, senderUserId: admin.id, isAdmin: true, content } }),
      prisma.supportTicket.update({ where: { id: ticketId }, data: { status: SupportStatus.PENDING_USER, lastMessageAt: new Date() } }),
    ]);
    await audit(prisma, admin.id, 'SUPPORT_REPLY', 'SupportTicket', ticketId, 'Admin replied to support ticket');
    return reply.code(303).redirect(`/admin/support?ticket=${encodeURIComponent(ticketId)}&msg=saved`);
  });

  app.post('/admin/support/status', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const ticketId = text(body, 'ticketId');
    const status = text(body, 'status') as SupportStatus;
    if (!ticketId || !Object.values(SupportStatus).includes(status)) return reply.code(303).redirect('/admin/support?msg=invalid');
    await prisma.supportTicket.update({ where: { id: ticketId }, data: { status } });
    await audit(prisma, admin.id, 'SUPPORT_STATUS_UPDATE', 'SupportTicket', ticketId, status);
    return reply.code(303).redirect(`/admin/support?ticket=${encodeURIComponent(ticketId)}&msg=saved`);
  });

  app.get('/admin/settings', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const settings = await prisma.systemSetting.findMany({ orderBy: [{ category: 'asc' }, { key: 'asc' }] });
    const [message, error] = messageFromQuery(request.query);
    const body = `<div class="card"><h3 class="section">تنظیم جدید / بروزرسانی</h3><div class="warn">مقادیر حساس مثل API Key را اینجا ذخیره نکن؛ کلیدهای Provider از بخش Provider و با رمزگذاری ذخیره می‌شوند.</div><form method="post" action="/admin/settings/save"><div class="grid2"><div class="field"><label>Key</label><input class="mono" name="key" placeholder="app.maintenance_mode" required></div><div class="field"><label>Category</label><input name="category" value="general"></div></div><div class="field"><label>Value (JSON)</label><textarea class="mono" name="value" placeholder='false یا {"x":1}' required></textarea></div><div class="field"><label>توضیح</label><input name="description"></div><button class="primary" type="submit">ذخیره Setting</button></form></div><div class="card table"><table><thead><tr><th>Category</th><th>Key</th><th>Value</th><th>Updated</th></tr></thead><tbody>${settings.map((s) => `<tr><td>${esc(s.category)}</td><td class="code">${esc(s.key)}</td><td class="code">${esc(JSON.stringify(s.value))}</td><td>${faDate(s.updatedAt)}</td></tr>`).join('')}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'تنظیمات سیستم', admin, active: 'settings', body, message, error }));
  });

  app.post('/admin/settings/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const body = request.body as AnyBody;
      const key = text(body, 'key');
      const category = text(body, 'category') || 'general';
      if (!/^[a-zA-Z0-9._-]{2,120}$/.test(key)) throw new Error('INVALID');
      const value = JSON.parse(text(body, 'value')) as Prisma.InputJsonValue;
      const description = text(body, 'description') || null;
      const saved = await prisma.systemSetting.upsert({ where: { key }, update: { category, value, description }, create: { key, category, value, description } });
      await audit(prisma, admin.id, 'SETTING_UPSERT', 'SystemSetting', saved.id, key);
      return reply.code(303).redirect('/admin/settings?msg=saved');
    } catch {
      return reply.code(303).redirect('/admin/settings?msg=invalid');
    }
  });

  app.get('/admin/readiness', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;

    let databaseHealthy = true;
    try {
      await prisma.$queryRaw`SELECT 1`;
    } catch {
      databaseHealthy = false;
    }

    const googleConfigured = Boolean(process.env.GOOGLE_WEB_CLIENT_ID?.trim());
    const providerEncryption = providerSecretEncryptionConfigured();
    const publicBaseUrl = process.env.PUBLIC_BASE_URL?.trim() || '';
    const publicBaseHttps = publicBaseUrl.startsWith('https://');
    const hesabPayKeyConfigured = Boolean(process.env.HESABPAY_API_KEY?.trim());
    const hesabPayEnvironment = process.env.HESABPAY_ENVIRONMENT?.trim() || 'sandbox';
    const hesabPayConfigured = hesabPayKeyConfigured && publicBaseHttps;
    const webhookUrl = publicBaseHttps
      ? `${publicBaseUrl.replace(/\/$/, '')}/api/v1/payments/hesabpay/webhook`
      : '—';

    const [providerCount, encryptedProviderCount] = await Promise.all([
      prisma.provider.count(),
      prisma.provider.count({
        where: {
          secretCiphertext: { not: null },
          secretIv: { not: null },
          secretTag: { not: null },
        },
      }),
    ]);

    const checks = [
      {
        label: 'Database',
        ok: databaseHealthy,
        detail: databaseHealthy ? 'اتصال PostgreSQL برقرار است.' : 'اتصال PostgreSQL ناموفق است.',
      },
      {
        label: 'Google Sign-In',
        ok: googleConfigured,
        detail: googleConfigured
          ? 'Web Client ID روی سرور تنظیم شده است.'
          : 'GOOGLE_WEB_CLIENT_ID روی سرور تنظیم نشده است.',
      },
      {
        label: 'Provider Secret Encryption',
        ok: providerEncryption,
        detail: providerEncryption
          ? 'AES-256-GCM برای ذخیره کلید Provider آماده است.'
          : 'ADMIN_SECRET_ENCRYPTION_KEY تنظیم نشده یا معتبر نیست.',
      },
      {
        label: 'Public HTTPS URL',
        ok: publicBaseHttps,
        detail: publicBaseHttps
          ? 'PUBLIC_BASE_URL برای callback/webhook با HTTPS تنظیم شده است.'
          : 'PUBLIC_BASE_URL امن هنوز تنظیم نشده است.',
      },
      {
        label: 'HesabPay',
        ok: hesabPayConfigured,
        detail: hesabPayConfigured
          ? `Gateway server config موجود است (${hesabPayEnvironment}).`
          : 'API Key و Public HTTPS URL هر دو برای فعال شدن پرداخت لازم هستند.',
      },
    ];

    const readyCount = checks.filter((item) => item.ok).length;
    const body = `<div class="warn">این صفحه فقط وضعیت «تنظیم شده / تنظیم نشده» را نشان می‌دهد و هیچ Secret، API Key یا Client ID را نمایش نمی‌دهد.</div><div class="statgrid" style="margin-top:14px"><div class="stat"><small>چک‌های آماده</small><b>${readyCount}/${checks.length}</b></div><div class="stat"><small>Provider ثبت‌شده</small><b>${providerCount}</b></div><div class="stat"><small>Provider با Secret رمزگذاری‌شده</small><b>${encryptedProviderCount}</b></div><div class="stat"><small>HesabPay Environment</small><b style="font-size:17px">${esc(hesabPayEnvironment)}</b></div></div><div class="card" style="margin-top:16px"><h3 class="section">Production Readiness</h3>${checks.map((item) => `<div class="note" style="display:flex;gap:12px;align-items:flex-start;margin-bottom:9px"><span class="badge ${item.ok ? 'okbadge' : 'badbadge'}">${item.ok ? 'READY' : 'MISSING'}</span><div><b>${esc(item.label)}</b><div class="muted" style="margin-top:4px">${esc(item.detail)}</div></div></div>`).join('')}</div><div class="card"><h3 class="section">HesabPay Webhook</h3><div class="muted">آدرس Webhook فقط وقتی PUBLIC_BASE_URL امن تنظیم باشد ساخته می‌شود.</div><div class="secret mono" style="margin-top:10px">${esc(webhookUrl)}</div><div class="muted" style="margin-top:10px">شارژ Wallet فقط بعد از Verify امضا + تطبیق مبلغ + Ledger idempotent انجام می‌شود؛ Redirect موفق به‌تنهایی Wallet را تغییر نمی‌دهد.</div></div>`;

    return reply.type('text/html; charset=utf-8').send(
      adminShell({ title: 'آمادگی سیستم', admin, active: 'readiness', body }),
    );
  });

  app.get('/admin/reports', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const start = new Date();
    start.setUTCDate(start.getUTCDate() - 30);
    const [completed, refunded, paymentPaid, newUsers, walletSum, byCategory] = await Promise.all([
      prisma.order.aggregate({
        where: { status: { in: [OrderStatus.COMPLETED, OrderStatus.PARTIAL] }, createdAt: { gte: start } },
        _sum: { totalAmountAfn: true, providerCostAfn: true },
        _count: { _all: true },
      }),
      prisma.order.aggregate({
        where: { status: OrderStatus.REFUNDED, updatedAt: { gte: start } },
        _sum: { totalAmountAfn: true },
        _count: { _all: true },
      }),
      prisma.paymentTransaction.aggregate({
        where: { status: 'PAID', paidAt: { gte: start } },
        _sum: { amountAfn: true },
        _count: { _all: true },
      }),
      prisma.user.count({ where: { createdAt: { gte: start } } }),
      prisma.wallet.aggregate({ _sum: { balanceAfn: true } }),
      prisma.order.groupBy({
        by: ['category'],
        where: { createdAt: { gte: start } },
        _count: { _all: true },
        _sum: { totalAmountAfn: true },
        orderBy: { _count: { category: 'desc' } },
      }),
    ]);
    const sales = completed._sum.totalAmountAfn ?? 0n;
    const cost = completed._sum.providerCostAfn ?? 0n;
    const profit = sales - cost;
    const body = `<div class="muted" style="margin-bottom:12px">خلاصه ۳۰ روز اخیر — محاسبات مالی بر پایه AFN</div><div class="statgrid"><div class="stat"><small>فروش تکمیل‌شده</small><b>${fmtAfn(sales)}</b><span class="muted">${completed._count._all} سفارش</span></div><div class="stat"><small>هزینه Provider ثبت‌شده</small><b>${fmtAfn(cost)}</b></div><div class="stat"><small>سود ناخالص ثبت‌شده</small><b>${fmtAfn(profit)}</b></div><div class="stat"><small>Refund</small><b>${fmtAfn(refunded._sum.totalAmountAfn ?? 0n)}</b><span class="muted">${refunded._count._all} سفارش</span></div></div><div class="grid2" style="margin-top:14px"><div class="stat"><small>پرداخت‌های تأییدشده</small><b>${fmtAfn(paymentPaid._sum.amountAfn ?? 0n)}</b><span class="muted">${paymentPaid._count._all} تراکنش</span></div><div class="stat"><small>موجودی کل Walletها</small><b>${fmtAfn(walletSum._sum.balanceAfn ?? 0n)}</b><span class="muted">${newUsers} کاربر جدید</span></div></div><div class="card table" style="margin-top:16px"><h3 class="section">عملکرد دسته‌ها</h3><table><thead><tr><th>دسته</th><th>تعداد سفارش</th><th>مبلغ</th></tr></thead><tbody>${byCategory.map((row) => `<tr><td>${row.category}</td><td>${row._count._all}</td><td>${fmtAfn(row._sum.totalAmountAfn ?? 0n)}</td></tr>`).join('') || '<tr><td colspan="3" class="muted">داده‌ای وجود ندارد.</td></tr>'}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'گزارش مالی', admin, active: 'reports', body }));
  });

  app.get('/admin/audit', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const logs = await prisma.adminAuditLog.findMany({ include: { adminUser: true }, orderBy: { createdAt: 'desc' }, take: 300 });
    const body = `<div class="card table"><table><thead><tr><th>زمان</th><th>مدیر</th><th>Action</th><th>Entity</th><th>خلاصه</th></tr></thead><tbody>${logs.map((l) => `<tr><td>${faDate(l.createdAt)}</td><td>${esc(l.adminUser.fullName || l.adminUser.email || l.adminUser.phone || 'ADMIN')}</td><td class="code">${esc(l.action)}</td><td>${esc(l.entityType)}<br><span class="muted code">${esc(l.entityId || '')}</span></td><td>${esc(l.summary)}</td></tr>`).join('')}</tbody></table></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'Audit Log مدیریت', admin, active: 'audit', body }));
  });

  app.get('/admin/overview', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const [users, activeServices, providers, orders, pendingTickets, payments] = await Promise.all([
      prisma.user.count(),
      prisma.service.count({ where: { enabled: true } }),
      prisma.provider.count({ where: { enabled: true } }),
      prisma.order.count(),
      prisma.supportTicket.count({ where: { status: { in: [SupportStatus.OPEN, SupportStatus.PENDING_ADMIN] } } }),
      prisma.paymentTransaction.count(),
    ]);
    const body = `<div class="statgrid"><div class="stat"><small>کاربران</small><b>${users}</b></div><div class="stat"><small>خدمات فعال</small><b>${activeServices}</b></div><div class="stat"><small>Provider فعال</small><b>${providers}</b></div><div class="stat"><small>سفارش‌ها</small><b>${orders}</b></div></div><div class="grid2" style="margin-top:14px"><div class="stat"><small>تیکت نیازمند بررسی</small><b>${pendingTickets}</b></div><div class="stat"><small>تراکنش پرداخت</small><b>${payments}</b></div></div>`;
    return reply.type('text/html; charset=utf-8').send(adminShell({ title: 'نمای کلی مدیریت', admin, active: 'dashboard', body }));
  });
}
