import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/models.dart';
import 'promotion_models.dart';

abstract class PromotionPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
  String money(int amountAfn, {bool showBase});
  Future<void> refreshBalanceOnly();
}

class PromotionPanelPage extends StatefulWidget {
  const PromotionPanelPage({super.key, required this.host, this.initialServiceId});
  final PromotionPanelHost host;
  final String? initialServiceId;

  @override
  State<PromotionPanelPage> createState() => _PromotionPanelPageState();
}

class _PromotionPanelPageState extends State<PromotionPanelPage> {
  PromotionCatalog catalog = const PromotionCatalog();
  List<PromotionOrder> orders = const [];
  bool loading = true;
  String? error;
  bool initialOpened = false;

  PromotionPanelHost get host => widget.host;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final result = await Future.wait([
        host.api.promotionCatalog(),
        host.api.promotionOrders(),
      ]);
      catalog = result[0] as PromotionCatalog;
      orders = result[1] as List<PromotionOrder>;
      if (mounted) setState(() => loading = false);
      _openInitial();
    } on ApiException catch (e) {
      if (mounted) setState(() { loading = false; error = e.code; });
    } catch (_) {
      if (mounted) setState(() { loading = false; error = 'network_error'; });
    }
  }

  void _openInitial() {
    if (initialOpened || widget.initialServiceId?.isNotEmpty != true) return;
    PromotionProduct? product;
    for (final item in catalog.products) {
      if (item.id == widget.initialServiceId) product = item;
    }
    if (product == null) return;
    initialOpened = true;
    final target = product;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => PromotionOrderPage(host: host, product: target!)),
      );
      if (changed == true) await load();
    });
  }

  Future<void> open(PromotionProduct product) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PromotionOrderPage(host: host, product: product)),
    );
    if (changed == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('تبلیغات اینستاگرام و فیسبوک', 'Instagram & Facebook Promotions'))),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _PromotionBanner(fa: fa, banner: catalog.banner),
            const SizedBox(height: 14),
            _InfoCard(
              icon: Icons.security_rounded,
              title: t('بدون رمز عبور و بدون کارت بانکی', 'No password and no bank card required'),
              body: t(
                'شما لینک پست و کد رسمی اجازه تبلیغ متا را می‌فرستید؛ هزینه از کیف پول VELIXEO پرداخت می‌شود و تیم ما تبلیغ را از حساب تبلیغاتی خود اجرا می‌کند.',
                'Share your post link and Meta partnership ad code. Pay from your VELIXEO wallet, and our team launches the ad from our ad account.',
              ),
            ),
            const SizedBox(height: 18),
            Text(t('انتخاب پلتفرم', 'Choose a platform'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            if (loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 35), child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              _InfoCard(icon: Icons.cloud_off_rounded, title: t('دریافت اطلاعات انجام نشد', 'Could not load promotions'), body: error!, error: true)
            else if (catalog.products.isEmpty)
              _InfoCard(
                icon: Icons.campaign_outlined,
                title: t('هنوز پکیجی اضافه نشده', 'No promotion packages yet'),
                body: t('پکیج‌ها از پنل مدیریت VELIXEO اضافه می‌شوند.', 'Packages are created from VELIXEO Admin.'),
              )
            else
              ...catalog.products.map((product) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => open(product),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5EBF2)),
                        ),
                        child: Row(
                          children: [
                            _PlatformIcon(product: product, size: 54),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fa ? product.titleFa : product.titleEn,
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    t(
                                      'بررسی و شروع معمولاً تا ${product.deliveryMaxHours} ساعت',
                                      'Review and launch usually within ${product.deliveryMaxHours} hours',
                                    ),
                                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF718197)),
                                  ),
                                ],
                              ),
                            ),
                            if (product.minPriceAfn != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(t('از', 'From'), style: const TextStyle(fontSize: 9, color: Color(0xFF8A97A6))),
                                  Text(host.money(product.minPriceAfn!), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF1686FF))),
                                ],
                              ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF8794A3)),
                          ],
                        ),
                      ),
                    ),
                  )),
            if (orders.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(t('سفارش‌های تبلیغ اخیر', 'Recent promotion orders'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              ...orders.take(5).map((order) => _OrderCard(host: host, order: order)),
            ],
          ],
        ),
      ),
    );
  }
}

class PromotionOrderPage extends StatefulWidget {
  const PromotionOrderPage({super.key, required this.host, required this.product});
  final PromotionPanelHost host;
  final PromotionProduct product;

  @override
  State<PromotionOrderPage> createState() => _PromotionOrderPageState();
}

class _PromotionOrderPageState extends State<PromotionOrderPage> {
  final postUrl = TextEditingController();
  final adCode = TextEditingController();
  final countries = TextEditingController(text: 'Afghanistan');
  final audienceNotes = TextEditingController();
  final websiteUrl = TextEditingController();
  PromotionPackage? selectedPackage;
  String? objective;
  bool submitting = false;
  String? error;

  PromotionPanelHost get host => widget.host;
  PromotionProduct get product => widget.product;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    for (final pkg in product.packages) {
      if (pkg.enabled) {
        selectedPackage = pkg;
        break;
      }
    }
    objective = product.supportedObjectives.isNotEmpty ? product.supportedObjectives.first : 'ENGAGEMENT';
  }

  @override
  void dispose() {
    postUrl.dispose();
    adCode.dispose();
    countries.dispose();
    audienceNotes.dispose();
    websiteUrl.dispose();
    super.dispose();
  }

  String newRequestId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String objectiveLabel(String value) {
    switch (value) {
      case 'PROFILE_VISITS':
        return t('بازدید پروفایل', 'Profile visits');
      case 'MESSAGES':
        return t('پیام‌ها', 'Messages');
      case 'WEBSITE_VISITS':
        return t('بازدید وب‌سایت', 'Website visits');
      case 'AWARENESS':
        return t('آگاهی و دیده‌شدن', 'Awareness');
      default:
        return t('تعامل', 'Engagement');
    }
  }

  String errorText(String code) {
    switch (code) {
      case 'insufficient_funds':
        return t('موجودی کیف پول کافی نیست.', 'Your wallet balance is not enough.');
      case 'partnership_ad_code_required':
        return t('کد اجازه تبلیغ متا الزامی است.', 'A Meta partnership ad code is required.');
      case 'website_url_required':
        return t('برای هدف بازدید وب‌سایت، لینک وب‌سایت را وارد کنید.', 'Website URL is required for Website visits.');
      case 'package_unavailable':
        return t('این پکیج فعلاً در دسترس نیست.', 'This package is currently unavailable.');
      default:
        return code.replaceAll('_', ' ');
    }
  }

  Future<void> showCodeHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('چطور کد اجازه تبلیغ را بگیرم؟', 'How do I get a partnership ad code?')),
        content: SingleChildScrollView(
          child: Text(
            product.platform == 'FACEBOOK'
                ? t(
                    '۱. پست یا Reel موردنظر را در Facebook باز کنید.\n۲. روی سه‌نقطه بزنید.\n۳. گزینه مربوط به Partnership Ad / Share partnership ad code را باز کنید.\n۴. Get partnership ad code را فعال کنید.\n۵. کد را Copy کرده و اینجا وارد کنید.\n\nاگر این گزینه را نمی‌بینید، حساب یا محتوا ممکن است برای Partnership Ads واجد شرایط نباشد.',
                    '1. Open the Facebook post or Reel you want to promote.\n2. Tap the three-dot menu.\n3. Open the Partnership Ad / Share partnership ad code option.\n4. Enable Get partnership ad code.\n5. Copy the code and paste it here.\n\nIf you do not see this option, the account or content may not be eligible for Partnership Ads.',
                  )
                : t(
                    '۱. Instagram را باز کنید و وارد پست یا Reel موردنظر شوید.\n۲. روی سه‌نقطه بزنید.\n۳. Partnership label and ads را باز کنید.\n۴. Get partnership ad code را فعال کنید.\n۵. کد را Copy کرده و اینجا وارد کنید.\n\nحساب باید Professional و محتوای شما واجد شرایط Partnership Ads باشد. رمز عبور یا کد OTP را برای ما نفرستید.',
                    '1. Open Instagram and select the post or Reel you want to promote.\n2. Tap the three-dot menu.\n3. Open Partnership label and ads.\n4. Turn on Get partnership ad code.\n5. Copy the code and paste it here.\n\nYour account must be professional and the content must be eligible for Partnership Ads. Never send us your password or OTP.',
                  ),
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('متوجه شدم', 'Got it')))],
      ),
    );
  }

  Future<void> submit() async {
    final pkg = selectedPackage;
    final objectiveValue = objective;
    if (pkg == null || objectiveValue == null || submitting) return;
    if (postUrl.text.trim().isEmpty || !postUrl.text.trim().startsWith('http')) {
      setState(() => error = t('لینک صحیح پست یا Reel را وارد کنید.', 'Enter a valid post or Reel link.'));
      return;
    }
    if (product.requirePartnershipAdCode && adCode.text.trim().isEmpty) {
      setState(() => error = errorText('partnership_ad_code_required'));
      return;
    }
    final targetCountries = countries.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (targetCountries.isEmpty) {
      setState(() => error = t('حداقل یک کشور هدف وارد کنید.', 'Enter at least one target country.'));
      return;
    }
    if (objectiveValue == 'WEBSITE_VISITS' && websiteUrl.text.trim().isEmpty) {
      setState(() => error = errorText('website_url_required'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('تأیید سفارش تبلیغ', 'Confirm promotion order')),
        content: Text(
          t(
            'مبلغ ${host.money(pkg.priceAfn)} از کیف پول شما کسر می‌شود. تیم VELIXEO ابتدا لینک و کد اجازه تبلیغ را بررسی می‌کند و سپس کمپین را در Meta Ads Manager اجرا می‌کند. نتیجه دقیق تبلیغ تضمین‌شده نیست و به مزایده و مخاطب متا بستگی دارد.',
            '${host.money(pkg.priceAfn)} will be charged from your wallet. VELIXEO will review the post and partnership permission, then launch the campaign in Meta Ads Manager. Exact performance is not guaranteed and depends on Meta auction and audience conditions.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('لغو', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('پرداخت و ثبت', 'Pay & place order'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() { submitting = true; error = null; });
    try {
      final result = await host.api.createPromotionOrder(
        serviceId: product.id,
        packageId: pkg.id,
        postUrl: postUrl.text.trim(),
        partnershipAdCode: adCode.text.trim(),
        objective: objectiveValue,
        targetCountries: targetCountries,
        audienceNotes: audienceNotes.text.trim(),
        websiteUrl: websiteUrl.text.trim(),
        clientRequestId: newRequestId(),
      );
      await host.refreshBalanceOnly();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF18A875), size: 48),
          title: Text(t('سفارش تبلیغ ثبت شد', 'Promotion order placed')),
          content: Text(
            t(
              'پرداخت انجام شد. شماره سفارش #${result.order.publicOrderNumber ?? result.order.id.substring(0, 8)} است. ابتدا مجوز تبلیغ بررسی و سپس کمپین اجرا می‌شود.',
              'Payment completed. Order #${result.order.publicOrderNumber ?? result.order.id.substring(0, 8)} is queued for permission review and campaign launch.',
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('باشه', 'Done')))],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = errorText(e.code));
    } catch (_) {
      if (mounted) setState(() => error = t('ارتباط با سرور برقرار نشد.', 'Could not connect to the server.'));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = fa ? product.descriptionFa : product.descriptionEn;
    final instructions = fa ? product.instructionsFa : product.instructionsEn;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? product.titleFa : product.titleEn)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: product.platform == 'INSTAGRAM'
                    ? const [Color(0xFF7A42D8), Color(0xFFF04471), Color(0xFFFFA32F)]
                    : const [Color(0xFF1268E8), Color(0xFF2B8BFF)],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _PlatformIcon(product: product, size: 64, light: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fa ? product.titleFa : product.titleEn, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 5),
                    Text(
                      t('پرداخت از کیف پول VELIXEO · بدون دریافت رمز عبور', 'VELIXEO Wallet payment · No password required'),
                      style: const TextStyle(color: Color(0xFFF1F4FF), fontSize: 10.5),
                    ),
                  ]),
                ),
              ],
            ),
          ),
          if (description?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 14),
            Text(description!, style: const TextStyle(color: Color(0xFF607487), height: 1.55)),
          ],
          const SizedBox(height: 18),
          Text(t('انتخاب پکیج', 'Choose a package'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 9),
          ...product.packages.where((p) => p.enabled).map((pkg) {
            final selected = selectedPackage?.id == pkg.id;
            final badge = fa ? pkg.badgeFa : pkg.badgeEn;
            final estimate = fa ? pkg.estimateFa : pkg.estimateEn;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() => selectedPackage = pkg),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFEFF6FF) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: selected ? const Color(0xFF1686FF) : const Color(0xFFE3EAF2), width: selected ? 1.5 : 1),
                  ),
                  child: Column(
                    children: [
                      Row(children: [
                        Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: const Color(0xFF1686FF)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(fa ? pkg.titleFa : pkg.titleEn, style: const TextStyle(fontWeight: FontWeight.w900))),
                            if (badge?.trim().isNotEmpty == true) ...[
                              const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFEBC4), borderRadius: BorderRadius.circular(999)), child: Text(badge!, style: const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w800, color: Color(0xFFA96B08)))),
                            ],
                          ]),
                          Text(t('${pkg.durationDays} روز تبلیغ', '${pkg.durationDays} days'), style: const TextStyle(fontSize: 10.5, color: Color(0xFF7D8B9B))),
                        ])),
                        Text(host.money(pkg.priceAfn), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1686FF))),
                      ]),
                      if (estimate?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerLeft, child: Text(estimate!, style: const TextStyle(fontSize: 9.5, color: Color(0xFF7B8999)))),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          if (instructions?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _InfoCard(icon: Icons.info_outline_rounded, title: t('قبل از سفارش', 'Before ordering'), body: instructions!),
          ],
          const SizedBox(height: 18),
          Text(t('اطلاعات تبلیغ', 'Promotion details'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          TextField(
            controller: postUrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: t('لینک پست یا Reel *', 'Post or Reel URL *'),
              hintText: product.platform == 'INSTAGRAM' ? 'https://www.instagram.com/...' : 'https://www.facebook.com/...',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: adCode,
            decoration: InputDecoration(
              labelText: t('کد اجازه تبلیغ متا *', 'Partnership ad code *'),
              hintText: 'adcode-...',
              suffixIcon: IconButton(onPressed: showCodeHelp, icon: const Icon(Icons.help_outline_rounded)),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: showCodeHelp,
              icon: const Icon(Icons.help_outline_rounded, size: 17),
              label: Text(t('چطور کد را بگیرم؟', 'How do I get this code?')),
            ),
          ),
          DropdownButtonFormField<String>(
            value: objective,
            decoration: InputDecoration(labelText: t('هدف تبلیغ', 'Campaign objective')),
            items: product.supportedObjectives.map((value) => DropdownMenuItem(value: value, child: Text(objectiveLabel(value)))).toList(growable: false),
            onChanged: (value) => setState(() => objective = value),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: countries,
            decoration: InputDecoration(
              labelText: t('کشورهای هدف *', 'Target countries *'),
              hintText: t('افغانستان، تاجیکستان', 'Afghanistan, Tajikistan'),
              helperText: t('اگر چند کشور است با ویرگول جدا کنید.', 'Separate multiple countries with commas.'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: audienceNotes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: t('توضیحات مخاطب (اختیاری)', 'Audience notes (optional)'),
              hintText: t('مثلاً مرد و زن ۱۸ تا ۳۵ سال، علاقه‌مند به تکنولوژی', 'Example: ages 18–35, interested in technology'),
            ),
          ),
          if (objective == 'WEBSITE_VISITS') ...[
            const SizedBox(height: 10),
            TextField(
              controller: websiteUrl,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: t('لینک وب‌سایت *', 'Website URL *')),
            ),
          ],
          const SizedBox(height: 14),
          _InfoCard(
            icon: Icons.gavel_rounded,
            title: t('نتیجه تبلیغ تضمینی نیست', 'Ad results are not guaranteed'),
            body: t(
              'Reach، Impression، پیام یا کلیک به مزایده Meta، کشور هدف، کیفیت محتوا و رقابت بستگی دارد. مبلغ پکیج هزینه اجرای سرویس و بودجه مشخص‌شده برای تبلیغ را پوشش می‌دهد.',
              'Reach, impressions, messages and clicks depend on Meta auction, audience, content quality and competition. Package pricing covers the configured ad budget and service fee.',
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            _InfoCard(icon: Icons.error_outline_rounded, title: t('سفارش ثبت نشد', 'Order not placed'), body: error!, error: true),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(color: const Color(0xFFF6F9FC), borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE4EAF1))),
            child: Row(children: [
              const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF1686FF)),
              const SizedBox(width: 10),
              Expanded(child: Text(t('موجودی کیف پول', 'Wallet balance'), style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(host.money(host.balanceAfn), style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: submitting || selectedPackage == null ? null : submit,
              child: Text(
                selectedPackage == null
                    ? t('پکیجی موجود نیست', 'No package available')
                    : submitting
                        ? t('در حال ثبت...', 'Placing order...')
                        : t('پرداخت و ثبت سفارش — ${host.money(selectedPackage!.priceAfn)}', 'Pay & place order — ${host.money(selectedPackage!.priceAfn)}'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotionBanner extends StatelessWidget {
  const _PromotionBanner({required this.fa, this.banner});
  final bool fa;
  final AppBanner? banner;

  String t(String faText, String enText) => fa ? faText : enText;

  @override
  Widget build(BuildContext context) {
    final title = fa ? banner?.titleFa : banner?.titleEn;
    final subtitle = fa ? banner?.subtitleFa : banner?.subtitleEn;
    final image = banner?.imageUrl.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(23),
      child: SizedBox(
        height: 160,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6B42D8), Color(0xFFF04471), Color(0xFFFFA32F)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
            if (image.isNotEmpty) Image.network(image, fit: BoxFit.cover, cacheWidth: 1080, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            Container(color: const Color(0xFF11162A).withValues(alpha: .34)),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(title?.trim().isNotEmpty == true ? title! : t('تبلیغات حرفه‌ای اینستاگرام و فیسبوک', 'Instagram & Facebook Promotions'), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 7),
                  Text(
                    subtitle?.trim().isNotEmpty == true ? subtitle! : t('بدون ویزاکارت؛ لینک پست و مجوز تبلیغ را بفرست و از کیف پول پرداخت کن.', 'No bank card needed. Share the post and ad permission, then pay from your wallet.'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFF4F3FF), fontSize: 11.2, height: 1.45),
                  ),
                ])),
                const SizedBox(width: 10),
                Container(width: 62, height: 62, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)), child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 33)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformIcon extends StatelessWidget {
  const _PlatformIcon({required this.product, required this.size, this.light = false});
  final PromotionProduct product;
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final color = product.platform == 'FACEBOOK' ? const Color(0xFF1877F2) : const Color(0xFFE4405F);
    final image = product.iconUrl?.trim() ?? '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: light ? Colors.white.withValues(alpha: .15) : color.withValues(alpha: .10), borderRadius: BorderRadius.circular(size * .28)),
      clipBehavior: Clip.antiAlias,
      child: image.isEmpty
          ? Icon(product.platform == 'FACEBOOK' ? Icons.facebook_rounded : Icons.camera_alt_rounded, color: light ? Colors.white : color, size: size * .48)
          : Image.network(image, fit: BoxFit.contain, cacheWidth: 192, errorBuilder: (_, __, ___) => Icon(Icons.campaign_rounded, color: light ? Colors.white : color)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.body, this.error = false});
  final IconData icon;
  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFE65454) : const Color(0xFF1686FF);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: color.withValues(alpha: .07), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withValues(alpha: .18))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 3),
          Text(body, style: const TextStyle(fontSize: 11, color: Color(0xFF65778A), height: 1.45)),
        ])),
      ]),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.host, required this.order});
  final PromotionPanelHost host;
  final PromotionOrder order;

  String t(String faText, String enText) => host.fa ? faText : enText;

  Color stateColor() {
    switch (order.promotionState) {
      case 'ACTIVE':
      case 'COMPLETED':
        return const Color(0xFF18A875);
      case 'NEED_INFORMATION':
        return const Color(0xFFF0A326);
      case 'REFUNDED':
      case 'FAILED':
        return const Color(0xFFE65454);
      default:
        return const Color(0xFF1686FF);
    }
  }

  String stateLabel() {
    switch (order.promotionState) {
      case 'REVIEWING_CODE': return t('در حال بررسی مجوز', 'Reviewing permission');
      case 'NEED_INFORMATION': return t('نیاز به اطلاعات', 'Need information');
      case 'READY_TO_LAUNCH': return t('آماده اجرا', 'Ready to launch');
      case 'ACTIVE': return t('فعال', 'Active');
      case 'COMPLETED': return t('تکمیل شده', 'Completed');
      case 'REFUNDED': return t('بازپرداخت شده', 'Refunded');
      default: return t('در انتظار بررسی', 'Pending review');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = stateColor();
    final message = host.fa ? order.adminMessageFa : order.adminMessageEn;
    final result = host.fa ? order.resultSummaryFa : order.resultSummaryEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE6ECF3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(host.fa ? (order.serviceTitleFa ?? 'تبلیغ') : (order.serviceTitleEn ?? 'Promotion'), style: const TextStyle(fontWeight: FontWeight.w900))),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)), child: Text(stateLabel(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: color))),
        ]),
        const SizedBox(height: 4),
        Text('#${order.publicOrderNumber ?? order.id.substring(0,8)} · ${host.money(order.totalAmountAfn)}', style: const TextStyle(fontSize: 10.5, color: Color(0xFF748497))),
        if (message?.trim().isNotEmpty == true) ...[const SizedBox(height: 7), Text(message!, style: const TextStyle(fontSize: 11, height: 1.4))],
        if (result?.trim().isNotEmpty == true) ...[const SizedBox(height: 7), Text(result!, style: const TextStyle(fontSize: 11, height: 1.4, fontWeight: FontWeight.w700))],
      ]),
    );
  }
}
