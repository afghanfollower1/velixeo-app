import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_service.dart';
import '../core/models.dart';
import 'admin_models.dart';
import 'admin_web_tool.dart';

String _a(bool fa, String faText, String enText) => fa ? faText : enText;

String _digits(Object value, bool fa) {
  final source = value.toString();
  if (!fa) return source;
  const latin = '0123456789';
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  return source.split('').map((char) {
    final index = latin.indexOf(char);
    return index < 0 ? char : persian[index];
  }).join();
}

String _money(int value, bool fa) {
  final source = value.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < source.length; i += 1) {
    if (i > 0 && (source.length - i) % 3 == 0) out.write(fa ? '٬' : ',');
    out.write(fa ? _digits(source[i], true) : source[i]);
  }
  return value < 0 ? '-' + out.toString() : out.toString();
}

String _ago(DateTime date, bool fa) {
  final diff = DateTime.now().difference(date.toLocal());
  if (diff.inMinutes < 1) return _a(fa, 'همین حالا', 'just now');
  if (diff.inHours < 1) {
    return _a(
      fa,
      _digits(diff.inMinutes, true) + ' دقیقه پیش',
      diff.inMinutes.toString() + ' min ago',
    );
  }
  if (diff.inDays < 1) {
    return _a(
      fa,
      _digits(diff.inHours, true) + ' ساعت پیش',
      diff.inHours.toString() + 'h ago',
    );
  }
  return _a(
    fa,
    _digits(diff.inDays, true) + ' روز پیش',
    diff.inDays.toString() + 'd ago',
  );
}

class AdminToolGroup {
  const AdminToolGroup({
    required this.titleFa,
    required this.titleEn,
    required this.subtitleFa,
    required this.subtitleEn,
    required this.icon,
    required this.tone,
    required this.tools,
  });
  final String titleFa;
  final String titleEn;
  final String subtitleFa;
  final String subtitleEn;
  final IconData icon;
  final AdminTone tone;
  final List<AdminTool> tools;
}

const _social = AdminTool(
  keyName: 'social',
  titleFa: 'شبکه‌های اجتماعی',
  titleEn: 'Social media',
  subtitleFa: 'برندها، خدمات و مسیریابی',
  subtitleEn: 'Brands, services and routing',
  icon: Icons.camera_alt_outlined,
  path: '/admin/v3?section=social',
);

const _virtual = AdminTool(
  keyName: 'virtual',
  titleFa: 'شماره مجازی',
  titleEn: 'Virtual numbers',
  subtitleFa: 'کشورها، اپراتورها و قیمت‌گذاری',
  subtitleEn: 'Countries, operators and pricing',
  icon: Icons.phone_iphone_rounded,
  path: '/admin/v3?section=virtual',
);

const _premium = AdminTool(
  keyName: 'premium',
  titleFa: 'اشتراک پریمیوم',
  titleEn: 'Premium',
  subtitleFa: 'محصولات، بسته‌ها و تحویل سفارش',
  subtitleEn: 'Products, plans and fulfillment',
  icon: Icons.diamond_outlined,
  path: '/admin/v3?section=premium',
  tone: AdminTone.purple,
);

const _topup = AdminTool(
  keyName: 'topup',
  titleFa: 'شارژ سیم‌کارت',
  titleEn: 'Mobile top-up',
  subtitleFa: 'وضعیت آماده‌سازی این بخش',
  subtitleEn: 'Service readiness',
  icon: Icons.battery_charging_full_rounded,
  path: '/admin/v3?section=topup',
  tone: AdminTone.peach,
);

const _digital = AdminTool(
  keyName: 'digital',
  titleFa: 'حساب‌های دیجیتال',
  titleEn: 'Digital accounts',
  subtitleFa: 'محصولات و ارائه‌دهندگان',
  subtitleEn: 'Products and providers',
  icon: Icons.layers_outlined,
  path: '/admin/v3?section=accounts',
);

const List<AdminToolGroup> adminToolGroups = [
  AdminToolGroup(
    titleFa: 'خدمات و ارائه‌دهندگان',
    titleEn: 'Services & providers',
    subtitleFa: 'پنج بخش، با تنظیمات اختصاصی',
    subtitleEn: 'Five workspaces, each with its own controls',
    icon: Icons.layers_outlined,
    tone: AdminTone.blue,
    tools: [_social, _virtual, _premium, _topup, _digital],
  ),
  AdminToolGroup(
    titleFa: 'سفارش‌های مشتریان',
    titleEn: 'Customer orders',
    subtitleFa: 'پیگیری، رسیدگی و تحویل سفارش',
    subtitleEn: 'Track, review and fulfill',
    icon: Icons.assignment_outlined,
    tone: AdminTone.purple,
    tools: [
      AdminTool(
        keyName: 'orders',
        titleFa: 'همه سفارش‌ها',
        titleEn: 'All customer orders',
        subtitleFa: 'فهرست یکپارچه سفارش‌های مشتریان',
        subtitleEn: 'A single view of all customer orders',
        icon: Icons.assignment_outlined,
        path: '/admin/v3?section=orders',
      ),
      AdminTool(
        keyName: 'social-orders',
        titleFa: 'سفارش‌های اجتماعی',
        titleEn: 'Social orders',
        subtitleFa: 'وضعیت، دریپ‌فید و جبران ریزش',
        subtitleEn: 'Status, drip-feed and refill',
        icon: Icons.camera_alt_outlined,
        path: '/admin/v3?section=orders&kind=social',
      ),
      AdminTool(
        keyName: 'virtual-orders',
        titleFa: 'سفارش‌های شماره',
        titleEn: 'Number orders',
        subtitleFa: 'پیامک، لغو و بازپرداخت',
        subtitleEn: 'SMS, cancellation and refunds',
        icon: Icons.phone_iphone_rounded,
        path: '/admin/v3?section=orders&kind=virtual',
      ),
      AdminTool(
        keyName: 'premium-orders',
        titleFa: 'سفارش‌های پریمیوم',
        titleEn: 'Premium orders',
        subtitleFa: 'اطلاعات مشتری و تحویل دستی',
        subtitleEn: 'Customer details and manual delivery',
        icon: Icons.diamond_outlined,
        path: '/admin/v3?section=premium&tab=orders',
        tone: AdminTone.purple,
      ),
      AdminTool(
        keyName: 'digital-orders',
        titleFa: 'سفارش‌های دیجیتال',
        titleEn: 'Digital orders',
        subtitleFa: 'پیگیری سفارش‌های این بخش',
        subtitleEn: 'Track digital purchases',
        icon: Icons.layers_outlined,
        path: '/admin/v3?section=orders&kind=accounts',
      ),
    ],
  ),
  AdminToolGroup(
    titleFa: 'کاربران و دسترسی‌ها',
    titleEn: 'Users & access',
    subtitleFa: 'حساب‌ها، کیف پول و دعوت دوستان',
    subtitleEn: 'Accounts, balances and referrals',
    icon: Icons.people_outline_rounded,
    tone: AdminTone.green,
    tools: [
      AdminTool(
        keyName: 'users',
        titleFa: 'کاربران',
        titleEn: 'Users',
        subtitleFa: 'اطلاعات حساب و مدیریت دسترسی',
        subtitleEn: 'Accounts and access management',
        icon: Icons.people_outline_rounded,
        path: '/admin/v3?section=users',
        tone: AdminTone.green,
      ),
      AdminTool(
        keyName: 'blacklist',
        titleFa: 'فهرست سیاه تلفن',
        titleEn: 'Phone blacklist',
        subtitleFa: 'شماره‌های مسدودشده',
        subtitleEn: 'Blocked phone numbers',
        icon: Icons.phonelink_erase_rounded,
        path: '/admin/v3?section=users',
        tone: AdminTone.peach,
      ),
      AdminTool(
        keyName: 'referrals',
        titleFa: 'دعوت دوستان',
        titleEn: 'Referrals',
        subtitleFa: 'تنظیمات و گزارش پاداش‌ها',
        subtitleEn: 'Reward settings and activity',
        icon: Icons.card_giftcard_rounded,
        path: '/admin/v3?section=referrals',
        tone: AdminTone.green,
      ),
    ],
  ),
  AdminToolGroup(
    titleFa: 'پرداخت‌ها و کیف پول',
    titleEn: 'Payments & wallet',
    subtitleFa: 'تراکنش‌ها، پرداخت‌ها و تخفیف‌ها',
    subtitleEn: 'Transactions, payments and discounts',
    icon: Icons.account_balance_wallet_outlined,
    tone: AdminTone.peach,
    tools: [
      AdminTool(
        keyName: 'payments',
        titleFa: 'پرداخت‌ها و تراکنش‌ها',
        titleEn: 'Payments & transactions',
        subtitleFa: 'تأیید پرداخت و گردش حساب',
        subtitleEn: 'Payment verification and ledger',
        icon: Icons.account_balance_wallet_outlined,
        path: '/admin/v3?section=payments',
        tone: AdminTone.green,
      ),
      AdminTool(
        keyName: 'coupons',
        titleFa: 'کدهای تخفیف',
        titleEn: 'Discount codes',
        subtitleFa: 'کدها، محدودیت‌ها و مدت اعتبار',
        subtitleEn: 'Codes, limits and validity',
        icon: Icons.confirmation_number_outlined,
        path: '/admin/v3?section=coupons',
        tone: AdminTone.peach,
      ),
    ],
  ),
  AdminToolGroup(
    titleFa: 'محتوا و تنظیمات',
    titleEn: 'Content & settings',
    subtitleFa: 'پشتیبانی، بنرها و تنظیمات سیستم',
    subtitleEn: 'Support, banners and system settings',
    icon: Icons.tune_rounded,
    tone: AdminTone.purple,
    tools: [
      AdminTool(
        keyName: 'support',
        titleFa: 'پشتیبانی مشتریان',
        titleEn: 'Customer support',
        subtitleFa: 'گفت‌وگوها و درخواست‌های باز',
        subtitleEn: 'Conversations and open tickets',
        icon: Icons.forum_outlined,
        path: '/admin/v3?section=support',
        tone: AdminTone.peach,
      ),
      AdminTool(
        keyName: 'banners',
        titleFa: 'بنرها و تبلیغات',
        titleEn: 'Banners & advertising',
        subtitleFa: 'بنر هر بخش و لینک مقصد',
        subtitleEn: 'Section banners and destinations',
        icon: Icons.image_outlined,
        path: '/admin/v3?section=banners',
      ),
      AdminTool(
        keyName: 'notifications',
        titleFa: 'اعلان‌های کاربران',
        titleEn: 'Customer notifications',
        subtitleFa: 'ارسال و زمان‌بندی اعلان',
        subtitleEn: 'Publish and schedule notifications',
        icon: Icons.notifications_none_rounded,
        path: '/admin/v3?section=notifications',
      ),
      AdminTool(
        keyName: 'settings',
        titleFa: 'تنظیمات سیستم',
        titleEn: 'System settings',
        subtitleFa: 'واحد پول و تنظیمات عمومی',
        subtitleEn: 'Currencies and general preferences',
        icon: Icons.settings_outlined,
        path: '/admin/v3?section=settings',
      ),
      AdminTool(
        keyName: 'audit',
        titleFa: 'گزارش فعالیت مدیران',
        titleEn: 'Admin activity log',
        subtitleFa: 'چه کسی، چه چیزی را تغییر داده؟',
        subtitleEn: 'Who changed what and when?',
        icon: Icons.history_rounded,
        path: '/admin/v3?section=audit',
        tone: AdminTone.purple,
      ),
    ],
  ),
];

class AdminAccessBar extends StatelessWidget {
  const AdminAccessBar({
    super.key,
    required this.fa,
    required this.inManagement,
    required this.onTap,
  });

  final bool fa;
  final bool inManagement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 19),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: inManagement ? Colors.white : const Color(0xFFEAF7FD),
          border: Border.all(
            color: inManagement ? const Color(0xFFE4EDF3) : const Color(0xFFD4EDF8),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.shield_outlined, size: 17, color: Color(0xFF4284A1)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _a(fa, 'حساب مدیر', 'Admin account'),
                style: const TextStyle(
                  color: Color(0xFF4284A1),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: onTap,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: EdgeInsets.zero,
                foregroundColor: const Color(0xFF24779A),
              ),
              icon: Icon(
                inManagement ? Icons.shopping_bag_outlined : Icons.dashboard_outlined,
                size: 16,
              ),
              label: Text(
                inManagement
                    ? _a(fa, 'خرید و خدمات', 'Shop & services')
                    : _a(fa, 'مدیریت', 'Manage'),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class AdminMobileDashboard extends StatefulWidget {
  const AdminMobileDashboard({
    super.key,
    required this.api,
    required this.user,
    required this.fa,
    required this.onExitManagement,
  });

  final ApiService api;
  final AppUser user;
  final bool fa;
  final VoidCallback onExitManagement;

  @override
  State<AdminMobileDashboard> createState() => _AdminMobileDashboardState();
}

class _AdminMobileDashboardState extends State<AdminMobileDashboard> {
  AdminMobileOverview? data;
  bool loading = true;
  Object? error;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    if (mounted) {
      setState(() {
        loading = data == null;
        error = null;
      });
    }
    try {
      final result = await widget.api.adminMobileOverview();
      if (!mounted) return;
      setState(() {
        data = result;
        loading = false;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = caught;
      });
    }
  }

  void openTool(AdminTool tool) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminWebToolPage(api: widget.api, fa: widget.fa, tool: tool),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fa = widget.fa;
    final current = data;
    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(31, 15, 31, 24),
            children: [
              _TopBar(
                fa: fa,
                onExit: widget.onExitManagement,
                onAlert: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminAttentionPage(
                      api: widget.api,
                      fa: fa,
                      overview: current,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AdminAccessBar(
                fa: fa,
                inManagement: true,
                onTap: widget.onExitManagement,
              ),
              _Hero(fa: fa, updatedAt: current?.updatedAt, onRefresh: load),
              if (loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFF38BDF8),
                  backgroundColor: Color(0xFFE8F6FC),
                ),
              ],
              if (error != null && current == null) ...[
                const SizedBox(height: 12),
                _Notice(
                  text: _a(
                    fa,
                    'اطلاعات مدیریت بارگذاری نشد. صفحه را پایین بکش و دوباره تلاش کن.',
                    'Management data could not be loaded. Pull down to retry.',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _KpiGrid(fa: fa, data: current),
              const SizedBox(height: 4),
              _AttentionCard(
                fa: fa,
                count: current?.needsAttention ?? 0,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminAttentionPage(
                      api: widget.api,
                      fa: fa,
                      overview: current,
                    ),
                  ),
                ),
              ),
              _SectionHeader(fa: fa, titleFa: 'دسترسی سریع', titleEn: 'Quick access'),
              const SizedBox(height: 11),
              _QuickAccess(
                fa: fa,
                orders: current?.needsAttention ?? 0,
                support: current?.openTickets ?? 0,
                onOrders: () => openTool(adminToolGroups[1].tools[0]),
                onUsers: () => openTool(adminToolGroups[2].tools[0]),
                onProviders: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminProvidersChooserPage(
                      api: widget.api,
                      fa: fa,
                    ),
                  ),
                ),
                onSupport: () => openTool(adminToolGroups[4].tools[0]),
              ),
              const SizedBox(height: 26),
              _SectionHeader(
                fa: fa,
                titleFa: 'مدیریت بخش‌ها',
                titleEn: 'Manage workspaces',
                actionFa: 'مشاهده همه',
                actionEn: 'View all',
                onAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminManagementCenterPage(
                      api: widget.api,
                      fa: fa,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 11),
              _AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Column(
                  children: adminToolGroups.first.tools
                      .map(
                        (tool) => _MenuTile(
                          fa: fa,
                          tool: tool,
                          onTap: () => openTool(tool),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              const SizedBox(height: 26),
              _SectionHeader(
                fa: fa,
                titleFa: 'آخرین فعالیت‌ها',
                titleEn: 'Recent activity',
                actionFa: 'مشاهده همه',
                actionEn: 'View all',
                onAction: () => openTool(adminToolGroups.last.tools.last),
              ),
              const SizedBox(height: 11),
              _ActivityCard(fa: fa, items: current?.recentActivity ?? const []),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 17,
                    color: Color(0xFF879BA8),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _a(fa, 'برای خودت خرید می‌کنی؟', 'Shopping for yourself?'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF879BA8)),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: widget.onExitManagement,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFFE1EAF0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _a(fa, 'خدمات و ثبت سفارش', 'Browse & order'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.fa, required this.onExit, required this.onAlert});
  final bool fa;
  final VoidCallback onExit;
  final VoidCallback onAlert;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 58,
        child: Row(
          children: [
            _CircleButton(icon: Icons.notifications_none_rounded, onTap: onAlert),
            Expanded(
              child: Text(
                _a(fa, 'مدیریت در اپ', 'Management'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF24343D),
                ),
              ),
            ),
            _CircleButton(
              icon: fa ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
              onTap: onExit,
            ),
          ],
        ),
      );
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE2EAF0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 23, color: const Color(0xFF344E5B)),
        ),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.fa, required this.updatedAt, required this.onRefresh});
  final bool fa;
  final DateTime? updatedAt;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFB7EAFF), Color(0xFFDCF4FF)],
          ),
          borderRadius: BorderRadius.circular(23),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              end: -75,
              top: -85,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _a(fa, 'نمای امروز · مدیریت VELIXEO', 'TODAY · VELIXEO ADMIN'),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF58869B)),
                      ),
                    ),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white60,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 20,
                        color: Color(0xFF56A6C7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _a(fa, 'همه‌چیز، زیر نظر تو.', 'Everything, in your hands.'),
                  style: const TextStyle(
                    fontSize: 23,
                    height: 1.55,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B5265),
                  ),
                ),
                Text(
                  _a(fa, 'خلاصهٔ کسب‌وکارت، بدون شلوغی.', 'A clear view of your business.'),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF648697)),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: Colors.white54),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF56AD8C),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        updatedAt == null
                            ? _a(fa, 'آخرین به‌روزرسانی: همین حالا', 'Updated just now')
                            : _a(
                                fa,
                                'آخرین به‌روزرسانی: ' + _ago(updatedAt!, true),
                                'Updated ' + _ago(updatedAt!, false),
                              ),
                        style: const TextStyle(fontSize: 9, color: Color(0xFF5A8092)),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onRefresh,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 30),
                        foregroundColor: const Color(0xFF387F9F),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 13),
                      label: Text(
                        _a(fa, 'تازه‌سازی', 'Refresh'),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.fa, required this.data});
  final bool fa;
  final AdminMobileOverview? data;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (
        title: _a(fa, 'فروش امروز', 'Today’s sales'),
        value: data == null ? '—' : _money(data!.salesTodayAfn, fa),
        unit: _a(fa, 'افغانی', 'AFN'),
        note: _a(fa, 'فروش ثبت‌شده امروز', 'Recorded sales today'),
        icon: Icons.account_balance_wallet_outlined,
        tone: AdminTone.green,
      ),
      (
        title: _a(fa, 'سفارش‌های امروز', 'Orders today'),
        value: data == null ? '—' : _digits(data!.ordersToday, fa),
        unit: '',
        note: _a(
          fa,
          _digits(data?.needsAttention ?? 0, true) + ' نیازمند رسیدگی',
          (data?.needsAttention ?? 0).toString() + ' need attention',
        ),
        icon: Icons.shopping_bag_outlined,
        tone: AdminTone.blue,
      ),
      (
        title: _a(fa, 'کاربران جدید', 'New customers'),
        value: data == null ? '—' : _digits(data!.usersToday, fa),
        unit: '',
        note: _a(fa, 'از ابتدای امروز', 'Since midnight'),
        icon: Icons.person_add_alt_1_outlined,
        tone: AdminTone.purple,
      ),
      (
        title: _a(fa, 'تیکت‌های باز', 'Open tickets'),
        value: data == null ? '—' : _digits(data!.openTickets, fa),
        unit: '',
        note: _a(fa, 'در انتظار پیگیری', 'Waiting for follow-up'),
        icon: Icons.forum_outlined,
        tone: AdminTone.peach,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.23,
      ),
      itemBuilder: (_, index) {
        final item = cards[index];
        return _AdminCard(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF7B919D)),
                    ),
                  ),
                  _ToneIcon(icon: item.icon, tone: item.tone, compact: true),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      item.value,
                      maxLines: 1,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF24343D),
                      ),
                    ),
                  ),
                  if (item.unit.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        item.unit,
                        style: const TextStyle(fontSize: 8.5, color: Color(0xFF91A5AF)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: item.tone == AdminTone.green
                      ? const Color(0xFF5C9E84)
                      : const Color(0xFF819BA6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({
    required this.fa,
    required this.count,
    required this.onTap,
  });
  final bool fa;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 4, 0, 24),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7EC),
            border: Border.all(color: const Color(0xFFF4E9D9)),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 35,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFBEAD0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  size: 19,
                  color: Color(0xFF9B7B49),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _a(fa, 'اول از اینجا شروع کن', 'Start here'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF83693F),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _a(
                        fa,
                        _digits(count, true) + ' سفارش منتظر رسیدگی توست',
                        count.toString() + ' orders are waiting for your attention',
                      ),
                      style: const TextStyle(fontSize: 10, color: Color(0xFFA28B69)),
                    ),
                  ],
                ),
              ),
              Icon(
                fa ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: const Color(0xFFA28B69),
                size: 18,
              ),
            ],
          ),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.fa,
    required this.titleFa,
    required this.titleEn,
    this.actionFa,
    this.actionEn,
    this.onAction,
  });
  final bool fa;
  final String titleFa;
  final String titleEn;
  final String? actionFa;
  final String? actionEn;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              _a(fa, titleFa, titleEn),
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF24343D),
              ),
            ),
          ),
          if (onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                _a(fa, actionFa ?? '', actionEn ?? ''),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF318EB6),
                ),
              ),
            ),
        ],
      );
}

class _QuickAccess extends StatelessWidget {
  const _QuickAccess({
    required this.fa,
    required this.orders,
    required this.support,
    required this.onOrders,
    required this.onUsers,
    required this.onProviders,
    required this.onSupport,
  });
  final bool fa;
  final int orders;
  final int support;
  final VoidCallback onOrders;
  final VoidCallback onUsers;
  final VoidCallback onProviders;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        label: _a(fa, 'سفارش‌ها', 'Orders'),
        icon: Icons.assignment_outlined,
        tone: AdminTone.blue,
        badge: orders,
        tap: onOrders,
      ),
      (
        label: _a(fa, 'کاربران', 'Users'),
        icon: Icons.people_outline_rounded,
        tone: AdminTone.green,
        badge: 0,
        tap: onUsers,
      ),
      (
        label: _a(fa, 'ارائه‌دهندگان', 'Providers'),
        icon: Icons.power_outlined,
        tone: AdminTone.purple,
        badge: 0,
        tap: onProviders,
      ),
      (
        label: _a(fa, 'پشتیبانی', 'Support'),
        icon: Icons.forum_outlined,
        tone: AdminTone.peach,
        badge: support,
        tap: onSupport,
      ),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.map((item) {
        return Expanded(
          child: InkWell(
            onTap: item.tap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      _ToneIcon(icon: item.icon, tone: item.tone),
                      if (item.badge > 0)
                        PositionedDirectional(
                          end: -4,
                          top: -4,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE2EDF2)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _digits(item.badge, fa),
                              style: const TextStyle(fontSize: 8, color: Color(0xFF6391A6)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF738995)),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon({required this.icon, required this.tone, this.compact = false});
  final IconData icon;
  final AdminTone tone;
  final bool compact;

  Color get background {
    switch (tone) {
      case AdminTone.green:
        return const Color(0xFFEEF8F3);
      case AdminTone.purple:
        return const Color(0xFFF2EFFB);
      case AdminTone.peach:
        return const Color(0xFFFFF5E9);
      case AdminTone.blue:
        return const Color(0xFFEDF8FD);
    }
  }

  Color get foreground {
    switch (tone) {
      case AdminTone.green:
        return const Color(0xFF63A68D);
      case AdminTone.purple:
        return const Color(0xFFA093C8);
      case AdminTone.peach:
        return const Color(0xFFC5A071);
      case AdminTone.blue:
        return const Color(0xFF57A4C5);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        width: compact ? 26 : 49,
        height: compact ? 26 : 49,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(compact ? 8 : 16),
          border: compact ? null : Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, size: compact ? 14 : 21, color: foreground),
      );
}

class _AdminCard extends StatelessWidget {
  const _AdminCard({
    required this.child,
    this.padding = const EdgeInsets.all(17),
    this.radius = 20,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEBF0F4)),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.fa, required this.tool, required this.onTap});
  final bool fa;
  final AdminTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFEEF3F6))),
          ),
          child: Row(
            children: [
              _ToneIcon(icon: tool.icon, tone: tool.tone),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tool.title(fa),
                      style: const TextStyle(
                        color: Color(0xFF4C6573),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tool.subtitle(fa),
                      style: const TextStyle(
                        color: Color(0xFF8EA0AA),
                        fontSize: 10,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                fa ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: const Color(0xFFADC0CB),
                size: 18,
              ),
            ],
          ),
        ),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.fa, required this.items});
  final bool fa;
  final List<AdminActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = items.take(3).toList(growable: false);
    return _AdminCard(
      child: rows.isEmpty
          ? Text(
              _a(fa, 'هنوز فعالیت مدیریتی ثبت نشده است.', 'No recent admin activity.'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF8EA0AA)),
            )
          : Column(
              children: List.generate(rows.length, (index) {
                final item = rows[index];
                return Padding(
                  padding: EdgeInsets.only(bottom: index == rows.length - 1 ? 0 : 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index.isEven
                              ? const Color(0xFF97C5AF)
                              : const Color(0xFF9DD3E9),
                          boxShadow: [
                            BoxShadow(
                              color: index.isEven
                                  ? const Color(0xFFF0F8F4)
                                  : const Color(0xFFF0F9FD),
                              spreadRadius: 4,
                              blurRadius: 0,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.summary,
                              style: const TextStyle(fontSize: 11, color: Color(0xFF597483)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.adminName + ' · ' + _ago(item.createdAt, fa),
                              style: const TextStyle(fontSize: 9, color: Color(0xFF9BABB4)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7EC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF4E9D9)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFA77D45)),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8E744E)),
              ),
            ),
          ],
        ),
      );
}

class AdminManagementCenterPage extends StatefulWidget {
  const AdminManagementCenterPage({
    super.key,
    required this.api,
    required this.fa,
  });
  final ApiService api;
  final bool fa;

  @override
  State<AdminManagementCenterPage> createState() => _AdminManagementCenterPageState();
}

class _AdminManagementCenterPageState extends State<AdminManagementCenterPage> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final fa = widget.fa;
    final needle = query.trim().toLowerCase();
    final groups = adminToolGroups.map((group) {
      final tools = needle.isEmpty
          ? group.tools
          : group.tools.where((tool) {
              final haystack = [
                tool.titleFa,
                tool.titleEn,
                tool.subtitleFa,
                tool.subtitleEn,
              ].join(' ').toLowerCase();
              return haystack.contains(needle);
            }).toList(growable: false);
      return AdminToolGroup(
        titleFa: group.titleFa,
        titleEn: group.titleEn,
        subtitleFa: group.subtitleFa,
        subtitleEn: group.subtitleEn,
        icon: group.icon,
        tone: group.tone,
        tools: tools,
      );
    }).where((group) => group.tools.isNotEmpty).toList(growable: false);

    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              _PageHeader(
                fa: fa,
                faTitle: 'مرکز مدیریت',
                enTitle: 'Management center',
                faSubtitle: 'ابزار مورد نیازت را سریع پیدا کن.',
                enSubtitle: 'Find the right tool, right when you need it.',
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => setState(() => query = value),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  hintText: _a(
                    fa,
                    'جستجو؛ مثلاً قیمت‌گذاری یا بنر…',
                    'Search pricing, banners, users…',
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE4EDF3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF9EDCF4)),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (groups.isEmpty)
                _Notice(
                  text: _a(
                    fa,
                    'ابزاری با این جستجو پیدا نشد.',
                    'No management tool matched your search.',
                  ),
                ),
              ...groups.map(
                (group) => Padding(
                  padding: const EdgeInsets.only(bottom: 17),
                  child: _AdminCard(
                    padding: const EdgeInsets.fromLTRB(14, 17, 14, 0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _ToneIcon(icon: group.icon, tone: group.tone),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _a(fa, group.titleFa, group.titleEn),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _a(fa, group.subtitleFa, group.subtitleEn),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Color(0xFF8FA3AF),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFE9F0F5)),
                        ...group.tools.map(
                          (tool) => _MenuTile(
                            fa: fa,
                            tool: tool,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminWebToolPage(
                                  api: widget.api,
                                  fa: fa,
                                  tool: tool,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminProvidersChooserPage extends StatelessWidget {
  const AdminProvidersChooserPage({
    super.key,
    required this.api,
    required this.fa,
  });
  final ApiService api;
  final bool fa;

  @override
  Widget build(BuildContext context) {
    const tools = [
      AdminTool(
        keyName: 'social-providers',
        titleFa: 'شبکه‌های اجتماعی',
        titleEn: 'Social media',
        subtitleFa: 'ارائه‌دهندگان و سرویس‌های SMM',
        subtitleEn: 'SMM providers and service catalogs',
        icon: Icons.camera_alt_outlined,
        path: '/admin/v3/social/providers',
      ),
      AdminTool(
        keyName: 'virtual-providers',
        titleFa: 'شماره مجازی',
        titleEn: 'Virtual numbers',
        subtitleFa: 'ارائه‌دهندگان شماره و پیامک',
        subtitleEn: 'Number and SMS providers',
        icon: Icons.phone_iphone_rounded,
        path: '/admin/v3?section=virtual',
      ),
      AdminTool(
        keyName: 'digital-providers',
        titleFa: 'حساب‌های دیجیتال',
        titleEn: 'Digital accounts',
        subtitleFa: 'اتصال و تنظیمات محصولات',
        subtitleEn: 'Product connections and settings',
        icon: Icons.layers_outlined,
        path: '/admin/v3?section=accounts',
        tone: AdminTone.purple,
      ),
    ];

    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              _PageHeader(
                fa: fa,
                faTitle: 'ارائه‌دهندگان',
                enTitle: 'Providers',
                faSubtitle: 'هر بخش، اتصال و کاتالوگ خودش را دارد.',
                enSubtitle: 'Each workspace has its own connections and catalog.',
              ),
              const SizedBox(height: 17),
              _AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Column(
                  children: tools.map(
                    (tool) => _MenuTile(
                      fa: fa,
                      tool: tool,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminWebToolPage(api: api, fa: fa, tool: tool),
                        ),
                      ),
                    ),
                  ).toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminAttentionPage extends StatelessWidget {
  const AdminAttentionPage({
    super.key,
    required this.api,
    required this.fa,
    required this.overview,
  });
  final ApiService api;
  final bool fa;
  final AdminMobileOverview? overview;

  @override
  Widget build(BuildContext context) {
    final attention = overview?.attention ?? const AdminAttentionCounts();
    final rows = [
      (adminToolGroups[1].tools[3], attention.premium),
      (adminToolGroups[1].tools[1], attention.social),
      (adminToolGroups[1].tools[2], attention.virtualNumber),
      (adminToolGroups[4].tools[0], attention.support),
    ];

    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              _PageHeader(
                fa: fa,
                faTitle: 'نوبت رسیدگی توست',
                enTitle: 'Your attention matters',
                faSubtitle: 'موارد مهم، کنار هم و قابل پیگیری.',
                enSubtitle: 'Important tasks, together and easy to follow.',
              ),
              const SizedBox(height: 17),
              _AdminCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Column(
                  children: rows.map((row) {
                    final tool = row.$1;
                    final count = row.$2;
                    final label = AdminTool(
                      keyName: tool.keyName,
                      titleFa: _digits(count, true) + ' ' + tool.titleFa,
                      titleEn: count.toString() + ' ' + tool.titleEn.toLowerCase(),
                      subtitleFa: tool.subtitleFa,
                      subtitleEn: tool.subtitleEn,
                      icon: tool.icon,
                      path: tool.path,
                      tone: tool.tone,
                    );
                    return _MenuTile(
                      fa: fa,
                      tool: label,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminWebToolPage(api: api, fa: fa, tool: tool),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.fa,
    required this.faTitle,
    required this.enTitle,
    required this.faSubtitle,
    required this.enSubtitle,
  });
  final bool fa;
  final String faTitle;
  final String enTitle;
  final String faSubtitle;
  final String enSubtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CircleButton(
                icon: fa ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded,
                onTap: () => Navigator.maybePop(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _a(fa, faTitle, enTitle),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF24343D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _a(fa, faSubtitle, enSubtitle),
            style: const TextStyle(fontSize: 12, height: 1.8, color: Color(0xFF879BA8)),
          ),
        ],
      );
}
