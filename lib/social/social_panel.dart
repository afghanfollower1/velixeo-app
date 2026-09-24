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
  Timer? statusTimer;
  final Map<String, TextEditingController> fields = {};
  final coupon = TextEditingController();

  SocialPanelHost get host => widget.host;
  bool get fa => host.fa;

  @override
  void initState() {
    super.initState();
    coupon.addListener(scheduleQuote);
    load();
    statusTimer = Timer.periodic(const Duration(minutes: 1), (_) => autoSyncOrders());
  }

  @override
  void dispose() {
    quoteTimer?.cancel();
    statusTimer?.cancel();
    for (final controller in fields.values) {
      controller.dispose();
    }
    coupon.dispose();
    super.dispose();
  }

  String t(String faText, String enText) => fa ? faText : enText;

  Future<void> autoSyncOrders() async {
    if (!mounted || loading || submitting) return;
    try {
      final synced = await host.api.socialOrders();
      if (!mounted) return;
      await host.refreshAccount();
      setState(() {
        orders = synced;
        if (lastCreatedOrder != null) {
          for (final item in synced) {
            if (item.id == lastCreatedOrder!.id) {
              lastCreatedOrder = item;
              break;
            }
          }
        }
      });
    } catch (_) {
      // Keep the last known state; the next minute retries automatically.
    }
  }


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
    if (error.code == 'refill_not_ready') return t('جبران هنوز از طرف ارائه‌دهنده فعال نشده است.', 'Refill is not available from the provider yet.');
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
    final availableAt = order.refillAvailableAt;
    if (!order.canRefill && availableAt != null && availableAt.isAfter(DateTime.now())) {
      final remaining = availableAt.difference(DateTime.now());
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      final message = t(
        'جبران این سفارش هنوز فعال نشده است. حدود $hours ساعت و $minutes دقیقه دیگر دوباره تلاش کنید.',
        'Refill is not available yet. Try again in about $hours hours and $minutes minutes.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }

    if (order.canRefill) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('جبران ریزش', 'Refill')),
          content: Text(t('درخواست جبران این سفارش ارسال شود؟', 'Send a refill request for this order?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('خیر', 'No'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('ارسال', 'Send'))),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      await host.api.refillSocialOrder(order.id);
      orders = await host.api.socialOrders();
      if (mounted) {
        setState(() => tab = 2);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('درخواست جبران ثبت شد.', 'Refill request created.'))),
        );
      }
    } on ApiException catch (e) {
      try { orders = await host.api.socialOrders(); } catch (_) {}
      if (!mounted) return;
      setState(() {});
      final detail = e.details?.toString().trim();
      if (e.code == 'refill_not_ready') {
        final refreshed = orders.where((item) => item.id == order.id).cast<SocialOrder?>().firstWhere((item) => item != null, orElse: () => null);
        final at = refreshed?.refillAvailableAt;
        if (at != null && at.isAfter(DateTime.now())) {
          final remaining = at.difference(DateTime.now());
          final hours = remaining.inHours;
          final minutes = remaining.inMinutes.remainder(60);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(
              'جبران هنوز فعال نشده است. حدود $hours ساعت و $minutes دقیقه دیگر دوباره تلاش کنید.',
              'Refill is not available yet. Try again in about $hours hours and $minutes minutes.',
            ))),
          );
          return;
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(detail?.isNotEmpty == true ? detail! : apiError(e))),
      );
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
      if (!mounted) return;
      final detail = e.details?.toString().trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(detail?.isNotEmpty == true ? detail! : apiError(e)),
        ),
      );
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

  Future<void> showTerms() async {
    final terms = fa ? orderConfig.termsFa : orderConfig.termsEn;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('قوانین و مقررات سفارش', 'Order terms & conditions')),
        content: SingleChildScrollView(
          child: Text(
            terms.isEmpty
                ? t('قوانین این بخش هنوز توسط مدیر ثبت نشده است.', 'Terms have not been configured yet.')
                : terms,
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('بستن', 'Close'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) setState(() => termsAccepted = true);
            },
            child: Text(t('می‌پذیرم', 'I agree')),
          ),
        ],
      ),
    );
  }

  Widget buildOrderSuccess(SocialOrder order) {
    Future<void> copyId() async {
      await Clipboard.setData(ClipboardData(text: order.displayOrderId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('شناسه سفارش کپی شد.', 'Order ID copied.'))),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF8F2),
        border: Border.all(color: const Color(0xFFBFE8D6)),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF0A8B5B), size: 28),
            const SizedBox(width: 9),
            Expanded(child: Text(t('سفارش شما با موفقیت ثبت شد', 'Your order was placed successfully'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF086343)))),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text(t('شناسه سفارش', 'Order ID'), style: const TextStyle(color: Color(0xFF74818B))),
              const Spacer(),
              SelectableText(order.displayOrderId, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(onPressed: copyId, tooltip: t('کپی شناسه', 'Copy Order ID'), icon: const Icon(Icons.copy_rounded, size: 19, color: Color(0xFF38BDF8))),
            ]),
          ),
          const SizedBox(height: 10),
          if (order.orderLink?.isNotEmpty == true) ...[
            _InfoRow(label: t('لینک سفارش', 'Order link'), value: order.orderLink!),
            const SizedBox(height: 8),
          ],
          _InfoRow(label: t('تعداد', 'Quantity'), value: order.isDripFeed ? '${order.unitQuantity} × ${order.runs} = ${order.totalQuantity}' : '${order.quantity ?? '—'}'),
          const SizedBox(height: 8),
          _InfoRow(label: t('کسر از کیف پول', 'Wallet deduction'), value: host.money(order.totalAmountAfn, showBase: true), strong: true),
          const SizedBox(height: 8),
          _InfoRow(label: t('موجودی فعلی', 'Current balance'), value: host.money(host.balanceAfn, showBase: true), strong: true),
          if (order.providerEta?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _InfoRow(label: t('زمان تقریبی', 'Estimated completion'), value: order.providerEta!),
          ],
          const SizedBox(height: 8),
          _InfoRow(label: t('وضعیت', 'Status'), value: statusLabel(order.status)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => setState(() {
                lastCreatedOrder = null;
                termsAccepted = false;
              }),
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: Text(t('ثبت سفارش دیگر', 'Place another order')),
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return fa ? _buildPersianSocial(context) : _buildEnglishSocial(context);
  }

  Widget _socialTabBody() {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return _ErrorState(
        message: t('دریافت خدمات ممکن نشد.', 'Could not load social services.'),
        onRetry: load,
      );
    }
    if (tab == 0) return buildNewOrder();
    if (tab == 1) return buildOrders();
    if (tab == 2) return buildRefills();
    return buildDripFeed();
  }

  Widget _buildPersianSocial(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خدمات شبکه‌های اجتماعی'),
          actions: [
            IconButton(
              tooltip: 'تازه‌سازی',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _SocialTabBar(
                labels: const ['سفارش', 'سفارش‌ها', 'جبران', 'دریپ‌فید'],
                selected: tab,
                direction: TextDirection.rtl,
                onChanged: (value) => setState(() => tab = value),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(child: _socialTabBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildEnglishSocial(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Social Media Services'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: loading ? null : load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: _SocialTabBar(
                labels: const ['New order', 'Orders', 'Refill', 'Drip-feed'],
                selected: tab,
                direction: TextDirection.ltr,
                onChanged: (value) => setState(() => tab = value),
              ),
            ),
            const SizedBox(height: 5),
            Expanded(child: _socialTabBody()),
          ],
        ),
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
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
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
          if (lastCreatedOrder != null)
            buildOrderSuccess(lastCreatedOrder!)
          else
            buildOrderForm(service),
          const SizedBox(height: 24),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      children: [
        _SocialInfoHero(fa: fa),
        const SizedBox(height: 12),
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
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
        SizedBox(
          height: 80,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: displayedBrands.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final brand = displayedBrands[index];
              return SizedBox(
                width: 62,
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
              );
            },
          ),
        ),
        const SizedBox(height: 18),
        Text(t('نوع سرویس', 'Service type'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
              Expanded(child: Text(t('ثبت سفارش', 'Place order'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928)),
            ],
          ),
          const SizedBox(height: 6),
          Text(fa ? service.titleFa : service.titleEn, style: const TextStyle(color: Color(0xFF74818B))),
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
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
                style: const TextStyle(fontSize: 12, color: Color(0xFF74818B)),
              ),
            ),
          if (service.providerEta?.trim().isNotEmpty == true)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 18, color: Color(0xFF74818B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${t('زمان تقریبی تکمیل', 'Estimated completion')}: ${service.providerEta!}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
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
                if (quote != null && quote!.runs > 1) ...[
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: t('تعداد کل', 'Total quantity'),
                    value: '${quote!.quantity} × ${quote!.runs} = ${quote!.totalQuantity}',
                    strong: true,
                  ),
                ],
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: termsAccepted ? const Color(0xFFBFE8D6) : const Color(0xFFDCE8F1)),
              borderRadius: BorderRadius.circular(14),
              color: termsAccepted ? const Color(0xFFF0FBF6) : const Color(0xFFFAFCFE),
            ),
            child: CheckboxListTile(
              value: termsAccepted,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(() => termsAccepted = value == true),
              title: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(t('قوانین و مقررات را خوانده‌ام و می‌پذیرم. ', 'I have read and accept the ')),
                  InkWell(
                    onTap: showTerms,
                    child: Text(
                      t('مشاهده قوانین', 'terms & conditions'),
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: submitting || !termsAccepted ? null : submitOrder,
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
    final cards = <Widget>[];
    for (final order in orders) {
      if (order.isDripFeed) {
        for (final run in order.dripRuns) {
          cards.add(
            _DripRunOrderCard(
              order: order,
              run: run,
              host: host,
              fa: fa,
              statusLabel: statusLabel,
              onRefresh: refreshOrder,
            ),
          );
        }
      } else {
        cards.add(
          _OrderCard(
            order: order,
            host: host,
            fa: fa,
            statusLabel: statusLabel,
            onRefresh: refreshOrder,
            onRefill: requestRefill,
            onCancel: cancelOrder,
            onRefreshAction: refreshRefill,
          ),
        );
      }
    }

    if (cards.isEmpty) {
      return _EmptyState(
        icon: Icons.receipt_long_outlined,
        title: t('هنوز سفارش شبکه اجتماعی ندارید', 'No social orders yet'),
        subtitle: t('بعد از ثبت سفارش، هر اجرای Drip-feed نیز به‌صورت یک سفارش جداگانه در همین بخش نمایش داده می‌شود.', 'After ordering, every drip-feed run is also shown here as its own order row.'),
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
        itemCount: cards.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: cards[index],
        ),
      ),
    );
  }

  Widget buildRefills() {
    final rows = <({SocialOrder order, SocialOrderAction action})>[];
    for (final order in orders) {
      for (final action in order.actions) {
        if (action.action == 'REFILL') rows.add((order: order, action: action));
      }
    }
    if (rows.isEmpty) {
      return _EmptyState(
        icon: Icons.restart_alt_rounded,
        title: t('هنوز درخواست جبران ندارید', 'No refill requests yet'),
        subtitle: t('درخواست‌های جبران ریزش و وضعیت واقعی آن‌ها از ارائه‌دهنده در این بخش نمایش داده می‌شود.', 'Refill requests and their live provider status appear here.'),
      );
    }
    return RefreshIndicator(
      onRefresh: autoSyncOrders,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          final action = row.action;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDCE8F1)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(fa ? (row.order.serviceTitleFa ?? 'سرویس') : (row.order.serviceTitleEn ?? 'Service'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  _StatusBadge(label: refillStatusLabel(action.status), status: action.status),
                ]),
                const SizedBox(height: 10),
                _InfoRow(label: t('شناسه سفارش', 'Order ID'), value: row.order.displayOrderId),
                if (action.providerReference?.isNotEmpty == true) ...[
                  const SizedBox(height: 7),
                  _InfoRow(label: t('شناسه جبران', 'Refill ID'), value: action.providerReference!),
                ],
                const SizedBox(height: 7),
                _InfoRow(label: t('تاریخ درخواست', 'Requested'), value: action.createdAt.toLocal().toString().substring(0, 16)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildDripFeed() {
    final rows = orders.where((order) => order.isDripFeed).toList(growable: false);
    if (rows.isEmpty) {
      return _EmptyState(
        icon: Icons.schedule_send_rounded,
        title: t('هنوز سفارش Drip-feed ندارید', 'No drip-feed orders yet'),
        subtitle: t('سفارش‌های مرحله‌ای، تعداد هر اجرا، Runs، Interval و وضعیت زنده Provider در این بخش نمایش داده می‌شود.', 'Scheduled orders, per-run quantity, runs, interval and live provider status appear here.'),
      );
    }
    return RefreshIndicator(
      onRefresh: autoSyncOrders,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final order = rows[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFDCE8F1)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(fa ? (order.serviceTitleFa ?? 'سرویس') : (order.serviceTitleEn ?? 'Service'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  _StatusBadge(label: dripFeedStatusLabel(order.dripFeedStatus), status: order.dripFeedStatus),
                ]),
                const SizedBox(height: 10),
                _InfoRow(label: t('شناسه سفارش', 'Order ID'), value: order.displayOrderId),
                const SizedBox(height: 7),
                _InfoRow(label: t('تعداد هر اجرا', 'Per run'), value: '${order.dripFeedUnitQuantity}'),
                const SizedBox(height: 7),
                _InfoRow(label: t('اجرا شده / کل اجرا', 'Runs'), value: '${order.dripFeedRunsCurrent} / ${order.dripFeedRunsAll}'),
                const SizedBox(height: 7),
                _InfoRow(label: t('فاصله زمانی', 'Interval'), value: '${order.dripFeedInterval} ${t('دقیقه', 'min')}'),
                const SizedBox(height: 7),
                _InfoRow(label: t('تعداد کل', 'Total quantity'), value: '${order.dripFeedUnitQuantity} × ${order.dripFeedRunsAll} = ${order.dripFeedTotalQuantity}', strong: true),
                if (order.startCount != null || order.remains != null) ...[
                  const Divider(height: 22),
                  Wrap(
                    spacing: 18,
                    children: [
                      if (order.startCount != null) Text('${t('شروع', 'Start')}: ${order.startCount}'),
                      if (order.remains != null) Text('${t('باقی‌مانده', 'Remains')}: ${order.remains}'),
                    ],
                  ),
                ],
                const Divider(height: 22),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => refreshOrder(order),
                      icon: const Icon(Icons.sync_rounded, size: 17),
                      label: Text(t('بروزرسانی وضعیت', 'Refresh status')),
                    ),
                    if (order.canCancel)
                      OutlinedButton.icon(
                        onPressed: () => cancelOrder(order),
                        icon: const Icon(Icons.cancel_outlined, size: 17),
                        label: Text(t('لغو', 'Cancel')),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String dripFeedStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'active': return t('فعال', 'Active');
      case 'finished': return t('پایان یافته', 'Finished');
      case 'stopped': return t('متوقف', 'Stopped');
      default: return statusLabel(status.toUpperCase());
    }
  }

  String refillStatusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'COMPLETED': return t('موفق', 'Completed');
      case 'REJECTED': return t('رد شده', 'Rejected');
      case 'FAILED': return t('ناموفق', 'Failed');
      case 'CANCELLED': return t('لغو شده', 'Cancelled');
      case 'PROCESSING':
      case 'IN PROGRESS':
      case 'IN_PROGRESS': return t('در حال انجام', 'In progress');
      default: return t('در انتظار', 'Pending');
    }
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


class _SocialInfoHero extends StatelessWidget {
  const _SocialInfoHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        minHeight: 155,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE8F7FF), Color(0xFFF5FCFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: const Color(0xFFD5EDF8)),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              end: 2,
              bottom: -22,
              child: Transform.rotate(
                angle: -0.22,
                child: const Text(
                  '◎',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 92,
                    height: 1,
                    color: Color(0x807ACEF0),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5F5FC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      fa ? 'خدمات اجتماعی' : 'Social services',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF3F91B4),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    fa ? 'یک قدم جلوتر دیده شو' : 'Take your presence further',
                    style: const TextStyle(
                      fontSize: 18,
                      height: 1.55,
                      color: Color(0xFF2C5366),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fa
                        ? 'خدمت مناسب را پیدا کن و سفارش خود را دنبال کن.'
                        : 'Find the right service and follow your order.',
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.7,
                      color: Color(0xFF7293A5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SocialTabBar extends StatelessWidget {
  const _SocialTabBar({
    required this.labels,
    required this.selected,
    required this.direction,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final TextDirection direction;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: direction,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F5F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: List.generate(labels.length, (index) {
              final active = selected == index;
              final icons = const [
                Icons.add_shopping_cart_rounded,
                Icons.receipt_long_rounded,
                Icons.restart_alt_rounded,
                Icons.schedule_send_rounded,
              ];
              return Expanded(
                child: InkWell(
                  onTap: () => onChanged(index),
                  borderRadius: BorderRadius.circular(9),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 39,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: active
                          ? const [
                              BoxShadow(
                                color: Color(0x0F536D7B),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icons[index],
                          size: 15,
                          color: active
                              ? const Color(0xFF2E8DB5)
                              : const Color(0xFF8B9BA5),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            labels[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              color: active
                                  ? const Color(0xFF2E7898)
                                  : const Color(0xFF8799A4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      );
}

class _WalletStrip extends StatelessWidget {
  const _WalletStrip({required this.host, required this.fa});
  final SocialPanelHost host;
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F8FC),
          border: Border.all(color: const Color(0xFFE4F0F6)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            const CircleAvatar(backgroundColor: Color(0xFFEAF7FD), child: Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF369FCA))),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fa ? 'موجودی قابل استفاده' : 'Available balance', style: const TextStyle(color: Color(0xFF76909F), fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(host.money(host.balanceAfn, showBase: true), style: const TextStyle(color: Color(0xFF287FA7), fontWeight: FontWeight.w700, fontSize: 18)),
                ],
              ),
            ),
            const Icon(Icons.verified_rounded, color: Color(0xFF58A7C8)),
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
                cacheWidth: ((MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).clamp(640, 1280)).round(),
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                loadingBuilder: (context, child, progress) => progress == null ? child : const SizedBox.shrink(),
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
                              fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFFE9F7FD)
                    : const Color(0xFFF3F7FA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected
                      ? const Color(0xFF6BC7EE)
                      : const Color(0xFFE9F0F4),
                ),
                boxShadow: selected
                    ? const [
                        BoxShadow(
                          color: Color(0x1A40B8E6),
                          blurRadius: 10,
                          offset: Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: IconTheme(
                data: IconThemeData(
                  color: selected
                      ? const Color(0xFF229FD3)
                      : const Color(0xFF91A7B5),
                ),
                child: Center(child: iconWidget()),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              fa ? brand.titleFa : brand.titleEn,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? const Color(0xFF198DBD)
                    : const Color(0xFF6E8390),
              ),
            ),
          ],
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
    if (service.providerEta?.trim().isNotEmpty == true) return service.providerEta!.trim();
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
                  Expanded(child: Text(fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                  if (service.featured) const Icon(Icons.star_rounded, color: Color(0xFFFFA928), size: 19),
                  const SizedBox(width: 4),
                  Icon(selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, color: const Color(0xFF38BDF8)),
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
            Icon(icon, size: 13, color: good ? const Color(0xFF0A8B5B) : const Color(0xFF74818B)),
            const SizedBox(width: 4),
            Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: good ? const Color(0xFF0A8B5B) : const Color(0xFF74818B))),
          ],
        ),
      );
}

class _DripRunOrderCard extends StatelessWidget {
  const _DripRunOrderCard({
    required this.order,
    required this.run,
    required this.host,
    required this.fa,
    required this.statusLabel,
    required this.onRefresh,
  });

  final SocialOrder order;
  final SocialDripRun run;
  final SocialPanelHost host;
  final bool fa;
  final String Function(String) statusLabel;
  final Future<void> Function(SocialOrder) onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE8F1)),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    fa ? (order.serviceTitleFa ?? 'سرویس') : (order.serviceTitleEn ?? 'Service'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusBadge(label: statusLabel(run.status), status: run.status),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _MiniBadge(
                  text: '${fa ? 'اجرای' : 'Run'} ${run.runIndex}/${run.runsAll}',
                  icon: Icons.repeat_rounded,
                  good: run.status == 'COMPLETED',
                ),
                _MiniBadge(
                  text: '${fa ? 'تعداد' : 'Qty'}: ${run.quantity}',
                  icon: Icons.numbers_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${fa ? 'شناسه Drip-feed' : 'Drip-feed ID'}: ${order.displayOrderId}-R${run.runIndex}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF74818B)),
            ),
            const SizedBox(height: 5),
            Text(
              '${fa ? 'زمان برنامه‌ریزی' : 'Scheduled'}: ${run.scheduledAt.toLocal().toString().substring(0, 16)}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF7D92A4)),
            ),
            if (order.orderLink?.isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                '${fa ? 'لینک' : 'Link'}: ${order.orderLink}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF74818B)),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => onRefresh(order),
              icon: const Icon(Icons.sync_rounded, size: 17),
              label: Text(fa ? 'بروزرسانی' : 'Refresh'),
            ),
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

  bool get terminal => ['COMPLETED','PARTIAL','CANCELLED','FAILED','REFUNDED'].contains(order.status);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFDCE8F1)),
          borderRadius: BorderRadius.circular(21),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(fa ? (order.serviceTitleFa ?? 'سرویس') : (order.serviceTitleEn ?? 'Service'), style: const TextStyle(fontWeight: FontWeight.w700))),
                _StatusBadge(label: statusLabel(order.status), status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text(host.money(order.totalAmountAfn, showBase: true), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fa ? 'شناسه سفارش' : 'Order ID'}: ${order.displayOrderId} • ${order.createdAt.toLocal().toString().substring(0, 16)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7D92A4)),
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: order.displayOrderId));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(fa ? 'شناسه سفارش کپی شد.' : 'Order ID copied.')),
                      );
                    }
                  },
                  tooltip: fa ? 'کپی شناسه' : 'Copy Order ID',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_rounded, size: 17, color: Color(0xFF38BDF8)),
                ),
              ],
            ),
            if (order.providerStatus != null || order.startCount != null || order.remains != null) ...[
              const Divider(height: 22),
              Wrap(
                spacing: 14,
                runSpacing: 6,
                children: [
                  if (order.startCount != null) Text('${fa ? 'شروع' : 'Start'}: ${order.startCount}', style: const TextStyle(fontSize: 12)),
                  if (order.remains != null) Text('${fa ? 'باقی‌مانده' : 'Remains'}: ${order.remains}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ],
            if (order.orderLink?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('${fa ? 'لینک' : 'Link'}: ${order.orderLink}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xFF74818B))),
            ],
            if (order.providerEta?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text('${fa ? 'زمان تقریبی' : 'ETA'}: ${order.providerEta}', style: const TextStyle(fontSize: 11, color: Color(0xFF74818B))),
            ],
            if (order.failureReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(order.failureReason!, style: const TextStyle(fontSize: 11, color: Color(0xFFC54152))),
            ],
            if (order.actions.isNotEmpty) ...[
              const Divider(height: 22),
              ...order.actions.take(3).map((action) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Icon(action.action == 'REFILL' ? Icons.restart_alt_rounded : Icons.cancel_outlined, size: 16, color: const Color(0xFF74818B)),
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
                if (order.refillCheckable)
                  OutlinedButton.icon(
                    onPressed: () => onRefill(order),
                    style: order.canRefill
                        ? null
                        : OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF7D92A4),
                            side: const BorderSide(color: Color(0xFFDCE8F1)),
                            backgroundColor: const Color(0xFFF4F7FA),
                          ),
                    icon: Icon(order.canRefill ? Icons.restart_alt_rounded : Icons.schedule_rounded, size: 17),
                    label: Text(fa ? 'جبران ریزش' : 'Refill'),
                  ),
                if (order.canCancel && !terminal)
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
    final normalized = status.toUpperCase().replaceAll('_', ' ');
    late final Color color;
    late final Color bg;
    if (normalized == 'COMPLETED' || normalized == 'FINISHED') {
      color = const Color(0xFF0A8B5B);
      bg = const Color(0xFFE7F8F1);
    } else if (normalized == 'ACTIVE') {
      color = const Color(0xFF7A1FA2);
      bg = const Color(0xFFF4E8FA);
    } else if (['FAILED','CANCELLED','REJECTED','STOPPED'].contains(normalized)) {
      color = const Color(0xFFB33737);
      bg = const Color(0xFFFFF0F0);
    } else if (normalized == 'PENDING') {
      color = const Color(0xFFB86A00);
      bg = const Color(0xFFFFF3E0);
    } else if (normalized == 'PARTIAL') {
      color = const Color(0xFF7655C7);
      bg = const Color(0xFFF1ECFF);
    } else if (normalized == 'REFUNDED') {
      color = const Color(0xFF177B8D);
      bg = const Color(0xFFE6F7FA);
    } else {
      color = const Color(0xFF38BDF8);
      bg = const Color(0xFFEAF6FF);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: const TextStyle(color: Color(0xFF74818B))),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: strong
                ? Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(value, textAlign: TextAlign.end, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  )
                : Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
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
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 7),
              Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF74818B), height: 1.5)),
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
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(Directionality.of(context) == TextDirection.rtl ? 'تلاش دوباره' : 'Retry')),
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
