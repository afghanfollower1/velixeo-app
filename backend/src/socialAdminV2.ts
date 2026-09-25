import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
} from '@prisma/client';
import {
  encryptProviderSecret,
  providerSecretEncryptionConfigured,
} from './providerSecrets.js';
import { smmClientForProvider } from './smmPanelAdapter.js';
import {
  convertSocialPriceToAfn,
  getSocialProviderSyncConfig,
  saveSocialProviderSyncConfig,
  socialRouteSaleRateAfn,
  syncSocialProviderCatalog,
} from './socialSync.js';

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};

type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type AnyBody = Record<string, unknown>;

type SocialCategoryDefinition = {
  slug: string;
  titleFa: string;
  titleEn: string;
  platform: string;
  descriptionFa: string;
  descriptionEn: string;
  sortOrder: number;
  enabled: boolean;
};

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const text = (body: AnyBody, key: string) => String(body[key] ?? '').trim();
const checked = (body: AnyBody, key: string) =>
  body[key] === 'on' || body[key] === 'true' || body[key] === '1';

function intValue(value: unknown, fallback: number) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function decimalValue(value: unknown, fallback = '0') {
  const raw = String(value ?? '').trim();
  return /^\d+(\.\d{1,8})?$/.test(raw) ? raw : fallback;
}

function jsonObject(value: Prisma.JsonValue | null | undefined): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function faDate(value: Date | string | null | undefined) {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('fa-IR');
  } catch {
    return '—';
  }
}

function fmtAfn(value: bigint | number | string | null | undefined) {
  return `${Number(value ?? 0).toLocaleString('en-US')} AFN`;
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
    data: { adminUserId: adminId, action, entityType, entityId, summary, metadata },
  });
}

function categoryKey(slug: string) {
  return `social.category.${slug}`;
}

function normalizeSlug(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

type CatalogSortMode = 'PRICE_ASC' | 'PRICE_DESC' | 'MANUAL';
const CATALOG_SORT_SETTING_KEY = 'social.catalog.sort_mode';

function normalizeCatalogSortMode(value: unknown): CatalogSortMode {
  const mode = String(value ?? '').trim().toUpperCase();
  if (mode === 'PRICE_DESC' || mode === 'MANUAL') return mode;
  return 'PRICE_ASC';
}

async function loadCatalogSortMode(prisma: PrismaClient): Promise<CatalogSortMode> {
  const row = await prisma.systemSetting.findUnique({ where: { key: CATALOG_SORT_SETTING_KEY } });
  const value = jsonObject(row?.value ?? {});
  return normalizeCatalogSortMode(value.mode);
}

function parseCategory(setting: {
  key: string;
  value: Prisma.JsonValue;
}): SocialCategoryDefinition | null {
  const row = jsonObject(setting.value);
  const slug = typeof row.slug === 'string'
    ? row.slug
    : setting.key.replace(/^social\.category\./, '');
  if (!slug) return null;
  return {
    slug,
    titleFa: typeof row.titleFa === 'string' ? row.titleFa : slug,
    titleEn: typeof row.titleEn === 'string' ? row.titleEn : slug,
    platform: typeof row.platform === 'string' ? row.platform : 'OTHER',
    descriptionFa: typeof row.descriptionFa === 'string' ? row.descriptionFa : '',
    descriptionEn: typeof row.descriptionEn === 'string' ? row.descriptionEn : '',
    sortOrder: Number.isFinite(Number(row.sortOrder)) ? Number(row.sortOrder) : 100,
    enabled: row.enabled !== false,
  };
}

async function loadCategories(prisma: PrismaClient) {
  const rows = await prisma.systemSetting.findMany({
    where: { category: 'social-category' },
    orderBy: { key: 'asc' },
  });
  return rows
    .map(parseCategory)
    .filter((item): item is SocialCategoryDefinition => item !== null)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.titleFa.localeCompare(b.titleFa));
}

function moduleShell(input: {
  title: string;
  admin: AdminIdentity;
  activeTab: string;
  body: string;
  message?: string;
  error?: boolean;
}) {
  const tabs = [
    ['overview', 'Overview'],
    ['providers', 'Providers'],
    ['catalog', 'Provider Services'],
    ['categories', 'Categories'],
    ['services', 'My Services'],
    ['routing', 'Routing'],
    ['orders', 'Orders'],
    ['logs', 'API Logs'],
  ];
  return `<!doctype html><html lang="en" dir="ltr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${esc(input.title)} — VELIXEO</title><style>
:root{--p:#1686FF;--sky:#37B6FF;--bg:#F7F9FC;--card:#fff;--text:#102235;--muted:#607487;--line:#DCE8F1;--ok:#169A68;--bad:#D94949;--nav:#0C1D33;--warn:#A96812}*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:system-ui,-apple-system,"Segoe UI",Tahoma,sans-serif}a{color:inherit}.layout{display:grid;grid-template-columns:245px minmax(0,1fr);min-height:100vh}.side{background:var(--nav);color:#fff;padding:18px;position:sticky;top:0;height:100vh;overflow:auto}.brand{font-size:20px;font-weight:900;margin-bottom:4px}.sub{color:#9fc2db;font-size:12px;margin-bottom:20px}.back{display:block;text-decoration:none;padding:10px 12px;border-radius:11px;background:rgba(255,255,255,.08);margin-bottom:14px}.side a.tab{display:block;color:#cfe8fa;text-decoration:none;padding:11px 12px;border-radius:11px;margin:4px 0}.side a.tab.active,.side a.tab:hover{background:rgba(45,169,255,.18);color:#fff}.main{padding:22px;min-width:0}.top{display:flex;align-items:center;gap:12px;justify-content:space-between;margin-bottom:16px}.top h1{margin:0;font-size:24px}.chip,.badge{display:inline-block;border-radius:999px;padding:5px 9px;background:#edf4f8;font-size:11px}.ok{background:#e8f8f1;color:#0b8a5c}.bad{background:#fff0f0;color:#b33737}.warnbadge{background:#fff7e8;color:#8e5d0c}.card{background:#fff;border:1px solid var(--line);border-radius:18px;padding:16px;margin-bottom:14px}.grid2{display:grid;grid-template-columns:1fr 1fr;gap:12px}.grid3{display:grid;grid-template-columns:repeat(3,1fr);gap:12px}.grid4{display:grid;grid-template-columns:repeat(4,1fr);gap:12px}.stat{background:#fff;border:1px solid var(--line);border-radius:17px;padding:15px}.stat small{color:var(--muted)}.stat b{display:block;font-size:22px;margin-top:8px}.field{margin-top:10px}.field label{display:block;color:var(--muted);font-size:12px;margin-bottom:5px}.field input,.field select,.field textarea{width:100%;border:1px solid var(--line);border-radius:11px;padding:10px 11px;background:#fff;outline:none}.field input,.field select{height:42px}.field textarea{min-height:82px;resize:vertical}.field input:focus,.field select:focus,.field textarea:focus{border-color:var(--p);box-shadow:0 0 0 3px rgba(13,120,200,.08)}.row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.spacer{flex:1}.btn,.ghost,.danger{border-radius:10px;padding:9px 12px;cursor:pointer;text-decoration:none;display:inline-grid;place-items:center}.btn{border:0;background:linear-gradient(135deg,var(--sky),var(--p));color:white;font-weight:800}.ghost{border:1px solid var(--line);background:#fff}.danger{border:1px solid #ffd5d5;background:#fff5f5;color:var(--bad)}.table{overflow:auto}.table table{width:100%;border-collapse:collapse;min-width:920px}th,td{padding:10px 8px;border-bottom:1px solid #edf3f7;text-align:left;font-size:12px;vertical-align:top}th{color:var(--muted)}.muted{color:var(--muted);font-size:12px}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;direction:ltr;text-align:left}.message{padding:10px 12px;border-radius:11px;margin-bottom:14px}.message.okm{background:#e8f8f1;border:1px solid #c7efdc;color:#0b8a5c}.message.errm{background:#fff0f0;border:1px solid #ffdada;color:#b33737}.notice{background:#f7fbff;border:1px solid var(--line);padding:11px;border-radius:12px}.pricing{background:#f8fcff;border:1px dashed #b9d9ee;border-radius:13px;padding:12px;margin-top:10px}.section{font-size:17px;font-weight:900;margin:0 0 10px}.check{display:flex;gap:7px;align-items:center;margin-top:12px}.check input{width:18px;height:18px}@media(max-width:980px){.layout{grid-template-columns:1fr}.side{position:static;height:auto}.side nav{display:flex;overflow:auto;gap:4px}.side a.tab{white-space:nowrap}.grid4,.grid3{grid-template-columns:1fr 1fr}.main{padding:15px}}@media(max-width:600px){.grid4,.grid3,.grid2{grid-template-columns:1fr}.top{align-items:flex-start;flex-direction:column}}
</style></head><body><section class="layout"><aside class="side"><div class="brand">VELIXEO</div><div class="sub">Social Media Admin</div><a class="back" href="/admin">← Main Admin</a><nav>${tabs.map(([key,label]) => `<a class="tab ${input.activeTab === key ? 'active' : ''}" href="/admin/social?tab=${key}">${label}</a>`).join('')}</nav></aside><main class="main"><div class="top"><div><h1>${esc(input.title)}</h1><div class="muted">Social Media management</div></div><span class="chip">${esc(input.admin.fullName || input.admin.email || input.admin.phone || 'ADMIN')}</span></div>${input.message ? `<div class="message ${input.error ? 'errm' : 'okm'}">${esc(input.message)}</div>` : ''}${input.body}</main></section></body></html>`;
}

function queryMessage(query: Record<string, unknown>) {
  const msg = String(query.msg ?? '').trim();
  const error = String(query.error ?? '') === '1';
  return { msg, error };
}

async function renderOverview(prisma: PrismaClient) {
  const [providers, services, activeServices, categories, orders, routes] = await Promise.all([
    prisma.provider.count({ where: { kind: ProviderKind.SOCIAL } }),
    prisma.service.count({ where: { category: ServiceCategory.SOCIAL } }),
    prisma.service.count({ where: { category: ServiceCategory.SOCIAL, enabled: true } }),
    prisma.systemSetting.count({ where: { category: 'social-category' } }),
    prisma.order.count({ where: { category: ServiceCategory.SOCIAL } }),
    prisma.serviceProviderRoute.count({
      where: { provider: { kind: ProviderKind.SOCIAL }, enabled: true },
    }),
  ]);
  const providerRows = await prisma.provider.findMany({
    where: { kind: ProviderKind.SOCIAL },
    orderBy: [{ priority: 'asc' }, { name: 'asc' }],
  });
  const states = await Promise.all(providerRows.map(async (provider) => ({
    provider,
    sync: await getSocialProviderSyncConfig(prisma, provider.id),
  })));
  return `<div class="grid4"><div class="stat"><small>Providers</small><b>${providers}</b></div><div class="stat"><small>کاتالوگ Provider</small><b>${services}</b></div><div class="stat"><small>Active app services</small><b>${activeServices}</b></div><div class="stat"><small>Categories</small><b>${categories}</b></div></div><div class="grid3" style="margin-top:12px"><div class="stat"><small>Route Active</small><b>${routes}</b></div><div class="stat"><small>Total SMM orders</small><b>${orders}</b></div><div class="stat"><small>Auto Pricing</small><b>LIVE</b></div></div><div class="card"><h3 class="section">Provider status</h3><div class="table"><table><thead><tr><th>Provider</th><th>Status</th><th>Auto Sync</th><th>Last sync</th><th>Services</th><th>Result</th></tr></thead><tbody>${states.map(({provider,sync}) => `<tr><td><b>${esc(provider.name)}</b><br><span class="mono muted">${esc(provider.slug)}</span></td><td><span class="badge ${provider.enabled ? 'ok' : 'bad'}">${provider.enabled ? 'Active' : 'Disabled'}</span></td><td>${sync.autoSync ? `<span class="badge ok">هر ${sync.syncMinutes} دقیقه</span>` : '<span class="badge">Disabled</span>'}</td><td>${faDate(sync.lastSyncAt)}</td><td>${sync.lastServiceCount}</td><td>${sync.lastSyncStatus === 'ok' ? '<span class="badge ok">OK</span>' : sync.lastSyncStatus === 'error' ? `<span class="badge bad">${esc(sync.lastSyncError || 'Error')}</span>` : '<span class="badge">—</span>'}</td></tr>`).join('') || '<tr><td colspan="6">No provider has been added yet.</td></tr>'}</tbody></table></div></div><div class="notice"><b>Live pricing:</b> سرویس‌هایی که حالت «Markup % / Auto Markup» دارند، Sale priceشان از آخرین قیمت Provider + نرخ ارز + Markup % محاسبه می‌شود. Auto Sync قیمت Provider را طبق زمان‌بندی تازه می‌کند؛ بنابراین افزایش یا کاهش قیمت Provider بدون آپدیت APK روی Sale price اثر می‌گذارد.</div>`;
}

async function renderProviders(
  prisma: PrismaClient,
  query: Record<string, unknown>,
) {
  const editId = String(query.edit ?? '').trim();
  const checkId = String(query.check ?? '').trim();
  const providers = await prisma.provider.findMany({
    where: { kind: ProviderKind.SOCIAL },
    orderBy: [{ priority: 'asc' }, { name: 'asc' }],
  });
  const selected = editId
    ? await prisma.provider.findFirst({ where: { id: editId, kind: ProviderKind.SOCIAL } })
    : null;
  const selectedSync = selected
    ? await getSocialProviderSyncConfig(prisma, selected.id)
    : null;
  let connection = '';
  if (checkId) {
    const provider = await prisma.provider.findFirst({ where: { id: checkId, kind: ProviderKind.SOCIAL } });
    if (provider) {
      try {
        const balance = await smmClientForProvider(provider).balance();
        connection = `<div class="message okm">اتصال ${esc(provider.name)} موفق است — موجودی: ${esc(balance.balance)} ${esc(balance.currency)}</div>`;
      } catch (error) {
        connection = `<div class="message errm">اتصال Nameوفق: ${esc(error instanceof Error ? error.message : 'provider_error')}</div>`;
      }
    }
  }
  const rows = await Promise.all(providers.map(async (provider) => ({
    provider,
    sync: await getSocialProviderSyncConfig(prisma, provider.id),
    routeCount: await prisma.serviceProviderRoute.count({ where: { providerId: provider.id } }),
  })));
  const p = selected;
  return `${connection}<div class="grid2"><div class="card"><h3 class="section">Providers SMM</h3><div class="table"><table><thead><tr><th>Name</th><th>سرویس‌ها</th><th>Markup</th><th>Auto Sync</th><th>Secret</th><th></th></tr></thead><tbody>${rows.map(({provider,sync,routeCount}) => `<tr><td><b>${esc(provider.name)}</b><br><span class="mono muted">${esc(provider.baseUrl || '')}</span></td><td>${routeCount}</td><td>${esc(provider.defaultMarkupPercent.toString())}%</td><td>${sync.autoSync ? `${sync.syncMinutes} دقیقه` : 'Disabled'}<br><span class="muted">${faDate(sync.lastSyncAt)}</span></td><td>${provider.secretCiphertext ? '<span class="badge ok">Configured</span>' : '<span class="badge bad">Empty</span>'}</td><td><div class="row"><a class="ghost" href="/admin/social?tab=providers&edit=${encodeURIComponent(provider.id)}">Edit</a><a class="ghost" href="/admin/social?tab=providers&check=${encodeURIComponent(provider.id)}">تست</a><form method="post" action="/admin/social/providers/sync"><input type="hidden" name="providerId" value="${esc(provider.id)}"><button class="btn" type="submit">Sync</button></form></div></td></tr>`).join('') || '<tr><td colspan="6">Provider ثبت نشده است.</td></tr>'}</tbody></table></div></div><div class="card"><h3 class="section">${p ? 'Edit Provider' : 'Provider جدید'}</h3><form method="post" action="/admin/social/providers/save">${p ? `<input type="hidden" name="id" value="${esc(p.id)}">` : ''}<div class="grid2"><div class="field"><label>Name Provider</label><input name="name" value="${esc(p?.name || '')}" placeholder="JustAnotherPanel" required></div><div class="field"><label>Slug یکتا</label><input class="mono" name="slug" value="${esc(p?.slug || '')}" placeholder="justanotherpanel" pattern="[a-z0-9_-]+" required></div></div><div class="field"><label>API URL</label><input class="mono" name="baseUrl" value="${esc(p?.baseUrl || '')}" placeholder="https://panel.example/api/v2" required></div><div class="grid3"><div class="field"><label>Priority</label><input type="number" name="priority" value="${esc(p?.priority ?? 100)}"></div><div class="field"><label>سود پیش‌فرض %</label><input name="markup" inputmode="decimal" value="${esc(p?.defaultMarkupPercent.toString() ?? '0')}"></div><div class="field"><label>Timeout ثانیه</label><input type="number" min="5" max="180" name="timeout" value="${esc(p?.timeoutSeconds ?? 30)}"></div></div><div class="grid2"><div class="field"><label>Auto Sync هر چند دقیقه</label><input type="number" min="1" max="1440" name="syncMinutes" value="${esc(selectedSync?.syncMinutes ?? 10)}"></div><div class="field"><label>API Key / Secret ${p?.secretCiphertext ? '(خالی = بدون تغییر)' : ''}</label><input class="mono" type="password" name="secret" autocomplete="new-password" placeholder="API Key"></div></div><label class="check"><input type="checkbox" name="autoSync"${selectedSync?.autoSync !== false ? ' checked' : ''}> Sync خودکار قیمت و خدمات Active باشد</label><label class="check"><input type="checkbox" name="enabled"${p?.enabled !== false ? ' checked' : ''}> Provider Active باشد</label><div class="field"><label>یادداشت داخلی</label><textarea name="notes">${esc(p?.notes || '')}</textarea></div><div class="row" style="margin-top:12px"><button class="btn" type="submit">Save Provider</button>${p ? '<a class="ghost" href="/admin/social?tab=providers">Provider جدید</a>' : ''}</div></form><div class="notice" style="margin-top:12px">Secret با AES-256-GCM Save می‌شود و دوباره نمایش داده نمی‌شود. Status رمزگذاری سرور: <b>${providerSecretEncryptionConfigured() ? 'Active' : 'غیرActive'}</b>.</div></div></div>`;
}

async function renderCategories(prisma: PrismaClient, query: Record<string, unknown>) {
  const categories = await loadCategories(prisma);
  const services = await prisma.service.findMany({
    where: { category: ServiceCategory.SOCIAL, enabled: true },
    select: { socialGroup: true },
  });
  const counts = new Map<string, number>();
  for (const service of services) {
    const key = service.socialGroup || 'OTHER';
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  const editSlug = String(query.edit ?? '').trim();
  const selected = categories.find((item) => item.slug === editSlug) || null;
  return `<div class="grid2"><div class="card"><h3 class="section">Categoriesی خدمات</h3><div class="table"><table><thead><tr><th>Name</th><th>Platform</th><th>Services</th><th>ترتیب</th><th>Status</th><th></th></tr></thead><tbody>${categories.map((category) => `<tr><td><b>${esc(category.titleFa)}</b><br><span class="muted">${esc(category.titleEn)}</span><br><span class="mono muted">${esc(category.slug)}</span></td><td>${esc(category.platform)}</td><td><b>${counts.get(category.slug) || 0}</b></td><td>${category.sortOrder}</td><td><span class="badge ${category.enabled ? 'ok' : 'bad'}">${category.enabled ? 'Active' : 'Disabled'}</span></td><td><div class="row"><a class="ghost" href="/admin/social?tab=categories&edit=${encodeURIComponent(category.slug)}">Edit</a><form method="post" action="/admin/social/categories/delete" onsubmit="return confirm('این دسته حذف و سرویس‌های داخل آن غیرفعال شوند؟')"><input type="hidden" name="slug" value="${esc(category.slug)}"><button class="danger" type="submit">Delete</button></form></div></td></tr>`).join('') || '<tr><td colspan="6">دسته‌ای ایجاد نشده است.</td></tr>'}</tbody></table></div></div><div class="card"><h3 class="section">${selected ? 'Edit دسته' : 'دسته جدید'}</h3><form method="post" action="/admin/social/categories/save">${selected ? `<input type="hidden" name="originalSlug" value="${esc(selected.slug)}">` : ''}<div class="grid2"><div class="field"><label>Name فارسی</label><input name="titleFa" value="${esc(selected?.titleFa || '')}" placeholder="فالوور خارجی" required></div><div class="field"><label>English name</label><input name="titleEn" value="${esc(selected?.titleEn || '')}" placeholder="International Followers" required></div></div><div class="grid2"><div class="field"><label>Slug</label><input class="mono" name="slug" value="${esc(selected?.slug || '')}" placeholder="instagram-foreign-followers" required></div><div class="field"><label>Platform</label><input name="platform" value="${esc(selected?.platform || 'INSTAGRAM')}" placeholder="INSTAGRAM" required></div></div><div class="field"><label>توضیح فارسی</label><textarea name="descriptionFa">${esc(selected?.descriptionFa || '')}</textarea></div><div class="field"><label>English description</label><textarea name="descriptionEn">${esc(selected?.descriptionEn || '')}</textarea></div><div class="field"><label>ترتیب نمایش</label><input type="number" name="sortOrder" value="${esc(selected?.sortOrder ?? 100)}"></div><label class="check"><input type="checkbox" name="enabled"${selected?.enabled !== false ? ' checked' : ''}> Active باشد</label><div class="row" style="margin-top:12px"><button class="btn" type="submit">Save Category</button>${selected ? `<button class="danger" type="submit" formaction="/admin/social/categories/delete" formmethod="post" name="slug" value="${esc(selected.slug)}" onclick="return confirm('این دسته حذف و سرویس‌های داخل آن غیرفعال شوند؟')">Delete Category</button>` : ''}</div></form></div></div>`;
}

async function renderCatalog(prisma: PrismaClient, query: Record<string, unknown>) {
  const providers = await prisma.provider.findMany({
    where: { kind: ProviderKind.SOCIAL },
    orderBy: [{ priority: 'asc' }, { name: 'asc' }],
  });
  const providerId = String(query.provider ?? providers[0]?.id ?? '').trim();
  const q = String(query.q ?? '').trim().toLowerCase();
  const routeId = String(query.route ?? '').trim();
  const categories = (await loadCategories(prisma)).filter((item) => item.enabled);
  const routes = providerId
    ? await prisma.serviceProviderRoute.findMany({
        where: { providerId },
        include: { service: true, provider: true },
        orderBy: [{ providerCategory: 'asc' }, { providerName: 'asc' }],
      })
    : [];
  const filtered = routes.filter((route) => !q || `${route.providerServiceCode} ${route.providerName} ${route.providerCategory}`.toLowerCase().includes(q));
  const editRoute = routeId
    ? await prisma.serviceProviderRoute.findFirst({
        where: { id: routeId, provider: { kind: ProviderKind.SOCIAL } },
        include: { service: true, provider: true },
      })
    : null;
  const rows = await Promise.all(filtered.slice(0, 500).map(async (route) => ({
    route,
    sale: await socialRouteSaleRateAfn(prisma, route.service, route),
  })));
  const pricingMeta = editRoute ? jsonObject(editRoute.service.metadata) : {};
  const pricingMode = editRoute?.service.basePriceAfn != null ? 'FIXED' : String(pricingMeta.pricingMode || 'AUTO_MARKUP');
  return `<div class="card"><div class="row"><form method="get" action="/admin/social" class="row" style="flex:1"><input type="hidden" name="tab" value="catalog"><select name="provider" style="min-width:220px;height:40px;border:1px solid #DCE8F1;border-radius:10px;padding:0 10px">${providers.map((provider) => `<option value="${esc(provider.id)}"${provider.id === providerId ? ' selected' : ''}>${esc(provider.name)}</option>`).join('')}</select><input name="q" value="${esc(String(query.q ?? ''))}" placeholder="جستجو ID، Name یا دسته Provider" style="min-width:260px;height:40px;border:1px solid #DCE8F1;border-radius:10px;padding:0 10px"><button class="ghost" type="submit">فیلتر</button></form>${providerId ? `<form method="post" action="/admin/social/providers/sync"><input type="hidden" name="providerId" value="${esc(providerId)}"><button class="btn" type="submit">Sync Now</button></form>` : ''}</div></div><div class="grid2"><div class="card"><h3 class="section">کاتالوگ خام Provider</h3><div class="muted" style="margin-bottom:10px">Sync سرویس‌های Provider را می‌گیرد. تا وقتی سرویس را Publish نکنی در اپ نمایش داده نمی‌شود.</div><div class="table"><table><thead><tr><th>ID</th><th>Name Provider</th><th>دسته Provider</th><th>Provider cost</th><th>Sale price فعلی</th><th>Min/Max</th><th>Status اپ</th><th></th></tr></thead><tbody>${rows.map(({route,sale}) => `<tr><td class="mono">${esc(route.providerServiceCode)}</td><td><b>${esc(route.providerName || route.service.titleEn)}</b><br><span class="muted">${esc(route.providerType || 'Default')}</span></td><td>${esc(route.providerCategory || '—')}</td><td>${esc(route.providerRate?.toString() || '—')} ${esc(route.providerCurrency || '')}</td><td>${sale == null ? '—' : fmtAfn(sale)}</td><td>${esc(route.providerMinQty ?? '—')}–${esc(route.providerMaxQty ?? '—')}</td><td><span class="badge ${route.service.enabled ? 'ok' : ''}">${route.service.enabled ? 'منتشر شده' : 'خام'}</span></td><td><a class="ghost" href="/admin/social?tab=catalog&provider=${encodeURIComponent(providerId)}&route=${encodeURIComponent(route.id)}">${route.service.enabled ? 'Edit فروش' : 'افزودن'}</a></td></tr>`).join('') || '<tr><td colspan="8">ابتدا Provider را Sync کن.</td></tr>'}</tbody></table></div></div><div>${editRoute ? `<div class="card"><h3 class="section">${editRoute.service.enabled ? 'Edit سرویس فروش' : 'افزودن سرویس به VELIXEO'}</h3><div class="notice"><b>منبع:</b> ${esc(editRoute.provider.name)} / ID ${esc(editRoute.providerServiceCode)}<br><b>Provider cost فعلی:</b> ${esc(editRoute.providerRate?.toString() || '—')} ${esc(editRoute.providerCurrency || '')}</div><form method="post" action="/admin/social/catalog/publish"><input type="hidden" name="routeId" value="${esc(editRoute.id)}"><input type="hidden" name="providerId" value="${esc(providerId)}"><div class="field"><label>Category داخل اپ</label><select name="categorySlug" required><option value="">انتخاب کن</option>${categories.map((category) => `<option value="${esc(category.slug)}"${category.slug === editRoute.service.socialGroup ? ' selected' : ''}>${esc(category.platform)} → ${esc(category.titleFa)}</option>`).join('')}</select></div><div class="grid2"><div class="field"><label>Name فارسی برای مشتری</label><input name="titleFa" value="${esc(editRoute.service.titleFa)}" required></div><div class="field"><label>English name</label><input name="titleEn" value="${esc(editRoute.service.titleEn)}" required></div></div><div class="field"><label>توضیح فارسی</label><textarea name="descriptionFa">${esc(editRoute.service.descriptionFa || '')}</textarea></div><div class="pricing"><b>قیمت‌گذاری</b><div class="field"><label>روش قیمت</label><select name="pricingMode"><option value="AUTO_MARKUP"${pricingMode !== 'FIXED' ? ' selected' : ''}>خودکار: قیمت Provider + Markup %</option><option value="FIXED"${pricingMode === 'FIXED' ? ' selected' : ''}>Sale price ثابت دستی</option></select></div><div class="grid3"><div class="field"><label>سود % (Auto)</label><input name="markup" inputmode="decimal" value="${esc(editRoute.markupPercent?.toString() ?? editRoute.provider.defaultMarkupPercent.toString())}"></div><div class="field"><label>قیمت ثابت</label><input name="fixedPrice" inputmode="decimal" value="${editRoute.service.basePriceAfn == null ? '' : esc(editRoute.service.basePriceAfn.toString())}"></div><div class="field"><label>ارز قیمت ثابت</label><select name="fixedCurrency"><option value="AFN">AFN</option><option value="USD">USD</option><option value="TOMAN">TOMAN</option></select></div></div><div class="muted">مثال Auto: خرید $1 و سود 30% ⇒ فروش $1.30 معادل AFN. اگر Provider بعداً $1.20 شود، Auto Sync Sale price را با همان 30% دوباره محاسبه می‌کند. در حالت Fixed قیمت تغییر نمی‌کند.</div></div><div class="grid3"><div class="field"><label>حداقل مشتری</label><input type="number" name="minQty" value="${esc(editRoute.service.minQty ?? editRoute.providerMinQty ?? '')}"></div><div class="field"><label>حداکثر مشتری</label><input type="number" name="maxQty" value="${esc(editRoute.service.maxQty ?? editRoute.providerMaxQty ?? '')}"></div><div class="field"><label>ترتیب</label><input type="number" name="sortOrder" value="${esc(editRoute.service.sortOrder)}"></div></div><label class="check"><input type="checkbox" name="enabled"${editRoute.service.enabled ? ' checked' : ' checked'}> در اپ Active باشد</label><button class="btn" type="submit" style="margin-top:12px">Save و انتشار</button></form></div>` : '<div class="card muted">یک سرویس از سمت چپ انتخاب کن تا دسته، Name و Sale priceش را تنظیم کنی.</div>'}</div></div>`;
}

async function renderServices(prisma: PrismaClient) {
  const [categories, sortMode] = await Promise.all([
    loadCategories(prisma),
    loadCatalogSortMode(prisma),
  ]);
  const categoryMap = new Map(categories.map((category) => [category.slug, category]));
  const services = await prisma.service.findMany({
    where: { category: ServiceCategory.SOCIAL, enabled: true },
    include: {
      routes: {
        where: { enabled: true, provider: { kind: ProviderKind.SOCIAL } },
        include: { provider: true },
        orderBy: [{ priority: 'asc' }, { provider: { priority: 'asc' } }],
      },
    },
    orderBy: [{ socialPlatform: 'asc' }, { socialGroup: 'asc' }, { sortOrder: 'asc' }],
  });
  const rows = await Promise.all(services.map(async (service) => {
    const route = service.routes[0];
    return {
      service,
      route,
      sale: route ? await socialRouteSaleRateAfn(prisma, service, route) : null,
    };
  }));
  if (sortMode !== 'MANUAL') {
    rows.sort((a, b) => {
      if (a.service.socialPlatform !== b.service.socialPlatform || a.service.socialGroup !== b.service.socialGroup) return 0;
      if (a.sale == null && b.sale == null) return a.service.sortOrder - b.service.sortOrder;
      if (a.sale == null) return 1;
      if (b.sale == null) return -1;
      if (a.sale === b.sale) return a.service.sortOrder - b.service.sortOrder;
      const cmp = a.sale < b.sale ? -1 : 1;
      return sortMode === 'PRICE_DESC' ? -cmp : cmp;
    });
  }
  const sortCard = `<div class="card"><div class="row"><div><h3 class="section" style="margin-bottom:4px">ترتیب نمایش قیمت برای کاربر</h3><div class="muted">مرتب‌سازی فقط داخل هر دسته اعمال می‌شود و قیمت نهایی AFN بعد از Markup ملاک است.</div></div><div class="spacer"></div><form method="post" action="/admin/social/catalog-sort/save" class="row"><select name="mode"><option value="PRICE_ASC"${sortMode === 'PRICE_ASC' ? ' selected' : ''}>ارزان‌ترین اول</option><option value="PRICE_DESC"${sortMode === 'PRICE_DESC' ? ' selected' : ''}>گران‌ترین اول</option><option value="MANUAL"${sortMode === 'MANUAL' ? ' selected' : ''}>ترتیب دستی</option></select><button class="btn" type="submit">ذخیره ترتیب</button></form></div></div>`;
  return sortCard + `<div class="card"><h3 class="section">سرویس‌هایی که کاربران می‌بینند</h3><div class="table"><table><thead><tr><th>سرویس</th><th>دسته</th><th>Provider</th><th>Provider cost</th><th>روش فروش</th><th>قیمت فعلی</th><th>Markup</th><th></th></tr></thead><tbody>${rows.map(({service,route,sale}) => { const category = categoryMap.get(service.socialGroup || ''); return `<tr><td><b>${esc(service.titleFa)}</b><br><span class="muted">${esc(service.titleEn)}</span></td><td>${esc(category?.titleFa || service.socialGroup || 'OTHER')}<br><span class="muted">${esc(service.socialPlatform || 'OTHER')}</span></td><td>${esc(route?.provider.name || '—')}</td><td>${esc(route?.providerRate?.toString() || '—')} ${esc(route?.providerCurrency || '')}</td><td>${service.basePriceAfn == null ? '<span class="badge ok">AUTO</span>' : '<span class="badge">FIXED</span>'}</td><td><b>${sale == null ? '—' : fmtAfn(sale)}</b></td><td>${esc(route?.markupPercent?.toString() ?? route?.provider.defaultMarkupPercent.toString() ?? '—')}%</td><td>${route ? `<a class="ghost" href="/admin/social?tab=catalog&provider=${encodeURIComponent(route.providerId)}&route=${encodeURIComponent(route.id)}">Edit</a>` : ''}</td></tr>`; }).join('') || '<tr><td colspan="8">هنوز سرویسی منتشر نشده است.</td></tr>'}</tbody></table></div></div>`;
}

async function renderRouting(prisma: PrismaClient) {
  const routes = await prisma.serviceProviderRoute.findMany({
    where: { service: { category: ServiceCategory.SOCIAL }, provider: { kind: ProviderKind.SOCIAL } },
    include: { service: true, provider: true },
    orderBy: [{ service: { titleFa: 'asc' } }, { priority: 'asc' }],
    take: 500,
  });
  return `<div class="card"><h3 class="section">Routing و Failover</h3><div class="muted" style="margin-bottom:10px">عدد Priority کمتر یعنی Provider زودتر امتحان می‌شود. Markup خالی یعنی سود پیش‌فرض Provider.</div><div class="table"><table><thead><tr><th>سرویس</th><th>Provider</th><th>Provider ID</th><th>Priority</th><th>Markup</th><th>Status</th><th></th></tr></thead><tbody>${routes.map((route) => `<tr><td><b>${esc(route.service.titleFa)}</b></td><td>${esc(route.provider.name)}</td><td class="mono">${esc(route.providerServiceCode)}</td><td>${route.priority}</td><td>${esc(route.markupPercent?.toString() ?? route.provider.defaultMarkupPercent.toString())}%</td><td><span class="badge ${route.enabled ? 'ok' : 'bad'}">${route.enabled ? 'Active' : 'Disabled'}</span></td><td><form method="post" action="/admin/social/routing/save" class="row"><input type="hidden" name="routeId" value="${esc(route.id)}"><input style="width:70px" type="number" name="priority" value="${route.priority}"><input style="width:80px" name="markup" value="${esc(route.markupPercent?.toString() || '')}" placeholder="%"><label><input type="checkbox" name="enabled"${route.enabled ? ' checked' : ''}> ON</label><button class="ghost" type="submit">Save</button></form></td></tr>`).join('') || '<tr><td colspan="7">Route وجود ندارد.</td></tr>'}</tbody></table></div></div>`;
}

async function renderOrders(prisma: PrismaClient) {
  const orders = await prisma.order.findMany({
    where: { category: ServiceCategory.SOCIAL },
    include: { service: true, provider: true, user: true },
    orderBy: { createdAt: 'desc' },
    take: 100,
  });
  return `<div class="card"><h3 class="section">آخرین Ordersی SMM</h3><div class="table"><table><thead><tr><th>تاریخ</th><th>کاربر</th><th>سرویس</th><th>Provider</th><th>مبلغ</th><th>Status</th></tr></thead><tbody>${orders.map((order) => `<tr><td>${faDate(order.createdAt)}</td><td>${esc(order.user.email || order.user.phone || order.user.fullName || order.user.id)}</td><td>${esc(order.service?.titleFa || '—')}</td><td>${esc(order.provider?.name || '—')}<br><span class="mono muted">${esc(order.providerOrderId || '')}</span></td><td>${fmtAfn(order.totalAmountAfn)}</td><td><span class="badge">${esc(order.status)}</span></td></tr>`).join('') || '<tr><td colspan="6">سفارشی وجود ندارد.</td></tr>'}</tbody></table></div></div>`;
}

async function renderLogs(prisma: PrismaClient) {
  const logs = await prisma.adminAuditLog.findMany({
    where: { OR: [{ action: { startsWith: 'SOCIAL_' } }, { entityType: 'SocialCategory' }] },
    include: { adminUser: true },
    orderBy: { createdAt: 'desc' },
    take: 150,
  });
  return `<div class="card"><h3 class="section">Social / API Logs</h3><div class="table"><table><thead><tr><th>تاریخ</th><th>عملیات</th><th>مدیر</th><th>خلاصه</th></tr></thead><tbody>${logs.map((log) => `<tr><td>${faDate(log.createdAt)}</td><td><span class="mono">${esc(log.action)}</span></td><td>${esc(log.adminUser.email || log.adminUser.fullName || log.adminUser.id)}</td><td>${esc(log.summary)}</td></tr>`).join('') || '<tr><td colspan="4">لاگی وجود ندارد.</td></tr>'}</tbody></table></div></div>`;
}

export function registerSocialAdminV2(
  app: FastifyInstance,
  prisma: PrismaClient,
  resolveAdmin: AdminResolver,
) {
  app.get('/admin/social', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const query = (request.query ?? {}) as Record<string, unknown>;
    const tab = String(query.tab ?? 'overview');
    const { msg, error } = queryMessage(query);
    let body = '';
    if (tab === 'providers') body = await renderProviders(prisma, query);
    else if (tab === 'catalog') body = await renderCatalog(prisma, query);
    else if (tab === 'categories') body = await renderCategories(prisma, query);
    else if (tab === 'services') body = await renderServices(prisma);
    else if (tab === 'routing') body = await renderRouting(prisma);
    else if (tab === 'orders') body = await renderOrders(prisma);
    else if (tab === 'logs') body = await renderLogs(prisma);
    else body = await renderOverview(prisma);
    return reply.type('text/html; charset=utf-8').send(moduleShell({
      title: 'شبکه‌های اجتماعی', admin, activeTab: tab, body, message: msg, error,
    }));
  });

  app.post('/admin/social/providers/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const id = text(body, 'id');
    const name = text(body, 'name');
    const slug = normalizeSlug(text(body, 'slug'));
    const baseUrl = text(body, 'baseUrl').replace(/\/$/, '');
    if (!name || !slug || !baseUrl) {
      return reply.code(303).redirect('/admin/social?tab=providers&error=1&msg=اطلاعات Provider ناقص است');
    }
    try {
      const providerData = {
        name,
        slug,
        kind: ProviderKind.SOCIAL,
        baseUrl,
        enabled: checked(body, 'enabled'),
        priority: intValue(body.priority, 100),
        defaultMarkupPercent: new Prisma.Decimal(decimalValue(body.markup, '0')),
        timeoutSeconds: Math.min(180, Math.max(5, intValue(body.timeout, 30))),
        notes: text(body, 'notes') || null,
      };
      const secret = text(body, 'secret');
      let provider;
      if (id) {
        const encrypted = secret ? encryptProviderSecret(secret) : {};
        provider = await prisma.provider.update({
          where: { id },
          data: { ...providerData, ...encrypted },
        });
      } else {
        if (secret && !providerSecretEncryptionConfigured()) throw new Error('PROVIDER_SECRET_ENCRYPTION_NOT_CONFIGURED');
        const encrypted = secret ? encryptProviderSecret(secret) : {};
        provider = await prisma.provider.create({
          data: { ...providerData, ...encrypted },
        });
      }
      await saveSocialProviderSyncConfig(prisma, provider.id, {
        autoSync: checked(body, 'autoSync'),
        syncMinutes: Math.min(1440, Math.max(1, intValue(body.syncMinutes, 10))),
      });
      await audit(prisma, admin.id, id ? 'SOCIAL_PROVIDER_UPDATE' : 'SOCIAL_PROVIDER_CREATE', 'Provider', provider.id, `${provider.name} (${provider.slug})`);
      return reply.code(303).redirect(`/admin/social?tab=providers&edit=${encodeURIComponent(provider.id)}&msg=${encodeURIComponent('Provider Save شد')}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=providers&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'save_failed')}`);
    }
  });

  app.post('/admin/social/providers/sync', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const providerId = text(request.body as AnyBody, 'providerId');
    try {
      const result = await syncSocialProviderCatalog(prisma, providerId);
      await audit(prisma, admin.id, 'SOCIAL_PROVIDER_SYNC', 'Provider', providerId, `Synced ${result.total} services`, {
        created: result.created,
        updated: result.updated,
        currency: result.currency,
      });
      return reply.code(303).redirect(`/admin/social?tab=catalog&provider=${encodeURIComponent(providerId)}&msg=${encodeURIComponent(`Sync کامل شد: ${result.total} سرویس، ${result.created} جدید`)}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=providers&edit=${encodeURIComponent(providerId)}&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'sync_failed')}`);
    }
  });

  app.post('/admin/social/categories/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const originalSlug = normalizeSlug(text(body, 'originalSlug'));
    const slug = normalizeSlug(text(body, 'slug'));
    const titleFa = text(body, 'titleFa');
    const titleEn = text(body, 'titleEn');
    const platform = text(body, 'platform').toUpperCase().replace(/[^A-Z0-9_-]/g, '_') || 'OTHER';
    if (!slug || !titleFa || !titleEn) {
      return reply.code(303).redirect('/admin/social?tab=categories&error=1&msg=اطلاعات Category ناقص است');
    }
    try {
      const value: SocialCategoryDefinition = {
        slug,
        titleFa,
        titleEn,
        platform,
        descriptionFa: text(body, 'descriptionFa'),
        descriptionEn: text(body, 'descriptionEn'),
        sortOrder: intValue(body.sortOrder, 100),
        enabled: checked(body, 'enabled'),
      };
      if (originalSlug && originalSlug !== slug) {
        const [source, target] = await Promise.all([
          prisma.systemSetting.findUnique({ where: { key: categoryKey(originalSlug) } }),
          prisma.systemSetting.findUnique({ where: { key: categoryKey(slug) } }),
        ]);
        if (!source) throw new Error('CATEGORY_NOT_FOUND');
        if (target) throw new Error('CATEGORY_SLUG_ALREADY_EXISTS');
        await prisma.$transaction([
          prisma.systemSetting.create({
            data: {
              key: categoryKey(slug),
              category: 'social-category',
              description: `Social service category ${slug}`,
              value: value as unknown as Prisma.InputJsonValue,
            },
          }),
          prisma.service.updateMany({
            where: { category: ServiceCategory.SOCIAL, socialGroup: originalSlug },
            data: { socialGroup: slug, socialPlatform: platform },
          }),
          prisma.systemSetting.delete({ where: { key: categoryKey(originalSlug) } }),
        ]);
      } else {
        await prisma.systemSetting.upsert({
          where: { key: categoryKey(slug) },
          create: {
            key: categoryKey(slug),
            category: 'social-category',
            description: `Social service category ${slug}`,
            value: value as unknown as Prisma.InputJsonValue,
          },
          update: {
            category: 'social-category',
            value: value as unknown as Prisma.InputJsonValue,
          },
        });
        await prisma.service.updateMany({
          where: { category: ServiceCategory.SOCIAL, socialGroup: slug },
          data: { socialPlatform: platform },
        });
      }
      await audit(prisma, admin.id, 'SOCIAL_CATEGORY_SAVE', 'SocialCategory', slug, `${platform} → ${titleFa}`, {
        originalSlug: originalSlug || slug,
        renamed: Boolean(originalSlug && originalSlug !== slug),
      });
      return reply.code(303).redirect(`/admin/social?tab=categories&edit=${encodeURIComponent(slug)}&msg=${encodeURIComponent('Category Save شد')}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=categories&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'category_save_failed')}`);
    }
  });

  app.post('/admin/social/categories/delete', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const slug = normalizeSlug(text(request.body as AnyBody, 'slug'));
    if (!slug) return reply.code(303).redirect('/admin/social?tab=categories&error=1&msg=CATEGORY_SLUG_REQUIRED');
    try {
      const row = await prisma.systemSetting.findUnique({ where: { key: categoryKey(slug) } });
      if (!row) throw new Error('CATEGORY_NOT_FOUND');
      const result = await prisma.$transaction(async (tx) => {
        const disabled = await tx.service.updateMany({
          where: { category: ServiceCategory.SOCIAL, socialGroup: slug },
          data: { enabled: false },
        });
        await tx.systemSetting.delete({ where: { key: categoryKey(slug) } });
        return disabled.count;
      });
      await audit(prisma, admin.id, 'SOCIAL_CATEGORY_DELETE', 'SocialCategory', slug, `Deleted category ${slug}; disabled ${result} services`, {
        disabledServiceCount: result,
      });
      return reply.code(303).redirect(`/admin/social?tab=categories&msg=${encodeURIComponent(`Category حذف شد؛ ${result} سرویس داخل آن غیرفعال شد`)}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=categories&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'category_delete_failed')}`);
    }
  });

  app.post('/admin/social/catalog-sort/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const mode = normalizeCatalogSortMode((request.body as AnyBody).mode);
    const value = { mode, updatedAt: new Date().toISOString(), updatedBy: admin.id };
    await prisma.systemSetting.upsert({
      where: { key: CATALOG_SORT_SETTING_KEY },
      create: {
        key: CATALOG_SORT_SETTING_KEY,
        category: 'social-settings',
        description: 'Customer-facing Social Media service sort mode.',
        value: value as unknown as Prisma.InputJsonValue,
      },
      update: { category: 'social-settings', value: value as unknown as Prisma.InputJsonValue },
    });
    await audit(prisma, admin.id, 'SOCIAL_CATALOG_SORT_UPDATE', 'SystemSetting', CATALOG_SORT_SETTING_KEY, `Catalog sort mode: ${mode}`, value as unknown as Prisma.InputJsonValue);
    return reply.code(303).redirect(`/admin/social?tab=services&msg=${encodeURIComponent(mode === 'PRICE_ASC' ? 'نمایش سرویس‌ها روی ارزان‌ترین اول تنظیم شد' : mode === 'PRICE_DESC' ? 'نمایش سرویس‌ها روی گران‌ترین اول تنظیم شد' : 'نمایش سرویس‌ها روی ترتیب دستی تنظیم شد')}`);
  });

  app.post('/admin/social/catalog/publish', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const routeId = text(body, 'routeId');
    const providerId = text(body, 'providerId');
    const categorySlug = text(body, 'categorySlug');
    try {
      const route = await prisma.serviceProviderRoute.findFirst({
        where: { id: routeId, provider: { kind: ProviderKind.SOCIAL } },
        include: { service: true, provider: true },
      });
      if (!route) throw new Error('ROUTE_NOT_FOUND');
      const categorySetting = await prisma.systemSetting.findUnique({ where: { key: categoryKey(categorySlug) } });
      const category = categorySetting ? parseCategory(categorySetting) : null;
      if (!category || !category.enabled) throw new Error('CATEGORY_NOT_FOUND');
      const pricingMode = text(body, 'pricingMode') === 'FIXED' ? 'FIXED' : 'AUTO_MARKUP';
      let basePriceAfn: bigint | null = null;
      if (pricingMode === 'FIXED') {
        const fixedPrice = decimalValue(body.fixedPrice, '0');
        if (new Prisma.Decimal(fixedPrice).lte(0)) throw new Error('FIXED_PRICE_REQUIRED');
        basePriceAfn = await convertSocialPriceToAfn(prisma, fixedPrice, text(body, 'fixedCurrency') || 'AFN');
      }
      const markup = new Prisma.Decimal(decimalValue(body.markup, route.provider.defaultMarkupPercent.toString()));
      const oldMeta = jsonObject(route.service.metadata);
      await prisma.$transaction([
        prisma.service.update({
          where: { id: route.serviceId },
          data: {
            titleFa: text(body, 'titleFa') || route.service.titleFa,
            titleEn: text(body, 'titleEn') || route.service.titleEn,
            descriptionFa: text(body, 'descriptionFa') || null,
            enabled: checked(body, 'enabled'),
            socialPlatform: category.platform,
            socialGroup: category.slug,
            basePriceAfn,
            minQty: intValue(body.minQty, route.providerMinQty ?? 1),
            maxQty: intValue(body.maxQty, route.providerMaxQty ?? 1000000),
            sortOrder: intValue(body.sortOrder, 100),
            metadata: {
              ...oldMeta,
              rawCatalog: false,
              pricingMode,
              categorySlug: category.slug,
              publishedFromProviderId: route.providerId,
              publishedAt: new Date().toISOString(),
            } as Prisma.InputJsonValue,
          },
        }),
        prisma.serviceProviderRoute.update({
          where: { id: route.id },
          data: { enabled: true, markupPercent: pricingMode === 'AUTO_MARKUP' ? markup : route.markupPercent },
        }),
      ]);
      await audit(prisma, admin.id, 'SOCIAL_SERVICE_PUBLISH', 'Service', route.serviceId, `${category.titleFa} → ${text(body, 'titleFa') || route.service.titleFa}`, {
        providerId: route.providerId,
        providerServiceCode: route.providerServiceCode,
        pricingMode,
        markup: markup.toString(),
        fixedAfn: basePriceAfn?.toString() ?? null,
      });
      return reply.code(303).redirect(`/admin/social?tab=catalog&provider=${encodeURIComponent(providerId)}&route=${encodeURIComponent(routeId)}&msg=${encodeURIComponent('سرویس در VELIXEO منتشر شد')}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=catalog&provider=${encodeURIComponent(providerId)}&route=${encodeURIComponent(routeId)}&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'publish_failed')}`);
    }
  });

  app.post('/admin/social/routing/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as AnyBody;
    const routeId = text(body, 'routeId');
    try {
      const route = await prisma.serviceProviderRoute.update({
        where: { id: routeId },
        data: {
          priority: intValue(body.priority, 100),
          markupPercent: text(body, 'markup') ? new Prisma.Decimal(decimalValue(body.markup, '0')) : null,
          enabled: checked(body, 'enabled'),
        },
      });
      await audit(prisma, admin.id, 'SOCIAL_ROUTE_UPDATE', 'ServiceProviderRoute', route.id, `Route ${route.providerServiceCode} updated`);
      return reply.code(303).redirect('/admin/social?tab=routing&msg=Route Save شد');
    } catch (error) {
      return reply.code(303).redirect(`/admin/social?tab=routing&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'route_failed')}`);
    }
  });
}
