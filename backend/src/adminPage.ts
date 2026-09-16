type AdminUserRow = {
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
<html lang="en" dir="ltr">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1" />
<title>${esc(title)}</title>
<style>
:root{--p:#1686FF;--sky:#37B6FF;--bg:#F7F9FC;--card:#fff;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#18A875;--bad:#E65454;--nav:#0C1D33}*{box-sizing:border-box}body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif;background:var(--bg);color:var(--text)}button,input{font:inherit}.login{min-height:100vh;display:grid;place-items:center;padding:24px}.login-card{width:min(440px,100%);background:#fff;border:1px solid var(--line);border-radius:28px;padding:28px;box-shadow:0 22px 70px rgba(13,120,200,.10)}.brand{display:flex;gap:12px;align-items:center}.logo{width:46px;height:46px;border-radius:14px;background:linear-gradient(145deg,#4DB8FF,#0D78C8);display:grid;place-items:center;color:#fff;font-weight:900;font-size:22px}.brand b{font-size:20px;letter-spacing:1px}.sub{color:var(--muted);font-size:13px}.field{margin-top:14px}.field label{display:block;font-size:12px;color:var(--muted);margin-bottom:6px}.field input{width:100%;height:48px;border:1px solid var(--line);border-radius:14px;padding:0 14px;outline:none;background:#fff}.field input:focus{border-color:var(--p);box-shadow:0 0 0 3px rgba(13,120,200,.08)}.primary{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:#fff;height:48px;border-radius:14px;padding:0 18px;font-weight:800;cursor:pointer}.wide{width:100%;margin-top:18px}.err{color:var(--bad);font-size:13px;margin-top:12px;background:#fff0f0;border:1px solid #ffdada;border-radius:12px;padding:10px}.ok{color:#0b8a5c;font-size:13px;background:#e8f8f1;border:1px solid #c7efdc;border-radius:12px;padding:10px;margin-bottom:14px}.app{display:grid;grid-template-columns:244px 1fr;min-height:100vh}.side{background:var(--nav);color:#fff;padding:18px;position:sticky;top:0;height:100vh}.side .brand{margin-bottom:28px}.nav a,.nav button{display:block;width:100%;border:0;background:transparent;color:#cfe8fa;text-align:left;padding:13px 14px;border-radius:12px;margin:4px 0;cursor:pointer;text-decoration:none}.nav a.active,.nav a:hover,.nav button:hover{background:rgba(49,168,255,.16);color:#fff}.logout{color:#ffced0!important}.main{padding:24px;min-width:0}.top{display:flex;justify-content:space-between;gap:16px;align-items:center;margin-bottom:20px}.top h1{font-size:24px;margin:0}.chip{font-size:12px;padding:7px 10px;border-radius:999px;background:#eaf6ff;color:var(--p)}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.stat,.card{background:#fff;border:1px solid var(--line);border-radius:16px;padding:18px}.stat span{color:var(--muted);font-size:12px}.stat strong{display:block;margin-top:8px;font-size:24px}.card{margin-top:16px}.toolbar{display:flex;gap:10px;flex-wrap:wrap;align-items:end}.toolbar .field{margin-top:0;min-width:260px;flex:1}.ghost{height:44px;border:1px solid var(--line);background:#fff;border-radius:12px;padding:0 13px;cursor:pointer;text-decoration:none;color:var(--text);display:inline-grid;place-items:center}.table-wrap{overflow:auto;margin-top:14px}table{width:100%;border-collapse:collapse;min-width:760px}th,td{padding:12px 10px;border-bottom:1px solid #edf3f7;text-align:left;font-size:13px}th{color:var(--muted);font-weight:700}.money{font-weight:900;color:var(--p)}.badge{display:inline-block;padding:5px 8px;border-radius:999px;font-size:11px;background:#eef3f7}.badge.admin{background:#e8f8f1;color:#0b8a5c}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.info{background:#f7fbff;border:1px solid var(--line);border-radius:14px;padding:12px;margin:8px 0}.info small{display:block;color:var(--muted)}.info b{display:block;margin-top:4px}.section-title{font-weight:900;margin:18px 0 8px}.tx{display:flex;justify-content:space-between;gap:10px;padding:11px 0;border-bottom:1px solid #edf3f7}.tx small{color:var(--muted)}.pos{color:var(--ok);font-weight:800}.neg{color:var(--bad);font-weight:800}.inline-form{margin:0}.ratebox input{width:100%;height:44px;border:1px solid var(--line);border-radius:12px;padding:0 12px;margin-top:8px}.ratebox .primary{margin-top:10px}.danger-note{color:#8d5614;background:#fff7e8;border:1px solid #ffe3ae;border-radius:12px;padding:10px;font-size:13px}@media(max-width:900px){.app{grid-template-columns:1fr}.side{height:auto;position:static}.nav{display:flex;overflow:auto;gap:4px}.nav a,.nav button{white-space:nowrap;width:auto}.stats{grid-template-columns:1fr 1fr}.main{padding:16px}}@media(max-width:540px){.stats,.grid2{grid-template-columns:1fr}.toolbar .field{min-width:100%}}
</style>
</head>
<body>${body}</body>
</html>`;

export function adminLoginHtml(error?: string) {
  return shell(`<section class="login"><div class="login-card"><div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub">Secure Admin Console</div></div></div><h2>Admin sign in</h2><div class="sub">Secure server-side authentication for VELIXEO management.</div><form method="post" action="/admin/login" autocomplete="on"><div class="field"><label for="identifier">Email or phone</label><input id="identifier" name="identifier" autocomplete="username" required></div><div class="field"><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" required></div><button class="primary wide" type="submit">Sign in to Admin</button>${error ? `<div class="err">${esc(error)}</div>` : ''}</form></div></section>`);
}

function usersTable(users: AdminUserRow[]) {
  if (!users.length) return '<div class="sub" style="margin-top:14px">No users found.</div>';
  return `<div class="table-wrap"><table><thead><tr><th>Name</th><th>ایمیل/شماره</th><th>Balance</th><th>Role</th><th>Joined</th><th></th></tr></thead><tbody>${users.map((u) => `<tr><td>${esc(u.fullName || '—')}</td><td>${esc(u.email || u.phone || '—')}</td><td class="money">${fmt(u.balanceAfn)}</td><td><span class="badge ${u.role === 'ADMIN' ? 'admin' : ''}">${esc(u.role)}</span></td><td>${esc(dateFa(u.createdAt))}</td><td><a class="ghost" href="/admin?view=users&user=${encodeURIComponent(u.id)}">View</a></td></tr>`).join('')}</tbody></table></div>`;
}

function selectedUserCard(user: AdminSelectedUser) {
  return `<div class="card"><div class="section-title" style="margin-top:0">User details</div><div class="grid2"><div class="info"><small>Name</small><b>${esc(user.fullName || '—')}</b></div><div class="info"><small>Role</small><b>${esc(user.role)}</b></div></div><div class="info"><small>ایمیل / شماره</small><b>${esc(user.email || user.phone || '—')}</b></div><div class="info"><small>Balance فعلی</small><b class="money">${fmt(user.balanceAfn)}</b></div><div class="section-title">Manual wallet adjustment</div><div class="danger-note">برای کسر Balance، مبلغ را با علامت منفی وارد کن. هر تغییر در Ledger ثبت می‌شود و بدون سابقه Balance تغییر نمی‌کند.</div><form method="post" action="/admin/wallet-adjust"><input type="hidden" name="userId" value="${esc(user.id)}"><div class="grid2"><div class="field"><label>Amount (AFN)</label><input name="amountAfn" type="number" step="1" placeholder="مثلاً 1500 یا -500" required></div><div class="field"><label>Reason</label><input name="reason" placeholder="مثلاً پرداخت حضوری" minlength="3" maxlength="300" required></div></div><button class="primary wide" type="submit">Save wallet adjustment</button></form><div class="section-title">Recent transactions</div>${user.walletEntries.length ? user.walletEntries.map((x) => `<div class="tx"><div><b>${esc(x.description || x.type)}</b><br><small>${esc(dateFa(x.createdAt))}</small></div><div class="${Number(x.amountAfn) >= 0 ? 'pos' : 'neg'}">${Number(x.amountAfn) > 0 ? '+' : ''}${fmt(x.amountAfn)}</div></div>`).join('') : '<div class="sub">هنوز تراکنشی ثبت نشده است.</div>'}</div>`;
}

export function adminDashboardHtml(model: AdminDashboardModel) {
  const titles = { dashboard: 'Dashboard', users: 'Users', rates: 'Exchange Rates', providers: 'API & Providers' } as const;
  const nav = (view: AdminDashboardModel['view'], label: string) => `<a class="${model.view === view ? 'active' : ''}" href="/admin?view=${view}">${label}</a>`;
  let content = '';
  if (model.view === 'dashboard') {
    content = `<div class="stats"><div class="stat"><span>کل Users</span><strong>${model.totalUsers}</strong></div><div class="stat"><span>ثبت‌Name امروز</span><strong>${model.usersToday}</strong></div><div class="stat"><span>Balance کل کیف پول‌ها</span><strong>${fmt(model.totalWalletBalanceAfn)}</strong></div><div class="stat"><span>Admins</span><strong>${model.totalAdmins}</strong></div></div><div class="card"><b>آخرین Users</b>${usersTable(model.users)}</div>`;
  } else if (model.view === 'users') {
    content = `<div class="card"><form method="get" action="/admin" class="toolbar"><input type="hidden" name="view" value="users"><div class="field"><label>Search</label><input name="q" value="${esc(model.q || '')}" placeholder="Name، Email or phone"></div><button class="primary" type="submit">Search</button><a class="ghost" href="/admin?view=users">Clear</a></form>${usersTable(model.users)}</div>${model.selectedUser ? selectedUserCard(model.selectedUser) : ''}`;
  } else if (model.view === 'rates') {
    const usd = model.rates.find((r) => r.code === 'USD')?.afnPerUnit || '';
    const toman = model.rates.find((r) => r.code === 'TOMAN')?.afnPerUnit || '';
    content = `<div class="card"><b>Display exchange rates</b><p class="sub">واحد پایه همیشه AFN است. تغییر نرخ روی Ordersی قدیمی اثر نمی‌گذارد.</p><div class="grid2"><form class="ratebox" method="post" action="/admin/rates"><input type="hidden" name="code" value="USD"><label>AFN به ازای 1 USD</label><input name="afnPerUnit" inputmode="decimal" value="${esc(usd)}" required><button class="primary" type="submit">Save USD</button></form><form class="ratebox" method="post" action="/admin/rates"><input type="hidden" name="code" value="TOMAN"><label>AFN به ازای 1 TOMAN</label><input name="afnPerUnit" inputmode="decimal" value="${esc(toman)}" required><button class="primary" type="submit">Save TOMAN</button></form></div></div>`;
  } else {
    content = `<div class="card"><b>API & Providers</b><p class="sub">این بخش برای HesabPay، Social، Virtual Number، Top-up و Premium آماده شده است. کلیدهای Provider فقط در Backend نگهداری خواهند شد و هیچ API Key داخل APK قرار نمی‌گیرد.</p></div>`;
  }

  const msg = model.message === 'wallet_updated' ? 'تغییر Wallet با موفقیت ثبت شد.' : model.message === 'rate_updated' ? 'نرخ با موفقیت ذخیره شد.' : model.message === 'insufficient_funds' ? 'Balance کاربر برای این مقدار کسر کافی نیست.' : model.message === 'invalid_request' ? 'اطلاعات واردشده معتبر نیست.' : '';

  return shell(`<section class="app"><aside class="side"><div class="brand"><div class="logo">V</div><div><b>VELIXEO</b><div class="sub" style="color:#9fc2db">Admin Console</div></div></div><nav class="nav">${nav('dashboard','Dashboard')}${nav('users','Users')}<a href="/admin/social">Social Media</a><a href="/admin/virtual-numbers">Virtual Numbers & SMS</a><a href="/admin/services?category=PREMIUM">Premium Subscriptions</a><a href="/admin/services?category=MOBILE_TOPUP">Mobile Top-up</a><a href="/admin/services?category=DIGITAL_ACCOUNT">Digital Accounts</a><a href="/admin/services?category=PROMOTION">Promotions</a><a href="/admin/orders">Orders</a><a href="/admin/payments">Payments & Wallet</a><a href="/admin/coupons">Coupons</a><a href="/admin/banners">Banners & Advertising</a><a href="/admin/notifications">Notifications</a><a href="/admin/support">Support</a>${nav('rates','Exchange Rates')}<a href="/admin/settings">Settings</a><a href="/admin/audit">Audit Log</a><form class="inline-form" method="post" action="/admin/logout"><button class="logout" type="submit">Sign out</button></form></nav></aside><main class="main"><div class="top"><div><h1>${titles[model.view]}</h1><div class="sub">VELIXEO Admin Console — secure server-rendered management</div></div><span class="chip">${esc(model.adminIdentity)}</span></div>${msg ? `<div class="${model.message === 'insufficient_funds' || model.message === 'invalid_request' ? 'err' : 'ok'}">${esc(msg)}</div>` : ''}${content}</main></section>`);
}
