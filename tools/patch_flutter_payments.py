from pathlib import Path

# pubspec.yaml
pubspec = Path('pubspec.yaml')
text = pubspec.read_text()
if 'url_launcher:' not in text:
    text = text.replace('  google_sign_in: ^7.2.0\n', '  google_sign_in: ^7.2.0\n  url_launcher: ^6.3.2\n', 1)
pubspec.write_text(text)

# lib/core/models.dart
models = Path('lib/core/models.dart')
text = models.read_text()
if 'class AppPayment {' not in text:
    text += r'''

class AppPayment {
  const AppPayment({
    required this.id,
    required this.gateway,
    required this.status,
    required this.amountAfn,
    required this.createdAt,
    required this.updatedAt,
    this.checkoutUrl,
    this.externalId,
    this.failureReason,
    this.paidAt,
    this.verifiedAt,
  });

  final String id;
  final String gateway;
  final String status;
  final int amountAfn;
  final String? checkoutUrl;
  final String? externalId;
  final String? failureReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? paidAt;
  final DateTime? verifiedAt;

  factory AppPayment.fromJson(Map<String, dynamic> json) => AppPayment(
        id: json['id'] as String,
        gateway: (json['gateway'] as String?) ?? 'UNKNOWN',
        status: (json['status'] as String?) ?? 'PENDING',
        amountAfn: int.tryParse('${json['amountAfn']}') ?? 0,
        checkoutUrl: json['checkoutUrl'] as String?,
        externalId: json['externalId'] as String?,
        failureReason: json['failureReason'] as String?,
        createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
        updatedAt: DateTime.tryParse('${json['updatedAt']}') ?? DateTime.now(),
        paidAt: json['paidAt'] == null ? null : DateTime.tryParse('${json['paidAt']}'),
        verifiedAt: json['verifiedAt'] == null ? null : DateTime.tryParse('${json['verifiedAt']}'),
      );
}

class PaymentCapabilities {
  const PaymentCapabilities({
    this.hesabPayConfigured = false,
    this.hesabPayEnvironment,
    this.webhookUrl,
  });

  final bool hesabPayConfigured;
  final String? hesabPayEnvironment;
  final String? webhookUrl;

  factory PaymentCapabilities.fromJson(Map<String, dynamic> json) {
    final gateways = json['gateways'] is Map
        ? Map<String, dynamic>.from(json['gateways'] as Map)
        : const <String, dynamic>{};
    final hesabPay = gateways['HESABPAY'] is Map
        ? Map<String, dynamic>.from(gateways['HESABPAY'] as Map)
        : const <String, dynamic>{};
    return PaymentCapabilities(
      hesabPayConfigured: (hesabPay['configured'] as bool?) ?? false,
      hesabPayEnvironment: hesabPay['environment'] as String?,
      webhookUrl: json['webhookUrl'] as String?,
    );
  }
}

class PaymentSessionResult {
  const PaymentSessionResult({
    required this.payment,
    required this.idempotent,
    this.checkoutUrl,
  });

  final AppPayment payment;
  final bool idempotent;
  final String? checkoutUrl;

  factory PaymentSessionResult.fromJson(Map<String, dynamic> json) {
    final payment = AppPayment.fromJson(
      Map<String, dynamic>.from(json['payment'] as Map),
    );
    return PaymentSessionResult(
      payment: payment,
      idempotent: (json['idempotent'] as bool?) ?? false,
      checkoutUrl: (json['checkoutUrl'] as String?) ?? payment.checkoutUrl,
    );
  }
}
'''
models.write_text(text)

# lib/core/api_service.dart
api = Path('lib/core/api_service.dart')
text = api.read_text()
if 'Future<PaymentCapabilities> paymentCapabilities()' not in text:
    insert = r'''

  Future<PaymentCapabilities> paymentCapabilities() async {
    final response = await _send('GET', '/api/v1/payments/capabilities', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return PaymentCapabilities.fromJson(_decodeObject(response));
  }

  Future<List<AppPayment>> payments() async {
    final response = await _send('GET', '/api/v1/payments', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['payments'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => AppPayment.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<AppPayment> payment(String id) async {
    final response = await _send('GET', '/api/v1/payments/$id', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return AppPayment.fromJson(
      Map<String, dynamic>.from(_decodeObject(response)['payment'] as Map),
    );
  }

  Future<PaymentSessionResult> createHesabPaySession({
    required int amountAfn,
    required String idempotencyKey,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/payments/hesabpay/session',
      body: {
        'amountAfn': amountAfn,
        'idempotencyKey': idempotencyKey,
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return PaymentSessionResult.fromJson(_decodeObject(response));
  }
'''
    index = text.rfind('\n}')
    if index < 0:
        raise SystemExit('ApiService class closing brace not found')
    text = text[:index] + insert + text[index:]
api.write_text(text)

# lib/app.dart
app = Path('lib/app.dart')
text = app.read_text()
if "package:url_launcher/url_launcher.dart" not in text:
    text = text.replace(
        "import 'package:flutter/material.dart';\n",
        "import 'package:flutter/material.dart';\nimport 'package:url_launcher/url_launcher.dart';\n",
        1,
    )

field_anchor = "  List<AppOrder> orders = const [];\n"
if 'PaymentCapabilities paymentCapabilities' not in text:
    text = text.replace(
        field_anchor,
        field_anchor + "  PaymentCapabilities paymentCapabilities = const PaymentCapabilities();\n  List<AppPayment> payments = const [];\n",
        1,
    )

load_anchor = """      try {
        orders = await api.orders();
      } catch (_) {}
"""
if 'paymentCapabilities = await api.paymentCapabilities();' not in text:
    text = text.replace(
        load_anchor,
        load_anchor + """      try {
        paymentCapabilities = await api.paymentCapabilities();
      } catch (_) {}
      try {
        payments = await api.payments();
      } catch (_) {}
""",
        1,
    )

method_anchor = "  Future<void> logout() async {\n"
if 'Future<void> refreshPaymentsAndWallet()' not in text:
    methods = r'''  Future<void> refreshPaymentsAndWallet() async {
    if (!authenticated) return;
    try {
      final result = await api.me();
      user = result.$1;
      balanceAfn = result.$2;
    } catch (_) {}
    try {
      walletEntries = await api.walletEntries();
    } catch (_) {}
    try {
      paymentCapabilities = await api.paymentCapabilities();
    } catch (_) {}
    try {
      payments = await api.payments();
    } catch (_) {}
    notifyListeners();
  }

  Future<PaymentSessionResult> createHesabPayTopUp(int amountAfn) async {
    final currentUser = user;
    if (!authenticated || currentUser == null) {
      throw const ApiException('unauthorized');
    }
    final result = await api.createHesabPaySession(
      amountAfn: amountAfn,
      idempotencyKey:
          'wallet-${currentUser.id}-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      payments = await api.payments();
    } catch (_) {}
    notifyListeners();
    return result;
  }

'''
    text = text.replace(method_anchor, methods + method_anchor, 1)

logout_anchor = """    notifications = const [];
    orders = const [];
    authError = null;
"""
if 'payments = const [];' not in text[text.find('Future<void> logout()'):text.find('String money(')]:
    text = text.replace(
        logout_anchor,
        """    notifications = const [];
    orders = const [];
    paymentCapabilities = const PaymentCapabilities();
    payments = const [];
    authError = null;
""",
        1,
    )

start = text.find('class AddFundsPage extends StatelessWidget {')
end = text.find('class ProfilePage extends StatelessWidget {')
if start < 0 or end < 0 or end <= start:
    raise SystemExit('AddFundsPage replacement anchors not found')

replacement = r'''class AddFundsPage extends StatefulWidget {
  const AddFundsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<AddFundsPage> createState() => _AddFundsPageState();
}

class _AddFundsPageState extends State<AddFundsPage>
    with WidgetsBindingObserver {
  final TextEditingController amount = TextEditingController(text: '500');
  bool busy = false;
  bool checkoutOpened = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      c.refreshPaymentsAndWallet();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    amount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && checkoutOpened) {
      checkoutOpened = false;
      c.refreshPaymentsAndWallet();
      if (mounted) setState(() {});
    }
  }

  String statusLabel(String status) {
    switch (status) {
      case 'PAID':
        return tr(c.fa, 'پرداخت موفق', 'Paid');
      case 'FAILED':
        return tr(c.fa, 'ناموفق', 'Failed');
      case 'CANCELLED':
        return tr(c.fa, 'لغو شده', 'Cancelled');
      case 'REFUNDED':
        return tr(c.fa, 'برگشت وجه', 'Refunded');
      default:
        return tr(c.fa, 'در انتظار تأیید', 'Pending verification');
    }
  }

  Color statusColor(String status) {
    switch (status) {
      case 'PAID':
        return const Color(0xFF18A875);
      case 'FAILED':
      case 'CANCELLED':
        return const Color(0xFFE65454);
      default:
        return const Color(0xFFEFAF38);
    }
  }

  String errorLabel(Object error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'hesabpay_not_configured':
        case 'hesabpay_configuration_invalid':
          return tr(c.fa, 'درگاه حساب‌پی هنوز روی سرور فعال نشده است.', 'HesabPay is not configured on the server yet.');
        case 'hesabpay_unavailable':
        case 'hesabpay_session_failed':
          return tr(c.fa, 'ارتباط با حساب‌پی برقرار نشد. دوباره تلاش کنید.', 'Could not reach HesabPay. Please try again.');
        case 'unauthorized':
          return tr(c.fa, 'نشست شما پایان یافته؛ دوباره وارد شوید.', 'Your session has expired. Please sign in again.');
        default:
          return tr(c.fa, 'ایجاد پرداخت انجام نشد. دوباره تلاش کنید.', 'Could not create the payment. Please try again.');
      }
    }
    return tr(c.fa, 'خطای ارتباطی رخ داد.', 'A network error occurred.');
  }

  Future<void> refresh() => c.refreshPaymentsAndWallet();

  Future<void> startPayment() async {
    FocusScope.of(context).unfocus();
    final value = int.tryParse(amount.text.trim());
    if (value == null || value < 1 || value > 100000000) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'مبلغ معتبر به افغانی وارد کنید.', 'Enter a valid AFN amount.'))),
      );
      return;
    }
    if (!c.paymentCapabilities.hesabPayConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(c.fa, 'درگاه حساب‌پی هنوز روی سرور فعال نشده است.', 'HesabPay is not configured on the server yet.'))),
      );
      return;
    }

    setState(() => busy = true);
    try {
      final session = await c.createHesabPayTopUp(value);
      final checkoutUrl = session.checkoutUrl;
      if (checkoutUrl == null || checkoutUrl.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(c.fa, 'جلسه پرداخت درحال آماده‌سازی است. چند لحظه بعد تازه‌سازی کنید.', 'The payment session is still initializing. Refresh in a moment.'))),
        );
        return;
      }

      final uri = Uri.tryParse(checkoutUrl);
      if (uri == null || !['https', 'http'].contains(uri.scheme)) {
        throw const ApiException('invalid_checkout_url');
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw const ApiException('checkout_launch_failed');
      checkoutOpened = true;
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorLabel(error))),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = c.paymentCapabilities.hesabPayConfigured;
    final environment = c.paymentCapabilities.hesabPayEnvironment;
    final recent = c.payments.take(8).toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(tr(c.fa, 'افزایش موجودی', 'Add Funds')),
        actions: [
          IconButton(
            tooltip: tr(c.fa, 'تازه‌سازی', 'Refresh'),
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(18),
          children: [
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: configured
                        ? const Color(0xFFE4F8EF)
                        : const Color(0xFFFFF4DE),
                    child: Icon(
                      configured ? Icons.verified_rounded : Icons.schedule_rounded,
                      color: configured
                          ? const Color(0xFF18A875)
                          : const Color(0xFFEFAF38),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('HesabPay • حساب‌پی', style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(
                          configured
                              ? tr(c.fa, 'آماده پرداخت • ${environment ?? '—'}', 'Ready • ${environment ?? '—'}')
                              : tr(c.fa, 'منتظر تنظیم امن در سرور', 'Waiting for secure server configuration'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF607487)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(c.fa, 'مبلغ شارژ کیف پول', 'Wallet top-up amount'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr(c.fa, 'مبلغ به افغانی', 'Amount in AFN'),
                      suffixText: 'AFN',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [100, 500, 1000, 5000]
                        .map(
                          (value) => OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => amount.text = '$value'),
                            child: Text('$value AFN'),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  PrimaryButton(
                    label: busy
                        ? tr(c.fa, 'درحال ایجاد پرداخت…', 'Creating payment…')
                        : configured
                            ? tr(c.fa, 'پرداخت با حساب‌پی', 'Pay with HesabPay')
                            : tr(c.fa, 'درگاه هنوز فعال نیست', 'Gateway not active yet'),
                    onPressed: configured && !busy ? startPayment : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD4EBFA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, color: Color(0xFF0D78C8)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tr(
                        c.fa,
                        'بازگشت از صفحه پرداخت به‌تنهایی موجودی را تغییر نمی‌دهد. کیف پول فقط بعد از تأیید امضای Webhook در Backend و تطبیق دقیق مبلغ شارژ می‌شود.',
                        'Returning from checkout never credits the wallet by itself. Balance changes only after the backend verifies the webhook signature and exact amount.',
                      ),
                      style: const TextStyle(color: Color(0xFF49657A), height: 1.5, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SectionTitle(tr(c.fa, 'پرداخت‌های اخیر', 'Recent payments')),
            if (recent.isEmpty)
              EmptyCard(
                icon: Icons.payments_outlined,
                title: tr(c.fa, 'هنوز پرداختی ثبت نشده', 'No payments yet'),
                subtitle: tr(c.fa, 'تلاش‌های پرداخت و وضعیت تأییدشده آن‌ها اینجا نمایش داده می‌شود.', 'Payment attempts and their verified status will appear here.'),
              )
            else
              ...recent.map(
                (payment) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.money(payment.amountAfn, showBase: true),
                                style: const TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: statusColor(payment.status).withValues(alpha: .10),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                statusLabel(payment.status),
                                style: TextStyle(
                                  color: statusColor(payment.status),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '${payment.gateway} • ${payment.createdAt.toLocal().toString().substring(0, 16)} • #${payment.id.substring(0, 8)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF607487)),
                        ),
                        if (payment.status == 'PAID' && payment.verifiedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr(c.fa, 'تأیید سرور انجام شده و کیف پول شارژ شده است.', 'Server verified; wallet credit completed.'),
                            style: const TextStyle(fontSize: 11, color: Color(0xFF18A875)),
                          ),
                        ],
                        if (payment.failureReason?.trim().isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            payment.failureReason!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFFE65454)),
                          ),
                        ],
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

'''
text = text[:start] + replacement + text[end:]
app.write_text(text)
