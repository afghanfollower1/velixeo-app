from pathlib import Path
import re
import subprocess


def read(path: str) -> str:
    return Path(path).read_text(encoding='utf-8')


def write(path: str, text: str):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str):
    text = read(path)
    if new in text:
        return
    if old not in text:
        raise RuntimeError(f'Anchor not found in {path}: {old[:160]!r}')
    write(path, text.replace(old, new, 1))


def regex_once(path: str, pattern: str, replacement: str, marker: str | None = None):
    text = read(path)
    if marker and marker in text:
        return
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count == 0:
        raise RuntimeError(f'Regex anchor not found in {path}: {pattern[:180]!r}')
    write(path, updated)


# -----------------------------------------------------------------------------
# MOBILE APP — English-first Figma implementation
# -----------------------------------------------------------------------------
app = 'lib/app.dart'
text = read(app)
if '// FIGMA_ENGLISH_V1' not in text:
    text = text.replace("import 'virtual_numbers/virtual_number_panel.dart';", "import 'virtual_numbers/virtual_number_panel.dart';\n\n// FIGMA_ENGLISH_V1 — UI implementation based on the approved English Figma file.")
    text = text.replace('  AppLang language = AppLang.fa;', '  AppLang language = AppLang.en;')
    text = text.replace('  bool languageConfirmed = false;', '  bool languageConfirmed = true;')
    text = text.replace('  bool get fa => language == AppLang.fa;', '  bool get fa => false; // English-first release. Persian layout will be enabled in the next design pass.')
    write(app, text)

new_theme = r'''final theme = ThemeData(
          useMaterial3: true,
          brightness: Brightness.light,
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1686FF),
            secondary: Color(0xFF37B6FF),
            surface: Colors.white,
            onSurface: Color(0xFF162235),
            outline: Color(0xFFE3EAF2),
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F9FC),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF162235),
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
            titleTextStyle: TextStyle(
              color: Color(0xFF162235),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE7EDF4)),
            ),
          ),
          dividerTheme: const DividerThemeData(color: Color(0xFFEDF1F6), thickness: 1),
          navigationBarTheme: NavigationBarThemeData(
            height: 68,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE8F3FF),
            elevation: 0,
            labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              color: states.contains(WidgetState.selected) ? const Color(0xFF1686FF) : const Color(0xFF8995A5),
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            )),
            iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? const Color(0xFF1686FF) : const Color(0xFF8995A5),
              size: 23,
            )),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            hintStyle: const TextStyle(color: Color(0xFF9AA6B6), fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3EAF2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE3EAF2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF1686FF), width: 1.4),
            ),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1686FF),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );'''
regex_once(app, r'final theme = ThemeData\(.*?\n        \);', new_theme, marker='English-first Figma theme')
# Marker lives in a comment elsewhere, so use exact primary as idempotency fallback.

main_shell = r'''class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      HomePage(controller: c),
      ServicesPage(controller: c),
      OrdersPage(controller: c),
      WalletPage(controller: c),
      ProfilePage(controller: c),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE9EEF5))),
        ),
        child: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Services'),
            NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Orders'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
            NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

'''
regex_once(app, r'class MainShell extends StatefulWidget \{.*?\n\}\n\nclass HomePage extends StatelessWidget \{', main_shell + 'class HomePage extends StatelessWidget {')

home_page = r'''class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final AppController controller;

  static const services = [
    ServiceItem('شبکه‌های اجتماعی', 'Social Media', Icons.favorite_rounded, Color(0xFF7857FF)),
    ServiceItem('شماره مجازی', 'Virtual Numbers', Icons.phone_iphone_rounded, Color(0xFF28A9FF)),
    ServiceItem('پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFFF3A523)),
    ServiceItem('شارژ موبایل', 'Mobile Top-up', Icons.sim_card_rounded, Color(0xFF12B8A6)),
    ServiceItem('اکانت دیجیتال', 'Digital Accounts', Icons.account_circle_rounded, Color(0xFF5B6EF5)),
    ServiceItem('پروموشن', 'Promotions', Icons.campaign_rounded, Color(0xFFE84D93)),
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'COMPLETED': return const Color(0xFF18A875);
      case 'PROCESSING':
      case 'IN_PROGRESS': return const Color(0xFF1686FF);
      case 'FAILED':
      case 'CANCELLED': return const Color(0xFFE65454);
      default: return const Color(0xFFF0A326);
    }
  }

  String _firstName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return 'there';
    return clean.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final identity = c.user?.fullName ?? c.user?.email ?? c.user?.phone ?? 'VELIXEO User';
    final heroBanners = c.banners.where((b) => b.placement == 'HOME_HERO').toList(growable: false);
    final popular = c.catalogServices.where((s) => s.featured).take(5).toList(growable: false);
    final livePopular = popular.isNotEmpty ? popular : c.catalogServices.take(5).toList(growable: false);
    final recent = c.orders.take(3).toList(growable: false);

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: c.refreshAccount,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hello, ${_firstName(identity)}!', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF172235))),
                      const SizedBox(height: 3),
                      const Text('What would you like to do today?', style: TextStyle(fontSize: 12.5, color: Color(0xFF8793A3))),
                    ],
                  ),
                ),
                _TopCircleButton(
                  icon: Icons.notifications_none_rounded,
                  badge: c.notifications.length,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsPage(controller: c))),
                ),
                const SizedBox(width: 9),
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF51BEFF), Color(0xFF1686FF)])),
                  child: Center(child: Text(_firstName(identity).substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900))),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(colors: [Color(0xFF1265D6), Color(0xFF1895FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: const [BoxShadow(color: Color(0x221686FF), blurRadius: 24, offset: Offset(0, 10))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Wallet Balance', style: TextStyle(color: Color(0xFFCDE7FF), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(c.money(c.balanceAfn), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5)),
                        const SizedBox(height: 4),
                        Text(c.secondaryBalance(), style: const TextStyle(color: Color(0xFFD9ECFF), fontSize: 11.5)),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF1686FF), minimumSize: const Size(0, 42), padding: const EdgeInsets.symmetric(horizontal: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WalletPage(controller: c))),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add funds', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            if (heroBanners.isNotEmpty) ...[
              const SizedBox(height: 14),
              RemoteBannerCard(controller: c, banner: heroBanners.first),
            ] else ...[
              const SizedBox(height: 14),
              Container(
                height: 126,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: const Color(0xFF101F3B), borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
                    Text('Grow your social presence', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                    SizedBox(height: 6),
                    Text('Fast, reliable digital services in one place.', style: TextStyle(color: Color(0xFFBFD0E6), fontSize: 12, height: 1.4)),
                  ])),
                  Container(width: 62, height: 62, decoration: BoxDecoration(color: const Color(0xFF1686FF).withValues(alpha: .18), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF51BEFF), size: 32)),
                ]),
              ),
            ],
            const SizedBox(height: 19),
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openServiceSearch(context, c),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE4EAF1))),
                child: const Row(children: [Icon(Icons.search_rounded, color: Color(0xFF8D99A9), size: 21), SizedBox(width: 10), Expanded(child: Text('Search services...', style: TextStyle(color: Color(0xFF9AA6B6), fontSize: 13.5))), Icon(Icons.tune_rounded, color: Color(0xFF6B7787), size: 19)]),
              ),
            ),
            const SizedBox(height: 23),
            const _HomeSectionHeader(title: 'Services', action: 'View all'),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: services.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .90),
              itemBuilder: (context, i) {
                final service = services[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(17),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _serviceDestination(c, service))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE8EDF3))),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(width: 43, height: 43, decoration: BoxDecoration(color: service.color.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)), child: Icon(service.icon, color: service.color, size: 23)),
                      const SizedBox(height: 9),
                      Text(service.en, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF273447))),
                    ]),
                  ),
                );
              },
            ),
            if (livePopular.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _HomeSectionHeader(title: 'Popular services', action: 'See all'),
              const SizedBox(height: 12),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: livePopular.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final service = livePopular[i];
                    final color = catalogColor(service.category);
                    return InkWell(
                      borderRadius: BorderRadius.circular(17),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _catalogDestination(c, service))),
                      child: Container(
                        width: 176,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: const Color(0xFFE8EDF3))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Container(width: 34, height: 34, decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(10)), child: Icon(catalogIcon(service.category), color: color, size: 19)), const Spacer(), if (service.basePriceAfn != null) Text(c.money(service.basePriceAfn!), style: const TextStyle(fontSize: 11, color: Color(0xFF1686FF), fontWeight: FontWeight.w900))]),
                          const SizedBox(height: 10),
                          Text(service.titleEn, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF253247))),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 24),
              const _HomeSectionHeader(title: 'Recent orders', action: 'View all'),
              const SizedBox(height: 10),
              ...recent.map((order) {
                final color = _statusColor(order.status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE8EDF3))),
                  child: Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFF1686FF).withValues(alpha: .08), borderRadius: BorderRadius.circular(12)), child: Icon(catalogIcon(order.category), color: const Color(0xFF1686FF), size: 20)),
                    const SizedBox(width: 11),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(order.serviceTitleEn ?? order.serviceSlug ?? order.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(c.money(order.totalAmountAfn), style: const TextStyle(fontSize: 11.5, color: Color(0xFF7C8999)))])),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)), child: Text(order.status.replaceAll('_', ' '), style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w800))),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap, this.badge = 0});
  final IconData icon;
  final VoidCallback onTap;
  final int badge;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: Stack(clipBehavior: Clip.none, children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE5EBF2))), child: Icon(icon, color: const Color(0xFF566274), size: 21)),
      if (badge > 0) Positioned(right: -1, top: -2, child: Container(minWidth: 17, height: 17, padding: const EdgeInsets.symmetric(horizontal: 4), decoration: BoxDecoration(color: const Color(0xFFFF4D67), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white, width: 1.5)), child: Center(child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900))))),
    ]),
  );
}

class _HomeSectionHeader extends StatelessWidget {
  const _HomeSectionHeader({required this.title, required this.action});
  final String title;
  final String action;
  @override
  Widget build(BuildContext context) => Row(children: [Expanded(child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1A2739)))), Text(action, style: const TextStyle(color: Color(0xFF1686FF), fontSize: 12, fontWeight: FontWeight.w800))]);
}

'''
regex_once(app, r'class HomePage extends StatelessWidget \{.*?\n\}\n\nclass WalletHero extends StatelessWidget \{', home_page + 'class WalletHero extends StatelessWidget {')

# Redesign the shared wallet hero so Wallet and other pages also match the Figma system.
wallet_hero = r'''class WalletHero extends StatelessWidget {
  const WalletHero({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFF1265D6), Color(0xFF1895FF)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x201686FF), blurRadius: 20, offset: Offset(0, 8))],
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Available balance', style: TextStyle(color: Color(0xFFD4E9FF), fontSize: 12)),
          const SizedBox(height: 6),
          Text(c.money(c.balanceAfn), style: const TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(c.secondaryBalance(), style: const TextStyle(color: Color(0xFFD8EBFF), fontSize: 11)),
        ])),
        Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 25)),
      ]),
    );
  }
}

'''
regex_once(app, r'class WalletHero extends StatelessWidget \{.*?\n\}\n\nIconData catalogIcon', wallet_hero + 'IconData catalogIcon')

# -----------------------------------------------------------------------------
# ADMIN — English Figma shell. All existing forms/actions remain server-side.
# -----------------------------------------------------------------------------
admin_ext = 'backend/src/adminExtended.ts'
text = read(admin_ext)
text = text.replace('<html lang="fa" dir="rtl">', '<html lang="en" dir="ltr">')
text = text.replace('text-align:right', 'text-align:left')
text = text.replace("    ['/admin', 'داشبورد', 'dashboard'],\n    ['/admin/users-control', 'کاربران', 'users'],\n    ['/admin/services', 'خدمات', 'services'],\n    ['/admin/social', 'شبکه‌های اجتماعی', 'social'],\n    ['/admin/virtual-numbers', 'شماره مجازی و SMS', 'virtual'],\n    ['/admin/orders', 'سفارش‌ها', 'orders'],\n    ['/admin/payments', 'پرداخت‌ها', 'payments'],\n    ['/admin/banners', 'بنرها', 'banners'],\n    ['/admin/coupons', 'کد تخفیف', 'coupons'],\n    ['/admin/notifications', 'اعلان‌ها', 'notifications'],\n    ['/admin/support', 'پشتیبانی', 'support'],\n    ['/admin/settings', 'تنظیمات سیستم', 'settings'],\n    ['/admin/readiness', 'آمادگی سیستم', 'readiness'],\n    ['/admin/reports', 'گزارش مالی', 'reports'],\n    ['/admin/audit', 'گزارش مدیر', 'audit'],",
"    ['/admin', 'Dashboard', 'dashboard'],\n    ['/admin/users-control', 'Users', 'users'],\n    ['/admin/social', 'Social Media', 'social'],\n    ['/admin/virtual-numbers', 'Virtual Numbers & SMS', 'virtual'],\n    ['/admin/services?category=PREMIUM', 'Premium Subscriptions', 'services'],\n    ['/admin/services?category=MOBILE_TOPUP', 'Mobile Top-up', 'services'],\n    ['/admin/services?category=DIGITAL_ACCOUNT', 'Digital Accounts', 'services'],\n    ['/admin/services?category=PROMOTION', 'Promotions', 'services'],\n    ['/admin/orders', 'Orders', 'orders'],\n    ['/admin/payments', 'Payments & Wallet', 'payments'],\n    ['/admin/coupons', 'Coupons', 'coupons'],\n    ['/admin/banners', 'Banners & Advertising', 'banners'],\n    ['/admin/notifications', 'Notifications', 'notifications'],\n    ['/admin/support', 'Support', 'support'],\n    ['/admin/settings', 'Settings', 'settings'],\n    ['/admin/reports', 'Reports', 'reports'],\n    ['/admin/audit', 'Audit Log', 'audit'],")
# Figma-like admin tokens and spacing.
text = text.replace('--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;', '--p:#1686FF;--sky:#37B6FF;--bg:#F7F9FC;')
text = text.replace('--nav:#0D2640', '--nav:#0C1D33')
text = text.replace('grid-template-columns:270px minmax(0,1fr)', 'grid-template-columns:244px minmax(0,1fr)')
text = text.replace('border-radius:20px', 'border-radius:16px')
text = text.replace('مدیریت مرکزی VELIXEO — عملیات مدیریتی در Audit Log ثبت می‌شود', 'VELIXEO management center — administrative actions are recorded in Audit Log')
text = text.replace('خروج', 'Sign out')
# Common English labels across the server-rendered admin while preserving values and actions.
translations = {
    'کاربران':'Users','خدمات و قیمت‌ها':'Services & Pricing','خدمات':'Services','شبکه‌های اجتماعی':'Social Media',
    'شماره مجازی و SMS':'Virtual Numbers & SMS','سفارش‌ها':'Orders','پرداخت‌ها':'Payments','بنرها':'Banners',
    'کد تخفیف':'Coupons','اعلان‌ها':'Notifications','پشتیبانی':'Support','تنظیمات سیستم':'System Settings',
    'گزارش مالی':'Financial Reports','گزارش مدیر':'Audit Log','ذخیره':'Save','ویرایش':'Edit','حذف':'Delete',
    'جستجو':'Search','پاک کردن':'Clear','وضعیت':'Status','فعال':'Active','غیرفعال':'Inactive','نام':'Name',
    'توضیحات':'Description','قیمت':'Price','عملیات':'Actions','مبلغ':'Amount','کاربر':'User','تاریخ':'Date',
    'ثبت شد':'Saved','در انتظار':'Pending','موفق':'Successful','ناموفق':'Failed','بازگشت وجه':'Refund',
}
for fa, en in translations.items():
    text = text.replace(fa, en)
write(admin_ext, text)

# Main /admin login & dashboard shell.
admin_page = 'backend/src/adminPage.ts'
text = read(admin_page)
text = text.replace('<html lang="fa" dir="rtl">', '<html lang="en" dir="ltr">')
text = text.replace('text-align:right', 'text-align:left')
text = text.replace('--p:#0D78C8;--sky:#31A8FF;--bg:#F4FAFF;', '--p:#1686FF;--sky:#37B6FF;--bg:#F7F9FC;')
text = text.replace('--nav:#0D2640', '--nav:#0C1D33')
text = text.replace('grid-template-columns:250px 1fr', 'grid-template-columns:244px 1fr')
text = text.replace('border-radius:20px', 'border-radius:16px')
page_translations = {
    'پنل مدیریت امن':'Secure Admin Console','ورود مدیر':'Admin sign in',
    'ورود این صفحه کاملاً سمت سرور انجام می‌شود و به JavaScript وابسته نیست.':'Secure server-side authentication for VELIXEO management.',
    'ایمیل یا شماره':'Email or phone','رمز عبور':'Password','ورود به پنل':'Sign in to Admin',
    'کاربری پیدا نشد.':'No users found.','نام':'Name','موجودی':'Balance','نقش':'Role','عضویت':'Joined','مشاهده':'View',
    'جزئیات کاربر':'User details','موجودی فعلی':'Current balance','افزایش / کسر دستی Wallet':'Manual wallet adjustment',
    'مبلغ AFN':'Amount (AFN)','دلیل عملیات':'Reason','ثبت تغییر کیف پول':'Save wallet adjustment','آخرین تراکنش‌ها':'Recent transactions',
    'داشبورد':'Dashboard','کاربران':'Users','نرخ ارز':'Exchange Rates','API و Providerها':'API & Providers',
    'کل کاربران':'Total users','ثبت‌نام امروز':'New users today','موجودی کل کیف پول‌ها':'Total wallet balance','مدیران':'Admins','آخرین کاربران':'Recent users',
    'جستجو':'Search','پاک کردن':'Clear','نرخ‌های نمایش':'Display exchange rates','ذخیره USD':'Save USD','ذخیره TOMAN':'Save TOMAN',
    'نمای کلی کامل':'Overview','خدمات و قیمت‌ها':'Services & Pricing','Provider و API':'Providers & API','سفارش‌ها':'Orders','پرداخت‌ها':'Payments',
    'بنرها':'Banners','کد تخفیف':'Coupons','اعلان‌ها':'Notifications','پشتیبانی':'Support','تنظیمات':'Settings','خروج':'Sign out',
    'مدیریت واقعی VELIXEO — بدون وابستگی به JavaScript':'VELIXEO Admin Console — secure server-rendered management',
}
for fa, en in page_translations.items():
    text = text.replace(fa, en)
# Replace old compact nav with the Figma module architecture.
text = text.replace("${nav('dashboard','Dashboard')}${nav('users','Users')}${nav('rates','Exchange Rates')}<a href=\"/admin/overview\">Overview</a><a href=\"/admin/services\">Services & Pricing</a><a href=\"/admin/providers\">Providers & API</a><a href=\"/admin/orders\">Orders</a><a href=\"/admin/payments\">Payments</a><a href=\"/admin/banners\">Banners</a><a href=\"/admin/coupons\">Coupons</a><a href=\"/admin/notifications\">Notifications</a><a href=\"/admin/support\">Support</a><a href=\"/admin/settings\">Settings</a><a href=\"/admin/audit\">Audit Log</a>",
"${nav('dashboard','Dashboard')}${nav('users','Users')}<a href=\"/admin/social\">Social Media</a><a href=\"/admin/virtual-numbers\">Virtual Numbers & SMS</a><a href=\"/admin/services?category=PREMIUM\">Premium Subscriptions</a><a href=\"/admin/services?category=MOBILE_TOPUP\">Mobile Top-up</a><a href=\"/admin/services?category=DIGITAL_ACCOUNT\">Digital Accounts</a><a href=\"/admin/services?category=PROMOTION\">Promotions</a><a href=\"/admin/orders\">Orders</a><a href=\"/admin/payments\">Payments & Wallet</a><a href=\"/admin/coupons\">Coupons</a><a href=\"/admin/banners\">Banners & Advertising</a><a href=\"/admin/notifications\">Notifications</a><a href=\"/admin/support\">Support</a>${nav('rates','Exchange Rates')}<a href=\"/admin/settings\">Settings</a><a href=\"/admin/audit\">Audit Log</a>")
write(admin_page, text)

# Social module: English labels + LTR + Figma navy/blue tokens. Business logic unchanged.
social_admin = 'backend/src/socialAdminV2.ts'
text = read(social_admin)
text = text.replace('<html lang="fa" dir="rtl">', '<html lang="en" dir="ltr">')
text = text.replace('text-align:right', 'text-align:left')
text = text.replace('--p:#0D78C8;--sky:#2DA9FF;--bg:#F4FAFF;', '--p:#1686FF;--sky:#37B6FF;--bg:#F7F9FC;')
text = text.replace('--nav:#0D2640', '--nav:#0C1D33')
social_translations = {
    'نمای کلی':'Overview','ارائه‌دهندگان':'Providers','خدمات Provider':'Provider Services','دسته‌بندی‌ها':'Categories',
    'سرویس‌های من':'My Services','سفارش‌ها':'Orders','مدیریت اصلی':'Main Admin','مدیریت اختصاصی خدمات شبکه‌های اجتماعی':'Social Media management',
    'وضعیت Providerها':'Provider status','ارائه‌دهندگان':'Providers','سرویس فعال در اپ':'Active app services','کل سفارش SMM':'Total SMM orders',
    'آخرین Sync':'Last sync','تعداد سرویس':'Services','نتیجه':'Result','فعال':'Active','خاموش':'Disabled','هنوز Provider ثبت نشده است.':'No provider has been added yet.',
    'قیمت‌گذاری زنده:':'Live pricing:','ذخیره':'Save','ویرایش':'Edit','نام':'Name','وضعیت':'Status','اولویت':'Priority','درصد سود':'Markup %',
    'تست اتصال':'Test connection','همگام‌سازی':'Sync','دسته‌بندی':'Category','پلتفرم':'Platform','قیمت خرید':'Provider cost','قیمت فروش':'Sale price',
}
for fa, en in social_translations.items():
    text = text.replace(fa, en)
write(social_admin, text)

# Virtual-number Admin/client uses the same English-first text selection through host.fa=false.
virtual_admin = 'backend/src/virtualNumberRoutes.ts'
text = read(virtual_admin)
text = text.replace('<html lang="fa" dir="rtl">', '<html lang="en" dir="ltr">')
text = text.replace('text-align:right', 'text-align:left')
for fa, en in {
    'شماره مجازی و SMS':'Virtual Numbers & SMS','ارائه‌دهندگان':'Providers','کشورها':'Countries','سرویس‌ها':'Services',
    'قیمت‌گذاری':'Pricing','سفارش‌ها':'Orders','موجودی':'Balance','فعال':'Active','غیرفعال':'Inactive','ذخیره':'Save','همگام‌سازی':'Sync',
}.items():
    text = text.replace(fa, en)
write(virtual_admin, text)

# Keep source formatting deterministic enough for CI and stage every touched file.
subprocess.run([
    'git', 'add',
    app,
    admin_ext,
    admin_page,
    social_admin,
    virtual_admin,
], check=True)

print('VELIXEO Figma English UI v1 applied to mobile and Admin while preserving live business logic.')
