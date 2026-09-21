import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import {
  BannerPlacement,
  CouponDiscountType,
  NotificationAudience,
  NotificationPriority,
  NotificationType,
  OrderStatus,
  PaymentStatus,
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
import { encryptProviderSecret, providerSecretEncryptionConfigured } from './providerSecrets.js';
import { smmClientForProvider } from './smmPanelAdapter.js';
import { fiveSimClientForProvider } from './fiveSimAdapter.js';
import {
  blockPhonePermanently,
  getAccountControl,
  permanentPhoneBlockDetails,
  restoreUserAccess,
  softDeleteUserAccount,
  suspendUserPermanently,
  suspendUserTemporarily,
  unblockPhone,
} from './accountControl.js';
import {
  referralAdminSnapshot,
  saveReferralSettings,
} from './referralRoutes.js';
import { dispatchNotificationPush, firebasePushConfigured, publishUserNotification } from './pushNotifications.js';
import {
  convertSocialPriceToAfn,
  getSocialProviderSyncConfig,
  socialRouteSaleRateAfn,
  syncSocialProviderCatalog,
} from './socialSync.js';

type AdminIdentity = { id: string; fullName: string | null; email: string | null; phone: string | null };
type AdminResolver = (request: FastifyRequest) => Promise<AdminIdentity | null>;
type Body = Record<string, unknown>;
type Section = 'dashboard'|'users'|'referrals'|'social'|'virtual'|'premium'|'topup'|'accounts'|'promotions'|'payments'|'orders'|'coupons'|'banners'|'notifications'|'support'|'settings'|'audit';
type SocialCategory = { slug:string; titleEn:string; titleFa:string; platform:string; descriptionEn:string; descriptionFa:string; sortOrder:number; enabled:boolean };

const e = (v: unknown) => String(v ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#39;');
const t = (b: Body, key: string) => String(b[key] ?? '').trim();
const c = (b: Body, key: string) => ['on','true','1'].includes(String(b[key] ?? ''));
const i = (v: unknown, fallback=0) => { const n=Number.parseInt(String(v ?? ''),10); return Number.isFinite(n)?n:fallback; };
const money = (v: bigint|number|string|null|undefined) => `${Number(v ?? 0).toLocaleString('en-US')} AFN`;
const dt = (v: Date|string|null|undefined) => v ? new Date(v).toLocaleString('en-US',{dateStyle:'medium',timeStyle:'short'}) : '—';
const sid = (v:string) => v.slice(0,8).toUpperCase();
const href = (section:Section, extra='') => `/admin/v3?section=${section}${extra}`;
const jsonObj = (v: Prisma.JsonValue|null|undefined):Record<string,unknown> => v && typeof v==='object' && !Array.isArray(v) ? v as Record<string,unknown> : {};
const brandMark = `<svg viewBox="0 0 96 96" aria-label="VELIXEO" role="img"><defs><linearGradient id="vmg" x1="10" y1="8" x2="79" y2="88" gradientUnits="userSpaceOnUse"><stop stop-color="#55D0FF"/><stop offset=".48" stop-color="#168BFF"/><stop offset="1" stop-color="#0753D9"/></linearGradient><linearGradient id="vmi" x1="52" y1="14" x2="78" y2="61" gradientUnits="userSpaceOnUse"><stop stop-color="#5CD4FF"/><stop offset="1" stop-color="#1269EC"/></linearGradient></defs><path d="M19 18c-4 0-7 2-8.7 5.2-1.7 3.2-1.6 6.8.3 10l27.2 47.2c2.3 4 5.9 6.3 10.1 6.3 3.1 0 5.9-1.2 8.2-3.5l18.1-18.2-12.8-18.4-12.2 12.1L27.8 22.5C25.8 19.5 22.9 18 19 18Z" fill="url(#vmg)"/><path d="M21.5 18.2h15.4l27.4 39.6-14.9 15.1-28-48.4c-1.3-2.2-1.2-4.4.1-6.3Z" fill="#176CE5" opacity=".56"/><path d="M50 59l8.5-8.5 5.8 7.3-10 10.1Z" fill="#fff" opacity=".93"/><circle cx="76" cy="23" r="9.4" fill="url(#vmi)"/><path d="M67.5 43.5c0-5.2 4.1-9.2 9.2-9.2s9.1 4 9.1 9.2c0 3-1.5 5.2-3.8 7.5l-6.9 7-7.6-7.9v-6.6Z" fill="url(#vmi)"/></svg>`;

function ico(name:string){
 const p:Record<string,string>={
 dashboard:'<path d="M4 4h6v6H4zM14 4h6v6h-6zM4 14h6v6H4zM14 14h6v6h-6z"/>',
 users:'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
 service:'<path d="M12 2l2.3 4.7 5.2.8-3.8 3.7.9 5.2-4.6-2.4-4.6 2.4.9-5.2-3.8-3.7 5.2-.8z"/>',
 phone:'<rect x="5" y="2" width="14" height="20" rx="3"/><path d="M9 18h6M9 6h6"/>',
 wallet:'<path d="M3 6h16a2 2 0 0 1 2 2v10H3a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h14M16 12h5"/>',
 orders:'<path d="M6 2h12l2 5H4zM5 7h14v15H5zM9 11h6M9 15h6"/>',
 coupon:'<path d="M3 7a2 2 0 0 0 0 4v6h18v-6a2 2 0 0 0 0-4V4H3zM12 4v13"/>',
 banner:'<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 15l5-5 4 4 3-3 6 6"/>',
 bell:'<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
 support:'<circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 4.4 1.6c-.8.8-1.9 1.3-1.9 2.9M12 17h.01"/>',
 settings:'<circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.4 1a7 7 0 0 0-1.8-1L14.4 3h-4.8l-.4 3.1a7 7 0 0 0-1.8 1l-2.4-1-2 3.4L5.1 11a7 7 0 0 0 0 2L3 14.5l2 3.4 2.4-1a7 7 0 0 0 1.8 1l.4 3.1h4.8l.4-3.1a7 7 0 0 0 1.8-1l2.4 1 2-3.4-2.1-1.5a7 7 0 0 0 .1-1z"/>',
 audit:'<path d="M4 4h16v16H4zM8 9h8M8 13h5M8 17h3"/>',
 search:'<circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/>',
 social:'<path d="M7 12a5 5 0 0 0 10 0M12 2v4M4.9 4.9l2.8 2.8M19.1 4.9l-2.8 2.8M3 12h4M17 12h4"/>',
 };
 return `<svg class="ico" viewBox="0 0 24 24" aria-hidden="true">${p[name]||p.service}</svg>`;
}

const meta:Record<Section,[string,string]>={
 dashboard:['Dashboard','Business overview and today’s performance'],
 users:['Users','Accounts, access and wallet management'], referrals:['Invite Friends','Referral links, rewards and invited-user tracking'], social:['Social Media','Providers, catalog, categories, pricing and routing'],
 virtual:['Virtual Number & SMS','Providers, services, countries, pricing and SMS orders'], premium:['Premium Subscriptions','Products, providers and subscription orders'],
 topup:['Mobile Top-up','Operators, products, providers and top-up orders'], accounts:['Digital Accounts','Digital products, stock and delivery'], promotions:['Promotions','Campaign services and promotion orders'],
 payments:['Payments & Wallet','Gateways, transactions, user wallets and refunds'], orders:['Orders','All customer orders across VELIXEO'], coupons:['Coupons','Discount rules and coupon usage'],
 banners:['Banners & Advertising','App banners, placements and CTA routes'], notifications:['Notifications','In-app announcements and user messages'], support:['Support','Tickets, conversations and resolution'],
 settings:['Settings','Exchange rates, languages, security and system status'], audit:['Audit Log','Trace all administrative changes and sensitive actions'],
};

function pill(label:string,kind=''){return `<span class="pill ${kind}">${e(label)}</span>`}
function state(s:string){const ok=['ACTIVE','COMPLETED','PAID','RESOLVED','SUCCESS'];const bad=['FAILED','SUSPENDED','CANCELLED','REFUNDED','CLOSED'];const warn=['PENDING','PROCESSING','AWAITING_SMS','PARTIAL','PENDING_USER','PENDING_ADMIN'];return pill(s,ok.includes(s)?'ok':bad.includes(s)?'bad':warn.includes(s)?'warn':'info')}
function nav(section:Section,label:string,icon:string,active:Section){return `<a class="nav ${active===section?'active':''}" href="${href(section)}">${ico(icon)}<span>${e(label)}</span></a>`}

const css=`
:root{--blue:#1687f8;--cyan:#31b5ff;--nav:#0b223f;--nav2:#071b32;--bg:#f5f8fc;--card:#fff;--text:#12243a;--muted:#718399;--line:#e3eaf3;--green:#18a875;--red:#e65362;--amber:#f2a12b;--purple:#765ff3;--shadow:0 7px 24px rgba(25,67,110,.055)}*{box-sizing:border-box}html,body{margin:0;min-height:100%;font-family:Inter,ui-sans-serif,-apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif;background:var(--bg);color:var(--text)}body{direction:ltr}a{color:inherit}button,input,select,textarea{font:inherit}.ico{width:18px;height:18px;fill:none;stroke:currentColor;stroke-width:1.85;stroke-linecap:round;stroke-linejoin:round}.layout{display:grid;grid-template-columns:244px minmax(0,1fr);min-height:100vh}.side{background:linear-gradient(180deg,var(--nav),var(--nav2));color:#fff;height:100vh;position:sticky;top:0;overflow:auto;padding:19px 13px}.brand{display:flex;align-items:center;gap:10px;padding:2px 8px 20px;border-bottom:1px solid rgba(255,255,255,.08);margin-bottom:12px}.vlogo{width:44px;height:44px;display:grid;place-items:center;filter:drop-shadow(0 8px 14px rgba(20,137,255,.22))}.vlogo svg{width:42px;height:42px;display:block}.brand b{font-size:18px;letter-spacing:.8px}.brand small{display:block;color:#86a6c5;font-size:9.5px;margin-top:2px}.cap{font-size:9.5px;letter-spacing:.8px;text-transform:uppercase;color:#688aaa;padding:10px 11px 4px}.nav{display:flex;align-items:center;gap:10px;text-decoration:none;color:#cad8e7;padding:10px 11px;border-radius:9px;margin:3px 0;font-size:12px}.nav:hover{background:rgba(255,255,255,.06);color:#fff}.nav.active{background:linear-gradient(135deg,#31a8ff,#1687f8);color:#fff;box-shadow:0 8px 22px rgba(20,132,238,.22)}.subnav{padding-left:18px;border-left:1px solid rgba(255,255,255,.09);margin-left:18px}.subnav .nav{font-size:10.8px;padding:7px 9px}.logout{width:100%;margin-top:14px;background:transparent;border:1px solid rgba(255,255,255,.1);color:#ffbdc6;border-radius:9px;padding:9px;cursor:pointer}.main{min-width:0;padding:0 17px 18px}.topbar{height:70px;display:grid;grid-template-columns:minmax(250px,1fr) auto;align-items:center;gap:16px;position:sticky;top:0;z-index:5;background:rgba(245,248,252,.96);backdrop-filter:blur(8px)}.search{max-width:760px;height:41px;background:#fff;border:1px solid var(--line);border-radius:9px;display:flex;align-items:center;gap:9px;padding:0 12px;color:#91a0b1}.search input{width:100%;border:0;outline:0;background:transparent;color:var(--text)}.admin{display:flex;align-items:center;gap:10px}.notif{width:38px;height:38px;border-radius:50%;background:#fff;border:1px solid var(--line);display:grid;place-items:center;position:relative}.notif:after{content:'';position:absolute;width:7px;height:7px;border-radius:50%;background:#f54b61;border:2px solid #fff;top:3px;right:4px}.avatar{width:38px;height:38px;border-radius:50%;background:linear-gradient(145deg,#0f3d6d,#1687f8);color:#fff;display:grid;place-items:center;font-weight:900}.admin b{font-size:11px}.admin small{display:block;color:var(--muted);font-size:9px;margin-top:2px}.head{display:flex;justify-content:space-between;align-items:flex-end;gap:14px;margin:7px 0 15px}.head h1{font-size:22px;margin:0 0 5px}.head p{font-size:11px;color:var(--muted);margin:0}.crumb{font-size:10px;color:#96a4b3}.flash{padding:10px 12px;border-radius:9px;margin-bottom:12px;font-size:11px;background:#eaf8f2;border:1px solid #ccecdf;color:#0c855a}.flash.err{background:#fff0f2;border-color:#ffd7dd;color:#b83c4c}.stats{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:12px;margin-bottom:12px}.stat,.card{background:#fff;border:1px solid var(--line);border-radius:13px;box-shadow:var(--shadow)}.stat{display:flex;gap:12px;align-items:center;padding:15px}.sicon{width:43px;height:43px;border-radius:11px;display:grid;place-items:center;background:#eaf5ff;color:#1687f8}.stat:nth-child(2) .sicon{background:#fff0e4;color:#ef8d2c}.stat:nth-child(3) .sicon{background:#e7f8ef;color:#17a772}.stat:nth-child(4) .sicon{background:#fff5de;color:#d99b14}.stat small{font-size:10px;color:var(--muted)}.stat strong{display:block;font-size:20px;margin-top:4px}.delta{font-size:9px;color:var(--green);margin-top:3px}.card{padding:15px;margin-bottom:12px}.cardhead{display:flex;justify-content:space-between;align-items:center;gap:10px;margin-bottom:12px}.cardhead h2,.cardhead h3{font-size:13px;margin:0}.muted{font-size:10px;color:var(--muted)}.link{font-size:10px;color:var(--blue);text-decoration:none}.grid{display:grid;grid-template-columns:minmax(0,1.75fr) minmax(310px,.85fr);gap:12px}.grid.eq{grid-template-columns:1fr 1fr}.chart{width:100%;height:215px}.chart-grid line{stroke:#edf2f7}.chart-line{fill:none;stroke:#1687f8;stroke-width:3;stroke-linecap:round;stroke-linejoin:round}.chart-area{fill:url(#area)}.donutgrid{display:grid;grid-template-columns:145px 1fr;gap:15px;align-items:center}.donut{width:140px;height:140px;border-radius:50%;position:relative;display:grid;place-items:center}.donut:after{content:'';position:absolute;inset:27px;background:#fff;border-radius:50%}.donuttext{z-index:1;text-align:center;color:var(--muted);font-size:9px}.donuttext b{display:block;color:var(--text);font-size:17px;margin:2px}.legend{display:grid;gap:7px}.legendrow{display:grid;grid-template-columns:9px 1fr auto;gap:7px;align-items:center;font-size:9.5px}.dot{width:8px;height:8px;border-radius:50%}.tablewrap{overflow:auto}.table{width:100%;border-collapse:collapse;min-width:760px}.table th,.table td{padding:9px 8px;border-bottom:1px solid #edf2f7;text-align:left;font-size:10px;vertical-align:middle}.table th{color:#8293a6;font-weight:700;background:#fbfcfe}.table tr:last-child td{border-bottom:0}.table td b{font-size:10.5px}.pill{display:inline-flex;padding:4px 7px;border-radius:999px;background:#edf3f8;color:#5d7187;font-size:9px;white-space:nowrap}.pill.ok{background:#e4f8ef;color:#0f845b}.pill.warn{background:#fff1dc;color:#a76a09}.pill.bad{background:#ffecef;color:#b63d4d}.pill.info{background:#e7f2ff;color:#147bd6}.provider{display:grid;grid-template-columns:34px 1fr auto auto;gap:8px;align-items:center;padding:9px 0;border-bottom:1px solid #edf2f7}.provider:last-child{border-bottom:0}.plogo{width:31px;height:31px;border-radius:8px;background:linear-gradient(135deg,#36b8ff,#1687f8);display:grid;place-items:center;color:#fff;font-weight:900}.provider b{font-size:10px}.provider small{display:block;color:var(--muted);font-size:8.5px;margin-top:2px}.money{font-weight:900;white-space:nowrap}.tabs{display:flex;gap:6px;flex-wrap:wrap;margin:-2px 0 13px}.tab{font-size:10px;padding:7px 10px;border:1px solid var(--line);background:#fff;color:#5f7287;border-radius:8px;text-decoration:none}.tab.active{background:#1687f8;color:#fff;border-color:#1687f8}.forms{display:grid;grid-template-columns:1fr 1fr;gap:10px}.field{margin-bottom:9px}.field label{display:block;font-size:9.5px;color:#687c91;margin-bottom:4px}.field input,.field select,.field textarea{width:100%;border:1px solid var(--line);border-radius:8px;background:#fff;padding:8px 9px;color:var(--text);outline:0}.field input,.field select{height:38px}.field textarea{min-height:70px;resize:vertical}.field input:focus,.field select:focus,.field textarea:focus{border-color:#74bcfb;box-shadow:0 0 0 3px rgba(22,135,248,.07)}.check{display:flex;gap:7px;align-items:center;font-size:10px;margin:4px 0 10px}.check input{width:16px;height:16px}.btn{display:inline-flex;align-items:center;justify-content:center;border:0;border-radius:8px;padding:8px 11px;background:linear-gradient(135deg,#31b1ff,#1687f8);color:#fff;font-size:9.5px;font-weight:800;cursor:pointer;text-decoration:none}.btn.ghost{background:#fff;border:1px solid var(--line);color:#566b82}.btn.danger{background:#fff0f2;border:1px solid #ffd6dc;color:#bc4050}.actions{display:flex;gap:6px;flex-wrap:wrap}.mono{font-family:ui-monospace,SFMono-Regular,Consolas,monospace}.empty{padding:28px;text-align:center;color:var(--muted);font-size:10px}.modulehero{background:linear-gradient(135deg,#0b75cf,#20a8fa);color:#fff;border:0;overflow:hidden;position:relative}.modulehero:after{content:'';position:absolute;width:260px;height:260px;border:48px solid rgba(255,255,255,.07);border-radius:50%;right:-100px;top:-140px}.modulehero p{color:#def3ff;font-size:10px;margin:5px 0}.kpis{display:flex;gap:24px;position:relative;z-index:1;margin-top:14px}.kpis b{display:block;font-size:19px}.kpis small{font-size:8.5px;color:#dff3ff}.notice{background:#f7fbff;border:1px solid var(--line);border-radius:9px;padding:10px;font-size:9.5px;color:#5f7287}.nhero{background:radial-gradient(circle at 85% 15%,rgba(84,205,255,.33),transparent 30%),linear-gradient(135deg,#072a52,#0e69cf 57%,#20a9ff);color:#fff;border:0;overflow:hidden;position:relative}.nhero .brandorb{width:58px;height:58px;border-radius:18px;background:rgba(255,255,255,.13);display:grid;place-items:center;border:1px solid rgba(255,255,255,.18)}.nhero .brandorb svg{width:46px;height:46px}.nhero h2{font-size:18px;margin:0}.nhero p{color:#d9efff;font-size:10px;line-height:1.5;margin:5px 0 0}.nmetrics{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:9px;margin-top:15px}.nmetric{background:rgba(255,255,255,.1);border:1px solid rgba(255,255,255,.14);border-radius:11px;padding:10px}.nmetric small{font-size:8.5px;color:#d7edff}.nmetric b{display:block;font-size:18px;margin-top:3px}.nrow{display:grid;grid-template-columns:38px 1fr auto;gap:10px;align-items:start;padding:11px 0;border-bottom:1px solid #edf2f7}.nrow:last-child{border-bottom:0}.nicon{width:36px;height:36px;border-radius:11px;background:linear-gradient(135deg,#e6f5ff,#d8ecff);display:grid;place-items:center;color:#1687f8}.nicon.order{background:#e9f3ff;color:#167ee8}.nicon.wallet{background:#e8faf2;color:#118960}.nicon.support{background:#f0ebff;color:#6f50dc}.nicon.promotion{background:#fff0f6;color:#dc4f8b}.nicon.account{background:#fff4e5;color:#c47a15}.nrow b{font-size:10.5px}.nrow small{display:block;color:var(--muted);font-size:8.7px;margin-top:3px;line-height:1.4}.nmeta{display:flex;gap:5px;justify-content:flex-end;flex-wrap:wrap}.preview-phone{border-radius:24px;background:#071b32;padding:9px;box-shadow:0 18px 50px rgba(13,52,91,.16)}.preview-screen{border-radius:18px;background:linear-gradient(180deg,#f9fbfe,#eef5fb);padding:13px;min-height:185px}.preview-note{background:#fff;border:1px solid #dfe8f1;border-radius:15px;padding:12px;box-shadow:0 8px 24px rgba(29,75,118,.08)}.preview-note .mark{width:32px;height:32px;border-radius:10px;background:linear-gradient(135deg,#50c8ff,#1687f8);display:grid;place-items:center}.preview-note .mark svg{width:26px;height:26px}.routehint{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0 11px}.routehint span{font-size:8.5px;background:#edf5ff;color:#176fac;border-radius:999px;padding:4px 7px}.order-filterbar{display:grid;grid-template-columns:minmax(220px,1.5fr) minmax(180px,.8fr) auto auto;gap:8px;align-items:center}.order-filterbar input,.order-filterbar select{height:39px;border:1px solid var(--line);border-radius:9px;background:#fff;padding:0 11px;outline:0;color:var(--text)}.order-filterbar input:focus,.order-filterbar select:focus{border-color:#69b7fb;box-shadow:0 0 0 3px rgba(22,135,248,.07)}.order-kinds{display:flex;gap:6px;flex-wrap:wrap;margin-top:10px}.order-kind{padding:6px 10px;border-radius:999px;border:1px solid var(--line);background:#fff;text-decoration:none;color:#667b90;font-size:9.5px;font-weight:800}.order-kind.active{background:#e7f2ff;border-color:#afd6fb;color:#1178d6}.order-status-tabs{display:flex;gap:7px;overflow:auto;padding:2px 1px 9px;margin-bottom:5px;scrollbar-width:thin}.order-status-tab{min-width:max-content;display:flex;align-items:center;gap:7px;padding:9px 11px;border:1px solid var(--line);border-radius:10px;background:#fff;text-decoration:none;color:#5f7287;font-size:9.5px;font-weight:800;box-shadow:0 3px 10px rgba(21,63,103,.025)}.order-status-tab b{font-size:10px;padding:2px 6px;border-radius:999px;background:#edf3f8;color:#5f7185}.order-status-tab.active{background:#1687f8;border-color:#1687f8;color:#fff;box-shadow:0 8px 20px rgba(22,135,248,.18)}.order-status-tab.active b{background:rgba(255,255,255,.2);color:#fff}.order-status-tab.error b{background:#ffecef;color:#bc4050}.order-status-tab.complete b{background:#e4f8ef;color:#0d855a}.order-status-tab.pending b{background:#e7f2ff;color:#147bd6}.order-status-tab.processing b{background:#fff1dc;color:#a76a09}.order-status-tab.cancel b{background:#fff0f2;color:#bc4050}.order-status-tab.partial b{background:#f2edff;color:#765ff3}.order-status-tab.refund b{background:#edf3f8;color:#526b84}.order-status-tab.active b{background:rgba(255,255,255,.2);color:#fff}.order-id b{display:block;font-size:11px}.order-id small{display:block;margin-top:3px}.provider-id{font-weight:900;color:#0d72c8}.order-link{max-width:270px}.order-link a{display:block;color:#1178d6;text-decoration:none;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:260px}.order-link small{display:block;margin-top:4px}.qtygrid{display:grid;grid-template-columns:repeat(3,max-content);gap:3px 9px;font-size:9.3px}.qtygrid span{color:var(--muted)}.qtygrid b{color:var(--text)}.order-user b{display:block}.order-user small{display:block;margin-top:2px}.orders-table{min-width:1540px}.orders-table td{vertical-align:top;padding-top:11px;padding-bottom:11px}.pager{display:flex;align-items:center;justify-content:flex-end;gap:7px;margin-top:11px}.pager a,.pager span{padding:6px 9px;border-radius:8px;border:1px solid var(--line);background:#fff;text-decoration:none;font-size:9px;color:#60758b}.pager .active{background:#1687f8;border-color:#1687f8;color:#fff}.orders-summary{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.footer{display:flex;justify-content:space-between;color:#95a3b2;font-size:8.5px;padding:10px 3px 3px}@media(max-width:1080px){.order-filterbar{grid-template-columns:1fr 1fr auto}.order-filterbar .reset{grid-column:auto}.layout{grid-template-columns:215px minmax(0,1fr)}.stats{grid-template-columns:1fr 1fr}.grid,.grid.eq{grid-template-columns:1fr}}@media(max-width:760px){.order-filterbar{grid-template-columns:1fr}.order-filterbar .btn{width:100%}.layout{display:block}.side{position:relative;height:auto}.main{padding:0 10px 15px}.topbar{position:relative;grid-template-columns:1fr;height:auto;padding:10px 0}.admin{display:none}.stats{grid-template-columns:1fr 1fr}.forms{grid-template-columns:1fr}.donutgrid{grid-template-columns:1fr}.donut{margin:auto}.head{align-items:flex-start}}@media(max-width:480px){.stats{grid-template-columns:1fr}}
`;

function shell(a:AdminIdentity,section:Section,body:string,tabs='',msg='',err=false){const [title,sub]=meta[section];return `<!doctype html><html lang="en" dir="ltr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${e(title)} — VELIXEO Admin</title><style>${css}</style></head><body><div class="layout"><aside class="side"><div class="brand"><div class="vlogo">${brandMark}</div><div><b>VELIXEO Admin</b><small>Manage Today, Grow Tomorrow</small></div></div>${nav('dashboard','Dashboard','dashboard',section)}${nav('users','Users','users',section)}${nav('referrals','Invite Friends','users',section)}<div class="cap">Services</div><div class="subnav">${nav('social','Social Media','social',section)}${nav('virtual','Virtual Number & SMS','phone',section)}${nav('premium','Premium Subscriptions','service',section)}${nav('topup','Mobile Top-up','phone',section)}${nav('accounts','Digital Accounts','service',section)}${nav('promotions','Promotions','banner',section)}</div><div class="cap">Management</div>${nav('payments','Payments & Wallet','wallet',section)}${nav('orders','Orders','orders',section)}${nav('coupons','Coupons','coupon',section)}${nav('banners','Banners & Advertising','banner',section)}${nav('notifications','Notifications','bell',section)}${nav('support','Support','support',section)}${nav('settings','Settings','settings',section)}${nav('audit','Audit Log','audit',section)}<form method="post" action="/admin/logout"><button class="logout">Sign out</button></form></aside><main class="main"><header class="topbar"><form class="search" method="get" action="/admin/v3"><input type="hidden" name="section" value="${section}">${ico('search')}<input name="q" placeholder="Search in admin panel..." autocomplete="off"></form><div class="admin"><div class="notif">${ico('bell')}</div><div><b>${e(a.fullName||a.email||'Admin')}</b><small>System Administrator</small></div><div class="avatar">${e((a.fullName||'V').charAt(0).toUpperCase())}</div></div></header><div class="head"><div><h1>${e(title)}</h1><p>${e(sub)}</p></div><div class="crumb">VELIXEO Admin / ${e(title)}</div></div>${tabs}${msg?`<div class="flash ${err?'err':''}">${e(msg)}</div>`:''}${body}<div class="footer"><span>VELIXEO Admin Panel · v1.0 · Built for a bigger future</span><span>Manage smarter. Grow without limits.</span></div></main></div></body></html>`}

async function needAdmin(req:FastifyRequest,rep:FastifyReply,resolve:AdminResolver){const a=await resolve(req);if(!a){rep.code(303).redirect('/admin/login');return null}return a}
async function audit(p:PrismaClient,a:string,action:string,type:string,id:string|null,summary:string,metadata?:Prisma.InputJsonValue){await p.adminAuditLog.create({data:{adminUserId:a,action,entityType:type,entityId:id,summary,metadata}})}
function qstate(req:FastifyRequest){const q=(req.query??{}) as Record<string,unknown>;const allowed=new Set<Section>(Object.keys(meta) as Section[]);const section=String(q.section||'dashboard') as Section;return {section:allowed.has(section)?section:'dashboard' as Section,tab:String(q.tab||'overview'),q:String(q.q||'').trim().slice(0,180),filter:String(q.filter||'all').trim().slice(0,40),status:String(q.status||'all').trim().slice(0,40),kind:String(q.kind||'all').trim().slice(0,40),page:Math.max(1,i(q.page,1)),edit:String(q.edit||''),route:String(q.route||''),provider:String(q.provider||''),ticket:String(q.ticket||''),msg:String(q.msg||''),err:String(q.err||'')==='1'}}
function tabbar(section:Section,current:string,items:[string,string][]){return `<div class="tabs">${items.map(([k,l])=>`<a class="tab ${k===current?'active':''}" href="${href(section,`&tab=${encodeURIComponent(k)}`)}">${e(l)}</a>`).join('')}</div>`}
function chart(values:number[]){const d=values.length?values:[0];const max=Math.max(...d,1);const pts=d.map((v,n)=>`${20+n*660/Math.max(1,d.length-1)},${190-v/max*150}`).join(' ');return `<svg class="chart" viewBox="0 0 700 215" preserveAspectRatio="none"><defs><linearGradient id="area" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#1687f8" stop-opacity=".22"/><stop offset="1" stop-color="#1687f8" stop-opacity="0"/></linearGradient></defs><g class="chart-grid">${[45,85,125,165,205].map(y=>`<line x1="20" x2="680" y1="${y}" y2="${y}"/>`).join('')}</g><polygon class="chart-area" points="${pts} 680,205 20,205"/><polyline class="chart-line" points="${pts}"/></svg>`}

async function providerCheck(p:any){if(!p.enabled)return{status:'Disabled',class:'bad',balance:'—'};if(!p.secretCiphertext)return{status:'API key needed',class:'warn',balance:'—'};try{if(p.kind===ProviderKind.SOCIAL){const b=await smmClientForProvider(p).balance();return{status:'Active',class:'ok',balance:`${b.balance} ${b.currency||''}`.trim()}}if(p.kind===ProviderKind.VIRTUAL_NUMBER){const b=await fiveSimClientForProvider(p).profile();return{status:'Active',class:'ok',balance:String(b.balance)}}return{status:'Active',class:'ok',balance:'Configured'}}catch{return{status:'Connection error',class:'warn',balance:'—'}}}

async function dashboard(p:PrismaClient){const now=new Date(),start=new Date(now);start.setUTCHours(0,0,0,0);const from=new Date(now.getTime()-29*86400000);const valid={notIn:[OrderStatus.CANCELLED,OrderStatus.FAILED,OrderStatus.REFUNDED]};const [users,ordersToday,sum,recent,range,providers]=await Promise.all([p.user.count(),p.order.count({where:{createdAt:{gte:start},status:valid}}),p.order.aggregate({where:{createdAt:{gte:start},status:valid},_sum:{totalAmountAfn:true,providerCostAfn:true}}),p.order.findMany({include:{user:true,service:true},orderBy:{createdAt:'desc'},take:5}),p.order.findMany({where:{createdAt:{gte:from},status:valid},select:{createdAt:true,totalAmountAfn:true,category:true}}),p.provider.findMany({orderBy:[{enabled:'desc'},{priority:'asc'}],take:5})]);const sales=sum._sum.totalAmountAfn??0n,cost=sum._sum.providerCostAfn??0n;const days=Array.from({length:30},(_,x)=>new Date(from.getTime()+x*86400000).toISOString().slice(0,10));const dm=new Map(days.map(x=>[x,0]));const cm=new Map<string,number>();for(const o of range){const k=o.createdAt.toISOString().slice(0,10);dm.set(k,(dm.get(k)||0)+Number(o.totalAmountAfn));cm.set(o.category,(cm.get(o.category)||0)+Number(o.totalAmountAfn))}const total=[...cm.values()].reduce((a,b)=>a+b,0)||1;const colors:Record<string,string>={SOCIAL:'#1687f8',VIRTUAL_NUMBER:'#14b98b',PREMIUM:'#51ce7d',MOBILE_TOPUP:'#f1a126',DIGITAL_ACCOUNT:'#765ff3',PROMOTION:'#e95976'};let acc=0;const grad=[...cm.entries()].map(([k,v])=>{const s=acc;acc+=v/total*100;return `${colors[k]||'#a2afbd'} ${s}% ${acc}%`}).join(',')||'#edf2f7 0 100%';const ph=await Promise.all(providers.map(async x=>({p:x,h:await providerCheck(x)})));return `<div class="stats"><div class="stat"><div class="sicon">${ico('users')}</div><div><small>Total Users</small><strong>${users.toLocaleString('en-US')}</strong><div class="delta">Live database</div></div></div><div class="stat"><div class="sicon">${ico('orders')}</div><div><small>Orders Today</small><strong>${ordersToday.toLocaleString('en-US')}</strong><div class="delta">Today</div></div></div><div class="stat"><div class="sicon">${ico('wallet')}</div><div><small>Sales Today</small><strong>${money(sales)}</strong><div class="delta">Valid orders</div></div></div><div class="stat"><div class="sicon">${ico('dashboard')}</div><div><small>Net Profit</small><strong>${money(sales-cost)}</strong><div class="delta">Sales − provider cost</div></div></div></div><div class="grid"><div class="card"><div class="cardhead"><div><h2>Sales Overview</h2><span class="muted">Last 30 days</span></div><div class="actions">${pill('Daily','info')}${pill('Weekly')}${pill('Monthly')}</div></div>${chart([...dm.values()])}</div><div class="card"><div class="cardhead"><h2>Service Distribution</h2><span class="muted">Last 30 days</span></div><div class="donutgrid"><div class="donut" style="background:conic-gradient(${grad})"><div class="donuttext">Total Sales<b>${money([...dm.values()].reduce((a,b)=>a+b,0))}</b></div></div><div class="legend">${[...cm.entries()].sort((a,b)=>b[1]-a[1]).map(([k,v])=>`<div class="legendrow"><i class="dot" style="background:${colors[k]||'#a2afbd'}"></i><span>${e(k.replaceAll('_',' '))}</span><b>${Math.round(v/total*100)}%</b></div>`).join('')||'<span class="muted">No sales data yet.</span>'}</div></div></div></div><div class="grid"><div class="card"><div class="cardhead"><h2>Recent Orders</h2><a class="link" href="${href('orders')}">View all</a></div><div class="tablewrap"><table class="table"><thead><tr><th>#</th><th>User</th><th>Service</th><th>Amount</th><th>Status</th><th>Time</th></tr></thead><tbody>${recent.map(o=>`<tr><td>${sid(o.id)}</td><td>${e(o.user.fullName||o.user.email||o.user.phone||'—')}</td><td><b>${e(o.service?.titleEn||o.service?.titleFa||o.category)}</b></td><td class="money">${money(o.totalAmountAfn)}</td><td>${state(o.status)}</td><td>${dt(o.createdAt)}</td></tr>`).join('')||'<tr><td colspan="6" class="empty">No orders yet.</td></tr>'}</tbody></table></div></div><div class="card"><div class="cardhead"><h2>Provider Status</h2><a class="link" href="${href('social','&tab=providers')}">View all</a></div>${ph.map(({p,h})=>`<div class="provider"><div class="plogo">${e(p.name.charAt(0).toUpperCase())}</div><div><b>${e(p.name)}</b><small>${e(p.kind.replaceAll('_',' '))} Provider</small></div>${pill(h.status,h.class)}<b class="money">${e(h.balance)}</b></div>`).join('')||'<div class="empty">No providers configured.</div>'}</div></div>`}

async function usersPage(p:PrismaClient,q:string,edit:string){
 const where:Prisma.UserWhereInput=q?{OR:[
  {fullName:{contains:q,mode:'insensitive'}},
  {email:{contains:q,mode:'insensitive'}},
  {phone:{contains:q,mode:'insensitive'}}
 ]}:{};
 const [rows,total,selected]=await Promise.all([
  p.user.findMany({where,include:{wallet:true},orderBy:{createdAt:'desc'},take:120}),
  p.user.count({where}),
  edit?p.user.findUnique({where:{id:edit},include:{wallet:{include:{entries:{orderBy:{createdAt:'desc'},take:15}}}}}):Promise.resolve(null)
 ]);
 const control=selected?await getAccountControl(p,selected.id):null;
 const blocked=selected?.phone?await permanentPhoneBlockDetails(p,selected.phone):null;
 const accessLabel=control?.state??selected?.status??'ACTIVE';
 const accessInfo=control?.state==='TEMP_SUSPENDED'
   ? `Until ${e(control.until||'—')}`
   : control?.reason?e(control.reason):'';
 const blockedRows=await p.systemSetting.findMany({where:{category:'account-control',key:{startsWith:'account.blockedPhone.'}},orderBy:{updatedAt:'desc'},take:40});
 const blacklistCard=`<div class="card"><div class="cardhead"><div><h2>Permanent Phone Blacklist</h2><span class="muted">Independent from account deletion</span></div>${pill(`${blockedRows.length} recent`,'info')}</div><form method="post" action="/admin/v3/phone-blacklist"><input type="hidden" name="action" value="BLOCK"><div class="forms"><div class="field"><label>Phone number (international)</label><input name="phone" placeholder="+937XXXXXXXX" required></div><div class="field"><label>Reason</label><input name="reason" maxlength="300" placeholder="Why this phone is blocked"></div></div><button class="btn danger">Block phone permanently</button></form><div class="tablewrap" style="margin-top:12px"><table class="table"><thead><tr><th>Phone</th><th>Reason</th><th>Blocked at</th><th></th></tr></thead><tbody>${blockedRows.map(row=>{const v=jsonObj(row.value);return `<tr><td class="mono">${e(v.phone||'—')}</td><td>${e(v.reason||'—')}</td><td>${e(v.blockedAt||row.updatedAt.toISOString())}</td><td>${v.phone?`<form method="post" action="/admin/v3/phone-blacklist"><input type="hidden" name="action" value="UNBLOCK"><input type="hidden" name="phone" value="${e(v.phone)}"><button class="btn ghost">Unblock</button></form>`:''}</td></tr>`}).join('')||'<tr><td colspan="4" class="empty">No permanently blocked phone numbers.</td></tr>'}</tbody></table></div></div>`;
 const directory=`<div class="card"><div class="cardhead"><div><h2>User Directory</h2><span class="muted">${total.toLocaleString('en-US')} accounts</span></div><form method="get" action="/admin/v3" class="actions"><input type="hidden" name="section" value="users"><input name="q" value="${e(q)}" placeholder="Name, email or phone" style="height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 9px"><button class="btn">Search</button></form></div><div class="tablewrap"><table class="table"><thead><tr><th>User</th><th>Role</th><th>Status</th><th>Wallet</th><th>Joined</th><th></th></tr></thead><tbody>${rows.map(u=>`<tr><td><b>${e(u.fullName||'—')}</b><br><span class="muted">${e(u.email||u.phone||'—')}</span></td><td>${pill(u.role,u.role==='ADMIN'?'info':'')}</td><td>${state(u.status)}</td><td class="money">${money(u.wallet?.balanceAfn||0n)}</td><td>${dt(u.createdAt)}</td><td><a class="btn ghost" href="${href('users',`&edit=${u.id}`)}">Manage</a></td></tr>`).join('')}</tbody></table></div></div>`;
 if(!selected)return directory+blacklistCard;
 const phoneBlock=selected.phone
   ? blocked
     ? `<div class="notice" style="border-color:#ffd6dc;background:#fff0f2;color:#a73545"><b>Phone permanently blocked</b><br><span class="mono">${e(selected.phone)}</span><br>${e(blocked.reason||'No reason')}</div><form method="post" action="/admin/v3/user-control" style="margin-top:9px"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="UNBLOCK_PHONE"><button class="btn ghost">Unblock phone</button></form>`
     : `<form method="post" action="/admin/v3/user-control"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="BLOCK_PHONE"><div class="field"><label>Permanent phone blacklist reason</label><input name="reason" maxlength="300" placeholder="Reason for blocking this phone"></div><button class="btn danger">Block this phone permanently</button></form>`
   : '<div class="muted">This account has no phone number to blacklist.</div>';
 const selectedUi=`<div class="grid eq"><div>
  <div class="card"><div class="cardhead"><h2>Account Management</h2>${state(selected.status)}</div>
   <form method="post" action="/admin/v3/user"><input type="hidden" name="userId" value="${selected.id}"><div class="forms"><div class="field"><label>Role</label><select name="role"><option ${selected.role==='USER'?'selected':''}>USER</option><option ${selected.role==='ADMIN'?'selected':''}>ADMIN</option></select></div><div class="field"><label>Base Status</label><select name="status"><option ${selected.status==='ACTIVE'?'selected':''}>ACTIVE</option><option ${selected.status==='SUSPENDED'?'selected':''}>SUSPENDED</option></select></div></div><button class="btn">Save Account</button></form>
  </div>
  <div class="card"><div class="cardhead"><h2>Access & Safety Controls</h2>${pill(accessLabel,accessLabel==='ACTIVE'?'ok':'warn')}</div>
   ${accessInfo?`<div class="notice" style="margin-bottom:10px">${accessInfo}</div>`:''}
   <form method="post" action="/admin/v3/user-control"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="TEMP_SUSPEND"><div class="forms"><div class="field"><label>Temporary block (hours)</label><input name="hours" type="number" min="1" max="8760" value="24" required></div><div class="field"><label>Reason</label><input name="reason" maxlength="300" placeholder="Optional admin reason"></div></div><button class="btn ghost">Temporarily suspend</button></form>
   <div class="actions" style="margin-top:10px"><form method="post" action="/admin/v3/user-control"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="PERM_SUSPEND"><input type="hidden" name="reason" value="Permanently suspended by administrator"><button class="btn danger">Permanent suspend</button></form><form method="post" action="/admin/v3/user-control"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="RESTORE"><button class="btn ghost">Restore access</button></form></div>
   <hr style="border:0;border-top:1px solid #edf2f7;margin:15px 0">${phoneBlock}
   <hr style="border:0;border-top:1px solid #edf2f7;margin:15px 0"><div class="notice"><b>Delete account</b><br>Soft-deletes and anonymizes the user while preserving financial/order records. This does not blacklist the phone unless you use the phone blacklist above.</div><form method="post" action="/admin/v3/user-control" style="margin-top:9px"><input type="hidden" name="userId" value="${selected.id}"><input type="hidden" name="action" value="DELETE"><div class="field"><label>Type DELETE to confirm</label><input name="confirmText" pattern="DELETE" required></div><div class="field"><label>Reason</label><input name="reason" maxlength="300" placeholder="Administrative deletion"></div><button class="btn danger">Delete account permanently</button></form>
  </div>
 </div><div>
  <div class="card"><div class="cardhead"><h2>Recent Wallet Activity</h2><b>${money(selected.wallet?.balanceAfn||0n)}</b></div>${selected.wallet?.entries.map(x=>`<div class="provider" style="grid-template-columns:1fr auto"><div><b>${e(x.description||x.type)}</b><small>${dt(x.createdAt)}</small></div><b style="color:${x.amountAfn>=0n?'#18a875':'#e65362'}">${x.amountAfn>0n?'+':''}${money(x.amountAfn)}</b></div>`).join('')||'<div class="empty">No wallet entries.</div>'}</div>
  <div class="card"><div class="cardhead"><h2>Wallet Adjustment</h2></div><form method="post" action="/admin/v3/wallet"><input type="hidden" name="userId" value="${selected.id}"><div class="forms"><div class="field"><label>Amount AFN</label><input name="amountAfn" type="number" placeholder="500 or -200" required></div><div class="field"><label>Reason</label><input name="reason" minlength="3" required></div></div><button class="btn">Post to Ledger</button></form></div>
 </div></div>`;
 return directory+blacklistCard+selectedUi;
}
async function referralsPage(p:PrismaClient){
 const snap=await referralAdminSnapshot(p),s=snap.settings;
 return `<div class="stats">
  <div class="stat"><div class="sicon">${ico('users')}</div><div><small>Total referrals</small><strong>${snap.count.toLocaleString('en-US')}</strong></div></div>
  <div class="stat"><div class="sicon">${ico('wallet')}</div><div><small>Verified referred top-ups</small><strong>${money(snap.totalQualifyingTopups)}</strong></div></div>
  <div class="stat"><div class="sicon">${ico('coupon')}</div><div><small>Total commission paid</small><strong>${money(snap.totalRewards)}</strong></div></div>
  <div class="stat"><div class="sicon">${ico('settings')}</div><div><small>Commission rate</small><strong>${e(s.rewardPercent)}%</strong><div class="delta">${s.enabled?'Program active':'Program disabled'}</div></div></div>
 </div>
 <div class="grid eq">
  <div class="card">
   <div class="cardhead"><h2>Referral Commission Settings</h2>${s.enabled?pill('Enabled','ok'):pill('Disabled','bad')}</div>
   <form method="post" action="/admin/v3/referral-settings">
    <label class="check"><input type="checkbox" name="enabled" ${s.enabled?'checked':''}> Enable Invite Friends commission</label>
    <div class="field"><label>Commission from each verified wallet top-up (%)</label><input type="number" min="0" max="100" step="0.01" name="rewardPercent" value="${e(s.rewardPercent)}" required></div>
    <div class="notice"><b>No reward is paid for registration.</b><br>The inviter receives this percentage only when the invited user completes a verified HesabPay wallet top-up. Payment-level idempotency prevents duplicate commission.</div>
    <button class="btn" style="margin-top:12px">Save commission settings</button>
   </form>
  </div>
  <div class="card modulehero">
   <div class="cardhead"><div><h2>Invite Friends</h2><p>The referral link connects the two accounts; commission follows real verified top-ups.</p></div>${ico('users')}</div>
   <div class="kpis"><div><b>${snap.count}</b><small>Invited accounts</small></div><div><b>${money(snap.totalQualifyingTopups)}</b><small>Top-ups</small></div><div><b>${money(snap.totalRewards)}</b><small>Commission</small></div></div>
  </div>
 </div>
 <div class="card"><div class="cardhead"><h2>Referral Activity</h2><span class="muted">Latest 500 referral relationships</span></div>
  <div class="tablewrap"><table class="table"><thead><tr><th>Inviter</th><th>Invitee</th><th>Code</th><th>Verified top-ups</th><th>Commission paid</th><th>Payments</th><th>Created</th></tr></thead><tbody>
  ${snap.items.map((x:any)=>`<tr>
   <td><b>${e(x.inviter?.fullName||'VELIXEO user')}</b><br><span class="muted">${e(x.inviter?.email||x.inviter?.phone||x.inviterId||'—')}</span></td>
   <td><b>${e(x.invitee?.fullName||'VELIXEO user')}</b><br><span class="muted">${e(x.invitee?.email||x.invitee?.phone||x.inviteeId||'—')}</span></td>
   <td class="mono">${e(x.code||'—')}</td>
   <td class="money">${money(Number(x.qualifyingTopupAfn||0))}</td>
   <td class="money">${money(Number(x.rewardAfn||0))}</td>
   <td>${e(Number(x.rewardCount||0))}</td>
   <td>${dt(String(x.createdAt||''))}</td>
  </tr>`).join('')||'<tr><td colspan="7" class="empty">No referral activity yet.</td></tr>'}
  </tbody></table></div>
 </div>`;
}
function categoryKey(slug:string){return `social.category.${slug}`}
function slug(v:string){return v.toLowerCase().trim().replace(/\s+/g,'-').replace(/[^a-z0-9_-]+/g,'-').replace(/^-+|-+$/g,'').slice(0,80)}
function parseCategory(row:{key:string;value:Prisma.JsonValue}):SocialCategory|null{const v=jsonObj(row.value),s=typeof v.slug==='string'?v.slug:row.key.replace(/^social\.category\./,'');if(!s)return null;return{slug:s,titleEn:typeof v.titleEn==='string'?v.titleEn:s,titleFa:typeof v.titleFa==='string'?v.titleFa:s,platform:typeof v.platform==='string'?v.platform:'OTHER',descriptionEn:typeof v.descriptionEn==='string'?v.descriptionEn:'',descriptionFa:typeof v.descriptionFa==='string'?v.descriptionFa:'',sortOrder:Number.isFinite(Number(v.sortOrder))?Number(v.sortOrder):100,enabled:v.enabled!==false}}
async function categories(p:PrismaClient){const rows=await p.systemSetting.findMany({where:{category:'social-category'},orderBy:{key:'asc'}});return rows.map(parseCategory).filter((x):x is SocialCategory=>Boolean(x)).sort((a,b)=>a.sortOrder-b.sortOrder||a.titleEn.localeCompare(b.titleEn))}

async function providerFormData(p:PrismaClient,kind:ProviderKind){return p.provider.findMany({where:{kind},orderBy:[{enabled:'desc'},{priority:'asc'},{name:'asc'}]})}
function providerEditor(section:Section,kind:ProviderKind,x:any){return `<form method="post" action="/admin/v3/provider"><input type="hidden" name="id" value="${e(x?.id||'')}"><input type="hidden" name="section" value="${section}"><input type="hidden" name="kind" value="${kind}"><div class="forms"><div class="field"><label>Provider Name</label><input name="name" value="${e(x?.name||'')}" required></div><div class="field"><label>Slug</label><input class="mono" name="slug" value="${e(x?.slug||'')}" required></div><div class="field"><label>API Base URL</label><input class="mono" name="baseUrl" value="${e(x?.baseUrl||'')}" placeholder="https://provider.tld/api/v2"></div><div class="field"><label>Priority (lower = first)</label><input type="number" name="priority" value="${e(x?.priority??20)}"></div><div class="field"><label>Default Markup %</label><input name="markup" inputmode="decimal" value="${e(x?.defaultMarkupPercent?.toString?.()||'0')}"></div><div class="field"><label>Timeout seconds</label><input type="number" name="timeout" value="${e(x?.timeoutSeconds??30)}"></div></div><div class="field"><label>Internal Notes</label><textarea name="notes">${e(x?.notes||'')}</textarea></div><label class="check"><input type="checkbox" name="enabled" ${x?.enabled===false?'':'checked'}> Enabled</label><button class="btn">${x?'Save Provider':'Add Provider'}</button></form>`}

async function socialPage(p:PrismaClient,tab:string,q:string,edit:string,providerId:string,routeId:string){const tb=tabbar('social',tab,[['overview','Overview'],['providers','Providers'],['brands','Brands'],['categories','Categories'],['services','My Services'],['routing','Routing'],['orders','Orders'],['logs','API Logs']]);const providers=await providerFormData(p,ProviderKind.SOCIAL);if(tab==='providers'){const selected=edit?providers.find(x=>x.id===edit):undefined;const syncs=await Promise.all(providers.map(async x=>({x,s:await getSocialProviderSyncConfig(p,x.id)})));return{tabs:tb,body:`<div class="grid"><div><div class="card"><div class="cardhead"><h2>SMM Providers</h2>${pill(`${providers.length} providers`,'info')}</div>${syncs.map(({x,s})=>`<div class="provider"><div class="plogo">${e(x.name.charAt(0))}</div><div><b>${e(x.name)}</b><small class="mono">${e(x.baseUrl||'No endpoint')}</small></div>${x.enabled?pill('Active','ok'):pill('Disabled','bad')}<div class="actions"><a class="btn ghost" href="${href('social',`&tab=providers&edit=${x.id}`)}">Edit</a><form method="post" action="/admin/v3/social/sync"><input type="hidden" name="providerId" value="${x.id}"><button class="btn">Sync</button></form></div></div><div class="muted" style="padding:0 0 7px 42px">Auto sync: ${s.autoSync?`every ${s.syncMinutes} min`:'off'} · Last: ${dt(s.lastSyncAt)} · ${s.lastServiceCount} services</div>`).join('')||'<div class="empty">No SMM provider yet.</div>'}</div>${selected?`<div class="card"><div class="cardhead"><h2>Encrypted API Credential</h2>${selected.secretCiphertext?pill('Configured','ok'):pill('Missing','warn')}</div><p class="muted">Saved secrets are never displayed again.</p><form method="post" action="/admin/v3/provider-secret"><input type="hidden" name="id" value="${selected.id}"><input type="hidden" name="section" value="social"><div class="field"><label>New API Key / Secret</label><textarea class="mono" name="secret" required></textarea></div><button class="btn">Save Encrypted Secret</button></form></div>`:''}</div><div class="card"><div class="cardhead"><h2>${selected?'Edit Provider':'Add Provider'}</h2><span class="muted">SMM API</span></div>${providerEditor('social',ProviderKind.SOCIAL,selected)}</div></div>`}}
 if(tab==='catalog'){const pid=providerId||providers[0]?.id||'';const cats=await categories(p);const routes=pid?await p.serviceProviderRoute.findMany({where:{providerId:pid,provider:{kind:ProviderKind.SOCIAL},...(q?{OR:[{providerServiceCode:{contains:q,mode:'insensitive'}},{providerName:{contains:q,mode:'insensitive'}},{providerCategory:{contains:q,mode:'insensitive'}}]}:{})},include:{provider:true,service:true},orderBy:[{providerCategory:'asc'},{providerServiceCode:'asc'}],take:400}):[];const selected=routeId?routes.find(x=>x.id===routeId)||await p.serviceProviderRoute.findUnique({where:{id:routeId},include:{provider:true,service:true}}):null;const priced=await Promise.all(routes.map(async r=>({r,sale:await socialRouteSaleRateAfn(p,r.service,{...r,provider:r.provider})})));const sm=selected?jsonObj(selected.service.metadata):{};return{tabs:tb,body:`<div class="card"><div class="cardhead"><form method="get" action="/admin/v3" class="actions"><input type="hidden" name="section" value="social"><input type="hidden" name="tab" value="catalog"><select name="provider" style="height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 8px">${providers.map(x=>`<option value="${x.id}" ${x.id===pid?'selected':''}>${e(x.name)}</option>`).join('')}</select><input name="q" value="${e(q)}" placeholder="Search ID, name or category" style="height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 8px"><button class="btn ghost">Filter</button></form>${pid?`<form method="post" action="/admin/v3/social/sync"><input type="hidden" name="providerId" value="${pid}"><button class="btn">Sync Now</button></form>`:''}</div><div class="notice">Provider services stay hidden from the app until you publish them. Auto Markup services keep following provider price changes after each sync.</div></div><div class="grid"><div class="card"><div class="cardhead"><h2>Provider Catalog</h2><span class="muted">${priced.length} loaded</span></div><div class="tablewrap"><table class="table"><thead><tr><th>ID</th><th>Provider Service</th><th>Category</th><th>Cost</th><th>Sale</th><th>Min / Max</th><th>App</th><th></th></tr></thead><tbody>${priced.map(({r,sale})=>`<tr><td class="mono">${e(r.providerServiceCode)}</td><td><b>${e(r.providerName||r.service.titleEn)}</b><br><span class="muted">${e(r.providerType||'Default')}</span></td><td>${e(r.providerCategory||'—')}</td><td>${e(r.providerRate?.toString()||'—')} ${e(r.providerCurrency||'')}</td><td class="money">${sale==null?'—':money(sale)}</td><td>${e(r.providerMinQty??'—')} – ${e(r.providerMaxQty??'—')}</td><td>${r.service.enabled?pill('Published','ok'):pill('Raw')}</td><td><a class="btn ghost" href="${href('social',`&tab=catalog&provider=${pid}&route=${r.id}`)}">${r.service.enabled?'Edit':'Publish'}</a></td></tr>`).join('')||'<tr><td colspan="8" class="empty">Sync a provider to load services.</td></tr>'}</tbody></table></div></div>${selected?`<div class="card"><div class="cardhead"><h2>${selected.service.enabled?'Edit Published Service':'Publish to VELIXEO'}</h2>${pill(selected.provider.name,'info')}</div><form method="post" action="/admin/v3/social/publish"><input type="hidden" name="routeId" value="${selected.id}"><input type="hidden" name="providerId" value="${pid}"><div class="field"><label>App Category</label><select name="categorySlug" required><option value="">Select category</option>${cats.map(x=>`<option value="${e(x.slug)}" ${String(sm.categorySlug||'')===x.slug?'selected':''}>${e(x.platform)} → ${e(x.titleEn)}</option>`).join('')}</select></div><div class="field"><label>Customer-facing English Name</label><input name="titleEn" value="${e(selected.service.titleEn)}" required></div><div class="field"><label>English Description</label><textarea name="descriptionEn">${e(selected.service.descriptionEn||'')}</textarea></div><div class="forms"><div class="field"><label>Pricing Mode</label><select name="pricingMode"><option value="AUTO_MARKUP" ${selected.service.basePriceAfn==null?'selected':''}>Auto Markup</option><option value="FIXED" ${selected.service.basePriceAfn!=null?'selected':''}>Fixed Price</option></select></div><div class="field"><label>Markup %</label><input name="markup" value="${e(selected.markupPercent?.toString()??selected.provider.defaultMarkupPercent.toString())}"></div><div class="field"><label>Fixed Price</label><input name="fixedPrice" value="${selected.service.basePriceAfn==null?'':e(selected.service.basePriceAfn.toString())}"></div><div class="field"><label>Fixed Currency</label><select name="fixedCurrency"><option>AFN</option><option>USD</option><option>TOMAN</option></select></div><div class="field"><label>Min Qty</label><input type="number" name="minQty" value="${e(selected.service.minQty??selected.providerMinQty??'')}"></div><div class="field"><label>Max Qty</label><input type="number" name="maxQty" value="${e(selected.service.maxQty??selected.providerMaxQty??'')}"></div></div><label class="check"><input type="checkbox" name="enabled" checked> Visible in app</label><button class="btn">Save & Publish</button></form></div>`:'<div class="card empty">Choose a provider service to configure its app category, customer name and pricing.</div>'}</div>`}}
 if(tab==='categories'){const cats=await categories(p);const editCat=edit?cats.find(x=>x.slug===edit):undefined;const counts=await p.service.groupBy({by:['socialGroup'],where:{category:ServiceCategory.SOCIAL,enabled:true},_count:{_all:true}});const map=new Map(counts.map(x=>[x.socialGroup||'',x._count._all]));return{tabs:tb,body:`<div class="grid"><div class="card"><div class="cardhead"><h2>App Categories</h2>${pill(`${cats.length} categories`,'info')}</div><div class="tablewrap"><table class="table"><thead><tr><th>Name</th><th>Platform</th><th>Services</th><th>Order</th><th>Status</th><th></th></tr></thead><tbody>${cats.map(x=>`<tr><td><b>${e(x.titleEn)}</b><br><span class="mono muted">${e(x.slug)}</span></td><td>${e(x.platform)}</td><td>${map.get(x.slug)||0}</td><td>${x.sortOrder}</td><td>${x.enabled?pill('Active','ok'):pill('Hidden','bad')}</td><td><a class="btn ghost" href="${href('social',`&tab=categories&edit=${x.slug}`)}">Edit</a></td></tr>`).join('')||'<tr><td colspan="6" class="empty">No categories yet.</td></tr>'}</tbody></table></div></div><div class="card"><div class="cardhead"><h2>${editCat?'Edit Category':'New Category'}</h2><span class="muted">Server-driven; no APK update</span></div><form method="post" action="/admin/v3/social/category"><input type="hidden" name="originalSlug" value="${e(editCat?.slug||'')}"><div class="forms"><div class="field"><label>Slug</label><input class="mono" name="slug" value="${e(editCat?.slug||'')}" required></div><div class="field"><label>Platform</label><select name="platform">${['INSTAGRAM','TIKTOK','TELEGRAM','YOUTUBE','FACEBOOK','X','SNAPCHAT','WHATSAPP','THREADS','OTHER'].map(x=>`<option ${editCat?.platform===x?'selected':''}>${x}</option>`).join('')}</select></div><div class="field"><label>English Name</label><input name="titleEn" value="${e(editCat?.titleEn||'')}" required></div><div class="field"><label>Sort Order</label><input type="number" name="sortOrder" value="${e(editCat?.sortOrder??100)}"></div></div><div class="field"><label>English Description</label><textarea name="descriptionEn">${e(editCat?.descriptionEn||'')}</textarea></div><label class="check"><input type="checkbox" name="enabled" ${editCat?.enabled===false?'':'checked'}> Active in app</label><button class="btn">Save Category</button></form></div></div>`}}
 const services=await p.service.findMany({where:{category:ServiceCategory.SOCIAL,...(tab==='services'?{enabled:true}:{})},include:{routes:{include:{provider:true},orderBy:{priority:'asc'}},orders:true},orderBy:[{enabled:'desc'},{sortOrder:'asc'}],take:300});if(tab==='routing')return{tabs:tb,body:`<div class="card"><div class="cardhead"><h2>Routing & Failover</h2><span class="muted">Lower priority number is tried first</span></div><div class="tablewrap"><table class="table"><thead><tr><th>VELIXEO Service</th><th>Provider</th><th>Provider Service ID</th><th>Priority</th><th>Markup</th><th>Last Sync</th></tr></thead><tbody>${services.flatMap(s=>s.routes.map(r=>`<tr><td>${e(s.titleEn)}</td><td>${e(r.provider.name)}</td><td class="mono">${e(r.providerServiceCode)}</td><td>${r.priority}</td><td>${e((r.markupPercent??r.provider.defaultMarkupPercent).toString())}%</td><td>${dt(r.lastSyncedAt)}</td></tr>`)).join('')||'<tr><td colspan="6" class="empty">No routes yet.</td></tr>'}</tbody></table></div></div>`};if(tab==='orders'){const orders=await p.order.findMany({where:{category:ServiceCategory.SOCIAL},include:{user:true,service:true,provider:true},orderBy:{createdAt:'desc'},take:150});return{tabs:tb,body:ordersTable(standardOrderRows(orders).slice(0,220))}}if(tab==='logs'){const logs=await p.orderActionLog.findMany({where:{order:{category:ServiceCategory.SOCIAL}},orderBy:{createdAt:'desc'},take:180});return{tabs:tb,body:logsTable(logs)}}if(tab==='services')return{tabs:tb,body:`<div class="card"><div class="cardhead"><h2>My Published Services</h2><span class="muted">${services.length} services</span></div><div class="tablewrap"><table class="table"><thead><tr><th>Service</th><th>Category</th><th>Routes</th><th>Pricing</th><th>Min / Max</th><th>Status</th></tr></thead><tbody>${services.map(s=>{const m=jsonObj(s.metadata);return`<tr><td><b>${e(s.titleEn)}</b><br><span class="mono muted">${e(s.slug)}</span></td><td>${e(String(m.categorySlug||s.socialGroup||'—'))}</td><td>${s.routes.map(r=>e(r.provider.name)).join(', ')||'—'}</td><td>${s.basePriceAfn!=null?`Fixed · ${money(s.basePriceAfn)}`:`Auto Markup`}</td><td>${s.minQty??'—'} – ${s.maxQty??'—'}</td><td>${s.enabled?pill('Active','ok'):pill('Hidden','bad')}</td></tr>`}).join('')}</tbody></table></div></div>`};const orderCount=await p.order.count({where:{category:ServiceCategory.SOCIAL}});const active=services.filter(x=>x.enabled).length;return{tabs:tb,body:`<div class="card modulehero"><div class="cardhead"><div><h2>Social Media Control Center</h2><p>Providers, live pricing, categories and customer services in one workspace.</p></div>${ico('social')}</div><div class="kpis"><div><b>${providers.length}</b><small>Providers</small></div><div><b>${services.length}</b><small>Catalog Services</small></div><div><b>${active}</b><small>Published</small></div><div><b>${orderCount}</b><small>Orders</small></div></div></div><div class="grid eq"><div class="card"><div class="cardhead"><h2>Provider Automation</h2><a class="link" href="${href('social','&tab=providers')}">Manage providers</a></div><div class="notice"><b>Live pricing is active by design.</b><br>Provider rate → exchange rate → markup. When provider cost changes, the next sync updates the source rate and the app receives the new sale price automatically. Fixed-price services remain unchanged.</div></div><div class="card"><div class="cardhead"><h2>Catalog Workflow</h2><a class="link" href="${href('social','&tab=catalog')}">Open catalog</a></div><div class="muted">1. Add provider → 2. Sync catalog → 3. Create app categories → 4. Publish selected services → 5. Set auto markup or fixed price → 6. Route/failover.</div></div></div>`}}

function adminOrderMeta(o:any){
  const input=jsonObj(o.input);
  const params=input.parameters&&typeof input.parameters==='object'&&!Array.isArray(input.parameters)?input.parameters as Record<string,unknown>:{};
  const output=jsonObj(o.output);
  const runs=Math.max(1,Number(input.runs??params.runs??1)||1);
  const interval=Math.max(0,Number(input.intervalMinutes??params.interval??0)||0);
  const unit=Math.max(0,Number(input.unitQuantity??params.quantity??o.quantity??0)||0);
  const total=Math.max(0,Number(input.totalQuantity??unit*runs)||0);
  const drip=input.dripFeed===true||runs>1;
  const refill=(o.actions??[]).find((x:any)=>x.action==='REFILL');
  let dripStatus='';
  if(drip){
    const raw=output.providerRawStatus&&typeof output.providerRawStatus==='object'&&!Array.isArray(output.providerRawStatus)?output.providerRawStatus as Record<string,unknown>:{};
    dripStatus=String(raw.status_name??raw.drip_feed_status??raw.dripfeed_status??'').trim();
    if(!dripStatus){
      if(['CANCELLED','FAILED','REFUNDED'].includes(String(o.status)))dripStatus='Stopped';
      else dripStatus='Active';
    }
  }
  const raw=output.providerRawStatus&&typeof output.providerRawStatus==='object'&&!Array.isArray(output.providerRawStatus)?output.providerRawStatus as Record<string,unknown>:{};
  const explicitCurrent=Number(raw.runs_current??raw.current_run??raw.run??NaN);
  const elapsed=Math.max(0,Date.now()-new Date(o.createdAt).getTime());
  const scheduledCurrent=interval>0?Math.min(runs,Math.max(1,Math.floor(elapsed/(interval*60000))+1)):1;
  const runsCurrent=Number.isFinite(explicitCurrent)?Math.max(0,Math.min(runs,explicitCurrent)):scheduledCurrent;
  return{input,output,runs,interval,unit,total,drip,refill,dripStatus,runsCurrent};
}
function adminDripRunStatus(o:any,m:ReturnType<typeof adminOrderMeta>,index:number){
  const normalized=String(m.dripStatus||'').trim().toLowerCase();
  if(['finished','completed','complete'].includes(normalized))return OrderStatus.COMPLETED;
  if(['stopped','cancelled','canceled','failed','refunded'].includes(normalized))return index<m.runsCurrent?OrderStatus.COMPLETED:OrderStatus.CANCELLED;
  if(index<m.runsCurrent)return OrderStatus.COMPLETED;
  if(index===m.runsCurrent&&m.runsCurrent>0)return OrderStatus.PROCESSING;
  return OrderStatus.PENDING;
}
function adminDripRunRows(o:any){
  const m=adminOrderMeta(o);
  if(!m.drip)return[o];
  const rows:any[]=[];
  const total=BigInt(o.totalAmountAfn??0);
  const count=BigInt(Math.max(1,m.runs));
  const base=total/count;
  const params=m.input.parameters&&typeof m.input.parameters==='object'&&!Array.isArray(m.input.parameters)
    ? m.input.parameters as Record<string,unknown>
    : {};
  for(let index=1;index<=m.runs;index+=1){
    const amount=index===m.runs?total-(base*BigInt(m.runs-1)):base;
    rows.push({
      ...o,
      status:adminDripRunStatus(o,m,index),
      quantity:m.unit,
      totalAmountAfn:amount,
      providerOrderId:null,
      input:{...m.input,parameters:{...params,runs:1},dripFeed:false,runs:1,unitQuantity:m.unit,totalQuantity:m.unit},
      _dripRun:{index,runs:m.runs,parentId:o.id,parentDisplay:e(o.publicOrderNumber??sid(o.id)),scheduledAt:new Date(new Date(o.createdAt).getTime()+Math.max(0,index-1)*m.interval*60000)},
    });
  }
  return rows;
}
function standardOrderRows(rows:any[]){return rows.flatMap(o=>adminOrderMeta(o).drip?adminDripRunRows(o):[o])}

function orderStatusControls(o:any){
  const m=adminOrderMeta(o),override=m.output.adminStatusOverride===true;
  return `<form method="post" action="/admin/v3/order-status" class="actions" style="margin-top:6px">
    <input type="hidden" name="id" value="${e(o.id)}">
    <select name="status" style="height:31px;border:1px solid #e3eaf3;border-radius:7px;padding:0 6px">
      ${Object.values(OrderStatus).map(s=>`<option value="${s}" ${s===o.status?'selected':''}>${s}</option>`).join('')}
    </select>
    <button class="btn ghost" style="padding:6px 8px">Override</button>
  </form>
  ${override?`<form method="post" action="/admin/v3/order-status-provider" style="margin-top:5px"><input type="hidden" name="id" value="${e(o.id)}"><button class="btn ghost" style="padding:6px 8px">Use Provider</button></form>`:''}`;
}

function ordersTable(rows:any[]){return `<div class="card"><div class="cardhead"><h2>Orders</h2>${pill(`${rows.length} shown`,'info')}</div><div class="tablewrap"><table class="table"><thead><tr><th>#</th><th>User</th><th>Service</th><th>Type / Provider</th><th>Amount</th><th>Status</th><th>Created</th><th>Admin</th></tr></thead><tbody>${rows.map(o=>{const m=adminOrderMeta(o),run=o._dripRun as any;const display=run?`${e(o.publicOrderNumber??sid(o.id))}-R${run.index}`:e(o.publicOrderNumber??sid(o.id));return`<tr><td>${display}<br><span class="mono muted">${run?`Drip ${e(run.index)}/${e(run.runs)}`:e(o.providerOrderId||'—')}</span></td><td>${e(o.user?.fullName||o.user?.email||o.user?.phone||'—')}</td><td><b>${e(o.service?.titleEn||o.service?.titleFa||o.category)}</b><br><span class="muted">${e(o.category)}</span></td><td>${run?pill(`Run ${run.index}/${run.runs}`,'info'):(m.drip?pill('Drip-feed','info'):'')} ${m.refill?pill('Refill','warn'):''}<br><span class="muted">${e(o.provider?.name||'—')}</span>${run?`<br><span class="muted">${e(o.quantity??0)} qty · scheduled ${dt(run.scheduledAt)}</span>`:(m.drip?`<br><span class="muted">${e(m.unit)} × ${e(m.runs)} · ${e(m.interval)} min · ${e(m.dripStatus)}</span>`:'')}${m.refill?`<br><span class="muted">Refill: ${e(m.refill.status)}</span>`:''}</td><td class="money">${money(o.totalAmountAfn)}</td><td>${state(o.status)}${!run&&m.drip?`<br>${pill(m.dripStatus,m.dripStatus.toLowerCase()==='active'?'info':m.dripStatus.toLowerCase()==='finished'?'ok':'warn')}`:''}${!run&&m.output.adminStatusOverride===true?'<br><span class="pill warn">Admin Override</span>':''}</td><td>${run?dt(run.scheduledAt):dt(o.createdAt)}</td><td>${run?'<span class="muted">Managed by Drip-feed</span>':orderStatusControls(o)}</td></tr>`}).join('')||'<tr><td colspan="8" class="empty">No orders found.</td></tr>'}</tbody></table></div></div>`}
function logsTable(rows:any[]){return `<div class="card"><div class="cardhead"><h2>API / Order Action Logs</h2><span class="muted">Latest provider interactions</span></div><div class="tablewrap"><table class="table"><thead><tr><th>Time</th><th>Order</th><th>Action</th><th>Status</th><th>Provider Reference</th></tr></thead><tbody>${rows.map(x=>`<tr><td>${dt(x.createdAt)}</td><td>${sid(x.orderId)}</td><td class="mono">${e(x.action)}</td><td>${state(x.status)}</td><td class="mono">${e(x.providerReference||'—')}</td></tr>`).join('')||'<tr><td colspan="5" class="empty">No logs yet.</td></tr>'}</tbody></table></div></div>`}

async function genericModule(p:PrismaClient,section:Section,category:ServiceCategory,kind:ProviderKind,tab:string,edit:string){const tb=tabbar(section,tab,[['overview','Overview'],['providers','Providers'],['services','Services'],['orders','Orders'],['logs','API Logs']]);const [providers,services,orders]=await Promise.all([providerFormData(p,kind),p.service.findMany({where:{category},include:{routes:{include:{provider:true}}},orderBy:[{enabled:'desc'},{sortOrder:'asc'}],take:250}),p.order.findMany({where:{category},include:{user:true,service:true,provider:true},orderBy:{createdAt:'desc'},take:130})]);if(tab==='providers'){const x=edit?providers.find(y=>y.id===edit):undefined;return{tabs:tb,body:`<div class="grid"><div><div class="card"><div class="cardhead"><h2>Providers</h2>${pill(`${providers.length}`,'info')}</div>${providers.map(y=>`<div class="provider"><div class="plogo">${e(y.name.charAt(0))}</div><div><b>${e(y.name)}</b><small class="mono">${e(y.baseUrl||'No URL')}</small></div>${y.enabled?pill('Active','ok'):pill('Disabled','bad')}<a class="btn ghost" href="${href(section,`&tab=providers&edit=${y.id}`)}">Edit</a></div>`).join('')||'<div class="empty">No providers yet.</div>'}</div>${x?`<div class="card"><div class="cardhead"><h2>Encrypted Credential</h2>${x.secretCiphertext?pill('Configured','ok'):pill('Missing','warn')}</div><form method="post" action="/admin/v3/provider-secret"><input type="hidden" name="id" value="${x.id}"><input type="hidden" name="section" value="${section}"><div class="field"><label>New API Key / Token</label><textarea class="mono" name="secret" required></textarea></div><button class="btn">Save Secret</button></form></div>`:''}</div><div class="card"><div class="cardhead"><h2>${x?'Edit Provider':'Add Provider'}</h2></div>${providerEditor(section,kind,x)}</div></div>`}}if(tab==='orders')return{tabs:tb,body:ordersTable(orders)};if(tab==='logs'){const logs=await p.orderActionLog.findMany({where:{order:{category}},orderBy:{createdAt:'desc'},take:150});return{tabs:tb,body:logsTable(logs)}}if(tab==='services')return{tabs:tb,body:`<div class="card"><div class="cardhead"><h2>Services</h2>${pill(`${services.length}`,'info')}</div><div class="tablewrap"><table class="table"><thead><tr><th>Service</th><th>Provider Routes</th><th>Price</th><th>Min / Max</th><th>Status</th></tr></thead><tbody>${services.map(s=>`<tr><td><b>${e(s.titleEn||s.titleFa)}</b><br><span class="mono muted">${e(s.slug)}</span></td><td>${s.routes.map(r=>e(r.provider.name)).join(', ')||'—'}</td><td>${s.basePriceAfn!=null?money(s.basePriceAfn):'Dynamic'}</td><td>${s.minQty??'—'} – ${s.maxQty??'—'}</td><td>${s.enabled?pill('Active','ok'):pill('Hidden','bad')}</td></tr>`).join('')||'<tr><td colspan="5" class="empty">No services yet.</td></tr>'}</tbody></table></div></div>`};return{tabs:tb,body:`<div class="card modulehero"><div class="cardhead"><div><h2>${e(meta[section][0])} Workspace</h2><p>Independent providers, products, pricing and orders for this business module.</p></div>${ico(section==='virtual'?'phone':'service')}</div><div class="kpis"><div><b>${providers.length}</b><small>Providers</small></div><div><b>${services.length}</b><small>Services</small></div><div><b>${services.filter(x=>x.enabled).length}</b><small>Active</small></div><div><b>${orders.length}</b><small>Recent Orders</small></div></div></div>`}}

async function virtualModule(p:PrismaClient,tab:string,edit:string){
 const tb=tabbar('virtual',tab,[['overview','Overview'],['banner','Banner'],['providers','Providers'],['services','Services'],['countries','Countries'],['pricing','Pricing'],['orders','Orders'],['logs','API Logs']]);
 const returnTo=(target:string)=>`/admin/v3?section=virtual&tab=${encodeURIComponent(target)}`;
 if(tab==='banner'){
  const banner=await p.banner.findFirst({
   where:{
    placement:BannerPlacement.SERVICES_TOP,
    actionUrl:{in:['velixeo://virtual-numbers','velixeo://virtual']},
   },
   orderBy:{updatedAt:'desc'},
  });
  return{tabs:tb,body:`
   <div class="grid eq">
    <div class="card">
     <div class="cardhead">
      <div><h2>Virtual Numbers Entry Banner</h2><span class="muted">Shown at the top every time the Virtual Numbers section opens</span></div>
      ${banner?(banner.enabled?pill('Live','ok'):pill('Disabled','bad')):pill('Default hero','info')}
     </div>
     <div class="notice" style="margin-bottom:12px">
      Change the image or text here at any time — no APK update is needed.
      If this banner is disabled, VELIXEO shows the built-in “Virtual numbers & OTP” information hero instead.
     </div>
     <form method="post" action="/admin/v3/virtual/banner">
      <input type="hidden" name="id" value="${e(banner?.id||'')}">
      <div class="forms">
       <div class="field"><label>English Title</label><input name="titleEn" value="${e(banner?.titleEn||'Virtual Numbers & OTP')}"></div>
       <div class="field"><label>Persian Title</label><input name="titleFa" value="${e(banner?.titleFa||'شماره مجازی و دریافت OTP')}"></div>
      </div>
      <div class="forms">
       <div class="field"><label>English Subtitle</label><input name="subtitleEn" value="${e(banner?.subtitleEn||'Choose a service, country and live operator to receive SMS verification codes.')}"></div>
       <div class="field"><label>Persian Subtitle</label><input name="subtitleFa" value="${e(banner?.subtitleFa||'سرویس و کشور را انتخاب کنید و شماره را با قیمت، موجودی و نرخ تحویل زنده بخرید.')}"></div>
      </div>
      <div class="field">
       <label>Banner Image URL</label>
       <input class="mono" name="imageUrl" value="${e(banner?.imageUrl||'')}" placeholder="https://.../virtual-number-banner.jpg" required>
       <small class="muted">Recommended: 1080×420 JPG/WebP, optimized below 300 KB for fast mobile loading.</small>
      </div>
      <div class="forms">
       <div class="field"><label>Sort Order</label><input type="number" name="sortOrder" value="${e(banner?.sortOrder??10)}"></div>
       <div class="field"><label>Deep Link</label><input class="mono" value="velixeo://virtual-numbers" disabled></div>
      </div>
      <label class="check"><input type="checkbox" name="enabled" ${banner?.enabled===false?'':'checked'}> Show this banner in the app</label>
      <button class="btn" style="margin-top:12px">Save Virtual Banner</button>
     </form>
    </div>
    <div class="card">
     <div class="cardhead"><h2>Preview</h2><span class="muted">Mobile crop preview</span></div>
     ${banner?.imageUrl
       ?`<div style="height:180px;border-radius:20px;overflow:hidden;position:relative;background:linear-gradient(135deg,#0b5f9f,#31a8ff)">
          <img src="${e(banner.imageUrl)}" alt="" style="width:100%;height:100%;object-fit:cover;display:block">
          <div style="position:absolute;inset:0;background:linear-gradient(90deg,rgba(0,18,40,.7),rgba(0,18,40,.12))"></div>
          <div style="position:absolute;left:18px;right:18px;bottom:16px;color:#fff"><b style="font-size:20px">${e(banner.titleEn||'Virtual Numbers & OTP')}</b><div style="font-size:12px;margin-top:5px;color:#e7f5ff">${e(banner.subtitleEn||'')}</div></div>
        </div>`
       :'<div class="empty">Save an image URL to see the live banner preview.</div>'}
     <p class="muted" style="margin-top:12px">The app uses a lightweight image decode and keeps the fallback hero visible if the network image fails.</p>
    </div>
   </div>`};
 }
 if(tab==='providers'){
  const providers=await providerFormData(p,ProviderKind.VIRTUAL_NUMBER),selected=edit?providers.find(x=>x.id===edit):undefined;
  const health=await Promise.all(providers.map(async x=>({x,h:await providerCheck(x)})));
  return{tabs:tb,body:`<div class="grid"><div><div class="card"><div class="cardhead"><h2>5SIM / Virtual Number Providers</h2>${pill(`${providers.length} configured`,'info')}</div><div class="notice" style="margin-bottom:10px">This workspace is isolated from Social Media. Only <b>VIRTUAL_NUMBER</b> providers, services and orders are used here.</div>${health.map(({x,h})=>`<div class="provider"><div class="plogo">${e(x.name.charAt(0))}</div><div><b>${e(x.name)}</b><small class="mono">${e(x.baseUrl||'https://5sim.net')}</small></div>${pill(h.status,h.class)}<div class="actions"><form method="post" action="/admin/virtual-numbers/sync"><input type="hidden" name="providerId" value="${x.id}"><input type="hidden" name="returnTo" value="${e(returnTo('providers'))}"><button class="btn">Sync 5SIM</button></form><a class="btn ghost" href="${href('virtual',`&tab=providers&edit=${x.id}`)}">Edit</a></div></div>`).join('')||'<div class="empty">No virtual-number provider configured.</div>'}</div>${selected?`<div class="card"><div class="cardhead"><h2>Encrypted 5SIM Credential</h2>${selected.secretCiphertext?pill('Configured','ok'):pill('Missing','warn')}</div><p class="muted">The API token stays server-side and is never sent to the app.</p><form method="post" action="/admin/v3/provider-secret"><input type="hidden" name="id" value="${selected.id}"><input type="hidden" name="section" value="virtual"><div class="field"><label>New 5SIM API token / secret</label><textarea class="mono" name="secret" required></textarea></div><button class="btn">Save Encrypted Secret</button></form></div>`:''}</div><div class="card"><div class="cardhead"><h2>${selected?'Edit Virtual Provider':'Add Virtual Provider'}</h2><span class="muted">VIRTUAL_NUMBER only</span></div>${providerEditor('virtual',ProviderKind.VIRTUAL_NUMBER,selected)}</div></div>`};
 }
 if(tab==='services'){
  const services=await p.service.findMany({
   where:{category:ServiceCategory.VIRTUAL_NUMBER},
   include:{routes:{where:{provider:{kind:ProviderKind.VIRTUAL_NUMBER}},include:{provider:true},orderBy:{priority:'asc'}}},
   orderBy:[{sortOrder:'asc'},{titleEn:'asc'}],
   take:1000
  });
  const active=services.filter(x=>x.enabled).length;
  return{tabs:tb,body:`
   <div class="card">
    <div class="cardhead"><div><h2>Virtual Number Services</h2><span class="muted">All 5SIM products are synchronized automatically</span></div><div class="actions">${pill(`${active} visible`,'ok')}${pill(`${services.length} total`,'info')}</div></div>
    <div class="notice" style="margin-bottom:10px"><b>Icons & ordering:</b> uploaded icons are compressed in your browser to a lightweight 128×128 WebP before saving. The app loads only the tiny icon URL and follows the exact Display order below. Future 5SIM syncs will not overwrite your manual order or icon. Social Media is untouched.</div>
    <div class="actions" style="margin-bottom:13px">
     <form method="post" action="/admin/virtual-numbers/services-bulk"><input type="hidden" name="enabled" value="1"><input type="hidden" name="returnTo" value="${e(returnTo('services'))}"><button class="btn">Enable all services</button></form>
     <form method="post" action="/admin/virtual-numbers/services-bulk"><input type="hidden" name="enabled" value="0"><input type="hidden" name="returnTo" value="${e(returnTo('services'))}"><button class="btn danger">Disable all services</button></form>
    </div>
    <div class="actions" style="margin-bottom:13px;align-items:center;gap:9px;flex-wrap:wrap">
     <div style="min-width:260px;flex:1">
      <input id="vxl-service-search" type="search" placeholder="Search service name, slug or 5SIM code…" oninput="vxlFilterServices()" style="width:100%;height:40px;border:1px solid #dce8f1;border-radius:10px;padding:0 12px">
     </div>
     <select id="vxl-service-visibility" onchange="vxlFilterServices()" style="height:40px;border:1px solid #dce8f1;border-radius:10px;padding:0 10px">
      <option value="all">All visibility</option>
      <option value="visible">Visible only</option>
      <option value="hidden">Hidden only</option>
     </select>
     <select id="vxl-service-icon-filter" onchange="vxlFilterServices()" style="height:40px;border:1px solid #dce8f1;border-radius:10px;padding:0 10px">
      <option value="all">All icons</option>
      <option value="missing">Missing icon</option>
      <option value="uploaded">Uploaded icon</option>
     </select>
     <span id="vxl-service-filter-count" class="badge">${services.length} shown</span>
    </div>
    <div class="tablewrap"><table class="table" style="min-width:1450px"><thead><tr><th>Service</th><th>Icon & display order</th><th>5SIM Route</th><th>Pricing</th><th>Status</th><th>Individual pricing</th><th>Visibility</th></tr></thead><tbody id="vxl-service-rows">
    ${services.map(s=>{
      const route=s.routes[0],markup=route?.markupPercent?.toString?.()??route?.provider.defaultMarkupPercent.toString()??'0';
      const meta=jsonObj(s.metadata);
      const hasIcon=typeof meta.virtualIconDataUri==='string'&&String(meta.virtualIconDataUri).startsWith('data:image/');
      const iconVersion=encodeURIComponent(String(meta.virtualIconUpdatedAt||s.updatedAt.toISOString()));
      const iconUrl=`/api/v1/virtual-numbers/service-icon/${encodeURIComponent(s.id)}?v=${iconVersion}`;
      const fileId=`vicon-${s.id}`,hiddenId=`vicondata-${s.id}`,previewId=`viconpreview-${s.id}`;
      const serviceSearch=[s.titleEn,s.titleFa,s.slug,...s.routes.flatMap(r=>[r.provider.name,r.providerServiceCode])].filter(Boolean).join(' ').toLowerCase();
      return`<tr class="vxl-service-row" data-search="${e(serviceSearch)}" data-enabled="${s.enabled?'1':'0'}" data-icon="${hasIcon?'1':'0'}">
       <td><b>${e(s.titleEn||s.titleFa)}</b><br><span class="mono muted">${e(s.slug)}</span></td>
       <td style="min-width:330px">
        <form method="post" action="/admin/virtual-numbers/service-display" class="vicon-form">
         <input type="hidden" name="serviceId" value="${s.id}">
         <input type="hidden" name="returnTo" value="${e(returnTo('services'))}">
         <input type="hidden" name="iconData" id="${hiddenId}">
         <div class="actions" style="align-items:center">
          <div style="width:46px;height:46px;border-radius:13px;background:#eef7ff;border:1px solid #dce8f1;display:grid;place-items:center;overflow:hidden">
           ${hasIcon?`<img id="${previewId}" src="${iconUrl}" alt="" style="width:100%;height:100%;object-fit:contain;padding:4px">`:`<div id="${previewId}" style="font-size:10px;color:#789;line-height:1.1;text-align:center">No<br>icon</div>`}
          </div>
          <div style="flex:1;min-width:155px">
           <label class="btn ghost" for="${fileId}" style="display:inline-block;padding:7px 9px;cursor:pointer">Upload icon</label>
           <input id="${fileId}" type="file" accept="image/png,image/jpeg,image/webp" style="display:none" onchange="vxlPrepareIcon(this,'${hiddenId}','${previewId}')">
           <div class="muted" style="margin-top:4px">PNG/JPG/WebP → 128×128 WebP</div>
          </div>
         </div>
         <div class="actions" style="margin-top:8px">
          <label class="muted">Display order <input name="sortOrder" type="number" min="1" max="1000000" value="${e(s.sortOrder)}" style="width:90px;height:32px;border:1px solid #e3eaf3;border-radius:7px;padding:0 7px"></label>
          ${hasIcon?'<label class="muted"><input type="checkbox" name="removeIcon"> Remove icon</label>':''}
          <button class="btn ghost" style="padding:6px 8px">Save icon & order</button>
         </div>
        </form>
       </td>
       <td>${s.routes.map(r=>`${e(r.provider.name)} · <span class="mono">${e(r.providerServiceCode)}</span>`).join('<br>')||'—'}</td>
       <td>${s.basePriceAfn!=null?`Fixed ${money(s.basePriceAfn)}`:`Live cost + ${e(markup)}%`}</td>
       <td>${s.enabled?pill('Visible','ok'):pill('Hidden','bad')}</td>
       <td><form method="post" action="/admin/virtual-numbers/service-pricing"><input type="hidden" name="serviceId" value="${s.id}"><input type="hidden" name="returnTo" value="${e(returnTo('services'))}"><div class="actions"><input name="markup" type="number" min="0" max="1000" step="0.01" value="${e(markup)}" title="Markup %" style="width:82px;height:32px;border:1px solid #e3eaf3;border-radius:7px;padding:0 7px"><input name="fixedPriceAfn" type="number" min="1" value="${s.basePriceAfn==null?'':e(s.basePriceAfn.toString())}" placeholder="Fixed AFN" style="width:105px;height:32px;border:1px solid #e3eaf3;border-radius:7px;padding:0 7px"><button class="btn ghost" style="padding:6px 8px">Save</button></div><small class="muted">Leave Fixed AFN empty for percentage pricing.</small></form></td>
       <td><form method="post" action="/admin/virtual-numbers/service-toggle"><input type="hidden" name="serviceId" value="${s.id}"><input type="hidden" name="enabled" value="${s.enabled?'0':'1'}"><input type="hidden" name="returnTo" value="${e(returnTo('services'))}"><button class="btn ghost">${s.enabled?'Hide':'Show'}</button></form></td>
      </tr>`;
    }).join('')||'<tr><td colspan="7" class="empty">Sync the 5SIM provider to load all products.</td></tr>'}
    <tr id="vxl-service-no-results" style="display:none"><td colspan="7" class="empty">No service matches this search/filter.</td></tr>
    </tbody></table></div>
   </div>
   <script>
   function vxlFilterServices(){
     const search=document.getElementById('vxl-service-search');
     const visibility=document.getElementById('vxl-service-visibility');
     const iconFilter=document.getElementById('vxl-service-icon-filter');
     const q=String(search&&search.value||'').trim().toLowerCase();
     const visibilityValue=String(visibility&&visibility.value||'all');
     const iconValue=String(iconFilter&&iconFilter.value||'all');
     const rows=Array.from(document.querySelectorAll('.vxl-service-row'));
     let shown=0;
     rows.forEach(function(row){
       const matchesText=!q||String(row.getAttribute('data-search')||'').includes(q);
       const enabled=row.getAttribute('data-enabled')==='1';
       const hasIcon=row.getAttribute('data-icon')==='1';
       const matchesVisibility=visibilityValue==='all'||(visibilityValue==='visible'&&enabled)||(visibilityValue==='hidden'&&!enabled);
       const matchesIcon=iconValue==='all'||(iconValue==='uploaded'&&hasIcon)||(iconValue==='missing'&&!hasIcon);
       const visible=matchesText&&matchesVisibility&&matchesIcon;
       row.style.display=visible?'':'none';
       if(visible)shown++;
     });
     const count=document.getElementById('vxl-service-filter-count');
     if(count)count.textContent=shown+' shown';
     const empty=document.getElementById('vxl-service-no-results');
     if(empty)empty.style.display=rows.length>0&&shown===0?'':'none';
   }
   function vxlPrepareIcon(input,hiddenId,previewId){
     const file=input.files&&input.files[0];
     if(!file)return;
     if(!['image/png','image/jpeg','image/webp'].includes(file.type)){
       alert('Use PNG, JPG or WebP.');
       input.value='';
       return;
     }
     const reader=new FileReader();
     reader.onload=function(){
       const img=new Image();
       img.onload=function(){
         const size=128,canvas=document.createElement('canvas');
         canvas.width=size;canvas.height=size;
         const ctx=canvas.getContext('2d');
         ctx.clearRect(0,0,size,size);
         const scale=Math.min(size/img.width,size/img.height);
         const w=Math.max(1,Math.round(img.width*scale)),h=Math.max(1,Math.round(img.height*scale));
         ctx.drawImage(img,Math.round((size-w)/2),Math.round((size-h)/2),w,h);
         const data=canvas.toDataURL('image/webp',0.82);
         if(data.length>210000){alert('Icon is still too large. Please choose a simpler image.');return;}
         document.getElementById(hiddenId).value=data;
         const host=document.getElementById(previewId);
         if(host&&host.tagName==='IMG'){host.src=data;}
         else if(host){host.outerHTML='<img id="'+previewId+'" src="'+data+'" alt="" style="width:100%;height:100%;object-fit:contain;padding:4px">';}
       };
       img.src=String(reader.result||'');
     };
     reader.readAsDataURL(file);
   }
   </script>`};
 }
 if(tab==='countries'){
  const row=await p.systemSetting.findUnique({where:{key:'virtual.enabledCountries'}});
  return{tabs:tb,body:`<div class="grid eq"><div class="card"><div class="cardhead"><h2>Countries</h2><span class="muted">Empty = every country available from 5SIM</span></div><div class="notice">By default, all provider countries are shown automatically. Use this list only if you want to restrict the catalog.</div><form method="post" action="/admin/virtual-numbers/countries"><input type="hidden" name="returnTo" value="${e(returnTo('countries'))}"><div class="field"><label>Allowed 5SIM country codes (optional)</label><textarea class="mono" name="countries">${e(Array.isArray(row?.value)?row.value.join(', '):'')}</textarea></div><button class="btn">Save Country Restriction</button></form></div><div class="card"><div class="cardhead"><h2>Smart Buy country logic</h2>${pill('Automatic','ok')}</div><p class="muted">The app now proposes the strongest country using live delivery percentage + stock + price, and separately proposes the cheapest country. Users can still search and select a country manually.</p></div></div>`};
 }
 if(tab==='pricing'){
  const providers=await providerFormData(p,ProviderKind.VIRTUAL_NUMBER);
  const settings=await p.systemSetting.findMany({where:{OR:[{key:{startsWith:'virtual.provider.'}},{key:'virtual.globalMarkupPercent'}]}});
  const global=settings.find(y=>y.key==='virtual.globalMarkupPercent');
  const globalValue=typeof global?.value==='number'||typeof global?.value==='string'?String(global.value):'';
  return{tabs:tb,body:`
   <div class="card"><div class="cardhead"><h2>Global Virtual Number Profit</h2><span class="muted">Applies to every VIRTUAL_NUMBER route only</span></div>
    <div class="notice" style="margin-bottom:10px">Example: set 50% here to sell every virtual number at provider cost + 50%. You can then override Instagram, Telegram or any individual service from the Services tab.</div>
    <form method="post" action="/admin/virtual-numbers/pricing-global"><input type="hidden" name="returnTo" value="${e(returnTo('pricing'))}"><div class="forms"><div class="field"><label>Global profit / markup (%)</label><input name="markup" type="number" min="0" max="1000" step="0.01" value="${e(globalValue)}" placeholder="50" required></div><div style="display:flex;align-items:end"><button class="btn" style="width:100%;margin-bottom:9px">Apply to all virtual services</button></div></div></form>
   </div>
   <div class="card"><div class="cardhead"><h2>5SIM Cost → AFN</h2><span class="muted">Provider cost × AFN factor × markup</span></div><div class="notice" style="margin-bottom:10px">Currency conversion and profit settings here affect Virtual Numbers only. Social Media pricing is untouched.</div><div class="grid eq">
    ${providers.map(x=>{const s=settings.find(y=>y.key===`virtual.provider.${x.id}.afnPerUnit`),v=typeof s?.value==='number'||typeof s?.value==='string'?String(s.value):'';return`<form class="card" style="box-shadow:none" method="post" action="/admin/virtual-numbers/provider-rate"><input type="hidden" name="providerId" value="${x.id}"><input type="hidden" name="returnTo" value="${e(returnTo('pricing'))}"><div class="cardhead"><h3>${e(x.name)}</h3>${pill(`${x.defaultMarkupPercent.toString()}% provider default`,'info')}</div><div class="field"><label>AFN per provider price unit</label><input name="afnPerUnit" value="${e(v)}" inputmode="decimal" required></div><button class="btn">Save Conversion Rate</button></form>`}).join('')||'<div class="empty">No VIRTUAL_NUMBER provider.</div>'}
   </div></div>`};
 }
 const base=await genericModule(p,'virtual',ServiceCategory.VIRTUAL_NUMBER,ProviderKind.VIRTUAL_NUMBER,tab,edit);
 return{...base,tabs:tb};
}
type AdminOrderStatusKey='all'|'error'|'awaiting_action'|'manual'|'pending'|'processing'|'inprogress'|'completed'|'partial'|'cancelled'|'refunded'|'unpaid'|'awaiting_cancel';
type AdminOrderKind='all'|'social'|'refill'|'dripfeed';

function orderParams(o:any){
  const input=jsonObj(o.input);
  return input.parameters&&typeof input.parameters==='object'&&!Array.isArray(input.parameters)
    ? input.parameters as Record<string,unknown>
    : {};
}
function orderRawStatus(o:any){
  const output=jsonObj(o.output);
  return String(output.providerStatus??output.providerMappedStatus??'').trim().toLowerCase();
}
function orderHasPendingCancel(o:any){
  return (o.actions??[]).some((x:any)=>{
    const action=String(x.action??'').toUpperCase();
    const status=String(x.status??'').toUpperCase();
    return action==='CANCEL'&&!['COMPLETED','SUCCESS','REJECTED','FAILED','CANCELLED'].includes(status);
  });
}
function orderIsManual(o:any){
  const input=jsonObj(o.input),output=jsonObj(o.output);
  return input.manualOrder===true||output.manualOrder===true||output.source==='MANUAL';
}
function orderBucketMatch(o:any,key:AdminOrderStatusKey){
  if(key==='all')return true;
  if(key==='error')return o.status===OrderStatus.FAILED;
  if(key==='awaiting_action')return o.status===OrderStatus.AWAITING_SMS||jsonObj(o.output).awaitingAction===true;
  if(key==='manual')return orderIsManual(o);
  if(key==='pending')return o.status===OrderStatus.PENDING;
  if(key==='processing'){
    if(o.status!==OrderStatus.PROCESSING)return false;
    const raw=orderRawStatus(o);
    return !raw.includes('in progress')&&!raw.includes('inprogress');
  }
  if(key==='inprogress'){
    const raw=orderRawStatus(o);
    return o.status===OrderStatus.PROCESSING&&(raw.includes('in progress')||raw.includes('inprogress'));
  }
  if(key==='completed')return o.status===OrderStatus.COMPLETED;
  if(key==='partial')return o.status===OrderStatus.PARTIAL;
  if(key==='cancelled')return o.status===OrderStatus.CANCELLED;
  if(key==='refunded')return o.status===OrderStatus.REFUNDED;
  if(key==='unpaid')return jsonObj(o.output).paymentStatus==='UNPAID';
  if(key==='awaiting_cancel')return orderHasPendingCancel(o);
  return true;
}
function orderKindMatch(o:any,key:AdminOrderKind){
  if(key==='all')return true;
  const m=adminOrderMeta(o);
  if(key==='social')return o.category===ServiceCategory.SOCIAL;
  if(key==='refill')return Boolean(m.refill);
  if(key==='dripfeed')return m.drip;
  return true;
}
function orderSearchMatch(o:any,query:string,filter:string){
  if(!query)return true;
  const q=query.toLowerCase();
  const params=orderParams(o);
  const link=String(params.link??params.url??'');
  const systemId=String(o.publicOrderNumber??'');
  const providerId=String(o.providerOrderId??'');
  const serviceId=String(o.serviceId??o.service?.id??'');
  const route=o.service?.routes?.find((x:any)=>x.providerId===o.providerId);
  const providerServiceId=String(route?.providerServiceCode??'');
  const userName=String(o.user?.fullName??'');
  const email=String(o.user?.email??'');
  const phone=String(o.user?.phone??'');
  const offer=[o.service?.titleEn,o.service?.titleFa,o.service?.slug,o.category].filter(Boolean).join(' ');
  const created=new Date(o.createdAt).toISOString();
  const internal=[String(o.id??''),sid(String(o.id??''))].join(' ');
  const values:Record<string,string>={
    system_id:`${systemId} ${internal}`,
    link,
    service_id:`${serviceId} ${providerServiceId}`,
    provider_order_id:providerId,
    date:created,
    username:userName,
    email,
    phone,
    offer,
    all:[systemId,internal,providerId,serviceId,providerServiceId,link,userName,email,phone,offer,created].join(' '),
  };
  return String(values[filter]??values.all).toLowerCase().includes(q);
}
function orderDisplaySystemId(o:any){
  return o.publicOrderNumber!=null?String(o.publicOrderNumber):sid(String(o.id));
}
function orderLink(o:any){
  const params=orderParams(o);
  return String(params.link??params.url??'').trim();
}
function orderProviderServiceId(o:any){
  const route=o.service?.routes?.find((x:any)=>x.providerId===o.providerId);
  return String(route?.providerServiceCode??'').trim();
}
function orderStatusLabel(key:AdminOrderStatusKey){
  const labels:Record<AdminOrderStatusKey,string>={
    all:'All',error:'Error',awaiting_action:'Awaiting action',manual:'Manual orders',pending:'Queued',
    processing:'Processing',inprogress:'In progress',completed:'Completed',partial:'Partial',
    cancelled:'Cancelled',refunded:'Refunded',unpaid:'Unpaid',awaiting_cancel:'Awaiting cancel',
  };
  return labels[key];
}
function orderStatusClass(key:AdminOrderStatusKey){
  if(key==='error')return'error';
  if(key==='completed')return'complete';
  if(key==='pending'||key==='awaiting_action')return'pending';
  if(key==='processing'||key==='inprogress'||key==='awaiting_cancel')return'processing';
  if(key==='cancelled')return'cancel';
  if(key==='partial')return'partial';
  if(key==='refunded')return'refund';
  return'';
}

function professionalOrdersTable(rows:any[],total:number,page:number,pages:number,urlForPage:(page:number)=>string){
  return `<div class="card">
    <div class="cardhead"><div><h2>Customer Orders</h2><span class="muted">Full order, provider and delivery information</span></div><div class="orders-summary">${pill(`${total.toLocaleString('en-US')} matched`,'info')}${pill(`${rows.length} on this page`)}</div></div>
    <div class="tablewrap"><table class="table orders-table"><thead><tr>
      <th>VELIXEO ID</th><th>Provider API ID</th><th>User</th><th>Service / Provider</th><th>Link</th><th>Quantity</th><th>Start / Remains</th><th>Amount</th><th>Status</th><th>Created</th><th>Admin</th>
    </tr></thead><tbody>
    ${rows.map(o=>{
      const m=adminOrderMeta(o),run=o._dripRun as any,output=jsonObj(o.output),link=orderLink(o);
      const systemId=run?`${orderDisplaySystemId(o)}-R${run.index}`:orderDisplaySystemId(o);
      const providerOrderId=run?'—':String(o.providerOrderId??'—');
      const providerServiceId=orderProviderServiceId(o);
      const start=String(output.startCount??output.start_count??'—');
      const remains=String(output.remains??'—');
      const qty=o.quantity??m.total??0;
      return `<tr>
        <td class="order-id"><b>#${e(systemId)}</b><small class="mono muted" title="${e(o.id)}">${e(sid(String(o.id)))}</small>${run?`<small>${pill(`Drip ${run.index}/${run.runs}`,'info')}</small>`:''}</td>
        <td><b class="mono provider-id">${e(providerOrderId)}</b><br><small class="muted">Service API: <span class="mono">${e(providerServiceId||'—')}</span></small></td>
        <td class="order-user"><b>${e(o.user?.fullName||'—')}</b><small>${e(o.user?.email||'—')}</small><small>${e(o.user?.phone||'—')}</small></td>
        <td><b>${e(o.service?.titleEn||o.service?.titleFa||o.category)}</b><br><small class="muted">${e(o.provider?.name||'No provider')} · ${e(o.category)}</small>${m.drip&&!run?`<br>${pill('Drip-feed','info')}`:''}${m.refill?` ${pill('Refill','warn')}`:''}</td>
        <td class="order-link">${link?`<a href="${e(link)}" target="_blank" rel="noopener noreferrer" title="${e(link)}">${e(link)}</a>`:'—'}<small>${e(String(output.providerType??m.input.providerType??''))}</small></td>
        <td><div class="qtygrid"><span>Qty</span><b>${e(qty)}</b>${m.drip&&!run?`<span>Runs</span><b>${e(m.runs)}</b><span>Each</span><b>${e(m.unit)}</b>`:''}</div></td>
        <td><div class="qtygrid"><span>Start</span><b>${e(start)}</b><span>Remains</span><b>${e(remains)}</b></div></td>
        <td class="money">${money(o.totalAmountAfn)}<br><small class="muted">Cost: ${money(o.providerCostAfn??0n)}</small></td>
        <td>${state(o.status)}${!run&&m.drip?`<br>${pill(m.dripStatus,m.dripStatus.toLowerCase()==='active'?'info':m.dripStatus.toLowerCase()==='finished'?'ok':'warn')}`:''}${orderHasPendingCancel(o)?`<br>${pill('Awaiting cancel','warn')}`:''}${!run&&output.adminStatusOverride===true?'<br><span class="pill warn">Admin Override</span>':''}</td>
        <td>${run?dt(run.scheduledAt):dt(o.createdAt)}${o.completedAt?`<br><small class="muted">Done: ${dt(o.completedAt)}</small>`:''}</td>
        <td>${run?'<span class="muted">Managed by Drip-feed</span>':orderStatusControls(o)}</td>
      </tr>`;
    }).join('')||'<tr><td colspan="11" class="empty">No orders found for this filter.</td></tr>'}
    </tbody></table></div>
    ${pages>1?`<div class="pager">${page>1?`<a href="${urlForPage(page-1)}">← Previous</a>`:''}<span>Page ${page} / ${pages}</span>${page<pages?`<a href="${urlForPage(page+1)}">Next →</a>`:''}</div>`:''}
  </div>`;
}

async function allOrders(p:PrismaClient,q:string,statusRaw:string,filterRaw:string,kindRaw:string,pageRaw:number){
  const validStatuses=new Set<AdminOrderStatusKey>(['all','error','awaiting_action','manual','pending','processing','inprogress','completed','partial','cancelled','refunded','unpaid','awaiting_cancel']);
  const validKinds=new Set<AdminOrderKind>(['all','social','refill','dripfeed']);
  const status=(validStatuses.has(statusRaw as AdminOrderStatusKey)?statusRaw:'all') as AdminOrderStatusKey;
  const kind=(validKinds.has(kindRaw as AdminOrderKind)?kindRaw:'all') as AdminOrderKind;
  const filter=['all','system_id','link','service_id','provider_order_id','date','username','email','phone','offer'].includes(filterRaw)?filterRaw:'all';
  const query=q.trim();

  const raw=await p.order.findMany({
    include:{
      user:true,
      provider:true,
      actions:{orderBy:{createdAt:'desc'}},
      service:{include:{routes:{select:{providerId:true,providerServiceCode:true,providerName:true}}}},
    },
    orderBy:{createdAt:'desc'},
  });

  const kindRows=raw.filter(o=>orderKindMatch(o,kind));
  const statusKeys:AdminOrderStatusKey[]=['all','error','awaiting_action','manual','pending','processing','inprogress','completed','partial','cancelled','refunded','unpaid','awaiting_cancel'];
  const counts=Object.fromEntries(statusKeys.map(k=>[k,kindRows.filter(o=>orderBucketMatch(o,k)).length])) as Record<AdminOrderStatusKey,number>;

  const searched=kindRows.filter(o=>orderBucketMatch(o,status)&&orderSearchMatch(o,query,filter));
  const expanded=(kind==='refill'||kind==='dripfeed'?searched:standardOrderRows(searched));
  const pageSize=100;
  const pages=Math.max(1,Math.ceil(expanded.length/pageSize));
  const page=Math.min(Math.max(1,pageRaw),pages);
  const rows=expanded.slice((page-1)*pageSize,page*pageSize);

  const params=(overrides:Record<string,string|number|undefined>={})=>{
    const values:Record<string,string>={
      section:'orders',
      status:String(overrides.status??status),
      kind:String(overrides.kind??kind),
      filter:String(overrides.filter??filter),
      q:String(overrides.q??query),
      page:String(overrides.page??page),
    };
    return '/admin/v3?'+Object.entries(values).filter(([,v])=>v!==''&&!(v==='all'&&['filter','kind'].includes(''))).map(([k,v])=>`${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join('&');
  };
  const statusUrl=(k:AdminOrderStatusKey)=>`/admin/v3?section=orders&status=${encodeURIComponent(k)}&kind=${encodeURIComponent(kind)}&filter=${encodeURIComponent(filter)}${query?`&q=${encodeURIComponent(query)}`:''}`;
  const kindUrl=(k:AdminOrderKind)=>`/admin/v3?section=orders&status=${encodeURIComponent(status)}&kind=${encodeURIComponent(k)}&filter=${encodeURIComponent(filter)}${query?`&q=${encodeURIComponent(query)}`:''}`;
  const pageUrl=(n:number)=>`/admin/v3?section=orders&status=${encodeURIComponent(status)}&kind=${encodeURIComponent(kind)}&filter=${encodeURIComponent(filter)}${query?`&q=${encodeURIComponent(query)}`:''}&page=${n}`;

  const statusBar=`<div class="order-status-tabs">${statusKeys.map(k=>`<a class="order-status-tab ${orderStatusClass(k)} ${status===k?'active':''}" href="${statusUrl(k)}"><span>${e(orderStatusLabel(k))}</span><b>${counts[k].toLocaleString('en-US')}</b></a>`).join('')}</div>`;
  const filters=`<div class="card"><form method="get" action="/admin/v3" class="order-filterbar">
    <input type="hidden" name="section" value="orders"><input type="hidden" name="status" value="${e(status)}"><input type="hidden" name="kind" value="${e(kind)}">
    <input name="q" value="${e(query)}" placeholder="Enter search value...">
    <select name="filter">
      <option value="all" ${filter==='all'?'selected':''}>All fields</option>
      <option value="system_id" ${filter==='system_id'?'selected':''}>VELIXEO order ID</option>
      <option value="link" ${filter==='link'?'selected':''}>Order link</option>
      <option value="service_id" ${filter==='service_id'?'selected':''}>Service ID / API service ID</option>
      <option value="provider_order_id" ${filter==='provider_order_id'?'selected':''}>Provider API order ID</option>
      <option value="date" ${filter==='date'?'selected':''}>Creation date</option>
      <option value="username" ${filter==='username'?'selected':''}>Username / full name</option>
      <option value="email" ${filter==='email'?'selected':''}>User email</option>
      <option value="phone" ${filter==='phone'?'selected':''}>User phone</option>
      <option value="offer" ${filter==='offer'?'selected':''}>Service / offer</option>
    </select>
    <button class="btn">Search</button><a class="btn ghost reset" href="/admin/v3?section=orders&status=${encodeURIComponent(status)}&kind=${encodeURIComponent(kind)}">Reset</a>
  </form><div class="order-kinds">${(['all','social','refill','dripfeed'] as AdminOrderKind[]).map(k=>`<a class="order-kind ${kind===k?'active':''}" href="${kindUrl(k)}">${k==='all'?'All order types':k==='social'?'Social':k==='refill'?'Refill':'Drip-feed'}</a>`).join('')}</div></div>`;

  return `${statusBar}${filters}${professionalOrdersTable(rows,expanded.length,page,pages,pageUrl)}`;
}

async function payments(p:PrismaClient,q:string){
  const search=q.trim();
  const [tx,wallets,pending,paid,userMatches]=await Promise.all([
    p.paymentTransaction.findMany({include:{user:true,provider:true},orderBy:{createdAt:'desc'},take:160}),
    p.wallet.aggregate({_sum:{balanceAfn:true}}),
    p.paymentTransaction.count({where:{status:PaymentStatus.PENDING}}),
    p.paymentTransaction.aggregate({where:{status:PaymentStatus.PAID},_sum:{amountAfn:true}}),
    search?p.user.findMany({
      where:{OR:[
        {fullName:{contains:search,mode:'insensitive'}},
        {email:{contains:search,mode:'insensitive'}},
        {phone:{contains:search,mode:'insensitive'}},
      ]},
      include:{wallet:true},
      orderBy:{createdAt:'desc'},
      take:20,
    }):Promise.resolve([]),
  ]);
  const base=(process.env.PUBLIC_BASE_URL||'').replace(/\/$/,'');
  const has=Boolean(process.env.HESABPAY_API_KEY?.trim());
  const registeredWebhook=process.env.HESABPAY_REGISTERED_WEBHOOK_URL
    || 'https://afghanfollower1.com/afghanfollower1/afghan-payments/v1/hesabpay/webhook';
  const internalWebhook=base?`${base}/api/v1/payments/hesabpay/webhook`:'Set PUBLIC_BASE_URL';

  const walletSearch=`<div class="card">
    <div class="cardhead"><div><h2>Manual Wallet Adjustment</h2><span class="muted">Credit or debit a user wallet with a ledger and audit record.</span></div>${pill('AFN only','info')}</div>
    <form method="get" action="/admin/v3" class="actions" style="margin-bottom:12px">
      <input type="hidden" name="section" value="payments">
      <input name="q" value="${e(search)}" placeholder="Search name, email or phone" style="min-width:260px;height:38px;border:1px solid #e3eaf3;border-radius:8px;padding:0 10px">
      <button class="btn">Search User</button>
    </form>
    ${search?(
      userMatches.length?userMatches.map(u=>`<div class="provider" style="grid-template-columns:minmax(180px,1fr) auto">
        <div><b>${e(u.fullName||'—')}</b><small>${e(u.email||u.phone||'—')} · Balance: ${money(u.wallet?.balanceAfn||0n)}</small></div>
        <form method="post" action="/admin/v3/wallet" class="actions" style="justify-content:flex-end">
          <input type="hidden" name="userId" value="${u.id}">
          <input type="hidden" name="returnSection" value="payments">
          <input type="hidden" name="returnQ" value="${e(search)}">
          <select name="operation" style="height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 8px">
            <option value="ADD">Add</option>
            <option value="DEDUCT">Deduct</option>
          </select>
          <input name="amountAfn" type="number" min="1" step="1" placeholder="Amount AFN" required style="width:115px;height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 8px">
          <input name="reason" minlength="3" maxlength="300" placeholder="Reason" required style="min-width:160px;height:34px;border:1px solid #e3eaf3;border-radius:8px;padding:0 8px">
          <button class="btn">Apply</button>
        </form>
      </div>`).join(''):'<div class="empty">No matching users found.</div>'
    ):'<div class="notice">Search a user first. Every manual balance change is recorded in Wallet Ledger and Audit Log.</div>'}
  </div>`;

  return `<div class="stats">
    <div class="stat"><div class="sicon">${ico('wallet')}</div><div><small>Total User Wallets</small><strong>${money(wallets._sum.balanceAfn||0n)}</strong></div></div>
    <div class="stat"><div class="sicon">${ico('orders')}</div><div><small>Pending Payments</small><strong>${pending}</strong></div></div>
    <div class="stat"><div class="sicon">${ico('wallet')}</div><div><small>Total Paid</small><strong>${money(paid._sum.amountAfn||0n)}</strong></div></div>
    <div class="stat"><div class="sicon">${ico('settings')}</div><div><small>HesabPay</small><strong style="font-size:14px">${has?'Configured':'API key missing'}</strong></div></div>
  </div>
  <div class="grid eq">
    <div class="card">
      <div class="cardhead"><h2>HesabPay Gateway</h2>${has?pill('Ready','ok'):pill('Key missing','warn')}</div>
      <div class="field"><label>Environment</label><input readonly value="${e(process.env.HESABPAY_ENVIRONMENT||'production')}"></div>
      <div class="field"><label>Public Base URL</label><input class="mono" readonly value="${e(base||'Not configured')}"></div>
      <div class="field"><label>Registered HesabPay Webhook</label><input class="mono" readonly value="${e(registeredWebhook)}"></div>
      <div class="field"><label>VELIXEO Internal Receiver</label><input class="mono" readonly value="${e(internalWebhook)}"></div>
      <div class="notice"><b>Shared webhook mode:</b> HesabPay stays registered to the WordPress webhook above. AOP handles AOP-* payments, AF NUMBER handles AFN-* payments, and the WordPress relay forwards only VLX-* payments to the internal VELIXEO receiver.<br><b>API key:</b> Railway still needs the same HesabPay key as <span class="mono">HESABPAY_API_KEY</span>. Secrets are never shown here.</div>
    </div>
    <div class="card"><div class="cardhead"><h2>Wallet Ledger</h2>${pill('Base currency: AFN','info')}</div><p class="muted">Deposits, purchases, refunds and manual adjustments are ledger-backed. USD and Toman are display conversions only.</p></div>
  </div>
  ${walletSearch}
  <div class="card"><div class="cardhead"><h2>Gateway Transactions</h2><span class="muted">Latest ${tx.length}</span></div><div class="tablewrap"><table class="table"><thead><tr><th>User</th><th>Gateway</th><th>Amount</th><th>Status</th><th>Reference</th><th>Created</th></tr></thead><tbody>${tx.map(x=>`<tr><td>${e(x.user.fullName||x.user.email||x.user.phone||'—')}</td><td>${e(x.gateway)}</td><td class="money">${money(x.amountAfn)}</td><td>${state(x.status)}</td><td class="mono">${e(x.externalId||x.referenceId||'—')}</td><td>${dt(x.createdAt)}</td></tr>`).join('')||'<tr><td colspan="6" class="empty">No transactions.</td></tr>'}</tbody></table></div></div>`;
}
async function coupons(p:PrismaClient){const rows=await p.coupon.findMany({orderBy:{createdAt:'desc'},take:160});return `<div class="grid"><div class="card"><div class="cardhead"><h2>Coupons</h2>${pill(`${rows.length}`,'info')}</div><div class="tablewrap"><table class="table"><thead><tr><th>Code</th><th>Type</th><th>Value</th><th>Usage</th><th>Status</th></tr></thead><tbody>${rows.map(x=>`<tr><td class="mono"><b>${e(x.code)}</b></td><td>${e(x.discountType)}</td><td>${e(x.discountValue.toString())}</td><td>${x.usedCount}/${x.usageLimit??'∞'}</td><td>${x.active?pill('Active','ok'):pill('Disabled','bad')}</td></tr>`).join('')}</tbody></table></div></div><div class="card"><div class="cardhead"><h2>Create Coupon</h2><span class="muted">Fixed AFN or Percent</span></div><form method="post" action="/admin/v3/coupon"><div class="forms"><div class="field"><label>Code</label><input class="mono" name="code" required></div><div class="field"><label>Title</label><input name="title"></div><div class="field"><label>Discount Type</label><select name="discountType"><option>FIXED_AFN</option><option>PERCENT</option></select></div><div class="field"><label>Discount Value</label><input name="discountValue" required></div><div class="field"><label>Minimum Order AFN</label><input type="number" name="minOrderAfn" value="0"></div><div class="field"><label>Usage Limit</label><input type="number" name="usageLimit"></div></div><label class="check"><input type="checkbox" name="active" checked> Active</label><button class="btn">Create Coupon</button></form></div></div>`}
async function banners(p:PrismaClient){const rows=await p.banner.findMany({orderBy:[{enabled:'desc'},{sortOrder:'asc'}]});return `<div class="grid"><div class="card"><div class="cardhead"><h2>App Banners</h2>${pill(`${rows.length}`,'info')}</div>${rows.map(x=>`<div class="provider" style="grid-template-columns:58px 1fr auto"><div style="width:56px;height:36px;border-radius:8px;background:#eef5fb url('${e(x.imageUrl)}') center/cover"></div><div><b>${e(x.titleEn||x.titleFa||x.placement)}</b><small>${e(x.placement)} · ${e(x.subtitleEn||x.subtitleFa||'No subtitle')}</small></div>${x.enabled?pill('Active','ok'):pill('Hidden','bad')}</div>`).join('')||'<div class="empty">No banners.</div>'}</div><div class="card"><div class="cardhead"><div><h2>Create Banner</h2><span class="muted">Recommended Social banner: 1080×420 px (JPG or PNG)</span></div>${pill('2.57:1','info')}</div><form method="post" action="/admin/v3/banner"><div class="field"><label>Placement</label><select name="placement">${Object.values(BannerPlacement).map(x=>`<option ${x==='SERVICES_TOP'?'selected':''}>${x}</option>`).join('')}</select></div><div class="forms"><div class="field"><label>English Title</label><input name="titleEn" placeholder="Better social services, all in one place"></div><div class="field"><label>Persian Title</label><input name="titleFa" placeholder="خدمات بهتر شبکه‌های اجتماعی، همه در یک‌جا"></div></div><div class="forms"><div class="field"><label>English Subtitle</label><input name="subtitleEn"></div><div class="field"><label>Persian Subtitle</label><input name="subtitleFa"></div></div><div class="field"><label>Image URL</label><input class="mono" name="imageUrl" required placeholder="https://.../social-banner.jpg"></div><div class="forms"><div class="field"><label>English CTA</label><input name="actionLabelEn"></div><div class="field"><label>Persian CTA</label><input name="actionLabelFa"></div></div><div class="field"><label>Action URL</label><input class="mono" name="actionUrl" placeholder="velixeo://social"></div><div class="field"><label>Sort Order</label><input type="number" name="sortOrder" value="100"></div><label class="check"><input type="checkbox" name="enabled" checked> Active</label><button class="btn">Create Banner</button></form></div></div>`}
async function notifications(p:PrismaClient){
  const now=new Date(),today=new Date(now);today.setUTCHours(0,0,0,0);
  const [rows,users,total,todayCount,scheduled,devices,reads,pushAgg]=await Promise.all([
    p.notification.findMany({include:{user:true,_count:{select:{reads:true}}},orderBy:{createdAt:'desc'},take:140}),
    p.user.findMany({where:{status:UserStatus.ACTIVE},orderBy:{createdAt:'desc'},take:350,select:{id:true,fullName:true,email:true,phone:true}}),
    p.notification.count(),
    p.notification.count({where:{createdAt:{gte:today}}}),
    p.notification.count({where:{enabled:true,publishAt:{gt:now}}}),
    p.pushDevice.count({where:{enabled:true}}),
    p.notificationRead.count(),
    p.notification.aggregate({_sum:{pushTotal:true,pushSent:true,pushFailed:true}}),
  ]);
  const userOptions=users.map(u=>`<option value="${e(u.id)}">${e(u.fullName||u.email||u.phone||sid(u.id))} · ${e(u.email||u.phone||sid(u.id))}</option>`).join('');
  const sent=pushAgg._sum.pushSent||0,totalPush=pushAgg._sum.pushTotal||0,failed=pushAgg._sum.pushFailed||0;
  const typeIcon=(type:NotificationType)=>type===NotificationType.ORDER||type===NotificationType.REFILL||type===NotificationType.DRIPFEED?'orders':type===NotificationType.WALLET||type===NotificationType.PAYMENT?'wallet':type===NotificationType.SUPPORT?'support':type===NotificationType.PROMOTION?'banner':type===NotificationType.ACCOUNT?'users':'bell';
  const typeClass=(type:NotificationType)=>type===NotificationType.ORDER||type===NotificationType.REFILL||type===NotificationType.DRIPFEED?'order':type===NotificationType.WALLET||type===NotificationType.PAYMENT?'wallet':type===NotificationType.SUPPORT?'support':type===NotificationType.PROMOTION?'promotion':type===NotificationType.ACCOUNT?'account':'';
  const types=Object.values(NotificationType);
  return `<div class="card nhero"><div style="display:flex;align-items:center;gap:14px;position:relative;z-index:1"><div class="brandorb">${brandMark}</div><div><h2>VELIXEO Notification Center</h2><p>Segmented push + in-app delivery with deep links, scheduling, read tracking and Android channels.</p></div></div><div class="nmetrics"><div class="nmetric"><small>Total notifications</small><b>${total.toLocaleString('en-US')}</b></div><div class="nmetric"><small>Published today</small><b>${todayCount.toLocaleString('en-US')}</b></div><div class="nmetric"><small>Active devices</small><b>${devices.toLocaleString('en-US')}</b></div><div class="nmetric"><small>Push delivered</small><b>${sent.toLocaleString('en-US')}</b></div></div></div>
  <div class="grid"><div><div class="card"><div class="cardhead"><div><h2>Recent Notifications</h2><span class="muted">${scheduled} scheduled · ${reads} reads · ${failed} push failures</span></div>${firebasePushConfigured()?pill('FCM live','ok'):pill('Push setup pending','warn')}</div>
  ${rows.map(x=>`<div class="nrow"><div class="nicon ${typeClass(x.type)}">${ico(typeIcon(x.type))}</div><div><b>${e(x.titleEn||x.titleFa)}</b><small>${e(x.bodyEn||x.bodyFa)}</small><small>${e(x.audience)}${x.user?` · ${e(x.user.fullName||x.user.email||x.user.phone||sid(x.user.id))}`:''} · ${dt(x.publishAt)}${x.actionRoute?` · → ${e(x.actionRoute)}`:''}</small></div><div class="nmeta">${pill(x.type,'info')}${x.publishAt>now?pill('Scheduled','warn'):x.enabled?pill('Live','ok'):pill('Disabled','bad')}${pill(`${x.pushSent}/${x.pushTotal} push`,x.pushFailed?'warn':'')}${pill(`${x._count.reads} read`)}</div></div>`).join('')||'<div class="empty">No notifications yet.</div>'}
  </div></div>
  <div><div class="card"><div class="cardhead"><div><h2>Create Notification</h2><span class="muted">Professional multi-channel composer</span></div>${pill('Push + In-app','info')}</div><form method="post" action="/admin/v3/notification">
  <div class="forms"><div class="field"><label>Audience</label><select name="audience"><option value="ALL">All users</option><option value="USER">One user</option></select></div><div class="field"><label>Target user</label><select name="userId"><option value="">Choose a user (only for One user)</option>${userOptions}</select></div>
  <div class="field"><label>Notification Type</label><select name="type">${types.map(x=>`<option value="${x}">${e(x.replaceAll('_',' '))}</option>`).join('')}</select></div><div class="field"><label>Priority</label><select name="priority"><option value="NORMAL">Normal</option><option value="HIGH">High</option><option value="LOW">Low</option></select></div></div>
  <div class="forms"><div class="field"><label>Deep-link Route</label><select name="actionRoute"><option value="notifications">Notifications</option><option value="orders">Orders</option><option value="wallet">Wallet</option><option value="support">Support</option><option value="payments">Payments</option><option value="services">Services</option><option value="profile">Profile</option><option value="home">Home</option></select></div><div class="field"><label>Entity ID (optional)</label><input class="mono" name="actionEntityId" placeholder="Order / ticket / payment ID"></div></div>
  <div class="routehint"><span>ORDER → Orders</span><span>WALLET → Wallet</span><span>SUPPORT → Support</span><span>PROMOTION → Home/Services</span></div>
  <div class="forms"><div class="field"><label>English Title</label><input name="titleEn" maxlength="120" required></div><div class="field"><label>Persian Title</label><input name="titleFa" maxlength="120" required></div></div>
  <div class="field"><label>English Body</label><textarea name="bodyEn" maxlength="1000" required></textarea></div><div class="field"><label>Persian Body</label><textarea name="bodyFa" maxlength="1000" required></textarea></div>
  <div class="forms"><div class="field"><label>English CTA (optional)</label><input name="actionLabelEn" placeholder="View order"></div><div class="field"><label>Persian CTA (optional)</label><input name="actionLabelFa" placeholder="مشاهده سفارش"></div><div class="field"><label>Publish at (optional)</label><input type="datetime-local" name="publishAt"></div><div class="field"><label>Expires at (optional)</label><input type="datetime-local" name="expiresAt"></div></div>
  <div class="field"><label>Hero image URL (optional)</label><input name="imageUrl" inputmode="url" placeholder="https://..."></div>
  <button class="btn" style="width:100%;height:42px">Publish / Schedule Notification</button></form></div>
  <div class="preview-phone"><div class="preview-screen"><div class="muted" style="margin:2px 2px 10px">Live design preview</div><div class="preview-note"><div style="display:flex;gap:9px;align-items:center"><div class="mark">${brandMark}</div><div><b>VELIXEO</b><small style="display:block;color:#7a8b9d;margin-top:2px">Smart notification · deep link ready</small></div></div><div style="font-size:11px;font-weight:800;margin-top:11px">Your update will appear here</div><div class="muted" style="line-height:1.5;margin-top:4px">Users receive a branded card in-app and a category-specific Android push.</div></div></div></div></div></div>`;
}

async function support(p:PrismaClient,id:string){const rows=await p.supportTicket.findMany({include:{user:true},orderBy:{lastMessageAt:'desc'},take:120});const x=id?await p.supportTicket.findUnique({where:{id},include:{user:true,messages:{include:{senderUser:true},orderBy:{createdAt:'asc'}}}}):null;return `<div class="grid"><div class="card"><div class="cardhead"><h2>Support Tickets</h2>${pill(`${rows.length}`,'info')}</div>${rows.map(y=>`<a href="${href('support',`&ticket=${y.id}`)}" class="provider" style="grid-template-columns:1fr auto;text-decoration:none"><div><b>${e(y.subject)}</b><small>${e(y.user.fullName||y.user.email||'—')} · ${dt(y.lastMessageAt)}</small></div>${state(y.status)}</a>`).join('')||'<div class="empty">No tickets.</div>'}</div><div class="card">${x?`<div class="cardhead"><div><h2>${e(x.subject)}</h2><span class="muted">${e(x.user.fullName||x.user.email||'—')}</span></div>${state(x.status)}</div><div style="max-height:410px;overflow:auto">${x.messages.map(m=>`<div style="background:${m.isAdmin?'#eaf5ff':'#f5f7fa'};border-radius:9px;padding:9px 10px;margin:7px 0"><b style="font-size:9px">${m.isAdmin?'Admin':e(m.senderUser?.fullName||'User')}</b><div style="font-size:10px;margin-top:4px;white-space:pre-wrap">${e(m.content)}</div><small class="muted">${dt(m.createdAt)}</small></div>`).join('')}</div><form method="post" action="/admin/v3/support"><input type="hidden" name="ticketId" value="${x.id}"><div class="field"><label>Reply</label><textarea name="content" required></textarea></div><div class="forms"><div class="field"><label>New Status</label><select name="status">${Object.values(SupportStatus).map(s=>`<option ${s==='PENDING_USER'?'selected':''}>${s}</option>`).join('')}</select></div><div style="display:flex;align-items:end"><button class="btn" style="width:100%;margin-bottom:9px">Send Reply</button></div></div></form>`:'<div class="empty">Select a ticket to open the conversation.</div>'}</div></div>`}
async function settings(p:PrismaClient){const rows=await p.exchangeRate.findMany({orderBy:{code:'asc'}}),get=(x:string)=>rows.find(y=>y.code===x)?.afnPerUnit.toString()||'';return `<div class="grid eq"><div class="card"><div class="cardhead"><h2>Exchange Rates</h2>${pill('Base: AFN','info')}</div><p class="muted">Accounting remains in AFN. USD and Toman are display conversions.</p><form method="post" action="/admin/v3/rates"><div class="field"><label>1 USD = AFN</label><input name="usd" value="${e(get('USD'))}" required></div><div class="field"><label>1 TOMAN = AFN</label><input name="toman" value="${e(get('TOMAN'))}" required></div><button class="btn">Save Rates</button></form></div><div class="card"><div class="cardhead"><h2>Production Readiness</h2><span class="muted">Secrets are never shown</span></div><div class="provider" style="grid-template-columns:1fr auto"><div><b>Provider Secret Encryption</b><small>ADMIN_SECRET_ENCRYPTION_KEY</small></div>${providerSecretEncryptionConfigured()?pill('Configured','ok'):pill('Missing','bad')}</div><div class="provider" style="grid-template-columns:1fr auto"><div><b>HesabPay API</b><small>HESABPAY_API_KEY</small></div>${process.env.HESABPAY_API_KEY?pill('Configured','ok'):pill('Missing','warn')}</div><div class="provider" style="grid-template-columns:1fr auto"><div><b>Public Base URL</b><small class="mono">${e(process.env.PUBLIC_BASE_URL||'Not set')}</small></div>${process.env.PUBLIC_BASE_URL?pill('Ready','ok'):pill('Missing','warn')}</div><div class="provider" style="grid-template-columns:1fr auto"><div><b>Firebase Push</b><small>FCM service account + Android client config</small></div>${firebasePushConfigured()?pill('Server configured','ok'):pill('Missing config','warn')}</div></div></div>`}
async function auditPage(p:PrismaClient){const rows=await p.adminAuditLog.findMany({include:{adminUser:true},orderBy:{createdAt:'desc'},take:260});return `<div class="card"><div class="cardhead"><h2>Audit Log</h2>${pill(`${rows.length} recent events`,'info')}</div><div class="tablewrap"><table class="table"><thead><tr><th>Time</th><th>Admin</th><th>Action</th><th>Entity</th><th>Summary</th></tr></thead><tbody>${rows.map(x=>`<tr><td>${dt(x.createdAt)}</td><td>${e(x.adminUser.fullName||x.adminUser.email||'Admin')}</td><td class="mono">${e(x.action)}</td><td>${e(x.entityType)} ${x.entityId?sid(x.entityId):''}</td><td>${e(x.summary)}</td></tr>`).join('')}</tbody></table></div></div>`}

export function registerAdminV3(app:FastifyInstance,p:PrismaClient,resolve:AdminResolver){
 app.get('/admin/v3',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const s=qstate(req);try{let body='',tabs='';if(s.section==='dashboard')body=await dashboard(p);else if(s.section==='users')body=await usersPage(p,s.q,s.edit);else if(s.section==='referrals')body=await referralsPage(p);else if(s.section==='social'){const r=await socialPage(p,s.tab,s.q,s.edit,s.provider,s.route);body=r.body;tabs=r.tabs}else if(s.section==='virtual'){const r=await virtualModule(p,s.tab,s.edit);body=r.body;tabs=r.tabs}else if(s.section==='premium'){const r=await genericModule(p,'premium',ServiceCategory.PREMIUM,ProviderKind.PREMIUM,s.tab,s.edit);body=r.body;tabs=r.tabs}else if(s.section==='topup'){const r=await genericModule(p,'topup',ServiceCategory.MOBILE_TOPUP,ProviderKind.TOPUP,s.tab,s.edit);body=r.body;tabs=r.tabs}else if(s.section==='accounts'){const r=await genericModule(p,'accounts',ServiceCategory.DIGITAL_ACCOUNT,ProviderKind.GENERIC,s.tab,s.edit);body=r.body;tabs=r.tabs}else if(s.section==='promotions'){const r=await genericModule(p,'promotions',ServiceCategory.PROMOTION,ProviderKind.GENERIC,s.tab,s.edit);body=r.body;tabs=r.tabs}else if(s.section==='orders'){tabs='';body=await allOrders(p,s.q,s.status,s.filter,s.kind,s.page);}else if(s.section==='payments')body=await payments(p,s.q);else if(s.section==='coupons')body=await coupons(p);else if(s.section==='banners')body=await banners(p);else if(s.section==='notifications')body=await notifications(p);else if(s.section==='support')body=await support(p,s.ticket);else if(s.section==='settings')body=await settings(p);else body=await auditPage(p);return rep.type('text/html; charset=utf-8').send(shell(a,s.section,body,tabs,s.msg,s.err))}catch(err){req.log.error(err);return rep.type('text/html; charset=utf-8').send(shell(a,s.section,'<div class="card empty">This section could not be loaded. The error was recorded in server logs.</div>',tabs,err instanceof Error?err.message:'load_failed',true))}});
 app.post('/admin/v3/virtual/banner',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body;
  try{
   const id=t(b,'id'),imageUrl=t(b,'imageUrl');
   if(imageUrl.length<5)throw new Error('Banner image URL is required');
   const data={
    placement:BannerPlacement.SERVICES_TOP,
    titleEn:t(b,'titleEn')||null,
    titleFa:t(b,'titleFa')||null,
    subtitleEn:t(b,'subtitleEn')||null,
    subtitleFa:t(b,'subtitleFa')||null,
    imageUrl,
    actionLabelEn:null,
    actionLabelFa:null,
    actionUrl:'velixeo://virtual-numbers',
    enabled:c(b,'enabled'),
    sortOrder:i(b.sortOrder,10),
   };
   const saved=id
    ?await p.banner.update({where:{id},data})
    :await p.banner.create({data});
   await audit(p,a.id,id?'VIRTUAL_BANNER_UPDATE':'VIRTUAL_BANNER_CREATE','Banner',saved.id,'Virtual Numbers entry banner',{imageUrl:saved.imageUrl,enabled:saved.enabled} as unknown as Prisma.InputJsonValue);
   return rep.code(303).redirect(href('virtual',`&tab=banner&msg=${encodeURIComponent('Virtual Numbers banner saved')}`));
  }catch(err){
   return rep.code(303).redirect(href('virtual',`&tab=banner&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'virtual_banner_failed')}`));
  }
 });
 app.post('/admin/v3/referral-settings',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body;
  try{
   const raw=Number(t(b,'rewardPercent')||'0');
   if(!Number.isFinite(raw)||raw<0||raw>100)throw new Error('Commission percentage must be between 0 and 100');
   const value={enabled:c(b,'enabled'),rewardPercent:Math.round(raw*100)/100,rewardTrigger:'WALLET_TOPUP' as const};
   await saveReferralSettings(p,value);
   await audit(p,a.id,'REFERRAL_SETTINGS_UPDATE','ReferralProgram',null,`enabled=${value.enabled}, commission=${value.rewardPercent}% of verified top-ups`,value as unknown as Prisma.InputJsonValue);
   return rep.code(303).redirect(href('referrals',`&msg=${encodeURIComponent('Referral commission settings saved')}`));
  }catch(err){return rep.code(303).redirect(href('referrals',`&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'referral_settings_failed')}`))}
 });
 app.post('/admin/v3/provider',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body,section=String(b.section||'social') as Section;try{const id=t(b,'id'),kind=String(b.kind) as ProviderKind,name=t(b,'name'),sl=t(b,'slug').toLowerCase();if(!name||!sl||!Object.values(ProviderKind).includes(kind))throw new Error('Invalid provider data');const data={name,slug:sl,kind,baseUrl:t(b,'baseUrl')||null,priority:i(b.priority,100),defaultMarkupPercent:new Prisma.Decimal(t(b,'markup')||'0'),timeoutSeconds:Math.max(5,Math.min(120,i(b.timeout,30))),notes:t(b,'notes')||null,enabled:c(b,'enabled')};const x=id?await p.provider.update({where:{id},data}):await p.provider.create({data});await audit(p,a.id,id?'PROVIDER_UPDATE':'PROVIDER_CREATE','Provider',x.id,`${x.name} (${x.kind})`);return rep.code(303).redirect(href(section,`&tab=providers&edit=${x.id}&msg=${encodeURIComponent('Provider saved')}`))}catch(err){return rep.code(303).redirect(href(section,`&tab=providers&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'provider_failed')}`))}});
 app.post('/admin/v3/provider-secret',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body,section=String(b.section||'social') as Section;try{if(!providerSecretEncryptionConfigured())throw new Error('Server secret encryption is not configured');const id=t(b,'id'),secret=t(b,'secret');if(!id||!secret)throw new Error('Secret is required');const x=await p.provider.update({where:{id},data:encryptProviderSecret(secret)});await audit(p,a.id,'PROVIDER_SECRET_UPDATE','Provider',x.id,`Secret updated for ${x.name}`);return rep.code(303).redirect(href(section,`&tab=providers&edit=${x.id}&msg=${encodeURIComponent('Encrypted credential saved')}`))}catch(err){return rep.code(303).redirect(href(section,`&tab=providers&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'secret_failed')}`))}});
 app.post('/admin/v3/social/sync',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const id=t(req.body as Body,'providerId');try{const r=await syncSocialProviderCatalog(p,id);await audit(p,a.id,'SOCIAL_PROVIDER_SYNC','Provider',id,`Synced ${r.total} SMM services`,r as unknown as Prisma.InputJsonValue);return rep.code(303).redirect(href('social',`&tab=catalog&provider=${id}&msg=${encodeURIComponent(`Sync complete: ${r.total} services`)}`))}catch(err){return rep.code(303).redirect(href('social',`&tab=providers&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'sync_failed')}`))}});
 app.post('/admin/v3/social/category',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body;try{const original=t(b,'originalSlug'),s=slug(t(b,'slug')),titleEn=t(b,'titleEn'),platform=t(b,'platform');if(!s||!titleEn)throw new Error('Slug and English name are required');const value:SocialCategory={slug:s,titleEn,titleFa:t(b,'titleFa')||titleEn,platform,descriptionEn:t(b,'descriptionEn'),descriptionFa:t(b,'descriptionFa'),sortOrder:i(b.sortOrder,100),enabled:c(b,'enabled')};if(original&&original!==s)await p.systemSetting.deleteMany({where:{key:categoryKey(original)}});await p.systemSetting.upsert({where:{key:categoryKey(s)},create:{key:categoryKey(s),category:'social-category',description:'Social app category',value:value as unknown as Prisma.InputJsonValue},update:{category:'social-category',value:value as unknown as Prisma.InputJsonValue}});if(original&&original!==s)await p.service.updateMany({where:{category:ServiceCategory.SOCIAL,socialGroup:original},data:{socialGroup:s}});await audit(p,a.id,'SOCIAL_CATEGORY_SAVE','SocialCategory',s,`${platform} → ${titleEn}`);return rep.code(303).redirect(href('social',`&tab=categories&edit=${s}&msg=${encodeURIComponent('Category saved')}`))}catch(err){return rep.code(303).redirect(href('social',`&tab=categories&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'category_failed')}`))}});
 app.post('/admin/v3/social/publish',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body,routeId=t(b,'routeId'),providerId=t(b,'providerId');try{const route=await p.serviceProviderRoute.findUnique({where:{id:routeId},include:{service:true,provider:true}});if(!route||route.provider.kind!==ProviderKind.SOCIAL)throw new Error('Route not found');const cats=await categories(p),cat=cats.find(x=>x.slug===t(b,'categorySlug'));if(!cat)throw new Error('Choose a valid category');const mode=t(b,'pricingMode')==='FIXED'?'FIXED':'AUTO_MARKUP',markup=new Prisma.Decimal(t(b,'markup')||route.provider.defaultMarkupPercent.toString());let fixed:bigint|null=null;if(mode==='FIXED'){const raw=t(b,'fixedPrice');if(!raw)throw new Error('Fixed price is required');fixed=await convertSocialPriceToAfn(p,new Prisma.Decimal(raw),t(b,'fixedCurrency')||'AFN')}const old=jsonObj(route.service.metadata);await p.$transaction([p.service.update({where:{id:route.serviceId},data:{titleEn:t(b,'titleEn')||route.service.titleEn,titleFa:t(b,'titleFa')||t(b,'titleEn')||route.service.titleFa,descriptionEn:t(b,'descriptionEn')||null,descriptionFa:t(b,'descriptionFa')||null,enabled:c(b,'enabled'),sortOrder:i(b.sortOrder,route.service.sortOrder),basePriceAfn:fixed,minQty:t(b,'minQty')?i(b.minQty):route.providerMinQty,maxQty:t(b,'maxQty')?i(b.maxQty):route.providerMaxQty,socialPlatform:cat.platform,socialGroup:cat.slug,metadata:{...old,rawCatalog:false,pricingMode:mode,categorySlug:cat.slug,publishedFromProviderId:route.providerId,publishedAt:new Date().toISOString()} as Prisma.InputJsonValue}}),p.serviceProviderRoute.update({where:{id:route.id},data:{enabled:true,markupPercent:mode==='AUTO_MARKUP'?markup:null}})]);await audit(p,a.id,'SOCIAL_SERVICE_PUBLISH','Service',route.serviceId,`${t(b,'titleEn')} → ${cat.titleEn}`,{pricingMode:mode,markup:markup.toString(),fixedAfn:fixed?.toString()??null});return rep.code(303).redirect(href('social',`&tab=catalog&provider=${providerId}&route=${routeId}&msg=${encodeURIComponent('Service published to VELIXEO')}`))}catch(err){return rep.code(303).redirect(href('social',`&tab=catalog&provider=${providerId}&route=${routeId}&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'publish_failed')}`))}});
 app.post('/admin/v3/user',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body,id=t(b,'userId');if(id===a.id)return rep.code(303).redirect(href('users',`&edit=${id}&err=1&msg=${encodeURIComponent('Current admin account is protected')}`));const role=String(b.role) as UserRole,status=String(b.status) as UserStatus;if(!Object.values(UserRole).includes(role)||!Object.values(UserStatus).includes(status))return rep.code(303).redirect(href('users','&err=1&msg=Invalid access settings'));const x=await p.user.update({where:{id},data:{role,status}});await audit(p,a.id,'USER_ACCESS_UPDATE','User',x.id,`${role}/${status}`);return rep.code(303).redirect(href('users',`&edit=${x.id}&msg=${encodeURIComponent('Account saved')}`))});
 app.post('/admin/v3/phone-blacklist',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body,action=t(b,'action'),phone=t(b,'phone'),reason=t(b,'reason');
  const back=(ok:boolean,msg:string)=>rep.code(303).redirect(href('users',`&${ok?'msg':'err=1&msg'}=${encodeURIComponent(msg)}`));
  try{
   if(action==='BLOCK'){
    await blockPhonePermanently(p,phone,a.id,reason);
    await audit(p,a.id,'PHONE_PERMANENT_BLOCK','PhoneBlacklist',null,`Phone permanently blocked: ${phone}`,{phone,reason} as unknown as Prisma.InputJsonValue);
    return back(true,'Phone permanently blocked');
   }
   if(action==='UNBLOCK'){
    await unblockPhone(p,phone);
    await audit(p,a.id,'PHONE_UNBLOCK','PhoneBlacklist',null,`Phone unblocked: ${phone}`);
    return back(true,'Phone removed from blacklist');
   }
   return back(false,'Unknown blacklist action');
  }catch(err){return back(false,err instanceof Error?err.message:'phone_blacklist_failed')}
 });
 app.post('/admin/v3/user-control',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body,id=t(b,'userId'),action=t(b,'action'),reason=t(b,'reason');
  const back=(ok:boolean,msg:string)=>rep.code(303).redirect(href('users',`&edit=${encodeURIComponent(id)}&${ok?'msg':'err=1&msg'}=${encodeURIComponent(msg)}`));
  if(!id||id===a.id)return back(false,'Current admin account is protected');
  const user=await p.user.findUnique({where:{id}});
  if(!user)return back(false,'User not found');
  try{
   if(action==='TEMP_SUSPEND'){
    const hours=Math.max(1,Math.min(8760,i(b.hours,24)));
    await suspendUserTemporarily(p,id,a.id,new Date(Date.now()+hours*3600000),reason);
    await audit(p,a.id,'USER_TEMP_SUSPEND','User',id,`Suspended for ${hours} hours`,{hours,reason} as Prisma.InputJsonValue);
    return back(true,'Account temporarily suspended');
   }
   if(action==='PERM_SUSPEND'){
    await suspendUserPermanently(p,id,a.id,reason);
    await audit(p,a.id,'USER_PERM_SUSPEND','User',id,'Account permanently suspended',{reason} as Prisma.InputJsonValue);
    return back(true,'Account permanently suspended');
   }
   if(action==='RESTORE'){
    const control=await getAccountControl(p,id);
    if(control?.state==='DELETED_ADMIN'||control?.state==='DELETED_USER')return back(false,'Deleted accounts cannot be restored here');
    await restoreUserAccess(p,id);
    await audit(p,a.id,'USER_ACCESS_RESTORE','User',id,'Account access restored');
    return back(true,'Account access restored');
   }
   if(action==='BLOCK_PHONE'){
    if(!user.phone)return back(false,'User has no phone number');
    await blockPhonePermanently(p,user.phone,a.id,reason);
    await audit(p,a.id,'PHONE_PERMANENT_BLOCK','User',id,`Phone permanently blocked: ${user.phone}`,{reason} as Prisma.InputJsonValue);
    return back(true,'Phone permanently blocked');
   }
   if(action==='UNBLOCK_PHONE'){
    if(!user.phone)return back(false,'User has no phone number');
    await unblockPhone(p,user.phone);
    await audit(p,a.id,'PHONE_UNBLOCK','User',id,`Phone unblocked: ${user.phone}`);
    return back(true,'Phone removed from blacklist');
   }
   if(action==='DELETE'){
    if(t(b,'confirmText')!=='DELETE')return back(false,'Type DELETE to confirm');
    const phone=user.phone;
    await softDeleteUserAccount(p,user,'ADMIN',a.id,reason);
    await audit(p,a.id,'USER_ADMIN_DELETE','User',id,'Account soft-deleted and anonymized',{hadPhone:Boolean(phone),reason} as Prisma.InputJsonValue);
    return rep.code(303).redirect(href('users',`&msg=${encodeURIComponent('Account deleted and anonymized')}`));
   }
   return back(false,'Unknown account action');
  }catch(err){return back(false,err instanceof Error?err.message:'account_action_failed')}
 });

 app.post('/admin/v3/wallet',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body,id=t(b,'userId'),reason=t(b,'reason'),operation=t(b,'operation');
  const returnSection=t(b,'returnSection');
  const returnQ=t(b,'returnQ');
  const destination=(ok:boolean,msg:string)=>{
    const feedback=ok
      ? `&msg=${encodeURIComponent(msg)}`
      : `&err=1&msg=${encodeURIComponent(msg)}`;
    if(returnSection==='payments'){
      return href('payments',`${returnQ?`&q=${encodeURIComponent(returnQ)}`:''}${feedback}`);
    }
    return href('users',`&edit=${id}${feedback}`);
  };
  let amount:bigint;
  try{
    amount=BigInt(t(b,'amountAfn'));
    if(operation==='DEDUCT'&&amount>0n)amount=-amount;
    if(operation==='ADD'&&amount<0n)amount=-amount;
    if(amount===0n)throw new Error('Amount must be greater than zero');
  }catch{
    return rep.code(303).redirect(destination(false,'Invalid amount'));
  }
  try{
    const entry=await p.$transaction(async tx=>{
      const w=await tx.wallet.findUnique({where:{userId:id}});
      if(!w)throw new Error('Wallet not found');
      const next=w.balanceAfn+amount;
      if(next<0n)throw new Error('Insufficient balance');
      await tx.wallet.update({where:{id:w.id},data:{balanceAfn:next}});
      return tx.walletEntry.create({data:{
        walletId:w.id,
        type:amount>0n?WalletEntryType.MANUAL_CREDIT:WalletEntryType.MANUAL_DEBIT,
        status:WalletEntryStatus.COMPLETED,
        amountAfn:amount,
        balanceAfterAfn:next,
        description:reason,
        referenceType:'ADMIN_ADJUSTMENT',
        referenceId:a.id,
        idempotencyKey:`figma-${a.id}-${Date.now()}-${randomBytes(4).toString('hex')}`
      }});
    },{isolationLevel:Prisma.TransactionIsolationLevel.Serializable});
    await audit(p,a.id,'WALLET_MANUAL_ADJUST','WalletEntry',entry.id,`${amount} AFN — ${reason}`,{userId:id});
    await publishUserNotification(p,id,{
      type:NotificationType.WALLET,
      priority:NotificationPriority.HIGH,
      titleEn:amount>0n?'Wallet credited':'Wallet adjusted',
      titleFa:amount>0n?'کیف پول شما شارژ شد':'موجودی کیف پول تغییر کرد',
      bodyEn:amount>0n
        ? `${amount.toLocaleString('en-US')} AFN was added to your VELIXEO wallet.`
        : `${(-amount).toLocaleString('en-US')} AFN was deducted from your VELIXEO wallet.`,
      bodyFa:amount>0n
        ? `${amount.toLocaleString('en-US')} افغانی به کیف پول VELIXEO شما اضافه شد.`
        : `${(-amount).toLocaleString('en-US')} افغانی از کیف پول VELIXEO شما کسر شد.`,
      actionRoute:'wallet',actionEntityId:entry.id,actionLabelEn:'Open wallet',actionLabelFa:'مشاهده کیف پول',
    });
    return rep.code(303).redirect(destination(true,'Wallet adjustment posted'));
  }catch(err){
    return rep.code(303).redirect(destination(false,err instanceof Error?err.message:'wallet_failed'));
  }
});
 app.post('/admin/v3/rates',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body;try{for(const [code,key] of [['USD','usd'],['TOMAN','toman']] as const){const raw=t(b,key);if(!/^\d+(\.\d{1,8})?$/.test(raw))throw new Error(`Invalid ${code} rate`);await p.exchangeRate.upsert({where:{code},update:{afnPerUnit:new Prisma.Decimal(raw)},create:{code,afnPerUnit:new Prisma.Decimal(raw)}})}await audit(p,a.id,'EXCHANGE_RATES_UPDATE','ExchangeRate',null,`USD=${t(b,'usd')}, TOMAN=${t(b,'toman')}`);return rep.code(303).redirect(href('settings','&msg=Exchange rates saved'))}catch(err){return rep.code(303).redirect(href('settings',`&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'rate_failed')}`))}});
 app.post('/admin/v3/order-status',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const b=req.body as Body,id=t(b,'id'),status=t(b,'status') as OrderStatus;
  if(!id||!Object.values(OrderStatus).includes(status))return rep.code(303).redirect(href('orders','&err=1&msg=Invalid order status'));
  const current=await p.order.findUnique({where:{id}});
  if(!current)return rep.code(303).redirect(href('orders','&err=1&msg=Order not found'));
  const output=jsonObj(current.output);
  await p.order.update({where:{id},data:{
    status,
    completedAt:status===OrderStatus.COMPLETED?(current.completedAt??new Date()):current.completedAt,
    output:{...output,adminStatusOverride:true,adminStatusOverrideValue:status,adminStatusOverrideAt:new Date().toISOString(),adminStatusOverrideBy:a.id},
  }});
  await audit(p,a.id,'ORDER_STATUS_OVERRIDE','Order',id,`Admin set order status to ${status}`);
  await publishUserNotification(p,current.userId,{
    type:NotificationType.ORDER,
    priority:(
      status===OrderStatus.COMPLETED
      || status===OrderStatus.FAILED
      || status===OrderStatus.CANCELLED
      || status===OrderStatus.REFUNDED
    ) ? NotificationPriority.HIGH : NotificationPriority.NORMAL,
    titleEn:'Order status updated',
    titleFa:'وضعیت سفارش بروزرسانی شد',
    bodyEn:`Your order ${sid(id)} is now ${status.replaceAll('_',' ')}.`,
    bodyFa:`وضعیت سفارش ${sid(id)} به ${status.replaceAll('_',' ')} تغییر کرد.`,
    actionRoute:'orders',actionEntityId:id,actionLabelEn:'View order',actionLabelFa:'مشاهده سفارش',
  });
  return rep.code(303).redirect(href('orders','&msg=Order status overridden'));
 });
 app.post('/admin/v3/order-status-provider',async(req,rep)=>{
  const a=await needAdmin(req,rep,resolve);if(!a)return;
  const id=t(req.body as Body,'id'),current=await p.order.findUnique({where:{id}});
  if(!current)return rep.code(303).redirect(href('orders','&err=1&msg=Order not found'));
  const output=jsonObj(current.output),raw=String(output.providerMappedStatus||'');
  const providerStatus=Object.values(OrderStatus).includes(raw as OrderStatus)?raw as OrderStatus:current.status;
  await p.order.update({where:{id},data:{status:providerStatus,output:{...output,adminStatusOverride:false,adminStatusOverrideValue:null,adminStatusOverrideClearedAt:new Date().toISOString(),adminStatusOverrideClearedBy:a.id}}});
  await audit(p,a.id,'ORDER_STATUS_PROVIDER_SYNC','Order',id,`Order returned to provider status ${providerStatus}`);
  return rep.code(303).redirect(href('orders','&msg=Provider status restored'));
 });

 app.post('/admin/v3/coupon',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body;try{const x=await p.coupon.create({data:{code:t(b,'code').toUpperCase(),title:t(b,'title')||null,discountType:String(b.discountType) as CouponDiscountType,discountValue:new Prisma.Decimal(t(b,'discountValue')),minOrderAfn:BigInt(t(b,'minOrderAfn')||'0'),usageLimit:t(b,'usageLimit')?i(b.usageLimit):null,active:c(b,'active')}});await audit(p,a.id,'COUPON_CREATE','Coupon',x.id,x.code);return rep.code(303).redirect(href('coupons','&msg=Coupon created'))}catch(err){return rep.code(303).redirect(href('coupons',`&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'coupon_failed')}`))}});
 app.post('/admin/v3/banner',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body;try{const x=await p.banner.create({data:{placement:String(b.placement) as BannerPlacement,titleEn:t(b,'titleEn')||null,titleFa:t(b,'titleFa')||null,subtitleEn:t(b,'subtitleEn')||null,subtitleFa:t(b,'subtitleFa')||null,imageUrl:t(b,'imageUrl'),actionLabelEn:t(b,'actionLabelEn')||null,actionLabelFa:t(b,'actionLabelFa')||null,actionUrl:t(b,'actionUrl')||null,enabled:c(b,'enabled'),sortOrder:i(b.sortOrder,100)}});await audit(p,a.id,'BANNER_CREATE','Banner',x.id,x.titleEn||x.titleFa||x.placement);return rep.code(303).redirect(href('banners','&msg=Banner created'))}catch(err){return rep.code(303).redirect(href('banners',`&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'banner_failed')}`))}});
 app.post('/admin/v3/notification',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body;try{
   const audience=String(b.audience) as NotificationAudience,userId=t(b,'userId')||null;
   const type=String(b.type||NotificationType.SYSTEM) as NotificationType;
   const priority=String(b.priority||NotificationPriority.NORMAL) as NotificationPriority;
   if(!Object.values(NotificationAudience).includes(audience))throw new Error('Invalid audience');
   if(!Object.values(NotificationType).includes(type))throw new Error('Invalid notification type');
   if(!Object.values(NotificationPriority).includes(priority))throw new Error('Invalid priority');
   if(audience===NotificationAudience.USER&&!userId)throw new Error('Choose a target user for a personal notification');
   const publishRaw=t(b,'publishAt'),expiresRaw=t(b,'expiresAt');
   const publishAt=publishRaw?new Date(publishRaw):new Date(),expiresAt=expiresRaw?new Date(expiresRaw):null;
   if(Number.isNaN(publishAt.getTime())||(expiresAt&&Number.isNaN(expiresAt.getTime())))throw new Error('Invalid publish or expiry date');
   if(expiresAt&&expiresAt<=publishAt)throw new Error('Expiry must be after publish time');
   const x=await p.notification.create({data:{
     audience,userId:audience===NotificationAudience.USER?userId:null,type,priority,
     titleEn:t(b,'titleEn'),titleFa:t(b,'titleFa'),bodyEn:t(b,'bodyEn'),bodyFa:t(b,'bodyFa'),
     actionRoute:t(b,'actionRoute')||'notifications',actionEntityId:t(b,'actionEntityId')||null,
     actionLabelEn:t(b,'actionLabelEn')||null,actionLabelFa:t(b,'actionLabelFa')||null,
     imageUrl:t(b,'imageUrl')||null,publishAt,expiresAt,enabled:true,
   }});
   let push={configured:firebasePushConfigured(),total:0,sent:0,failed:0,disabledTokens:0};
   const isDue=publishAt.getTime()<=Date.now()+1000;
   if(isDue){try{push=await dispatchNotificationPush(p,x)}catch(pushError){req.log.error(pushError,'notification push failed')}}
   await audit(p,a.id,'NOTIFICATION_CREATE','Notification',x.id,x.titleEn,{type,priority,route:x.actionRoute,publishAt:x.publishAt.toISOString(),push} as unknown as Prisma.InputJsonValue);
   const message=isDue?(push.configured?`Notification published · push ${push.sent}/${push.total}`:'Notification published · push configuration unavailable'):`Notification scheduled for ${dt(publishAt)}`;
   return rep.code(303).redirect(href('notifications',`&msg=${encodeURIComponent(message)}`))
 }catch(err){return rep.code(303).redirect(href('notifications',`&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'notification_failed')}`))}});

 app.post('/admin/v3/support',async(req,rep)=>{const a=await needAdmin(req,rep,resolve);if(!a)return;const b=req.body as Body,id=t(b,'ticketId'),content=t(b,'content'),status=String(b.status) as SupportStatus;try{
   const result=await p.$transaction([
     p.supportMessage.create({data:{ticketId:id,senderUserId:a.id,isAdmin:true,content}}),
     p.supportTicket.update({where:{id},data:{status,lastMessageAt:new Date()}}),
   ]);
   const ticket=result[1];
   await audit(p,a.id,'SUPPORT_REPLY','SupportTicket',id,content.slice(0,120));
   await publishUserNotification(p,ticket.userId,{
     type:NotificationType.SUPPORT,priority:NotificationPriority.HIGH,
     titleEn:'New support reply',titleFa:'پاسخ جدید پشتیبانی',
     bodyEn:content.length>180?`${content.slice(0,177)}...`:content,
     bodyFa:content.length>180?`${content.slice(0,177)}...`:content,
     actionRoute:'support',actionEntityId:id,actionLabelEn:'Open ticket',actionLabelFa:'مشاهده تیکت',
   });
   return rep.code(303).redirect(href('support',`&ticket=${id}&msg=Reply sent`))
  }catch(err){return rep.code(303).redirect(href('support',`&ticket=${id}&err=1&msg=${encodeURIComponent(err instanceof Error?err.message:'reply_failed')}`))}});
}
