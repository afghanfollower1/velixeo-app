from pathlib import Path


def replace_once(path: str, old: str, new: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if old not in text:
        raise SystemExit(f'pattern not found in {path}: {old[:100]!r}')
    if text.count(old) != 1:
        raise SystemExit(f'pattern not unique in {path}: {text.count(old)} matches')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


# Fix strict OrderStatus typing caught by CI.
replace_once(
    'backend/src/virtualNumberRoutes.ts',
    "    if ([OrderStatus.COMPLETED, OrderStatus.CANCELLED, OrderStatus.REFUNDED].includes(order.status)) {",
    "    if (order.status === OrderStatus.COMPLETED || order.status === OrderStatus.CANCELLED || order.status === OrderStatus.REFUNDED) {",
)

# Register the virtual-number module in the API.
replace_once(
    'backend/src/index.ts',
    "import { registerSocialRoutes } from './socialRoutes.js';\n",
    "import { registerSocialRoutes } from './socialRoutes.js';\nimport { registerVirtualNumberRoutes } from './virtualNumberRoutes.js';\n",
)
replace_once(
    'backend/src/index.ts',
    "registerSocialRoutes(app, prisma, authenticate, adminWebUser);\n",
    "registerSocialRoutes(app, prisma, authenticate, adminWebUser);\nregisterVirtualNumberRoutes(app, prisma, authenticate, adminWebUser);\n",
)

# Add a first-class admin navigation entry.
replace_once(
    'backend/src/adminExtended.ts',
    "    ['/admin/social-services', 'پنل شبکه‌های اجتماعی', 'social'],\n",
    "    ['/admin/social-services', 'پنل شبکه‌های اجتماعی', 'social'],\n    ['/admin/virtual-numbers', 'شماره مجازی و SMS', 'virtual'],\n",
)

# Wire new client models and API calls.
replace_once(
    'lib/core/api_service.dart',
    "import '../social/social_models.dart';\n",
    "import '../social/social_models.dart';\nimport '../support/support_models.dart';\nimport '../virtual_numbers/virtual_number_models.dart';\n",
)

api_path = Path('lib/core/api_service.dart')
api = api_path.read_text(encoding='utf-8')
insert_at = api.rfind('\n}')
if insert_at < 0:
    raise SystemExit('ApiService class ending not found')
api_methods = r'''

  Future<VirtualCatalog> virtualNumberCatalog() async {
    final response = await _send('GET', '/api/v1/virtual-numbers/catalog');
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualCatalog.fromJson(_decodeObject(response));
  }

  Future<VirtualOffers> virtualNumberOffers({required String serviceId, required String country}) async {
    final query = Uri(queryParameters: {'serviceId': serviceId, 'country': country}).query;
    final response = await _send('GET', '/api/v1/virtual-numbers/offers?$query');
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOffers.fromJson(_decodeObject(response));
  }

  Future<List<VirtualOrder>> virtualNumberOrders() async {
    final response = await _send('GET', '/api/v1/virtual-numbers/orders', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['orders'] as List<dynamic>?) ?? const [];
    return rows.map((item) => VirtualOrder.fromJson(Map<String, dynamic>.from(item as Map))).toList(growable: false);
  }

  Future<VirtualOrder> createVirtualNumberOrder({
    required String serviceId,
    required String country,
    required String operatorName,
    required String mode,
    required String clientRequestId,
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/virtual-numbers/orders',
      body: {
        'serviceId': serviceId,
        'country': country,
        'operator': operatorName,
        'mode': mode,
        'clientRequestId': clientRequestId,
      },
      auth: true,
    );
    if (![200, 201, 202].contains(response.statusCode)) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> checkVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/check', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> cancelVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/cancel', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<VirtualOrder> finishVirtualNumberOrder(String id) async {
    final response = await _send('POST', '/api/v1/virtual-numbers/orders/$id/finish', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    return VirtualOrder.fromJson(Map<String, dynamic>.from(_decodeObject(response)['order'] as Map));
  }

  Future<List<SupportTicket>> supportTickets() async {
    final response = await _send('GET', '/api/v1/support/tickets', auth: true);
    if (response.statusCode != 200) _throwResponse(response);
    final rows = (_decodeObject(response)['tickets'] as List<dynamic>?) ?? const [];
    return rows.map((item) => SupportTicket.fromJson(Map<String, dynamic>.from(item as Map))).toList(growable: false);
  }

  Future<SupportTicket> createSupportTicket({required String subject, required String message}) async {
    final response = await _send(
      'POST',
      '/api/v1/support/tickets',
      body: {'subject': subject.trim(), 'message': message.trim()},
      auth: true,
    );
    if (response.statusCode != 201) _throwResponse(response);
    return SupportTicket.fromJson(Map<String, dynamic>.from(_decodeObject(response)['ticket'] as Map));
  }

  Future<SupportMessage> replySupportTicket(String ticketId, String message) async {
    final response = await _send(
      'POST',
      '/api/v1/support/tickets/$ticketId/messages',
      body: {'message': message.trim()},
      auth: true,
    );
    if (response.statusCode != 201) _throwResponse(response);
    return SupportMessage.fromJson(Map<String, dynamic>.from(_decodeObject(response)['message'] as Map));
  }
'''
if 'Future<VirtualCatalog> virtualNumberCatalog()' not in api:
    api = api[:insert_at] + api_methods + api[insert_at:]
api_path.write_text(api, encoding='utf-8')

# Flutter app: imports and host interfaces.
replace_once(
    'lib/app.dart',
    "import 'social/social_panel.dart';\n",
    "import 'social/social_panel.dart';\nimport 'support/support_page.dart';\nimport 'virtual_numbers/virtual_number_panel.dart';\n",
)
replace_once(
    'lib/app.dart',
    'class AppController extends ChangeNotifier implements SocialPanelHost {',
    'class AppController extends ChangeNotifier implements SocialPanelHost, VirtualNumberPanelHost, SupportPanelHost {',
)

# Centralize category destinations so Home, Services, search and banners behave consistently.
replace_once(
    'lib/app.dart',
    'class MainShell extends StatefulWidget {',
    r'''Widget _serviceDestination(AppController c, ServiceItem service) {
  if (service.en == 'Social Media') return SocialPanelPage(host: c);
  if (service.en == 'Virtual Numbers') return VirtualNumberPanelPage(host: c);
  return ServicePreviewPage(controller: c, service: service);
}

Widget _catalogDestination(AppController c, CatalogService service) {
  if (service.category == 'SOCIAL') return SocialPanelPage(host: c);
  if (service.category == 'VIRTUAL_NUMBER') return VirtualNumberPanelPage(host: c);
  return CatalogServicePage(controller: c, service: service);
}

Future<void> _openServiceSearch(BuildContext context, AppController c) async {
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ServiceSearchPage(controller: c)));
}

class MainShell extends StatefulWidget {''',
)

# Home/static category routing.
old_home_route = r'''                    builder: (_) => services[i].en == 'Social Media'
                        ? SocialPanelPage(host: c)
                        : ServicePreviewPage(controller: c, service: services[i]),'''
replace_once('lib/app.dart', old_home_route, "                    builder: (_) => _serviceDestination(c, services[i]),")

# Services fallback category routing.
old_fallback_route = r'''                      MaterialPageRoute(builder: (_) => service.en == 'Social Media'
                          ? SocialPanelPage(host: c)
                          : ServicePreviewPage(controller: c, service: service)),'''
replace_once('lib/app.dart', old_fallback_route, "                      MaterialPageRoute(builder: (_) => _serviceDestination(c, service)),")

# Live catalog routing.
replace_once(
    'lib/app.dart',
    "                      MaterialPageRoute(builder: (_) => CatalogServicePage(controller: c, service: service)),",
    "                      MaterialPageRoute(builder: (_) => _catalogDestination(c, service)),",
)

# Make both search fields open a real searchable screen.
replace_once(
    'lib/app.dart',
    r'''            TextField(
              readOnly: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(c.fa, 'چه خدمتی نیاز دارید؟', 'What service do you need?'),
              ),
            ),''',
    r'''            TextField(
              readOnly: true,
              onTap: () => _openServiceSearch(context, c),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: tr(c.fa, 'چه خدمتی نیاز دارید؟', 'What service do you need?'),
                suffixIcon: const Icon(Icons.arrow_forward_rounded),
              ),
            ),''',
)
replace_once(
    'lib/app.dart',
    r'''            TextField(
              readOnly: true,
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'جستجوی سرویس...', 'Search services...')),
            ),''',
    r'''            TextField(
              readOnly: true,
              onTap: () => _openServiceSearch(context, c),
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'جستجوی سرویس...', 'Search services...'), suffixIcon: const Icon(Icons.arrow_forward_rounded)),
            ),''',
)

# Add real search UI before ServicesPage.
replace_once(
    'lib/app.dart',
    'class ServicesPage extends StatelessWidget {',
    r'''class ServiceSearchPage extends StatefulWidget {
  const ServiceSearchPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<ServiceSearchPage> createState() => _ServiceSearchPageState();
}

class _ServiceSearchPageState extends State<ServiceSearchPage> {
  final query = TextEditingController();

  @override
  void initState() {
    super.initState();
    query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  bool matches(String value) => value.toLowerCase().contains(query.text.trim().toLowerCase());

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = query.text.trim();
    final categories = HomePage.services.where((item) => q.isEmpty || matches(item.fa) || matches(item.en)).toList(growable: false);
    final live = c.catalogServices.where((item) => q.isEmpty || matches(item.titleFa) || matches(item.titleEn) || matches(item.slug) || matches(item.category)).toList(growable: false);
    return Scaffold(
      appBar: AppBar(title: Text(tr(c.fa, 'جستجوی خدمات', 'Search services'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: query,
            autofocus: true,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr(c.fa, 'نام سرویس، شبکه یا دسته...', 'Service, platform or category...'), suffixIcon: q.isEmpty ? null : IconButton(onPressed: query.clear, icon: const Icon(Icons.close))),
          ),
          const SizedBox(height: 16),
          if (categories.isEmpty && live.isEmpty)
            EmptyCard(icon: Icons.search_off_rounded, title: tr(c.fa, 'نتیجه‌ای پیدا نشد', 'No results found'), subtitle: tr(c.fa, 'عبارت دیگری جستجو کنید.', 'Try another search.')),
          ...categories.map((service) => Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: SoftCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _serviceDestination(c, service))),
                  child: Row(children: [
                    CircleAvatar(backgroundColor: service.color.withValues(alpha: .10), child: Icon(service.icon, color: service.color)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(c.fa ? service.fa : service.en, style: const TextStyle(fontWeight: FontWeight.w900))),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              )),
          if (live.isNotEmpty) ...[
            const SizedBox(height: 7),
            SectionTitle(tr(c.fa, 'سرویس‌های فعال', 'Live services')),
            ...live.map((service) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: SoftCard(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _catalogDestination(c, service))),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: catalogColor(service.category).withValues(alpha: .10), child: Icon(catalogIcon(service.category), color: catalogColor(service.category))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c.fa ? service.titleFa : service.titleEn, style: const TextStyle(fontWeight: FontWeight.w900)),
                        Text(service.category, style: const TextStyle(fontSize: 10, color: Color(0xFF607487))),
                      ])),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

class ServicesPage extends StatelessWidget {''',
)

# Add Support to Profile.
replace_once(
    'lib/app.dart',
    r'''          SettingsTile(
            icon: Icons.cloud_done_outlined,
            title: tr(c.fa, 'وضعیت سرور', 'Server status'),''',
    r'''          SettingsTile(
            icon: Icons.support_agent_rounded,
            title: tr(c.fa, 'پشتیبانی و تیکت', 'Support & tickets'),
            value: '',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: c))),
          ),
          SettingsTile(
            icon: Icons.cloud_done_outlined,
            title: tr(c.fa, 'وضعیت سرور', 'Server status'),''',
)

# Replace banner with clickable CTA/deep-link implementation.
app_path = Path('lib/app.dart')
app = app_path.read_text(encoding='utf-8')
start = app.index('class RemoteBannerCard extends StatelessWidget {')
end = app.index('class WalletPage extends StatelessWidget {', start)
new_banner = r'''class RemoteBannerCard extends StatelessWidget {
  const RemoteBannerCard({super.key, required this.controller, required this.banner});
  final AppController controller;
  final AppBanner banner;

  Future<void> openAction(BuildContext context) async {
    final raw = banner.actionUrl?.trim();
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    if (uri.scheme == 'velixeo') {
      final target = uri.host.isNotEmpty ? uri.host : uri.path.replaceFirst('/', '');
      if (target == 'social') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SocialPanelPage(host: controller)));
      } else if (target == 'virtual-numbers' || target == 'virtual') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => VirtualNumberPanelPage(host: controller)));
      } else if (target == 'wallet') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => AddFundsPage(controller: controller)));
      } else if (target == 'support') {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportPage(host: controller)));
      } else if (target == 'services') {
        await _openServiceSearch(context, controller);
      }
      return;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = controller.fa;
    final title = fa ? banner.titleFa : banner.titleEn;
    final subtitle = fa ? banner.subtitleFa : banner.subtitleEn;
    final action = fa ? banner.actionLabelFa : banner.actionLabelEn;
    final clickable = banner.actionUrl?.trim().isNotEmpty == true;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: clickable ? () => openAction(context) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          height: 150,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                banner.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0D78C8), Color(0xFF31A8FF)])),
                ),
              ),
              Container(color: Colors.black.withValues(alpha: .24)),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (title?.trim().isNotEmpty == true) Text(title!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
                    if (subtitle?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                    if (action?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(action!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                        if (clickable) const Padding(padding: EdgeInsetsDirectional.only(start: 5), child: Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 15)),
                      ]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

'''
app = app[:start] + new_banner + app[end:]
app_path.write_text(app, encoding='utf-8')

print('VELIXEO live panels integration patched successfully')
