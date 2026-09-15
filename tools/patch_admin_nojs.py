from pathlib import Path

admin = r'''type AdminUserRow = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
  role: string;
  balanceAfn: string;
  createdAt: string | Date;
};

type AdminWalletEntry = {
  id: string;
  type: string;
  status: string;
  amountAfn: string;
  balanceAfterAfn: string;
  description: string | null;
  createdAt: string | Date;
};

type AdminSelectedUser = AdminUserRow & { walletEntries: AdminWalletEntry[] };

type AdminRate = { code: string; afnPerUnit: string; updatedAt: string | Date };

type AdminDashboardModel = {
  adminIdentity: string;
  view: 'dashboard' | 'users' | 'rates' | 'providers';
  totalUsers: number;
  usersToday: number;
  totalAdmins: number;
  totalWalletBalanceAfn: string;
  users: AdminUserRow[];
  q?: string;
  selectedUser?: AdminSelectedUser | null;
  rates: AdminRate[];
  message?: string;
};

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const fmt = (value: string | number | bigint) =>
  `${Number(value || 0).toLocaleString('en-US')} AFN`;

const dateFa = (value: string | Date) => {
  try {
    return new Date(value).toLocaleString('fa-IR');
  } catch {
    return '—';
  }
};

const shell = (body: string, title = 'VELIXEO Admin') => `<!doctype html>
<html lang="fa" dir="rtl">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>${esc(title)}</title>
<style>
:root{--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;--card:#fff;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#18A875;--bad:#E65454;--nav:#0D2640}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;background:var(--bg);color:var(--text)}button,input{font:inherit}.login{min-height:100vh;display:grid;place-items:center;padding:24px}.login-card{width:min(440px,100%);background:#fff;border:1px solid var(--line);border-radius:28px;padding:28px;box-shadow:0 22px 70px rgba(13,120,200,.10)}.brand{display:flex;gap:12px;align-items:center}.logo{width:46px;height:46px;border-radius:14px;background:linear-gradient(145deg,#4DB8FF,#0D78C8);display:grid;place-items:center;color:#fff;font-weight:900;font-size:22px}.brand b{font-size:20px;letter-spacing:1px}.sub{color:var(--muted);font-size:13px}.field{margin-top:14px}.field label{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}.field input{width:100%;height:48px;border:1px solid var(--line);border-radius:14px;padding:0 14px;outline:none;background:#fff}.field input:focus{border-color:var(--p);box-shadow:0 0 0 3px rgba(13,120,200,.08)}.primary{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:#fff;height:48px;border-radius:14px;padding:0 18px;font-weight:800;cursor:pointer}.wide{width:100%;margin-top:18px}.err{color:var(--bad);font-size:13px;margin-top:12px;background:#fff0f0;border:1px solid #ffdada;border-radius:12px;padding:10px}.ok{color:#0b8a5c;font-size:13px;background:#e8f8f1;border:1px solid #c7efdc;border-radius:12px;padding:10px;margin-bottom:14px}.app{display:grid;grid-template-columns:250px 1fr;min-height:100vh}.side{background:var(--nav);color:#fff;padding:18px;position:sticky;top:0;height:100vh}.side .brand{margin-bottom:28px}.nav a,.nav button{display:block;width:100%;border:0;background:transparent;color:#cfe8fa;text-align:right;padding:13px 14px;border-radius:12px;margin:4px 0;cursor:pointer;text-decoration:none}.nav a.active,.nav a:hover,.nav button:hover{background:rgba(49,168,255,.16);color:#fff}.logout{color:#ffced0!important}.main{padding:24px;min-width:0}.top{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-bottom:20px}.top h1{font-size:24px;margin:0}.chip{font-size:12px;padding:7px 10px;border-radius:999px;background:#eaf6ff;color:var(--p)}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.stat,.card{background:#fff;border:1px solid var(--line);border-radius:20px;padding:18px}.stat span{color:var(--muted);font-size:12px}.stat strong{display:block;margin-top:8px;font-size:24px}.card{margin-top:16px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:end}.toolbar .field{margin-top:0;min-width:260px;flex:1}.ghost{height:44px;border:1px solid var(--line);background:#fff;border-radius:12px;padding:0 13px;cursor:pointer;text-decoration:none;color:var(--text);display:inline-grid;place-items:center}.table-wrap{overflow:auto;margin-top:14px}table{width:100%;border-collapse:collapse;min-width:760px}th,td{padding:12px 10px;border-bottom:1px solid #edf3f7;text-align:right;font-size:13px}th{color:var(--muted);font-weight:700}.money{font-weight:900;color:var(--p)}.badge{display:inline-block;padding:5px 8px;border-radius:999px;font-size:11px;background:#eef3f7}.badge.admin{background:#e8f8f1;color:#0b8a5c}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.info{background:#f7fbff;border:1px solid var(--line);border-radius:14px;padding:12px;margin:8px 0}.info small{display:block;color:var(--muted)}.info b{display:block;margin-top:4px}.section-title{font-weight:900;margin:18px 0 8px}.tx{display:flex;justify-content:space-between;gap:10px;padding:11px 0;border-bottom:1px solid #edf3f7}.tx small{color:var(--muted)}.pos{color:var(--ok);font-weight:800}.neg{color:var(--bad);font-weight:800}.inline-form{margin:0}.ratebox input{width:100%;height:44px;border:1px solid var(--line);border-radius:12px;padding:0 12px;margin-top:8px}.ratebox .primary{margin-top:10px}.danger-note{color:#8d5614;background:#fff7e8;border:1px solid #ffe3ae;border-radius:12px;padding:10px;font-size:13px}@media(max-width:900px){.app{grid-template-columns:1fr}.side{height:auto;position:static}.nav{display:flex;overflow:auto;gap:4px}.nav a,.nav button{white-space:nowrap;width:auto}.stats{grid-template-columns:1fr 1fr}.main{padding:16px}}@media(max-width:540px){.stats,.grid2{grid-template-columns:1fr}.toolbar .field{min-width:100%}}
</style>
</head>
<body>${body}</body>
</html>`;

export function adminLoginHtml(error?: string) {
  return shell(`<section class="login"><div class="login-card"><div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub">پنل مدیریت امن</div></div></div><h2>ورود مدیر</h2><div class="sub">ورود این صفحه کاملاً سمت سرور انجام می‌شود و به JavaScript وابسته نیست.</div><form method="post" action="/admin/login" autocomplete="on"><div class="field"><label for="identifier">ایمیل یا شماره</label><input id="identifier" name="identifier" autocomplete="username" required></div><div class="field"><label for="password">رمز عبور</label><input id="password" name="password" type="password" autocomplete="current-password" required></div><button class="primary wide" type="submit">ورود به پنل</button>${error ? `<div class="err">${esc(error)}</div>` : ''}</form></div></section>`);
}

function usersTable(users: AdminUserRow[]) {
  if (!users.length) return '<div class="sub" style="margin-top:14px">کاربری پیدا نشد.</div>';
  return `<div class="table-wrap"><table><thead><tr><th>نام</th><th>ایمیل/شماره</th><th>موجودی</th><th>نقش</th><th>عضویت</th><th></th></tr></thead><tbody>${users.map((u) => `<tr><td>${esc(u.fullName || '—')}</td><td>${esc(u.email || u.phone || '—')}</td><td class="money">${fmt(u.balanceAfn)}</td><td><span class="badge ${u.role === 'ADMIN' ? 'admin' : ''}">${esc(u.role)}</span></td><td>${esc(dateFa(u.createdAt))}</td><td><a class="ghost" href="/admin?view=users&user=${encodeURIComponent(u.id)}">مشاهده</a></td></tr>`).join('')}</tbody></table></div>`;
}

function selectedUserCard(user: AdminSelectedUser) {
  return `<div class="card"><div class="section-title" style="margin-top:0">جزئیات کاربر</div><div class="grid2"><div class="info"><small>نام</small><b>${esc(user.fullName || '—')}</b></div><div class="info"><small>نقش</small><b>${esc(user.role)}</b></div></div><div class="info"><small>ایمیل / شماره</small><b>${esc(user.email || user.phone || '—')}</b></div><div class="info"><small>موجودی فعلی</small><b class="money">${fmt(user.balanceAfn)}</b></div><div class="section-title">افزایش / کسر دستی Wallet</div><div class="danger-note">برای کسر موجودی، مبلغ را با علامت منفی وارد کن. هر تغییر در Ledger ثبت می‌شود و بدون سابقه موجودی تغییر نمی‌کند.</div><form method="post" action="/admin/wallet-adjust"><input type="hidden" name="userId" value="${esc(user.id)}"><div class="grid2"><div class="field"><label>مبلغ AFN</label><input name="amountAfn" type="number" step="1" placeholder="مثلاً 1500 یا -500" required></div><div class="field"><label>دلیل عملیات</label><input name="reason" placeholder="مثلاً پرداخت حضوری" minlength="3" maxlength="300" required></div></div><button class="primary wide" type="submit">ثبت تغییر کیف پول</button></form><div class="section-title">آخرین تراکنش‌ها</div>${user.walletEntries.length ? user.walletEntries.map((x) => `<div class="tx"><div><b>${esc(x.description || x.type)}</b><br><small>${esc(dateFa(x.createdAt))}</small></div><div class="${Number(x.amountAfn) >= 0 ? 'pos' : 'neg'}">${Number(x.amountAfn) > 0 ? '+' : ''}${fmt(x.amountAfn)}</div></div>`).join('') : '<div class="sub">هنوز تراکنشی ثبت نشده است.</div>'}</div>`;
}

export function adminDashboardHtml(model: AdminDashboardModel) {
  const titles = { dashboard: 'داشبورد', users: 'کاربران', rates: 'نرخ ارز', providers: 'API و Providerها' } as const;
  const nav = (view: AdminDashboardModel['view'], label: string) => `<a class="${model.view === view ? 'active' : ''}" href="/admin?view=${view}">${label}</a>`;
  let content = '';
  if (model.view === 'dashboard') {
    content = `<div class="stats"><div class="stat"><span>کل کاربران</span><strong>${model.totalUsers}</strong></div><div class="stat"><span>ثبت‌نام امروز</span><strong>${model.usersToday}</strong></div><div class="stat"><span>موجودی کل کیف پول‌ها</span><strong>${fmt(model.totalWalletBalanceAfn)}</strong></div><div class="stat"><span>مدیران</span><strong>${model.totalAdmins}</strong></div></div><div class="card"><b>آخرین کاربران</b>${usersTable(model.users)}</div>`;
  } else if (model.view === 'users') {
    content = `<div class="card"><form method="get" action="/admin" class="toolbar"><input type="hidden" name="view" value="users"><div class="field"><label>جستجو</label><input name="q" value="${esc(model.q || '')}" placeholder="نام، ایمیل یا شماره"></div><button class="primary" type="submit">جستجو</button><a class="ghost" href="/admin?view=users">پاک کردن</a></form>${usersTable(model.users)}</div>${model.selectedUser ? selectedUserCard(model.selectedUser) : ''}`;
  } else if (model.view === 'rates') {
    const usd = model.rates.find((r) => r.code === 'USD')?.afnPerUnit || '';
    const toman = model.rates.find((r) => r.code === 'TOMAN')?.afnPerUnit || '';
    content = `<div class="card"><b>نرخ‌های نمایش</b><p class="sub">واحد پایه همیشه AFN است. تغییر نرخ روی سفارش‌های قدیمی اثر نمی‌گذارد.</p><div class="grid2"><form class="ratebox" method="post" action="/admin/rates"><input type="hidden" name="code" value="USD"><label>AFN به ازای 1 USD</label><input name="afnPerUnit" inputmode="decimal" value="${esc(usd)}" required><button class="primary" type="submit">ذخیره USD</button></form><form class="ratebox" method="post" action="/admin/rates"><input type="hidden" name="code" value="TOMAN"><label>AFN به ازای 1 TOMAN</label><input name="afnPerUnit" inputmode="decimal" value="${esc(toman)}" required><button class="primary" type="submit">ذخیره TOMAN</button></form></div></div>`;
  } else {
    content = `<div class="card"><b>API و Providerها</b><p class="sub">این بخش برای HesabPay، Social، Virtual Number، Top-up و Premium آماده شده است. کلیدهای Provider فقط در Backend نگهداری خواهند شد و هیچ API Key داخل APK قرار نمی‌گیرد.</p></div>`;
  }

  const msg = model.message === 'wallet_updated' ? 'تغییر Wallet با موفقیت ثبت شد.' : model.message === 'rate_updated' ? 'نرخ با موفقیت ذخیره شد.' : model.message === 'insufficient_funds' ? 'موجودی کاربر برای این مقدار کسر کافی نیست.' : model.message === 'invalid_request' ? 'اطلاعات واردشده معتبر نیست.' : '';

  return shell(`<section class="app"><aside class="side"><div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub" style="color:#9fc2db">Admin Console</div></div></div><nav class="nav">${nav('dashboard','داشبورد')}${nav('users','کاربران')}${nav('rates','نرخ ارز')}${nav('providers','API و Providerها')}<form class="inline-form" method="post" action="/admin/logout"><button class="logout" type="submit">خروج</button></form></nav></aside><main class="main"><div class="top"><div><h1>${titles[model.view]}</h1><div class="sub">مدیریت واقعی VELIXEO — بدون وابستگی به JavaScript</div></div><span class="chip">${esc(model.adminIdentity)}</span></div>${msg ? `<div class="${model.message === 'insufficient_funds' || model.message === 'invalid_request' ? 'err' : 'ok'}">${esc(msg)}</div>` : ''}${content}</main></section>`);
}
'''

Path('backend/src/adminPage.ts').write_text(admin, encoding='utf-8')

p = Path('backend/src/index.ts')
s = p.read_text(encoding='utf-8')
s = s.replace("import { adminHtml } from './adminPage.js';", "import { adminDashboardHtml, adminLoginHtml } from './adminPage.js';")

anchor = """await app.register(rateLimit, {\n  max: 120,\n  timeWindow: '1 minute',\n});\n"""
parser = """await app.register(rateLimit, {\n  max: 120,\n  timeWindow: '1 minute',\n});\n\napp.addContentTypeParser(\n  'application/x-www-form-urlencoded',\n  { parseAs: 'string' },\n  (_request, body, done) => {\n    try {\n      done(null, Object.fromEntries(new URLSearchParams(String(body))));\n    } catch (error) {\n      done(error as Error, undefined);\n    }\n  },\n);\n"""
if anchor not in s:
    raise SystemExit('rate-limit anchor not found')
s = s.replace(anchor, parser, 1)

old_route = """app.get('/admin', async (_request, reply) => {\n  return reply.type('text/html; charset=utf-8').send(adminHtml);\n});\n"""
new_routes = r'''const adminWebCookieName = 'velixeo_admin';

type AdminWebClaims = JwtClaims & { scope?: string };

function parseCookies(header?: string) {
  const out: Record<string, string> = {};
  for (const part of (header ?? '').split(';')) {
    const index = part.indexOf('=');
    if (index <= 0) continue;
    const key = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    try {
      out[key] = decodeURIComponent(value);
    } catch {
      out[key] = value;
    }
  }
  return out;
}

async function adminWebUser(request: FastifyRequest) {
  const token = parseCookies(request.headers.cookie)[adminWebCookieName];
  if (!token) return null;
  try {
    const claims = app.jwt.verify<AdminWebClaims>(token);
    if (claims.scope !== 'admin-web' || claims.role !== UserRole.ADMIN) return null;
    return prisma.user.findFirst({
      where: { id: claims.sub, role: UserRole.ADMIN },
      include: { wallet: true },
    });
  } catch {
    return null;
  }
}

function adminCookie(token: string, maxAge = 8 * 60 * 60) {
  return `${adminWebCookieName}=${encodeURIComponent(token)}; Path=/admin; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;
}

app.get('/admin', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (!admin) return reply.type('text/html; charset=utf-8').send(adminLoginHtml());

  const query = z
    .object({
      view: z.enum(['dashboard', 'users', 'rates', 'providers']).default('dashboard'),
      q: z.string().trim().max(120).optional(),
      user: z.string().uuid().optional(),
      msg: z.string().max(40).optional(),
    })
    .safeParse(request.query);
  const view = query.success ? query.data.view : 'dashboard';
  const q = query.success ? query.data.q : undefined;
  const selectedUserId = query.success ? query.data.user : undefined;
  const message = query.success ? query.data.msg : undefined;

  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const where: Prisma.UserWhereInput = q
    ? {
        OR: [
          { fullName: { contains: q, mode: 'insensitive' } },
          { email: { contains: q, mode: 'insensitive' } },
          { phone: { contains: q, mode: 'insensitive' } },
        ],
      }
    : {};

  const [totalUsers, usersToday, totalAdmins, walletAggregate, users, rates, selectedUser] =
    await Promise.all([
      prisma.user.count(),
      prisma.user.count({ where: { createdAt: { gte: dayStart } } }),
      prisma.user.count({ where: { role: UserRole.ADMIN } }),
      prisma.wallet.aggregate({ _sum: { balanceAfn: true } }),
      prisma.user.findMany({
        where: view === 'users' ? where : {},
        orderBy: { createdAt: 'desc' },
        take: view === 'users' ? 100 : 8,
        include: { wallet: true },
      }),
      prisma.exchangeRate.findMany({ orderBy: { code: 'asc' } }),
      selectedUserId
        ? prisma.user.findUnique({
            where: { id: selectedUserId },
            include: {
              wallet: {
                include: { entries: { orderBy: { createdAt: 'desc' }, take: 30 } },
              },
            },
          })
        : Promise.resolve(null),
    ]);

  return reply.type('text/html; charset=utf-8').send(
    adminDashboardHtml({
      adminIdentity: admin.fullName || admin.email || admin.phone || 'ADMIN',
      view,
      totalUsers,
      usersToday,
      totalAdmins,
      totalWalletBalanceAfn: (walletAggregate._sum.balanceAfn ?? 0n).toString(),
      q,
      message,
      users: users.map((user) => ({
        ...publicUser(user),
        balanceAfn: (user.wallet?.balanceAfn ?? 0n).toString(),
      })),
      rates: rates.map((rate) => ({
        code: rate.code,
        afnPerUnit: rate.afnPerUnit.toString(),
        updatedAt: rate.updatedAt,
      })),
      selectedUser: selectedUser
        ? {
            ...publicUser(selectedUser),
            balanceAfn: (selectedUser.wallet?.balanceAfn ?? 0n).toString(),
            walletEntries: (selectedUser.wallet?.entries ?? []).map((entry) => ({
              id: entry.id,
              type: entry.type,
              status: entry.status,
              amountAfn: entry.amountAfn.toString(),
              balanceAfterAfn: entry.balanceAfterAfn.toString(),
              description: entry.description,
              createdAt: entry.createdAt,
            })),
          }
        : null,
    }),
  );
});

app.post('/admin/login', async (request, reply) => {
  const parsed = loginSchema.safeParse(request.body);
  if (!parsed.success) {
    return reply.code(400).type('text/html; charset=utf-8').send(adminLoginHtml('ایمیل/شماره و رمز را درست وارد کنید.'));
  }
  const rawIdentifier = parsed.data.identifier;
  const emailIdentifier = rawIdentifier.includes('@') ? rawIdentifier.toLowerCase() : '__not_an_email__';
  const phoneIdentifier = normalizePhone(rawIdentifier) ?? rawIdentifier;
  const user = await prisma.user.findFirst({
    where: { OR: [{ email: emailIdentifier }, { phone: phoneIdentifier }] },
  });
  if (!user || !(await bcrypt.compare(parsed.data.password, user.passwordHash))) {
    return reply.code(401).type('text/html; charset=utf-8').send(adminLoginHtml('ایمیل/شماره یا رمز عبور نادرست است.'));
  }
  if (user.role !== UserRole.ADMIN) {
    return reply.code(403).type('text/html; charset=utf-8').send(adminLoginHtml('این حساب دسترسی مدیر ندارد.'));
  }
  const token = app.jwt.sign(
    { sub: user.id, role: user.role, scope: 'admin-web' },
    { expiresIn: '8h' },
  );
  reply.header('Set-Cookie', adminCookie(token));
  return reply.code(303).redirect('/admin');
});

app.post('/admin/logout', async (_request, reply) => {
  reply.header('Set-Cookie', adminCookie('', 0));
  return reply.code(303).redirect('/admin');
});

app.post('/admin/wallet-adjust', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (!admin) return reply.code(303).redirect('/admin');
  const parsed = adminAdjustmentSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(303).redirect('/admin?view=users&msg=invalid_request');
  const amountAfn = BigInt(parsed.data.amountAfn);
  if (amountAfn === 0n) return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=invalid_request`);
  try {
    await applyWalletDelta({
      userId: parsed.data.userId,
      amountAfn,
      type: amountAfn > 0n ? WalletEntryType.MANUAL_CREDIT : WalletEntryType.MANUAL_DEBIT,
      description: parsed.data.reason,
      idempotencyKey: `admin-web-${admin.id}-${Date.now()}-${randomBytes(6).toString('hex')}`,
      referenceType: 'ADMIN_ADJUSTMENT',
      referenceId: admin.id,
    });
    return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=wallet_updated`);
  } catch (error) {
    if (error instanceof Error && error.message === 'INSUFFICIENT_FUNDS') {
      return reply.code(303).redirect(`/admin?view=users&user=${encodeURIComponent(parsed.data.userId)}&msg=insufficient_funds`);
    }
    throw error;
  }
});

app.post('/admin/rates', async (request, reply) => {
  const admin = await adminWebUser(request);
  if (!admin) return reply.code(303).redirect('/admin');
  const parsed = rateSchema.safeParse(request.body);
  if (!parsed.success) return reply.code(303).redirect('/admin?view=rates&msg=invalid_request');
  await prisma.exchangeRate.upsert({
    where: { code: parsed.data.code },
    update: { afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit) },
    create: { code: parsed.data.code, afnPerUnit: new Prisma.Decimal(parsed.data.afnPerUnit) },
  });
  return reply.code(303).redirect('/admin?view=rates&msg=rate_updated');
});
'''

if old_route not in s:
    raise SystemExit('old admin route not found')
s = s.replace(old_route, new_routes, 1)
p.write_text(s, encoding='utf-8')
print('Applied no-JS admin console patch')
