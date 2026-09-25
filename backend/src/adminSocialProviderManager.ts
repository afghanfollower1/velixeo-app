import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  Prisma,
  PrismaClient,
  ProviderKind,
  ServiceCategory,
  type Provider,
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
import { brandSettingKey, defaultBrandIcons, loadSocialBrands, normalizeBrandKey, parseBrand, validateBrandIcon, type SocialBrand } from './socialBrands.js';
import { getSocialOrderSettings, saveSocialOrderSettings } from './socialOrderSettings.js';
import { normalizeCurrencyCode } from './currency.js';
import { renderAdminV3Page } from './adminFigmaEnglish.js';
import { adminLangFromRequest } from './adminLocale.js';

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};
type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type Body = Record<string, unknown>;
type Query = Record<string, unknown>;
type ProviderMeta = {
  websiteUrl: string;
  defaultCurrency: string;
  description: string;
};
type SocialCategory = {
  slug: string;
  titleEn: string;
  titleFa: string;
  platform: string;
  descriptionEn: string;
  descriptionFa: string;
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
const text = (body: Body, key: string) => String(body[key] ?? '').trim();
const checked = (body: Body, key: string) => ['on', 'true', '1'].includes(String(body[key] ?? ''));
const intValue = (value: unknown, fallback = 0) => {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
};
const jsonObject = (value: Prisma.JsonValue | null | undefined): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
const money = (value: bigint | number | string | null | undefined) =>
  `${Number(value ?? 0).toLocaleString('en-US')} AFN`;
const dateText = (value: Date | string | null | undefined, fa = false) => {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString(fa ? 'fa-AF' : 'en-US', { dateStyle: 'medium', timeStyle: 'short' });
  } catch {
    return '—';
  }
};
const safeSlug = (value: string) =>
  value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
const categoryKey = (slug: string) => `social.category.${slug}`;
const providerMetaKey = (providerId: string) => `social.provider.meta.${providerId}`;

async function requireAdmin(
  request: FastifyRequest,
  reply: FastifyReply,
  resolveAdmin: AdminResolver,
) {
  const admin = await resolveAdmin(request);
  if (!admin) {
    reply.code(303).redirect('/admin/login');
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

async function getProviderMeta(prisma: PrismaClient, providerId: string): Promise<ProviderMeta> {
  const setting = await prisma.systemSetting.findUnique({ where: { key: providerMetaKey(providerId) } });
  const row = jsonObject(setting?.value);
  return {
    websiteUrl: typeof row.websiteUrl === 'string' ? row.websiteUrl : '',
    defaultCurrency: typeof row.defaultCurrency === 'string' ? row.defaultCurrency : 'USD',
    description: typeof row.description === 'string' ? row.description : '',
  };
}

async function saveProviderMeta(prisma: PrismaClient, providerId: string, value: ProviderMeta) {
  await prisma.systemSetting.upsert({
    where: { key: providerMetaKey(providerId) },
    create: {
      key: providerMetaKey(providerId),
      category: 'social-provider-meta',
      description: 'Admin-facing social provider metadata.',
      value: value as unknown as Prisma.InputJsonValue,
    },
    update: {
      category: 'social-provider-meta',
      value: value as unknown as Prisma.InputJsonValue,
    },
  });
}

function parseCategory(setting: { key: string; value: Prisma.JsonValue }): SocialCategory | null {
  const row = jsonObject(setting.value);
  const slug = typeof row.slug === 'string'
    ? row.slug
    : setting.key.replace(/^social\.category\./, '');
  if (!slug) return null;
  return {
    slug,
    titleEn: typeof row.titleEn === 'string' ? row.titleEn : slug,
    titleFa: typeof row.titleFa === 'string' ? row.titleFa : (typeof row.titleEn === 'string' ? row.titleEn : slug),
    platform: typeof row.platform === 'string' ? row.platform : 'OTHER',
    descriptionEn: typeof row.descriptionEn === 'string' ? row.descriptionEn : '',
    descriptionFa: typeof row.descriptionFa === 'string' ? row.descriptionFa : '',
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
    .filter((item): item is SocialCategory => item !== null)
    .sort((a, b) => a.sortOrder - b.sortOrder || a.titleEn.localeCompare(b.titleEn));
}

function icon(name: string) {
  const paths: Record<string, string> = {
    back: '<path d="M19 12H5m6-6-6 6 6 6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    edit: '<path d="M4 20h4l11-11-4-4L4 16v4zM13.5 6.5l4 4"/>',
    link: '<path d="M10 13a5 5 0 0 0 7.1.1l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1M14 11a5 5 0 0 0-7.1-.1l-2 2A5 5 0 0 0 12 20l1.1-1.1"/>',
    wallet: '<path d="M3 6h16a2 2 0 0 1 2 2v10H3a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h14M16 12h5"/>',
    sync: '<path d="M20 7h-5V2M4 17h5v5M19 12a7 7 0 0 0-12-5L4 10M5 12a7 7 0 0 0 12 5l3-3"/>',
    list: '<path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/>',
    trash: '<path d="M3 6h18M8 6V4h8v2M7 6l1 14h8l1-14M10 10v6M14 10v6"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
    category: '<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"/>',
    service: '<path d="M12 2l2.5 5 5.5.8-4 3.9.9 5.5L12 14.6 7.1 17.2 8 11.7 4 7.8 9.5 7z"/>',
    provider: '<path d="M5 5h14v5H5zM5 14h14v5H5zM8 7.5h.01M8 16.5h.01"/>',
  };
  return `<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.service}</svg>`;
}

const socialManagerCss = `
<style id="velixeo-social-manager-components">
.provider-name{display:flex;align-items:center;gap:10px;min-width:0}
.provider-name>div:last-child{min-width:0}
.provider-logo{width:36px;height:36px;border-radius:12px;background:#edf8fd;display:grid;place-items:center;color:#369fca;font-weight:800;flex:0 0 auto}
.switch{display:inline-flex;align-items:center;gap:7px}.switch form{margin:0}
.switch button{width:40px;height:23px;border:0;border-radius:99px;position:relative;cursor:pointer;background:#cbd6e1;padding:0}
.switch button.on{background:#38bdf8}
.switch button:after{content:'';position:absolute;top:3px;left:3px;width:17px;height:17px;background:#fff;border-radius:50%;transition:.2s}
.switch button.on:after{left:20px}
.split-title{display:flex;gap:9px;align-items:center}
.price-auto{color:#158365;font-weight:700}.price-fixed{color:#7661c9;font-weight:700}
.service-name{max-width:430px;line-height:1.5;overflow-wrap:anywhere}
.searchbar{display:flex;gap:9px;align-items:center;flex-wrap:wrap}
.searchbar input,.searchbar select{height:42px;border:1px solid var(--line);border-radius:12px;padding:0 12px;background:#fff;min-width:170px}
.source-categories{display:flex;gap:8px;overflow:auto;padding:4px 0 12px;scrollbar-width:thin;overscroll-behavior-inline:contain}
.source-category{flex:0 0 auto;display:inline-flex;align-items:center;gap:8px;padding:9px 12px;border:1px solid var(--line);border-radius:12px;background:#fff;text-decoration:none;color:#74818b;font-size:12px}
.source-category:hover{border-color:#9edcf4;background:#f7fbfd;color:#2288b1}
.source-category.active{background:#eef9fe;border-color:#9edcf4;color:#2288b1;font-weight:650}
.source-category .count{display:inline-grid;place-items:center;min-width:24px;height:21px;padding:0 7px;border-radius:8px;background:#f0f3f6;color:#65798e;font-size:10px}
.source-category.active .count{background:#fff;color:#2288b1}
.catalog-title{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
.tiny{font-size:10px;color:var(--muted);line-height:1.7}
.iconbtn{width:36px;height:36px;border-radius:10px;border:1px solid var(--line);background:#fff;color:#65798e;display:inline-grid;place-items:center;cursor:pointer;text-decoration:none;padding:0;flex:0 0 auto}
.iconbtn:hover{color:#2288b1;border-color:#9edcf4;background:#f7fbfd}.iconbtn.green{color:#158365}.iconbtn.red{color:#c54152}.iconbtn.purple{color:#7661c9}.iconbtn.orange{color:#ad670d}
.provider-picker{display:grid;grid-template-columns:minmax(220px,320px) minmax(220px,1fr) auto;gap:10px;align-items:end}
.refill-control{display:flex;align-items:center;justify-content:space-between;gap:14px;padding:13px 14px;border:1px solid var(--line);border-radius:14px;background:#fbfdfe;margin:8px 0 14px}
.refill-control .meta{font-size:11px;color:var(--muted);line-height:1.7}
.refill-control .toggle{display:inline-flex;align-items:center;gap:9px;font-size:12px;font-weight:650}
.refill-control .toggle input{width:19px;height:19px;accent-color:#38bdf8}
.provider-capability{display:flex;gap:7px;flex-wrap:wrap;margin-top:7px}
#route-content .table{width:100%;min-width:0;table-layout:auto}
#route-content .table th,#route-content .table td{white-space:normal;overflow-wrap:anywhere;vertical-align:middle}
#route-content .tablewrap{max-width:100%;overflow:auto;scrollbar-gutter:stable;overscroll-behavior-inline:contain}
#route-content .actions{flex-wrap:wrap}
#route-content .card{margin-bottom:18px}
.service-config-panel{scroll-margin-top:18px;border-color:#cfe9f6!important;box-shadow:0 16px 40px rgba(54,143,181,.08)}
.service-config-feedback{display:none;margin:0 0 12px;padding:10px 12px;border-radius:12px;font-size:11px;font-weight:650}
.service-config-feedback.ok{display:block;background:#eaf8f2;color:#147956}
.service-config-feedback.bad{display:block;background:#fff1f2;color:#b83949}
html.vx-admin-fa #route-content .provider-name,html.vx-admin-fa #route-content .split-title,html.vx-admin-fa #route-content .searchbar{direction:rtl}
html.vx-admin-en #route-content .provider-name,html.vx-admin-en #route-content .split-title,html.vx-admin-en #route-content .searchbar{direction:ltr}
html.vx-admin-fa #route-content .source-categories{direction:rtl}
html.vx-admin-en #route-content .source-categories{direction:ltr}
@media(max-width:1500px){
  #route-content table.responsive-admin-table,#route-content table.responsive-admin-table tbody{display:block;width:100%}
  #route-content table.responsive-admin-table thead{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
  #route-content table.responsive-admin-table tbody{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
  #route-content table.responsive-admin-table tbody tr{display:block;min-width:0;border:1px solid var(--line);border-radius:16px;padding:8px 13px;background:#fff}
  #route-content table.responsive-admin-table tbody td{display:grid;grid-template-columns:minmax(105px,.75fr) minmax(0,1.25fr);gap:10px;width:100%;padding:9px 0;border:0;border-bottom:1px solid #edf2f5;text-align:start}
  #route-content table.responsive-admin-table tbody td::before{content:attr(data-label);font-size:10px;color:#91a3ae;font-weight:650}
  #route-content table.responsive-admin-table tbody td:first-child{display:block;padding:10px 0 12px}
  #route-content table.responsive-admin-table tbody td:first-child::before{display:none}
  #route-content table.responsive-admin-table tbody td:last-child{border-bottom:0}
  #route-content table.responsive-admin-table tbody td[colspan]{display:block;text-align:center}
  #route-content table.responsive-admin-table tbody td[colspan]::before{display:none}
}
@media(max-width:900px){
  #route-content table.responsive-admin-table tbody{grid-template-columns:1fr}
  .provider-picker{grid-template-columns:1fr}
  .provider-picker .btn{width:100%}
  .refill-control{align-items:flex-start;flex-direction:column}
}
@media(max-width:680px){
  .searchbar{align-items:stretch}.searchbar form{width:100%}.searchbar input,.searchbar select{width:100%}
  #route-content .card{padding:14px}
  #route-content table.responsive-admin-table tbody td{grid-template-columns:minmax(90px,.7fr) minmax(0,1.3fr)}
}
</style>`;

function pill(label: string, kind = '') {
  return `<span class="pill ${kind}">${esc(label)}</span>`;
}

function socialTabs(active: string) {
  const items = [
    ['/admin/v3?section=social&tab=overview', 'Overview', 'overview'],
    ['/admin/v3/social/providers', 'Providers', 'providers'],
    ['/admin/v3/social/provider-services', 'Provider Services', 'provider-services'],
    ['/admin/v3/social/my-services', 'Services', 'services'],
    ['/admin/v3/social/brands', 'Brands', 'brands'],
    ['/admin/v3/social/categories', 'Categories', 'categories'],
    ['/admin/v3/social/order-settings', 'Order Settings', 'order-settings'],
    ['/admin/v3?section=social&tab=routing', 'Routing', 'routing'],
    ['/admin/v3?section=social&tab=orders', 'Orders', 'orders'],
    ['/admin/v3?section=social&tab=logs', 'API Logs', 'logs'],
  ];
  return `<div class="tabs">${items.map(([url, label, key]) =>
    `<a class="tab ${active === key ? 'active' : ''}" href="${url}">${label}</a>`
  ).join('')}</div>`;
}

function shell(input: {
  request: FastifyRequest;
  admin: AdminIdentity;
  title: string;
  subtitle: string;
  active: string;
  body: string;
  message?: string;
  error?: boolean;
  script?: string;
}) {
  const lang = adminLangFromRequest(input.request);
  const behavior = `
<script id="velixeo-social-manager-behavior">
(()=>{
  document.querySelectorAll('#route-content table').forEach(table=>{
    table.classList.add('responsive-admin-table');
    const labels=Array.from(table.querySelectorAll('thead th')).map(cell=>(cell.textContent||'').trim());
    table.querySelectorAll('tbody tr').forEach(row=>{
      Array.from(row.children).forEach((cell,index)=>{
        if(!cell.dataset.label)cell.dataset.label=labels[index]||'';
      });
    });
  });
  document.querySelectorAll('#route-content .tablewrap,#route-content .source-categories').forEach(scroller=>{
    scroller.addEventListener('wheel',event=>{
      if(scroller.scrollWidth<=scroller.clientWidth)return;
      if(Math.abs(event.deltaY)<=Math.abs(event.deltaX))return;
      event.preventDefault();
      scroller.scrollLeft+=event.deltaY;
    },{passive:false});
  });
  const panel=document.querySelector('[data-service-config]');
  if(panel)requestAnimationFrame(()=>panel.scrollIntoView({behavior:'smooth',block:'start'}));
})();
</script>`;
  const pageBody = socialManagerCss
    + input.body
    + behavior
    + (input.script ? `<script id="velixeo-social-manager-script">${input.script}</script>` : '');
  return renderAdminV3Page(
    input.admin,
    'social',
    pageBody,
    socialTabs(input.active),
    input.message ?? '',
    input.error ?? false,
    lang,
    input.title,
    input.subtitle,
  );
}

function query(request: FastifyRequest) {
  const q = (request.query ?? {}) as Query;
  return {
    provider: String(q.provider ?? '').trim(),
    route: String(q.route ?? '').trim(),
    edit: String(q.edit ?? '').trim(),
    mode: String(q.mode ?? '').trim(),
    q: String(q.q ?? '').trim().slice(0, 150),
    sourceCategory: String(q.sourceCategory ?? '').trim().slice(0, 240),
    msg: String(q.msg ?? '').trim(),
    error: String(q.error ?? '') === '1',
  };
}

function providerForm(
  provider: Provider | null,
  meta: ProviderMeta,
  sync: Awaited<ReturnType<typeof getSocialProviderSyncConfig>>,
  currencies: string[],
) {
  const selectedCurrency = provider?.currencyCode || meta.defaultCurrency || 'USD';
  const common = ['AUTO','AFN','USD','TOMAN'];
  const currencyValues = [...new Set([...common, ...currencies.map(code => code.toUpperCase()), selectedCurrency.toUpperCase()])];
  const currencyOptions = currencyValues.map(code =>
    `<option value="${esc(code)}" ${selectedCurrency.toUpperCase()===code?'selected':''}>${esc(code === 'AUTO' ? 'AUTO / Provider API' : code)}</option>`
  ).join('');
  return `<form method="post" action="/admin/v3/social/providers/save"><input type="hidden" name="id" value="${esc(provider?.id || '')}"><div class="forms"><div class="field"><label>Provider Name</label><input name="name" value="${esc(provider?.name || '')}" placeholder="JustAnotherPanel" required></div><div class="field"><label>Slug (optional)</label><input class="mono" name="slug" value="${esc(provider?.slug || '')}" placeholder="auto-generated-from-name"><span class="tiny">Leave blank and VELIXEO creates a unique slug automatically.</span></div><div class="field"><label>Website URL</label><input class="mono" name="websiteUrl" value="${esc(meta.websiteUrl)}" placeholder="https://provider.com"></div><div class="field"><label>API Endpoint / Base URL</label><input class="mono" name="baseUrl" value="${esc(provider?.baseUrl || '')}" placeholder="https://provider.com/api/v2" required></div><div class="field"><label>Default Provider Currency</label><select name="currency">${currencyOptions}</select><span class="tiny">All provider prices are converted to AFN. Add extra currencies and AFN rates in Settings → Exchange Rates.</span></div><div class="field"><label>Default Profit / Markup %</label><input name="markup" inputmode="decimal" value="${esc(provider?.defaultMarkupPercent?.toString() || '0')}" placeholder="30"></div><div class="field"><label>Priority</label><input type="number" name="priority" value="${esc(provider?.priority ?? 20)}"><span class="tiny">Lower number is preferred first.</span></div><div class="field"><label>Timeout (seconds)</label><input type="number" min="5" max="120" name="timeout" value="${esc(provider?.timeoutSeconds ?? 30)}"></div><div class="field"><label>Auto Service Sync</label><select name="autoSync"><option value="1" ${sync.autoSync?'selected':''}>Enabled</option><option value="0" ${!sync.autoSync?'selected':''}>Disabled</option></select></div><div class="field"><label>Service Sync Interval (minutes)</label><input type="number" min="1" max="1440" name="syncMinutes" value="${esc(sync.syncMinutes)}"></div></div><div class="field"><label>API Key / Secret ${provider ? '(leave blank to keep current key)' : '(optional — can be added later)'}</label><textarea class="mono" name="secret" placeholder="Paste the provider API key here"></textarea><span class="tiny">You can save the provider first and add the API key later. Sync and ordering will stay disabled until a valid key is configured. Secrets are encrypted before storage.</span></div><div class="field"><label>Description / Internal Notes</label><textarea name="description" placeholder="Internal notes about this provider">${esc(meta.description || provider?.notes || '')}</textarea></div><label class="check"><input type="checkbox" name="enabled" ${provider?.enabled===false?'':'checked'}> Provider enabled</label><div class="actions"><button class="btn">${provider ? 'Save Provider' : 'Add Provider'}</button><a class="btn ghost" href="/admin/v3/social/providers">Cancel</a></div></form>`;
}

async function providerStatus(provider: Provider) {
  if (!provider.enabled) return { status: 'Disabled', kind: 'bad', balance: '—', currency: '' };
  if (!provider.secretCiphertext) return { status: 'API key missing', kind: 'warn', balance: '—', currency: '' };
  try {
    const balance = await smmClientForProvider(provider).balance();
    return {
      status: 'Connected',
      kind: 'ok',
      balance: balance.balance,
      currency: balance.currency || '',
    };
  } catch (error) {
    return {
      status: 'Connection error',
      kind: 'warn',
      balance: '—',
      currency: '',
      error: error instanceof Error ? error.message.slice(0, 160) : 'provider_error',
    };
  }
}

async function providersPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const fa = adminLangFromRequest(request) === 'fa';
  const l = (faText: string, enText: string) => fa ? faText : enText;
  const n = (value: number) => value.toLocaleString(fa ? 'fa-AF' : 'en-US');
  const providers = await prisma.provider.findMany({
    where: { kind: ProviderKind.SOCIAL },
    orderBy: [{ enabled: 'desc' }, { priority: 'asc' }, { name: 'asc' }],
  });

  if (q.mode === 'new' || q.edit) {
    const selected = q.edit
      ? await prisma.provider.findFirst({ where: { id: q.edit, kind: ProviderKind.SOCIAL } })
      : null;
    if (q.edit && !selected) {
      return shell({
        request,
        admin,
        title: 'Providers',
        subtitle: 'Provider not found',
        active: 'providers',
        body: `<div class="card empty">${l('ارائه‌دهنده انتخاب‌شده وجود ندارد.','The selected provider does not exist.')}</div>`,
        message: q.msg,
        error: q.error,
      });
    }
    const [meta, rateRows] = await Promise.all([
      selected ? getProviderMeta(prisma, selected.id) : Promise.resolve({ websiteUrl: '', defaultCurrency: 'USD', description: '' }),
      prisma.exchangeRate.findMany({ select: { code: true }, orderBy: { code: 'asc' } }),
    ]);
    const sync = selected
      ? await getSocialProviderSyncConfig(prisma, selected.id)
      : { autoSync: true, syncMinutes: 10, lastSyncAt: null, lastSyncStatus: 'idle' as const, lastSyncError: null, lastServiceCount: 0, lastCreatedCount: 0, lastUpdatedCount: 0 };
    const currencies = rateRows.map(row => row.code);
    return shell({
      request,
      admin,
      title: selected ? 'Edit Provider' : 'Add New Provider',
      subtitle: selected ? 'Update connection, pricing and synchronization settings.' : 'Add an SMM API provider and connect its service catalog.',
      active: 'providers',
      message: q.msg,
      error: q.error,
      body: `<div class="card" style="max-width:920px;margin:0 auto"><div class="cardhead"><div class="split-title">${icon('provider')}<div><h2>${selected ? esc(selected.name) : l('جزئیات ارائه‌دهنده','Provider Details')}</h2><span class="muted">${l('اطلاعات اتصال و قوانین سرویس','Connection credentials and business rules')}</span></div></div><a class="btn ghost" href="/admin/v3/social/providers">${icon('back')} ${l('بازگشت به ارائه‌دهندگان','Back to Providers')}</a></div>${providerForm(selected, meta, sync, currencies)}</div>`,
    });
  }

  const data = await Promise.all(providers.map(async provider => {
    const [meta, sync, serviceCount] = await Promise.all([
      getProviderMeta(prisma, provider.id),
      getSocialProviderSyncConfig(prisma, provider.id),
      prisma.serviceProviderRoute.count({ where: { providerId: provider.id } }),
    ]);
    return { provider, meta, sync, serviceCount };
  }));

  const rows = data.map(({ provider, meta, sync, serviceCount }) => {
    const enabled = provider.enabled;
    const toggleTitle = enabled ? l('غیرفعال کردن ارائه‌دهنده','Disable provider') : l('فعال کردن ارائه‌دهنده','Enable provider');
    const deleteConfirm = l(
      'این ارائه‌دهنده حذف شود؟ سرویس‌های خام واردشده نیز حذف می‌شوند و سرویس‌های منتشرشده بدون مسیر دیگر مخفی خواهند شد.',
      'Delete this provider? Raw imported services will also be removed. Published services without another route will be hidden.',
    ).replaceAll("'", "\\'");
    return `<tr>
      <td><div class="provider-name"><div class="provider-logo">${esc(provider.name.charAt(0).toUpperCase())}</div><div><b>${esc(provider.name)}</b><br><span class="mono muted">${esc(provider.slug)}</span></div></div></td>
      <td><span id="balance-${provider.id}" class="pill info">${l('در حال بررسی…','Checking…')}</span><br><span id="balance-time-${provider.id}" class="tiny">${l('بروزرسانی خودکار: ۶۰ ثانیه','Auto refresh: 60 sec')}</span></td>
      <td>${esc(provider.currencyCode || meta.defaultCurrency || 'AUTO')}</td>
      <td><b>${n(serviceCount)}</b><br><span class="tiny">${l('آخرین همگام‌سازی API:','API last sync:')} ${n(sync.lastServiceCount)}</span></td>
      <td>${sync.autoSync ? pill(l(`هر ${n(sync.syncMinutes)} دقیقه`,`Every ${sync.syncMinutes} min`),'ok') : pill(l('خاموش','Off'))}<br><span class="tiny">${l('آخرین:','Last:')} ${esc(dateText(sync.lastSyncAt, fa))}</span></td>
      <td><span id="status-${provider.id}">${enabled ? pill(l('فعال','Enabled'),'ok') : pill(l('غیرفعال','Disabled'),'bad')}</span></td>
      <td><div class="switch"><form method="post" action="/admin/v3/social/providers/toggle"><input type="hidden" name="id" value="${provider.id}"><button class="${enabled?'on':''}" title="${toggleTitle}" aria-label="${toggleTitle}"></button></form></div></td>
      <td><div class="actions">
        ${meta.websiteUrl
          ? `<a class="iconbtn orange" href="${esc(meta.websiteUrl)}" target="_blank" rel="noreferrer" title="${l('باز کردن وب‌سایت ارائه‌دهنده','Open provider website')}" aria-label="${l('باز کردن وب‌سایت ارائه‌دهنده','Open provider website')}">${icon('link')}</a>`
          : `<span class="iconbtn" title="${l('وب‌سایت ارائه‌دهنده تنظیم نشده','No provider website configured')}" aria-label="${l('وب‌سایت ارائه‌دهنده تنظیم نشده','No provider website configured')}">${icon('link')}</span>`}
        <a class="iconbtn" href="/admin/v3/social/providers?edit=${provider.id}" title="${l('ویرایش ارائه‌دهنده','Edit provider')}" aria-label="${l('ویرایش ارائه‌دهنده','Edit provider')}">${icon('edit')}</a>
        <button type="button" class="iconbtn purple" onclick="refreshProviderStatuses()" title="${l('بررسی موجودی','Check balance now')}" aria-label="${l('بررسی موجودی','Check balance now')}">${icon('wallet')}</button>
        <form method="post" action="/admin/v3/social/provider-services/sync"><input type="hidden" name="providerId" value="${provider.id}"><button class="iconbtn green" title="${l('همگام‌سازی سرویس‌های ارائه‌دهنده','Synchronize provider services')}" aria-label="${l('همگام‌سازی سرویس‌های ارائه‌دهنده','Synchronize provider services')}">${icon('sync')}</button></form>
        <a class="iconbtn" href="/admin/v3/social/provider-services?provider=${provider.id}" title="${l('فهرست سرویس‌های ارائه‌دهنده','Provider service list')}" aria-label="${l('فهرست سرویس‌های ارائه‌دهنده','Provider service list')}">${icon('list')}</a>
        <form method="post" action="/admin/v3/social/providers/delete" onsubmit="return confirm('${deleteConfirm}');"><input type="hidden" name="id" value="${provider.id}"><button class="iconbtn red" title="${l('حذف ارائه‌دهنده','Delete provider')}" aria-label="${l('حذف ارائه‌دهنده','Delete provider')}">${icon('trash')}</button></form>
      </div></td>
    </tr>`;
  }).join('');

  const statusLabels = fa
    ? { Connected: 'متصل', Disabled: 'غیرفعال', 'API key missing': 'کلید API ثبت نشده', 'Connection error': 'خطای اتصال' }
    : { Connected: 'Connected', Disabled: 'Disabled', 'API key missing': 'API key missing', 'Connection error': 'Connection error' };
  const script = `
const providerStatusLabels=${JSON.stringify(statusLabels)};
async function refreshProviderStatuses(){
  try{
    const response=await fetch('/admin/v3/social/provider-status',{headers:{Accept:'application/json'},cache:'no-store'});
    if(!response.ok)return;
    const payload=await response.json();
    for(const item of payload.providers||[]){
      const b=document.getElementById('balance-'+item.id);
      const s=document.getElementById('status-'+item.id);
      const tm=document.getElementById('balance-time-'+item.id);
      if(b){b.textContent=item.balance==='—'?'—':(item.balance+' '+(item.currency||''));b.className='pill '+(item.kind||'info');}
      if(s){const label=providerStatusLabels[item.status]||item.status;s.innerHTML='<span class="pill '+(item.kind||'info')+'">'+label+'</span>';}
      if(tm){tm.textContent=${JSON.stringify(l('بروزرسانی','Updated'))}+' '+new Date(payload.updatedAt).toLocaleTimeString(${JSON.stringify(fa ? 'fa-AF' : 'en-US')});}
    }
  }catch(_error){}
}
refreshProviderStatuses();
setInterval(refreshProviderStatuses,60000);
`;

  return shell({
    request,
    admin,
    title: 'Providers',
    subtitle: 'Add, monitor and manage every SMM API provider from one place.',
    active: 'providers',
    message: q.msg,
    error: q.error,
    script,
    body: `<div class="card"><div class="cardhead"><div><h2>${l('ارائه‌دهندگان SMM','SMM Providers')}</h2><span class="muted">${l('تا زمانی که این صفحه باز است، موجودی هر ۶۰ ثانیه به‌صورت خودکار بررسی می‌شود.','Balances are checked automatically every 60 seconds while this page is open.')}</span></div><a class="btn" href="/admin/v3/social/providers?mode=new">${icon('plus')} ${l('افزودن ارائه‌دهنده','Add Provider')}</a></div><div class="tablewrap"><table class="table"><thead><tr><th>${l('ارائه‌دهنده','Provider')}</th><th>${l('موجودی زنده','Live Balance')}</th><th>${l('واحد پول','Currency')}</th><th>${l('سرویس‌ها','Services')}</th><th>${l('همگام‌سازی سرویس‌ها','Service Sync')}</th><th>${l('اتصال','Connection')}</th><th>${l('فعال','Active')}</th><th>${l('عملیات','Actions')}</th></tr></thead><tbody>${rows || `<tr><td colspan="8" class="empty">${l('هنوز ارائه‌دهنده‌ای اضافه نشده است.','No providers yet. Add your first SMM provider.')}</td></tr>`}</tbody></table></div></div><div class="notice"><b>${l('راهنما:','How it works:')}</b> ${l('آیکن لینک وب‌سایت را باز می‌کند · ویرایش تنظیمات را تغییر می‌دهد · موجودی API را بررسی می‌کند · همگام‌سازی کاتالوگ را بروزرسانی می‌کند · آیکن فهرست، سرویس‌های همان ارائه‌دهنده را باز می‌کند · حذف، ارائه‌دهنده را ایمن حذف می‌کند.','Website opens the provider site · Edit changes settings · Balance checks the API · Sync downloads/updates the provider catalog · Service List opens that provider’s services · Delete removes the provider safely.')}</div>`,
  });
}

async function providerServicesPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const fa = adminLangFromRequest(request) === 'fa';
  const l = (faText: string, enText: string) => fa ? faText : enText;
  const n = (value: number) => value.toLocaleString(fa ? 'fa-AF' : 'en-US');
  const providers = await prisma.provider.findMany({
    where: { kind: ProviderKind.SOCIAL },
    orderBy: [{ enabled: 'desc' }, { priority: 'asc' }, { name: 'asc' }],
  });
  const providerId = q.provider || providers[0]?.id || '';
  const provider = providers.find(item => item.id === providerId) ?? null;
  const [categories, brands] = await Promise.all([loadCategories(prisma), loadSocialBrands(prisma)]);

  const sourceIndexRows = providerId
    ? await prisma.serviceProviderRoute.findMany({
        where: { providerId },
        select: { providerCategory: true, metadata: true },
      })
    : [];
  const sourceCategoryMap = new Map<string, { count: number; firstIndex: number }>();
  for (const row of sourceIndexRows) {
    const name = (row.providerCategory || 'Uncategorized').trim() || 'Uncategorized';
    const meta = jsonObject(row.metadata);
    const rawIndex = Number(meta._velixeoCatalogIndex);
    const index = Number.isFinite(rawIndex) ? rawIndex : Number.MAX_SAFE_INTEGER;
    const current = sourceCategoryMap.get(name);
    if (current) {
      current.count += 1;
      current.firstIndex = Math.min(current.firstIndex, index);
    } else {
      sourceCategoryMap.set(name, { count: 1, firstIndex: index });
    }
  }
  const sourceCategories = [...sourceCategoryMap.entries()]
    .map(([name, data]) => ({ name, ...data }))
    .sort((a, b) => a.firstIndex - b.firstIndex || a.name.localeCompare(b.name));

  const activeSourceCategory = q.q
    ? q.sourceCategory
    : (q.sourceCategory || sourceCategories[0]?.name || '');

  const where: Prisma.ServiceProviderRouteWhereInput = providerId
    ? {
        providerId,
        ...(activeSourceCategory
          ? { providerCategory: activeSourceCategory === 'Uncategorized' ? null : activeSourceCategory }
          : {}),
        ...(q.q ? {
          OR: [
            { providerServiceCode: { contains: q.q, mode: 'insensitive' } },
            { providerName: { contains: q.q, mode: 'insensitive' } },
            { providerCategory: { contains: q.q, mode: 'insensitive' } },
          ],
        } : {}),
      }
    : { id: '__none__' };

  const routes = await prisma.serviceProviderRoute.findMany({
    where,
    include: { provider: true, service: true },
    orderBy: [{ providerServiceCode: 'asc' }],
  });

  routes.sort((a, b) => {
    const ai = Number(jsonObject(a.metadata)._velixeoCatalogIndex);
    const bi = Number(jsonObject(b.metadata)._velixeoCatalogIndex);
    const av = Number.isFinite(ai) ? ai : Number.MAX_SAFE_INTEGER;
    const bv = Number.isFinite(bi) ? bi : Number.MAX_SAFE_INTEGER;
    return av - bv || String(a.providerServiceCode).localeCompare(String(b.providerServiceCode));
  });

  const priced = await Promise.all(routes.map(async route => ({
    route,
    sale: await socialRouteSaleRateAfn(prisma, route.service, route),
  })));

  const selected = q.route
    ? await prisma.serviceProviderRoute.findFirst({
        where: { id: q.route, provider: { kind: ProviderKind.SOCIAL } },
        include: { provider: true, service: true },
      })
    : null;
  const selectedMeta = selected ? jsonObject(selected.service.metadata) : {};
  const selectedRouteMeta = selected ? jsonObject(selected.metadata) : {};
  const isPublished = selected ? selectedMeta.rawCatalog !== true : false;
  const selectedCategorySlug = String(selectedMeta.categorySlug || selected?.service.socialGroup || '');
  const selectedCategory = categories.find(item => item.slug === selectedCategorySlug) ?? null;
  const selectedBrand = normalizeBrandKey(selectedCategory?.platform || selected?.service.socialPlatform || '');
  const detectedRefill = selected
    ? (typeof selectedRouteMeta._providerRefillDetected === 'boolean'
        ? selectedRouteMeta._providerRefillDetected
        : selected.providerRefill)
    : false;
  const detectedDripFeed = selected
    ? (typeof selectedRouteMeta._providerDripFeedDetected === 'boolean'
        ? selectedRouteMeta._providerDripFeedDetected
        : Boolean(selectedRouteMeta.dripfeed ?? selectedRouteMeta.drip_feed))
    : false;
  const dripFeedEnabled = selected
    ? (typeof selectedRouteMeta._velixeoDripFeedOverride === 'boolean'
        ? selectedRouteMeta._velixeoDripFeedOverride
        : detectedDripFeed)
    : false;

  const rows = priced.map(({ route, sale }) => {
    const meta = jsonObject(route.service.metadata);
    const routeMeta = jsonObject(route.metadata);
    const raw = meta.rawCatalog === true;
    const detected = typeof routeMeta._providerRefillDetected === 'boolean'
      ? routeMeta._providerRefillDetected
      : route.providerRefill;
    const appState = raw
      ? pill(l('اضافه نشده','Not added'))
      : route.service.enabled
        ? pill(l('فعال','Live'),'ok')
        : pill(l('پیش‌نویس','Draft'),'warn');
    const refillState = route.providerRefill
      ? pill(detected ? l('جبران · خودکار','Refill · Auto') : l('جبران · دستی','Refill · Manual'),'ok')
      : pill(detected ? l('جبران غیرفعال','Refill disabled') : l('بدون جبران','No refill'));
    const dripDetected = typeof routeMeta._providerDripFeedDetected === 'boolean'
      ? routeMeta._providerDripFeedDetected
      : Boolean(routeMeta.dripfeed ?? routeMeta.drip_feed);
    const dripEnabled = typeof routeMeta._velixeoDripFeedOverride === 'boolean'
      ? routeMeta._velixeoDripFeedOverride
      : dripDetected;
    const dripState = dripEnabled
      ? pill(dripDetected ? l('دریپ‌فید · خودکار','Drip-feed · Auto') : l('دریپ‌فید · دستی','Drip-feed · Manual'),'ok')
      : pill(dripDetected ? l('دریپ‌فید غیرفعال','Drip-feed disabled') : l('بدون دریپ‌فید','No drip-feed'));
    const actionTitle = raw ? l('افزودن این سرویس به VELIXEO','Add this service to VELIXEO') : l('ویرایش سرویس VELIXEO','Edit VELIXEO service');
    return `<tr data-route-id="${route.id}"><td class="mono">${esc(route.providerServiceCode)}</td><td class="service-name"><b>${esc(route.providerName || route.service.titleEn)}</b><br><span class="tiny">${esc(route.providerType || 'Default')}</span></td><td><b>${esc(route.providerRate?.toString() || '—')}</b> ${esc(route.providerCurrency || '')}</td><td class="money">${sale == null ? '—' : money(sale)}</td><td>${esc(route.providerMinQty ?? '—')} – ${esc(route.providerMaxQty ?? '—')}</td><td>${refillState}</td><td>${dripState}</td><td>${route.providerCancel ? pill(l('بله','Yes'),'ok') : pill(l('خیر','No'))}</td><td class="route-app-state">${appState}</td><td><a data-route-action class="iconbtn ${raw?'green':'purple'}" href="/admin/v3/social/provider-services?provider=${route.providerId}&route=${route.id}${q.q?`&q=${encodeURIComponent(q.q)}`:(!q.q && activeSourceCategory?`&sourceCategory=${encodeURIComponent(activeSourceCategory)}`:'')}" title="${actionTitle}" aria-label="${actionTitle}">${raw?icon('plus'):icon('edit')}</a></td></tr>`;
  }).join('');

  const brandOptions = brands
    .filter(item => item.enabled)
    .map(item => `<option value="${esc(item.key)}" ${normalizeBrandKey(item.key)===selectedBrand?'selected':''}>${esc(fa ? item.titleFa : item.titleEn)}</option>`)
    .join('');
  const categoryOptions = categories
    .filter(item => item.enabled)
    .map(item => `<option value="${esc(item.slug)}" data-platform="${esc(normalizeBrandKey(item.platform))}" ${selectedCategorySlug===item.slug?'selected':''}>${esc(fa ? item.titleFa : item.titleEn)}</option>`)
    .join('');
  const currentMode = selected?.service.basePriceAfn != null ? 'FIXED' : 'AUTO_MARKUP';

  const config = selected ? `<div id="service-config-panel" data-service-config class="card service-config-panel"><div class="cardhead"><div><h2>${isPublished?l('ویرایش سرویس VELIXEO','Edit VELIXEO Service'):l('افزودن سرویس به VELIXEO','Add Service to VELIXEO')}</h2><span class="muted">${l('ارائه‌دهنده','Provider')} #${esc(selected.providerServiceCode)} · ${esc(selected.provider.name)}</span></div><a class="btn ghost" href="/admin/v3/social/provider-services?provider=${selected.providerId}${activeSourceCategory?`&sourceCategory=${encodeURIComponent(activeSourceCategory)}`:''}">${l('بستن','Close')}</a></div>
  <div class="notice"><b>${l('نام اصلی ارائه‌دهنده:','Original provider name:')}</b> ${esc(selected.providerName || selected.service.titleEn)}<br><b>${l('هزینه ارائه‌دهنده:','Provider cost:')}</b> ${esc(selected.providerRate?.toString() || '—')} ${esc(selected.providerCurrency || '')} · ${l('حداقل','Min')} ${esc(selected.providerMinQty ?? '—')} · ${l('حداکثر','Max')} ${esc(selected.providerMaxQty ?? '—')}</div>
  <div id="service-config-feedback" class="service-config-feedback"></div>
  <form id="service-publish-form" method="post" action="/admin/v3/social/provider-services/publish">
    <input type="hidden" name="routeId" value="${selected.id}">
    <input type="hidden" name="providerId" value="${selected.providerId}">
    <input type="hidden" name="sourceCategory" value="${esc(activeSourceCategory)}">
    <div class="forms">
      <div class="field"><label>${l('برند / شبکه اجتماعی','Brand / Network')}</label><select id="socialBrandSelect" name="brandKey" required><option value="">${l('انتخاب برند','Choose brand')}</option>${brandOptions}</select></div>
      <div class="field"><label>${l('دسته‌بندی VELIXEO','VELIXEO Category')}</label><select id="socialCategorySelect" name="categorySlug" required><option value="">${l('انتخاب دسته‌بندی','Choose category')}</option>${categoryOptions}</select></div>
      <div class="field"><label>${l('نوع سرویس ارائه‌دهنده','Provider Service Type')}</label><input value="${esc(selected.providerType || 'Default')}" readonly></div>
      <div class="field"><label>${l('قیمت اصلی ارائه‌دهنده','Original Provider Price')}</label><input value="${esc(selected.providerRate?.toString() || '—')} ${esc(selected.providerCurrency || '')}" readonly></div>
    </div>
    <div class="field"><label>${l('نام انگلیسی برای مشتری','Customer-facing English Name')}</label><input name="titleEn" value="${esc(isPublished ? selected.service.titleEn : (selected.providerName || selected.service.titleEn))}" required></div>
    <div class="field"><label>${l('نام فارسی برای مشتری','Customer-facing Persian Name')}</label><input name="titleFa" value="${esc(isPublished ? selected.service.titleFa : '')}" placeholder="${l('نام فارسی سرویس','Persian service name')}"></div>
    <div class="forms">
      <div class="field"><label>${l('توضیحات انگلیسی','English Description')}</label><textarea name="descriptionEn">${esc(selected.service.descriptionEn || '')}</textarea></div>
      <div class="field"><label>${l('توضیحات فارسی','Persian Description')}</label><textarea name="descriptionFa">${esc(selected.service.descriptionFa || '')}</textarea></div>
    </div>
    <div class="forms">
      <div class="field"><label>${l('روش قیمت‌گذاری','Pricing Mode')}</label><select name="pricingMode"><option value="AUTO_MARKUP" ${currentMode==='AUTO_MARKUP'?'selected':''}>${l('سود خودکار — مطابق قیمت ارائه‌دهنده','Auto Markup — follows provider price')}</option><option value="FIXED" ${currentMode==='FIXED'?'selected':''}>${l('قیمت فروش ثابت','Fixed Sale Price')}</option></select></div>
      <div class="field"><label>${l('درصد سود','Profit / Markup %')}</label><input name="markup" value="${esc(selected.markupPercent?.toString() ?? selected.provider.defaultMarkupPercent.toString())}" placeholder="30"></div>
      <div class="field"><label>${l('قیمت فروش ثابت','Fixed Sale Price')}</label><input name="fixedPrice" value="${selected.service.basePriceAfn == null ? '' : esc(selected.service.basePriceAfn.toString())}" placeholder="${l('فقط برای حالت قیمت ثابت','Only for Fixed mode')}"></div>
      <div class="field"><label>${l('واحد قیمت ثابت','Fixed Price Currency')}</label><select name="fixedCurrency"><option>AFN</option><option>USD</option><option>TOMAN</option></select></div>
      <div class="field"><label>${l('حداقل تعداد','Minimum Quantity')}</label><input type="number" name="minQty" value="${esc(selected.service.minQty ?? selected.providerMinQty ?? '')}"></div>
      <div class="field"><label>${l('حداکثر تعداد','Maximum Quantity')}</label><input type="number" name="maxQty" value="${esc(selected.service.maxQty ?? selected.providerMaxQty ?? '')}"></div>
      <div class="field"><label>${l('ترتیب نمایش','Sort Order')}</label><input type="number" name="sortOrder" value="${esc(selected.service.sortOrder)}"></div>
      <div class="field"><label>${l('روزهای جبران / ضمانت','Refill / Guarantee Days')}</label><input type="number" name="refillDays" min="0" value="${esc(selected.service.refillDays ?? '')}" placeholder="30"></div>
    </div>
    <div class="refill-control">
      <div><b>${l('جبران ریزش / ضمانت','Refill / Drop Guarantee')}</b><div class="meta">${l('تشخیص API ارائه‌دهنده:','Provider API detected:')} <strong>${detectedRefill ? l('موجود','Available') : l('موجود نیست','Not available')}</strong>. ${l('کلید ابتدا از مقدار ارائه‌دهنده پیروی می‌کند، اما برای این سرویس می‌توانید آن را دستی فعال یا غیرفعال کنید.','The switch starts with the provider value, but you can manually enable or disable it for this VELIXEO service.')}</div></div>
      <label class="toggle"><input type="checkbox" name="refillEnabled" ${selected.providerRefill?'checked':''}> <span>${l('فعال','Enabled')}</span></label>
    </div>
    <div class="refill-control">
      <div><b>${l('ارسال زمان‌بندی‌شده','Drip-feed')}</b><div class="meta">${l('تشخیص API ارائه‌دهنده:','Provider API detected:')} <strong>${detectedDripFeed ? l('موجود','Available') : l('موجود نیست','Not available')}</strong>. ${l('اگر ارائه‌دهنده پشتیبانی کند خودکار فعال می‌شود و می‌توانید برای این سرویس آن را تغییر دهید.','It is enabled automatically when supported, and you can override it for this service.')}</div></div>
      <label class="toggle"><input type="checkbox" name="dripFeedEnabled" ${dripFeedEnabled?'checked':''}> <span>${l('فعال','Enabled')}</span></label>
    </div>
    <div class="provider-capability">${detectedRefill?pill(l('ارائه‌دهنده جبران ریزش دارد','Provider supports refill'),'ok'):pill(l('ارائه‌دهنده جبران ریزش ندارد','Provider reports no refill'))}${detectedDripFeed?pill(l('ارائه‌دهنده دریپ‌فید دارد','Provider supports drip-feed'),'ok'):pill(l('ارائه‌دهنده دریپ‌فید ندارد','Provider reports no drip-feed'))}${selected.providerCancel?pill(l('ارائه‌دهنده قابلیت لغو دارد','Provider supports cancel'),'ok'):pill(l('قابلیت لغو ندارد','No cancel'))}</div>
    <label class="check"><input type="checkbox" name="featured" ${selected.service.featured?'checked':''}> ${l('سرویس ویژه','Featured service')}</label>
    <label class="check"><input type="checkbox" name="enabled" ${selected.service.enabled?'checked':''}> ${l('فوراً برای کاربران نمایش داده شود','Visible to users immediately')}</label>
    <div class="notice">${l('اگر نمایش برای کاربران خاموش باشد، سرویس به‌صورت پیش‌نویس ذخیره می‌شود. فقط سرویس‌هایی که اینجا اضافه می‌کنید در بخش سرویس‌ها و اپ مشتری نمایش داده می‌شوند.','Save as draft by leaving “Visible to users” off. Only services you add here appear under Services and in the customer app.')}</div>
    <button class="btn">${isPublished?l('ذخیره تغییرات','Save Changes'):l('افزودن به VELIXEO','Add to VELIXEO')}</button>
  </form></div>` : `<div class="card empty">${l('یک سرویس ارائه‌دهنده را انتخاب و روی + بزنید تا برند، دسته‌بندی، قیمت و تنظیمات جبران را مشخص کنید.','Choose a provider service and press + to select its brand, category, pricing and refill settings.')}</div>`;

  const providerPicker = `<div class="card"><form method="get" action="/admin/v3/social/provider-services" class="provider-picker">
    <div class="field" style="margin:0"><label>${l('ارائه‌دهنده','Provider')}</label><select name="provider">${providers.map(item=>`<option value="${item.id}" ${item.id===providerId?'selected':''}>${esc(item.name)}</option>`).join('')}</select></div>
    <div class="field" style="margin:0"><label>${l('جستجوی سرویس‌های ارائه‌دهنده','Search provider services')}</label><input name="q" value="${esc(q.q)}" placeholder="${l('شناسه سرویس، نام یا دسته‌بندی ارائه‌دهنده','Service ID, name or provider category')}"></div>
    <button class="btn">${l('نمایش سرویس‌ها','Show Services')}</button>
  </form>
  ${provider ? `<div class="actions" style="margin-top:12px"><a class="btn ghost" href="/admin/v3/social/providers">${l('ارائه‌دهندگان','Providers')}</a><form method="post" action="/admin/v3/social/provider-services/sync"><input type="hidden" name="providerId" value="${provider.id}"><button class="btn">${icon('sync')} ${l('دریافت / بروزرسانی همه سرویس‌ها','Get / Refresh All Services')}</button></form></div>` : ''}
  <div class="notice" style="margin-top:12px">${l('این بخش فقط کاتالوگ ارائه‌دهنده را نشان می‌دهد. تا زمانی که روی + نزنید و تنظیمات را ذخیره نکنید، سرویسی به VELIXEO اضافه نمی‌شود.','This area shows the provider catalog only. Nothing is added to VELIXEO until you press + and save the service configuration.')}</div>
  ${sourceCategories.length ? `<div class="source-categories">${sourceCategories.map(item => `<a class="source-category ${!q.q && item.name===activeSourceCategory?'active':''}" href="/admin/v3/social/provider-services?provider=${encodeURIComponent(providerId)}&sourceCategory=${encodeURIComponent(item.name)}"><span>${esc(item.name)}</span><span class="count">${n(item.count)}</span></a>`).join('')}</div>` : ''}
  </div>`;

  const script = selected ? `
(() => {
  const brand = document.getElementById('socialBrandSelect');
  const category = document.getElementById('socialCategorySelect');
  const form = document.getElementById('service-publish-form');
  const feedback = document.getElementById('service-config-feedback');
  const panel = document.getElementById('service-config-panel');
  if (!brand || !category) return;
  const sync = () => {
    const value = String(brand.value || '').toUpperCase();
    let selectedVisible = false;
    for (const option of Array.from(category.options)) {
      if (!option.value) { option.hidden = false; continue; }
      const visible = !value || String(option.dataset.platform || '').toUpperCase() === value;
      option.hidden = !visible;
      if (visible && option.selected) selectedVisible = true;
    }
    if (!selectedVisible && category.value) category.value = '';
  };
  brand.addEventListener('change', sync);
  sync();

  form?.addEventListener('submit', async (event) => {
    event.preventDefault();
    const submit = form.querySelector('button[type="submit"],button:not([type])');
    const oldLabel = submit?.textContent || '';
    if (submit) { submit.disabled = true; submit.textContent = ${JSON.stringify(l('در حال ذخیره…','Saving…'))}; }
    if (feedback) { feedback.className = 'service-config-feedback'; feedback.textContent = ''; }
    try {
      const response = await fetch(form.action, {
        method: 'POST',
        body: new FormData(form),
        headers: { Accept: 'application/json' },
      });
      const payload = await response.json();
      if (!response.ok || !payload.ok) throw new Error(payload.error || ${JSON.stringify(l('ذخیره سرویس انجام نشد.','Could not save the service.'))});
      const row = document.querySelector('[data-route-id="' + payload.routeId + '"]');
      const state = row?.querySelector('.route-app-state');
      if (state) {
        state.innerHTML = payload.enabled
          ? '<span class="pill ok">${l('فعال','Live')}</span>'
          : '<span class="pill warn">${l('پیش‌نویس','Draft')}</span>';
      }
      const action = row?.querySelector('[data-route-action]');
      if (action) {
        action.classList.remove('green');
        action.classList.add('purple');
        action.setAttribute('title', ${JSON.stringify(l('ویرایش سرویس VELIXEO','Edit VELIXEO service'))});
        action.setAttribute('aria-label', ${JSON.stringify(l('ویرایش سرویس VELIXEO','Edit VELIXEO service'))});
      }
      if (feedback) {
        feedback.className = 'service-config-feedback ok';
        feedback.textContent = payload.message || ${JSON.stringify(l('سرویس ذخیره شد.','Service saved.'))};
      }
      history.replaceState({}, '', payload.returnUrl || location.pathname + location.search);
      setTimeout(() => {
        panel?.remove();
        row?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      }, 650);
    } catch (error) {
      if (feedback) {
        feedback.className = 'service-config-feedback bad';
        feedback.textContent = error instanceof Error ? error.message : ${JSON.stringify(l('ذخیره سرویس انجام نشد.','Could not save the service.'))};
      }
    } finally {
      if (submit) { submit.disabled = false; submit.textContent = oldLabel; }
    }
  });
})();` : undefined;

  return shell({
    request,
    admin,
    title: 'Provider Services',
    subtitle: provider
      ? `${provider.name} catalog — choose a service, then add it to the exact VELIXEO brand and category.`
      : 'Choose a provider to browse its API service catalog.',
    active: 'provider-services',
    message: q.msg,
    error: q.error,
    script,
    body: providers.length
      ? `${selected ? config : ''}${providerPicker}${selected ? '' : config}<div class="card provider-catalog-card"><div class="cardhead"><div class="catalog-title"><h2>${q.q ? l('نتایج جستجو','Search Results') : esc(activeSourceCategory || provider?.name || l('کاتالوگ ارائه‌دهنده','Provider Catalog'))}</h2>${!q.q && activeSourceCategory ? pill(n(sourceCategoryMap.get(activeSourceCategory)?.count ?? 0) + ' ' + l('سرویس','services'),'info') : ''}</div><span class="muted">${q.q ? n(priced.length) + ' ' + l('سرویس مطابق','matching services') : n(sourceIndexRows.length) + ' ' + l('سرویس همگام‌شده','total synced services') + ' · ' + n(sourceCategories.length) + ' ' + l('دسته‌بندی','categories')}</span></div><div class="tablewrap"><table class="table"><thead><tr><th>ID</th><th>${l('نام اصلی سرویس','Original Service Name')}</th><th>${l('هزینه ارائه‌دهنده','Provider Cost')}</th><th>${l('قیمت فروش VELIXEO','VELIXEO Sale')}</th><th>${l('حداقل / حداکثر','Min / Max')}</th><th>${l('جبران','Refill')}</th><th>${l('دریپ‌فید','Drip-feed')}</th><th>${l('لغو','Cancel')}</th><th>${l('وضعیت در اپ','App Status')}</th><th>${l('افزودن','Add')}</th></tr></thead><tbody>${rows || `<tr><td colspan="10" class="empty">${provider ? l('سرویسی پیدا نشد. ارائه‌دهنده را همگام کنید یا دسته‌بندی دیگری را انتخاب کنید.','No services found. Sync the provider or choose another provider category.') : l('ابتدا ارائه‌دهنده را انتخاب کنید.','Choose a provider first.')}</td></tr>`}</tbody></table></div></div>`
      : `<div class="card empty">${l('هنوز ارائه‌دهنده شبکه اجتماعی اضافه نشده است. ابتدا ارائه‌دهنده را اضافه و سپس سرویس‌های آن را همگام کنید.','No Social Media provider exists yet. Add a provider first, then sync its services.')}</div>`,
  });
}

function brandPreview(brand: SocialBrand) {
  if (brand.iconType === 'URL' || brand.iconType === 'UPLOAD') {
    return `<img src='${esc(brand.iconValue)}' alt='' style='width:30px;height:30px;object-fit:contain;border-radius:8px'>`;
  }
  return `<span style='width:30px;height:30px;border-radius:8px;display:grid;place-items:center;background:#edf6ff;color:#147bd6;font-weight:900;font-size:10px'>${esc((brand.iconValue || brand.key).slice(0,2).toUpperCase())}</span>`;
}

async function brandsPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const brands = await loadSocialBrands(prisma);
  const categories = await loadCategories(prisma);
  const services = await prisma.service.findMany({ where: { category: ServiceCategory.SOCIAL }, select: { socialPlatform: true, metadata: true } });
  const selected = q.edit ? brands.find(item => item.key === normalizeBrandKey(q.edit)) ?? null : null;
  const showForm = q.mode === 'new' || Boolean(selected);
  const rows = brands.map(item => {
    const categoryCount = categories.filter(cat => normalizeBrandKey(cat.platform) === item.key).length;
    const serviceCount = services.filter(service => {
      const meta = jsonObject(service.metadata);
      const added = meta.addedToVelixeo === true || typeof meta.publishedAt === 'string' || typeof meta.publishedFromProviderId === 'string';
      return added && normalizeBrandKey(service.socialPlatform || '') === item.key;
    }).length;
    return `<tr><td><div class='provider-name'>${brandPreview(item)}<div><b>${esc(item.titleEn)}</b><br><span class='mono muted'>${esc(item.key)}</span></div></div></td><td>${esc(item.titleFa)}</td><td>${categoryCount}</td><td>${serviceCount}</td><td>${item.sortOrder}</td><td>${item.enabled?pill('Visible','ok'):pill('Hidden','bad')}</td><td><div class='actions'><a class='iconbtn' href='/admin/v3/social/brands?edit=${encodeURIComponent(item.key)}' title='Edit brand'>${icon('edit')}</a><form method='post' action='/admin/v3/social/brands/toggle'><input type='hidden' name='key' value='${esc(item.key)}'><button class='iconbtn ${item.enabled?'orange':'green'}' title='${item.enabled?'Hide brand from app':'Show brand in app'}'>${icon('eye')}</button></form><form method='post' action='/admin/v3/social/brands/delete' onsubmit="return confirm('Delete this unused brand?');"><input type='hidden' name='key' value='${esc(item.key)}'><button class='iconbtn red' title='Delete brand'>${icon('trash')}</button></form></div></td></tr>`;
  }).join('');
  const iconOptions = defaultBrandIcons.map(name => `<option value='${name}' ${selected?.iconType==='DEFAULT'&&selected.iconValue===name?'selected':''}>${name}</option>`).join('');
  const form = showForm ? `<div class='card'><div class='cardhead'><h2>${selected?'Edit Brand':'Add Brand'}</h2><a class='btn ghost' href='/admin/v3/social/brands'>Cancel</a></div><form id='brand-form' method='post' action='/admin/v3/social/brands/save'><input type='hidden' name='originalKey' value='${esc(selected?.key || '')}'><input type='hidden' id='iconUploadData' name='iconUploadData' value=''><div class='forms'><div class='field'><label>Brand Key</label><input class='mono' name='key' value='${esc(selected?.key || '')}' placeholder='INSTAGRAM' required><span class='tiny'>Stable key used by categories and services.</span></div><div class='field'><label>Sort Order</label><input type='number' name='sortOrder' value='${esc(selected?.sortOrder ?? 100)}'></div><div class='field'><label>English Brand Name</label><input name='titleEn' value='${esc(selected?.titleEn || '')}' placeholder='Instagram' required></div><div class='field'><label>Persian Brand Name</label><input name='titleFa' value='${esc(selected?.titleFa || '')}' placeholder='اینستاگرام'></div></div><div class='field'><label>Icon Source</label><select id='iconType' name='iconType'><option value='DEFAULT' ${selected?.iconType!=='URL'&&selected?.iconType!=='UPLOAD'?'selected':''}>VELIXEO default icon library</option><option value='URL' ${selected?.iconType==='URL'?'selected':''}>Image URL</option><option value='UPLOAD' ${selected?.iconType==='UPLOAD'?'selected':''}>Upload PNG / JPG / WebP</option></select></div><div id='icon-default' class='field'><label>Default Icon</label><select name='defaultIcon'>${iconOptions}</select></div><div id='icon-url' class='field'><label>Icon URL</label><input class='mono' name='iconUrl' value='${selected?.iconType==='URL'?esc(selected.iconValue):''}' placeholder='https://.../instagram.png'></div><div id='icon-upload' class='field'><label>Upload Icon</label><input id='iconFile' type='file' accept='image/png,image/jpeg,image/webp'><span class='tiny'>Square icon recommended. Maximum about 400 KB.</span>${selected?.iconType==='UPLOAD'?'<div class="tiny">An uploaded icon is already saved. Choose a file only to replace it.</div>':''}</div><div class='field'><label>Preview</label><div id='brandIconPreview' style='width:64px;height:64px;border:1px solid var(--line);border-radius:14px;display:grid;place-items:center;background:#fff'>${selected?brandPreview(selected):'ICON'}</div></div><label class='check'><input type='checkbox' name='enabled' ${selected?.enabled===false?'':'checked'}> Visible in the customer app</label><button class='btn'>Save Brand</button></form></div>` : `<div class='card'><div class='cardhead'><h2>Brand Structure</h2><span class='muted'>Brand → Category → Service</span></div><div class='notice'>Brands are customer-facing networks such as Instagram, TikTok, Telegram and WhatsApp. Names, icons, order and visibility are server-driven.</div></div>`;
  return shell({
    request,
    admin, title: 'Brands', subtitle: 'Manage the social networks customers see before choosing a category.', active: 'brands',
    message: q.msg, error: q.error,
    body: `<div class='card'><div class='cardhead'><div><h2>Social Brands</h2><span class='muted'>${brands.length} brands</span></div><a class='btn' href='/admin/v3/social/brands?mode=new'>${icon('plus')} Add Brand</a></div><div class='tablewrap'><table class='table'><thead><tr><th>Brand</th><th>Persian Name</th><th>Categories</th><th>Services</th><th>Sort</th><th>App Status</th><th>Actions</th></tr></thead><tbody>${rows || '<tr><td colspan="7" class="empty">No brands yet.</td></tr>'}</tbody></table></div></div>${form}`,
    script: showForm ? `
      const type=document.getElementById('iconType'); const def=document.getElementById('icon-default'); const url=document.getElementById('icon-url'); const upload=document.getElementById('icon-upload'); const file=document.getElementById('iconFile'); const hidden=document.getElementById('iconUploadData'); const preview=document.getElementById('brandIconPreview');
      function syncIconFields(){ const value=type.value; def.style.display=value==='DEFAULT'?'block':'none'; url.style.display=value==='URL'?'block':'none'; upload.style.display=value==='UPLOAD'?'block':'none'; }
      type.addEventListener('change',syncIconFields); syncIconFields();
      file?.addEventListener('change',()=>{ const selected=file.files&&file.files[0]; if(!selected)return; if(selected.size>400000){alert('Icon is too large. Keep it below about 400 KB.');file.value='';return;} const reader=new FileReader(); reader.onload=()=>{hidden.value=String(reader.result||''); preview.innerHTML='<img src="'+hidden.value+'" style="width:54px;height:54px;object-fit:contain;border-radius:10px">';}; reader.readAsDataURL(selected); });
    ` : undefined,
  });
}
async function categoriesPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const [categories, brands] = await Promise.all([loadCategories(prisma), loadSocialBrands(prisma)]);
  const services = await prisma.service.findMany({
    where: { category: ServiceCategory.SOCIAL },
    select: { socialGroup: true, enabled: true, metadata: true },
  });
  const counts = new Map<string, { total: number; live: number }>();
  for (const service of services) {
    const meta = jsonObject(service.metadata);
    const added = meta.addedToVelixeo === true
      || typeof meta.publishedAt === 'string'
      || typeof meta.publishedFromProviderId === 'string';
    if (!service.socialGroup || !added) continue;
    const current = counts.get(service.socialGroup) ?? { total: 0, live: 0 };
    current.total += 1;
    if (service.enabled) current.live += 1;
    counts.set(service.socialGroup, current);
  }
  const selected = q.edit ? categories.find(item => item.slug === q.edit) ?? null : null;
  const showForm = q.mode === 'new' || Boolean(selected);
  const rows = categories.map(item => {
    const count = counts.get(item.slug) ?? { total: 0, live: 0 };
    return `<tr><td><b>${esc(item.titleEn)}</b><br><span class="mono muted">${esc(item.slug)}</span></td><td>${(()=>{const brand=brands.find(brand=>brand.key===normalizeBrandKey(item.platform));return brand?`<div class='provider-name'>${brandPreview(brand)}<span>${esc(brand.titleEn)}</span></div>`:pill(item.platform,'info')})()}</td><td>${count.total} <span class="tiny">(${count.live} live)</span></td><td>${item.sortOrder}</td><td>${item.enabled?pill('Visible','ok'):pill('Hidden','bad')}</td><td><div class="actions"><a class="iconbtn" href="/admin/v3/social/categories?edit=${encodeURIComponent(item.slug)}" title="Edit category">${icon('edit')}</a><form method="post" action="/admin/v3/social/categories/toggle"><input type="hidden" name="slug" value="${esc(item.slug)}"><button class="iconbtn ${item.enabled?'orange':'green'}" title="${item.enabled?'Hide category from app':'Show category in app'}">${icon('eye')}</button></form><form method="post" action="/admin/v3/social/categories/delete" onsubmit="return confirm('Delete this empty category?');"><input type="hidden" name="slug" value="${esc(item.slug)}"><button class="iconbtn red" title="Delete category">${icon('trash')}</button></form></div></td></tr>`;
  }).join('');

  const form = showForm ? `<div class="card"><div class="cardhead"><h2>${selected?'Edit Category':'Add Category'}</h2><a class="btn ghost" href="/admin/v3/social/categories">Cancel</a></div><form method="post" action="/admin/v3/social/categories/save"><input type="hidden" name="originalSlug" value="${esc(selected?.slug || '')}"><div class="field"><label>Category Slug</label><input class="mono" name="slug" value="${esc(selected?.slug || '')}" placeholder="instagram-followers" required></div><div class="field"><label>Brand</label><select name="platform" required><option value="">Choose brand</option>${brands.map(brand=>`<option value="${esc(brand.key)}" ${brand.key===normalizeBrandKey(selected?.platform||'')?'selected':''}>${esc(brand.titleEn)} · ${esc(brand.key)}</option>`).join('')}</select><span class="tiny">Manage names and icons from Brands.</span></div><div class="field"><label>English Category Name</label><input name="titleEn" value="${esc(selected?.titleEn || '')}" placeholder="Followers" required></div><div class="field"><label>Persian Category Name (optional for now)</label><input name="titleFa" value="${esc(selected?.titleFa || '')}" placeholder="فالوور"></div><div class="field"><label>English Description</label><textarea name="descriptionEn">${esc(selected?.descriptionEn || '')}</textarea></div><div class="field"><label>Sort Order</label><input type="number" name="sortOrder" value="${esc(selected?.sortOrder ?? 100)}"></div><label class="check"><input type="checkbox" name="enabled" ${selected?.enabled===false?'':'checked'}> Visible in the customer app</label><button class="btn">Save Category</button></form></div>` : `<div class="card"><div class="cardhead"><h2>Category Structure</h2><span class="muted">Brand → Category → Services</span></div><div class="notice">Examples: Instagram → Followers, Likes, Views · TikTok → Followers, Views. Create Brands first, then attach categories. Changes are server-driven.</div></div>`;

  return shell({
    request,
    admin,
    title: 'Categories',
    subtitle: 'Create the brand/category structure customers see before choosing a service.',
    active: 'categories',
    message: q.msg,
    error: q.error,
    body: `<div class="card"><div class="cardhead"><div><h2>Social Categories</h2><span class="muted">${categories.length} categories</span></div><a class="btn" href="/admin/v3/social/categories?mode=new">${icon('plus')} Add Category</a></div><div class="tablewrap"><table class="table"><thead><tr><th>Category</th><th>Brand</th><th>Services</th><th>Sort</th><th>App Status</th><th>Actions</th></tr></thead><tbody>${rows || '<tr><td colspan="6" class="empty">No categories yet.</td></tr>'}</tbody></table></div></div>${form}`,
  });
}

async function myServicesPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const all = await prisma.service.findMany({
    where: {
      category: ServiceCategory.SOCIAL,
      ...(q.q ? {
        OR: [
          { titleEn: { contains: q.q, mode: 'insensitive' } },
          { titleFa: { contains: q.q, mode: 'insensitive' } },
          { slug: { contains: q.q, mode: 'insensitive' } },
          { socialGroup: { contains: q.q, mode: 'insensitive' } },
        ],
      } : {}),
    },
    include: { routes: { include: { provider: true }, orderBy: { priority: 'asc' } } },
    orderBy: [{ enabled: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
    take: 500,
  });
  const services = all.filter(service => {
    const meta = jsonObject(service.metadata);
    return meta.addedToVelixeo === true
      || typeof meta.publishedAt === 'string'
      || typeof meta.publishedFromProviderId === 'string';
  });
  const rows = services.map(service => {
    const primary = service.routes[0];
    const refillMeta = primary ? jsonObject(primary.metadata) : {};
    const detected = primary
      ? (typeof refillMeta._providerRefillDetected === 'boolean'
          ? refillMeta._providerRefillDetected
          : primary.providerRefill)
      : false;
    const refill = primary
      ? (primary.providerRefill
          ? pill(detected ? 'Enabled · Provider' : 'Enabled · Manual','ok')
          : pill(detected ? 'Disabled manually' : 'No refill'))
      : pill('No route');
    const refillToggle = primary
      ? `<form method="post" action="/admin/v3/social/my-services/refill-toggle"><input type="hidden" name="routeId" value="${primary.id}"><button class="iconbtn ${primary.providerRefill?'orange':'green'}" title="${primary.providerRefill?'Disable refill':'Enable refill'}">${icon('sync')}</button></form>`
      : '';
    return `<tr><td><b>${esc(service.titleFa || service.titleEn)}</b><br><span class="muted">${esc(service.titleEn)}</span><br><span class="mono tiny">${esc(service.slug)}</span></td><td>${esc(service.socialPlatform || 'OTHER')} → ${esc(service.socialGroup || '—')}</td><td>${primary ? esc(primary.provider.name) : '—'}${service.routes.length > 1 ? ` +${service.routes.length - 1}` : ''}</td><td>${service.basePriceAfn != null ? `<span class="price-fixed">Fixed · ${money(service.basePriceAfn)}</span>` : '<span class="price-auto">Auto Markup</span>'}</td><td>${service.minQty ?? '—'} – ${service.maxQty ?? '—'}</td><td><div class="actions">${refill}${refillToggle}</div>${service.refillDays ? `<span class="tiny">${service.refillDays} guarantee days</span>` : ''}</td><td>${service.featured?pill('Featured','info'):''} ${service.enabled?pill('Live','ok'):pill('Draft / Hidden','warn')}</td><td><div class="actions">${primary ? `<a class="iconbtn" href="/admin/v3/social/provider-services?provider=${primary.providerId}&route=${primary.id}" title="Edit service">${icon('edit')}</a>` : ''}<form method="post" action="/admin/v3/social/my-services/toggle"><input type="hidden" name="id" value="${service.id}"><button class="iconbtn ${service.enabled?'orange':'green'}" title="${service.enabled?'Hide from customer app':'Publish to customer app'}">${icon('eye')}</button></form></div></td></tr>`;
  }).join('');
  return shell({
    request,
    admin,
    title: 'Services',
    subtitle: 'Only services you have added to VELIXEO are shown here. Provider catalog items stay in Provider Services.',
    active: 'services',
    message: q.msg,
    error: q.error,
    body: `<div class="card"><div class="cardhead"><form method="get" action="/admin/v3/social/my-services" class="searchbar"><input name="q" value="${esc(q.q)}" placeholder="Search service, slug or category"><button class="btn ghost">Search</button></form><a class="btn" href="/admin/v3/social/provider-services">${icon('plus')} Add from Provider Services</a></div><div class="notice">This list contains only VELIXEO services that you explicitly added from a provider. Use the refill switch here for a quick manual override.</div><div class="tablewrap"><table class="table"><thead><tr><th>VELIXEO Service</th><th>Brand / Category</th><th>Provider</th><th>Pricing</th><th>Min / Max</th><th>Refill</th><th>Status</th><th>Actions</th></tr></thead><tbody>${rows || '<tr><td colspan="8" class="empty">No VELIXEO social services yet. Open Provider Services and press + to add one.</td></tr>'}</tbody></table></div></div>`,
  });
}

async function orderSettingsPage(prisma: PrismaClient, admin: AdminIdentity, request: FastifyRequest) {
  const q = query(request);
  const settings = await getSocialOrderSettings(prisma);
  return shell({
    request,
    admin,
    title: 'Order Settings',
    subtitle: 'Control customer order IDs, terms and the post-completion refill window.',
    active: 'order-settings',
    message: q.msg,
    error: q.error,
    body: `<div class="grid eq">
      <div class="card">
        <div class="cardhead"><div><h2>Customer Order ID</h2><span class="muted">Choose what customers see as their Order ID.</span></div></div>
        <form method="post" action="/admin/v3/social/order-settings/save">
          <div class="field"><label>Order ID Mode</label><select name="orderIdMode">
            <option value="PROVIDER" ${settings.orderIdMode==='PROVIDER'?'selected':''}>Provider/API Order ID</option>
            <option value="SEQUENTIAL" ${settings.orderIdMode==='SEQUENTIAL'?'selected':''}>VELIXEO Sequential Order ID</option>
          </select></div>
          <div class="field"><label>Sequential Start Number</label><input type="number" min="1" name="startNumber" value="${esc(settings.startNumber)}"><span class="tiny">Example: 100063. Existing assigned numbers are never changed.</span></div>
          <div class="field"><label>Refill Window After Completion (hours)</label><input type="number" min="1" max="720" name="refillWindowHours" value="${esc(settings.refillWindowHours)}"><span class="tiny">Refill capability itself always comes from the provider API. This only controls how long the button remains available after completion.</span></div>
          <div class="field"><label>English Terms & Conditions</label><textarea name="termsEn" required>${esc(settings.termsEn)}</textarea></div>
          <div class="field"><label>Persian Terms & Conditions</label><textarea name="termsFa" required>${esc(settings.termsFa)}</textarea></div>
          <button class="btn">Save Order Settings</button>
        </form>
      </div>
      <div class="card">
        <div class="cardhead"><h2>How it works</h2>${pill('Server enforced','ok')}</div>
        <div class="notice"><b>Provider/API ID:</b> customers see the order number returned by the SMM provider, but it is labeled only as “Order ID”.</div>
        <div class="notice"><b>VELIXEO Sequential ID:</b> customers see a VELIXEO number starting from your chosen value, such as 100063, 100064, 100065… Provider IDs remain private for status, refill and cancellation.</div>
        <div class="notice"><b>Refill:</b> Sync reads the provider API <span class="mono">refill</span> flag automatically when a service is added. You can then manually enable or disable refill per VELIXEO service; that override is preserved on future provider syncs.</div>
        <div class="notice"><b>Cancel:</b> the provider API <span class="mono">cancel</span> flag is also synchronized automatically and the button is hidden for terminal/partial orders.</div>
      </div>
    </div>`,
  });
}

export function registerAdminSocialProviderManager(
  app: FastifyInstance,
  prisma: PrismaClient,
  resolveAdmin: AdminResolver,
) {
  app.addHook('onRequest', async (request, reply) => {
    if (request.method !== 'GET') return;
    const rawUrl = request.raw.url || '';
    const url = new URL(rawUrl, 'http://velixeo.local');
    if (url.pathname !== '/admin/v3' || url.searchParams.get('section') !== 'social') return;
    const tab = url.searchParams.get('tab');
    const redirects: Record<string, string> = {
      providers: '/admin/v3/social/providers',
      catalog: '/admin/v3/social/provider-services',
      'provider-services': '/admin/v3/social/provider-services',
      brands: '/admin/v3/social/brands',
      categories: '/admin/v3/social/categories',
      services: '/admin/v3/social/my-services',
      settings: '/admin/v3/social/order-settings',
    };
    if (tab && redirects[tab]) {
      const target = new URL(redirects[tab], 'http://velixeo.local');
      for (const [key, value] of url.searchParams.entries()) {
        if (key === 'section' || key === 'tab') continue;
        target.searchParams.set(key, value);
      }
      return reply.code(303).redirect(`${target.pathname}${target.search}`);
    }
  });

  app.get('/admin/v3/social/providers', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await providersPage(prisma, admin, request));
  });

  app.get('/admin/v3/social/provider-status', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const providers = await prisma.provider.findMany({ where: { kind: ProviderKind.SOCIAL } });
    const statuses = await Promise.all(providers.map(async provider => ({
      id: provider.id,
      ...(await providerStatus(provider)),
    })));
    return reply.header('Cache-Control', 'no-store').send({ updatedAt: new Date().toISOString(), providers: statuses });
  });

  app.get('/admin/v3/social/order-settings', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await orderSettingsPage(prisma, admin, request));
  });

  app.post('/admin/v3/social/order-settings/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const current = await getSocialOrderSettings(prisma);
      const saved = await saveSocialOrderSettings(prisma, {
        orderIdMode: text(body, 'orderIdMode') === 'PROVIDER' ? 'PROVIDER' : 'SEQUENTIAL',
        startNumber: Math.max(1, intValue(body.startNumber, current.startNumber)),
        refillWindowHours: Math.max(1, Math.min(720, intValue(body.refillWindowHours, current.refillWindowHours))),
        termsEn: text(body, 'termsEn') || current.termsEn,
        termsFa: text(body, 'termsFa') || current.termsFa,
      });
      await audit(
        prisma,
        admin.id,
        'SOCIAL_ORDER_SETTINGS_UPDATE',
        'SystemSetting',
        'social.order.settings',
        `Order IDs: ${saved.orderIdMode}; refill window: ${saved.refillWindowHours}h`,
      );
      return reply.code(303).redirect('/admin/v3/social/order-settings?msg=Order%20settings%20saved.');
    } catch (error) {
      return reply.code(303).redirect(`/admin/v3/social/order-settings?error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'order_settings_failed')}`);
    }
  });

  app.post('/admin/v3/social/providers/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const id = text(body, 'id');
      const name = text(body, 'name');
      if (!name) throw new Error('Provider name is required.');
      let slug = safeSlug(text(body, 'slug') || name);
      if (!slug) throw new Error('A valid provider name or slug is required.');
      {
        const baseSlug = slug;
        let candidate = baseSlug;
        let suffix = 1;
        while (await prisma.provider.findFirst({
          where: { slug: candidate, ...(id ? { id: { not: id } } : {}) },
          select: { id: true },
        })) {
          suffix += 1;
          candidate = `${baseSlug}-${suffix}`;
        }
        slug = candidate;
      }
      const baseUrl = text(body, 'baseUrl');
      if (!baseUrl) throw new Error('API endpoint is required.');
      const secret = text(body, 'secret');
      if (secret && !providerSecretEncryptionConfigured()) {
        throw new Error('Provider secret encryption is not configured on the server.');
      }
      const currencyCode = normalizeCurrencyCode(text(body, 'currency'), null);
      const data = {
        name,
        slug,
        kind: ProviderKind.SOCIAL,
        baseUrl,
        currencyCode,
        enabled: checked(body, 'enabled'),
        priority: intValue(body.priority, 20),
        defaultMarkupPercent: new Prisma.Decimal(text(body, 'markup') || '0'),
        timeoutSeconds: Math.max(5, Math.min(120, intValue(body.timeout, 30))),
        notes: text(body, 'description') || null,
      };
      let provider = id
        ? await prisma.provider.update({ where: { id }, data })
        : await prisma.provider.create({ data });
      if (secret) {
        provider = await prisma.provider.update({
          where: { id: provider.id },
          data: encryptProviderSecret(secret),
        });
      }
      await saveProviderMeta(prisma, provider.id, {
        websiteUrl: text(body, 'websiteUrl'),
        defaultCurrency: currencyCode || 'AUTO',
        description: text(body, 'description'),
      });
      await saveSocialProviderSyncConfig(prisma, provider.id, {
        autoSync: text(body, 'autoSync') !== '0',
        syncMinutes: intValue(body.syncMinutes, 10),
      });
      await audit(prisma, admin.id, id ? 'SOCIAL_PROVIDER_UPDATE' : 'SOCIAL_PROVIDER_CREATE', 'Provider', provider.id, `${provider.name} (${provider.slug})`);
      return reply.code(303).redirect(`/admin/v3/social/providers?msg=${encodeURIComponent(id ? 'Provider updated.' : 'Provider added successfully.')}`);
    } catch (error) {
      const id = text(body, 'id');
      const target = id ? `?edit=${encodeURIComponent(id)}&` : '?mode=new&';
      return reply.code(303).redirect(`/admin/v3/social/providers${target}error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'provider_save_failed')}`);
    }
  });

  app.post('/admin/v3/social/providers/toggle', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const id = text(request.body as Body, 'id');
    const provider = await prisma.provider.findFirst({ where: { id, kind: ProviderKind.SOCIAL } });
    if (!provider) return reply.code(303).redirect('/admin/v3/social/providers?error=1&msg=Provider%20not%20found');
    const updated = await prisma.provider.update({ where: { id }, data: { enabled: !provider.enabled } });
    await audit(prisma, admin.id, 'SOCIAL_PROVIDER_TOGGLE', 'Provider', id, `${updated.name}: ${updated.enabled ? 'enabled' : 'disabled'}`);
    return reply.code(303).redirect('/admin/v3/social/providers');
  });

  app.post('/admin/v3/social/providers/delete', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const id = text(request.body as Body, 'id');
    try {
      const provider = await prisma.provider.findFirst({ where: { id, kind: ProviderKind.SOCIAL } });
      if (!provider) throw new Error('Provider not found.');
      const routes = await prisma.serviceProviderRoute.findMany({
        where: { providerId: id },
        include: { service: true },
      });
      const rawServiceIds = routes
        .filter(route => jsonObject(route.service.metadata).rawCatalog === true)
        .map(route => route.serviceId);
      const publishedServiceIds = routes
        .filter(route => jsonObject(route.service.metadata).rawCatalog !== true)
        .map(route => route.serviceId);
      await prisma.$transaction(async tx => {
        await tx.systemSetting.deleteMany({ where: { key: { in: [providerMetaKey(id), `social.provider.sync.${id}`] } } });
        await tx.provider.delete({ where: { id } });
        if (rawServiceIds.length) await tx.service.deleteMany({ where: { id: { in: rawServiceIds } } });
      });
      for (const serviceId of publishedServiceIds) {
        const remaining = await prisma.serviceProviderRoute.count({ where: { serviceId, enabled: true } });
        if (remaining === 0) await prisma.service.update({ where: { id: serviceId }, data: { enabled: false } });
      }
      await audit(prisma, admin.id, 'SOCIAL_PROVIDER_DELETE', 'Provider', id, provider.name);
      return reply.code(303).redirect('/admin/v3/social/providers?msg=Provider%20deleted.');
    } catch (error) {
      return reply.code(303).redirect(`/admin/v3/social/providers?error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'provider_delete_failed')}`);
    }
  });

  app.get('/admin/v3/social/provider-services', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await providerServicesPage(prisma, admin, request));
  });

  app.post('/admin/v3/social/provider-services/sync', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const providerId = text(request.body as Body, 'providerId');
    try {
      const result = await syncSocialProviderCatalog(prisma, providerId);
      await audit(prisma, admin.id, 'SOCIAL_PROVIDER_SYNC', 'Provider', providerId, `Synced ${result.total} services`, result as unknown as Prisma.InputJsonValue);
      return reply.code(303).redirect(`/admin/v3/social/provider-services?provider=${providerId}&msg=${encodeURIComponent(`Received ${result.total} services. ${result.created} new, ${result.updated} updated.`)}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/v3/social/provider-services?provider=${providerId}&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'sync_failed')}`);
    }
  });

  app.post('/admin/v3/social/provider-services/publish', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    const routeId = text(body, 'routeId');
    const providerId = text(body, 'providerId');
    const sourceCategory = text(body, 'sourceCategory');
    const sourceCategoryQuery = sourceCategory ? `&sourceCategory=${encodeURIComponent(sourceCategory)}` : '';
    try {
      const route = await prisma.serviceProviderRoute.findFirst({
        where: { id: routeId, provider: { kind: ProviderKind.SOCIAL } },
        include: { provider: true, service: true },
      });
      if (!route) throw new Error('Provider service not found.');
      const categories = await loadCategories(prisma);
      const category = categories.find(item => item.slug === text(body, 'categorySlug'));
      if (!category) throw new Error('Choose a valid category.');
      const mode = text(body, 'pricingMode') === 'FIXED' ? 'FIXED' : 'AUTO_MARKUP';
      const markup = new Prisma.Decimal(text(body, 'markup') || route.provider.defaultMarkupPercent.toString());
      let fixedPrice: bigint | null = null;
      if (mode === 'FIXED') {
        const raw = text(body, 'fixedPrice');
        if (!raw) throw new Error('Fixed price is required in Fixed mode.');
        fixedPrice = await convertSocialPriceToAfn(prisma, new Prisma.Decimal(raw), text(body, 'fixedCurrency') || 'AFN');
      }
      const oldMeta = jsonObject(route.service.metadata);
      const oldRouteMeta = jsonObject(route.metadata);
      const refillEnabled = checked(body, 'refillEnabled');
      const dripFeedEnabled = checked(body, 'dripFeedEnabled');
      const titleEn = text(body, 'titleEn') || route.providerName || route.service.titleEn;
      await prisma.$transaction([
        prisma.service.update({
          where: { id: route.serviceId },
          data: {
            titleEn,
            titleFa: text(body, 'titleFa') || titleEn,
            descriptionEn: text(body, 'descriptionEn') || null,
            descriptionFa: text(body, 'descriptionFa') || null,
            enabled: checked(body, 'enabled'),
            featured: checked(body, 'featured'),
            sortOrder: intValue(body.sortOrder, route.service.sortOrder),
            basePriceAfn: fixedPrice,
            minQty: text(body, 'minQty') ? intValue(body.minQty) : route.providerMinQty,
            maxQty: text(body, 'maxQty') ? intValue(body.maxQty) : route.providerMaxQty,
            refillDays: text(body, 'refillDays') ? intValue(body.refillDays) : route.service.refillDays,
            socialPlatform: category.platform,
            socialGroup: category.slug,
            metadata: {
              ...oldMeta,
              rawCatalog: false,
              addedToVelixeo: true,
              pricingMode: mode,
              categorySlug: category.slug,
              publishedFromProviderId: route.providerId,
              publishedAt: new Date().toISOString(),
            } as Prisma.InputJsonValue,
          },
        }),
        prisma.serviceProviderRoute.update({
          where: { id: route.id },
          data: {
            enabled: true,
            markupPercent: mode === 'AUTO_MARKUP' ? markup : null,
            providerRefill: refillEnabled,
            metadata: {
              ...oldRouteMeta,
              _providerRefillDetected: typeof oldRouteMeta._providerRefillDetected === 'boolean'
                ? oldRouteMeta._providerRefillDetected
                : route.providerRefill,
              _velixeoRefillOverride: refillEnabled,
              _providerDripFeedDetected: typeof oldRouteMeta._providerDripFeedDetected === 'boolean'
                ? oldRouteMeta._providerDripFeedDetected
                : Boolean(oldRouteMeta.dripfeed ?? oldRouteMeta.drip_feed),
              _velixeoDripFeedOverride: dripFeedEnabled,
            } as Prisma.InputJsonValue,
          },
        }),
      ]);
      await audit(prisma, admin.id, 'SOCIAL_SERVICE_PUBLISH', 'Service', route.serviceId, `${titleEn} → ${category.platform}/${category.titleEn}`, {
        pricingMode: mode,
        markup: markup.toString(),
        fixedAfn: fixedPrice?.toString() ?? null,
        visible: checked(body, 'enabled'),
        refillEnabled,
        dripFeedEnabled,
      });
      return reply.code(303).redirect(`/admin/v3/social/provider-services?provider=${providerId}${sourceCategoryQuery}&msg=${encodeURIComponent(checked(body,'enabled') ? 'Service saved and published to the app.' : 'Service saved as a draft.')}`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/v3/social/provider-services?provider=${providerId}${sourceCategoryQuery}&route=${routeId}&error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'publish_failed')}`);
    }
  });

  app.get('/admin/v3/social/brands', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await brandsPage(prisma, admin, request));
  });

  app.post('/admin/v3/social/brands/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const originalKey = normalizeBrandKey(text(body, 'originalKey'));
      const key = normalizeBrandKey(text(body, 'key'));
      const titleEn = text(body, 'titleEn');
      if (!key || !titleEn) throw new Error('Brand key and English name are required.');
      const rawType = text(body, 'iconType').toUpperCase();
      const iconType: SocialBrand['iconType'] = rawType === 'URL' || rawType === 'UPLOAD' ? rawType : 'DEFAULT';
      let iconValue = iconType === 'DEFAULT' ? text(body, 'defaultIcon') : iconType === 'URL' ? text(body, 'iconUrl') : text(body, 'iconUploadData');
      if (iconType === 'UPLOAD' && !iconValue && originalKey) {
        const existingSetting = await prisma.systemSetting.findUnique({ where: { key: brandSettingKey(originalKey) } });
        const existing = existingSetting ? parseBrand(existingSetting) : null;
        if (existing?.iconType === 'UPLOAD') iconValue = existing.iconValue;
      }
      iconValue = validateBrandIcon(iconType, iconValue || 'generic');
      const value: SocialBrand = { key, titleEn, titleFa: text(body, 'titleFa') || titleEn, iconType, iconValue, sortOrder: intValue(body.sortOrder, 100), enabled: checked(body, 'enabled') };
      if (originalKey && originalKey !== key) {
        const categoryRows = await prisma.systemSetting.findMany({ where: { category: 'social-category' } });
        for (const row of categoryRows) {
          const category = parseCategory(row);
          if (!category || normalizeBrandKey(category.platform) !== originalKey) continue;
          await prisma.systemSetting.update({ where: { key: row.key }, data: { value: { ...jsonObject(row.value), platform: key } as Prisma.InputJsonValue } });
        }
        await prisma.service.updateMany({ where: { category: ServiceCategory.SOCIAL, socialPlatform: originalKey }, data: { socialPlatform: key } });
        await prisma.systemSetting.deleteMany({ where: { key: brandSettingKey(originalKey) } });
      }
      await prisma.systemSetting.upsert({
        where: { key: brandSettingKey(key) },
        create: { key: brandSettingKey(key), category: 'social-brand', description: 'Social brand ' + key, value: value as unknown as Prisma.InputJsonValue },
        update: { category: 'social-brand', value: value as unknown as Prisma.InputJsonValue },
      });
      await audit(prisma, admin.id, 'SOCIAL_BRAND_SAVE', 'SocialBrand', key, titleEn, { iconType, enabled: value.enabled });
      return reply.code(303).redirect('/admin/v3/social/brands?edit=' + encodeURIComponent(key) + '&msg=Brand%20saved.');
    } catch (error) {
      return reply.code(303).redirect('/admin/v3/social/brands?error=1&msg=' + encodeURIComponent(error instanceof Error ? error.message : 'brand_save_failed'));
    }
  });

  app.post('/admin/v3/social/brands/toggle', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const key = normalizeBrandKey(text(request.body as Body, 'key'));
    const setting = await prisma.systemSetting.findUnique({ where: { key: brandSettingKey(key) } });
    let brand = setting ? parseBrand(setting) : null;
    if (!brand) brand = (await loadSocialBrands(prisma)).find(item => item.key === key) || null;
    if (!brand) return reply.code(303).redirect('/admin/v3/social/brands?error=1&msg=Brand%20not%20found');
    const value: SocialBrand = { ...brand, enabled: !brand.enabled };
    await prisma.systemSetting.upsert({
      where: { key: brandSettingKey(key) },
      create: { key: brandSettingKey(key), category: 'social-brand', description: 'Social brand ' + key, value: value as unknown as Prisma.InputJsonValue },
      update: { category: 'social-brand', value: value as unknown as Prisma.InputJsonValue },
    });
    await audit(prisma, admin.id, 'SOCIAL_BRAND_TOGGLE', 'SocialBrand', key, brand.titleEn + ': ' + (value.enabled ? 'enabled' : 'disabled'));
    return reply.code(303).redirect('/admin/v3/social/brands');
  });

  app.post('/admin/v3/social/brands/delete', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const key = normalizeBrandKey(text(request.body as Body, 'key'));
    const categories = await loadCategories(prisma);
    const categoryCount = categories.filter(item => normalizeBrandKey(item.platform) === key).length;
    const serviceCount = await prisma.service.count({ where: { category: ServiceCategory.SOCIAL, socialPlatform: key } });
    if (categoryCount || serviceCount) return reply.code(303).redirect('/admin/v3/social/brands?error=1&msg=' + encodeURIComponent('Move or delete this brand’s categories/services first.'));
    await prisma.systemSetting.deleteMany({ where: { key: brandSettingKey(key) } });
    await audit(prisma, admin.id, 'SOCIAL_BRAND_DELETE', 'SocialBrand', key, key);
    return reply.code(303).redirect('/admin/v3/social/brands?msg=Brand%20deleted.');
  });
  app.get('/admin/v3/social/categories', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await categoriesPage(prisma, admin, request));
  });

  app.post('/admin/v3/social/categories/save', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const original = text(body, 'originalSlug');
      const slug = safeSlug(text(body, 'slug'));
      const titleEn = text(body, 'titleEn');
      const platform = normalizeBrandKey(text(body, 'platform'));
      if (!slug || !titleEn) throw new Error('Category slug and English name are required.');
      const brand = (await loadSocialBrands(prisma)).find(item => item.key === platform);
      if (!brand) throw new Error('Choose a valid brand first.');
      const value: SocialCategory = {
        slug,
        titleEn,
        titleFa: text(body, 'titleFa') || titleEn,
        platform,
        descriptionEn: text(body, 'descriptionEn'),
        descriptionFa: text(body, 'descriptionFa'),
        sortOrder: intValue(body.sortOrder, 100),
        enabled: checked(body, 'enabled'),
      };
      if (original && original !== slug) {
        await prisma.systemSetting.deleteMany({ where: { key: categoryKey(original) } });
      }
      await prisma.systemSetting.upsert({
        where: { key: categoryKey(slug) },
        create: {
          key: categoryKey(slug),
          category: 'social-category',
          description: `Social category ${slug}`,
          value: value as unknown as Prisma.InputJsonValue,
        },
        update: {
          category: 'social-category',
          value: value as unknown as Prisma.InputJsonValue,
        },
      });
      const affected = await prisma.service.findMany({
        where: { category: ServiceCategory.SOCIAL, socialGroup: original || slug },
        select: { id: true, metadata: true },
      });
      for (const service of affected) {
        await prisma.service.update({
          where: { id: service.id },
          data: {
            socialGroup: slug,
            socialPlatform: platform,
            metadata: {
              ...jsonObject(service.metadata),
              categorySlug: slug,
            } as Prisma.InputJsonValue,
          },
        });
      }
      await audit(prisma, admin.id, 'SOCIAL_CATEGORY_SAVE', 'SocialCategory', slug, `${platform} → ${titleEn}`);
      return reply.code(303).redirect(`/admin/v3/social/categories?edit=${encodeURIComponent(slug)}&msg=Category%20saved.`);
    } catch (error) {
      return reply.code(303).redirect(`/admin/v3/social/categories?error=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'category_save_failed')}`);
    }
  });

  app.post('/admin/v3/social/categories/toggle', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const slug = text(request.body as Body, 'slug');
    const setting = await prisma.systemSetting.findUnique({ where: { key: categoryKey(slug) } });
    if (!setting) return reply.code(303).redirect('/admin/v3/social/categories?error=1&msg=Category%20not%20found');
    const value = jsonObject(setting.value);
    const next = value.enabled === false;
    await prisma.systemSetting.update({
      where: { key: setting.key },
      data: { value: { ...value, enabled: next } as Prisma.InputJsonValue },
    });
    await audit(prisma, admin.id, 'SOCIAL_CATEGORY_TOGGLE', 'SocialCategory', slug, `${slug}: ${next ? 'visible' : 'hidden'}`);
    return reply.code(303).redirect('/admin/v3/social/categories');
  });

  app.post('/admin/v3/social/categories/delete', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const slug = text(request.body as Body, 'slug');
    const count = await prisma.service.count({
      where: { category: ServiceCategory.SOCIAL, socialGroup: slug },
    });
    if (count > 0) {
      return reply.code(303).redirect(`/admin/v3/social/categories?error=1&msg=${encodeURIComponent(`This category still contains ${count} service(s). Hide it or move the services before deleting.`)}`);
    }
    await prisma.systemSetting.deleteMany({ where: { key: categoryKey(slug) } });
    await audit(prisma, admin.id, 'SOCIAL_CATEGORY_DELETE', 'SocialCategory', slug, slug);
    return reply.code(303).redirect('/admin/v3/social/categories?msg=Category%20deleted.');
  });

  app.get('/admin/v3/social/my-services', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    return reply.type('text/html; charset=utf-8').send(await myServicesPage(prisma, admin, request));
  });

  app.post('/admin/v3/social/my-services/toggle', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const id = text(request.body as Body, 'id');
    const service = await prisma.service.findFirst({
      where: { id, category: ServiceCategory.SOCIAL },
    });
    if (!service || jsonObject(service.metadata).rawCatalog === true) {
      return reply.code(303).redirect('/admin/v3/social/my-services?error=1&msg=Service%20not%20found');
    }
    const updated = await prisma.service.update({ where: { id }, data: { enabled: !service.enabled } });
    await audit(prisma, admin.id, 'SOCIAL_SERVICE_VISIBILITY', 'Service', id, `${updated.titleEn}: ${updated.enabled ? 'live' : 'hidden'}`);
    return reply.code(303).redirect(`/admin/v3/social/my-services?msg=${encodeURIComponent(updated.enabled ? 'Service is now live in the app.' : 'Service hidden from the app.')}`);
  });

  app.post('/admin/v3/social/my-services/refill-toggle', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const routeId = text(request.body as Body, 'routeId');
    const route = await prisma.serviceProviderRoute.findFirst({
      where: { id: routeId, provider: { kind: ProviderKind.SOCIAL } },
      include: { service: true },
    });
    if (!route || jsonObject(route.service.metadata).rawCatalog === true) {
      return reply.code(303).redirect('/admin/v3/social/my-services?error=1&msg=Service%20route%20not%20found');
    }
    const routeMeta = jsonObject(route.metadata);
    const next = !route.providerRefill;
    await prisma.serviceProviderRoute.update({
      where: { id: route.id },
      data: {
        providerRefill: next,
        metadata: {
          ...routeMeta,
          _providerRefillDetected: typeof routeMeta._providerRefillDetected === 'boolean'
            ? routeMeta._providerRefillDetected
            : route.providerRefill,
          _velixeoRefillOverride: next,
        } as Prisma.InputJsonValue,
      },
    });
    await audit(
      prisma,
      admin.id,
      'SOCIAL_SERVICE_REFILL_OVERRIDE',
      'ServiceProviderRoute',
      route.id,
      `${route.service.titleEn}: refill ${next ? 'enabled' : 'disabled'}`,
    );
    return reply.code(303).redirect(
      `/admin/v3/social/my-services?msg=${encodeURIComponent(next ? 'Refill enabled for this service.' : 'Refill disabled for this service.')}`,
    );
  });
}
