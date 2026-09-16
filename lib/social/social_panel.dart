import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import 'social_models.dart';

abstract class SocialPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
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
  List<SocialOrder> orders = const [];
  bool loading = true;
  bool submitting = false;
  String? selectedPlatform;
  String? selectedGroup;
  SocialService? selectedService;
  SocialQuote? quote;
  String? error;
  int tab = 0;
  Timer? quoteTimer;
  final Map<String, TextEditingController> fields = {};

  SocialPanelHost get host => widget.host;
  bool get fa => host.fa;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    quoteTimer?.cancel();
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String t(String faText, String enText) => fa ? faText : enText;

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final results = await Future.wait([
        host.api.socialCatalog(),
        host.api.socialOrders(),
      ]);
      catalog = results[0] as SocialCatalog;
      orders = results[1] as List<SocialOrder>;
      final platforms = availablePlatforms;
      selectedPlatform ??= platforms.isEmpty ? null : platforms.first;
      if (selectedPlatform != null && !platforms.contains(selectedPlatform)) {
        selectedPlatform = platforms.isEmpty ? null : platforms.first;
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

  List<String> get availablePlatforms {
    final values = catalog.services.map((e) => e.platform).toSet().toList();
    const preferred = [
      'INSTAGRAM','TIKTOK','YOUTUBE','FACEBOOK','TELEGRAM','X','THREADS',
      'SNAPCHAT','LINKEDIN','PINTEREST','SPOTIFY','SOUNDCLOUD','DISCORD','OTHER',
    ];
    values.sort((a, b) {
      final ia = preferred.indexOf(a);
      final ib = preferred.indexOf(b);
      return (ia < 0 ? 999 : ia).compareTo(ib < 0 ? 999 : ib);
    });
    return values;
  }

  List<String> get availableGroups {
    final values = catalog.services
        .where((e) => selectedPlatform == null || e.platform == selectedPlatform)
        .map((e) => e.group)
        .toSet()
        .toList();
    const preferred = ['FOLLOWERS','LIKES','VIEWS','COMMENTS','SHARES','SAVES','REACH','POLL','TRAFFIC','OTHER'];
    values.sort((a, b) {
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
      quote = null;
    });
    scheduleQuote();
  }

  Map<String, dynamic> currentParameters() => {
        for (final entry in fields.entries)
          if (entry.value.text.trim().isNotEmpty) entry.key: entry.value.text.trim(),
      };

  void scheduleQuote() {
    quoteTimer?.cancel();
    quoteTimer = Timer(const Duration(milliseconds: 450), () async {
      final service = selectedService;
      if (service == null || !mounted) return;
      try {
        final result = await host.api.socialQuote(
          serviceId: service.id,
          parameters: currentParameters(),
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
    FocusScope.of(context).unfocus();
    setState(() => submitting = true);
    try {
      final latestQuote = await host.api.socialQuote(
        serviceId: service.id,
        parameters: currentParameters(),
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
      );
      await host.refreshAccount();
      orders = await host.api.socialOrders();
      if (!mounted) return;
      setState(() {
        quote = latestQuote;
        tab = 1;
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
    if (error.code == 'cancel_not_supported') return t('لغو این سفارش از سمت Provider پشتیبانی نمی‌شود.', 'Provider does not support cancelling this order.');
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _WalletStrip(host: host, fa: fa),
        const SizedBox(height: 18),
        Text(t('پلتفرم', 'Platform'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: availablePlatforms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 9),
            itemBuilder: (context, index) {
              final platform = availablePlatforms[index];
              return _PlatformCard(
                platform: platform,
                fa: fa,
                selected: platform == selectedPlatform,
                onTap: () => setState(() {
                  selectedPlatform = platform;
                  selectedGroup = null;
                  selectedService = null;
                  quote = null;
                }),
              );
            },
          ),
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
        if (selectedService != null) ...[
          const SizedBox(height: 8),
          buildOrderForm(selectedService!),
          const SizedBox(height: 24),
        ],
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
          ...service.orderFields.map((field) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: buildField(field),
              )),
          if (service.minQty != null || service.maxQty != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                t('محدوده سفارش: ${service.minQty ?? '—'} تا ${service.maxQty ?? '—'}', 'Order range: ${service.minQty ?? '—'} to ${service.maxQty ?? '—'}'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
              ),
            ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFF4FAFF), borderRadius: BorderRadius.circular(16)),
            child: Column(
              children: [
                _InfoRow(label: t('نرخ', 'Rate'), value: '${host.money(service.priceRateAfn, showBase: true)} / ${service.priceUnit}'),
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

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.platform, required this.fa, required this.selected, required this.onTap});
  final String platform;
  final bool fa;
  final bool selected;
  final VoidCallback onTap;

  IconData get icon {
    switch (platform) {
      case 'YOUTUBE': return Icons.play_circle_fill_rounded;
      case 'TELEGRAM': return Icons.send_rounded;
      case 'FACEBOOK': return Icons.facebook_rounded;
      case 'TIKTOK': return Icons.music_note_rounded;
      case 'X': return Icons.alternate_email_rounded;
      case 'LINKEDIN': return Icons.business_center_rounded;
      case 'SNAPCHAT': return Icons.camera_alt_rounded;
      case 'SPOTIFY': return Icons.headphones_rounded;
      default: return Icons.photo_camera_rounded;
    }
  }

  String get label {
    switch (platform) {
      case 'INSTAGRAM': return 'Instagram';
      case 'TIKTOK': return 'TikTok';
      case 'YOUTUBE': return 'YouTube';
      case 'FACEBOOK': return 'Facebook';
      case 'TELEGRAM': return 'Telegram';
      case 'X': return 'X';
      case 'THREADS': return 'Threads';
      case 'SNAPCHAT': return 'Snapchat';
      case 'LINKEDIN': return 'LinkedIn';
      case 'PINTEREST': return 'Pinterest';
      case 'SPOTIFY': return 'Spotify';
      case 'SOUNDCLOUD': return 'SoundCloud';
      case 'DISCORD': return 'Discord';
      default: return fa ? 'سایر' : 'Other';
    }
  }

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 94,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF0D78C8) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? const Color(0xFF0D78C8) : const Color(0xFFDCE8F1)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : const Color(0xFF0D78C8), size: 26),
              const SizedBox(height: 6),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : const Color(0xFF102235))),
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
