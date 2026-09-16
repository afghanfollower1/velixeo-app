import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_service.dart';
import 'virtual_number_models.dart';

abstract class VirtualNumberPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
  String money(int amountAfn, {bool showBase});
  Future<void> refreshAccount();
}

class VirtualNumberPanelPage extends StatefulWidget {
  const VirtualNumberPanelPage({super.key, required this.host});
  final VirtualNumberPanelHost host;

  @override
  State<VirtualNumberPanelPage> createState() => _VirtualNumberPanelPageState();
}

class _VirtualNumberPanelPageState extends State<VirtualNumberPanelPage> {
  VirtualCatalog catalog = const VirtualCatalog();
  VirtualOffers? offers;
  List<VirtualOrder> orders = const [];
  VirtualService? selectedService;
  VirtualCountry? selectedCountry;
  int tab = 0;
  bool loading = true;
  bool loadingOffers = false;
  bool buying = false;
  bool polling = false;
  String? error;
  Timer? tickTimer;
  Timer? pollTimer;

  VirtualNumberPanelHost get host => widget.host;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    load();
    tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    pollTimer = Timer.periodic(const Duration(seconds: 8), (_) => pollActiveOrders());
  }

  @override
  void dispose() {
    tickTimer?.cancel();
    pollTimer?.cancel();
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

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        host.api.virtualNumberCatalog(),
        host.api.virtualNumberOrders(),
      ]);
      catalog = results[0] as VirtualCatalog;
      orders = results[1] as List<VirtualOrder>;
      if (catalog.services.isNotEmpty) {
        final currentId = selectedService?.id;
        selectedService = catalog.services.where((item) => item.id == currentId).firstOrNull ?? catalog.services.first;
        final countries = selectedService!.countries;
        if (countries.isNotEmpty) {
          final currentCountry = selectedCountry?.code;
          selectedCountry = countries.where((item) => item.code == currentCountry).firstOrNull ?? countries.first;
        } else {
          selectedCountry = null;
        }
      } else {
        selectedService = null;
        selectedCountry = null;
      }
      await loadOffers();
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network_error';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> loadOffers() async {
    final service = selectedService;
    final country = selectedCountry;
    if (service == null || country == null) {
      if (mounted) setState(() => offers = null);
      return;
    }
    if (mounted) setState(() { loadingOffers = true; offers = null; });
    try {
      final result = await host.api.virtualNumberOffers(serviceId: service.id, country: country.code);
      if (mounted && selectedService?.id == service.id && selectedCountry?.code == country.code) {
        setState(() => offers = result);
      }
    } catch (_) {
      if (mounted) setState(() => offers = null);
    } finally {
      if (mounted) setState(() => loadingOffers = false);
    }
  }

  void changeService(VirtualService? service) {
    if (service == null) return;
    setState(() {
      selectedService = service;
      selectedCountry = service.countries.isEmpty ? null : service.countries.first;
      offers = null;
    });
    loadOffers();
  }

  void changeCountry(VirtualCountry? country) {
    if (country == null) return;
    setState(() {
      selectedCountry = country;
      offers = null;
    });
    loadOffers();
  }

  Future<void> buy({required String operatorName, required String mode}) async {
    final service = selectedService;
    final country = selectedCountry;
    if (service == null || country == null || buying) return;
    final preview = mode == 'LOW_PRICE'
        ? offers?.lowPrice
        : mode == 'ANY'
            ? offers?.anyOperator
            : operatorName == 'any'
                ? offers?.bestRate
                : offers?.operators.where((item) => item.operatorName == operatorName).firstOrNull;
    if (preview != null && preview.priceAfn > host.balanceAfn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('موجودی کیف پول کافی نیست.', 'Your wallet balance is not enough.'))),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('تأیید خرید شماره', 'Confirm number purchase')),
        content: Text(
          preview == null
              ? t('شماره از بهترین مسیر موجود انتخاب می‌شود.', 'The number will be selected from the best available route.')
              : '${t('قیمت', 'Price')}: ${host.money(preview.priceAfn, showBase: true)}\n${t('کشور', 'Country')}: ${country.code}\n${t('اپراتور', 'Operator')}: ${operatorName == 'any' ? t('هوشمند', 'Smart') : operatorName}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('لغو', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('خرید', 'Buy'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => buying = true);
    try {
      final order = await host.api.createVirtualNumberOrder(
        serviceId: service.id,
        country: country.code,
        operatorName: operatorName,
        mode: mode,
        clientRequestId: newRequestId(),
      );
      orders = [order, ...orders.where((item) => item.id != order.id)];
      await host.refreshAccount();
      if (!mounted) return;
      setState(() => tab = 2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('شماره با موفقیت خریداری شد.', 'Number purchased successfully.'))),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel('network_error'))));
    } finally {
      if (mounted) setState(() => buying = false);
    }
  }

  String errorLabel(String code) {
    switch (code) {
      case 'insufficient_funds':
        return t('موجودی کیف پول کافی نیست.', 'Insufficient wallet balance.');
      case 'number_not_available':
      case 'no_virtual_number_offers':
        return t('فعلاً برای این انتخاب شماره‌ای موجود نیست.', 'No number is currently available for this selection.');
      case 'provider_submission_uncertain':
        return t('درخواست ارسال شد اما پاسخ Provider نامشخص است؛ سفارش را تازه‌سازی کنید.', 'The provider response is uncertain. Refresh the order before retrying.');
      case 'network_error':
        return t('ارتباط با سرور برقرار نشد.', 'Could not reach the server.');
      default:
        return t('عملیات انجام نشد. دوباره تلاش کنید.', 'The operation could not be completed.');
    }
  }

  bool isActive(VirtualOrder order) =>
      !['COMPLETED', 'CANCELLED', 'REFUNDED', 'FAILED'].contains(order.status);

  Future<void> pollActiveOrders() async {
    if (polling || !mounted) return;
    final active = orders.where(isActive).take(6).toList(growable: false);
    if (active.isEmpty) return;
    polling = true;
    try {
      for (final item in active) {
        try {
          final updated = await host.api.checkVirtualNumberOrder(item.id);
          replaceOrder(updated);
        } catch (_) {}
      }
    } finally {
      polling = false;
    }
  }

  void replaceOrder(VirtualOrder updated) {
    final next = [...orders];
    final index = next.indexWhere((item) => item.id == updated.id);
    if (index >= 0) {
      next[index] = updated;
    } else {
      next.insert(0, updated);
    }
    if (mounted) setState(() => orders = next);
  }

  Future<void> checkOrder(VirtualOrder order) async {
    try {
      replaceOrder(await host.api.checkVirtualNumberOrder(order.id));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    }
  }

  Future<void> cancelOrder(VirtualOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('لغو شماره؟', 'Cancel this number?')),
        content: Text(t('اگر Provider لغو را بپذیرد و SMS دریافت نشده باشد، مبلغ به کیف پول برمی‌گردد.', 'If the provider accepts the cancellation and no SMS was received, the wallet is refunded.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('برگشت', 'Back'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('لغو شماره', 'Cancel number'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      replaceOrder(await host.api.cancelVirtualNumberOrder(order.id));
      await host.refreshAccount();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    }
  }

  Future<void> finishOrder(VirtualOrder order) async {
    try {
      replaceOrder(await host.api.finishVirtualNumberOrder(order.id));
      await host.refreshAccount();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    }
  }

  String serviceName(VirtualService service) => fa ? service.titleFa : service.titleEn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('شماره مجازی', 'Virtual Numbers')),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14),
            child: Center(
              child: Text(
                host.money(host.balanceAfn, showBase: true),
                style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D78C8)),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                children: [
                  _InfoHero(fa: fa),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, icon: const Icon(Icons.tune_rounded), label: Text(t('خرید دستی', 'Manual'))),
                      ButtonSegment(value: 1, icon: const Icon(Icons.auto_awesome_rounded), label: Text(t('خرید هوشمند', 'Smart Buy'))),
                      ButtonSegment(value: 2, icon: const Icon(Icons.sms_outlined), label: Text(t('شماره‌های من', 'My Numbers'))),
                    ],
                    selected: {tab},
                    onSelectionChanged: (value) => setState(() => tab = value.first),
                  ),
                  const SizedBox(height: 16),
                  if (error != null)
                    _Notice(text: errorLabel(error!), danger: true)
                  else if (catalog.services.isEmpty)
                    _Notice(text: t('هنوز سرویس شماره مجازی از پنل ادمین فعال نشده است.', 'No virtual-number service is enabled in Admin yet.'))
                  else if (tab == 0)
                    manualPanel()
                  else if (tab == 1)
                    smartPanel()
                  else
                    numbersPanel(),
                ],
              ),
            ),
    );
  }

  Widget selectors() {
    final service = selectedService;
    if (service == null) return const SizedBox.shrink();
    return Column(
      children: [
        DropdownButtonFormField<VirtualService>(
          value: service,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('سرویس', 'Service'), prefixIcon: const Icon(Icons.apps_rounded)),
          items: catalog.services.map((item) => DropdownMenuItem(value: item, child: Text(serviceName(item), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: changeService,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<VirtualCountry>(
          value: selectedCountry,
          isExpanded: true,
          decoration: InputDecoration(labelText: t('کشور', 'Country'), prefixIcon: const Icon(Icons.public_rounded)),
          items: service.countries
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text('${item.code.toUpperCase()} • ${host.money(item.minPriceAfn)} • ${item.availableCount} ${t('شماره', 'available')}'),
                  ))
              .toList(),
          onChanged: changeCountry,
        ),
      ],
    );
  }

  Widget manualPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(child: selectors()),
        const SizedBox(height: 14),
        if (loadingOffers)
          const Center(child: Padding(padding: EdgeInsets.all(26), child: CircularProgressIndicator()))
        else if (offers == null || offers!.operators.isEmpty)
          _Notice(text: t('برای این سرویس و کشور فعلاً شماره‌ای موجود نیست.', 'No number is currently available for this service and country.'))
        else ...[
          Row(
            children: [
              Text(t('اپراتورها / سرورها', 'Operators / servers'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const Spacer(),
              Text('${offers!.operators.length}', style: const TextStyle(color: Color(0xFF607487))),
            ],
          ),
          const SizedBox(height: 9),
          ...offers!.operators.map((offer) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: _OfferTile(
                  offer: offer,
                  fa: fa,
                  price: host.money(offer.priceAfn, showBase: true),
                  busy: buying,
                  onBuy: () => buy(operatorName: offer.operatorName, mode: 'BEST_RATE'),
                ),
              )),
        ],
      ],
    );
  }

  Widget smartPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(child: selectors()),
        const SizedBox(height: 12),
        _Notice(text: t('خرید هوشمند Provider را به شما نشان نمی‌دهد؛ سیستم براساس قیمت، درصد تحویل و اولویت مسیر بهترین شماره را انتخاب می‌کند.', 'Smart Buy keeps providers hidden and selects a route by live price, delivery rate and routing priority.')),
        const SizedBox(height: 14),
        if (loadingOffers)
          const Center(child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator()))
        else if (offers == null)
          _Notice(text: t('پیشنهاد زنده‌ای موجود نیست.', 'No live offer is available.'))
        else
          ...[
            _SmartCard(
              icon: Icons.verified_rounded,
              title: t('بهترین نرخ تحویل', 'Best delivery rate'),
              subtitle: t('اولویت با درصد موفقیت بیشتر، سپس قیمت بهتر', 'Prioritizes delivery success, then price'),
              offer: offers!.bestRate,
              fa: fa,
              price: offers!.bestRate == null ? '—' : host.money(offers!.bestRate!.priceAfn, showBase: true),
              busy: buying,
              onTap: () => buy(operatorName: 'any', mode: 'BEST_RATE'),
            ),
            const SizedBox(height: 10),
            _SmartCard(
              icon: Icons.savings_outlined,
              title: t('کمترین قیمت', 'Lowest price'),
              subtitle: t('ارزان‌ترین شماره موجود با موجودی واقعی', 'Cheapest currently available route'),
              offer: offers!.lowPrice,
              fa: fa,
              price: offers!.lowPrice == null ? '—' : host.money(offers!.lowPrice!.priceAfn, showBase: true),
              busy: buying,
              onTap: () => buy(operatorName: 'any', mode: 'LOW_PRICE'),
            ),
            const SizedBox(height: 10),
            _SmartCard(
              icon: Icons.shuffle_rounded,
              title: t('هر اپراتور', 'Any operator'),
              subtitle: t('سیستم اولین مسیر مناسب را با Failover انتخاب می‌کند', 'Uses routing priority with provider failover'),
              offer: offers!.anyOperator,
              fa: fa,
              price: offers!.anyOperator == null ? '—' : host.money(offers!.anyOperator!.priceAfn, showBase: true),
              busy: buying,
              onTap: () => buy(operatorName: 'any', mode: 'ANY'),
            ),
          ],
      ],
    );
  }

  Widget numbersPanel() {
    if (orders.isEmpty) {
      return _Notice(text: t('هنوز شماره‌ای نخریده‌اید.', 'You have not purchased a number yet.'));
    }
    return Column(
      children: orders.map((order) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _OrderCard(
          order: order,
          fa: fa,
          price: host.money(order.totalAmountAfn, showBase: true),
          onRefresh: () => checkOrder(order),
          onCancel: order.canCancel ? () => cancelOrder(order) : null,
          onFinish: order.canFinish ? () => finishOrder(order) : null,
          onBuyNew: () => setState(() => tab = 0),
        ),
      )).toList(),
    );
  }
}

class _InfoHero extends StatelessWidget {
  const _InfoHero({required this.fa});
  final bool fa;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF0B5F9F), Color(0xFF1597DC), Color(0xFF31A8FF)]),
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(17)),
              child: const Icon(Icons.sms_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fa ? 'شماره مجازی و دریافت OTP' : 'Virtual numbers & OTP', style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(fa ? 'قیمت و موجودی به‌صورت زنده بررسی می‌شود.' : 'Live price, stock and delivery rate.', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: child));
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: danger ? const Color(0xFFFFF0F0) : const Color(0xFFEAF6FF),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: danger ? const Color(0xFFFFDADA) : const Color(0xFFD4EBFA)),
        ),
        child: Text(text, style: TextStyle(color: danger ? const Color(0xFFB33737) : const Color(0xFF315B78), height: 1.45)),
      );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.fa, required this.price, required this.busy, required this.onBuy});
  final VirtualOffer offer;
  final bool fa;
  final String price;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFE4F4FF),
                child: const Icon(Icons.cell_tower_rounded, color: Color(0xFF0D78C8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.operatorName, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 7,
                      children: [
                        Text('${offer.count} ${fa ? 'موجود' : 'available'}', style: const TextStyle(fontSize: 11, color: Color(0xFF607487))),
                        if (offer.deliveryPercent != null)
                          Text('${offer.deliveryPercent!.toStringAsFixed(1)}% ${fa ? 'تحویل' : 'delivery'}', style: const TextStyle(fontSize: 11, color: Color(0xFF18A875), fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D78C8))),
                  const SizedBox(height: 5),
                  FilledButton.tonal(onPressed: busy ? null : onBuy, child: Text(fa ? 'خرید' : 'Buy')),
                ],
              ),
            ],
          ),
        ),
      );
}

class _SmartCard extends StatelessWidget {
  const _SmartCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.offer,
    required this.fa,
    required this.price,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VirtualOffer? offer;
  final bool fa;
  final String price;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: const Color(0xFFE4F4FF), child: Icon(icon, color: const Color(0xFF0D78C8))),
                  const SizedBox(width: 11),
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15))),
                  Text(price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D78C8))),
                ],
              ),
              const SizedBox(height: 8),
              Text(subtitle, style: const TextStyle(color: Color(0xFF607487), fontSize: 12)),
              if (offer != null) ...[
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text(offer!.operatorName)),
                    Chip(label: Text('${offer!.count} ${fa ? 'موجود' : 'available'}')),
                    if (offer!.deliveryPercent != null) Chip(label: Text('${offer!.deliveryPercent!.toStringAsFixed(1)}%')),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: busy || offer == null ? null : onTap, child: Text(fa ? 'خرید هوشمند' : 'Smart buy')),
              ),
            ],
          ),
        ),
      );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.fa,
    required this.price,
    required this.onRefresh,
    required this.onBuyNew,
    this.onCancel,
    this.onFinish,
  });
  final VirtualOrder order;
  final bool fa;
  final String price;
  final VoidCallback onRefresh;
  final VoidCallback onBuyNew;
  final VoidCallback? onCancel;
  final VoidCallback? onFinish;

  String get remaining {
    final expires = order.expires;
    if (expires == null) return '—';
    final diff = expires.difference(DateTime.now().toUtc());
    if (diff.isNegative) return '00:00';
    final minutes = diff.inMinutes.toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String statusLabel() {
    switch (order.status) {
      case 'AWAITING_SMS': return fa ? 'در انتظار SMS' : 'Waiting for SMS';
      case 'PROCESSING': return fa ? 'SMS دریافت شد' : 'SMS received';
      case 'COMPLETED': return fa ? 'تکمیل' : 'Completed';
      case 'CANCELLED': return fa ? 'لغو شده' : 'Cancelled';
      case 'REFUNDED': return fa ? 'برگشت وجه' : 'Refunded';
      case 'FAILED': return fa ? 'ناموفق' : 'Failed';
      default: return fa ? 'در حال آماده‌سازی' : 'Preparing';
    }
  }

  Future<void> copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final terminal = ['COMPLETED', 'CANCELLED', 'REFUNDED', 'FAILED'].contains(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(fa ? (order.serviceTitleFa ?? order.product ?? 'شماره مجازی') : (order.serviceTitleEn ?? order.product ?? 'Virtual number'), style: const TextStyle(fontWeight: FontWeight.w900))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(color: const Color(0xFFEAF6FF), borderRadius: BorderRadius.circular(999)),
                  child: Text(statusLabel(), style: const TextStyle(color: Color(0xFF0D78C8), fontSize: 11, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 13),
            if (order.phone != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF5FAFE), borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, color: Color(0xFF0D78C8)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(order.phone!, textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
                    IconButton(onPressed: () => copy(context, order.phone!, fa ? 'شماره کپی شد.' : 'Number copied.'), icon: const Icon(Icons.copy_rounded)),
                  ],
                ),
              ),
            const SizedBox(height: 9),
            Row(
              children: [
                Text('${fa ? 'کشور' : 'Country'}: ${order.country ?? '—'}', style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
                const Spacer(),
                if (!terminal) Text('⏱ $remaining', style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(width: 8),
                Text(price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D78C8))),
              ],
            ),
            if (order.sms.isEmpty && !terminal) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(borderRadius: BorderRadius.circular(99)),
              const SizedBox(height: 7),
              Text(fa ? 'در انتظار دریافت پیامک…' : 'Waiting for the SMS…', style: const TextStyle(color: Color(0xFF607487), fontSize: 12)),
            ],
            if (order.sms.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...order.sms.map((sms) => Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFE8F8F1), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFC7EFDC))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (sms.code?.isNotEmpty == true)
                          Row(
                            children: [
                              Expanded(child: Text(sms.code!, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: Color(0xFF0B8A5C)), textDirection: TextDirection.ltr)),
                              IconButton(onPressed: () => copy(context, sms.code!, fa ? 'کد کپی شد.' : 'Code copied.'), icon: const Icon(Icons.copy_rounded)),
                            ],
                          ),
                        if (sms.sender?.isNotEmpty == true) Text(sms.sender!, style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (sms.text?.isNotEmpty == true) Text(sms.text!, style: const TextStyle(fontSize: 12, height: 1.4)),
                      ],
                    ),
                  )),
            ],
            if (order.failureReason?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(order.failureReason!, style: const TextStyle(color: Color(0xFFE65454), fontSize: 11)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: Text(fa ? 'بررسی SMS' : 'Check SMS')),
                if (onFinish != null) FilledButton.tonalIcon(onPressed: onFinish, icon: const Icon(Icons.check_circle_outline), label: Text(fa ? 'پایان سفارش' : 'Finish')),
                if (onCancel != null) OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.close_rounded), label: Text(fa ? 'لغو و برگشت وجه' : 'Cancel & refund')),
                if (terminal) FilledButton.icon(onPressed: onBuyNew, icon: const Icon(Icons.add_rounded), label: Text(fa ? 'خرید شماره جدید' : 'Buy another number')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
