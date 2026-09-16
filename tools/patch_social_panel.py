from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise SystemExit(f'Anchor not found: {label}')
    return text.replace(old, new, 1)

# Prisma schema additions
schema_path = Path('backend/prisma/schema.prisma')
schema = schema_path.read_text()
schema = replace_once(
    schema,
    '  basePriceAfn   BigInt?\n  minQty         Int?\n',
    '  basePriceAfn   BigInt?\n  priceUnit      Int             @default(1)\n  minQty         Int?\n  maxQty         Int?\n  socialPlatform String?\n  socialGroup    String?\n  estimatedMinMinutes Int?\n  estimatedMaxMinutes Int?\n  refillDays     Int?\n',
    'service social fields',
)
# remove duplicate maxQty introduced by replacement if present
schema = schema.replace('  refillDays     Int?\n  maxQty         Int?\n  metadata', '  refillDays     Int?\n  metadata', 1)
schema = replace_once(
    schema,
    '  markupPercent       Decimal? @db.Decimal(10, 2)\n  metadata            Json?\n',
    '  markupPercent       Decimal? @db.Decimal(10, 2)\n  providerName        String?\n  providerType        String?\n  providerCategory    String?\n  providerRate        Decimal? @db.Decimal(20, 8)\n  providerCurrency    String?\n  providerMinQty      Int?\n  providerMaxQty      Int?\n  providerRefill      Boolean  @default(false)\n  providerCancel      Boolean  @default(false)\n  lastSyncedAt        DateTime?\n  metadata            Json?\n',
    'route provider fields',
)
schema = replace_once(
    schema,
    '  providerOrderId      String?\n  input                Json?\n',
    '  providerOrderId      String?\n  clientRequestId      String?         @unique\n  input                Json?\n',
    'order client request id',
)
schema = replace_once(
    schema,
    '  provider Provider? @relation(fields: [providerId], references: [id], onDelete: SetNull)\n\n  @@index([userId, createdAt])\n',
    '  provider Provider? @relation(fields: [providerId], references: [id], onDelete: SetNull)\n  actions  OrderActionLog[]\n\n  @@index([userId, createdAt])\n',
    'order actions relation',
)
if 'model OrderActionLog {' not in schema:
    anchor = 'model PaymentTransaction {'
    model = '''model OrderActionLog {\n  id                String   @id @default(uuid())\n  orderId           String\n  action            String\n  status            String\n  providerReference String?\n  response          Json?\n  createdAt         DateTime @default(now())\n  updatedAt         DateTime @updatedAt\n\n  order Order @relation(fields: [orderId], references: [id], onDelete: Cascade)\n\n  @@index([orderId, createdAt])\n  @@index([action, status])\n}\n\n'''
    if anchor not in schema:
        raise SystemExit('Anchor not found: PaymentTransaction model')
    schema = schema.replace(anchor, model + anchor, 1)
schema_path.write_text(schema)

# Backend registration
index_path = Path('backend/src/index.ts')
index = index_path.read_text()
index = replace_once(
    index,
    "import { registerAdminCsrfGuard } from './adminSecurity.js';\n",
    "import { registerAdminCsrfGuard } from './adminSecurity.js';\nimport { registerSocialRoutes } from './socialRoutes.js';\n",
    'social import',
)
index = replace_once(
    index,
    'registerHesabPayWebhookRoutes(app, prisma, authenticate);\n',
    'registerHesabPayWebhookRoutes(app, prisma, authenticate);\nregisterSocialRoutes(app, prisma, authenticate, adminWebUser);\n',
    'social route registration',
)
index_path.write_text(index)

# Add admin navigation entry
admin_path = Path('backend/src/adminExtended.ts')
admin = admin_path.read_text()
admin = replace_once(
    admin,
    "    ['/admin/providers', 'Provider و API', 'providers'],\n",
    "    ['/admin/providers', 'Provider و API', 'providers'],\n    ['/admin/social-services', 'پنل شبکه‌های اجتماعی', 'social'],\n",
    'admin social nav',
)
admin_path.write_text(admin)

# HesabPay should default to real production environment for VELIXEO
payment_path = Path('backend/src/paymentRoutes.ts')
payment = payment_path.read_text()
payment = payment.replace("HESABPAY_ENVIRONMENT: z.enum(['sandbox', 'production']).default('sandbox')", "HESABPAY_ENVIRONMENT: z.enum(['sandbox', 'production']).default('production')")
payment_path.write_text(payment)

env_path = Path('backend/.env.example')
env = env_path.read_text()
env = env.replace('# HesabPay wallet top-up gateway. Keep sandbox until an end-to-end sandbox payment is verified.\nHESABPAY_ENVIRONMENT=sandbox', '# HesabPay wallet top-up gateway. VELIXEO uses the real production gateway; credentials stay server-side.\nHESABPAY_ENVIRONMENT=production')
env = env.replace('# Optional override; when blank the backend selects the official sandbox/production host.', '# Optional override; when blank the backend selects the official host for HESABPAY_ENVIRONMENT.')
env_path.write_text(env)

# Flutter API client
api_path = Path('lib/core/api_service.dart')
api = api_path.read_text()
api = replace_once(
    api,
    "import 'models.dart';\n",
    "import 'models.dart';\nimport '../social/social_models.dart';\n",
    'social models import',
)
if 'Future<SocialCatalog> socialCatalog()' not in api:
    methods = r'''

  Future<SocialCatalog> socialCatalog() async {
    final response = await _send('GET', '/api/v1/social/catalog');
    if (response.statusCode != 200) _throwResponse(response);
    return SocialCatalog.fromJson(_decodeObject(response));
  }

  Future<List<SocialOrder>> socialOrders() async {
    final response = await _send('GET', '/api/v1/social/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows
        .map((item) => SocialOrder.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<SocialQuote> socialQuote({
    required String serviceId,
    required Map<String, dynamic> parameters,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/social/quote',
      body: {'serviceId': serviceId, 'parameters': parameters},
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return SocialQuote.fromJson(_decodeObject(response));
  }

  Future<SocialCreateOrderResult> createSocialOrder({
    required String serviceId,
    required String clientRequestId,
    required Map<String, dynamic> parameters,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders',
      body: {
        'serviceId': serviceId,
        'clientRequestId': clientRequestId,
        'parameters': parameters,
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return SocialCreateOrderResult.fromJson(_decodeObject(response));
  }

  Future<SocialOrder> refreshSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/refresh',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
    return SocialOrder.fromJson(
      Map<String, dynamic>.from(_decodeObject(response)['order'] as Map),
    );
  }

  Future<void> refillSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/refill',
      auth: true,
    );
    if (![200, 201].contains(response.statusCode)) _throwResponse(response);
  }

  Future<void> cancelSocialOrder(String orderId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/cancel',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }

  Future<void> refreshSocialAction(String orderId, String actionId) async {
    final response = await _send(
      'POST',
      '/api/v1/social/orders/$orderId/actions/$actionId/refresh',
      auth: true,
    );
    if (response.statusCode != 200) _throwResponse(response);
  }
'''
    pos = api.rfind('\n}')
    if pos < 0:
        raise SystemExit('ApiService closing brace not found')
    api = api[:pos] + methods + api[pos:]
api_path.write_text(api)

# Flutter app wiring
app_path = Path('lib/app.dart')
app = app_path.read_text()
app = replace_once(
    app,
    "import 'core/models.dart';\n",
    "import 'core/models.dart';\nimport 'social/social_panel.dart';\n",
    'social panel import',
)
app = app.replace('class AppController extends ChangeNotifier {', 'class AppController extends ChangeNotifier implements SocialPanelHost {', 1)
app = replace_once(
    app,
    '                    builder: (_) => ServicePreviewPage(controller: c, service: services[i]),\n',
    "                    builder: (_) => services[i].en == 'Social Media'\n                        ? SocialPanelPage(host: c)\n                        : ServicePreviewPage(controller: c, service: services[i]),\n",
    'home social navigation',
)
app = replace_once(
    app,
    '                      MaterialPageRoute(builder: (_) => ServicePreviewPage(controller: c, service: service)),\n',
    "                      MaterialPageRoute(builder: (_) => service.en == 'Social Media'\n                          ? SocialPanelPage(host: c)\n                          : ServicePreviewPage(controller: c, service: service)),\n",
    'fallback social navigation',
)
old_dynamic = '''            ] else ...[\n              ...c.catalogServices.map((service) {\n'''
new_dynamic = '''            ] else ...[\n              if (c.catalogServices.any((service) => service.category == 'SOCIAL'))\n                Padding(\n                  padding: const EdgeInsets.only(bottom: 11),\n                  child: SoftCard(\n                    onTap: () => Navigator.push(\n                      context,\n                      MaterialPageRoute(builder: (_) => SocialPanelPage(host: c)),\n                    ),\n                    child: Row(\n                      children: [\n                        Container(\n                          width: 50,\n                          height: 50,\n                          decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: .1), borderRadius: BorderRadius.circular(16)),\n                          child: const Icon(Icons.trending_up_rounded, color: Color(0xFF8B5CF6)),\n                        ),\n                        const SizedBox(width: 14),\n                        Expanded(\n                          child: Column(\n                            crossAxisAlignment: CrossAxisAlignment.start,\n                            children: [\n                              Text(tr(c.fa, 'شبکه‌های اجتماعی', 'Social Media'), style: const TextStyle(fontWeight: FontWeight.w900)),\n                              const SizedBox(height: 3),\n                              Text(tr(c.fa, 'سفارش جدید، پیگیری، جبران و لغو', 'Order, track, refill and cancel'), style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),\n                            ],\n                          ),\n                        ),\n                        const Icon(Icons.chevron_right),\n                      ],\n                    ),\n                  ),\n                ),\n              ...c.catalogServices.where((service) => service.category != 'SOCIAL').map((service) {\n'''
app = replace_once(app, old_dynamic, new_dynamic, 'group social services')
app_path.write_text(app)

# Version bump for the expanded social-media milestone
pubspec_path = Path('pubspec.yaml')
pubspec = pubspec_path.read_text()
pubspec = pubspec.replace('version: 0.4.0+4', 'version: 0.5.0+5')
pubspec_path.write_text(pubspec)
