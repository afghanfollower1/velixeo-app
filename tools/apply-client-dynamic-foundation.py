from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'Missing anchor: {label}')
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f'Missing start anchor: {label}')
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f'Missing end anchor: {label}')
    return text[:a] + replacement + text[b:]


api_path = Path('lib/core/api_service.dart')
api = api_path.read_text()
api_anchor = "  Future<AppUser> updatePreferences({AppLang? language, DisplayCurrency? currency}) async {"
api_methods = r'''  Future<List<CatalogService>> catalogServices() async {
    final response = await _send('GET', '/api/v1/catalog/services');
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['services'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => CatalogService.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<AppBanner>> banners() async {
    final response = await _send('GET', '/api/v1/content/banners');
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['banners'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppBanner.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<AppNotification>> notifications() async {
    final response = await _send('GET', '/api/v1/content/notifications', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['notifications'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppNotification.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<AppOrder>> orders() async {
    final response = await _send('GET', '/api/v1/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

'''
api = replace_once(api, api_anchor, api_methods + api_anchor, 'api dynamic methods')
api_path.write_text(api)

app_path = Path('lib/app.dart')
app = app_path.read_text()

app = replace_once(
    app,
    "  List<WalletEntry> walletEntries = const [];\n  bool booting = true;",
    "  List<WalletEntry> walletEntries = const [];\n  List<CatalogService> catalogServices = const [];\n  List<AppBanner> banners = const [];\n  List<AppNotification> notifications = const [];\n  List<AppOrder> orders = const [];\n  bool booting = true;",
    'controller dynamic fields',
)

old_secondary = r'''  Future<void> _loadSecondaryData() async {
    try {
      rates = await api.exchangeRates();
    } catch (_) {}
    try {
      walletEntries = await api.walletEntries();
    } catch (_) {}
  }
'''
new_secondary = r'''  Future<void> _loadSecondaryData() async {
    try {
      rates = await api.exchangeRates();
    } catch (_) {}
    try {
      walletEntries = await api.walletEntries();
    } catch (_) {}
    try {
      catalogServices = await api.catalogServices();
    } catch (_) {}
    try {
      banners = await api.banners();
    } catch (_) {}
    if (authenticated) {
      try {
        notifications = await api.notifications();
      } catch (_) {}
      try {
        orders = await api.orders();
      } catch (_) {}
    }
  }
'''
app = replace_once(app, old_secondary, new_secondary, 'secondary data loader')

app = replace_once(
    app,
    "    walletEntries = const [];\n    authError = null;",
    "    walletEntries = const [];\n    catalogServices = const [];\n    banners = const [];\n    notifications = const [];\n    orders = const [];\n    authError = null;",
    'logout dynamic clear',
)

app = replace_once(
    app,
    "      case 'network_error':\n        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');",
    "      case 'network_error':\n        return tr(fa, 'اتصال به سرور برقرار نشد. اینترنت را بررسی کنید.', 'Could not reach the server. Check your internet connection.');\n      case 'account_suspended':\n        return tr(fa, 'این حساب توسط مدیریت موقتاً تعلیق شده است.', 'This account has been suspended by an administrator.');",
    'suspended auth message',
)

app = replace_once(
    app,
    "    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User');\n    return SafeArea(",
    "    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? tr(c.fa, 'کاربر VELIXEO', 'VELIXEO User');\n    final heroBanners = c.banners.where((banner) => banner.placement == 'HOME_HERO').toList(growable: false);\n    return SafeArea(",
    'home hero banners variable',
)

app = replace_once(
    app,
    "                IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),",
    "                IconButton(\n                  onPressed: () => Navigator.push(\n                    context,\n                    MaterialPageRoute(builder: (_) => NotificationsPage(controller: c)),\n                  ),\n                  icon: Badge(\n                    isLabelVisible: c.notifications.isNotEmpty,\n                    label: Text('${c.notifications.length}'),\n                    child: const Icon(Icons.notifications_none_rounded),\n                  ),\n                ),",
    'notification button',
)

app = replace_once(
    app,
    "            WalletHero(controller: c),\n            const SizedBox(height: 18),\n            TextField(",
    "            WalletHero(controller: c),\n            if (heroBanners.isNotEmpty) ...[\n              const SizedBox(height: 16),\n              RemoteBannerCard(controller: c, banner: heroBanners.first),\n            ],\n            const SizedBox(height: 18),\n            TextField(",
    'home remote banner',
)

services_start = "class ServicesPage extends StatelessWidget {"
services_end = "class ServicePreviewPage extends StatelessWidget {"
services_replacement = r'''IconData catalogIcon(String category) {
  switch (category) {
    case 'VIRTUAL_NUMBER':
      return Icons.phone_android_rounded;
    case 'PREMIUM':
      return Icons.workspace_premium_rounded;
    case 'DIGITAL_ACCOUNT':
      return Icons.manage_accounts_rounded;
    case 'MOBILE_TOPUP':
      return Icons.sim_card_rounded;
    case 'PROMOTION':
      return Icons.campaign_rounded;
    default:
      return Icons.trending_up_rounded;
  }
}

Color catalogColor(String category) {
  switch (category) {
    case 'VIRTUAL_NUMBER':
      return const Color(0xFF22A8F5);
    case 'PREMIUM':
      return const Color(0xFFFFA928);
    case 'DIGITAL_ACCOUNT':
      return const Color(0xFF6366F1);
    case 'MOBILE_TOPUP':
      return const Color(0xFF14B8A6);
    case 'PROMOTION':
      return const Color(0xFFEC4899);
    default:
      return const Color(0xFF8B5CF6);
  }
}

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Text(tr(c.fa, 'خدمات', 'Services'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                const BrandMark(size: 34, wordmark: false),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              readOnly: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'جستجوی سرویس...', 'Search services...')),
            ),
            const SizedBox(height: 18),
            if (c.catalogServices.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFFFE2A5)),
                ),
                child: Text(
                  tr(c.fa, 'کاتالوگ زنده هنوز از پنل ادمین پر نشده؛ فعلاً دسته‌بندی‌های اصلی نمایش داده می‌شوند.', 'The live catalog is still empty in Admin, so the main categories are shown for now.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8D6119)),
                ),
              ),
              ...HomePage.services.map(
                (service) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ServicePreviewPage(controller: c, service: service)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: service.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                          child: Icon(service.icon, color: service.color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(child: Text(c.fa ? service.fa : service.en, style: const TextStyle(fontWeight: FontWeight.w800))),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              ...c.catalogServices.map((service) {
                final color = catalogColor(service.category);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CatalogServicePage(controller: c, service: service)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),
                          child: Icon(catalogIcon(service.category), color: color),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w800)),
                              const SizedBox(height: 3),
                              Text(
                                service.basePriceAfn == null
                                    ? tr(c.fa, 'قیمت از Provider دریافت می‌شود', 'Live provider pricing')
                                    : tr(c.fa, 'از ${c.money(service.basePriceAfn!)}', 'From ${c.money(service.basePriceAfn!)}'),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
                              ),
                            ],
                          ),
                        ),
                        if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928), size: 20),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class CatalogServicePage extends StatelessWidget {
  const CatalogServicePage({super.key, required this.controller, required this.service});
  final AppController controller;
  final CatalogService service;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    final color = catalogColor(service.category);
    final description = fa ? service.descriptionFa : service.descriptionEn;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? service.titleFa : service.titleEn)),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Center(child: Icon(catalogIcon(service.category), size: 72, color: color)),
          ),
          const SizedBox(height: 20),
          if (description?.trim().isNotEmpty == true)
            Text(description!, style: const TextStyle(color: Color(0xFF607487), height: 1.55)),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Text(tr(fa, 'قیمت پایه', 'Base price')),
                    const Spacer(),
                    Text(
                      service.basePriceAfn == null ? tr(fa, 'قیمت زنده', 'Live price') : controller.money(service.basePriceAfn!, showBase: true),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                if (service.minQty != null || service.maxQty != null) ...[
                  const Divider(height: 24),
                  Row(
                    children: [
                      Text(tr(fa, 'محدوده سفارش', 'Order range')),
                      const Spacer(),
                      Text('${service.minQty ?? '—'} – ${service.maxQty ?? '—'}'),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            tr(
              fa,
              'این خدمت از پنل مدیریت VELIXEO کنترل می‌شود. خرید زمانی فعال می‌شود که Provider واقعی برای همین Service Route متصل و تست شود.',
              'This service is controlled from VELIXEO Admin. Purchasing will activate only after a real provider route is connected and verified.',
            ),
            style: const TextStyle(color: Color(0xFF607487), height: 1.5),
          ),
          const SizedBox(height: 22),
          PrimaryButton(label: tr(fa, 'خرید پس از اتصال Provider فعال می‌شود', 'Purchase unlocks after provider integration'), onPressed: null),
        ],
      ),
    );
  }
}

'''
app = replace_between(app, services_start, services_end, services_replacement, 'services dynamic replacement')

orders_start = "class OrdersPage extends StatelessWidget {"
orders_end = "class WalletPage extends StatelessWidget {"
orders_replacement = r'''class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.controller});
  final AppController controller;

  String statusLabel(bool fa, String status) {
    switch (status) {
      case 'PROCESSING':
        return tr(fa, 'در حال انجام', 'Processing');
      case 'COMPLETED':
        return tr(fa, 'تکمیل', 'Completed');
      case 'PARTIAL':
        return tr(fa, 'نیمه‌کامل', 'Partial');
      case 'AWAITING_SMS':
        return tr(fa, 'در انتظار SMS', 'Awaiting SMS');
      case 'CANCELLED':
        return tr(fa, 'لغو شده', 'Cancelled');
      case 'FAILED':
        return tr(fa, 'ناموفق', 'Failed');
      case 'REFUNDED':
        return tr(fa, 'برگشت وجه', 'Refunded');
      default:
        return tr(fa, 'در انتظار', 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(tr(c.fa, 'سفارش‌های من', 'My Orders'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            if (c.orders.isEmpty) ...[
              const SizedBox(height: 60),
              const Icon(Icons.receipt_long_outlined, size: 74, color: Color(0xFF9BB1C4)),
              const SizedBox(height: 18),
              Text(
                tr(c.fa, 'هنوز سفارش واقعی ثبت نشده است', 'No live orders yet'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                tr(c.fa, 'بعد از اتصال Provider، سفارش‌های واقعی از Backend همین‌جا نمایش داده می‌شوند.', 'Real backend orders will appear here after provider integration.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF607487)),
              ),
            ] else ...[
              ...c.orders.map(
                (order) => Padding(
                  padding: const EdgeInsets.only(bottom: 11),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.fa ? (order.serviceTitleFa ?? order.category) : (order.serviceTitleEn ?? order.category),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(999)),
                              child: Text(statusLabel(c.fa, order.status), style: const TextStyle(fontSize: 11, color: Color(0xFF0D78C8), fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 9),
                        Text(c.money(order.totalAmountAfn, showBase: true), style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('${order.createdAt.toLocal().toString().substring(0, 16)} • #${order.id.substring(0, 8)}', style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                        if (order.failureReason?.isNotEmpty == true) ...[
                          const SizedBox(height: 7),
                          Text(order.failureReason!, style: const TextStyle(fontSize: 12, color: Color(0xFFE65454))),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'اعلان‌ها', 'Notifications'))),
      body: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (c.notifications.isEmpty)
              EmptyCard(
                icon: Icons.notifications_none_rounded,
                title: tr(c.fa, 'اعلانی ندارید', 'No notifications'),
                subtitle: tr(c.fa, 'اعلان‌های عمومی یا اختصاصی از پنل مدیریت اینجا نمایش داده می‌شوند.', 'Admin announcements and personal notifications will appear here.'),
              )
            else
              ...c.notifications.map(
                (notice) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.fa ? notice.titleFa : notice.titleEn, style: const TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(c.fa ? notice.bodyFa : notice.bodyEn, style: const TextStyle(color: Color(0xFF607487), height: 1.45)),
                        const SizedBox(height: 8),
                        Text(notice.publishAt.toLocal().toString().substring(0, 16), style: const TextStyle(fontSize: 11, color: Color(0xFF8AA0B3))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RemoteBannerCard extends StatelessWidget {
  const RemoteBannerCard({super.key, required this.controller, required this.banner});
  final AppController controller;
  final AppBanner banner;

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    final title = fa ? banner.titleFa : banner.titleEn;
    final subtitle = fa ? banner.subtitleFa : banner.subtitleEn;
    final action = fa ? banner.actionLabelFa : banner.actionLabelEn;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              banner.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0D78C8), Color(0xFF31A8FF)]),
                ),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: .24)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (title?.trim().isNotEmpty == true)
                    Text(title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                  if (subtitle?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                  if (action?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text(action!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

'''
app = replace_between(app, orders_start, orders_end, orders_replacement, 'orders and notifications replacement')

app_path.write_text(app)
