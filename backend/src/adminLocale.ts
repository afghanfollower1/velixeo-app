import type { FastifyInstance, FastifyRequest } from 'fastify';

const translations: Record<string, string> = {
  // Global navigation / shell
  'Dashboard': 'داشبورد',
  'Main Dashboard': 'داشبورد اصلی',
  'Business overview and today’s performance': 'نمای کلی کسب‌وکار و عملکرد امروز',
  'Users': 'کاربران',
  'Accounts, access and wallet management': 'مدیریت حساب‌ها، دسترسی و کیف پول',
  'Invite Friends': 'دعوت دوستان',
  'Referral links, rewards and invited-user tracking': 'لینک‌های دعوت، پاداش‌ها و پیگیری کاربران دعوت‌شده',
  'Services': 'خدمات',
  'Social Media': 'شبکه‌های اجتماعی',
  'Providers, catalog, categories, pricing and routing': 'ارائه‌دهندگان، کاتالوگ، دسته‌بندی‌ها، قیمت‌گذاری و مسیریابی',
  'Virtual Number & SMS': 'شماره مجازی و پیامک',
  'Providers, services, countries, pricing and SMS orders': 'ارائه‌دهندگان، سرویس‌ها، کشورها، قیمت‌گذاری و سفارش‌های پیامکی',
  'Premium Subscriptions': 'اشتراک‌های پریمیوم',
  'Products, providers and subscription orders': 'محصولات، ارائه‌دهندگان و سفارش‌های اشتراک',
  'Mobile Top-up': 'شارژ سیم‌کارت',
  'Operators, products, providers and top-up orders': 'اپراتورها، محصولات، ارائه‌دهندگان و سفارش‌های شارژ',
  'Digital Accounts': 'اکانت‌های دیجیتال',
  'Digital products, stock and delivery': 'محصولات دیجیتال، موجودی و تحویل',
      'Payments & Wallet': 'پرداخت‌ها و کیف پول',
  'Gateways, transactions, user wallets and refunds': 'درگاه‌ها، تراکنش‌ها، کیف پول کاربران و بازپرداخت‌ها',
  'Orders': 'سفارش‌ها',
  'All customer orders across VELIXEO': 'تمام سفارش‌های مشتریان در VELIXEO',
  'Coupons': 'کدهای تخفیف',
  'Discount rules and coupon usage': 'قوانین تخفیف و میزان استفاده از کدها',
  'Banners': 'بنرها',
  'App banners, placements and CTA routes': 'بنرهای اپ، محل نمایش و مسیر دکمه‌ها',
  'Save changes': 'ذخیره تغییرات',
  'Delete banner': 'حذف بنر',
  'Active / visible in app': 'فعال / قابل نمایش در اپ',
  'Image URL (optional)': 'آدرس تصویر (اختیاری)',
  'Account Security': 'امنیت حساب',
  'Same verification state shown in the mobile app': 'همان وضعیت تأییدی که در اپ موبایل نمایش داده می‌شود',
  'Secure': 'امن',
  'Needs attention': 'نیاز به تکمیل',
  'Two-factor': 'ورود دومرحله‌ای',
  'Not verified': 'تأیید نشده',
  'Verified': 'تأیید شده',

  'Notifications': 'اعلان‌ها',
  'In-app announcements and user messages': 'اعلان‌های داخل اپ و پیام‌های کاربران',
  'Support': 'پشتیبانی',
  'Tickets, conversations and resolution': 'تیکت‌ها، گفتگوها و رسیدگی',
  'Settings': 'تنظیمات',
  'Exchange rates, languages, security and system status': 'نرخ ارز، زبان‌ها، امنیت و وضعیت سیستم',
  'Audit Log': 'گزارش فعالیت‌ها',
  'Trace all administrative changes and sensitive actions': 'ثبت تمام تغییرات مدیریتی و عملیات حساس',
  'Program active': 'برنامه فعال است',
  'Program disabled': 'برنامه غیرفعال است',
  'No reason': 'بدون دلیل ثبت‌شده',
  'No endpoint': 'Endpoint تنظیم نشده',
  'Not configured': 'تنظیم نشده',
  'Not set': 'تعیین نشده',
  'Server configured': 'سرور تنظیم شده',
  'No subtitle': 'بدون زیرعنوان',
  'FCM live': 'FCM فعال',
  'Push + In-app': 'Push + داخل اپ',
  'Edit Published Service': 'ویرایش سرویس منتشرشده',
  'New Category': 'دسته‌بندی جدید',
  'Choose a service, country and live operator to receive SMS verification codes.': 'برای دریافت کد پیامکی، سرویس، کشور و اپراتور زنده را انتخاب کنید.',
  'Saving…': 'در حال ذخیره…',
  'Use PNG, JPG or WebP.': 'از PNG، JPG یا WebP استفاده کنید.',
  'Icon is still too large. Please choose a simpler image.': 'حجم آیکن هنوز زیاد است؛ تصویر ساده‌تری انتخاب کنید.',
  'Could not save all changes:': 'ذخیره همه تغییرات ممکن نشد:',
  'Virtual Numbers entry banner': 'بنر ورودی شماره‌های مجازی',
  'Virtual Numbers banner saved': 'بنر شماره‌های مجازی ذخیره شد',
  'Commission percentage must be between 0 and 100': 'درصد کمیسیون باید بین ۰ تا ۱۰۰ باشد',
  'Referral commission settings saved': 'تنظیمات کمیسیون دعوت ذخیره شد',
  'Encrypted credential saved': 'اطلاعات اتصال رمزگذاری‌شده ذخیره شد',
  'Slug and English name are required': 'Slug و نام انگلیسی الزامی است',
  'Category saved': 'دسته‌بندی ذخیره شد',
  'Route not found': 'مسیر ارائه‌دهنده پیدا نشد',
  'Fixed price is required': 'قیمت ثابت الزامی است',
  'Current admin account is protected': 'حساب مدیر فعلی محافظت‌شده است',
  'Account saved': 'حساب ذخیره شد',
  'Phone removed from blacklist': 'شماره از فهرست سیاه حذف شد',
  'Unknown blacklist action': 'عملیات فهرست سیاه نامعتبر است',
  'User not found': 'کاربر پیدا نشد',
  'Account temporarily suspended': 'حساب موقتاً تعلیق شد',
  'Account permanently suspended': 'حساب برای همیشه تعلیق شد',
  'Deleted accounts cannot be restored here': 'حساب‌های حذف‌شده از این بخش قابل بازیابی نیستند',
  'Account access restored': 'دسترسی حساب بازیابی شد',
  'User has no phone number': 'کاربر شماره تلفن ندارد',
  'Account soft-deleted and anonymized': 'حساب حذف نرم و ناشناس‌سازی شد',
  'Account deleted and anonymized': 'حساب حذف و ناشناس‌سازی شد',
  'Unknown account action': 'عملیات حساب نامعتبر است',
  'Amount must be greater than zero': 'مبلغ باید بیشتر از صفر باشد',
  'Wallet not found': 'کیف پول پیدا نشد',
  'Insufficient balance': 'موجودی کافی نیست',
  'Wallet credited': 'کیف پول شارژ شد',
  'Wallet adjusted': 'موجودی کیف پول اصلاح شد',
  'Open wallet': 'باز کردن کیف پول',
  'Wallet adjustment posted': 'اصلاح موجودی ثبت شد',
  'Order status updated': 'وضعیت سفارش به‌روزرسانی شد',
  'Choose a target user for a personal notification': 'برای اعلان شخصی، کاربر مقصد را انتخاب کنید',
  'Expiry must be after publish time': 'زمان انقضا باید بعد از زمان انتشار باشد',
  'Notification published · push configuration unavailable': 'اعلان منتشر شد · تنظیمات Push در دسترس نیست',
  'New support reply': 'پاسخ جدید پشتیبانی',
  'Open ticket': 'باز کردن تیکت',
  'Order not found': 'سفارش پیدا نشد',
  'The requested VELIXEO order could not be found.': 'سفارش درخواستی VELIXEO پیدا نشد.',
  'Back to orders': 'بازگشت به سفارش‌ها',
  'Customer Amount': 'مبلغ مشتری',
  'VELIXEO sale': 'فروش VELIXEO',
  'Provider Cost': 'هزینه ارائه‌دهنده',
  'Recorded cost': 'هزینه ثبت‌شده',
  'Gross Margin': 'حاشیه ناخالص',
  'Sale − provider cost': 'فروش منهای هزینه ارائه‌دهنده',
  'Quantity': 'تعداد',
  'Order & Service': 'سفارش و سرویس',
  'VELIXEO Order ID': 'شناسه سفارش VELIXEO',
  'Provider API Order ID': 'شناسه سفارش API ارائه‌دهنده',
  'Target / Link': 'هدف / لینک',
  'Completed': 'تکمیل',
  'Customer': 'مشتری',
  'Real account data': 'اطلاعات واقعی حساب',
  'User ID': 'شناسه کاربر',
  'Admin status control': 'کنترل وضعیت توسط مدیر',
  'Customer / Provider Input': 'ورودی مشتری / ارائه‌دهنده',
  'Stored order payload': 'داده ذخیره‌شده سفارش',
  'Provider Output': 'خروجی ارائه‌دهنده',
  'Latest stored provider data': 'آخرین داده ذخیره‌شده ارائه‌دهنده',
  'Order Action Log': 'گزارش عملیات سفارش',
  'Provider Reference': 'مرجع ارائه‌دهنده',
  'No order actions recorded yet.': 'هنوز عملیاتی برای این سفارش ثبت نشده است.',
  'Search in admin panel...': 'جستجو در پنل مدیریت...',
  'System Administrator': 'مدیر سیستم',
  'Sign out': 'خروج',
  'Management': 'مدیریت',
  'Overview': 'نمای کلی',
  'Status': 'وضعیت',
  'Actions': 'عملیات',
  'Action': 'عملیات',
  'Edit': 'ویرایش',
  'Save': 'ذخیره',
  'Cancel': 'لغو',
  'Search': 'جستجو',
  'Reset': 'بازنشانی',
  'Apply': 'اعمال',
  'Add': 'افزودن',
  'Remove': 'حذف',
  'New': 'جدید',
  'Created': 'ایجاد شده',
  'Updated': 'به‌روزرسانی شده',
  'Time': 'زمان',
  'Type': 'نوع',
  'Title': 'عنوان',
  'Description': 'توضیحات',
  'Name': 'نام',
  'Code': 'کد',
  'Value': 'مقدار',
  'Role': 'نقش',
  'Phone': 'شماره تلفن',
  'Email': 'ایمیل',
  'User': 'کاربر',
  'Provider': 'ارائه‌دهنده',
  'Providers': 'ارائه‌دهندگان',
  'Service': 'سرویس',
  'Product': 'محصول',
  'Products': 'محصولات',
  'Category': 'دسته‌بندی',
  'Group': 'گروه',
  'Platform': 'پلتفرم',
  'Currency': 'واحد پول',
  'Priority': 'اولویت',
  'Price': 'قیمت',
  'Cost': 'هزینه',
  'Sale': 'فروش',
  'Amount': 'مبلغ',
  'Reference': 'مرجع',
  'Environment': 'محیط',
  'Preview': 'پیش‌نمایش',
  'Visible': 'نمایش داده شود',
  'Hidden': 'مخفی',
  'Enabled': 'فعال',
  'Disabled': 'غیرفعال',
  'Active': 'فعال',
  'Live': 'فعال',
  'Published': 'منتشر شده',
  'Pending': 'در انتظار',
  'Processing': 'در حال انجام',
  'Cancelled': 'لغو شده',
  'Refunded': 'بازپرداخت شده',
  'Failed': 'ناموفق',
  'High': 'زیاد',
  'Normal': 'عادی',
  'Low': 'کم',
  'Today': 'امروز',
  'Previous': 'قبلی',
  'Next': 'بعدی',
  'View all': 'مشاهده همه',
  'View order': 'مشاهده سفارش',
  'Manage': 'مدیریت',
  'Profile': 'پروفایل',
  'Home': 'خانه',
  'Wallet': 'کیف پول',
  'Payments': 'پرداخت‌ها',
  'Routing': 'مسیریابی',
  'Pricing': 'قیمت‌گذاری',
  'Countries': 'کشورها',
  'Brands': 'برندها',
  'Categories': 'دسته‌بندی‌ها',
  'API Logs': 'لاگ‌های API',
  'Provider Catalog': 'کاتالوگ ارائه‌دهنده',
  'Provider Services': 'سرویس‌های ارائه‌دهنده',
  'My Services': 'سرویس‌های من',
  'My Published Services': 'سرویس‌های منتشرشده من',
  'Production Readiness': 'آمادگی محیط تولید',

  // Common forms
  'English': 'انگلیسی',
  'Persian': 'فارسی',
  'English Title': 'عنوان انگلیسی',
  'Persian Title': 'عنوان فارسی',
  'English title': 'عنوان انگلیسی',
  'Persian title': 'عنوان فارسی',
  'English Name': 'نام انگلیسی',
  'Persian Name': 'نام فارسی',
  'English Description': 'توضیحات انگلیسی',
  'Persian Description': 'توضیحات فارسی',
  'English description': 'توضیحات انگلیسی',
  'Persian description': 'توضیحات فارسی',
  'English Subtitle': 'زیرعنوان انگلیسی',
  'Persian Subtitle': 'زیرعنوان فارسی',
  'English subtitle': 'زیرعنوان انگلیسی',
  'Persian subtitle': 'زیرعنوان فارسی',
  'English Body': 'متن انگلیسی',
  'Persian Body': 'متن فارسی',
  'English CTA': 'دکمه انگلیسی',
  'Persian CTA': 'دکمه فارسی',
  'English CTA (optional)': 'دکمه انگلیسی (اختیاری)',
  'Persian CTA (optional)': 'دکمه فارسی (اختیاری)',
  'English label': 'برچسب انگلیسی',
  'Persian label': 'برچسب فارسی',
  'English placeholder': 'متن راهنمای انگلیسی',
  'Persian placeholder': 'متن راهنمای فارسی',
  'English badge': 'نشان انگلیسی',
  'Persian badge': 'نشان فارسی',
  'English duration': 'مدت انگلیسی',
  'Persian duration': 'مدت فارسی',
  'English customer message': 'پیام انگلیسی برای مشتری',
  'Persian customer message': 'پیام فارسی برای مشتری',
  'English instructions before purchase': 'راهنمای انگلیسی قبل از خرید',
  'Persian instructions before purchase': 'راهنمای فارسی قبل از خرید',
  'Slug': 'شناسه لاتین',
  'Sort Order': 'ترتیب نمایش',
  'Sort order': 'ترتیب نمایش',
  'Display order': 'ترتیب نمایش',
  'Featured': 'ویژه',
  'Featured service': 'سرویس ویژه',
  'Required': 'اجباری',
  'Optional admin reason': 'دلیل مدیر (اختیاری)',
  'Reason': 'دلیل',
  'Internal Notes': 'یادداشت داخلی',
  'Description / Internal Notes': 'توضیحات / یادداشت داخلی',
  'Website URL': 'آدرس وب‌سایت',
  'Image URL': 'لینک تصویر',
  'Icon URL': 'لینک آیکن',
  'Product icon URL (optional)': 'لینک آیکن محصول (اختیاری)',
  'Hero image URL (optional)': 'لینک تصویر اصلی (اختیاری)',
  'Banner Image URL': 'لینک تصویر بنر',
  'Banner image URL (optional)': 'لینک تصویر بنر (اختیاری)',
  'Action URL': 'لینک عملیات',
  'Deep Link': 'لینک داخلی',
  'Deep link': 'لینک داخلی',
  'Deep-link Route': 'مسیر لینک داخلی',
  'Entity ID (optional)': 'شناسه مورد (اختیاری)',
  'Order / ticket / payment ID': 'شناسه سفارش / تیکت / پرداخت',
  'Publish at (optional)': 'زمان انتشار (اختیاری)',
  'Expires at (optional)': 'زمان انقضا (اختیاری)',
  'Target user': 'کاربر هدف',
  'Audience': 'مخاطب',
  'All users': 'همه کاربران',
  'One user': 'یک کاربر',
  'Choose a user (only for One user)': 'یک کاربر انتخاب کنید (فقط برای حالت یک کاربر)',
  'Notification Type': 'نوع اعلان',
  'New Status': 'وضعیت جدید',

  // Dashboard
  'Total Users': 'کل کاربران',
  'Orders Today': 'سفارش‌های امروز',
  'Sales Today': 'فروش امروز',
  'Net Profit': 'سود خالص',
  'Live database': 'دیتابیس زنده',
  'Valid orders': 'سفارش‌های معتبر',
  'Sales − provider cost': 'فروش منهای هزینه ارائه‌دهنده',
  'Sales Overview': 'نمای کلی فروش',
  'Last 30 days': '۳۰ روز گذشته',
  'Daily': 'روزانه',
  'Weekly': 'هفتگی',
  'Monthly': 'ماهانه',
  'Service Distribution': 'توزیع سرویس‌ها',
  'Total Sales': 'کل فروش',
  'Recent Orders': 'سفارش‌های اخیر',
  'Provider Status': 'وضعیت ارائه‌دهنده',
  'No sales data yet.': 'هنوز داده فروشی وجود ندارد.',
  'No orders yet.': 'هنوز سفارشی ثبت نشده است.',
  'No providers configured.': 'هنوز ارائه‌دهنده‌ای تنظیم نشده است.',

  // Users / access
  'User Directory': 'فهرست کاربران',
  'Name, email or phone': 'نام، ایمیل یا شماره تلفن',
  'Access & Safety Controls': 'کنترل دسترسی و امنیت',
  'Account Management': 'مدیریت حساب',
  'Save Account': 'ذخیره حساب',
  'Temporary block (hours)': 'تعلیق موقت (ساعت)',
  'Temporarily suspend': 'تعلیق موقت',
  'Permanent suspend': 'تعلیق دائمی',
  'Restore access': 'بازگردانی دسترسی',
  'Administrative deletion': 'حذف توسط مدیر',
  'Delete account permanently': 'حذف دائمی حساب',
  'Delete account': 'حذف حساب',
  'Type DELETE to confirm': 'برای تأیید، DELETE را وارد کنید',
  'Permanent Phone Blacklist': 'فهرست سیاه دائمی شماره‌ها',
  'Independent from account deletion': 'مستقل از حذف حساب',
  'Phone number (international)': 'شماره تلفن (بین‌المللی)',
  'Why this phone is blocked': 'دلیل مسدودسازی این شماره',
  'Block phone permanently': 'مسدودسازی دائمی شماره',
  'Block this phone permanently': 'این شماره را برای همیشه مسدود کن',
  'Phone permanently blocked': 'شماره برای همیشه مسدود شده است',
  'Permanent phone blacklist reason': 'دلیل مسدودسازی دائمی شماره',
  'Unblock': 'رفع مسدودی',
  'Unblock phone': 'رفع مسدودی شماره',
  'Blocked at': 'زمان مسدودسازی',
  'This account has no phone number to blacklist.': 'این حساب شماره‌ای برای افزودن به فهرست سیاه ندارد.',
  'No matching users found.': 'کاربر مطابق پیدا نشد.',
  'No permanently blocked phone numbers.': 'شماره مسدودشده دائمی وجود ندارد.',

  // Wallet / payments
  'Manual Wallet Adjustment': 'تغییر دستی کیف پول',
  'Credit or debit a user wallet with a ledger and audit record.': 'افزایش یا کاهش موجودی کاربر همراه با ثبت در دفتر کل و گزارش مدیریتی.',
  'Search User': 'جستجوی کاربر',
  'Search name, email or phone': 'جستجوی نام، ایمیل یا شماره تلفن',
  'Amount AFN': 'مبلغ به افغانی',
  'Post to Ledger': 'ثبت در دفتر کل',
  'Recent Wallet Activity': 'فعالیت اخیر کیف پول',
  'Wallet Ledger': 'دفتر کل کیف پول',
  'Wallet Adjustment': 'تغییر موجودی کیف پول',
  'Total User Wallets': 'مجموع موجودی کیف پول کاربران',
  'Pending Payments': 'پرداخت‌های در انتظار',
  'Gateway Transactions': 'تراکنش‌های درگاه',
  'HesabPay Gateway': 'درگاه حساب‌پی',
  'Registered HesabPay Webhook': 'وب‌هوک ثبت‌شده حساب‌پی',
  'VELIXEO Internal Receiver': 'گیرنده داخلی VELIXEO',
  'Shared webhook mode:': 'حالت وب‌هوک مشترک:',
  'Deposits, purchases, refunds and manual adjustments are ledger-backed. USD and Toman are display conversions only.': 'واریز، خرید، بازپرداخت و تغییرات دستی همگی در دفتر کل ثبت می‌شوند. دلار و تومان فقط برای نمایش تبدیل می‌شوند.',
  'Search a user first. Every manual balance change is recorded in Wallet Ledger and Audit Log.': 'ابتدا کاربر را جستجو کنید. هر تغییر دستی موجودی در دفتر کل کیف پول و گزارش فعالیت‌ها ثبت می‌شود.',
  'No wallet entries.': 'هیچ رکوردی در کیف پول وجود ندارد.',
  'No transactions.': 'هیچ تراکنشی وجود ندارد.',

  // Orders
  'Customer Orders': 'سفارش‌های مشتریان',
  'Full order, provider and delivery information': 'اطلاعات کامل سفارش، ارائه‌دهنده و تحویل',
  'All fields': 'همه فیلدها',
  'Enter search value...': 'مقدار جستجو را وارد کنید...',
  'VELIXEO order ID': 'شناسه سفارش VELIXEO',
  'Order link': 'لینک سفارش',
  'Service ID / API service ID': 'شناسه سرویس / شناسه سرویس API',
  'Provider API order ID': 'شناسه سفارش API ارائه‌دهنده',
  'Creation date': 'تاریخ ایجاد',
  'Username / full name': 'نام کاربری / نام کامل',
  'User email': 'ایمیل کاربر',
  'User phone': 'شماره کاربر',
  'Service / offer': 'سرویس / پیشنهاد',
  'All order types': 'همه انواع سفارش',
  'Social': 'شبکه اجتماعی',
  'Drip-feed': 'ارسال زمان‌بندی‌شده',
  'VELIXEO ID': 'شناسه VELIXEO',
  'Provider API ID': 'شناسه API ارائه‌دهنده',
  'Service / Provider': 'سرویس / ارائه‌دهنده',
  'Link': 'لینک',
  'Qty': 'تعداد',
  'Start / Remains': 'شروع / باقی‌مانده',
  'Start': 'شروع',
  'Remains': 'باقی‌مانده',
  'Admin': 'مدیر',
  'Managed by Drip-feed': 'مدیریت‌شده توسط ارسال زمان‌بندی‌شده',
  'Admin Override': 'تغییر دستی مدیر',
  'No orders found for this filter.': 'برای این فیلتر سفارشی پیدا نشد.',
  'No orders found.': 'سفارشی پیدا نشد.',
  'Awaiting action': 'در انتظار اقدام',
  'Manual orders': 'سفارش‌های دستی',
  'Queued': 'در صف',
  'In progress': 'در حال انجام',
  'Partial': 'نیمه‌کامل',
  'Unpaid': 'پرداخت‌نشده',
  'Awaiting cancel': 'در انتظار لغو',

  // Social
  'Social Media Control Center': 'مرکز مدیریت شبکه‌های اجتماعی',
  'Providers, live pricing, categories and customer services in one workspace.': 'ارائه‌دهندگان، قیمت‌گذاری زنده، دسته‌بندی‌ها و سرویس‌های مشتری در یک بخش.',
  'SMM Providers': 'ارائه‌دهندگان SMM',
  'Add Provider': 'افزودن ارائه‌دهنده',
  'Provider Name': 'نام ارائه‌دهنده',
  'API Endpoint / Base URL': 'آدرس API / آدرس پایه',
  'Default Provider Currency': 'واحد پول پیش‌فرض ارائه‌دهنده',
  'Default Profit / Markup %': 'درصد سود پیش‌فرض',
  'Priority (lower = first)': 'اولویت (عدد کمتر = زودتر)',
  'Timeout seconds': 'مهلت اتصال (ثانیه)',
  'Provider enabled': 'ارائه‌دهنده فعال باشد',
  'New API Key / Secret': 'کلید API / Secret جدید',
  'New API Key / Token': 'کلید API / Token جدید',
  'Encrypted API Credential': 'اطلاعات API رمزگذاری‌شده',
  'Encrypted Credential': 'اطلاعات ورود رمزگذاری‌شده',
  'Save Encrypted Secret': 'ذخیره کلید رمزگذاری‌شده',
  'Save Secret': 'ذخیره کلید',
  'Saved secrets are never displayed again.': 'کلیدهای ذخیره‌شده دوباره نمایش داده نمی‌شوند.',
  'Secrets are never shown here.': 'کلیدهای محرمانه در این بخش نمایش داده نمی‌شوند.',
  'Connection': 'اتصال',
  'Connected': 'متصل',
  'API key needed': 'کلید API لازم است',
  'Connection error': 'خطای اتصال',
  'Get / Refresh Services': 'دریافت / بروزرسانی سرویس‌ها',
  'Choose provider': 'انتخاب ارائه‌دهنده',
  'Original Service Name': 'نام اصلی سرویس',
  'Provider Category': 'دسته‌بندی ارائه‌دهنده',
  'VELIXEO Sale': 'قیمت فروش VELIXEO',
  'Min / Max': 'حداقل / حداکثر',
  'Refill': 'جبران',
  'App Status': 'وضعیت در اپ',
  'Add Service to VELIXEO': 'افزودن سرویس به VELIXEO',
  'Edit VELIXEO Service': 'ویرایش سرویس VELIXEO',
  'VELIXEO Category': 'دسته‌بندی VELIXEO',
  'Customer-facing English Name': 'نام انگلیسی قابل نمایش برای مشتری',
  'Pricing Mode': 'حالت قیمت‌گذاری',
  'Profit / Markup %': 'درصد سود',
  'Fixed Sale Price': 'قیمت فروش ثابت',
  'Fixed Price Currency': 'واحد قیمت ثابت',
  'Minimum Quantity': 'حداقل تعداد',
  'Maximum Quantity': 'حداکثر تعداد',
  'Refill / Guarantee Days': 'روزهای ضمانت / جبران',
  'Visible to users immediately': 'فوراً برای کاربران نمایش داده شود',
  'Add to VELIXEO': 'افزودن به VELIXEO',
  'Save Changes': 'ذخیره تغییرات',
  'Social Categories': 'دسته‌بندی‌های شبکه اجتماعی',
  'Add Category': 'افزودن دسته‌بندی',
  'Edit Category': 'ویرایش دسته‌بندی',
  'Category Slug': 'شناسه دسته‌بندی',
  'Platform Key': 'شناسه پلتفرم',
  'English Category Name': 'نام انگلیسی دسته‌بندی',
  'Persian Category Name (optional for now)': 'نام فارسی دسته‌بندی',
  'Category Structure': 'ساختار دسته‌بندی',
  'Choose brand': 'انتخاب برند',
  'Draft / Hidden': 'پیش‌نویس / مخفی',
  'Auto Markup': 'سود خودکار',
  'Fixed': 'ثابت',
  'Add from Provider': 'افزودن از ارائه‌دهنده',
  'VELIXEO Service': 'سرویس VELIXEO',
  'Open catalog': 'باز کردن کاتالوگ',
  'Sync a provider to load services.': 'برای بارگذاری سرویس‌ها، ارائه‌دهنده را همگام‌سازی کنید.',
  'No SMM provider yet.': 'هنوز ارائه‌دهنده SMM اضافه نشده است.',
  'No routes yet.': 'هنوز مسیری ثبت نشده است.',

  // Virtual numbers
  'Virtual Numbers Entry Banner': 'بنر ورودی شماره‌های مجازی',
  'Shown at the top every time the Virtual Numbers section opens': 'هر بار که بخش شماره مجازی باز شود در بالای صفحه نمایش داده می‌شود',
  'Save Virtual Banner': 'ذخیره بنر شماره مجازی',
  'Mobile crop preview': 'پیش‌نمایش برش موبایل',
  'The app uses a lightweight image decode and keeps the fallback hero visible if the network image fails.': 'اپ تصویر را به‌صورت سبک بارگذاری می‌کند و اگر تصویر شبکه باز نشود، بنر جایگزین نمایش داده می‌شود.',
  '5SIM / Virtual Number Providers': 'ارائه‌دهندگان 5SIM / شماره مجازی',
  'This workspace is isolated from Social Media. Only VIRTUAL_NUMBER providers, services and orders are used here.': 'این بخش از شبکه‌های اجتماعی جداست و فقط ارائه‌دهندگان، سرویس‌ها و سفارش‌های شماره مجازی در آن استفاده می‌شوند.',
  'Encrypted 5SIM Credential': 'کلید رمزگذاری‌شده 5SIM',
  'The API token stays server-side and is never sent to the app.': 'توکن API فقط روی سرور نگهداری می‌شود و هرگز به اپ ارسال نمی‌شود.',
  'New 5SIM API token / secret': 'توکن API / Secret جدید 5SIM',
  'Virtual Number Services': 'سرویس‌های شماره مجازی',
  'All 5SIM products are synchronized automatically': 'تمام محصولات 5SIM به‌صورت خودکار همگام‌سازی می‌شوند',
  'Icons & ordering:': 'آیکن‌ها و ترتیب نمایش:',
  'Bulk icon & display-order editor': 'ویرایش گروهی آیکن و ترتیب نمایش',
  'Save all changes': 'ذخیره همه تغییرات',
  'Search service name, slug or 5SIM code…': 'جستجوی نام سرویس، شناسه یا کد 5SIM…',
  'All visibility': 'همه وضعیت‌های نمایش',
  'Visible only': 'فقط نمایش‌داده‌شده‌ها',
  'Hidden only': 'فقط مخفی‌ها',
  'All icons': 'همه آیکن‌ها',
  'Missing icon': 'بدون آیکن',
  'Uploaded icon': 'آیکن آپلودشده',
  'Icon & display order': 'آیکن و ترتیب نمایش',
  '5SIM Route': 'مسیر 5SIM',
  'Individual pricing': 'قیمت‌گذاری اختصاصی',
  'Upload icon': 'آپلود آیکن',
  'Remove icon': 'حذف آیکن',
  'Leave Fixed AFN empty for percentage pricing.': 'برای قیمت‌گذاری درصدی، قیمت ثابت افغانی را خالی بگذارید.',
  'Sync the 5SIM provider to load all products.': 'برای بارگذاری تمام محصولات، ارائه‌دهنده 5SIM را همگام‌سازی کنید.',
  'No service matches this search/filter.': 'هیچ سرویسی با این جستجو/فیلتر مطابقت ندارد.',
  'Enable all services': 'فعال‌سازی همه سرویس‌ها',
  'Disable all services': 'غیرفعال‌سازی همه سرویس‌ها',
  'Global Virtual Number Profit': 'سود کلی شماره مجازی',
  'Global profit / markup (%)': 'درصد سود کلی',
  'Apply to all virtual services': 'اعمال روی همه سرویس‌های شماره مجازی',
  'Currency conversion and profit settings here affect Virtual Numbers only. Social Media pricing is untouched.': 'تنظیمات تبدیل ارز و سود این بخش فقط روی شماره مجازی اثر دارد و قیمت‌گذاری شبکه‌های اجتماعی تغییر نمی‌کند.',
  '5SIM Cost → AFN': 'هزینه 5SIM → افغانی',
  'AFN per provider price unit': 'افغانی به ازای هر واحد قیمت ارائه‌دهنده',
  'Provider cost × AFN factor × markup': 'هزینه ارائه‌دهنده × ضریب افغانی × درصد سود',
  'Live pricing is active by design.': 'قیمت‌گذاری زنده به‌صورت پیش‌فرض فعال است.',
  'Allowed 5SIM country codes (optional)': 'کد کشورهای مجاز 5SIM (اختیاری)',
  'Empty = every country available from 5SIM': 'خالی = همه کشورهای موجود در 5SIM',
  'Save Country Restriction': 'ذخیره محدودیت کشور',
  'By default, all provider countries are shown automatically. Use this list only if you want to restrict the catalog.': 'به‌صورت پیش‌فرض همه کشورهای ارائه‌دهنده نمایش داده می‌شوند. فقط در صورت نیاز به محدودسازی از این لیست استفاده کنید.',
  'Smart Buy country logic': 'منطق خرید هوشمند کشور',

  // Premium
  'Admin Alerts': 'اعلان‌های مدیر',
  'Products & Packages': 'محصولات و پکیج‌ها',
  'Premium & Subscriptions Workspace': 'مدیریت پریمیوم و اشتراک‌ها',
  'Manual activation and manual-delivery products with wallet payment, bilingual forms and admin fulfillment.': 'محصولات با فعال‌سازی یا تحویل دستی، پرداخت کیف پول، فرم دوزبانه و انجام توسط مدیر.',
  'How this module works': 'نحوه کار این بخش',
  'No provider API required': 'بدون نیاز به API ارائه‌دهنده',
  'Product → package → dynamic customer form → wallet payment → paid order queue → Telegram admin invoice → manual fulfillment → customer notification.': 'محصول → پکیج → فرم پویا مشتری → پرداخت کیف پول → صف سفارش پرداخت‌شده → فاکتور تلگرام مدیر → انجام دستی → اعلان مشتری.',
  'Manage products & packages': 'مدیریت محصولات و پکیج‌ها',
  'Fulfillment': 'انجام سفارش',
  'Open fulfillment queue': 'باز کردن صف انجام سفارش',
  'Premium section banner': 'بنر بخش پریمیوم',
  'Shown when users enter Premium & Subscriptions.': 'هنگام ورود کاربر به بخش پریمیوم و اشتراک‌ها نمایش داده می‌شود.',
  'The app has a bilingual built-in banner even when no image is configured. Later UI/UX work can replace this image without changing product logic.': 'حتی بدون تنظیم تصویر، اپ یک بنر داخلی دوزبانه دارد. بعداً می‌توان طراحی UI/UX را بدون تغییر منطق محصول عوض کرد.',
  'Leave empty to keep the built-in gradient hero.': 'برای استفاده از بنر گرادیانی داخلی، این فیلد را خالی بگذارید.',
  'Show banner': 'نمایش بنر',
  'Save Premium banner': 'ذخیره بنر پریمیوم',
  'Logic preview — final visual design comes later': 'پیش‌نمایش منطق — طراحی نهایی بعداً انجام می‌شود',
  'Premium products': 'محصولات پریمیوم',
  'Manual packages — no provider API required.': 'پکیج‌های دستی — بدون نیاز به API ارائه‌دهنده.',
  '+ New product': '+ محصول جدید',
  'Create product': 'ایجاد محصول',
  'Edit product': 'ویرایش محصول',
  'Bilingual content + packages + dynamic customer fields': 'محتوای دوزبانه + پکیج‌ها + فیلدهای پویای مشتری',
  'Fulfillment type': 'نوع انجام سفارش',
  'Delivery from (hours)': 'شروع زمان تحویل (ساعت)',
  'Delivery up to (hours)': 'حداکثر زمان تحویل (ساعت)',
  'Packages': 'پکیج‌ها',
  'Package': 'پکیج',
  'Package ID': 'شناسه پکیج',
  'Price AFN': 'قیمت به افغانی',
  'Stock (blank = unlimited)': 'موجودی (خالی = نامحدود)',
  'Available for customers': 'برای مشتریان قابل خرید باشد',
  '+ Add package': '+ افزودن پکیج',
  'Each package has its own duration, price and optional stock.': 'هر پکیج مدت، قیمت و موجودی اختیاری مستقل دارد.',
  'Customer order form': 'فرم سفارش مشتری',
  'Customer field': 'فیلد مشتری',
  'Key': 'کلید',
  'Select options (comma-separated; SELECT only)': 'گزینه‌های انتخابی (با ویرگول جدا شود؛ فقط برای SELECT)',
  'Option A, Option B': 'گزینه A، گزینه B',
  '+ Add field': '+ افزودن فیلد',
  'Do not ask for passwords here. Use username, phone, email or custom text needed for activation.': 'در این بخش رمز عبور درخواست نکنید. فقط نام کاربری، تلفن، ایمیل یا متن لازم برای فعال‌سازی را بگیرید.',
  'Visible in app': 'در اپ نمایش داده شود',
  'Save product & packages': 'ذخیره محصول و پکیج‌ها',
  'No Premium products yet.': 'هنوز محصول پریمیومی ساخته نشده است.',
  'Premium fulfillment queue': 'صف انجام سفارش‌های پریمیوم',
  'Every order shown here has already been charged from the customer wallet.': 'هزینه تمام سفارش‌های این لیست قبلاً از کیف پول مشتری کسر شده است.',
  'Invoice': 'فاکتور',
  'Product / Package': 'محصول / پکیج',
  'Submitted data': 'اطلاعات ثبت‌شده',
  'Paid': 'پرداخت‌شده',
  'State': 'وضعیت',
  'Need information': 'نیاز به اطلاعات',
  'Reject + refund wallet': 'رد سفارش + بازپرداخت به کیف پول',
  'Secure delivery text (optional; encrypted at rest)': 'اطلاعات امن تحویل (اختیاری؛ به‌صورت رمزگذاری‌شده ذخیره می‌شود)',
  'Only use when delivering account/license details.': 'فقط برای تحویل اطلاعات اکانت یا لایسنس استفاده کنید.',
  'Update order': 'به‌روزرسانی سفارش',
  'No Premium orders yet.': 'هنوز سفارش پریمیومی ثبت نشده است.',
  'Telegram admin notifications': 'اعلان‌های تلگرام مدیر',
  'One bot for registrations, verified wallet top-ups, paid orders and refunds.': 'یک ربات برای ثبت‌نام‌ها، شارژهای تأییدشده کیف پول، سفارش‌های پرداخت‌شده و بازپرداخت‌ها.',
  'Security rule:': 'قانون امنیتی:',
  'the Bot Token is never stored in the browser or database. Set': 'توکن ربات هرگز در مرورگر یا دیتابیس ذخیره نمی‌شود. مقدار',
  'in Railway. This form only stores the destination Chat ID.': 'را در Railway تنظیم کنید. این فرم فقط Chat ID مقصد را ذخیره می‌کند.',
  'Telegram Chat ID': 'Chat ID تلگرام',
  'Enable VELIXEO admin Telegram notifications': 'فعال‌سازی اعلان‌های تلگرام مدیریت VELIXEO',
  'Save alert settings': 'ذخیره تنظیمات اعلان',
  'Send test message': 'ارسال پیام آزمایشی',
  'Notification coverage': 'پوشش اعلان‌ها',
  'Verified events only': 'فقط رویدادهای تأییدشده',
  'Bot token': 'توکن ربات',
  'Railway secret': 'متغیر محرمانه Railway',
  'Destination chat': 'چت مقصد',
  'Notifications are sent only after real events commit successfully: new registration, verified wallet credit, paid order, manual wallet adjustment or refund. Passwords, OTP codes, API keys and verification tokens are never included.': 'اعلان‌ها فقط بعد از ثبت موفق رویداد واقعی ارسال می‌شوند: ثبت‌نام جدید، شارژ تأییدشده کیف پول، سفارش پرداخت‌شده، تغییر دستی کیف پول یا بازپرداخت. رمز عبور، کد یک‌بارمصرف، کلید API و توکن‌های تأیید هرگز در پیام ارسال نمی‌شوند.',
  'Ready': 'آماده',
  'Setup needed': 'نیاز به تنظیم',
  'Open orders': 'سفارش‌های باز',
  'Paid sales': 'فروش پرداخت‌شده',
  'Manual activation': 'فعال‌سازی دستی',
  'Manual delivery': 'تحویل دستی',
  'Custom request': 'درخواست سفارشی',
  'Best value': 'بهترین انتخاب',
  'Telegram username': 'یوزرنیم تلگرام',

  // Meta / Instagram connection
  'Instagram Connections': 'اتصالات اینستاگرام',
  'Instagram connections': 'اتصالات اینستاگرام',
  'Official Meta OAuth connections. Passwords are never stored or shown here.': 'اتصالات رسمی Meta OAuth. رمز عبور هرگز ذخیره یا نمایش داده نمی‌شود.',
  'Advertising access': 'دسترسی تبلیغاتی',
  'Granted permissions': 'مجوزهای صادرشده',
  'Customer ad accounts': 'حساب‌های تبلیغاتی مشتری',
  'ADVERTISE granted': 'مجوز ADVERTISE صادر شده',
  'No ADVERTISE task': 'مجوز ADVERTISE وجود ندارد',
  'No page tasks': 'هیچ دسترسی صفحه‌ای ثبت نشده',
  'None returned': 'موردی دریافت نشد',
  'Validated': 'بررسی‌شده',
  'Meta / Instagram Login': 'ورود Meta / Instagram',
  'Needs setup': 'نیاز به تنظیم',
  'Required Railway variables': 'متغیرهای لازم Railway',
  'Current redirect URI': 'آدرس بازگشت فعلی',
  'Admin fulfillment model': 'مدل اجرای ادمین',
  'View Instagram connections': 'مشاهده اتصالات اینستاگرام',
  'Fallback only: require Partnership Ad Code when no Instagram account is connected': 'فقط روش جایگزین: اگر حساب اینستاگرام متصل نیست، کد Partnership الزامی باشد',
  'Open Instagram': 'باز کردن اینستاگرام',
  'Instagram': 'اینستاگرام',
  'Facebook Page': 'صفحه فیسبوک',
  'Media ID': 'شناسه رسانه',
  'Ad code fallback': 'کد جایگزین Partnership',

  // Service separation / coming soon
  'Premium Accounts': 'اکانت‌های پریمیوم',
  'Telegram Premium, Snapchat+ and other premium subscriptions': 'تلگرام پریمیوم، اسنپ‌چت پلاس و سایر اشتراک‌های پریمیوم',
  'Coming soon — waiting for official telecom APIs': 'به‌زودی — در انتظار API رسمی شرکت‌های مخابراتی',
  'Netflix, VPN, streaming, licenses and digital account delivery': 'نتفلیکس، VPN، سرویس‌های استریم، لایسنس‌ها و تحویل اکانت‌های دیجیتال',
  'Coming soon — telecom provider APIs are not connected yet.': 'به‌زودی — API شرکت‌های مخابراتی هنوز متصل نشده است.',
  'Coming soon.': 'به‌زودی.',
  'This module stays disabled until official mobile operator APIs are connected and tested. No top-up products or provider routes are required for now.': 'این بخش تا زمان اتصال و آزمایش API رسمی اپراتورهای موبایل غیرفعال می‌ماند. فعلاً نیازی به افزودن محصول یا مسیر Provider برای شارژ نیست.',
  'Premium Accounts Workspace': 'فضای مدیریت اکانت‌های پریمیوم',
  'Premium-only services such as Telegram Premium, Snapchat+ and similar subscriptions. Netflix, VPN and other digital accounts belong in Digital Accounts.': 'این بخش فقط برای خدمات پریمیوم مانند تلگرام پریمیوم، اسنپ‌چت پلاس و اشتراک‌های مشابه است. نتفلیکس، VPN و سایر اکانت‌های دیجیتال باید در بخش اکانت‌های دیجیتال قرار بگیرند.',

  // Referrals
  'Referral Commission Settings': 'تنظیمات کمیسیون دعوت',
  'Enable Invite Friends commission': 'فعال‌سازی کمیسیون دعوت دوستان',
  'Commission from each verified wallet top-up (%)': 'درصد کمیسیون از هر شارژ تأییدشده کیف پول',
  'Save commission settings': 'ذخیره تنظیمات کمیسیون',
  'No reward is paid for registration.': 'برای ثبت‌نام به‌تنهایی پاداشی پرداخت نمی‌شود.',
  'The referral link connects the two accounts; commission follows real verified top-ups.': 'لینک دعوت دو حساب را به هم متصل می‌کند و کمیسیون فقط از شارژهای واقعی و تأییدشده محاسبه می‌شود.',
  'Referral Activity': 'فعالیت دعوت‌ها',
  'Latest 500 referral relationships': '۵۰۰ رابطه دعوت اخیر',
  'Inviter': 'دعوت‌کننده',
  'Invitee': 'دعوت‌شده',
  'Commission rate': 'نرخ کمیسیون',
  'Verified top-ups': 'شارژهای تأییدشده',
  'Commission paid': 'کمیسیون پرداخت‌شده',
  'Total referrals': 'کل دعوت‌ها',
  'Invited accounts': 'حساب‌های دعوت‌شده',
  'Total commission paid': 'کل کمیسیون پرداخت‌شده',
  'No referral activity yet.': 'هنوز فعالیت دعوتی ثبت نشده است.',

  // Coupons / banners
  'Create Coupon': 'ایجاد کد تخفیف',
  'Discount Type': 'نوع تخفیف',
  'Discount Value': 'مقدار تخفیف',
  'Minimum Order AFN': 'حداقل سفارش به افغانی',
  'Usage Limit': 'محدودیت استفاده',
  'Usage': 'تعداد استفاده',
  'Fixed AFN or Percent': 'مبلغ ثابت یا درصد',
  'Create Banner': 'ایجاد بنر',
  'App Banners': 'بنرهای اپ',
  'Placement': 'محل نمایش',
  'Server-driven; no APK update': 'کنترل‌شده از سرور؛ بدون نیاز به آپدیت APK',
  'No banners.': 'هیچ بنری وجود ندارد.',

  // Notifications
  'VELIXEO Notification Center': 'مرکز اعلان‌های VELIXEO',
  'Segmented push + in-app delivery with deep links, scheduling, read tracking and Android channels.': 'ارسال هدفمند پوش + اعلان داخل اپ همراه با لینک داخلی، زمان‌بندی، وضعیت خواندن و کانال‌های اندروید.',
  'Total notifications': 'کل اعلان‌ها',
  'Published today': 'منتشرشده امروز',
  'Active devices': 'دستگاه‌های فعال',
  'Push delivered': 'پوش‌های ارسال‌شده',
  'Recent Notifications': 'اعلان‌های اخیر',
  'Create Notification': 'ایجاد اعلان',
  'Professional multi-channel composer': 'ساخت حرفه‌ای اعلان چندکاناله',
  'Publish / Schedule Notification': 'انتشار / زمان‌بندی اعلان',
  'Live design preview': 'پیش‌نمایش زنده طراحی',
  'Smart notification · deep link ready': 'اعلان هوشمند · آماده لینک داخلی',
  'Your update will appear here': 'اعلان شما اینجا نمایش داده می‌شود',
  'Users receive a branded card in-app and a category-specific Android push.': 'کاربران کارت برندشده داخل اپ و پوش اندروید متناسب با دسته دریافت می‌کنند.',
  'No notifications yet.': 'هنوز اعلانی وجود ندارد.',

  // Support
  'Support Tickets': 'تیکت‌های پشتیبانی',
  'Select a ticket to open the conversation.': 'برای باز کردن گفتگو یک تیکت را انتخاب کنید.',
  'Reply': 'پاسخ',
  'Send Reply': 'ارسال پاسخ',
  'No tickets.': 'هیچ تیکتی وجود ندارد.',

  // Settings
  'Exchange Rates': 'نرخ ارز',
  'Base: AFN': 'واحد پایه: افغانی',
  'All provider costs are normalized to AFN for accounting. Customers can display prices in AFN, USD or Toman from the app profile.': 'تمام هزینه‌های ارائه‌دهندگان برای حسابداری به افغانی تبدیل می‌شوند. کاربران می‌توانند قیمت را از پروفایل اپ به افغانی، دلار یا تومان نمایش دهند.',
  '1 USD = AFN': '۱ دلار = افغانی',
  '1 TOMAN = AFN': '۱ تومان = افغانی',
  'Save Display Rates': 'ذخیره نرخ‌های نمایشی',
  'Add / Update Provider Currency': 'افزودن / بروزرسانی واحد پول ارائه‌دهنده',
  'Currency code': 'کد واحد پول',
  '1 unit = AFN': '۱ واحد = افغانی',
  'Save Provider Currency': 'ذخیره واحد پول ارائه‌دهنده',
  'AFN per unit': 'افغانی به ازای هر واحد',
  'No exchange rates saved.': 'هنوز نرخ ارزی ذخیره نشده است.',
  'Provider Secret Encryption': 'رمزگذاری کلید ارائه‌دهنده',
  'HesabPay API': 'API حساب‌پی',
  'Public Base URL': 'آدرس عمومی پایه',
  'Firebase Push': 'پوش فایربیس',
  'Secrets are never shown': 'کلیدهای محرمانه نمایش داده نمی‌شوند',
  'Missing': 'تنظیم نشده',
  'Configured': 'تنظیم شده',

  // Logs / generic module
  'API / Order Action Logs': 'لاگ‌های API / عملیات سفارش',
  'Latest provider interactions': 'آخرین تعاملات ارائه‌دهنده',
  'Summary': 'خلاصه',
  'No logs yet.': 'هنوز لاگی ثبت نشده است.',
  'Independent providers, products, pricing and orders for this business module.': 'ارائه‌دهندگان، محصولات، قیمت‌گذاری و سفارش‌های مستقل برای این بخش کسب‌وکار.',
  'Provider Routes': 'مسیرهای ارائه‌دهنده',
  'No services yet.': 'هنوز سرویسی وجود ندارد.',
  'No providers yet.': 'هنوز ارائه‌دهنده‌ای وجود ندارد.',
  'This section could not be loaded. The error was recorded in server logs.': 'این بخش بارگذاری نشد. خطا در لاگ‌های سرور ثبت شده است.',

  // Misc placeholders / hints
  'Search ID, name or category': 'جستجوی شناسه، نام یا دسته‌بندی',
  'Choose a provider service to configure its app category, customer name and pricing.': 'یک سرویس ارائه‌دهنده را انتخاب کنید تا دسته‌بندی اپ، نام مشتری و قیمت‌گذاری آن را تنظیم کنید.',
  'Recommended: 1080×420 JPG/WebP, optimized below 300 KB for fast mobile loading.': 'پیشنهادی: 1080×420 با فرمت JPG/WebP و حجم کمتر از 300KB برای بارگذاری سریع.',
  'Recommended Social banner: 1080×420 px (JPG or PNG)': 'بنر پیشنهادی شبکه اجتماعی: 1080×420 پیکسل (JPG یا PNG)',
  'Save an image URL to see the live banner preview.': 'برای دیدن پیش‌نمایش زنده، لینک تصویر را ذخیره کنید.',
  'No categories yet.': 'هنوز دسته‌بندی‌ای وجود ندارد.',
  'No VIRTUAL_NUMBER provider.': 'ارائه‌دهنده شماره مجازی وجود ندارد.',
  'No virtual-number provider configured.': 'ارائه‌دهنده شماره مجازی تنظیم نشده است.',
};

const statusTranslations: Record<string, string> = {
  ACTIVE: 'فعال',
  ADMIN: 'مدیر',
  USER: 'کاربر',
  SUSPENDED: 'تعلیق‌شده',
  PENDING: 'در انتظار',
  PROCESSING: 'در حال انجام',
  COMPLETED: 'تکمیل‌شده',
  PARTIAL: 'نیمه‌کامل',
  AWAITING_SMS: 'در انتظار پیامک',
  CANCELLED: 'لغوشده',
  FAILED: 'ناموفق',
  REFUNDED: 'بازپرداخت‌شده',
  PAID: 'پرداخت‌شده',
  RESOLVED: 'حل‌شده',
  SUCCESS: 'موفق',
  CLOSED: 'بسته',
  PENDING_USER: 'در انتظار کاربر',
  PENDING_ADMIN: 'در انتظار مدیر',
  ENABLED: 'فعال',
  DISABLED: 'غیرفعال',
  VISIBLE: 'نمایش داده شود',
  HIDDEN: 'مخفی',
  PUBLISHED: 'منتشرشده',
  MANUAL_ACTIVATION: 'فعال‌سازی دستی',
  MANUAL_DELIVERY: 'تحویل دستی',
  CUSTOM_REQUEST: 'درخواست سفارشی',
  MESSAGING: 'پیام‌رسان',
  SOCIAL: 'شبکه اجتماعی',
  STREAMING: 'استریم',
  OTHER: 'سایر',
  PREMIUM: 'پریمیوم',
  PAYMENT: 'پرداخت',
  WALLET: 'کیف پول',
  ORDER: 'سفارش',
  SUPPORT: 'پشتیبانی',
  ACCOUNT: 'حساب',
};

type AdminLang = 'fa' | 'en';

function adminLangFromRequest(request: FastifyRequest): AdminLang {
  const cookie = String(request.headers.cookie || '');
  const match = cookie.match(/(?:^|;\s*)velixeo_admin_lang=(fa|en)(?:;|$)/);
  return match?.[1] === 'fa' ? 'fa' : 'en';
}

function adminFaNumber(value: string) {
  return value.replace(/\d/g, digit => '۰۱۲۳۴۵۶۷۸۹'[Number(digit)]);
}

function adminPersianText(clean: string): string | null {
  if (translations[clean]) return translations[clean];
  if (statusTranslations[clean]) return statusTranslations[clean];
  let m: RegExpMatchArray | null;
  if ((m = clean.match(/^(\d+) matched$/))) return adminFaNumber(m[1]) + ' مورد مطابق';
  if ((m = clean.match(/^(\d+) on this page$/))) return adminFaNumber(m[1]) + ' مورد در این صفحه';
  if ((m = clean.match(/^Page (\d+) \/ (\d+)$/))) return 'صفحه ' + adminFaNumber(m[1]) + ' از ' + adminFaNumber(m[2]);
  if ((m = clean.match(/^(\d+) changed$/))) return adminFaNumber(m[1]) + ' تغییر';
  if ((m = clean.match(/^(\d+) shown$/))) return adminFaNumber(m[1]) + ' مورد نمایش داده شده';
  if ((m = clean.match(/^(\d+) visible$/))) return adminFaNumber(m[1]) + ' فعال';
  if ((m = clean.match(/^(\d+) configured$/))) return adminFaNumber(m[1]) + ' تنظیم شده';
  if ((m = clean.match(/^(\d+) total$/))) return adminFaNumber(m[1]) + ' مورد';
  if ((m = clean.match(/^(\d+) packages$/))) return adminFaNumber(m[1]) + ' پکیج';
  if ((m = clean.match(/^(\d+) open$/))) return adminFaNumber(m[1]) + ' باز';
  if ((m = clean.match(/^(\d+) completed$/))) return adminFaNumber(m[1]) + ' تکمیل‌شده';
  if ((m = clean.match(/^(\d+) recent events$/))) return adminFaNumber(m[1]) + ' رویداد اخیر';
  if ((m = clean.match(/^(\d+) recent$/))) return adminFaNumber(m[1]) + ' مورد اخیر';
  if ((m = clean.match(/^(\d+) accounts$/))) return adminFaNumber(m[1]) + ' حساب';
  if ((m = clean.match(/^(\d+) matched users$/))) return adminFaNumber(m[1]) + ' کاربر مطابق';
  if ((m = clean.match(/^From (.+)$/))) return 'از ' + m[1];
  if ((m = clean.match(/^Cost: (.+)$/))) return 'هزینه: ' + m[1];
  if ((m = clean.match(/^Done: (.+)$/))) return 'تکمیل: ' + m[1];
  if ((m = clean.match(/^Service API: (.+)$/))) return 'API سرویس: ' + m[1];
  if ((m = clean.match(/^Balance: (.+)$/))) return 'موجودی: ' + m[1];
  if ((m = clean.match(/^Delivery (\d+)–(\d+)h$/))) return 'تحویل ' + adminFaNumber(m[1]) + ' تا ' + adminFaNumber(m[2]) + ' ساعت';
  if ((m = clean.match(/^Live cost \+ (.+)%$/))) return 'هزینه زنده + ' + m[1] + '٪';
  if ((m = clean.match(/^Fixed (.+)$/))) return 'ثابت ' + m[1];
  if ((m = clean.match(/^Drip (\d+)\/(\d+)$/))) return 'مرحله ' + adminFaNumber(m[1]) + ' از ' + adminFaNumber(m[2]);
  return null;
}

function localizeAdminContentFa(html: string) {
  let result = html.replace(/>([^<>]+)</g, (whole, raw: string) => {
    const clean = raw.replace(/\s+/g, ' ').trim();
    if (!clean) return whole;
    const value = adminPersianText(clean);
    if (!value) return whole;
    const lead = raw.match(/^\s*/)?.[0] || '';
    const tail = raw.match(/\s*$/)?.[0] || '';
    return '>' + lead + value + tail + '<';
  });
  result = result.replace(/\b(placeholder|title|aria-label)="([^"]*)"/g, (whole, attr: string, raw: string) => {
    const value = adminPersianText(raw.replace(/\s+/g, ' ').trim());
    return value ? attr + '="' + value.replaceAll('"', '&quot;') + '"' : whole;
  });
  return result;
}

function renderAdminFaPresentation(html: string) {
  return html
    .replace(
      /<html[^>]*>/i,
      '<html lang="fa" dir="rtl" class="vx-admin-fa" data-vx-design="fa">',
    )
    .replace(/<body([^>]*)>/i, '<body$1 class="vx-admin-body vx-admin-body-fa">');
}

function renderAdminEnPresentation(html: string) {
  return html
    .replace(
      /<html[^>]*>/i,
      '<html lang="en" dir="ltr" class="vx-admin-en" data-vx-design="en">',
    )
    .replace(/<body([^>]*)>/i, '<body$1 class="vx-admin-body vx-admin-body-en">');
}

function localeInjection(lang: AdminLang) {
  const fa = lang === 'fa';
  return `<style id="velixeo-admin-design-systems">
  :root{--vx-sky:#38bdf8;--vx-sky-hover:#7dd3fc;--vx-ink:#24343d;--vx-muted:#74818b;--vx-soft:#edf8fd;--vx-bg:#f6f9fc;--vx-line:#e7eef2;--vx-green:#158365;--vx-orange:#ad670d;--vx-red:#c54152}
  .vx-locale{position:fixed;right:18px;bottom:18px;z-index:99999;background:#fff;border:1px solid #dfe8f1;border-radius:12px;padding:5px;display:flex;gap:4px;box-shadow:0 8px 30px rgba(20,60,100,.12)}
  .vx-locale button{border:0;border-radius:8px;padding:7px 10px;background:transparent;color:#61758b;font:600 11px Inter,Arial,sans-serif;cursor:pointer}
  .vx-locale button.active{background:var(--vx-sky);color:#183b4b}
  .vx-admin-menu-toggle{display:none;position:fixed;top:14px;z-index:100000;width:42px;height:42px;border:1px solid var(--vx-line);border-radius:13px;background:#fff;color:#4d7081;box-shadow:0 8px 28px rgba(20,60,100,.1);font-size:20px;align-items:center;justify-content:center}
  .vx-admin-backdrop{display:none}

  /* Persian Admin — independent RTL presentation */
  html.vx-admin-fa body{direction:rtl;font-family:"Vazirmatn",Tahoma,Arial,sans-serif;line-height:1.75;background:var(--vx-bg);color:var(--vx-ink);letter-spacing:0}
  html.vx-admin-fa .layout{direction:rtl;grid-template-columns:minmax(0,1fr) 244px;min-height:100vh}
  html.vx-admin-fa .side{grid-column:2;grid-row:1;background:#fff;color:#8795a1;border-left:1px solid #edf1f5;border-right:0;padding:32px 22px;box-shadow:none;text-align:right}
  html.vx-admin-fa .main{grid-column:1;grid-row:1;padding:30px 38px;direction:rtl;min-width:0}
  html.vx-admin-fa .brand{direction:rtl;flex-direction:row-reverse;justify-content:flex-end;color:var(--vx-ink);border:0;padding:0 2px 10px;margin-bottom:20px}
  html.vx-admin-fa .brand b{color:var(--vx-ink);font-size:19px;letter-spacing:0}
  html.vx-admin-fa .brand small{color:#97a8b1}
  html.vx-admin-fa .cap{color:#b0bac2;padding:15px 12px 7px;font-size:10px;letter-spacing:0;text-align:right}
  html.vx-admin-fa .nav{direction:rtl;justify-content:flex-start;text-align:right;color:#8795a1;padding:12px 13px;border-radius:12px;font-size:12px;gap:12px}
  html.vx-admin-fa .nav:hover{background:#f7fbfd;color:#318eb6}
  html.vx-admin-fa .nav.active{background:var(--vx-soft);color:#318eb6;box-shadow:none;font-weight:700}
  html.vx-admin-fa .subnav{padding:0;margin:0;border:0}
  html.vx-admin-fa .topbar{direction:rtl;grid-template-columns:auto minmax(250px,1fr);background:rgba(246,249,252,.96);height:64px}
  html.vx-admin-fa .topbar .search{grid-column:2;grid-row:1;margin-right:auto;margin-left:0}
  html.vx-admin-fa .topbar .admin{grid-column:1;grid-row:1}
  html.vx-admin-fa .search{border-radius:14px;height:40px;border-color:var(--vx-line)}
  html.vx-admin-fa .avatar{border-radius:15px;background:#e2f3fe;color:#438aa8}
  html.vx-admin-fa .head{direction:rtl;text-align:right;margin:7px 0 24px;align-items:flex-end}
  html.vx-admin-fa .head h1{font-size:24px;font-weight:800;line-height:1.55}
  html.vx-admin-fa .head p{font-size:12px;line-height:1.9}
  html.vx-admin-fa .crumb{font-size:10px;color:#a1b1bc}
  html.vx-admin-fa .stats{direction:rtl;gap:14px;margin-bottom:22px}
  html.vx-admin-fa .stat{padding:20px;border-radius:20px;border-color:#eef2f5;box-shadow:none}
  html.vx-admin-fa .stat strong{font-size:25px}
  html.vx-admin-fa .card{direction:rtl;text-align:right;border-radius:20px;padding:21px;margin-bottom:18px;border-color:#eef2f5;box-shadow:none}
  html.vx-admin-fa .cardhead{direction:rtl}
  html.vx-admin-fa .cardhead h2,html.vx-admin-fa .cardhead h3{font-size:15px;font-weight:700}
  html.vx-admin-fa .table th,html.vx-admin-fa .table td,html.vx-admin-fa table th,html.vx-admin-fa table td{text-align:right;padding:14px 10px;line-height:1.75;font-size:11px}
  html.vx-admin-fa input,html.vx-admin-fa select,html.vx-admin-fa textarea{text-align:right;font-family:"Vazirmatn",Tahoma,Arial,sans-serif}
  html.vx-admin-fa .mono,html.vx-admin-fa input.mono,html.vx-admin-fa textarea.mono{direction:ltr;text-align:left;font-family:ui-monospace,SFMono-Regular,Consolas,monospace}
  html.vx-admin-fa .field label{font-size:11px}
  html.vx-admin-fa .field input,html.vx-admin-fa .field select,html.vx-admin-fa .field textarea{border-radius:12px;padding:11px 14px;font-size:12px;border-color:#dfe8ed}
  html.vx-admin-fa .field input,html.vx-admin-fa .field select{height:44px}
  html.vx-admin-fa .btn{min-height:40px;border-radius:13px;background:var(--vx-sky);color:#183b4b;font-family:"Vazirmatn",Tahoma,Arial,sans-serif;font-size:11px;font-weight:700;box-shadow:0 4px 12px #38bdf821}
  html.vx-admin-fa .btn:hover{background:var(--vx-sky-hover)}
  html.vx-admin-fa .btn.ghost{background:#fff;border:1px solid var(--vx-line);color:#347996}
  html.vx-admin-fa .tabs{direction:rtl;border-bottom:1px solid var(--vx-line);gap:5px}
  html.vx-admin-fa .tab{border:0;border-bottom:2px solid transparent;border-radius:0;background:transparent;padding:12px 14px;font-size:11px}
  html.vx-admin-fa .tab.active{color:#2288b1;border-bottom-color:var(--vx-sky)}
  html.vx-admin-fa .modulehero,html.vx-admin-fa .nhero{background:#edf7fc;color:#245168;border:1px solid #dceef8}
  html.vx-admin-fa .modulehero p,html.vx-admin-fa .nhero p{color:var(--vx-muted)}
  html.vx-admin-fa .vx-locale{right:auto;left:18px}

  /* English Admin — independent LTR presentation */
  html.vx-admin-en body{direction:ltr;font-family:"Inter",Arial,sans-serif;line-height:1.6;background:var(--vx-bg);color:var(--vx-ink)}
  html.vx-admin-en .layout{direction:ltr;grid-template-columns:244px minmax(0,1fr);min-height:100vh}
  html.vx-admin-en .side{grid-column:1;grid-row:1;background:#fff;color:#8795a1;border-right:1px solid #edf1f5;border-left:0;padding:32px 22px;box-shadow:none;text-align:left}
  html.vx-admin-en .main{grid-column:2;grid-row:1;padding:30px 38px;direction:ltr;min-width:0}
  html.vx-admin-en .brand{direction:ltr;color:var(--vx-ink);border:0;padding:0 2px 10px;margin-bottom:20px}
  html.vx-admin-en .brand b{color:var(--vx-ink);font-size:19px}
  html.vx-admin-en .brand small{color:#97a8b1}
  html.vx-admin-en .cap{color:#b0bac2;padding:15px 12px 7px;font-size:10px}
  html.vx-admin-en .nav{direction:ltr;color:#8795a1;padding:12px 13px;border-radius:12px;font-size:12px;gap:12px}
  html.vx-admin-en .nav:hover{background:#f7fbfd;color:#318eb6}
  html.vx-admin-en .nav.active{background:var(--vx-soft);color:#318eb6;box-shadow:none;font-weight:600}
  html.vx-admin-en .topbar{direction:ltr;background:rgba(246,249,252,.96);height:64px}
  html.vx-admin-en .search{border-radius:14px;height:40px;border-color:var(--vx-line)}
  html.vx-admin-en .avatar{border-radius:15px;background:#e2f3fe;color:#438aa8}
  html.vx-admin-en .head{margin:7px 0 24px;align-items:flex-end}
  html.vx-admin-en .head h1{font-size:24px;font-weight:700;line-height:1.4}
  html.vx-admin-en .head p{font-size:12px}
  html.vx-admin-en .stats{gap:14px;margin-bottom:22px}
  html.vx-admin-en .stat{padding:20px;border-radius:20px;border-color:#eef2f5;box-shadow:none}
  html.vx-admin-en .stat strong{font-size:25px}
  html.vx-admin-en .card{border-radius:20px;padding:21px;margin-bottom:18px;border-color:#eef2f5;box-shadow:none}
  html.vx-admin-en .cardhead h2,html.vx-admin-en .cardhead h3{font-size:15px;font-weight:600}
  html.vx-admin-en .table th,html.vx-admin-en .table td{padding:14px 10px;font-size:11px}
  html.vx-admin-en .field label{font-size:11px}
  html.vx-admin-en .field input,html.vx-admin-en .field select,html.vx-admin-en .field textarea{font-family:"Inter",Arial,sans-serif;border-radius:12px;padding:11px 14px;font-size:12px;border-color:#dfe8ed}
  html.vx-admin-en .field input,html.vx-admin-en .field select{height:44px}
  html.vx-admin-en .btn{min-height:40px;border-radius:13px;background:var(--vx-sky);color:#183b4b;font-size:11px;font-weight:600;box-shadow:0 4px 12px #38bdf821}
  html.vx-admin-en .btn:hover{background:var(--vx-sky-hover)}
  html.vx-admin-en .btn.ghost{background:#fff;border:1px solid var(--vx-line);color:#347996}
  html.vx-admin-en .tabs{border-bottom:1px solid var(--vx-line);gap:5px}
  html.vx-admin-en .tab{border:0;border-bottom:2px solid transparent;border-radius:0;background:transparent;padding:12px 14px;font-size:11px}
  html.vx-admin-en .tab.active{color:#2288b1;border-bottom-color:var(--vx-sky)}
  html.vx-admin-en .modulehero,html.vx-admin-en .nhero{background:#edf7fc;color:#245168;border:1px solid #dceef8}
  html.vx-admin-en .modulehero p,html.vx-admin-en .nhero p{color:var(--vx-muted)}

  @media(max-width:1080px){
    html.vx-admin-fa .layout{grid-template-columns:minmax(0,1fr) 205px}
    html.vx-admin-en .layout{grid-template-columns:205px minmax(0,1fr)}
    html.vx-admin-fa .main,html.vx-admin-en .main{padding:25px 24px}
  }
  @media(max-width:760px){
    html.vx-admin-fa .layout,html.vx-admin-en .layout{display:block}
    html.vx-admin-fa .main,html.vx-admin-en .main{padding:66px 14px 18px}
    html.vx-admin-fa .topbar,html.vx-admin-en .topbar{position:relative}
    html.vx-admin-fa .topbar .search,html.vx-admin-en .topbar .search{display:none}
    .vx-admin-menu-toggle{display:flex}
    html.vx-admin-fa .vx-admin-menu-toggle{right:14px;left:auto}
    html.vx-admin-en .vx-admin-menu-toggle{left:14px;right:auto}
    html.vx-admin-fa .side,html.vx-admin-en .side{position:fixed;top:0;height:100vh;width:260px;z-index:99998;overflow:auto;transition:transform .2s ease;box-shadow:0 24px 60px rgba(20,60,100,.16)}
    html.vx-admin-fa .side{right:0;left:auto;transform:translateX(110%)}
    html.vx-admin-en .side{left:0;right:auto;transform:translateX(-110%)}
    html.vx-admin-fa body.vx-admin-menu-open .side,html.vx-admin-en body.vx-admin-menu-open .side{transform:translateX(0)}
    body.vx-admin-menu-open .vx-admin-backdrop{display:block;position:fixed;inset:0;z-index:99997;background:rgba(36,52,61,.22)}
    .stats{grid-template-columns:1fr 1fr}
    .grid,.grid.eq{grid-template-columns:1fr}
  }
  @media(max-width:480px){
    .stats{grid-template-columns:1fr}
    html.vx-admin-fa .main,html.vx-admin-en .main{padding-left:12px;padding-right:12px}
    .vx-locale{bottom:12px}
  }
  </style>
  <button type="button" class="vx-admin-menu-toggle" aria-label="${fa ? 'باز کردن فهرست مدیریت' : 'Open admin menu'}">☰</button>
  <div class="vx-admin-backdrop" data-vx-close-menu></div>
  <div class="vx-locale" aria-label="${fa ? 'زبان پنل مدیریت' : 'Admin language'}">
    <button type="button" data-vx-lang="en" class="${fa ? '' : 'active'}">EN</button>
    <button type="button" data-vx-lang="fa" class="${fa ? 'active' : ''}">فارسی</button>
  </div>
  <script id="velixeo-admin-locale-script">(()=>{
    const key='velixeo_admin_lang';
    const current='${lang}';
    document.querySelectorAll('[data-vx-lang]').forEach(button=>{
      button.addEventListener('click',()=>{
        const next=button.dataset.vxLang;
        if(!next||next===current)return;
        document.cookie=key+'='+next+'; Path=/admin; Max-Age=31536000; SameSite=Lax';
        location.reload();
      });
    });
    const toggle=()=>document.body.classList.toggle('vx-admin-menu-open');
    document.querySelector('.vx-admin-menu-toggle')?.addEventListener('click',toggle);
    document.querySelector('[data-vx-close-menu]')?.addEventListener('click',()=>document.body.classList.remove('vx-admin-menu-open'));
    document.querySelectorAll('.side a,.side button').forEach(item=>item.addEventListener('click',()=>{
      if(innerWidth<=760)document.body.classList.remove('vx-admin-menu-open');
    }));
  })();</script>`;
}

export function registerAdminLocale(app: FastifyInstance) {
  app.addHook('onSend', async (request, reply, payload) => {
    const url = request.raw.url || '';
    if (!url.startsWith('/admin')) return payload;
    if (url.startsWith('/admin/login')) return payload;
    const contentType = String(reply.getHeader('content-type') || '');
    if (!contentType.includes('text/html') || typeof payload !== 'string') return payload;
    if (payload.includes('velixeo-admin-locale-script')) return payload;

    const lang = adminLangFromRequest(request);
    if (lang === 'fa') {
      const localized = localizeAdminContentFa(payload);
      const designed = renderAdminFaPresentation(localized);
      return designed.replace('</body>', localeInjection('fa') + '</body>');
    }
    const designed = renderAdminEnPresentation(payload);
    return designed.replace('</body>', localeInjection('en') + '</body>');
  });
}
