import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/models.dart';
import 'premium_models.dart';

abstract class PremiumPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
  String money(int amountAfn, {bool showBase});
  Future<void> refreshBalanceOnly();
}

class PremiumPanelPage extends StatefulWidget {
  const PremiumPanelPage({super.key, required this.host, this.initialServiceId});

  final PremiumPanelHost host;
  final String? initialServiceId;

  @override
  State<PremiumPanelPage> createState() => _PremiumPanelPageState();
}

class _PremiumPanelPageState extends State<PremiumPanelPage> {
  final search = TextEditingController();
  PremiumCatalog catalog = const PremiumCatalog();
  List<PremiumOrder> orders = const [];
  String group = 'ALL';
  bool loading = true;
  String? error;
  bool initialOpened = false;

  PremiumPanelHost get host => widget.host;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    search.addListener(() => setState(() {}));
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() {
      loading = true;
      error = null;
    });
    try {
      final results = await Future.wait([
        host.api.premiumCatalog(),
        host.api.premiumOrders(),
      ]);
      catalog = results[0] as PremiumCatalog;
      orders = results[1] as List<PremiumOrder>;
      if (mounted) setState(() => loading = false);
      _openInitialProductIfNeeded();
    } on ApiException catch (e) {
      if (mounted) setState(() {
        loading = false;
        error = e.code;
      });
    } catch (_) {
      if (mounted) setState(() {
        loading = false;
        error = 'network_error';
      });
    }
  }

  void _openInitialProductIfNeeded() {
    if (initialOpened || widget.initialServiceId?.isNotEmpty != true) return;
    final product = catalog.products.where((item) => item.id == widget.initialServiceId).firstOrNull;
    if (product == null) return;
    initialOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => PremiumProductPage(host: host, product: product)),
      );
      if (changed == true) await load();
    });
  }

  List<PremiumProduct> get visibleProducts {
    final q = search.text.trim().toLowerCase();
    return catalog.products.where((item) {
      if (group != 'ALL' && item.group != group) return false;
      if (q.isEmpty) return true;
      return [
        item.titleFa,
        item.titleEn,
        item.slug,
        item.group,
      ].any((value) => value.toLowerCase().contains(q));
    }).toList(growable: false);
  }

  String groupLabel(String value) {
    switch (value) {
      case 'MESSAGING':
        return t('پیام‌رسان', 'Messaging');
      case 'SOCIAL':
        return t('شبکه اجتماعی', 'Social');
      case 'VPN':
        return 'VPN';
      case 'STREAMING':
        return t('استریم', 'Streaming');
      case 'AI':
        return 'AI';
      case 'OTHER':
        return t('سایر', 'Other');
      default:
        return t('همه', 'All');
    }
  }

  Color groupColor(String value) {
    switch (value) {
      case 'MESSAGING':
        return const Color(0xFF2D9CDB);
      case 'SOCIAL':
        return const Color(0xFFE2528D);
      case 'VPN':
        return const Color(0xFF7257E8);
      case 'STREAMING':
        return const Color(0xFFE54747);
      case 'AI':
        return const Color(0xFF20A47A);
      default:
        return const Color(0xFFF3A523);
    }
  }

  Future<void> openProduct(PremiumProduct product) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PremiumProductPage(host: host, product: product)),
    );
    if (changed == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ['ALL', ...{
      for (final product in catalog.products) product.group,
    }];
    return Scaffold(
      appBar: AppBar(
        title: Text(t('اکانت‌های پریمیوم', 'Premium Accounts')),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            _PremiumBanner(fa: fa, banner: catalog.banner),
            const SizedBox(height: 14),
            TextField(
              controller: search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: t('جستجوی تلگرام پریمیوم، اسنپ‌چت پلاس...', 'Search Telegram Premium, Snapchat+...'),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(onPressed: search.clear, icon: const Icon(Icons.close_rounded)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final value = groups[index];
                  final selected = group == value;
                  return ChoiceChip(
                    label: Text(groupLabel(value)),
                    selected: selected,
                    onSelected: (_) => setState(() => group = value),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('محصولات پریمیوم', 'Premium products'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  t('${visibleProducts.length} محصول', '${visibleProducts.length} products'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF718197)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              _PremiumNotice(
                icon: Icons.cloud_off_rounded,
                title: t('دریافت اطلاعات انجام نشد', 'Could not load Premium catalog'),
                body: error!,
              )
            else if (visibleProducts.isEmpty)
              _PremiumNotice(
                icon: Icons.workspace_premium_outlined,
                title: t('محصولی پیدا نشد', 'No products found'),
                body: t(
                  'محصولات از پنل مدیریت VELIXEO اضافه می‌شوند.',
                  'Products are managed from VELIXEO Admin.',
                ),
              )
            else
              ...visibleProducts.map((product) {
                final color = groupColor(product.group);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => openProduct(product),
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE7EDF4)),
                      ),
                      child: Row(
                        children: [
                          _PremiumProductIcon(product: product, color: color, size: 50),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Flexible(
                                    child: Text(
                                      fa ? product.titleFa : product.titleEn,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
                                    ),
                                  ),
                                  if (product.featured) ...[
                                    const SizedBox(width: 5),
                                    const Icon(Icons.star_rounded, color: Color(0xFFFFA928), size: 17),
                                  ],
                                ]),
                                const SizedBox(height: 4),
                                Text(
                                  t(
                                    'تحویل ${product.deliveryMinHours} تا ${product.deliveryMaxHours} ساعت',
                                    'Delivery in ${product.deliveryMinHours}–${product.deliveryMaxHours} hours',
                                  ),
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF76879A)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (product.minPriceAfn != null) ...[
                                Text(
                                  t('از', 'From'),
                                  style: const TextStyle(fontSize: 9.5, color: Color(0xFF8795A6)),
                                ),
                                Text(
                                  host.money(product.minPriceAfn!),
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF1686FF)),
                                ),
                              ],
                              const SizedBox(height: 4),
                              const Icon(Icons.chevron_right_rounded, color: Color(0xFF7F8C9B)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            if (orders.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text(
                t('سفارش‌های اخیر پریمیوم', 'Recent Premium orders'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 9),
              ...orders.take(5).map((order) => _PremiumOrderCard(host: host, order: order)),
            ],
          ],
        ),
      ),
    );
  }
}

class PremiumProductPage extends StatefulWidget {
  const PremiumProductPage({super.key, required this.host, required this.product});

  final PremiumPanelHost host;
  final PremiumProduct product;

  @override
  State<PremiumProductPage> createState() => _PremiumProductPageState();
}

class _PremiumProductPageState extends State<PremiumProductPage> {
  final controllers = <String, TextEditingController>{};
  final selectValues = <String, String>{};
  PremiumPackage? selectedPackage;
  bool submitting = false;
  String? error;

  PremiumPanelHost get host => widget.host;
  PremiumProduct get product => widget.product;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    selectedPackage = product.packages.where((item) => item.available).firstOrNull;
    for (final field in product.formFields) {
      if (field.type == 'SELECT') {
        if (field.options.isNotEmpty) selectValues[field.key] = field.options.first;
      } else {
        controllers[field.key] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
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

  String fieldValue(PremiumFormField field) {
    if (field.type == 'SELECT') return selectValues[field.key] ?? '';
    return controllers[field.key]?.text.trim() ?? '';
  }

  Map<String, String>? validateFields() {
    final out = <String, String>{};
    for (final field in product.formFields) {
      final value = fieldValue(field);
      if (field.required && value.isEmpty) {
        setState(() => error = t(
          'لطفاً «${field.labelFa}» را وارد کنید.',
          'Please enter “${field.labelEn}”.',
        ));
        return null;
      }
      if (value.isNotEmpty) out[field.key] = value;
    }
    return out;
  }

  String errorText(String code) {
    if (code.startsWith('required_field:')) return t('یکی از اطلاعات ضروری وارد نشده است.', 'A required field is missing.');
    switch (code) {
      case 'insufficient_funds':
        return t('موجودی کیف پول کافی نیست. ابتدا کیف پول را شارژ کنید.', 'Your wallet balance is not enough. Please add funds first.');
      case 'package_unavailable':
        return t('این پکیج فعلاً موجود نیست. لیست را تازه‌سازی کنید.', 'This package is currently unavailable. Refresh the catalog.');
      case 'service_unavailable':
        return t('این سرویس فعلاً غیرفعال است.', 'This service is currently unavailable.');
      case 'network_error':
        return t('ارتباط با سرور برقرار نشد.', 'Could not connect to the server.');
      default:
        return code.replaceAll('_', ' ');
    }
  }

  Future<void> submit() async {
    final pkg = selectedPackage;
    if (pkg == null || submitting) return;
    final fields = validateFields();
    if (fields == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('تأیید سفارش', 'Confirm order')),
        content: Text(
          t(
            'مبلغ ${host.money(pkg.priceAfn)} همین حالا از کیف پول شما کسر می‌شود. فعال‌سازی معمولاً تا ${product.deliveryMaxHours} ساعت انجام می‌شود.',
            '${host.money(pkg.priceAfn)} will be charged from your wallet now. Fulfillment is normally completed within ${product.deliveryMaxHours} hours.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('لغو', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('پرداخت و ثبت سفارش', 'Pay & place order'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final result = await host.api.createPremiumOrder(
        serviceId: product.id,
        packageId: pkg.id,
        fields: fields,
        clientRequestId: newRequestId(),
      );
      await host.refreshBalanceOnly();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_rounded, color: Color(0xFF18A875), size: 48),
          title: Text(t('سفارش ثبت شد', 'Order placed')),
          content: Text(
            t(
              'پرداخت با موفقیت انجام شد. شماره سفارش #${result.order.publicOrderNumber ?? result.order.id.substring(0, 8)} است و فعال‌سازی حداکثر تا ${product.deliveryMaxHours} ساعت انجام می‌شود.',
              'Payment was successful. Order #${result.order.publicOrderNumber ?? result.order.id.substring(0, 8)} is now queued and will be fulfilled within ${product.deliveryMaxHours} hours.',
            ),
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('باشه', 'Done'))),
          ],
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => error = errorText(e.code));
    } catch (_) {
      if (mounted) setState(() => error = errorText('network_error'));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Widget fieldWidget(PremiumFormField field) {
    final label = fa ? field.labelFa : field.labelEn;
    final placeholder = fa ? field.placeholderFa : field.placeholderEn;
    if (field.type == 'SELECT') {
      return DropdownButtonFormField<String>(
        value: selectValues[field.key],
        decoration: InputDecoration(labelText: field.required ? '$label *' : label),
        items: field.options.map((option) => DropdownMenuItem(value: option, child: Text(option))).toList(growable: false),
        onChanged: (value) => setState(() => selectValues[field.key] = value ?? ''),
      );
    }
    TextInputType? keyboardType;
    if (field.type == 'PHONE') keyboardType = TextInputType.phone;
    if (field.type == 'EMAIL') keyboardType = TextInputType.emailAddress;
    return TextField(
      controller: controllers[field.key],
      keyboardType: keyboardType,
      maxLines: field.type == 'TEXTAREA' ? 3 : 1,
      decoration: InputDecoration(
        labelText: field.required ? '$label *' : label,
        hintText: placeholder?.isNotEmpty == true ? placeholder : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final description = fa ? product.descriptionFa : product.descriptionEn;
    final instructions = fa ? product.instructionsFa : product.instructionsEn;
    return Scaffold(
      appBar: AppBar(title: Text(fa ? product.titleFa : product.titleEn)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(17),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF6646E8), Color(0xFFFFA02F)]),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _PremiumProductIcon(product: product, color: Colors.white, size: 64, darkBackground: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fa ? product.titleFa : product.titleEn, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(
                        t(
                          'تحویل ${product.deliveryMinHours} تا ${product.deliveryMaxHours} ساعت',
                          'Delivery in ${product.deliveryMinHours}–${product.deliveryMaxHours} hours',
                        ),
                        style: const TextStyle(color: Color(0xFFF3EFFF), fontSize: 11.5),
                      ),
                    ],
                  ),
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
          ...product.packages.map((pkg) {
            final selected = selectedPackage?.id == pkg.id;
            final title = fa ? pkg.titleFa : pkg.titleEn;
            final duration = fa ? pkg.durationFa : pkg.durationEn;
            final badge = fa ? pkg.badgeFa : pkg.badgeEn;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: pkg.available ? () => setState(() => selectedPackage = pkg) : null,
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFFF8E9) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: selected ? const Color(0xFFFFA928) : const Color(0xFFE3EAF2), width: selected ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: pkg.available ? const Color(0xFFF3A523) : const Color(0xFFB3BDC8)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(title.isNotEmpty ? title : duration, style: const TextStyle(fontWeight: FontWeight.w900))),
                            if (badge?.trim().isNotEmpty == true) ...[
                              const SizedBox(width: 6),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFEBC4), borderRadius: BorderRadius.circular(999)), child: Text(badge!, style: const TextStyle(fontSize: 8.5, color: Color(0xFFA96B08), fontWeight: FontWeight.w800))),
                            ],
                          ]),
                          if (duration.isNotEmpty) Text(duration, style: const TextStyle(fontSize: 10.5, color: Color(0xFF7D8B9B))),
                          if (!pkg.available) Text(t('ناموجود', 'Out of stock'), style: const TextStyle(fontSize: 10, color: Color(0xFFE65454))),
                        ]),
                      ),
                      Text(host.money(pkg.priceAfn), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF1686FF))),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (instructions?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 9),
            _PremiumNotice(icon: Icons.info_outline_rounded, title: t('قبل از خرید', 'Before purchase'), body: instructions!),
          ],
          const SizedBox(height: 18),
          Text(t('اطلاعات موردنیاز', 'Required information'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(
            t('فقط اطلاعات لازم برای فعال‌سازی را وارد کنید. رمز عبور درخواست نمی‌شود.', 'Enter only the information needed for activation. Passwords are not requested.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF7C8A9B)),
          ),
          const SizedBox(height: 10),
          ...product.formFields.map((field) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: fieldWidget(field),
              )),
          if (error != null) ...[
            const SizedBox(height: 4),
            _PremiumNotice(icon: Icons.error_outline_rounded, title: t('سفارش ثبت نشد', 'Order not placed'), body: error!, error: true),
          ],
          const SizedBox(height: 18),
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
                    ? t('پکیج موجودی نیست', 'No package available')
                    : submitting
                        ? t('در حال ثبت...', 'Placing order...')
                        : t(
                            'پرداخت و ثبت سفارش — ${host.money(selectedPackage!.priceAfn)}',
                            'Pay & place order — ${host.money(selectedPackage!.priceAfn)}',
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner({required this.fa, this.banner});

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
        height: 154,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF6246D9), Color(0xFFFFA12D)], begin: Alignment.topLeft, end: Alignment.bottomRight))),
            if (image.isNotEmpty)
              Image.network(
                image,
                fit: BoxFit.cover,
                cacheWidth: 1080,
                filterQuality: FilterQuality.low,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xC8121631), Color(0x33121631)]))),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title?.trim().isNotEmpty == true ? title! : t('اکانت‌های پریمیوم', 'Premium Accounts'),
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          subtitle?.trim().isNotEmpty == true
                              ? subtitle!
                              : t(
                                  'پکیج پریمیوم را انتخاب کنید، از کیف پول پرداخت کنید و فعال‌سازی توسط تیم ما انجام می‌شود.',
                                  'Choose a premium package, pay from your wallet, and our team completes the activation.',
                                ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFEDEBFF), fontSize: 11.5, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumProductIcon extends StatelessWidget {
  const _PremiumProductIcon({
    required this.product,
    required this.color,
    required this.size,
    this.darkBackground = false,
  });

  final PremiumProduct product;
  final Color color;
  final double size;
  final bool darkBackground;

  @override
  Widget build(BuildContext context) {
    final image = product.iconUrl?.trim() ?? '';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: darkBackground ? Colors.white.withValues(alpha: .15) : color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(size * .28),
      ),
      clipBehavior: Clip.antiAlias,
      child: image.isEmpty
          ? Icon(Icons.workspace_premium_rounded, color: darkBackground ? Colors.white : color, size: size * .48)
          : Image.network(
              image,
              fit: BoxFit.contain,
              cacheWidth: 192,
              errorBuilder: (_, __, ___) => Icon(Icons.workspace_premium_rounded, color: darkBackground ? Colors.white : color),
            ),
    );
  }
}

class _PremiumNotice extends StatelessWidget {
  const _PremiumNotice({
    required this.icon,
    required this.title,
    required this.body,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final color = error ? const Color(0xFFE65454) : const Color(0xFF1686FF);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
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

class _PremiumOrderCard extends StatelessWidget {
  const _PremiumOrderCard({required this.host, required this.order});

  final PremiumPanelHost host;
  final PremiumOrder order;

  String t(String faText, String enText) => host.fa ? faText : enText;

  Color stateColor() {
    switch (order.premiumState) {
      case 'COMPLETED':
        return const Color(0xFF18A875);
      case 'PROCESSING':
        return const Color(0xFF1686FF);
      case 'NEED_INFORMATION':
        return const Color(0xFFF0A326);
      case 'REFUNDED':
      case 'FAILED':
      case 'CANCELLED':
        return const Color(0xFFE65454);
      default:
        return const Color(0xFFF0A326);
    }
  }

  String stateLabel() {
    switch (order.premiumState) {
      case 'COMPLETED':
        return t('تکمیل شده', 'Completed');
      case 'PROCESSING':
        return t('در حال انجام', 'Processing');
      case 'NEED_INFORMATION':
        return t('نیاز به اطلاعات', 'Need information');
      case 'REFUNDED':
        return t('برگشت وجه', 'Refunded');
      default:
        return t('در انتظار انجام', 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = stateColor();
    final message = host.fa ? order.adminMessageFa : order.adminMessageEn;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: const Color(0xFFE6ECF3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              host.fa ? (order.serviceTitleFa ?? 'پریمیوم') : (order.serviceTitleEn ?? 'Premium'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(999)),
            child: Text(stateLabel(), style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          '${host.fa ? (order.packageTitleFa ?? order.packageId ?? '') : (order.packageTitleEn ?? order.packageId ?? '')} · #${order.publicOrderNumber ?? order.id.substring(0, 8)}',
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF748497)),
        ),
        if (message?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 7),
          Text(message!, style: const TextStyle(fontSize: 11, height: 1.4)),
        ],
        if (order.deliveryText?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFEAF8F2), borderRadius: BorderRadius.circular(10)),
            child: Text(
              '${t('اطلاعات تحویل:', 'Delivery details:')}\n${order.deliveryText}',
              style: const TextStyle(fontSize: 10.5, height: 1.45),
            ),
          ),
        ],
      ]),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
