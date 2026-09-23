import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  BannerPlacement,
  NotificationPriority,
  NotificationType,
  OrderStatus,
  Prisma,
  PrismaClient,
  ServiceCategory,
  WalletEntryStatus,
  WalletEntryType,
} from '@prisma/client';
import {
  parsePremiumMetadata,
  premiumMetadataJson,
  premiumMinPriceAfn,
  type PremiumFormField,
  type PremiumPackage,
} from './premiumCatalog.js';
import {
  encryptProviderSecret,
  providerSecretEncryptionConfigured,
} from './providerSecrets.js';
import { publishUserNotification } from './pushNotifications.js';
import {
  premiumTelegramSettings,
  savePremiumTelegramSettings,
  sendPremiumTelegramMessage,
} from './telegramAdminAlerts.js';
import { sendAdminRefundAlert } from './adminTelegramEvents.js';

type AdminIdentity = {
  id: string;
  fullName: string | null;
  email: string | null;
  phone: string | null;
};
type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type Body = Record<string, unknown>;

const esc = (value: unknown) =>
  String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

const text = (body: Body, key: string) => String(body[key] ?? '').trim();
const checked = (body: Body, key: string) =>
  ['on', 'true', '1'].includes(String(body[key] ?? ''));

function intValue(value: unknown, fallback = 0) {
  const valueInt = Number.parseInt(String(value ?? ''), 10);
  return Number.isFinite(valueInt) ? valueInt : fallback;
}

function jsonObject(value: unknown): Record<string, unknown> {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function safeSlug(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^a-z0-9_-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function money(value: bigint | string | number | null | undefined) {
  return `${Number(value ?? 0).toLocaleString('en-US')} AFN`;
}

function dt(value: Date | string | null | undefined) {
  if (!value) return '—';
  try {
    return new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' });
  } catch {
    return '—';
  }
}

function pill(label: string, kind = '') {
  return `<span class="pill ${kind}">${esc(label)}</span>`;
}

function href(tab: string, extra = '') {
  return `/admin/v3?section=premium&tab=${encodeURIComponent(tab)}${extra}`;
}

function tabs(active: string) {
  const items = [
    ['overview', 'Overview'],
    ['banner', 'Banner'],
    ['products', 'Products & Packages'],
    ['orders', 'Orders'],
    ['settings', 'Admin Alerts'],
  ];
  return `<div class="tabs">${items
    .map(([key, label]) => `<a class="tab ${active === key ? 'active' : ''}" href="${href(key)}">${label}</a>`)
    .join('')}</div>`;
}

function packageRow(pkg?: Partial<PremiumPackage>) {
  return `<div class="card premium-package-row" style="box-shadow:none;border-style:dashed;padding:11px">
    <div class="cardhead"><b>Package</b><button type="button" class="btn danger" onclick="this.closest('.premium-package-row').remove()">Remove</button></div>
    <div class="forms">
      <div class="field"><label>Package ID</label><input data-k="id" value="${esc(pkg?.id || '')}" placeholder="3-months"></div>
      <div class="field"><label>Price AFN</label><input data-k="priceAfn" type="number" min="1" value="${esc(pkg?.priceAfn || '')}" required></div>
      <div class="field"><label>English title</label><input data-k="titleEn" value="${esc(pkg?.titleEn || '')}" placeholder="3 Months"></div>
      <div class="field"><label>عنوان فارسی</label><input data-k="titleFa" value="${esc(pkg?.titleFa || '')}" placeholder="۳ ماهه"></div>
      <div class="field"><label>English duration</label><input data-k="durationEn" value="${esc(pkg?.durationEn || '')}" placeholder="3 months"></div>
      <div class="field"><label>مدت فارسی</label><input data-k="durationFa" value="${esc(pkg?.durationFa || '')}" placeholder="۳ ماه"></div>
      <div class="field"><label>Stock (blank = unlimited)</label><input data-k="stock" type="number" min="0" value="${pkg?.stock == null ? '' : esc(pkg.stock)}"></div>
      <div class="field"><label>Sort order</label><input data-k="sortOrder" type="number" min="1" value="${esc(pkg?.sortOrder ?? 10)}"></div>
      <div class="field"><label>English badge</label><input data-k="badgeEn" value="${esc(pkg?.badgeEn || '')}" placeholder="Best value"></div>
      <div class="field"><label>نشان فارسی</label><input data-k="badgeFa" value="${esc(pkg?.badgeFa || '')}" placeholder="بهترین قیمت"></div>
    </div>
    <label class="check"><input data-k="enabled" type="checkbox" ${pkg?.enabled === false ? '' : 'checked'}> Available for customers</label>
  </div>`;
}

function fieldRow(field?: Partial<PremiumFormField>) {
  const type = field?.type || 'TEXT';
  const option = (value: string, label = value) =>
    `<option value="${value}" ${type === value ? 'selected' : ''}>${label}</option>`;
  return `<div class="card premium-field-row" style="box-shadow:none;border-style:dashed;padding:11px">
    <div class="cardhead"><b>Customer field</b><button type="button" class="btn danger" onclick="this.closest('.premium-field-row').remove()">Remove</button></div>
    <div class="forms">
      <div class="field"><label>Key</label><input data-k="key" value="${esc(field?.key || '')}" placeholder="telegram_username"></div>
      <div class="field"><label>Type</label><select data-k="type">${option('TEXT')}${option('USERNAME')}${option('PHONE')}${option('EMAIL')}${option('SELECT')}${option('TEXTAREA')}</select></div>
      <div class="field"><label>English label</label><input data-k="labelEn" value="${esc(field?.labelEn || '')}" placeholder="Telegram username"></div>
      <div class="field"><label>برچسب فارسی</label><input data-k="labelFa" value="${esc(field?.labelFa || '')}" placeholder="یوزرنیم تلگرام"></div>
      <div class="field"><label>English placeholder</label><input data-k="placeholderEn" value="${esc(field?.placeholderEn || '')}"></div>
      <div class="field"><label>متن راهنما فارسی</label><input data-k="placeholderFa" value="${esc(field?.placeholderFa || '')}"></div>
    </div>
    <div class="field"><label>Select options (comma-separated; SELECT only)</label><input data-k="options" value="${esc((field?.options || []).join(', '))}" placeholder="Option A, Option B"></div>
    <label class="check"><input data-k="required" type="checkbox" ${field?.required ? 'checked' : ''}> Required</label>
  </div>`;
}

function productForm(service: any | null) {
  const meta = service ? parsePremiumMetadata(service.metadata) : parsePremiumMetadata(null);
  const packages = meta.packages.length ? meta.packages : [{
    id: '3-months',
    titleFa: '۳ ماهه',
    titleEn: '3 Months',
    durationFa: '۳ ماه',
    durationEn: '3 months',
    priceAfn: '1000',
    enabled: true,
    sortOrder: 10,
    stock: null,
    badgeFa: '',
    badgeEn: '',
  } satisfies PremiumPackage];
  const fields = meta.formFields.length ? meta.formFields : [{
    key: 'account',
    type: 'USERNAME',
    labelFa: 'یوزرنیم یا شماره حساب',
    labelEn: 'Username or account number',
    placeholderFa: '',
    placeholderEn: '',
    required: true,
    options: [],
  } satisfies PremiumFormField];

  return `<form method="post" action="/admin/v3/premium/product" onsubmit="return premiumPrepareProduct(this)">
    <input type="hidden" name="id" value="${esc(service?.id || '')}">
    <input type="hidden" name="packagesJson">
    <input type="hidden" name="formFieldsJson">
    <div class="forms">
      <div class="field"><label>English title</label><input name="titleEn" value="${esc(service?.titleEn || '')}" required placeholder="Telegram Premium"></div>
      <div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(service?.titleFa || '')}" required placeholder="تلگرام پریمیوم"></div>
      <div class="field"><label>Slug</label><input class="mono" name="slug" value="${esc(service?.slug || '')}" placeholder="telegram-premium"></div>
      <div class="field"><label>Category</label><select name="group">
        ${['MESSAGING','SOCIAL','OTHER'].map(group => `<option value="${group}" ${meta.group === group ? 'selected' : ''}>${group}</option>`).join('')}
      </select></div>
      <div class="field"><label>Fulfillment type</label><select name="deliveryType">
        ${[
          ['MANUAL_ACTIVATION','Manual activation'],
          ['MANUAL_DELIVERY','Manual delivery'],
          ['CUSTOM_REQUEST','Custom request'],
        ].map(([value,label]) => `<option value="${value}" ${meta.deliveryType === value ? 'selected' : ''}>${label}</option>`).join('')}
      </select></div>
      <div class="field"><label>Product icon URL (optional)</label><input name="iconUrl" value="${esc(meta.iconUrl)}" placeholder="https://.../telegram.png"></div>
      <div class="field"><label>Delivery from (hours)</label><input name="deliveryMinHours" type="number" min="0" max="720" value="${esc(meta.deliveryMinHours)}"></div>
      <div class="field"><label>Delivery up to (hours)</label><input name="deliveryMaxHours" type="number" min="1" max="720" value="${esc(meta.deliveryMaxHours)}"></div>
      <div class="field"><label>Display order</label><input name="sortOrder" type="number" value="${esc(service?.sortOrder ?? 100)}"></div>
    </div>
    <div class="forms">
      <div class="field"><label>English description</label><textarea name="descriptionEn">${esc(service?.descriptionEn || '')}</textarea></div>
      <div class="field"><label>توضیحات فارسی</label><textarea name="descriptionFa">${esc(service?.descriptionFa || '')}</textarea></div>
      <div class="field"><label>English instructions before purchase</label><textarea name="instructionsEn">${esc(meta.instructionsEn)}</textarea></div>
      <div class="field"><label>راهنمای فارسی قبل از خرید</label><textarea name="instructionsFa">${esc(meta.instructionsFa)}</textarea></div>
    </div>
    <div class="cardhead"><div><h3>Packages</h3><span class="muted">Each package has its own duration, price and optional stock.</span></div><button type="button" class="btn ghost" onclick="premiumAddPackage()">+ Add package</button></div>
    <div id="premium-packages">${packages.map(packageRow).join('')}</div>
    <div class="cardhead" style="margin-top:18px"><div><h3>Customer order form</h3><span class="muted">Do not ask for passwords here. Use username, phone, email or custom text needed for activation.</span></div><button type="button" class="btn ghost" onclick="premiumAddField()">+ Add field</button></div>
    <div id="premium-fields">${fields.map(fieldRow).join('')}</div>
    <div class="actions" style="margin-top:14px">
      <label class="check"><input type="checkbox" name="enabled" ${service?.enabled === false ? '' : 'checked'}> Visible in app</label>
      <label class="check"><input type="checkbox" name="featured" ${service?.featured ? 'checked' : ''}> Featured</label>
    </div>
    <button class="btn" style="width:100%;height:42px">Save product & packages</button>
  </form>
  <template id="premium-package-template">${packageRow()}</template>
  <template id="premium-field-template">${fieldRow()}</template>
  <script>
  function premiumAddPackage(){const t=document.getElementById('premium-package-template');document.getElementById('premium-packages').append(t.content.cloneNode(true));}
  function premiumAddField(){const t=document.getElementById('premium-field-template');document.getElementById('premium-fields').append(t.content.cloneNode(true));}
  function premiumVal(row,key){const el=row.querySelector('[data-k="'+key+'"]');return el?String(el.value||'').trim():'';}
  function premiumCheck(row,key){const el=row.querySelector('[data-k="'+key+'"]');return Boolean(el&&el.checked);}
  function premiumPrepareProduct(form){
    const packages=Array.from(document.querySelectorAll('.premium-package-row')).map((row,index)=>({
      id:premiumVal(row,'id')||('package-'+(index+1)),
      titleEn:premiumVal(row,'titleEn'),
      titleFa:premiumVal(row,'titleFa'),
      durationEn:premiumVal(row,'durationEn'),
      durationFa:premiumVal(row,'durationFa'),
      priceAfn:premiumVal(row,'priceAfn'),
      stock:premiumVal(row,'stock')===''?null:Number(premiumVal(row,'stock')),
      sortOrder:Number(premiumVal(row,'sortOrder')||((index+1)*10)),
      badgeEn:premiumVal(row,'badgeEn'),
      badgeFa:premiumVal(row,'badgeFa'),
      enabled:premiumCheck(row,'enabled')
    }));
    if(packages.length===0){alert('Add at least one package.');return false;}
    if(packages.some(p=>!/^\\d+$/.test(p.priceAfn)||Number(p.priceAfn)<=0)){alert('Every package needs a valid AFN price.');return false;}
    const fields=Array.from(document.querySelectorAll('.premium-field-row')).map((row,index)=>({
      key:premiumVal(row,'key')||('field-'+(index+1)),
      type:premiumVal(row,'type')||'TEXT',
      labelEn:premiumVal(row,'labelEn'),
      labelFa:premiumVal(row,'labelFa'),
      placeholderEn:premiumVal(row,'placeholderEn'),
      placeholderFa:premiumVal(row,'placeholderFa'),
      required:premiumCheck(row,'required'),
      options:premiumVal(row,'options').split(',').map(v=>v.trim()).filter(Boolean)
    }));
    form.elements.packagesJson.value=JSON.stringify(packages);
    form.elements.formFieldsJson.value=JSON.stringify(fields);
    return true;
  }
  </script>`;
}

function premiumState(order: any) {
  const output = jsonObject(order.output);
  return String(output.premiumState || order.status || 'PENDING');
}

function submittedFields(order: any) {
  const input = jsonObject(order.input);
  return jsonObject(input.submittedFields);
}

function packageSnapshot(order: any) {
  return jsonObject(jsonObject(order.input).package);
}

export async function premiumAdminPage(
  prisma: PrismaClient,
  tab: string,
  edit: string,
) {
  const activeTab = ['overview','banner','products','orders','settings'].includes(tab) ? tab : 'overview';
  const tabHtml = tabs(activeTab);

  if (activeTab === 'banner') {
    const banner = await prisma.banner.findFirst({
      where: {
        placement: BannerPlacement.SERVICES_TOP,
        actionUrl: 'velixeo://premium',
      },
      orderBy: { updatedAt: 'desc' },
    });
    return {
      tabs: tabHtml,
      body: `<div class="grid eq"><div class="card"><div class="cardhead"><div><h2>Premium section banner</h2><span class="muted">Shown when users enter Premium & Subscriptions.</span></div>${banner ? (banner.enabled ? pill('Live','ok') : pill('Disabled','bad')) : pill('Built-in fallback','info')}</div>
      <div class="notice">The app has a bilingual built-in banner even when no image is configured. Later UI/UX work can replace this image without changing product logic.</div>
      <form method="post" action="/admin/v3/premium/banner"><input type="hidden" name="id" value="${esc(banner?.id || '')}">
      <div class="forms"><div class="field"><label>English title</label><input name="titleEn" value="${esc(banner?.titleEn || 'Premium & Subscriptions')}"></div><div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(banner?.titleFa || 'پریمیوم و اشتراک‌ها')}"></div></div>
      <div class="forms"><div class="field"><label>English subtitle</label><textarea name="subtitleEn">${esc(banner?.subtitleEn || 'Choose a plan, pay securely from your wallet, and our team completes the activation manually.')}</textarea></div><div class="field"><label>توضیح فارسی</label><textarea name="subtitleFa">${esc(banner?.subtitleFa || 'پکیج موردنظر را انتخاب کنید، از کیف پول پرداخت کنید و تیم ما فعال‌سازی را برایتان انجام می‌دهد.')}</textarea></div></div>
      <div class="field"><label>Banner image URL (optional)</label><input class="mono" name="imageUrl" value="${esc(banner?.imageUrl || '')}" placeholder="https://.../premium-banner.webp"><span class="muted">Leave empty to keep the built-in gradient hero.</span></div>
      <div class="forms"><div class="field"><label>Sort order</label><input type="number" name="sortOrder" value="${esc(banner?.sortOrder ?? 10)}"></div><div class="field"><label>Deep link</label><input value="velixeo://premium" disabled></div></div>
      <label class="check"><input type="checkbox" name="enabled" ${banner?.enabled === false ? '' : 'checked'}> Show banner</label>
      <button class="btn">Save Premium banner</button></form></div>
      <div class="card"><div class="cardhead"><h2>Preview</h2><span class="muted">Logic preview — final visual design comes later</span></div>
      <div style="height:190px;border-radius:20px;overflow:hidden;position:relative;background:linear-gradient(135deg,#6d4cff,#ff9e36)">
      ${banner?.imageUrl ? `<img src="${esc(banner.imageUrl)}" style="width:100%;height:100%;object-fit:cover">` : ''}
      <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(14,13,36,.72),rgba(14,13,36,.15))"></div>
      <div style="position:absolute;left:18px;right:18px;bottom:18px;color:white"><b style="font-size:20px">${esc(banner?.titleEn || 'Premium & Subscriptions')}</b><div style="font-size:11px;margin-top:6px">${esc(banner?.subtitleEn || 'Manual activation after secure wallet payment.')}</div></div></div></div></div>`,
    };
  }

  if (activeTab === 'products') {
    const services = await prisma.service.findMany({
      where: { category: ServiceCategory.PREMIUM },
      orderBy: [{ enabled: 'desc' }, { sortOrder: 'asc' }, { titleEn: 'asc' }],
    });
    const selected = edit ? services.find((service) => service.id === edit) ?? null : null;
    return {
      tabs: tabHtml,
      body: `<div class="grid"><div><div class="card"><div class="cardhead"><div><h2>Premium products</h2><span class="muted">Manual packages — no provider API required.</span></div><a class="btn" href="${href('products','&edit=new')}">+ New product</a></div>
      <div class="tablewrap"><table class="table"><thead><tr><th>Product</th><th>Group</th><th>Packages</th><th>From</th><th>Delivery</th><th>Status</th><th></th></tr></thead><tbody>
      ${services.map((service) => {
        const meta = parsePremiumMetadata(service.metadata);
        const min = premiumMinPriceAfn(meta);
        return `<tr><td><b>${esc(service.titleEn)}</b><br><span class="muted">${esc(service.titleFa)}</span></td><td>${esc(meta.group)}</td><td>${meta.packages.length}</td><td class="money">${min == null ? '—' : money(min)}</td><td>${meta.deliveryMinHours}–${meta.deliveryMaxHours}h<br><span class="muted">${esc(meta.deliveryType)}</span></td><td>${service.enabled ? pill('Live','ok') : pill('Hidden','bad')}</td><td><div class="actions"><a class="btn ghost" href="${href('products',`&edit=${service.id}`)}">Edit</a><form method="post" action="/admin/v3/premium/product-delete" onsubmit="return confirm('Remove this product? Existing orders are preserved.');"><input type="hidden" name="id" value="${service.id}"><button class="btn danger">Remove</button></form></div></td></tr>`;
      }).join('') || '<tr><td colspan="7" class="empty">No Premium products yet.</td></tr>'}
      </tbody></table></div></div></div>
      <div class="card"><div class="cardhead"><div><h2>${selected ? 'Edit product' : 'Create product'}</h2><span class="muted">Bilingual content + packages + dynamic customer fields</span></div>${selected ? `<a class="btn ghost" href="${href('products')}">New</a>` : ''}</div>${productForm(selected)}</div></div>`,
    };
  }

  if (activeTab === 'orders') {
    const orders = await prisma.order.findMany({
      where: { category: ServiceCategory.PREMIUM },
      include: { user: true, service: true, actions: { orderBy: { createdAt: 'desc' }, take: 5 } },
      orderBy: { createdAt: 'desc' },
      take: 150,
    });
    return {
      tabs: tabHtml,
      body: `<div class="card"><div class="cardhead"><div><h2>Premium fulfillment queue</h2><span class="muted">Every order shown here has already been charged from the customer wallet.</span></div>${pill(`${orders.filter(o => ['PENDING','PROCESSING'].includes(o.status)).length} open`,'info')}</div>
      <div class="tablewrap"><table class="table" style="min-width:1450px"><thead><tr><th>Invoice</th><th>Customer</th><th>Product / Package</th><th>Submitted data</th><th>Paid</th><th>State</th><th>Created</th><th>Fulfillment</th></tr></thead><tbody>
      ${orders.map((order) => {
        const pkg = packageSnapshot(order);
        const fields = submittedFields(order);
        const output = jsonObject(order.output);
        const state = premiumState(order);
        const open = !['COMPLETED','REFUNDED','CANCELLED','FAILED'].includes(order.status);
        return `<tr><td><b>#${esc(order.publicOrderNumber?.toString() || order.id.slice(0,8))}</b><br><span class="mono muted">${esc(order.id.slice(0,8))}</span></td>
        <td><b>${esc(order.user.fullName || '—')}</b><br><span class="muted">${esc(order.user.email || order.user.phone || '—')}</span></td>
        <td><b>${esc(order.service?.titleEn || order.service?.titleFa || 'Premium')}</b><br><span class="muted">${esc(pkg.titleEn || pkg.titleFa || pkg.id || 'Package')}</span></td>
        <td>${Object.entries(fields).map(([key,value]) => `<div><b>${esc(key)}:</b> ${esc(value)}</div>`).join('') || '—'}</td>
        <td class="money">${money(order.totalAmountAfn)}</td><td>${pill(state,state==='COMPLETED'?'ok':state==='REFUNDED'?'bad':state==='PROCESSING'?'info':'warn')}</td><td>${dt(order.createdAt)}</td>
        <td style="min-width:330px">${open ? `<form method="post" action="/admin/v3/premium/order-status"><input type="hidden" name="orderId" value="${order.id}"><div class="field"><label>Action</label><select name="action"><option value="PROCESSING">Processing</option><option value="NEED_INFORMATION">Need information</option><option value="COMPLETED">Completed</option><option value="REFUND">Reject + refund wallet</option></select></div><div class="field"><label>English customer message</label><input name="messageEn" value="${esc(output.adminMessageEn || '')}" placeholder="We need your correct username..."></div><div class="field"><label>پیام فارسی مشتری</label><input name="messageFa" value="${esc(output.adminMessageFa || '')}" placeholder="لطفاً یوزرنیم صحیح را ارسال کنید..."></div><div class="field"><label>Secure delivery text (optional; encrypted at rest)</label><textarea name="deliveryText" placeholder="Only use when delivering account/license details."></textarea></div><button class="btn">Update order</button></form>` : `<span class="muted">Closed · ${esc(state)}</span>`}</td></tr>`;
      }).join('') || '<tr><td colspan="8" class="empty">No Premium orders yet.</td></tr>'}
      </tbody></table></div></div>`,
    };
  }

  if (activeTab === 'settings') {
    const settings = await premiumTelegramSettings(prisma);
    return {
      tabs: tabHtml,
      body: `<div class="grid eq"><div class="card"><div class="cardhead"><div><h2>Telegram admin notifications</h2><span class="muted">One bot for registrations, verified wallet top-ups, paid orders and refunds.</span></div>${settings.tokenConfigured && settings.chatId ? pill('Ready','ok') : pill('Setup needed','warn')}</div>
      <div class="notice"><b>Security rule:</b> the Bot Token is never stored in the browser or database. Set <span class="mono">PREMIUM_TELEGRAM_BOT_TOKEN</span> in Railway. This form only stores the destination Chat ID.</div>
      <form method="post" action="/admin/v3/premium/telegram-settings"><div class="field"><label>Telegram Chat ID</label><input class="mono" name="chatId" value="${esc(settings.chatId)}" placeholder="-1001234567890"></div><label class="check"><input type="checkbox" name="enabled" ${settings.enabled ? 'checked' : ''}> Enable VELIXEO admin Telegram notifications</label><button class="btn">Save alert settings</button></form>
      <form method="post" action="/admin/v3/premium/telegram-test" style="margin-top:10px"><button class="btn ghost" ${settings.tokenConfigured && settings.chatId ? '' : 'disabled'}>Send test message</button></form></div>
      <div class="card"><div class="cardhead"><h2>Notification coverage</h2>${pill('Verified events only','info')}</div><div class="notice">Notifications are sent only after real events commit successfully: new registration, verified wallet credit, paid order, manual wallet adjustment or refund. Passwords, OTP codes, API keys and verification tokens are never included.</div><div class="provider" style="grid-template-columns:1fr auto"><div><b>Bot token</b><small>Railway secret</small></div>${settings.tokenConfigured ? pill('Configured','ok') : pill('Missing','bad')}</div><div class="provider" style="grid-template-columns:1fr auto"><div><b>Destination chat</b><small class="mono">${esc(settings.chatId || 'Not set')}</small></div>${settings.chatId ? pill('Configured','ok') : pill('Missing','warn')}</div></div></div>`,
    };
  }

  const [products, openOrders, completedOrders, revenue] = await Promise.all([
    prisma.service.findMany({ where: { category: ServiceCategory.PREMIUM }, orderBy: [{ enabled: 'desc' }, { sortOrder: 'asc' }] }),
    prisma.order.count({ where: { category: ServiceCategory.PREMIUM, status: { in: [OrderStatus.PENDING, OrderStatus.PROCESSING] } } }),
    prisma.order.count({ where: { category: ServiceCategory.PREMIUM, status: OrderStatus.COMPLETED } }),
    prisma.order.aggregate({ where: { category: ServiceCategory.PREMIUM, status: { notIn: [OrderStatus.REFUNDED, OrderStatus.CANCELLED, OrderStatus.FAILED] } }, _sum: { totalAmountAfn: true } }),
  ]);
  return {
    tabs: tabHtml,
    body: `<div class="card modulehero"><div class="cardhead"><div><h2>Premium Accounts Workspace</h2><p>Premium-only services such as Telegram Premium, Snapchat+ and similar subscriptions. Netflix, VPN and other digital accounts belong in Digital Accounts.</p></div></div><div class="kpis"><div><b>${products.length}</b><small>Products</small></div><div><b>${products.filter(p => p.enabled).length}</b><small>Live</small></div><div><b>${openOrders}</b><small>Open orders</small></div><div><b>${money(revenue._sum.totalAmountAfn || 0n)}</b><small>Paid sales</small></div></div></div>
    <div class="grid eq"><div class="card"><div class="cardhead"><h2>How this module works</h2>${pill('No provider API required','info')}</div><div class="notice">Product → package → dynamic customer form → wallet payment → paid order queue → Telegram admin invoice → manual fulfillment → customer notification.</div><a class="btn" href="${href('products')}">Manage products & packages</a></div><div class="card"><div class="cardhead"><h2>Fulfillment</h2>${pill(`${completedOrders} completed`,'ok')}</div><p class="muted">Use Processing while working on an order, Need information when the customer data is incomplete, Completed after activation/delivery, or Reject + refund when the service cannot be fulfilled.</p><a class="btn ghost" href="${href('orders')}">Open fulfillment queue</a></div></div>`,
  };
}

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

async function uniqueServiceSlug(prisma: PrismaClient, raw: string, name: string, id: string) {
  const base = safeSlug(raw || name);
  if (!base) throw new Error('A valid product name or slug is required.');
  let candidate = base;
  let suffix = 1;
  while (await prisma.service.findFirst({
    where: { slug: candidate, ...(id ? { id: { not: id } } : {}) },
    select: { id: true },
  })) {
    suffix += 1;
    candidate = `${base}-${suffix}`;
  }
  return candidate;
}

async function refundPremiumOrder(prisma: PrismaClient, orderId: string, reason: string) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findFirst({
      where: { id: orderId, category: ServiceCategory.PREMIUM },
      include: { service: true },
    });
    if (!order) throw new Error('Order not found');
    if (order.status === OrderStatus.REFUNDED) return order;
    if (order.status === OrderStatus.COMPLETED) throw new Error('Completed order cannot be refunded from this quick action.');

    const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
    if (!wallet) throw new Error('Wallet not found');
    const key = `premium-order-refund-${order.id}`;
    const existing = await tx.walletEntry.findUnique({ where: { idempotencyKey: key } });
    if (!existing) {
      const next = wallet.balanceAfn + order.totalAmountAfn;
      await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: next } });
      await tx.walletEntry.create({
        data: {
          walletId: wallet.id,
          type: WalletEntryType.REFUND,
          status: WalletEntryStatus.COMPLETED,
          amountAfn: order.totalAmountAfn,
          balanceAfterAfn: next,
          referenceType: 'PREMIUM_ORDER_REFUND',
          referenceId: order.id,
          description: reason || `Premium order refund ${order.id}`,
          idempotencyKey: key,
        },
      });
    }

    if (order.service) {
      await tx.$executeRaw`SELECT 1 FROM "Service" WHERE id = ${order.service.id} FOR UPDATE`;
      const locked = await tx.service.findUnique({ where: { id: order.service.id } });
      if (locked) {
        const meta = parsePremiumMetadata(locked.metadata);
        const packageId = String(jsonObject(order.input).packageId || '');
        const index = meta.packages.findIndex((pkg) => pkg.id === packageId);
        if (index >= 0 && meta.packages[index].stock != null) {
          meta.packages[index] = { ...meta.packages[index], stock: (meta.packages[index].stock ?? 0) + 1 };
          await tx.service.update({
            where: { id: locked.id },
            data: {
              metadata: premiumMetadataJson(meta),
              basePriceAfn: premiumMinPriceAfn(meta),
            },
          });
        }
      }
    }

    const output = jsonObject(order.output);
    return tx.order.update({
      where: { id: order.id },
      data: {
        status: OrderStatus.REFUNDED,
        completedAt: new Date(),
        failureReason: reason || 'Refunded by admin',
        output: {
          ...output,
          premiumState: 'REFUNDED',
          adminMessageEn: reason || 'Your order was refunded.',
          adminMessageFa: reason || 'مبلغ سفارش به کیف پول شما برگشت داده شد.',
          refundedAt: new Date().toISOString(),
        } as Prisma.InputJsonValue,
      },
      include: { service: true },
    });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

export function registerPremiumAdminRoutes(
  app: FastifyInstance,
  prisma: PrismaClient,
  resolveAdmin: AdminResolver,
) {
  app.post('/admin/v3/premium/banner', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const id = text(body, 'id');
      const imageUrl = text(body, 'imageUrl');
      const data = {
        placement: BannerPlacement.SERVICES_TOP,
        titleEn: text(body, 'titleEn') || null,
        titleFa: text(body, 'titleFa') || null,
        subtitleEn: text(body, 'subtitleEn') || null,
        subtitleFa: text(body, 'subtitleFa') || null,
        imageUrl: imageUrl || '',
        actionLabelEn: null,
        actionLabelFa: null,
        actionUrl: 'velixeo://premium',
        enabled: checked(body, 'enabled'),
        sortOrder: intValue(body.sortOrder, 10),
      };
      const saved = id
        ? await prisma.banner.update({ where: { id }, data })
        : await prisma.banner.create({ data });
      await audit(prisma, admin.id, id ? 'PREMIUM_BANNER_UPDATE' : 'PREMIUM_BANNER_CREATE', 'Banner', saved.id, 'Premium section banner');
      return reply.code(303).redirect(href('banner', '&msg=Premium%20banner%20saved'));
    } catch (error) {
      return reply.code(303).redirect(href('banner', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'premium_banner_failed')}`));
    }
  });

  app.post('/admin/v3/premium/product', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const id = text(body, 'id');
      const titleEn = text(body, 'titleEn');
      const titleFa = text(body, 'titleFa');
      if (!titleEn || !titleFa) throw new Error('English and Persian product titles are required.');
      const slug = await uniqueServiceSlug(prisma, text(body, 'slug'), titleEn, id);
      let packagesRaw: unknown;
      let fieldsRaw: unknown;
      try {
        packagesRaw = JSON.parse(text(body, 'packagesJson') || '[]');
        fieldsRaw = JSON.parse(text(body, 'formFieldsJson') || '[]');
      } catch {
        throw new Error('Package or customer-form data is invalid.');
      }
      const meta = parsePremiumMetadata({
        premium: {
          version: 1,
          group: text(body, 'group') || 'OTHER',
          deliveryType: text(body, 'deliveryType') || 'MANUAL_ACTIVATION',
          deliveryMinHours: intValue(body.deliveryMinHours, 1),
          deliveryMaxHours: intValue(body.deliveryMaxHours, 12),
          iconUrl: text(body, 'iconUrl'),
          instructionsFa: text(body, 'instructionsFa'),
          instructionsEn: text(body, 'instructionsEn'),
          packages: packagesRaw,
          formFields: fieldsRaw,
        },
      });
      if (!meta.packages.length) throw new Error('Add at least one valid package with a positive AFN price.');
      if (meta.deliveryMaxHours < meta.deliveryMinHours) meta.deliveryMaxHours = meta.deliveryMinHours;

      const data = {
        category: ServiceCategory.PREMIUM,
        slug,
        titleEn,
        titleFa,
        descriptionEn: text(body, 'descriptionEn') || null,
        descriptionFa: text(body, 'descriptionFa') || null,
        enabled: checked(body, 'enabled'),
        featured: checked(body, 'featured'),
        sortOrder: intValue(body.sortOrder, 100),
        basePriceAfn: premiumMinPriceAfn(meta),
        priceUnit: 1,
        minQty: 1,
        maxQty: 1,
        metadata: premiumMetadataJson(meta),
      };
      const service = id
        ? await prisma.service.update({ where: { id }, data })
        : await prisma.service.create({ data });
      await audit(prisma, admin.id, id ? 'PREMIUM_PRODUCT_UPDATE' : 'PREMIUM_PRODUCT_CREATE', 'Service', service.id, `${service.titleEn}: ${meta.packages.length} packages`);
      return reply.code(303).redirect(href('products', `&edit=${service.id}&msg=${encodeURIComponent('Premium product saved')}`));
    } catch (error) {
      return reply.code(303).redirect(href('products', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'premium_product_failed')}`));
    }
  });

  app.post('/admin/v3/premium/product-delete', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const id = text(request.body as Body, 'id');
    try {
      const service = await prisma.service.findFirst({ where: { id, category: ServiceCategory.PREMIUM } });
      if (!service) throw new Error('Product not found');
      const orders = await prisma.order.count({ where: { serviceId: id } });
      if (orders > 0) {
        await prisma.service.update({ where: { id }, data: { enabled: false } });
        await audit(prisma, admin.id, 'PREMIUM_PRODUCT_ARCHIVE', 'Service', id, `${service.titleEn}: hidden because historical orders exist`);
      } else {
        await prisma.service.delete({ where: { id } });
        await audit(prisma, admin.id, 'PREMIUM_PRODUCT_DELETE', 'Service', id, service.titleEn);
      }
      return reply.code(303).redirect(href('products', '&msg=Premium%20product%20removed'));
    } catch (error) {
      return reply.code(303).redirect(href('products', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'premium_delete_failed')}`));
    }
  });

  app.post('/admin/v3/premium/telegram-settings', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    try {
      const saved = await savePremiumTelegramSettings(prisma, {
        enabled: checked(body, 'enabled'),
        chatId: text(body, 'chatId'),
      });
      await audit(prisma, admin.id, 'PREMIUM_TELEGRAM_SETTINGS', 'SystemSetting', 'premium.telegram.admin', `enabled=${saved.enabled}, chat=${saved.chatId || 'none'}`);
      return reply.code(303).redirect(href('settings', '&msg=Telegram%20alert%20settings%20saved'));
    } catch (error) {
      return reply.code(303).redirect(href('settings', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'telegram_settings_failed')}`));
    }
  });

  app.post('/admin/v3/premium/telegram-test', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    try {
      const result = await sendPremiumTelegramMessage(prisma, '✅ VELIXEO Premium admin alert test\nTelegram notifications are connected.');
      if (!result.sent) throw new Error(result.reason || 'telegram_not_configured');
      await audit(prisma, admin.id, 'PREMIUM_TELEGRAM_TEST', 'SystemSetting', 'premium.telegram.admin', 'Telegram test message sent');
      return reply.code(303).redirect(href('settings', '&msg=Telegram%20test%20message%20sent'));
    } catch (error) {
      return reply.code(303).redirect(href('settings', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'telegram_test_failed')}`));
    }
  });

  app.post('/admin/v3/premium/order-status', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin);
    if (!admin) return;
    const body = request.body as Body;
    const orderId = text(body, 'orderId');
    const action = text(body, 'action').toUpperCase();
    const messageEn = text(body, 'messageEn');
    const messageFa = text(body, 'messageFa');
    const deliveryText = text(body, 'deliveryText');
    try {
      const current = await prisma.order.findFirst({
        where: { id: orderId, category: ServiceCategory.PREMIUM },
        include: { service: true },
      });
      if (!current) throw new Error('Order not found');

      let updated = current;
      if (action === 'REFUND') {
        updated = await refundPremiumOrder(prisma, current.id, messageEn || messageFa || 'Premium order could not be fulfilled');
      } else {
        const output = jsonObject(current.output);
        let encryptedDelivery: Record<string, string> | undefined;
        if (deliveryText) {
          if (!providerSecretEncryptionConfigured()) throw new Error('Server encryption is required before storing secure delivery text.');
          const encrypted = encryptProviderSecret(deliveryText);
          encryptedDelivery = {
            ciphertext: encrypted.secretCiphertext,
            iv: encrypted.secretIv,
            tag: encrypted.secretTag,
          };
        }
        const state = action === 'COMPLETED' ? 'COMPLETED'
          : action === 'PROCESSING' ? 'PROCESSING'
          : action === 'NEED_INFORMATION' ? 'NEED_INFORMATION'
          : 'PENDING';
        const status = state === 'COMPLETED'
          ? OrderStatus.COMPLETED
          : state === 'PROCESSING'
            ? OrderStatus.PROCESSING
            : OrderStatus.PENDING;
        updated = await prisma.order.update({
          where: { id: current.id },
          data: {
            status,
            completedAt: state === 'COMPLETED' ? new Date() : null,
            output: {
              ...output,
              premiumState: state,
              adminMessageEn: messageEn || null,
              adminMessageFa: messageFa || null,
              ...(encryptedDelivery ? { deliverySecret: encryptedDelivery } : {}),
              adminUpdatedAt: new Date().toISOString(),
            } as Prisma.InputJsonValue,
          },
          include: { service: true },
        });
      }

      const state = action === 'REFUND' ? 'REFUNDED' : action;
      const notification = state === 'COMPLETED'
        ? {
            titleEn: 'Premium order completed',
            titleFa: 'سفارش پریمیوم تکمیل شد',
            bodyEn: messageEn || 'Your Premium order has been completed successfully.',
            bodyFa: messageFa || 'سفارش پریمیوم شما با موفقیت تکمیل شد.',
          }
        : state === 'PROCESSING'
          ? {
              titleEn: 'Premium order is processing',
              titleFa: 'سفارش پریمیوم در حال انجام است',
              bodyEn: messageEn || 'Our team has started working on your order.',
              bodyFa: messageFa || 'تیم ما انجام سفارش شما را آغاز کرده است.',
            }
          : state === 'NEED_INFORMATION'
            ? {
                titleEn: 'More information is required',
                titleFa: 'اطلاعات بیشتری نیاز است',
                bodyEn: messageEn || 'Please review your Premium order and contact support with the requested information.',
                bodyFa: messageFa || 'لطفاً سفارش پریمیوم را بررسی کرده و اطلاعات درخواستی را برای پشتیبانی ارسال کنید.',
              }
            : {
                titleEn: 'Premium order refunded',
                titleFa: 'مبلغ سفارش پریمیوم برگشت داده شد',
                bodyEn: messageEn || 'The order could not be fulfilled and the amount was returned to your wallet.',
                bodyFa: messageFa || 'سفارش قابل انجام نبود و مبلغ آن به کیف پول شما برگشت داده شد.',
              };
      try {
        await publishUserNotification(prisma, updated.userId, {
          type: NotificationType.ORDER,
          priority: NotificationPriority.HIGH,
          ...notification,
          actionRoute: 'orders',
          actionEntityId: updated.id,
          actionLabelEn: 'View order',
          actionLabelFa: 'مشاهده سفارش',
        });
      } catch {}

      if (action === 'REFUND') {
        try {
          await sendAdminRefundAlert(prisma, updated.id, messageEn || messageFa || 'Premium order refunded by admin');
        } catch (error) {
          request.log.warn({ error, orderId: updated.id }, 'admin Telegram Premium refund alert failed');
        }
      }

      await prisma.orderActionLog.create({
        data: {
          orderId: updated.id,
          action: 'PREMIUM_ADMIN_STATUS',
          status: state,
          response: {
            adminId: admin.id,
            messageEn,
            messageFa,
            secureDeliveryUpdated: Boolean(deliveryText),
          },
        },
      });
      await audit(prisma, admin.id, 'PREMIUM_ORDER_STATUS', 'Order', updated.id, `#${updated.publicOrderNumber?.toString() || updated.id.slice(0,8)} → ${state}`);
      return reply.code(303).redirect(href('orders', '&msg=Premium%20order%20updated'));
    } catch (error) {
      return reply.code(303).redirect(href('orders', `&err=1&msg=${encodeURIComponent(error instanceof Error ? error.message : 'premium_order_update_failed')}`));
    }
  });
}
