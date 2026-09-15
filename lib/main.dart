import 'package:flutter/material.dart';

void main() => runApp(const VelixeoApp());

enum AppLang { fa, en }
enum DisplayCurrency { afn, usd, toman }

class VelixeoApp extends StatefulWidget {
  const VelixeoApp({super.key});
  @override
  State<VelixeoApp> createState() => _VelixeoAppState();
}

class _VelixeoAppState extends State<VelixeoApp> {
  AppLang lang = AppLang.fa;
  DisplayCurrency currency = DisplayCurrency.afn;
  bool onboarded = false;

  bool get fa => lang == AppLang.fa;

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF31A8FF),
        primary: const Color(0xFF0D6EFD),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xFFF7FBFF),
      fontFamily: null,
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFDCE8F1)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCE8F1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFDCE8F1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF0D6EFD), width: 1.4),
        ),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'VELIXEO',
      theme: baseTheme,
      builder: (context, child) => Directionality(
        textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
        child: child ?? const SizedBox.shrink(),
      ),
      home: onboarded
          ? MainShell(
              fa: fa,
              currency: currency,
              onLanguage: (v) => setState(() => lang = v),
              onCurrency: (v) => setState(() => currency = v),
            )
          : LanguagePage(
              fa: fa,
              onSelect: (v) => setState(() => lang = v),
              onContinue: () => setState(() => onboarded = true),
            ),
    );
  }
}

String tr(bool fa, String faText, String enText) => fa ? faText : enText;

String money(double afn, DisplayCurrency c, {bool withBase = false}) {
  const usdAfn = 70.0;
  const tomanPerAfn = 1180.0;
  String fmt(num v) {
    final s = v.round().toString();
    return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }
  switch (c) {
    case DisplayCurrency.afn:
      return '${fmt(afn)} AFN';
    case DisplayCurrency.usd:
      final usd = afn / usdAfn;
      return withBase ? '\$${usd.toStringAsFixed(2)}  ≈  ${fmt(afn)} AFN' : '\$${usd.toStringAsFixed(2)}';
    case DisplayCurrency.toman:
      final toman = afn * tomanPerAfn;
      return withBase ? '${fmt(toman)} تومان  ≈  ${fmt(afn)} AFN' : '${fmt(toman)} تومان';
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 46, this.wordmark = true});
  final double size;
  final bool wordmark;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(size * .28),
            gradient: const LinearGradient(
              colors: [Color(0xFF49C5FF), Color(0xFF0D6EFD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CustomPaint(painter: _LogoPainter()),
        ),
        if (wordmark) ...[
          const SizedBox(width: 10),
          Text(
            'VELIXEO',
            style: TextStyle(
              fontSize: size * .43,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
              color: const Color(0xFF102235),
            ),
          ),
        ],
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .14
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(s.width * .25, s.height * .29)
      ..lineTo(s.width * .49, s.height * .73)
      ..lineTo(s.width * .72, s.height * .31);
    canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(s.width * .77, s.height * .22), s.width * .07, Paint()..color = Colors.white);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LanguagePage extends StatelessWidget {
  const LanguagePage({super.key, required this.fa, required this.onSelect, required this.onContinue});
  final bool fa;
  final ValueChanged<AppLang> onSelect;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              const BrandMark(size: 82),
              const SizedBox(height: 28),
              Text(
                tr(fa, 'زبان خود را انتخاب کنید', 'Choose your language'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                tr(fa, 'بعداً از تنظیمات قابل تغییر است', 'You can change it later in settings'),
                style: const TextStyle(color: Color(0xFF607487)),
              ),
              const SizedBox(height: 30),
              _LanguageTile(
                title: 'فارسی',
                subtitle: 'ادامه به زبان فارسی',
                flag: '🇦🇫',
                selected: fa,
                onTap: () => onSelect(AppLang.fa),
              ),
              const SizedBox(height: 12),
              _LanguageTile(
                title: 'English',
                subtitle: 'Continue in English',
                flag: '🌐',
                selected: !fa,
                onTap: () => onSelect(AppLang.en),
              ),
              const Spacer(),
              PrimaryButton(label: tr(fa, 'ادامه', 'Continue'), onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LoginPage(fa: fa, onDone: onContinue)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({required this.title, required this.subtitle, required this.flag, required this.selected, required this.onTap});
  final String title, subtitle, flag;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? const Color(0xFF0D6EFD) : const Color(0xFFDCE8F1), width: selected ? 1.6 : 1),
          ),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF607487)))])),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: const Color(0xFF0D6EFD)),
            ],
          ),
        ),
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.fa, required this.onDone});
  final bool fa;
  final VoidCallback onDone;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool hidden = true;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 40),
              const Center(child: BrandMark(size: 66)),
              const SizedBox(height: 46),
              Text(tr(widget.fa, 'ورود به حساب کاربری', 'Welcome back'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(tr(widget.fa, 'برای ادامه وارد حساب خود شوید', 'Sign in to continue'), style: const TextStyle(color: Color(0xFF607487))),
              const SizedBox(height: 28),
              TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.alternate_email), hintText: tr(widget.fa, 'ایمیل یا شماره موبایل', 'Email or phone number'))),
              const SizedBox(height: 14),
              TextField(
                obscureText: hidden,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outline),
                  hintText: tr(widget.fa, 'رمز عبور', 'Password'),
                  suffixIcon: IconButton(onPressed: () => setState(() => hidden = !hidden), icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined)),
                ),
              ),
              const SizedBox(height: 10),
              Align(alignment: AlignmentDirectional.centerEnd, child: TextButton(onPressed: () {}, child: Text(tr(widget.fa, 'رمز را فراموش کرده‌اید؟', 'Forgot password?')))),
              const SizedBox(height: 12),
              PrimaryButton(label: tr(widget.fa, 'ورود', 'Sign in'), onPressed: widget.onDone),
              const SizedBox(height: 18),
              Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text(tr(widget.fa, 'یا', 'or'))), const Expanded(child: Divider())]),
              const SizedBox(height: 18),
              OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.person_add_alt_1), label: Text(tr(widget.fa, 'ساخت حساب جدید', 'Create account'))),
            ],
          ),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.fa, required this.currency, required this.onLanguage, required this.onCurrency});
  final bool fa;
  final DisplayCurrency currency;
  final ValueChanged<AppLang> onLanguage;
  final ValueChanged<DisplayCurrency> onCurrency;
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(fa: widget.fa, currency: widget.currency),
      ServicesPage(fa: widget.fa, currency: widget.currency),
      OrdersPage(fa: widget.fa, currency: widget.currency),
      WalletPage(fa: widget.fa, currency: widget.currency),
      ProfilePage(fa: widget.fa, currency: widget.currency, onLanguage: widget.onLanguage, onCurrency: widget.onCurrency),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr(widget.fa, 'خانه', 'Home')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: tr(widget.fa, 'خدمات', 'Services')),
          NavigationDestination(icon: const Icon(Icons.shopping_bag_outlined), selectedIcon: const Icon(Icons.shopping_bag), label: tr(widget.fa, 'سفارش‌ها', 'Orders')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet), label: tr(widget.fa, 'کیف پول', 'Wallet')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: tr(widget.fa, 'پروفایل', 'Profile')),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  static const services = [
    _Service('شبکه‌های اجتماعی', 'Social Media', Icons.trending_up_rounded, Color(0xFF8B5CF6)),
    _Service('شماره مجازی', 'Virtual Numbers', Icons.phone_android_rounded, Color(0xFF22A8F5)),
    _Service('پریمیوم', 'Premium', Icons.workspace_premium_rounded, Color(0xFFFFA928)),
    _Service('اکانت دیجیتال', 'Digital Accounts', Icons.manage_accounts_rounded, Color(0xFF6366F1)),
    _Service('شارژ موبایل', 'Mobile Credit', Icons.sim_card_rounded, Color(0xFF14B8A6)),
    _Service('پروموشن', 'Promotions', Icons.campaign_rounded, Color(0xFFEC4899)),
  ];

  @override
  Widget build(BuildContext context) => SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(children: [const BrandMark(size: 38), const Spacer(), IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)), const CircleAvatar(radius: 18, child: Icon(Icons.person_outline))]),
                  const SizedBox(height: 18),
                  Text(tr(fa, 'سلام، کاربر عزیز 👋', 'Hello 👋'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  WalletHero(fa: fa, currency: currency),
                  const SizedBox(height: 18),
                  TextField(readOnly: true, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(fa, 'چه خدمتی نیاز دارید؟', 'What service do you need?'))),
                  const SizedBox(height: 22),
                  SectionTitle(tr(fa, 'دسته‌بندی خدمات', 'Service categories')),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: services.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: .9),
                    itemBuilder: (context, i) => ServiceCard(service: services[i], fa: fa, onTap: () => openService(context, i, fa, currency)),
                  ),
                  const SizedBox(height: 24),
                  SectionTitle(tr(fa, 'پیشنهادهای ویژه', 'Special offers')),
                  Container(
                    height: 150,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(colors: [Color(0xFF102B70), Color(0xFF0D6EFD), Color(0xFF31A8FF)]),
                    ),
                    child: Stack(children: [
                      PositionedDirectional(end: -14, bottom: -24, child: Icon(Icons.rocket_launch_rounded, size: 130, color: Colors.white.withOpacity(.12))),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(fa, 'رشد سریع‌تر در شبکه‌های اجتماعی', 'Grow faster on social media'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), const SizedBox(height: 6), Text(tr(fa, 'خدمات منتخب با تحویل سریع', 'Selected services with fast delivery'), style: const TextStyle(color: Colors.white70)), const Spacer(), const Icon(Icons.arrow_forward_rounded, color: Colors.white)]),
                    ]),
                  ),
                  const SizedBox(height: 24),
                  SectionTitle(tr(fa, 'سفارش‌های اخیر', 'Recent orders')),
                  OrderTile(title: 'Instagram Followers', subtitle: '1,000 Followers', amount: money(850, currency), status: tr(fa, 'در حال پردازش', 'Processing'), color: const Color(0xFFE1306C)),
                  const SizedBox(height: 10),
                  OrderTile(title: 'Telegram Number', subtitle: 'Iran +98', amount: money(45, currency), status: tr(fa, 'تکمیل شده', 'Completed'), color: const Color(0xFF229ED9)),
                ]),
              ),
            ),
          ],
        ),
      );
}

class WalletHero extends StatelessWidget {
  const WalletHero({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), gradient: const LinearGradient(colors: [Color(0xFF43BEFF), Color(0xFF0D6EFD)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(fa, 'موجودی کیف پول', 'Wallet balance'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 6),
          const Text('12,450 AFN', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w900)),
          const SizedBox(height: 3),
          Text('≈ \$177.86   •   ≈ 14,691,000 تومان', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 14),
          Row(children: [Expanded(child: _HeroAction(icon: Icons.add, label: tr(fa, 'افزایش موجودی', 'Add funds'))), const SizedBox(width: 10), Expanded(child: _HeroAction(icon: Icons.history, label: tr(fa, 'تراکنش‌ها', 'Transactions')))]),
        ]),
      );
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(vertical: 11), decoration: BoxDecoration(color: Colors.white.withOpacity(.18), borderRadius: BorderRadius.circular(14)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: Colors.white, size: 18), const SizedBox(width: 6), Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)))]));
}

class ServicesPage extends StatelessWidget {
  const ServicesPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Row(children: [Text(tr(fa, 'خدمات', 'Services'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), const Spacer(), const BrandMark(size: 34, wordmark: false)]),
        const SizedBox(height: 16),
        TextField(readOnly: true, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(fa, 'جستجوی سرویس...', 'Search services...'))),
        const SizedBox(height: 18),
        ...List.generate(HomePage.services.length, (i) {
          final s = HomePage.services[i];
          return Padding(padding: const EdgeInsets.only(bottom: 11), child: InkWell(onTap: () => openService(context, i, fa, currency), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFDCE8F1))), child: Row(children: [Container(width: 50, height: 50, decoration: BoxDecoration(color: s.color.withOpacity(.1), borderRadius: BorderRadius.circular(16)), child: Icon(s.icon, color: s.color)), const SizedBox(width: 14), Expanded(child: Text(fa ? s.fa : s.en, style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.chevron_right)]))));
        }),
      ]));
}

void openService(BuildContext context, int i, bool fa, DisplayCurrency currency) {
  final pages = <Widget>[
    SocialHubPage(fa: fa, currency: currency),
    VirtualNumbersPage(fa: fa, currency: currency),
    ProductPage(fa: fa, currency: currency, titleFa: 'پریمیوم و اشتراک‌ها', titleEn: 'Premium & Subscriptions', products: const [('Telegram Premium', 350.0), ('Snapchat+', 420.0), ('Netflix', 650.0)]),
    ProductPage(fa: fa, currency: currency, titleFa: 'اکانت‌های دیجیتال', titleEn: 'Digital Accounts', products: const [('Canva Pro', 550.0), ('Spotify Premium', 620.0), ('Discord Nitro', 720.0)]),
    MobileCreditPage(fa: fa, currency: currency),
    PromotionPage(fa: fa),
  ];
  Navigator.push(context, MaterialPageRoute(builder: (_) => pages[i]));
}

class SocialHubPage extends StatelessWidget {
  const SocialHubPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) {
    const platforms = [('Instagram', Icons.camera_alt_rounded, Color(0xFFE1306C)), ('Facebook', Icons.facebook_rounded, Color(0xFF1877F2)), ('TikTok', Icons.music_note_rounded, Color(0xFF111111)), ('YouTube', Icons.play_circle_fill_rounded, Color(0xFFFF0000)), ('Telegram', Icons.send_rounded, Color(0xFF229ED9)), ('X', Icons.close_rounded, Color(0xFF111111))];
    return Scaffold(appBar: AppBar(title: Text(tr(fa, 'شبکه‌های اجتماعی', 'Social Media'))), body: ListView(padding: const EdgeInsets.all(18), children: [Text(tr(fa, 'پلتفرم را انتخاب کنید', 'Choose a platform'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 14), ...platforms.map((p) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SocialServicePage(fa: fa, currency: currency, platform: p.$1))), child: Row(children: [CircleAvatar(backgroundColor: p.$3.withOpacity(.1), child: Icon(p.$2, color: p.$3)), const SizedBox(width: 12), Expanded(child: Text(p.$1, style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.chevron_right)]))))]));
  }
}

class SocialServicePage extends StatelessWidget {
  const SocialServicePage({super.key, required this.fa, required this.currency, required this.platform});
  final bool fa;
  final DisplayCurrency currency;
  final String platform;
  @override
  Widget build(BuildContext context) {
    const services = [('Followers', 'فالوور', 850.0), ('Likes', 'لایک', 320.0), ('Views', 'ویو', 180.0), ('Comments', 'کامنت', 720.0), ('Story Views', 'ویو استوری', 260.0)];
    return Scaffold(appBar: AppBar(title: Text(platform)), body: ListView(padding: const EdgeInsets.all(18), children: services.map((s) => Padding(padding: const EdgeInsets.only(bottom: 11), child: SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SocialOrderPage(fa: fa, currency: currency, platform: platform, service: fa ? s.$2 : s.$1, base: s.$3))), child: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFF0F7FF), child: Icon(Icons.auto_awesome, color: Color(0xFF0D6EFD))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(fa ? s.$2 : s.$1, style: const TextStyle(fontWeight: FontWeight.w800)), const Text('Fast delivery • Refill available', style: TextStyle(fontSize: 12, color: Color(0xFF607487)))])), Text(money(s.$3, currency), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))])))).toList()));
  }
}

class SocialOrderPage extends StatefulWidget {
  const SocialOrderPage({super.key, required this.fa, required this.currency, required this.platform, required this.service, required this.base});
  final bool fa;
  final DisplayCurrency currency;
  final String platform, service;
  final double base;
  @override
  State<SocialOrderPage> createState() => _SocialOrderPageState();
}

class _SocialOrderPageState extends State<SocialOrderPage> {
  int quantity = 1000;
  @override
  Widget build(BuildContext context) {
    final total = widget.base * quantity / 1000;
    return Scaffold(appBar: AppBar(title: Text('${widget.platform} • ${widget.service}')), body: ListView(padding: const EdgeInsets.all(18), children: [
      SoftCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(widget.fa, 'سرویس با کیفیت بالا', 'High quality service'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: const [Chip(label: Text('Refill 30 Days')), Chip(label: Text('Fast Delivery')), Chip(label: Text('Min 100')), Chip(label: Text('Max 100K'))]),
        const SizedBox(height: 16),
        TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.link), hintText: tr(widget.fa, 'نام کاربری یا لینک', 'Username or profile link'))),
        const SizedBox(height: 14),
        Row(children: [Text(tr(widget.fa, 'تعداد', 'Quantity'), style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), IconButton(onPressed: () => setState(() => quantity = (quantity - 100).clamp(100, 100000)), icon: const Icon(Icons.remove_circle_outline)), Text('$quantity', style: const TextStyle(fontWeight: FontWeight.w900)), IconButton(onPressed: () => setState(() => quantity = (quantity + 100).clamp(100, 100000)), icon: const Icon(Icons.add_circle_outline))]),
        const Divider(height: 28),
        Row(children: [Text(tr(widget.fa, 'مجموع', 'Total')), const Spacer(), Text(money(total, widget.currency, withBase: true), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))]),
        const SizedBox(height: 18),
        PrimaryButton(label: tr(widget.fa, 'ثبت سفارش', 'Place order'), onPressed: () => showSuccess(context, widget.fa)),
      ])),
    ]));
  }
}

class VirtualNumbersPage extends StatelessWidget {
  const VirtualNumbersPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) {
    const countries = [('🇦🇫', 'Afghanistan', '+93'), ('🇮🇷', 'Iran', '+98'), ('🇹🇷', 'Türkiye', '+90'), ('🇺🇸', 'United States', '+1'), ('🇬🇧', 'United Kingdom', '+44')];
    return Scaffold(appBar: AppBar(title: Text(tr(fa, 'شماره مجازی', 'Virtual Numbers'))), body: ListView(padding: const EdgeInsets.all(18), children: [
      Text(tr(fa, 'کشور را انتخاب کنید', 'Select country'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 12),
      ...countries.map((c) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VirtualServicePage(fa: fa, currency: currency, country: c.$2, code: c.$3))), child: Row(children: [Text(c.$1, style: const TextStyle(fontSize: 26)), const SizedBox(width: 12), Expanded(child: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w800))), Text(c.$3, style: const TextStyle(color: Color(0xFF607487))), const Icon(Icons.chevron_right)]))))
    ]));
  }
}

class VirtualServicePage extends StatelessWidget {
  const VirtualServicePage({super.key, required this.fa, required this.currency, required this.country, required this.code});
  final bool fa;
  final DisplayCurrency currency;
  final String country, code;
  @override
  Widget build(BuildContext context) {
    const apps = [('Telegram', Icons.send_rounded, 45.0), ('WhatsApp', Icons.chat_rounded, 52.0), ('Google', Icons.g_mobiledata_rounded, 38.0), ('Instagram', Icons.camera_alt_rounded, 49.0)];
    return Scaffold(appBar: AppBar(title: Text('$country $code')), body: ListView(padding: const EdgeInsets.all(18), children: [Text(tr(fa, 'سرویس را انتخاب کنید', 'Select service'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 12), ...apps.map((a) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveNumberPage(fa: fa, currency: currency, service: a.$1, amount: a.$3, code: code))), child: Row(children: [CircleAvatar(backgroundColor: const Color(0xFFEAF6FF), child: Icon(a.$2, color: const Color(0xFF0D6EFD))), const SizedBox(width: 12), Expanded(child: Text(a.$1, style: const TextStyle(fontWeight: FontWeight.w800))), Text(money(a.$3, currency), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))]))))]));
  }
}

class ActiveNumberPage extends StatelessWidget {
  const ActiveNumberPage({super.key, required this.fa, required this.currency, required this.service, required this.amount, required this.code});
  final bool fa;
  final DisplayCurrency currency;
  final String service, code;
  final double amount;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(service)), body: ListView(padding: const EdgeInsets.all(18), children: [SoftCard(child: Column(children: [
        const Icon(Icons.send_rounded, size: 50, color: Color(0xFF229ED9)),
        const SizedBox(height: 16),
        Text('$code 912 345 6789', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(money(amount, currency, withBase: true), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        const Text('09:45', style: TextStyle(fontSize: 38, color: Color(0xFF18A875), fontWeight: FontWeight.w900)),
        Text(tr(fa, 'در انتظار SMS', 'Awaiting SMS'), style: const TextStyle(color: Color(0xFF607487))),
        const SizedBox(height: 20),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.copy), label: Text(tr(fa, 'کپی شماره', 'Copy number')))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.refresh), label: Text(tr(fa, 'بررسی SMS', 'Refresh SMS'))))]),
        const Divider(height: 32),
        Align(alignment: AlignmentDirectional.centerStart, child: Text(tr(fa, 'پیام‌های دریافتی', 'Received messages'), style: const TextStyle(fontWeight: FontWeight.w900))),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFDFF4FF), borderRadius: BorderRadius.circular(16)), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(service, style: const TextStyle(fontWeight: FontWeight.w800)), Text(tr(fa, 'کد تأیید شما:', 'Your verification code:'), style: const TextStyle(fontSize: 12, color: Color(0xFF607487))), const Text('482931', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))])), IconButton(onPressed: () {}, icon: const Icon(Icons.copy))])),
      ]))]));
}

class ProductPage extends StatelessWidget {
  const ProductPage({super.key, required this.fa, required this.currency, required this.titleFa, required this.titleEn, required this.products});
  final bool fa;
  final DisplayCurrency currency;
  final String titleFa, titleEn;
  final List<(String, double)> products;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr(fa, titleFa, titleEn))), body: ListView(padding: const EdgeInsets.all(18), children: products.map((p) => Padding(padding: const EdgeInsets.only(bottom: 11), child: SoftCard(onTap: () => showSuccess(context, fa), child: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFFFF3DD), child: Icon(Icons.workspace_premium_rounded, color: Color(0xFFF59E0B))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(p.$1, style: const TextStyle(fontWeight: FontWeight.w900)), Text(tr(fa, 'موجود • تحویل سریع', 'In stock • Fast delivery'), style: const TextStyle(fontSize: 12, color: Color(0xFF18A875)))])), Text(money(p.$2, currency), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))])))).toList()));
}

class MobileCreditPage extends StatefulWidget {
  const MobileCreditPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  State<MobileCreditPage> createState() => _MobileCreditPageState();
}

class _MobileCreditPageState extends State<MobileCreditPage> {
  int amount = 500;
  String operatorName = 'Roshan';
  @override
  Widget build(BuildContext context) {
    const ops = ['Roshan', 'MTN', 'Etisalat', 'Salaam'];
    return Scaffold(appBar: AppBar(title: Text(tr(widget.fa, 'شارژ موبایل', 'Mobile Credit'))), body: ListView(padding: const EdgeInsets.all(18), children: [
      Text(tr(widget.fa, 'افغانستان', 'Afghanistan'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: ops.map((o) => ChoiceChip(selected: operatorName == o, onSelected: (_) => setState(() => operatorName = o), avatar: const Icon(Icons.sim_card, size: 18), label: Text(o))).toList()),
      const SizedBox(height: 18),
      TextField(keyboardType: TextInputType.phone, decoration: InputDecoration(prefixIcon: const Icon(Icons.phone), hintText: tr(widget.fa, 'شماره موبایل 07XXXXXXXX', 'Mobile number 07XXXXXXXX'))),
      const SizedBox(height: 18),
      Text(tr(widget.fa, 'مبلغ شارژ', 'Top-up amount'), style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [50, 100, 200, 500, 1000, 2000].map((v) => ChoiceChip(selected: amount == v, onSelected: (_) => setState(() => amount = v), label: Text('$v AFN'))).toList()),
      const SizedBox(height: 24),
      Row(children: [Text(tr(widget.fa, 'قابل پرداخت', 'Payable')), const Spacer(), Text(money(amount.toDouble(), widget.currency, withBase: true), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))]),
      const SizedBox(height: 18),
      PrimaryButton(label: tr(widget.fa, 'ادامه و پرداخت', 'Continue & pay'), onPressed: () => showSuccess(context, widget.fa)),
    ]));
  }
}

class PromotionPage extends StatelessWidget {
  const PromotionPage({super.key, required this.fa});
  final bool fa;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr(fa, 'پروموشن و تبلیغات', 'Promotions'))), body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(fa, 'درخواست کمپین', 'Campaign request'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(items: const ['Instagram', 'Facebook', 'TikTok', 'YouTube'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), onChanged: (_) {}, decoration: InputDecoration(labelText: tr(fa, 'پلتفرم', 'Platform'))),
        const SizedBox(height: 14),
        TextField(decoration: InputDecoration(prefixIcon: const Icon(Icons.link), labelText: tr(fa, 'لینک پست یا صفحه', 'Post / Page link'))),
        const SizedBox(height: 14),
        TextField(maxLines: 4, decoration: InputDecoration(labelText: tr(fa, 'هدف و توضیحات کمپین', 'Campaign goal / notes'))),
        const SizedBox(height: 14),
        TextField(keyboardType: TextInputType.number, decoration: InputDecoration(prefixIcon: const Icon(Icons.payments_outlined), labelText: tr(fa, 'بودجه به افغانی', 'Budget (AFN)'))),
        const SizedBox(height: 22),
        PrimaryButton(label: tr(fa, 'ثبت درخواست', 'Submit campaign'), onPressed: () => showSuccess(context, fa)),
      ]));
}

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(fa, 'سفارش‌های من', 'My Orders'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, children: [ChoiceChip(selected: true, label: Text(tr(fa, 'همه', 'All')), onSelected: (_) {}), ChoiceChip(selected: false, label: Text(tr(fa, 'اجتماعی', 'Social')), onSelected: (_) {}), ChoiceChip(selected: false, label: Text(tr(fa, 'شماره', 'Numbers')), onSelected: (_) {})]),
        const SizedBox(height: 18),
        OrderTile(title: 'Instagram Followers', subtitle: '1,000 Followers', amount: money(850, currency), status: tr(fa, 'در حال پردازش', 'Processing'), color: const Color(0xFFE1306C)),
        const SizedBox(height: 10),
        OrderTile(title: 'Telegram Number', subtitle: 'Iran +98', amount: money(45, currency), status: tr(fa, 'تکمیل شده', 'Completed'), color: const Color(0xFF229ED9)),
        const SizedBox(height: 10),
        OrderTile(title: 'Telegram Premium', subtitle: '3 Months', amount: money(950, currency), status: tr(fa, 'در انتظار', 'Pending'), color: const Color(0xFFF59E0B)),
      ]));
}

class WalletPage extends StatelessWidget {
  const WalletPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(fa, 'کیف پول', 'Wallet'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        WalletHero(fa: fa, currency: currency),
        const SizedBox(height: 18),
        PrimaryButton(label: tr(fa, 'افزایش موجودی', 'Add funds'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddFundsPage(fa: fa, currency: currency)))),
        const SizedBox(height: 22),
        SectionTitle(tr(fa, 'تراکنش‌های اخیر', 'Recent transactions')),
        TransactionTile(icon: Icons.add_circle_outline, title: tr(fa, 'افزایش موجودی', 'Wallet top-up'), amount: '+ 1,000 AFN', positive: true),
        const SizedBox(height: 10),
        TransactionTile(icon: Icons.shopping_bag_outlined, title: 'Instagram Followers', amount: '- 850 AFN', positive: false),
        const SizedBox(height: 10),
        TransactionTile(icon: Icons.undo_rounded, title: tr(fa, 'برگشت وجه', 'Refund'), amount: '+ 45 AFN', positive: true),
      ]));
}

class AddFundsPage extends StatefulWidget {
  const AddFundsPage({super.key, required this.fa, required this.currency});
  final bool fa;
  final DisplayCurrency currency;
  @override
  State<AddFundsPage> createState() => _AddFundsPageState();
}

class _AddFundsPageState extends State<AddFundsPage> {
  int amount = 1000;
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(tr(widget.fa, 'افزایش موجودی', 'Add Funds'))), body: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(widget.fa, 'مبلغ مورد نظر', 'Choose amount'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [100, 500, 1000, 2000, 5000].map((v) => ChoiceChip(selected: amount == v, onSelected: (_) => setState(() => amount = v), label: Text('$v AFN'))).toList()),
        const SizedBox(height: 22),
        Text(tr(widget.fa, 'روش پرداخت', 'Payment method'), style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        SoftCard(child: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFE4F8EF), child: Icon(Icons.bolt_rounded, color: Color(0xFF18A875))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('HesabPay • حساب‌پی', style: TextStyle(fontWeight: FontWeight.w900)), Text(tr(widget.fa, 'پرداخت سریع و امن', 'Fast & secure payment'), style: const TextStyle(fontSize: 12, color: Color(0xFF607487)))])), const Icon(Icons.radio_button_checked, color: Color(0xFF0D6EFD))])),
        const SizedBox(height: 12),
        SoftCard(child: Row(children: [const CircleAvatar(backgroundColor: Color(0xFFF3F6FA), child: Icon(Icons.credit_card)), const SizedBox(width: 12), Expanded(child: Text(tr(widget.fa, 'درگاه پرداخت آینده', 'Future payment gateway'), style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.radio_button_off, color: Color(0xFF607487))])),
        const SizedBox(height: 22),
        Row(children: [Text(tr(widget.fa, 'مبلغ پایه', 'Base amount')), const Spacer(), Text('$amount AFN', style: const TextStyle(fontWeight: FontWeight.w900))]),
        const SizedBox(height: 4),
        Row(children: [Text(tr(widget.fa, 'معادل نمایشی', 'Display equivalent')), const Spacer(), Text(money(amount.toDouble(), widget.currency), style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))]),
        const SizedBox(height: 20),
        PrimaryButton(label: tr(widget.fa, 'ادامه به حساب‌پی', 'Continue to HesabPay'), onPressed: () => showSuccess(context, widget.fa, wallet: true)),
      ]));
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.fa, required this.currency, required this.onLanguage, required this.onCurrency});
  final bool fa;
  final DisplayCurrency currency;
  final ValueChanged<AppLang> onLanguage;
  final ValueChanged<DisplayCurrency> onCurrency;
  @override
  Widget build(BuildContext context) => SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Text(tr(fa, 'پروفایل', 'Profile'), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 18),
        SoftCard(child: Row(children: [const CircleAvatar(radius: 30, child: Icon(Icons.person_outline, size: 30)), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tr(fa, 'کاربر VELIXEO', 'VELIXEO User'), style: const TextStyle(fontWeight: FontWeight.w900)), const Text('user@velixeo.app', style: TextStyle(fontSize: 12, color: Color(0xFF607487)))])), const Icon(Icons.verified_rounded, color: Color(0xFF18A875))])),
        const SizedBox(height: 16),
        _SettingsTile(icon: Icons.language, title: tr(fa, 'زبان', 'Language'), value: fa ? 'فارسی' : 'English', onTap: () => showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: [ListTile(title: const Text('فارسی'), trailing: fa ? const Icon(Icons.check, color: Color(0xFF0D6EFD)) : null, onTap: () { onLanguage(AppLang.fa); Navigator.pop(context); }), ListTile(title: const Text('English'), trailing: !fa ? const Icon(Icons.check, color: Color(0xFF0D6EFD)) : null, onTap: () { onLanguage(AppLang.en); Navigator.pop(context); })])))),
        _SettingsTile(icon: Icons.currency_exchange, title: tr(fa, 'واحد نمایش قیمت', 'Display currency'), value: currency.name.toUpperCase(), onTap: () => showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.all(18), child: Column(mainAxisSize: MainAxisSize.min, children: DisplayCurrency.values.map((c) => ListTile(title: Text(c == DisplayCurrency.afn ? 'AFN • افغانی' : c == DisplayCurrency.usd ? 'USD • Dollar' : 'TOMAN • تومان'), trailing: currency == c ? const Icon(Icons.check, color: Color(0xFF0D6EFD)) : null, onTap: () { onCurrency(c); Navigator.pop(context); })).toList())))),
        _SettingsTile(icon: Icons.notifications_outlined, title: tr(fa, 'اعلان‌ها', 'Notifications'), value: '', onTap: () {}),
        _SettingsTile(icon: Icons.support_agent_rounded, title: tr(fa, 'پشتیبانی', 'Support'), value: '', onTap: () {}),
        _SettingsTile(icon: Icons.shield_outlined, title: tr(fa, 'امنیت و حریم خصوصی', 'Security & privacy'), value: '', onTap: () {}),
        _SettingsTile(icon: Icons.info_outline, title: tr(fa, 'درباره VELIXEO', 'About VELIXEO'), value: 'v0.1.0', onTap: () {}),
      ]));
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({required this.icon, required this.title, required this.value, required this.onTap});
  final IconData icon;
  final String title, value;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: SoftCard(onTap: onTap, child: Row(children: [Icon(icon, color: const Color(0xFF0D6EFD)), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), if (value.isNotEmpty) Text(value, style: const TextStyle(color: Color(0xFF607487))), const SizedBox(width: 6), const Icon(Icons.chevron_right, size: 20)])));
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(width: double.infinity, height: 54, child: FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0D6EFD), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800))));
}

class SoftCard extends StatelessWidget {
  const SoftCard({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(20), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: child)));
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key});
  final String title;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)));
}

class ServiceCard extends StatelessWidget {
  const ServiceCard({super.key, required this.service, required this.fa, required this.onTap});
  final _Service service;
  final bool fa;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(borderRadius: BorderRadius.circular(18), onTap: onTap, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: service.color.withOpacity(.08), borderRadius: BorderRadius.circular(18), border: Border.all(color: service.color.withOpacity(.14))), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Container(width: 43, height: 43, decoration: BoxDecoration(color: service.color, borderRadius: BorderRadius.circular(14)), child: Icon(service.icon, color: Colors.white, size: 20)), const SizedBox(height: 8), Text(fa ? service.fa : service.en, maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))])));
}

class OrderTile extends StatelessWidget {
  const OrderTile({super.key, required this.title, required this.subtitle, required this.amount, required this.status, required this.color});
  final String title, subtitle, amount, status;
  final Color color;
  @override
  Widget build(BuildContext context) => SoftCard(child: Row(children: [CircleAvatar(backgroundColor: color.withOpacity(.1), child: Icon(Icons.shopping_bag_outlined, color: color)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF607487))), const SizedBox(height: 4), Text(status, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w700))])), Text(amount, style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.w900))]));
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.icon, required this.title, required this.amount, required this.positive});
  final IconData icon;
  final String title, amount;
  final bool positive;
  @override
  Widget build(BuildContext context) => SoftCard(child: Row(children: [CircleAvatar(backgroundColor: (positive ? const Color(0xFF18A875) : const Color(0xFFE65454)).withOpacity(.1), child: Icon(icon, color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454))), const SizedBox(width: 12), Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))), Text(amount, style: TextStyle(color: positive ? const Color(0xFF18A875) : const Color(0xFFE65454), fontWeight: FontWeight.w900))]));
}

class _Service {
  const _Service(this.fa, this.en, this.icon, this.color);
  final String fa, en;
  final IconData icon;
  final Color color;
}

void showSuccess(BuildContext context, bool fa, {bool wallet = false}) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      icon: const CircleAvatar(radius: 30, backgroundColor: Color(0xFFE4F8EF), child: Icon(Icons.check_rounded, color: Color(0xFF18A875), size: 34)),
      title: Text(wallet ? tr(fa, 'پرداخت ثبت شد', 'Payment submitted') : tr(fa, 'سفارش ثبت شد', 'Order placed')),
      content: Text(wallet ? tr(fa, 'در نسخه عملیاتی، پرداخت پس از تأیید امن Webhook حساب‌پی به کیف پول اضافه می‌شود.', 'In production, the wallet is credited only after secure HesabPay webhook verification.') : tr(fa, 'سفارش شما با موفقیت ثبت شد. وضعیت را از بخش سفارش‌ها دنبال کنید.', 'Your order was submitted successfully. Track it from Orders.')),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr(fa, 'باشه', 'OK')))],
    ),
  );
}
