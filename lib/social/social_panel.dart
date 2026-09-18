import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_service.dart';
import '../core/models.dart';
import 'social_models.dart';

abstract class SocialPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
  List<AppBanner> get banners;
  String money(int amountAfn, {bool showBase});
  Future<void> refreshAccount();
}

class SocialPanelPage extends StatefulWidget {
  const SocialPanelPage({super.key, required this.host});
  final SocialPanelHost host;

  @override
  State<SocialPanelPage> createState() => _SocialPanelPageState();
}

class _SocialPanelPageState extends State<SocialPanelPage> {
  SocialCatalog catalog = const SocialCatalog();
  SocialOrderConfig orderConfig = const SocialOrderConfig();
  List<SocialOrder> orders = const [];
  bool loading = true;
  bool submitting = false;
  bool dripFeedEnabled = false;
  bool termsAccepted = false;
  bool showAllBrands = false;
  String? selectedPlatform;
  String? selectedGroup;
  SocialService? selectedService;
  SocialOrder? lastCreatedOrder;
  SocialQuote? quote;
  String? error;
  int tab = 0;
  Timer? quoteTimer;
  final Map<String, TextEditingController> fields = {};
  final coupon = TextEditingController();

  SocialPanelHost get host => widget.host;
  bool get fa => host.fa;

  @override
  void initState() {
    super.initState();
    coupon.addListener(scheduleQuote);
    load();
  }

  @override
  void dispose() {
    quoteTimer?.cancel();
    for (final controller in fields.values) {
      controller.dispose();
    }
    coupon.dispose();
    super.dispose();
  }

  String t(String faText, String enText) => fa ? faText : enText;

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        host.api.socialCatalog(),
        host.api.socialOrders(),
        host.api.socialOrderConfig(),
      ]);
      catalog = results[0] as SocialCatalog;
      orders = results[1] as List<SocialOrder>;
      orderConfig = results[2] as SocialOrderConfig;
      final brands = availableBrands;
      final brandKeys = brands.map((brand) => brand.key).toList(growable: false);
      selectedPlatform ??= brandKeys.isEmpty ? null : brandKeys.first;
      if (selectedPlatform != null && !brandKeys.contains(selectedPlatform)) {
        selectedPlatform = brandKeys.isEmpty ? null : brandKeys.first;
      }
      final groups = availableGroups;
      if (selectedGroup != null && !groups.contains(selectedGroup)) selectedGroup = null;
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network_error';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  List<SocialBrand> get availableBrands {
    if (catalog.brands.isNotEmpty) {
      final rows = [...catalog.brands];
      rows.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return rows;
    }
    final keys = catalog.services.map((e) => e.platform).toSet().toList()..sort();
    return keys
        .map((key) => SocialBrand(
              key: key,
              titleFa: key,
              titleEn: key,
              iconType: 'DEFAULT',
              iconValue: key.toLowerCase(),
              sortOrder: 100,
            ))
        .toList(growable: false);
  }

  List<String> get availableGroups {
    final values = catalog.services
        .where((e) => selectedPlatform == null || e.platform == selectedPlatform)
        .map((e) => e.group)
        .toSet()
        .toList();
    final serverOrder = <String, int>{
      for (final category in catalog.categories)
        if (selectedPlatform == null || category.platform == selectedPlatform)
          category.slug: category.sortOrder,
    };
    const preferred = ['FOLLOWERS','LIKES','VIEWS','COMMENTS','SHARES','SAVES','REACH','POLL','TRAFFIC','OTHER'];
    values.sort((a, b) {
      final sa = serverOrder[a];
      final sb = serverOrder[b];
      if (sa != null || sb != null) {
        return (sa ?? 999999).compareTo(sb ?? 999999);
      }
      final ia = preferred.indexOf(a);
      final ib = preferred.indexOf(b);
      return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
    });
    return values;
  }

  List<SocialService> get visibleServices => catalog.services.where((service) {
        if (selectedPlatform != null && service.platform != selectedPlatform) return false;
        if (selectedGroup != null && service.group != selectedGroup) return false;
        return true;
      }).toList(growable: false);

  AppBanner? get socialBanner {
    final rows = host.banners
        .where((banner) => banner.placement == 'SERVICES_TOP')
        .toList(growable: false)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return rows.isEmpty ? null : rows.first;
  }

  List<SocialBrand> get displayedBrands {
    final rows = availableBrands;
    if (showAllBrands || rows.length <= 6) return rows;
    return rows.take(6).toList(growable: false);
  }

  void selectService(SocialService service) {
    quoteTimer?.cancel();
    for (final controller in fields.values) {
      controller.dispose();
    }
    fields.clear();
    for (final field in service.orderFields) {
      final initial = field.key == 'quantity' && service.minQty != null
          ? '${service.minQty}'
          : field.key == 'delay' && field.options.isNotEmpty
              ? field.options.first.value
              : '';
      final controller = TextEditingController(text: initial);
      controller.addListener(scheduleQuote);
      fields[field.key] = controller;
    }
    setState(() {
      selectedService = service;
      dripFeedEnabled = false;
      termsAccepted = false;
      lastCreatedOrder = null;
      quote = null;
    });
    scheduleQuote();
  }

  Map<String, dynamic> currentParameters() => {
        for (final entry in fields.entries)
          if (entry.value.text.trim().isNotEmpty &&
              (dripFeedEnabled || (entry.key != 'runs' && entry.key != 'interval')))
            entry.key: entry.value.text.trim(),
      };

  void changeService() {
    quoteTimer?.cancel();
    for (final controller in fields.values) {
      controller.dispose();
    }
    fields.clear();
    setState(() {
      selectedService = null;
      dripFeedEnabled = false;
      termsAccepted = false;
      lastCreatedOrder = null;
      quote = null;
    });
  }

  void scheduleQuote() {
    quoteTimer?.cancel();
    quoteTimer = Timer(const Duration(milliseconds: 450), () async {
      final service = selectedService;
      if (service == null || !mounted) return;
      try {
        final result = await host.api.socialQuote(
          serviceId: service.id,
          parameters: currentParameters(),
          couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),
        );
        if (mounted && selectedService?.id == service.id) setState(() => quote = result);
      } catch (_) {
        if (mounted && selectedService?.id == service.id) setState(() => quote = null);
      }
    });
  }

  Future<void> submitOrder() async {
    final service = selectedService;
    if (service == null || submitting) return;
    if (!termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('ابتدا قوانین و مقررات را مطالعه و تأیید کنید.', 'Please read and accept the terms before placing the order.'))),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => submitting = true);
    try {
      final latestQuote = await host.api.socialQuote(
        serviceId: service.id,
        parameters: currentParameters(),
        couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),
      );
      if (latestQuote.totalAmountAfn > host.balanceAfn) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('موجودی کیف پول کافی نیست.', 'Your wallet balance is not enough.'))),
        );
        return;
      }
      final result = await host.api.createSocialOrder(
        serviceId: service.id,
        clientRequestId: _uuidV4(),
        parameters: currentParameters(),
        termsAccepted: true,
        couponCode: coupon.text.trim().isEmpty ? null : coupon.text.trim(),
      );
      await host.refreshAccount();
      orders = await host.api.socialOrders();
      if (!mounted) return;
      setState(() {
        quote = latestQuote;
        lastCreatedOrder = result.order;
      });
      final warning = result.warning == 'provider_submission_uncertain'
          ? t('سفارش ثبت شد و وضعیت Provider در حال بررسی است.', 'Order saved; provider submission is being reviewed.')
          : t('سفارش با موفقیت ثبت شد.', 'Order placed successfully.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning)));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  String apiError(ApiException error) {
    if (error.code == 'insufficient_funds') return t('موجودی کافی نیست.', 'Insufficient wallet balance.');
    if (error.code == 'quantity_out_of_range') return t('تعداد خارج از محدوده این سرویس است.', 'Quantity is outside the service limits.');
    if (error.code.startsWith('FIELD_REQUIRED:')) {
      return t('لطفاً تمام فیلدهای ضروری را تکمیل کنید.', 'Please complete all required fields.');
    }
    if (error.code == 'service_unavailable') return t('این سرویس فعلاً در دسترس نیست.', 'This service is currently unavailable.');
    if (error.code == 'provider_rejected') return t('Provider سفارش را نپذیرفت و مبلغ برگشت داده شد.', 'Provider rejected the order and the amount was refunded.');
    if (error.code == 'refill_not_supported') return t('این سفارش جبران ریزش ندارد.', 'Refill is not available for this order.');
    if (error.code == 'refill_not_available') return t('جبران فقط بعد از تکمیل سفارش در دسترس است.', 'Refill becomes available only after completion.');
    if (error.code == 'refill_window_expired') return t('مهلت جبران این سفارش تمام شده است.', 'The refill window has expired.');
    if (error.code == 'order_not_cancellable') return t('این سفارش دیگر قابل لغو نیست.', 'This order can no longer be cancelled.');
    if (error.code == 'cancel_not_supported') return t('لغو این سفارش از سمت Provider پشتیبانی نمی‌شود.', 'Provider does not support cancelling this order.');
    if (error.code == 'coupon_invalid') return t('کد تخفیف معتبر نیست.', 'Coupon code is invalid.');
    if (error.code == 'coupon_expired') return t('اعتبار این کد تخفیف تمام شده است.', 'This coupon has expired.');
    if (error.code == 'coupon_not_started') return t('زمان استفاده از این کد هنوز شروع نشده است.', 'This coupon is not active yet.');
    if (error.code == 'coupon_usage_limit') return t('سقف استفاده از این کد تکمیل شده است.', 'This coupon has reached its usage limit.');
    if (error.code == 'coupon_min_order') return t('مبلغ سفارش برای این کد کافی نیست.', 'This order does not meet the coupon minimum.');
    return t('عملیات انجام نشد. دوباره تلاش کنید.', 'The operation failed. Please try again.');
  }

  Future<void> refreshOrder(SocialOrder order) async {
    try {
      await host.api.refreshSocialOrder(order.id);
      orders = await host.api.socialOrders();
      await host.refreshAccount();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  Future<void> requestRefill(SocialOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('درخواست جبران ریزش', 'Request refill')),
        content: Text(t('درخواست جبران برای این سفارش به Provider ارسال شود؟', 'Send a refill request for this order to the provider?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('نه', 'No'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('ارسال', 'Send'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await host.api.refillSocialOrder(order.id);
      orders = await host.api.socialOrders();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('درخواست جبران ثبت شد.', 'Refill request created.'))));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  Future<void> cancelOrder(SocialOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('لغو سفارش', 'Cancel order')),
        content: Text(t('درخواست لغو به Provider ارسال شود؟ پس از تأیید Provider، مبلغ بخش انجام‌نشده به کیف پول برمی‌گردد.', 'Send a cancellation request? Any unfulfilled amount is refunded after provider confirmation.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('نه', 'No'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('لغو سفارش', 'Cancel order'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await host.api.cancelSocialOrder(order.id);
      await refreshOrder(order);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  Future<void> refreshRefill(SocialOrder order, SocialOrderAction action) async {
    try {
      await host.api.refreshSocialAction(order.id, action.id);
      orders = await host.api.socialOrders();
      if (mounted) setState(() {});
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(apiError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('خدمات شبکه‌های اجتماعی', 'Social Media Services')),
        actions: [
          IconButton(onPressed: loading ? null : load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(child: _TabButton(label: t('سفارش جدید', 'New order'), icon: Icons.add_shopping_cart_rounded, selected: tab == 0, onTap: () => setState(() => tab = 0))),
                  Expanded(child: _TabButton(label: t('سفارش‌های من', 'My orders'), icon: Icons.receipt_long_rounded, selected: tab == 1, onTap: () => setState(() => tab = 1))),
                ],
              ),
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? _ErrorState(message: t('دریافت خدمات ممکن نشد.', 'Could not load social services.'), onRetry: load)
                    : tab == 0
                        ? buildNewOrder()
                        : buildOrders(),
          ),
        ],
      ),
    );
  }

  Widget buildNewOrder() {
    if (catalog.services.isEmpty) {
      return _EmptyState(
        icon: Icons.hub_outlined,
        title: t('هنوز سرویس فعالی وجود ندارد', 'No active services yet'),
        subtitle: t('سرویس‌ها بعد از Sync و فعال‌سازی از پنل مدیریت اینجا نمایش داده می‌شوند.', 'Services appear here after they are synced and enabled in Admin.'),
      );
    }

    final service = selectedService;
    if (service != null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _WalletStrip(host: host, fa: fa),
          const SizedBox(height: 14),
          Align(
            alignment: fa ? Alignment.centerRight : Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: changeService,
              icon: Icon(fa ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded, size: 18),
              label: Text(t('تغییر سرویس', 'Change service')),
            ),
          ),
          const SizedBox(height: 10),
          buildOrderForm(service),
          const SizedBox(height: 24),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WalletStrip(host: host, fa: fa),
        if (socialBanner != null) ...[
          const SizedBox(height: 14),
          _SocialPromoBanner(banner: socialBanner!, fa: fa),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                t('شبکه‌های اجتماعی', 'Social platforms'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
            if (availableBrands.length > 6)
              TextButton.icon(
                onPressed: () => setState(() => showAllBrands = !showAllBrands),
                icon: Icon(showAllBrands ? Icons.expand_less_rounded : Icons.grid_view_rounded, size: 18),
                label: Text(t(showAllBrands ? 'نمایش کمتر' : 'سرویس‌های بیشتر', showAllBrands ? 'Show less' : 'More services')),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 9.0;
            const columns = 3;
            final width = (constraints.maxWidth - (gap * (columns - 1))) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: displayedBrands.map((brand) => SizedBox(
                width: width,
                child: _BrandCard(
                  brand: brand,
                  fa: fa,
                  selected: brand.key == selectedPlatform,
                  onTap: () => setState(() {
                    selectedPlatform = brand.key;
                    selectedGroup = null;
                    selectedService = null;
                    quote = null;
                  }),
                ),
              )).toList(growable: false),
            );
          },
        ),
        const SizedBox(height: 18),
        Text(t('نوع سرویس', 'Service type'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(t('همه', 'All')),
              selected: selectedGroup == null,
              onSelected: (_) => setState(() { selectedGroup = null; selectedService = null; quote = null; }),
            ),
            ...availableGroups.map((group) => ChoiceChip(
                  label: Text(groupLabel(group)),
                  selected: group == selectedGroup,
                  onSelected: (_) => setState(() { selectedGroup = group; selectedService = null; quote = null; }),
                )),
          ],
        ),
        const SizedBox(height: 18),
        ...visibleServices.map((service) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ServiceCard(
                service: service,
                host: host,
                fa: fa,
                selected: selectedService?.id == service.id,
                onTap: () => selectService(service),
              ),
            )),
      ],
    );
  }

  Widget buildOrderForm(SocialService service) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDCE8F1)),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x0A102235), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(t('ثبت سفارش', 'Place order'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928)),
            ],
          ),
          const SizedBox(height: 6),
          Text(fa ? service.titleFa : service.titleEn, style: const TextStyle(color: Color(0xFF607487))),
          const SizedBox(height: 16),
          ...service.orderFields
              .where((field) => field.key != 'runs' && field.key != 'interval')
              .map((field) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: buildField(field),
                  )),
          if (service.orderFields.any((field) => field.key == 'runs' || field.key == 'interval')) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                border: Border.all(color: const Color(0xFFDCE8F1)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CheckboxListTile(
                value: dripFeedEnabled,
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  t('دریپ‌فید (ارسال مرحله‌ای)', 'Drip-feed'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  t('فقط در صورت نیاز فعال کنید.', 'Enable only if you want scheduled delivery.'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF718399)),
                ),
                onChanged: (value) {
                  final enabled = value == true;
                  if (!enabled) {
                    fields['runs']?.clear();
                    fields['interval']?.clear();
                  }
                  setState(() {
                    dripFeedEnabled = enabled;
                    quote = null;
                  });
                  scheduleQuote();
                },
              ),
            ),
            if (dripFeedEnabled)
              ...service.orderFields
                  .where((field) => field.key == 'runs' || field.key == 'interval')
                  .map((field) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: buildField(field),
                      )),
          ],
          if (service.minQty != null || service.maxQty != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                t('محدوده سفارش: ${service.minQty ?? '—'} تا ${service.maxQty ?? '—'}', 'Order range: ${service.minQty ?? '—'} to ${service.maxQty ?? '—'}'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
              ),
            ),
          TextField(
            controller: coupon,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: t('کد تخفیف', 'Coupon code'),
              hintText: t('اختیاری', 'Optional'),
              prefixIcon: const Icon(Icons.local_offer_outlined),
              suffixIcon: coupon.text.trim().isEmpty
                  ? null
                  : IconButton(onPressed: coupon.clear, icon: const Icon(Icons.close_rounded)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF4FAFF), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _InfoRow(label: t('نرخ', 'Rate'), value: '${host.money(service.priceRateAfn, showBase: true)} / ${service.priceUnit}'),
                if (quote != null && quote!.discountAmountAfn > 0) ...[
                  const SizedBox(height: 8),
                  _InfoRow(label: t('جمع قبل از تخفیف', 'Subtotal'), value: host.money(quote!.subtotalAmountAfn, showBase: true)),
                  const SizedBox(height: 8),
                  _InfoRow(label: t('تخفیف', 'Discount'), value: '- ${host.money(quote!.discountAmountAfn, showBase: true)}'),
                ],
                const SizedBox(height: 8),
                _InfoRow(
                  label: t('قیمت نهایی', 'Total'),
                  value: quote == null ? t('پس از تکمیل فرم', 'Complete the form') : host.money(quote!.totalAmountAfn, showBase: true),
                  strong: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: submitting ? null : submitOrder,
              icon: submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_outline_rounded),
              label: Text(submitting ? t('در حال ثبت...', 'Placing order...') : t('پرداخت از کیف پول و ثبت سفارش', 'Pay from wallet & place order')),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('مبلغ سفارش در سرور دوباره محاسبه می‌شود و Provider مستقیماً از داخل اپ قابل مشاهده نیست.', 'The server recalculates the price before purchase; provider details are never exposed in the app.'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF7D92A4), height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget buildField(SocialOrderField field) {
    final label = fa ? field.labelFa : field.labelEn;
    final hint = fa ? field.hintFa : field.hintEn;
    final controller = fields[field.key]!;
    if (field.type == 'select') {
      return DropdownButtonFormField<String>(
        value: controller.text.isEmpty ? null : controller.text,
        decoration: InputDecoration(labelText: field.required ? '$label *' : label, hintText: hint),
        items: field.options
            .map((option) => DropdownMenuItem(value: option.value, child: Text(fa ? option.labelFa : option.labelEn)))
            .toList(growable: false),
        onChanged: (value) {
          controller.text = value ?? '';
          scheduleQuote();
        },
      );
    }
    if (field.type == 'date') {
      return TextField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: field.required ? '$label *' : label,
          hintText: hint,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            initialDate: DateTime.now().add(const Duration(days: 30)),
          );
          if (date != null) {
            controller.text = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
            scheduleQuote();
          }
        },
      );
    }
    return TextField(
      controller: controller,
      keyboardType: field.type == 'number' ? TextInputType.number : TextInputType.text,
      maxLines: field.type == 'multiline' ? 5 : 1,
      decoration: InputDecoration(
        labelText: field.required ? '$label *' : label,
        hintText: hint,
        alignLabelWithHint: field.type == 'multiline',
      ),
    );
  }

  Widget buildOrders() {
    if (orders.isEmpty) {
      return _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: t('هنوز سفارش شبکه اجتماعی ندارید', 'No social orders yet'),
        subtitle: t('بعد از ثبت سفارش، وضعیت، مقدار باقی‌مانده، جبران و لغو از همین بخش مدیریت می‌شود.', 'After ordering, status, remains, refill and cancellation are managed here.'),
      );
    }
    return RefreshIndicator(
      onRefresh: () async {
        orders = await host.api.socialOrders();
        if (mounted) setState(() {});
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _OrderCard(
            order: orders[index],
            host: host,
            fa: fa,
            statusLabel: statusLabel,
            onRefresh: refreshOrder,
            onRefill: requestRefill,
            onCancel: cancelOrder,
            onRefreshAction: refreshRefill,
          ),
        ),
      ),
    );
  }

  String statusLabel(String status) {
    switch (status) {
      case 'PROCESSING': return t('در حال انجام', 'In progress');
      case 'COMPLETED': return t('تکمیل', 'Completed');
      case 'PARTIAL': return t('نیمه‌کامل', 'Partial');
      case 'CANCELLED': return t('لغو شده', 'Cancelled');
      case 'FAILED': return t('ناموفق', 'Failed');
      case 'REFUNDED': return t('برگشت وجه', 'Refunded');
      default: return t('در انتظار', 'Pending');
    }
  }

  String groupLabel(String group) {
    for (final category in catalog.categories) {
      if (category.slug == group) {
        return fa ? category.titleFa : category.titleEn;
      }
    }
    const faLabels = {
      'FOLLOWERS': 'فالوور / عضو', 'LIKES': 'لایک', 'VIEWS': 'بازدید',
      'COMMENTS': 'کامنت', 'SHARES': 'اشتراک‌گذاری', 'SAVES': 'ذخیره',
      'REACH': 'ریچ / ایمپرشن', 'POLL': 'نظرسنجی', 'TRAFFIC': 'ترافیک', 'OTHER': 'سایر',
    };
    const enLabels = {
      'FOLLOWERS': 'Followers / Members', 'LIKES': 'Likes', 'VIEWS': 'Views',
      'COMMENTS': 'Comments', 'SHARES': 'Shares', 'SAVES': 'Saves',
      'REACH': 'Reach / Impressions', 'POLL': 'Poll', 'TRAFFIC': 'Traffic', 'OTHER': 'Other',
    };
    return fa ? (faLabels[group] ?? group) : (enLabels[group] ?? group);
  }
}

class _WalletStrip extends StatelessWidget {
  const _WalletStrip({required this.host, required this.fa});
  final SocialPanelHost host;
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF31A8FF), Color(0xFF0D78C8)]),
          borderRadius: BorderRadius.circular(19),
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: Color(0x33FFFFFF), child: Icon(Icons.account_balance_wallet_rounded, color: Colors.white)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fa ? 'موجودی قابل استفاده' : 'Available balance', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(host.money(host.balanceAfn, showBase: true), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
            ),
            const Icon(Icons.verified_rounded, color: Colors.white),
          ],
        ),
      );
}

class _SocialPromoBanner extends StatelessWidget {
  const _SocialPromoBanner({required this.banner, required this.fa});

  final AppBanner banner;
  final bool fa;

  @override
  Widget build(BuildContext context) {
    final title = (fa ? banner.titleFa : banner.titleEn)?.trim() ?? '';
    final subtitle = (fa ? banner.subtitleFa : banner.subtitleEn)?.trim() ?? '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 1080 / 420,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (banner.imageUrl.trim().isNotEmpty)
              Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0E6DD8), Color(0xFF35B5FF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0E6DD8), Color(0xFF35B5FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            if (title.isNotEmpty || subtitle.isNotEmpty)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: fa ? Alignment.centerRight : Alignment.centerLeft,
                    end: fa ? Alignment.centerLeft : Alignment.centerRight,
                    colors: const [Color(0xA6000000), Color(0x18000000), Color(0x00000000)],
                  ),
                ),
              ),
            if (title.isNotEmpty || subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                child: Align(
                  alignment: fa ? Alignment.centerRight : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: .72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: fa ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (title.isNotEmpty)
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: fa ? TextAlign.right : TextAlign.left,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        if (title.isNotEmpty && subtitle.isNotEmpty) const SizedBox(height: 5),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: fa ? TextAlign.right : TextAlign.left,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.35),
                          ),
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

class _BrandCard extends StatelessWidget {
  const _BrandCard({
    required this.brand,
    required this.fa,
    required this.selected,
    required this.onTap,
  });

  final SocialBrand brand;
  final bool fa;
  final bool selected;
  final VoidCallback onTap;

  IconData get fallbackIcon {
    switch (brand.iconValue.toLowerCase()) {
      case 'instagram': return Icons.camera_alt_rounded;
      case 'threads': return Icons.alternate_email_rounded;
      case 'youtube': return Icons.play_circle_fill_rounded;
      case 'telegram': return Icons.send_rounded;
      case 'whatsapp': return Icons.chat_rounded;
      case 'facebook': return Icons.facebook_rounded;
      case 'tiktok': return Icons.music_note_rounded;
      case 'x': return Icons.alternate_email_rounded;
      case 'linkedin': return Icons.business_center_rounded;
      case 'snapchat': return Icons.camera_alt_rounded;
      case 'spotify': return Icons.headphones_rounded;
      case 'discord': return Icons.forum_rounded;
      case 'pinterest': return Icons.push_pin_rounded;
      default: return Icons.photo_camera_rounded;
    }
  }

  Widget iconWidget() {
    final type = brand.iconType.toUpperCase();
    final value = brand.iconValue.trim();
    if (type == 'UPLOAD' && value.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(value.split(',').last);
        return Image.memory(
          bytes,
          width: 30,
          height: 30,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: 28),
        );
      } catch (_) {}
    }
    if (type == 'URL' && (value.startsWith('https://') || value.startsWith('http://'))) {
      return Image.network(
        value,
        width: 30,
        height: 30,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(fallbackIcon, size: 28),
      );
    }
    return Icon(fallbackIcon, size: 28);
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0D78C8) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? const Color(0xFF0D78C8) : const Color(0xFFDCE8F1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTheme(
                data: IconThemeData(color: selected ? Colors.white : const Color(0xFF0D78C8)),
                child: iconWidget(),
              ),
              const SizedBox(height: 7),
              Text(
                fa ? brand.titleFa : brand.titleEn,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : const Color(0xFF102235)),
              ),
            ],
          ),
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.host, required this.fa, required this.selected, required this.onTap});
  final SocialService service;
  final SocialPanelHost host;
  final bool fa;
  final bool selected;
  final VoidCallback onTap;

  String eta() {
    final min = service.estimatedMinMinutes;
    final max = service.estimatedMaxMinutes;
    if (min == null && max == null) return fa ? 'زمان تقریبی ثبت نشده' : 'ETA not set';
    String fmt(int value) {
      if (value >= 1440) return fa ? '${(value / 1440).ceil()} روز' : '${(value / 1440).ceil()}d';
      if (value >= 60) return fa ? '${(value / 60).ceil()} ساعت' : '${(value / 60).ceil()}h';
      return fa ? '$value دقیقه' : '${value}m';
    }
    if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
    return fmt(min ?? max!);
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF1F9FF) : Colors.white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: selected ? const Color(0xFF31A8FF) : const Color(0xFFDCE8F1), width: selected ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14))),
                  if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928), size: 19),
                  const SizedBox(width: 4),
                  Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: const Color(0xFF0D78C8)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniBadge(text: '${host.money(service.priceRateAfn, showBase: true)} / ${service.priceUnit}', icon: Icons.payments_outlined),
                  _MiniBadge(text: eta(), icon: Icons.schedule_rounded),
                  if (service.refillSupported)
                    _MiniBadge(text: service.refillDays == null ? (fa ? 'جبران ریزش' : 'Refill') : (fa ? 'جبران ${service.refillDays} روزه' : '${service.refillDays}d refill'), icon: Icons.restart_alt_rounded, good: true),
                  if (service.cancelSupported) _MiniBadge(text: fa ? 'قابل لغو' : 'Cancelable', icon: Icons.cancel_outlined, good: true),
                ],
              ),
            ],
          ),
        ),
      );
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.text, required this.icon, this.good = false});
  final String text;
  final IconData icon;
  final bool good;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: good ? const Color(0xFFE7F8F1) : const Color(0xFFF1F5F8),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: good ? const Color(0xFF0A8B5B) : const Color(0xFF607487)),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: good ? const Color(0xFF0A8B5B) : const Color(0xFF607487))),
          ],
        ),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.host,
    required this.fa,
    required this.statusLabel,
    required this.onRefresh,
    required this.onRefill,
    required this.onCancel,
    required this.onRefreshAction,
  });

  final SocialOrder order;
  final SocialPanelHost host;
  final bool fa;
  final String Function(String) statusLabel;
  final Future<void> Function(SocialOrder) onRefresh;
  final Future<void> Function(SocialOrder) onRefill;
  final Future<void> Function(SocialOrder) onCancel;
  final Future<void> Function(SocialOrder, SocialOrderAction) onRefreshAction;

  bool get terminal => ['COMPLETED','CANCELLED','FAILED','REFUNDED'].contains(order.status);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE8F1)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(fa ? (order.serviceTitleFa ?? 'سرویس') : (order.serviceTitleEn ?? 'Service'), style: const TextStyle(fontWeight: FontWeight.w900))),
                _StatusBadge(label: statusLabel(order.status), status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(host.money(order.totalAmountAfn, showBase: true), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('#${order.id.substring(0, 8)} • ${order.createdAt.toLocal().toString().substring(0, 16)}', style: const TextStyle(fontSize: 11, color: Color(0xFF7D92A4))),
            if (order.providerStatus != null || order.startCount != null || order.remains != null) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (order.providerStatus != null) Text('${fa ? 'Provider' : 'Provider'}: ${order.providerStatus}', style: const TextStyle(fontSize: 12)),
                  if (order.startCount != null) Text('${fa ? 'شروع' : 'Start'}: ${order.startCount}', style: const TextStyle(fontSize: 12)),
                  if (order.remains != null) Text('${fa ? 'باقی‌مانده' : 'Remains'}: ${order.remains}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
            if (order.failureReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(order.failureReason!, style: const TextStyle(fontSize: 11, color: Color(0xFFE65454))),
            ],
            if (order.actions.isNotEmpty) ...[
              const Divider(height: 22),
              ...order.actions.take(3).map((action) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(action.action == 'REFILL' ? Icons.restart_alt_rounded : Icons.cancel_outlined, size: 16, color: const Color(0xFF607487)),
                        const SizedBox(width: 6),
                        Expanded(child: Text('${action.action} • ${action.status}', style: const TextStyle(fontSize: 11))),
                        if (action.action == 'REFILL' && !['COMPLETED','REJECTED'].contains(action.status.toUpperCase()))
                          IconButton(onPressed: () => onRefreshAction(order, action), icon: const Icon(Icons.refresh_rounded, size: 18), visualDensity: VisualDensity.compact),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: () => onRefresh(order), icon: const Icon(Icons.sync_rounded, size: 17), label: Text(fa ? 'بروزرسانی وضعیت' : 'Refresh status')),
                if (order.refillSupported && ['COMPLETED','PARTIAL'].contains(order.status))
                  OutlinedButton.icon(onPressed: () => onRefill(order), icon: const Icon(Icons.restart_alt_rounded, size: 17), label: Text(fa ? 'جبران ریزش' : 'Refill')),
                if (order.cancelSupported && !terminal)
                  OutlinedButton.icon(onPressed: () => onCancel(order), icon: const Icon(Icons.cancel_outlined, size: 17), label: Text(fa ? 'لغو' : 'Cancel')),
              ],
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.status});
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    final good = status == 'COMPLETED';
    final bad = ['FAILED','CANCELLED'].contains(status);
    final color = good ? const Color(0xFF0A8B5B) : bad ? const Color(0xFFB33737) : const Color(0xFF0D78C8);
    final bg = good ? const Color(0xFFE7F8F1) : bad ? const Color(0xFFFFF0F0) : const Color(0xFFEAF6FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w800)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF607487))),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w700))),
        ],
      );
}

class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.icon, required this.selected, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected ? const [BoxShadow(color: Color(0x10102235), blurRadius: 12)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [Icon(icon, size: 18, color: selected ? const Color(0xFF0D78C8) : const Color(0xFF607487)), const SizedBox(width: 6), Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? const Color(0xFF102235) : const Color(0xFF607487)))],
          ),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 72, color: const Color(0xFF9BB1C4)),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 7),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF607487), height: 1.5)),
            ],
          ),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: Color(0xFF9BB1C4)),
            const SizedBox(height: 14),
            Text(message),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      );
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final raw = bytes.map(hex).join();
  return '${raw.substring(0, 8)}-${raw.substring(8, 12)}-${raw.substring(12, 16)}-${raw.substring(16, 20)}-${raw.substring(20)}';
}
