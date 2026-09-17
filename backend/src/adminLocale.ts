import type { FastifyInstance } from 'fastify';

const translations: Record<string, string> = {
  'Dashboard': 'داشبورد',
  'Users': 'کاربران',
  'Services': 'خدمات',
  'Social Media': 'شبکه‌های اجتماعی',
  'Virtual Number & SMS': 'شماره مجازی و SMS',
  'Premium Subscriptions': 'اشتراک‌های Premium',
  'Mobile Top-up': 'شارژ سیم‌کارت',
  'Digital Accounts': 'اکانت‌های دیجیتال',
  'Promotions': 'تبلیغات',
  'Payments & Wallet': 'پرداخت و کیف پول',
  'Orders': 'سفارش‌ها',
  'Coupons': 'کدهای تخفیف',
  'Banners & Advertising': 'بنرها و تبلیغات',
  'Notifications': 'اعلان‌ها',
  'Support': 'پشتیبانی',
  'Settings': 'تنظیمات',
  'Audit Log': 'گزارش فعالیت‌ها',
  'Overview': 'نمای کلی',
  'Providers': 'ارائه‌دهندگان',
  'Provider Services': 'فهرست خدمات ارائه‌دهنده',
  'Categories': 'دسته‌بندی‌ها',
  'My Services': 'سرویس‌های من',
  'Routing': 'مسیر‌دهی',
  'API Logs': 'لاگ‌های API',
  'Main Dashboard': 'داشبورد اصلی',
  'SMM Providers': 'ارائه‌دهندگان SMM',
  'Add Provider': 'افزودن ارائه‌دهنده',
  'Provider Name': 'نام ارائه‌دهنده',
  'Website URL': 'آدرس وب‌سایت',
  'API Endpoint / Base URL': 'آدرس API / Base URL',
  'Default Provider Currency': 'واحد پول ارائه‌دهنده',
  'Default Profit / Markup %': 'درصد سود پیش‌فرض',
  'Priority': 'اولویت',
  'Timeout (seconds)': 'مهلت اتصال (ثانیه)',
  'Auto Service Sync': 'همگام‌سازی خودکار خدمات',
  'Service Sync Interval (minutes)': 'فاصله همگام‌سازی خدمات (دقیقه)',
  'API Key / Secret': 'کلید API / Secret',
  'Description / Internal Notes': 'توضیحات / یادداشت داخلی',
  'Provider enabled': 'ارائه‌دهنده فعال باشد',
  'Save Provider': 'ذخیره ارائه‌دهنده',
  'Cancel': 'لغو',
  'Live Balance': 'موجودی زنده',
  'Currency': 'واحد پول',
  'Service Sync': 'همگام‌سازی خدمات',
  'Connection': 'اتصال',
  'Active': 'فعال',
  'Actions': 'عملیات',
  'Enabled': 'فعال',
  'Disabled': 'غیرفعال',
  'Connected': 'متصل',
  'Provider Catalog': 'کاتالوگ ارائه‌دهنده',
  'Get / Refresh Services': 'دریافت / بروزرسانی خدمات',
  'Choose provider': 'انتخاب ارائه‌دهنده',
  'Original Service Name': 'نام اصلی سرویس',
  'Provider Category': 'دسته ارائه‌دهنده',
  'Provider Cost': 'قیمت ارائه‌دهنده',
  'VELIXEO Sale': 'قیمت فروش VELIXEO',
  'Min / Max': 'حداقل / حداکثر',
  'Refill': 'جبران ریزش',
  'Cancel': 'لغو',
  'App Status': 'وضعیت در اپ',
  'Add': 'افزودن',
  'Add Service to VELIXEO': 'افزودن سرویس به VELIXEO',
  'Edit VELIXEO Service': 'ویرایش سرویس VELIXEO',
  'VELIXEO Category': 'دسته‌بندی VELIXEO',
  'Customer-facing English Name': 'نام انگلیسی برای کاربر',
  'English Description': 'توضیحات انگلیسی',
  'Pricing Mode': 'حالت قیمت‌گذاری',
  'Profit / Markup %': 'درصد سود',
  'Fixed Sale Price': 'قیمت فروش ثابت',
  'Fixed Price Currency': 'واحد قیمت ثابت',
  'Minimum Quantity': 'حداقل تعداد',
  'Maximum Quantity': 'حداکثر تعداد',
  'Sort Order': 'ترتیب نمایش',
  'Refill / Guarantee Days': 'روزهای ضمانت / جبران',
  'Featured service': 'سرویس ویژه',
  'Visible to users immediately': 'فوراً به کاربران نمایش داده شود',
  'Add to VELIXEO': 'افزودن به VELIXEO',
  'Save Changes': 'ذخیره تغییرات',
  'Social Categories': 'دسته‌بندی‌های شبکه اجتماعی',
  'Add Category': 'افزودن دسته‌بندی',
  'Edit Category': 'ویرایش دسته‌بندی',
  'Category Slug': 'شناسه دسته',
  'Platform Key': 'شناسه شبکه',
  'English Category Name': 'نام انگلیسی دسته',
  'Persian Category Name (optional for now)': 'نام فارسی دسته',
  'Category Structure': 'ساختار دسته‌بندی',
  'Platform': 'شبکه',
  'App Status': 'وضعیت اپ',
  'Visible': 'نمایش داده شود',
  'Hidden': 'مخفی',
  'Live': 'فعال',
  'Draft / Hidden': 'پیش‌نویس / مخفی',
  'Auto Markup': 'قیمت‌گذاری خودکار',
  'Fixed': 'ثابت',
  'Search': 'جستجو',
  'Add from Provider': 'افزودن از ارائه‌دهنده',
  'VELIXEO Service': 'سرویس VELIXEO',
  'Provider': 'ارائه‌دهنده',
  'Pricing': 'قیمت‌گذاری',
  'Status': 'وضعیت',
  'English': 'English',
  'Persian': 'فارسی'
};

function localeInjection() {
  const dictionary = JSON.stringify(translations).replaceAll('<', '\\u003c');
  return `<style id="velixeo-admin-locale-style">
  .vx-locale{position:fixed;right:18px;bottom:18px;z-index:99999;background:#fff;border:1px solid #dfe8f1;border-radius:12px;padding:5px;display:flex;gap:4px;box-shadow:0 8px 30px rgba(20,60,100,.12)}
  .vx-locale button{border:0;border-radius:8px;padding:7px 10px;background:transparent;color:#61758b;font:600 11px Inter,Arial,sans-serif;cursor:pointer}.vx-locale button.active{background:#1687f8;color:#fff}
  html[dir=rtl] .vx-locale{right:auto;left:18px}html[dir=rtl] body{direction:rtl}html[dir=rtl] .layout{grid-template-columns:minmax(0,1fr) 244px}html[dir=rtl] .side{grid-column:2}html[dir=rtl] .main{grid-column:1;grid-row:1}html[dir=rtl] .table th,html[dir=rtl] .table td{text-align:right}html[dir=rtl] .subnav{padding-left:0;padding-right:18px;border-left:0;border-right:1px solid rgba(255,255,255,.09);margin-left:0;margin-right:18px}
  @media(max-width:980px){html[dir=rtl] .layout{grid-template-columns:1fr}.side,.main{grid-column:auto!important}}
  </style><div class="vx-locale"><button type="button" data-vx-lang="en">EN</button><button type="button" data-vx-lang="fa">فارسی</button></div><script id="velixeo-admin-locale-script">(()=>{const dict=${dictionary};const reverse=Object.fromEntries(Object.entries(dict).map(([a,b])=>[b,a]));const key='velixeo_admin_lang';let lang=localStorage.getItem(key)||'en';const norm=s=>String(s||'').replace(/\\s+/g,' ').trim();function translateText(root,map){const w=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);const nodes=[];while(w.nextNode())nodes.push(w.currentNode);for(const n of nodes){const raw=n.nodeValue||'';const clean=norm(raw);if(!clean||!map[clean])continue;const lead=raw.match(/^\\s*/)?.[0]||'';const tail=raw.match(/\\s*$/)?.[0]||'';n.nodeValue=lead+map[clean]+tail;}for(const el of root.querySelectorAll('[placeholder],[title],[aria-label]')){for(const attr of ['placeholder','title','aria-label']){const v=el.getAttribute(attr);const clean=norm(v);if(clean&&map[clean])el.setAttribute(attr,map[clean]);}}}function apply(next){const current=document.documentElement.dataset.vxLang||'en';if(current!==next)translateText(document.body,next==='fa'?dict:reverse);lang=next;localStorage.setItem(key,next);document.documentElement.dataset.vxLang=next;document.documentElement.lang=next==='fa'?'fa':'en';document.documentElement.dir=next==='fa'?'rtl':'ltr';document.querySelectorAll('[data-vx-lang]').forEach(b=>b.classList.toggle('active',b.dataset.vxLang===next));}document.addEventListener('click',e=>{const b=e.target.closest('[data-vx-lang]');if(b)apply(b.dataset.vxLang);});if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>apply(lang));else apply(lang);})();</script>`;
}

export function registerAdminLocale(app: FastifyInstance) {
  app.addHook('onSend', async (request, reply, payload) => {
    const url = request.raw.url || '';
    if (!url.startsWith('/admin/v3')) return payload;
    const contentType = String(reply.getHeader('content-type') || '');
    if (!contentType.includes('text/html') || typeof payload !== 'string') return payload;
    if (payload.includes('velixeo-admin-locale-script')) return payload;
    return payload.replace('</body>', `${localeInjection()}</body>`);
  });
}
