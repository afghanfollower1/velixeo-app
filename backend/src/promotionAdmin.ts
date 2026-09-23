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
  parsePromotionMetadata,
  promotionMetadataJson,
  promotionMinPriceAfn,
  type PromotionPackage,
} from './promotionCatalog.js';
import { publishUserNotification } from './pushNotifications.js';
import { sendAdminRefundAlert } from './adminTelegramEvents.js';

type AdminIdentity = { id: string; fullName: string | null; email: string | null; phone: string | null };
type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type Body = Record<string, unknown>;

const esc = (value: unknown) => String(value ?? '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const textValue = (body: Body, key: string) => String(body[key] ?? '').trim();
const checked = (body: Body, key: string) => ['on', 'true', '1'].includes(String(body[key] ?? ''));
const intValue = (value: unknown, fallback = 0) => Number.isFinite(Number.parseInt(String(value ?? ''), 10))
  ? Number.parseInt(String(value ?? ''), 10)
  : fallback;
const obj = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' && !Array.isArray(value) ? value as Record<string, unknown> : {};
const money = (value: bigint | string | number | null | undefined) =>
  `${Number(value ?? 0).toLocaleString('en-US')} AFN`;
const dt = (value: Date | string | null | undefined) =>
  value ? new Date(value).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' }) : '—';
const pill = (label: string, kind = '') => `<span class="pill ${kind}">${esc(label)}</span>`;
const href = (tab: string, extra = '') => `/admin/v3?section=promotions&tab=${encodeURIComponent(tab)}${extra}`;

function safeSlug(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 80);
}

function tabs(active: string) {
  return `<div class="tabs">${[
    ['overview','Overview'],
    ['banner','Banner'],
    ['packages','Packages'],
    ['orders','Orders'],
    ['connections','Instagram Connections'],
    ['meta','Meta Setup'],
  ].map(([key,label])=>`<a class="tab ${active===key?'active':''}" href="${href(key)}">${label}</a>`).join('')}</div>`;
}

function packageRow(pkg?: Partial<PromotionPackage>) {
  return `<div class="card promotion-package-row" style="box-shadow:none;border-style:dashed;padding:11px">
  <div class="cardhead"><b>Promotion package</b><button type="button" class="btn danger" onclick="this.closest('.promotion-package-row').remove()">Remove</button></div>
  <div class="forms">
    <div class="field"><label>Package ID</label><input data-k="id" value="${esc(pkg?.id || '')}" placeholder="growth-3-days"></div>
    <div class="field"><label>Total customer price AFN</label><input data-k="priceAfn" type="number" min="1" value="${esc(pkg?.priceAfn || '')}" required></div>
    <div class="field"><label>Ad budget AFN</label><input data-k="adBudgetAfn" type="number" min="0" value="${esc(pkg?.adBudgetAfn || '')}"></div>
    <div class="field"><label>Service fee AFN</label><input data-k="serviceFeeAfn" type="number" min="0" value="${esc(pkg?.serviceFeeAfn || '0')}"></div>
    <div class="field"><label>English title</label><input data-k="titleEn" value="${esc(pkg?.titleEn || '')}" placeholder="Growth"></div>
    <div class="field"><label>عنوان فارسی</label><input data-k="titleFa" value="${esc(pkg?.titleFa || '')}" placeholder="رشد"></div>
    <div class="field"><label>Duration days</label><input data-k="durationDays" type="number" min="1" max="90" value="${esc(pkg?.durationDays ?? 3)}"></div>
    <div class="field"><label>Sort order</label><input data-k="sortOrder" type="number" min="1" value="${esc(pkg?.sortOrder ?? 10)}"></div>
    <div class="field"><label>English badge</label><input data-k="badgeEn" value="${esc(pkg?.badgeEn || '')}" placeholder="Popular"></div>
    <div class="field"><label>نشان فارسی</label><input data-k="badgeFa" value="${esc(pkg?.badgeFa || '')}" placeholder="محبوب"></div>
    <div class="field"><label>English estimate note</label><input data-k="estimateEn" value="${esc(pkg?.estimateEn || '')}" placeholder="Estimated reach varies by auction"></div>
    <div class="field"><label>توضیح تخمینی فارسی</label><input data-k="estimateFa" value="${esc(pkg?.estimateFa || '')}" placeholder="نتیجه تقریبی و وابسته به مزایده متا است"></div>
  </div>
  <label class="check"><input data-k="enabled" type="checkbox" ${pkg?.enabled===false?'':'checked'}> Available to customers</label>
  </div>`;
}

function productForm(service: any | null) {
  const meta = service ? parsePromotionMetadata(service.metadata) : parsePromotionMetadata(null);
  const packages = meta.packages.length ? meta.packages : [{
    id:'starter-2-days', titleFa:'شروع', titleEn:'Starter', priceAfn:'500', adBudgetAfn:'400',
    serviceFeeAfn:'100', durationDays:2, enabled:true, sortOrder:10, badgeFa:'', badgeEn:'',
    estimateFa:'', estimateEn:'',
  } satisfies PromotionPackage];
  const objectiveOptions = [
    ['ENGAGEMENT','Engagement'],['PROFILE_VISITS','Profile visits'],['MESSAGES','Messages'],
    ['WEBSITE_VISITS','Website visits'],['AWARENESS','Awareness'],
  ];
  return `<form method="post" action="/admin/v3/promotions/product" onsubmit="return promotionPrepare(this)">
    <input type="hidden" name="id" value="${esc(service?.id || '')}">
    <input type="hidden" name="packagesJson">
    <div class="forms">
      <div class="field"><label>English title</label><input name="titleEn" value="${esc(service?.titleEn || '')}" required placeholder="Instagram Promotion"></div>
      <div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(service?.titleFa || '')}" required placeholder="تبلیغ اینستاگرام"></div>
      <div class="field"><label>Slug</label><input class="mono" name="slug" value="${esc(service?.slug || '')}" placeholder="instagram-promotion"></div>
      <div class="field"><label>Platform</label><select name="platform"><option value="INSTAGRAM" ${meta.platform==='INSTAGRAM'?'selected':''}>Instagram</option><option value="FACEBOOK" ${meta.platform==='FACEBOOK'?'selected':''}>Facebook</option></select></div>
      <div class="field"><label>Delivery from (hours)</label><input name="deliveryMinHours" type="number" min="0" max="720" value="${meta.deliveryMinHours}"></div>
      <div class="field"><label>Delivery up to (hours)</label><input name="deliveryMaxHours" type="number" min="1" max="720" value="${meta.deliveryMaxHours}"></div>
      <div class="field"><label>Display order</label><input name="sortOrder" type="number" value="${esc(service?.sortOrder ?? 100)}"></div>
      <div class="field"><label>Icon URL (optional)</label><input name="iconUrl" value="${esc(meta.iconUrl)}" placeholder="https://..."></div>
    </div>
    <div class="forms">
      <div class="field"><label>English description</label><textarea name="descriptionEn">${esc(service?.descriptionEn || '')}</textarea></div>
      <div class="field"><label>توضیحات فارسی</label><textarea name="descriptionFa">${esc(service?.descriptionFa || '')}</textarea></div>
      <div class="field"><label>English instructions</label><textarea name="instructionsEn">${esc(meta.instructionsEn)}</textarea></div>
      <div class="field"><label>راهنمای فارسی</label><textarea name="instructionsFa">${esc(meta.instructionsFa)}</textarea></div>
    </div>
    <div class="field"><label>Supported objectives</label><div class="actions">${objectiveOptions.map(([value,label])=>`<label class="check"><input type="checkbox" name="objective_${value}" ${meta.supportedObjectives.includes(value as any)?'checked':''}> ${label}</label>`).join('')}</div></div>
    <label class="check"><input type="checkbox" name="requirePartnershipAdCode" ${meta.requirePartnershipAdCode?'checked':''}> Fallback only: require Partnership Ad Code when no Instagram account is connected</label>
    <div class="cardhead" style="margin-top:18px"><div><h3>Promotion Packages</h3><span class="muted">Separate customer price, ad budget and service fee for clear accounting.</span></div><button type="button" class="btn ghost" onclick="promotionAddPackage()">+ Add package</button></div>
    <div id="promotion-packages">${packages.map(packageRow).join('')}</div>
    <div class="actions" style="margin-top:14px"><label class="check"><input type="checkbox" name="enabled" ${service?.enabled===false?'':'checked'}> Visible in app</label><label class="check"><input type="checkbox" name="featured" ${service?.featured?'checked':''}> Featured</label></div>
    <button class="btn" style="width:100%;height:42px">Save promotion product</button>
  </form>
  <template id="promotion-package-template">${packageRow()}</template>
  <script>
  function promotionAddPackage(){const t=document.getElementById('promotion-package-template');document.getElementById('promotion-packages').append(t.content.cloneNode(true));}
  function pval(row,key){const el=row.querySelector('[data-k="'+key+'"]');return el?String(el.value||'').trim():'';}
  function pcheck(row,key){const el=row.querySelector('[data-k="'+key+'"]');return Boolean(el&&el.checked);}
  function promotionPrepare(form){
    const packages=Array.from(document.querySelectorAll('.promotion-package-row')).map((row,index)=>({
      id:pval(row,'id')||('package-'+(index+1)), titleEn:pval(row,'titleEn'), titleFa:pval(row,'titleFa'),
      priceAfn:pval(row,'priceAfn'), adBudgetAfn:pval(row,'adBudgetAfn')||pval(row,'priceAfn'),
      serviceFeeAfn:pval(row,'serviceFeeAfn')||'0', durationDays:Number(pval(row,'durationDays')||3),
      sortOrder:Number(pval(row,'sortOrder')||((index+1)*10)), badgeEn:pval(row,'badgeEn'), badgeFa:pval(row,'badgeFa'),
      estimateEn:pval(row,'estimateEn'), estimateFa:pval(row,'estimateFa'), enabled:pcheck(row,'enabled')
    }));
    if(!packages.length){alert('Add at least one package.');return false;}
    if(packages.some(p=>!/^[0-9]+$/.test(p.priceAfn)||Number(p.priceAfn)<=0)){alert('Every package needs a valid customer price.');return false;}
    form.elements.packagesJson.value=JSON.stringify(packages);return true;
  }
  </script>`;
}

function stateOf(order: any) {
  const output = obj(order.output);
  return String(output.promotionState || order.status || 'PENDING_REVIEW');
}

async function requireAdmin(request: FastifyRequest, reply: FastifyReply, resolveAdmin: AdminResolver) {
  const admin = await resolveAdmin(request);
  if (!admin) { reply.code(303).redirect('/admin/login'); return null; }
  return admin;
}

async function audit(prisma: PrismaClient, adminId: string, action: string, entityType: string, entityId: string | null, summary: string) {
  await prisma.adminAuditLog.create({ data: { adminUserId: adminId, action, entityType, entityId, summary } });
}

async function uniqueSlug(prisma: PrismaClient, raw: string, name: string, id: string) {
  const base = safeSlug(raw || name);
  if (!base) throw new Error('A valid product name or slug is required.');
  let candidate = base, suffix = 1;
  while (await prisma.service.findFirst({ where: { slug: candidate, ...(id ? { id: { not: id } } : {}) }, select: { id: true } })) {
    suffix += 1; candidate = `${base}-${suffix}`;
  }
  return candidate;
}

async function refundOrder(prisma: PrismaClient, orderId: string, reason: string) {
  return prisma.$transaction(async (tx) => {
    const order = await tx.order.findFirst({ where: { id: orderId, category: ServiceCategory.PROMOTION }, include: { service: true } });
    if (!order) throw new Error('Order not found');
    if (order.status === OrderStatus.REFUNDED) return order;
    if (order.status === OrderStatus.COMPLETED) throw new Error('Completed order cannot be refunded from this action.');
    const wallet = await tx.wallet.findUnique({ where: { userId: order.userId } });
    if (!wallet) throw new Error('Wallet not found');
    const key = `promotion-order-refund-${order.id}`;
    const existing = await tx.walletEntry.findUnique({ where: { idempotencyKey: key } });
    if (!existing) {
      const next = wallet.balanceAfn + order.totalAmountAfn;
      await tx.wallet.update({ where: { id: wallet.id }, data: { balanceAfn: next } });
      await tx.walletEntry.create({ data: {
        walletId: wallet.id, type: WalletEntryType.REFUND, status: WalletEntryStatus.COMPLETED,
        amountAfn: order.totalAmountAfn, balanceAfterAfn: next, referenceType:'PROMOTION_ORDER_REFUND',
        referenceId: order.id, description: reason || 'Promotion order refund', idempotencyKey:key,
      }});
    }
    const output = obj(order.output);
    return tx.order.update({ where: { id: order.id }, data: {
      status: OrderStatus.REFUNDED, completedAt: new Date(), failureReason: reason || 'Refunded by admin',
      output: { ...output, promotionState:'REFUNDED', adminMessageEn:reason || 'Your promotion order was refunded.', adminMessageFa:reason || 'مبلغ سفارش تبلیغ به کیف پول شما برگشت داده شد.', refundedAt:new Date().toISOString() } as Prisma.InputJsonValue,
    }, include: { service: true } });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

export async function promotionAdminPage(prisma: PrismaClient, tab: string, edit: string) {
  const active = ['overview','banner','packages','orders','connections','meta'].includes(tab) ? tab : 'overview';
  const tabHtml = tabs(active);

  if (active === 'banner') {
    const banner = await prisma.banner.findFirst({ where:{ placement:BannerPlacement.SERVICES_TOP, actionUrl:'velixeo://promotions' }, orderBy:{updatedAt:'desc'} });
    return { tabs:tabHtml, body:`<div class="grid eq"><div class="card"><div class="cardhead"><div><h2>Promotions banner</h2><span class="muted">Explains Instagram/Facebook promotion when users enter this section.</span></div>${banner?.enabled?pill('Live','ok'):pill('Fallback available','info')}</div>
    <form method="post" action="/admin/v3/promotions/banner"><input type="hidden" name="id" value="${esc(banner?.id||'')}">
    <div class="forms"><div class="field"><label>English title</label><input name="titleEn" value="${esc(banner?.titleEn||'Promote your content without a bank card')}"></div><div class="field"><label>عنوان فارسی</label><input name="titleFa" value="${esc(banner?.titleFa||'بدون ویزاکارت، محتوایت را تبلیغ کن')}"></div></div>
    <div class="forms"><div class="field"><label>English subtitle</label><textarea name="subtitleEn">${esc(banner?.subtitleEn||'Choose a package, share your post link and partnership ad code, and VELIXEO launches the Meta ad.')}</textarea></div><div class="field"><label>توضیح فارسی</label><textarea name="subtitleFa">${esc(banner?.subtitleFa||'پکیج را انتخاب کن، لینک پست و کد اجازه تبلیغ را بفرست؛ VELIXEO تبلیغ متا را اجرا می‌کند.')}</textarea></div></div>
    <div class="field"><label>Banner image URL (optional)</label><input name="imageUrl" value="${esc(banner?.imageUrl||'')}"></div><div class="field"><label>Sort order</label><input type="number" name="sortOrder" value="${esc(banner?.sortOrder??10)}"></div>
    <label class="check"><input type="checkbox" name="enabled" ${banner?.enabled===false?'':'checked'}> Show banner</label><button class="btn">Save Promotions banner</button></form></div>
    <div class="card"><h2>Version 1 model</h2><div class="notice">Customer pays from VELIXEO Wallet. The admin validates the Partnership Ad Code and launches the campaign manually in Meta Ads Manager. No customer password is collected.</div></div></div>` };
  }

  if (active === 'packages') {
    const services = await prisma.service.findMany({ where:{category:ServiceCategory.PROMOTION}, orderBy:[{enabled:'desc'},{sortOrder:'asc'},{titleEn:'asc'}] });
    const selected = edit ? services.find(s=>s.id===edit) ?? null : null;
    return { tabs:tabHtml, body:`<div class="grid"><div><div class="card"><div class="cardhead"><div><h2>Promotion products</h2><span class="muted">Instagram/Facebook manual Meta Ads packages.</span></div><a class="btn" href="${href('packages','&edit=new')}">+ New product</a></div>
    <div class="tablewrap"><table class="table"><thead><tr><th>Product</th><th>Platform</th><th>Packages</th><th>From</th><th>Status</th><th></th></tr></thead><tbody>${services.map(s=>{const m=parsePromotionMetadata(s.metadata);const min=promotionMinPriceAfn(m);return `<tr><td><b>${esc(s.titleEn)}</b><br><span class="muted">${esc(s.titleFa)}</span></td><td>${esc(m.platform)}</td><td>${m.packages.length}</td><td class="money">${min==null?'—':money(min)}</td><td>${s.enabled?pill('Live','ok'):pill('Hidden','bad')}</td><td><a class="btn ghost" href="${href('packages',`&edit=${s.id}`)}">Edit</a></td></tr>`}).join('')||'<tr><td colspan="6" class="empty">No promotion products yet.</td></tr>'}</tbody></table></div></div></div>
    <div class="card"><div class="cardhead"><div><h2>${selected?'Edit product':'Create product'}</h2><span class="muted">Package pricing + Meta permissions</span></div></div>${productForm(selected)}</div></div>` };
  }

  if (active === 'orders') {
    const orders = await prisma.order.findMany({ where:{category:ServiceCategory.PROMOTION}, include:{user:true,service:true}, orderBy:{createdAt:'desc'}, take:150 });
    return { tabs:tabHtml, body:`<div class="card"><div class="cardhead"><div><h2>Promotion fulfillment queue</h2><span class="muted">Paid orders waiting for manual Meta Ads execution.</span></div>${pill(`${orders.filter(o=>!['COMPLETED','REFUNDED','FAILED','CANCELLED'].includes(o.status)).length} open`,'info')}</div>
    <div class="tablewrap"><table class="table" style="min-width:1500px"><thead><tr><th>Invoice</th><th>Customer</th><th>Platform / Package</th><th>Post & Permission</th><th>Targeting</th><th>Paid</th><th>State</th><th>Fulfillment</th></tr></thead><tbody>${orders.map(order=>{const input=obj(order.input), output=obj(order.output), pkg=obj(input.package), state=stateOf(order), open=!['COMPLETED','REFUNDED','FAILED','CANCELLED'].includes(order.status);return `<tr>
    <td><b>#${esc(order.publicOrderNumber?.toString()||order.id.slice(0,8))}</b><br><span class="muted">${dt(order.createdAt)}</span></td>
    <td><b>${esc(order.user.fullName||'—')}</b><br><span class="muted">${esc(order.user.email||order.user.phone||'—')}</span></td>
    <td><b>${esc(input.platform||'—')}</b><br><span class="muted">${esc(pkg.titleEn||pkg.titleFa||pkg.id||'—')} · ${esc(pkg.durationDays||'—')} days</span></td>
    <td><div><b>Instagram:</b> ${input.instagramUsername?'@'+esc(input.instagramUsername):'—'} ${input.metaAdvertisingReady?pill('ADVERTISE','ok'):''}</div><div class="muted">${esc(input.instagramPageName||'')} ${input.metaConnectionId?'· '+esc(String(input.metaConnectionId).slice(0,8)):''}</div><div style="margin-top:5px"><b>Post:</b> <a href="${esc(input.postUrl||'#')}" target="_blank" rel="noreferrer">Open link</a></div><div style="margin-top:5px"><b>Media ID:</b> <span class="mono">${esc(input.instagramMediaId||'—')}</span></div><div style="margin-top:5px"><b>Ad code fallback:</b> <span class="mono">${esc(input.partnershipAdCode||'—')}</span></div></td>
    <td><div><b>${esc(input.objective||'—')}</b></div><div class="muted">${esc(Array.isArray(input.targetCountries)?input.targetCountries.join(', '):'—')}</div><div class="muted">${esc(input.audienceNotes||'')}</div></td>
    <td class="money">${money(order.totalAmountAfn)}</td><td>${pill(state,state==='COMPLETED'?'ok':state==='REFUNDED'?'bad':state==='ACTIVE'?'ok':state==='NEED_INFORMATION'?'warn':'info')}</td>
    <td style="min-width:330px">${open?`<form method="post" action="/admin/v3/promotions/order-status"><input type="hidden" name="orderId" value="${order.id}">
    <div class="field"><label>Action</label><select name="action"><option value="REVIEWING_CODE">Reviewing code</option><option value="NEED_INFORMATION">Need information</option><option value="READY_TO_LAUNCH">Ready to launch</option><option value="ACTIVE">Ad active</option><option value="COMPLETED">Completed</option><option value="REFUND">Reject + refund wallet</option></select></div>
    <div class="forms"><div class="field"><label>Meta Campaign ID</label><input class="mono" name="metaCampaignId" value="${esc(output.metaCampaignId||'')}"></div><div class="field"><label>Meta Ad ID</label><input class="mono" name="metaAdId" value="${esc(output.metaAdId||'')}"></div></div>
    <div class="field"><label>English customer message</label><input name="messageEn" value="${esc(output.adminMessageEn||'')}"></div><div class="field"><label>پیام فارسی مشتری</label><input name="messageFa" value="${esc(output.adminMessageFa||'')}"></div>
    <div class="field"><label>English result summary</label><textarea name="resultSummaryEn">${esc(output.resultSummaryEn||'')}</textarea></div><div class="field"><label>خلاصه نتیجه فارسی</label><textarea name="resultSummaryFa">${esc(output.resultSummaryFa||'')}</textarea></div>
    <button class="btn">Update order</button></form>`:`<span class="muted">Closed · ${esc(state)}</span>`}</td></tr>`}).join('')||'<tr><td colspan="8" class="empty">No promotion orders yet.</td></tr>'}</tbody></table></div></div>` };
  }

  if (active === 'connections') {
    const rows = await prisma.metaConnection.findMany({
      include: { user: true },
      orderBy: { updatedAt: 'desc' },
      take: 250,
    });
    return { tabs:tabHtml, body:`<div class="card"><div class="cardhead"><div><h2>Instagram connections</h2><span class="muted">Official Meta OAuth connections. Passwords are never stored or shown here.</span></div>${pill(`${rows.filter(r=>r.status==='CONNECTED').length} connected`,'info')}</div>
    <div class="tablewrap"><table class="table" style="min-width:1450px"><thead><tr><th>Customer</th><th>Instagram</th><th>Facebook Page</th><th>Advertising access</th><th>Granted permissions</th><th>Customer ad accounts</th><th>Status</th><th>Updated</th></tr></thead><tbody>${rows.map(row=>{
      const tasks=Array.isArray(row.pageTasks)?row.pageTasks.map(String):[];
      const perms=Array.isArray(row.permissions)?row.permissions.map(String):[];
      const ads=Array.isArray(row.adAccounts)?row.adAccounts as any[]:[];
      const ready=tasks.includes('ADVERTISE');
      const igUrl=row.instagramUsername?`https://www.instagram.com/${encodeURIComponent(row.instagramUsername)}/`:'';
      return `<tr>
      <td><b>${esc(row.user.fullName||'—')}</b><br><span class="muted">${esc(row.user.email||row.user.phone||'—')}</span></td>
      <td><b>${row.instagramUsername?'@'+esc(row.instagramUsername):'—'}</b><br><span class="muted mono">${esc(row.instagramUserId||'—')}</span>${igUrl?`<br><a href="${igUrl}" target="_blank" rel="noreferrer">Open Instagram</a>`:''}</td>
      <td><b>${esc(row.pageName||'—')}</b><br><span class="muted mono">${esc(row.pageId||'—')}</span></td>
      <td>${ready?pill('ADVERTISE granted','ok'):pill('No ADVERTISE task','warn')}<br><span class="muted">${esc(tasks.join(', ')||'No page tasks')}</span></td>
      <td><span class="muted">${esc(perms.join(', ')||'—')}</span></td>
      <td>${ads.length?ads.map(a=>`<div><b>${esc(a.name||a.id||'Ad account')}</b> <span class="mono">${esc(a.id||'')}</span></div>`).join(''):'<span class="muted">None returned</span>'}</td>
      <td>${row.status==='CONNECTED'?pill('Connected','ok'):pill(row.status,'bad')}</td>
      <td>${dt(row.updatedAt)}<br><span class="muted">Validated ${dt(row.lastValidatedAt)}</span></td>
      </tr>`;
    }).join('')||'<tr><td colspan="8" class="empty">No Instagram accounts connected yet.</td></tr>'}</tbody></table></div></div>` };
  }

  if (active === 'meta') {
    const metaConfigured = Boolean(process.env.META_APP_ID && process.env.META_APP_SECRET && process.env.META_REDIRECT_URI && process.env.ADMIN_SECRET_ENCRYPTION_KEY);
    return { tabs:tabHtml, body:`<div class="grid eq"><div class="card"><div class="cardhead"><h2>Meta / Instagram Login</h2>${metaConfigured?pill('Configured','ok'):pill('Needs setup','warn')}</div>
    <div class="notice"><b>VELIXEO uses official Meta OAuth.</b> Customers sign in on Meta's own page. Their password and OTP are never captured by VELIXEO. The server stores encrypted access tokens plus the Facebook Page, Instagram Professional account, page tasks and granted permissions.</div>
    <div class="field"><label>Required Railway variables</label><div class="mono">META_APP_ID<br>META_APP_SECRET<br>META_REDIRECT_URI<br>ADMIN_SECRET_ENCRYPTION_KEY</div></div>
    <div class="field"><label>Current redirect URI</label><div class="mono">${esc(process.env.META_REDIRECT_URI||'Not configured')}</div></div>
    <p class="muted">Use a Meta Business App with Instagram API (Facebook Login) and Marketing API. Request only the permissions needed for pages/Instagram and advertising. Instagram must be Professional and linked to a Facebook Page for this flow.</p></div>
    <div class="card"><h2>Admin fulfillment model</h2><ol style="line-height:2"><li>Customer connects Instagram in the app.</li><li>VELIXEO stores the authorized Instagram/Page IDs and encrypted tokens.</li><li>Customer selects one of their own posts and pays from Wallet.</li><li>The order shows the connected account and media ID in Admin.</li><li>Admin prepares the Meta campaign manually now; Marketing API draft creation can be enabled after Meta App review/Advanced Access.</li></ol><a class="btn ghost" href="${href('connections')}">View Instagram connections</a></div></div>` };
  }

  const [products,openOrders,activeOrders,completed,revenue] = await Promise.all([
    prisma.service.count({where:{category:ServiceCategory.PROMOTION}}),
    prisma.order.count({where:{category:ServiceCategory.PROMOTION,status:OrderStatus.PENDING}}),
    prisma.order.count({where:{category:ServiceCategory.PROMOTION,status:OrderStatus.PROCESSING}}),
    prisma.order.count({where:{category:ServiceCategory.PROMOTION,status:OrderStatus.COMPLETED}}),
    prisma.order.aggregate({where:{category:ServiceCategory.PROMOTION,status:{notIn:[OrderStatus.REFUNDED,OrderStatus.CANCELLED,OrderStatus.FAILED]}},_sum:{totalAmountAfn:true}}),
  ]);
  return { tabs:tabHtml, body:`<div class="card modulehero"><div class="cardhead"><div><h2>Instagram & Facebook Promotions</h2><p>Wallet-paid Meta advertising without collecting customer passwords or cards.</p></div></div><div class="kpis"><div><b>${products}</b><small>Products</small></div><div><b>${openOrders}</b><small>Pending</small></div><div><b>${activeOrders}</b><small>Processing / Active</small></div><div><b>${money(revenue._sum.totalAmountAfn||0n)}</b><small>Paid sales</small></div></div></div>
  <div class="grid eq"><div class="card"><h2>Version 1 workflow</h2><div class="notice">Package → targeting → Login with Instagram → select own post → Wallet payment → Telegram/admin invoice → manual Meta campaign → status/result back to customer.</div><a class="btn" href="${href('packages')}">Create promotion packages</a></div><div class="card"><h2>Fulfillment</h2><p class="muted">${completed} completed campaigns. Use Need information if the post/code is invalid, Active after publishing in Meta, and Refund if the campaign cannot be launched.</p><a class="btn ghost" href="${href('orders')}">Open promotion queue</a></div></div>` };
}

export function registerPromotionAdminRoutes(app: FastifyInstance, prisma: PrismaClient, resolveAdmin: AdminResolver) {
  app.post('/admin/v3/promotions/banner', async (request, reply) => {
    const admin = await requireAdmin(request, reply, resolveAdmin); if (!admin) return;
    const body = request.body as Body;
    try {
      const id=textValue(body,'id');
      const data={ placement:BannerPlacement.SERVICES_TOP, titleEn:textValue(body,'titleEn')||null, titleFa:textValue(body,'titleFa')||null,
        subtitleEn:textValue(body,'subtitleEn')||null, subtitleFa:textValue(body,'subtitleFa')||null, imageUrl:textValue(body,'imageUrl')||'',
        actionLabelEn:null, actionLabelFa:null, actionUrl:'velixeo://promotions', enabled:checked(body,'enabled'), sortOrder:intValue(body.sortOrder,10) };
      const saved=id?await prisma.banner.update({where:{id},data}):await prisma.banner.create({data});
      await audit(prisma,admin.id,id?'PROMOTION_BANNER_UPDATE':'PROMOTION_BANNER_CREATE','Banner',saved.id,'Promotions entry banner');
      return reply.code(303).redirect(href('banner','&msg=Promotions%20banner%20saved'));
    } catch(error){ return reply.code(303).redirect(href('banner',`&err=1&msg=${encodeURIComponent(error instanceof Error?error.message:'promotion_banner_failed')}`)); }
  });

  app.post('/admin/v3/promotions/product', async (request, reply) => {
    const admin=await requireAdmin(request,reply,resolveAdmin); if(!admin)return;
    const body=request.body as Body;
    try{
      const id=textValue(body,'id'), titleEn=textValue(body,'titleEn'), titleFa=textValue(body,'titleFa');
      if(!titleEn||!titleFa)throw new Error('English and Persian titles are required.');
      const slug=await uniqueSlug(prisma,textValue(body,'slug'),titleEn,id);
      let packagesRaw:unknown; try{packagesRaw=JSON.parse(textValue(body,'packagesJson')||'[]')}catch{throw new Error('Package data is invalid.')}
      const supportedObjectives=['ENGAGEMENT','PROFILE_VISITS','MESSAGES','WEBSITE_VISITS','AWARENESS'].filter(o=>checked(body,`objective_${o}`));
      const meta=parsePromotionMetadata({promotion:{version:1,platform:textValue(body,'platform')||'INSTAGRAM',deliveryMinHours:intValue(body.deliveryMinHours,1),deliveryMaxHours:intValue(body.deliveryMaxHours,12),iconUrl:textValue(body,'iconUrl'),instructionsFa:textValue(body,'instructionsFa'),instructionsEn:textValue(body,'instructionsEn'),supportedObjectives,requirePartnershipAdCode:checked(body,'requirePartnershipAdCode'),packages:packagesRaw}});
      if(!meta.packages.length)throw new Error('Add at least one valid promotion package.');
      const data={category:ServiceCategory.PROMOTION,slug,titleEn,titleFa,descriptionEn:textValue(body,'descriptionEn')||null,descriptionFa:textValue(body,'descriptionFa')||null,enabled:checked(body,'enabled'),featured:checked(body,'featured'),sortOrder:intValue(body.sortOrder,100),basePriceAfn:promotionMinPriceAfn(meta),priceUnit:1,minQty:1,maxQty:1,metadata:promotionMetadataJson(meta)};
      const service=id?await prisma.service.update({where:{id},data}):await prisma.service.create({data});
      await audit(prisma,admin.id,id?'PROMOTION_PRODUCT_UPDATE':'PROMOTION_PRODUCT_CREATE','Service',service.id,`${service.titleEn}: ${meta.packages.length} packages`);
      return reply.code(303).redirect(href('packages',`&edit=${service.id}&msg=Promotion%20product%20saved`));
    }catch(error){return reply.code(303).redirect(href('packages',`&err=1&msg=${encodeURIComponent(error instanceof Error?error.message:'promotion_product_failed')}`));}
  });

  app.post('/admin/v3/promotions/order-status', async (request, reply) => {
    const admin=await requireAdmin(request,reply,resolveAdmin);if(!admin)return;
    const body=request.body as Body, orderId=textValue(body,'orderId'), action=textValue(body,'action').toUpperCase();
    const messageEn=textValue(body,'messageEn'),messageFa=textValue(body,'messageFa');
    try{
      const current=await prisma.order.findFirst({where:{id:orderId,category:ServiceCategory.PROMOTION},include:{service:true}});
      if(!current)throw new Error('Order not found');
      let updated=current;
      if(action==='REFUND'){
        updated=await refundOrder(prisma,current.id,messageEn||messageFa||'Promotion could not be launched');
        try{await sendAdminRefundAlert(prisma,updated.id,messageEn||messageFa||'Promotion refunded by admin')}catch{}
      }else{
        const state=['REVIEWING_CODE','NEED_INFORMATION','READY_TO_LAUNCH','ACTIVE','COMPLETED'].includes(action)?action:'REVIEWING_CODE';
        const status=state==='COMPLETED'?OrderStatus.COMPLETED:(state==='ACTIVE'||state==='READY_TO_LAUNCH'||state==='REVIEWING_CODE')?OrderStatus.PROCESSING:OrderStatus.PENDING;
        const output=obj(current.output);
        updated=await prisma.order.update({where:{id:current.id},data:{status,completedAt:state==='COMPLETED'?new Date():null,output:{...output,promotionState:state,adminMessageEn:messageEn||null,adminMessageFa:messageFa||null,metaCampaignId:textValue(body,'metaCampaignId')||null,metaAdId:textValue(body,'metaAdId')||null,resultSummaryEn:textValue(body,'resultSummaryEn')||null,resultSummaryFa:textValue(body,'resultSummaryFa')||null,adminUpdatedAt:new Date().toISOString()} as Prisma.InputJsonValue},include:{service:true}});
      }
      const state=action==='REFUND'?'REFUNDED':action;
      const notify=state==='ACTIVE'?{titleEn:'Your promotion is active',titleFa:'تبلیغ شما فعال شد',bodyEn:messageEn||'Your Meta promotion is now active.',bodyFa:messageFa||'تبلیغ متای شما اکنون فعال است.'}:state==='COMPLETED'?{titleEn:'Promotion completed',titleFa:'تبلیغ تکمیل شد',bodyEn:messageEn||'Your promotion campaign has completed.',bodyFa:messageFa||'کمپین تبلیغاتی شما تکمیل شد.'}:state==='NEED_INFORMATION'?{titleEn:'Promotion needs information',titleFa:'اطلاعات تبلیغ نیاز به اصلاح دارد',bodyEn:messageEn||'Please review the post link or partnership ad permission.',bodyFa:messageFa||'لطفاً لینک پست یا اجازه تبلیغ را بررسی و اصلاح کنید.'}:state==='REFUNDED'?{titleEn:'Promotion refunded',titleFa:'مبلغ تبلیغ برگشت داده شد',bodyEn:messageEn||'The campaign could not be launched and your wallet was refunded.',bodyFa:messageFa||'کمپین قابل اجرا نبود و مبلغ به کیف پول شما برگشت داده شد.'}:{titleEn:'Promotion is being prepared',titleFa:'تبلیغ در حال آماده‌سازی است',bodyEn:messageEn||'Our team is reviewing and preparing your Meta campaign.',bodyFa:messageFa||'تیم ما در حال بررسی و آماده‌سازی کمپین متای شما است.'};
      try{await publishUserNotification(prisma,updated.userId,{type:NotificationType.PROMOTION,priority:NotificationPriority.HIGH,...notify,actionRoute:'orders',actionEntityId:updated.id,actionLabelEn:'View order',actionLabelFa:'مشاهده سفارش'})}catch{}
      await prisma.orderActionLog.create({data:{orderId:updated.id,action:'PROMOTION_ADMIN_STATUS',status:state,response:{adminId:admin.id,messageEn,messageFa} as Prisma.InputJsonValue}});
      await audit(prisma,admin.id,'PROMOTION_ORDER_STATUS','Order',updated.id,`Promotion order → ${state}`);
      return reply.code(303).redirect(href('orders','&msg=Promotion%20order%20updated'));
    }catch(error){return reply.code(303).redirect(href('orders',`&err=1&msg=${encodeURIComponent(error instanceof Error?error.message:'promotion_order_update_failed')}`));}
  });
}
