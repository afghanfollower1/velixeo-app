import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:country_picker/country_picker.dart';

import '../core/api_service.dart';
import '../core/models.dart';
import 'virtual_number_models.dart';

String _normalizeCountryKey(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

final CountryService _countryService = CountryService();
final List<Country> _allCountries = _countryService.getAll();
final Map<String, Country> _countriesByNormalizedName = {
  for (final country in _allCountries) _normalizeCountryKey(country.name): country,
};

const Map<String, String> _fiveSimCountryAliases = {
  'england': 'GB',
  'uk': 'GB',
  'greatbritain': 'GB',
  'usa': 'US',
  'unitedstatesofamerica': 'US',
  'russia': 'RU',
  'southkorea': 'KR',
  'northkorea': 'KP',
  'czech': 'CZ',
  'czechrepublic': 'CZ',
  'ivorycoast': 'CI',
  'cotedivoire': 'CI',
  'moldova': 'MD',
  'tanzania': 'TZ',
  'bolivia': 'BO',
  'venezuela': 'VE',
  'laos': 'LA',
  'brunei': 'BN',
  'capeverde': 'CV',
  'easttimor': 'TL',
  'macedonia': 'MK',
  'palestine': 'PS',
  'syria': 'SY',
  'iran': 'IR',
  'vietnam': 'VN',
  'kosovo': 'XK',
};

Country? _resolveCountry(VirtualCountry item) {
  final iso = item.iso.trim().toUpperCase();
  if (iso.length == 2) {
    final byCode = _countryService.findByCode(iso);
    if (byCode != null) return byCode;
  }
  final direct = _countriesByNormalizedName[_normalizeCountryKey(item.name)] ??
      _countriesByNormalizedName[_normalizeCountryKey(item.code)];
  if (direct != null) return direct;
  final alias = _fiveSimCountryAliases[_normalizeCountryKey(item.name)] ??
      _fiveSimCountryAliases[_normalizeCountryKey(item.code)];
  return alias == null ? null : _countryService.findByCode(alias);
}

String _countryFlag(VirtualCountry item) {
  final resolved = _resolveCountry(item);
  if (resolved != null) return resolved.flagEmoji;
  final raw = item.flag.trim();
  return raw.isNotEmpty && raw != '🌐' ? raw : '🌐';
}

String _countryDisplayName(VirtualCountry item) {
  final direct = _countriesByNormalizedName[_normalizeCountryKey(item.name)] ??
      _countriesByNormalizedName[_normalizeCountryKey(item.code)];
  if (direct != null) return direct.name;
  final raw = item.name.trim().isNotEmpty ? item.name.trim() : item.code.trim();
  if (raw.isEmpty) return 'Unknown';
  return raw
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part.length == 1
          ? part.toUpperCase()
          : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String _orderCountryName(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return '—';
  final direct = _countriesByNormalizedName[_normalizeCountryKey(value)];
  if (direct != null) return direct.name;
  return value
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => part.length == 1
          ? part.toUpperCase()
          : '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

AppBanner? _pickVirtualBanner(List<AppBanner> rows) {
  for (final banner in rows) {
    final target = banner.actionUrl?.trim().toLowerCase();
    if (banner.placement == 'SERVICES_TOP' &&
        (target == 'velixeo://virtual-numbers' || target == 'velixeo://virtual')) {
      return banner;
    }
  }
  return null;
}

abstract class VirtualNumberPanelHost {
  ApiService get api;
  bool get fa;
  int get balanceAfn;
  List<AppBanner> get banners;
  String money(int amountAfn, {bool showBase});
  Future<void> refreshBalanceOnly();
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
  bool loadingCountries = false;
  bool loadingOffers = false;
  bool buying = false;
  bool polling = false;
  String orderFilter = 'ACTIVE';
  AppBanner? virtualBanner;
  String? error;
  Timer? tickTimer;
  Timer? pollTimer;

  VirtualNumberPanelHost get host => widget.host;
  bool get fa => host.fa;
  String t(String faText, String enText) => fa ? faText : enText;

  @override
  void initState() {
    super.initState();
    virtualBanner = _pickVirtualBanner(host.banners);
    load();
    unawaited(loadVirtualBanner());
    tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && tab == 2 && orders.any(isActive)) setState(() {});
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
    final previousServiceId = selectedService?.id;
    final previousCountryCode = selectedCountry?.code;
    try {
      final results = await Future.wait([
        host.api.virtualNumberCatalog(),
        host.api.virtualNumberOrders(),
      ]);
      catalog = results[0] as VirtualCatalog;
      orders = results[1] as List<VirtualOrder>;
      if (catalog.services.isNotEmpty) {
        final service = catalog.services
            .where((item) => item.id == previousServiceId)
            .firstOrNull ?? sortedServices.first;
        selectedService = service;
        selectedCountry = null;
        offers = null;
        if (mounted) setState(() => loading = false);
        unawaited(loadCountries(service, preferredCountryCode: previousCountryCode));
        return;
      }
      selectedService = null;
      selectedCountry = null;
      offers = null;
    } on ApiException catch (e) {
      error = e.code;
    } catch (_) {
      error = 'network_error';
    } finally {
      if (mounted && loading) setState(() => loading = false);
    }
  }

  Future<void> loadVirtualBanner() async {
    try {
      final rows = await host.api.banners();
      if (!mounted) return;
      final next = _pickVirtualBanner(rows);
      if (next?.id != virtualBanner?.id ||
          next?.imageUrl != virtualBanner?.imageUrl ||
          next?.titleEn != virtualBanner?.titleEn ||
          next?.subtitleEn != virtualBanner?.subtitleEn) {
        setState(() => virtualBanner = next);
      }
    } catch (_) {
      // The default informational hero stays visible when the remote banner is unavailable.
    }
  }

  Future<void> loadCountries(
    VirtualService service, {
    String? preferredCountryCode,
  }) async {
    if (mounted) {
      setState(() {
        loadingCountries = true;
        selectedCountry = null;
        offers = null;
      });
    }
    try {
      final countries = await host.api.virtualNumberCountries(serviceId: service.id);
      if (!mounted || selectedService?.id != service.id) return;
      final hydrated = service.copyWithCountries(countries);
      final sorted = sortedCountries(hydrated);
      final preferred = sorted
          .where((item) => item.code == preferredCountryCode)
          .firstOrNull;
      setState(() {
        selectedService = hydrated;
        selectedCountry = preferred ?? sorted.firstOrNull;
      });
      unawaited(loadOffers());
    } on ApiException catch (e) {
      if (mounted && selectedService?.id == service.id) {
        setState(() {
          error = e.code;
          selectedService = service.copyWithCountries(const []);
          selectedCountry = null;
          offers = null;
        });
      }
    } catch (_) {
      if (mounted && selectedService?.id == service.id) {
        setState(() {
          error = 'network_error';
          selectedService = service.copyWithCountries(const []);
          selectedCountry = null;
          offers = null;
        });
      }
    } finally {
      if (mounted && selectedService?.id == service.id) {
        setState(() => loadingCountries = false);
      }
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

  Future<void> changeService(
    VirtualService? service, {
    bool loadCountryData=true,
  }) async {
    if (service == null) return;
    setState(() {
      selectedService = service;
      selectedCountry = null;
      offers = null;
      error = null;
    });
    if(loadCountryData)await loadCountries(service);
  }

  void changeCountry(VirtualCountry? country) {
    if (country == null) return;
    setState(() {
      selectedCountry = country;
      offers = null;
    });
    loadOffers();
  }

  Future<void> buy({
    required String operatorName,
    required String mode,
    VirtualCountry? countryOverride,
  }) async {
    final service = selectedService;
    final country = countryOverride ?? selectedCountry;
    if (service == null || country == null || buying) return;

    setState(() => buying = true);
    try {
      final VirtualOffers liveOffers;
      if (selectedCountry?.code == country.code && offers != null) {
        liveOffers = offers!;
      } else {
        liveOffers = await host.api.virtualNumberOffers(
          serviceId: service.id,
          country: country.code,
        );
      }
      final preview = mode == 'LOW_PRICE'
          ? liveOffers.lowPrice
          : mode == 'ANY'
              ? liveOffers.anyOperator
              : operatorName == 'any'
                  ? liveOffers.bestRate
                  : liveOffers.operators.where((item) => item.operatorName == operatorName).firstOrNull;

      if (preview == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('برای این انتخاب شماره موجود نیست.', 'No live number is available for this selection.'))),
          );
        }
        return;
      }
      if (preview.priceAfn > host.balanceAfn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('موجودی کیف پول کافی نیست.', 'Your wallet balance is not enough.'))),
          );
        }
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('تأیید خرید شماره', 'Confirm number purchase')),
          content: Text(
            '${t('قیمت', 'Price')}: ${host.money(preview.priceAfn, showBase: true)}\n'
            '${t('کشور', 'Country')}: ${_countryFlag(country)} ${_countryDisplayName(country)}\n'
            '${t('اپراتور', 'Operator')}: ${operatorName == 'any' ? t('هوشمند', 'Smart') : operatorName}'
            '${preview.deliveryPercent == null ? '' : '\n${t('نرخ تحویل', 'Delivery rate')}: ${preview.deliveryPercent!.toStringAsFixed(1)}%'}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('لغو', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t('خرید', 'Buy'))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final order = await host.api.createVirtualNumberOrder(
        serviceId: service.id,
        country: country.code,
        operatorName: operatorName,
        mode: mode,
        clientRequestId: newRequestId(),
      );
      orders = [order, ...orders.where((item) => item.id != order.id)];
      await host.refreshBalanceOnly();
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

  Future<void> smartBuy() async {
    final service=selectedService;
    if(service==null||buying)return;
    setState(()=>buying=true);
    try{
      final order=await host.api.createVirtualNumberOrder(
        serviceId:service.id,
        country:'any',
        operatorName:'any',
        mode:'SMART',
        clientRequestId:newRequestId(),
      );
      orders=[order,...orders.where((item)=>item.id!=order.id)];
      await host.refreshBalanceOnly();
      if(!mounted)return;
      setState(()=>tab=2);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(t('کشور و اپراتور به‌صورت هوشمند انتخاب شد و شماره با موفقیت خریداری شد.','The best country and operator were selected automatically and the number was purchased.'))),
      );
    }on ApiException catch(e){
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(errorLabel(e.code))));
    }catch(_){
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(errorLabel('network_error'))));
    }finally{
      if(mounted)setState(()=>buying=false);
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
      final updates = await Future.wait(
        active.map((item) async {
          try {
            return await host.api.checkVirtualNumberOrder(item.id);
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted) return;
      final next=[...orders];
      for(final updated in updates.whereType<VirtualOrder>()){
        final index=next.indexWhere((item)=>item.id==updated.id);
        if(index>=0) next[index]=updated; else next.insert(0,updated);
      }
      setState(()=>orders=next);
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
      await host.refreshBalanceOnly();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    }
  }

  Future<void> finishOrder(VirtualOrder order) async {
    try {
      replaceOrder(await host.api.finishVirtualNumberOrder(order.id));
      await host.refreshBalanceOnly();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorLabel(e.code))));
    }
  }

  String serviceName(VirtualService service) => fa ? service.titleFa : service.titleEn;

  List<VirtualService> get sortedServices {
    final rows = [...catalog.services];
    rows.sort((a,b) {
      final order=a.sortOrder.compareTo(b.sortOrder);
      if(order!=0)return order;
      return serviceName(a).toLowerCase().compareTo(serviceName(b).toLowerCase());
    });
    return rows;
  }


  List<VirtualCountry> sortedCountries(VirtualService service) {
    final rows=[...service.countries];
    rows.sort((a,b)=>_countryDisplayName(a).toLowerCase().compareTo(_countryDisplayName(b).toLowerCase()));
    return rows;
  }

  Future<void> chooseService() async {
    final picked=await showModalBottomSheet<VirtualService>(
      context:context,
      isScrollControlled:true,
      useSafeArea:true,
      builder:(_)=>_SearchPickerSheet<VirtualService>(
        title:t('انتخاب سرویس','Choose service'),
        searchHint:t('جستجوی سرویس…','Search services…'),
        items:sortedServices,
        searchText:(item)=>'${serviceName(item)} ${item.slug}',
        itemBuilder:(item)=>Row(children:[
          _BrandBadge(service:item,size:42),
          const SizedBox(width:12),
          Expanded(child:Text(serviceName(item),style:const TextStyle(fontWeight:FontWeight.w800))),
          if(item.featured)const Icon(Icons.star_rounded,color:Color(0xFFFFB020),size:18),
        ]),
      ),
    );
    if(picked!=null){
      final smart=tab==1;
      await changeService(picked,loadCountryData:!smart);
      if(smart&&mounted)await smartBuy();
    }
  }

  Future<void> chooseCountry() async {
    final service=selectedService;
    if(service==null)return;
    final picked=await showModalBottomSheet<VirtualCountry>(
      context:context,
      isScrollControlled:true,
      useSafeArea:true,
      builder:(_)=>_SearchPickerSheet<VirtualCountry>(
        title:t('انتخاب کشور','Choose country'),
        searchHint:t('جستجوی کشور…','Search countries…'),
        items:sortedCountries(service),
        searchText:(item)=>'${_countryDisplayName(item)} ${item.name} ${item.code} ${item.iso}',
        itemBuilder:(item)=>Row(children:[
          Text(_countryFlag(item),style:const TextStyle(fontSize:28)),
          const SizedBox(width:12),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(_countryDisplayName(item),style:const TextStyle(fontWeight:FontWeight.w800)),
            Text('${host.money(item.minPriceAfn)} • ${item.availableCount} ${t('موجود','available')}',style:const TextStyle(fontSize:10.5,color:Color(0xFF718399))),
          ])),
          if(item.maxRate!=null)Text('${item.maxRate!.toStringAsFixed(1)}%',style:const TextStyle(fontWeight:FontWeight.w800,color:Color(0xFF18A875))),
        ]),
      ),
    );
    if(picked!=null)changeCountry(picked);
  }

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
                  virtualBanner == null
                      ? _InfoHero(fa: fa)
                      : _VirtualPromoBanner(banner: virtualBanner!, fa: fa),
                  const SizedBox(height: 14),
                  SegmentedButton<int>(
                    segments: [
                      ButtonSegment(value: 0, icon: const Icon(Icons.tune_rounded), label: Text(t('خرید دستی', 'Manual'))),
                      ButtonSegment(value: 1, icon: const Icon(Icons.auto_awesome_rounded), label: Text(t('خرید هوشمند', 'Smart Buy'))),
                      ButtonSegment(value: 2, icon: const Icon(Icons.sms_outlined), label: Text(t('شماره‌های من', 'My Numbers'))),
                    ],
                    selected: {tab},
                    onSelectionChanged: (value) {
                      final next=value.first;
                      setState(()=>tab=next);
                      if(next==0){
                        final service=selectedService;
                        if(service!=null&&service.countries.isEmpty&&!loadingCountries){
                          unawaited(loadCountries(service));
                        }
                      }
                    },
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

  Widget serviceSelector() {
    final service=selectedService;
    return InkWell(
      onTap:chooseService,
      borderRadius:BorderRadius.circular(14),
      child:InputDecorator(
        decoration:InputDecoration(
          labelText:t('سرویس','Service'),
          prefixIcon:service==null?const Icon(Icons.apps_rounded):Padding(
            padding:const EdgeInsets.all(8),
            child:_BrandBadge(service:service,size:34),
          ),
          suffixIcon:const Icon(Icons.search_rounded),
        ),
        child:Text(service==null?t('انتخاب سرویس','Choose service'):serviceName(service),overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800)),
      ),
    );
  }

  Widget countrySelector() {
    final country=selectedCountry;
    return InkWell(
      onTap:selectedService==null||loadingCountries?null:chooseCountry,
      borderRadius:BorderRadius.circular(14),
      child:InputDecorator(
        decoration:InputDecoration(
          labelText:t('کشور','Country'),
          prefixIcon:loadingCountries
              ?const Padding(
                  padding:EdgeInsets.all(14),
                  child:SizedBox.square(dimension:18,child:CircularProgressIndicator(strokeWidth:2)),
                )
              :country==null
                  ?const Icon(Icons.public_rounded)
                  :Center(widthFactor:1.8,child:Text(_countryFlag(country),style:const TextStyle(fontSize:25))),
          suffixIcon:loadingCountries?null:const Icon(Icons.search_rounded),
        ),
        child:Text(
          loadingCountries
              ?t('در حال دریافت کشورهای فعال…','Loading available countries…')
              :country==null
                  ?t('کشوری موجود نیست','No country available')
                  :'${_countryDisplayName(country)} • ${host.money(country.minPriceAfn)}',
          overflow:TextOverflow.ellipsis,
          style:const TextStyle(fontWeight:FontWeight.w800),
        ),
      ),
    );
  }

  Widget selectors() {
    if(selectedService==null)return const SizedBox.shrink();
    return Column(children:[
      serviceSelector(),
      const SizedBox(height:12),
      countrySelector(),
    ]);
  }

  Widget manualPanel() {
    final current=offers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelCard(child: selectors()),
        const SizedBox(height: 14),
        if (loadingOffers)
          const Center(child: Padding(padding: EdgeInsets.all(26), child: CircularProgressIndicator()))
        else if (current == null || current.operators.isEmpty)
          _Notice(text: t('برای این سرویس و کشور فعلاً شماره‌ای موجود نیست.', 'No number is currently available for this service and country.'))
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(t('اپراتورها / سرورها', 'Operators / servers'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              Text('${current.operators.length}', style: const TextStyle(color: Color(0xFF607487), fontWeight:FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing:7,
            runSpacing:7,
            children:[
              _SummaryPill(
                icon:Icons.savings_outlined,
                label:t('کمترین','Lowest'),
                value:host.money(current.minPriceAfn,showBase:true),
              ),
              _SummaryPill(
                icon:Icons.trending_up_rounded,
                label:t('بیشترین','Highest'),
                value:host.money(current.maxPriceAfn,showBase:true),
              ),
              if(current.bestDeliveryPercent!=null)
                _SummaryPill(
                  icon:Icons.mark_email_read_outlined,
                  label:t('بهترین SMS','Best SMS'),
                  value:'${current.bestDeliveryPercent!.toStringAsFixed(2)}%',
                ),
            ],
          ),
          const SizedBox(height: 10),
          ...current.operators.map((offer) {
            final tags=<String>[];
            if(current.lowPrice?.operatorName==offer.operatorName && current.lowPrice?.priceAfn==offer.priceAfn){
              tags.add(t('ارزان‌ترین','Cheapest'));
            }
            if(current.highPrice?.operatorName==offer.operatorName && current.highPrice?.priceAfn==offer.priceAfn && current.maxPriceAfn!=current.minPriceAfn){
              tags.add(t('بیشترین قیمت','Highest price'));
            }
            if(current.bestRate?.operatorName==offer.operatorName &&
                current.bestRate?.deliveryPercent==offer.deliveryPercent &&
                (offer.deliveryPercent??0)>0){
              tags.add(t('پایدارترین','Best delivery'));
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _OfferTile(
                offer: offer,
                fa: fa,
                price: host.money(offer.priceAfn, showBase: true),
                busy: buying,
                tags:tags,
                onBuy: () => buy(operatorName: offer.operatorName, mode: 'BEST_RATE'),
              ),
            );
          }),
          if(current.anyOperator!=null)...[
            const SizedBox(height:2),
            _OfferTile(
              offer:current.anyOperator!,
              fa:fa,
              price:host.money(current.anyOperator!.priceAfn,showBase:true),
              busy:buying,
              anyOperator:true,
              tags:[t('انتخاب خودکار','Auto select')],
              onBuy:()=>buy(operatorName:'any',mode:'ANY'),
            ),
          ],
          const SizedBox(height:6),
          _Notice(text:t(
            'درصد SMS نشان‌دهنده نرخ اخیر تحویل پیام برای همان سرویس، کشور و اپراتور است. قیمت و موجودی لحظه‌ای تغییر می‌کند.',
            'SMS % is the recent delivery rate for this exact service, country and operator. Price and stock can change live.',
          )),
        ],
      ],
    );
  }

  Widget smartPanel() {
    final service=selectedService;
    return Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        _PanelCard(child:serviceSelector()),
        const SizedBox(height:12),
        _Notice(
          text:t(
            'فقط سرویس را انتخاب کنید. کشور و اپراتور به‌صورت خودکار از میان گزینه‌های زنده 5SIM و براساس بهترین نرخ تحویل SMS انتخاب می‌شود و خرید همان لحظه انجام می‌گردد.',
            'Choose only the service. The country and operator are selected automatically from live 5SIM offers using the best SMS delivery rate, and the purchase starts immediately.',
          ),
        ),
        const SizedBox(height:12),
        _SmartCountryCard(
          icon:Icons.auto_awesome_rounded,
          fa:fa,
          title:t('خرید هوشمند 5SIM','5SIM Smart Buy'),
          subtitle:t(
            'نیازی به انتخاب کشور یا سرور نیست؛ سیستم بهترین گزینه موجود را خودش انتخاب می‌کند.',
            'No country or server selection is needed; the best available option is selected automatically.',
          ),
          country:null,
          price:service==null?t('ابتدا سرویس را انتخاب کنید','Choose a service first'):t('انتخاب خودکار کشور و اپراتور','Automatic country & operator'),
          busy:buying,
          onTap:service==null?null:smartBuy,
        ),
      ],
    );
  }

  bool orderMatches(VirtualOrder order,String filter) {
    switch(filter){
      case 'ALL': return true;
      case 'ACTIVE': return isActive(order);
      case 'COMPLETED': return order.status=='COMPLETED';
      case 'CANCELLED': return order.status=='CANCELLED'||order.status=='REFUNDED';
      case 'FAILED': return order.status=='FAILED';
      default:return true;
    }
  }

  bool orderMatchesFilter(VirtualOrder order)=>orderMatches(order,orderFilter);

  int filterCount(String filter)=>
      orders.where((order)=>orderMatches(order,filter)).length;

  Widget numbersPanel() {
    if (orders.isEmpty) {
      return _Notice(text: t('هنوز شماره‌ای نخریده‌اید.', 'You have not purchased a number yet.'));
    }
    final visible=orders.where(orderMatchesFilter).toList(growable:false);
    final filters=[
      ('ACTIVE',t('فعال','Active'),Icons.timelapse_rounded,const Color(0xFF1686FF)),
      ('COMPLETED',t('تکمیل‌شده','Completed'),Icons.check_circle_rounded,const Color(0xFF16A875)),
      ('CANCELLED',t('لغوشده','Cancelled'),Icons.cancel_rounded,const Color(0xFFE65454)),
      ('FAILED',t('ناموفق','Failed'),Icons.error_rounded,const Color(0xFFB42318)),
      ('ALL',t('همه','All'),Icons.list_alt_rounded,const Color(0xFF607487)),
    ];
    return Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        SingleChildScrollView(
          scrollDirection:Axis.horizontal,
          child:Row(
            children:filters.map((item){
              final selected=orderFilter==item.$1;
              return Padding(
                padding:const EdgeInsetsDirectional.only(end:8),
                child:ChoiceChip(
                  selected:selected,
                  onSelected:(_)=>setState(()=>orderFilter=item.$1),
                  avatar:Icon(item.$3,size:17,color:selected?Colors.white:item.$4),
                  label:Text('${item.$2} ${filterCount(item.$1)}'),
                  labelStyle:TextStyle(
                    fontWeight:FontWeight.w800,
                    color:selected?Colors.white:const Color(0xFF27364A),
                  ),
                  selectedColor:item.$4,
                  side:BorderSide(color:selected?item.$4:const Color(0xFFDCE8F1)),
                  backgroundColor:Colors.white,
                  showCheckmark:false,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height:12),
        if(visible.isEmpty)
          _Notice(text:t('در این دسته سفارشی وجود ندارد.','There are no orders in this category.'))
        else
          ...visible.map((order) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OrderCard(
              order: order,
              fa: fa,
              price: host.money(order.totalAmountAfn, showBase: true),
              onRefresh: isActive(order) ? () => checkOrder(order) : null,
              onCancel: order.canCancel ? () => cancelOrder(order) : null,
              onFinish: order.canFinish ? () => finishOrder(order) : null,
              onBuyNew: () => setState(() => tab = 0),
            ),
          )),
      ],
    );
  }

}

class _VirtualPromoBanner extends StatelessWidget {
  const _VirtualPromoBanner({required this.banner,required this.fa});
  final AppBanner banner;
  final bool fa;

  @override
  Widget build(BuildContext context){
    final title=(fa?banner.titleFa:banner.titleEn)?.trim();
    final subtitle=(fa?banner.subtitleFa:banner.subtitleEn)?.trim();
    final imageUrl=banner.imageUrl.trim();
    return ClipRRect(
      borderRadius:BorderRadius.circular(24),
      child:SizedBox(
        height:154,
        child:Stack(
          fit:StackFit.expand,
          children:[
            Container(
              decoration:const BoxDecoration(
                gradient:LinearGradient(
                  colors:[Color(0xFF0B5F9F),Color(0xFF1597DC),Color(0xFF31A8FF)],
                ),
              ),
            ),
            if(imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit:BoxFit.cover,
                cacheWidth:((MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).clamp(640,1280)).round(),
                filterQuality:FilterQuality.low,
                gaplessPlayback:true,
                loadingBuilder:(context,child,progress)=>progress==null?child:const SizedBox.shrink(),
                errorBuilder:(_,__,___)=>const SizedBox.shrink(),
              ),
            Container(
              decoration:const BoxDecoration(
                gradient:LinearGradient(
                  begin:Alignment.centerLeft,
                  end:Alignment.centerRight,
                  colors:[Color(0xA8001830),Color(0x33001830),Color(0x05001830)],
                ),
              ),
            ),
            Padding(
              padding:const EdgeInsets.all(18),
              child:Column(
                crossAxisAlignment:CrossAxisAlignment.start,
                mainAxisAlignment:MainAxisAlignment.end,
                children:[
                  if(title?.isNotEmpty==true)
                    Text(
                      title!,
                      maxLines:2,
                      overflow:TextOverflow.ellipsis,
                      style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.w900),
                    ),
                  if(subtitle?.isNotEmpty==true)...[
                    const SizedBox(height:5),
                    Text(
                      subtitle!,
                      maxLines:2,
                      overflow:TextOverflow.ellipsis,
                      style:const TextStyle(color:Color(0xFFE8F5FF),fontSize:11.5,height:1.35,fontWeight:FontWeight.w600),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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

class _BrandVisual {
  const _BrandVisual.fa(this.faIcon,this.color):materialIcon=null;
  const _BrandVisual.material(this.materialIcon,this.color):faIcon=null;
  final FaIconData? faIcon;
  final IconData? materialIcon;
  final Color color;
}

String _serviceInitials(VirtualService service) {
  final raw = service.titleEn.trim().isNotEmpty ? service.titleEn.trim() : service.slug;
  final clean = raw.replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ').trim();
  if (clean.isEmpty) return '?';
  final parts = clean.split(RegExp(r'\s+')).where((part)=>part.isNotEmpty).toList();
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  final one = parts.first;
  return one.substring(0, one.length >= 2 ? 2 : 1).toUpperCase();
}

Color _serviceFallbackColor(VirtualService service) {
  const palette = [
    Color(0xFF1686FF), Color(0xFF805AD5), Color(0xFF16A875),
    Color(0xFFE86A33), Color(0xFFDB3F71), Color(0xFF2D7D9A),
    Color(0xFF6B7280), Color(0xFF8B5CF6),
  ];
  final source = '${service.slug}|${service.titleEn}';
  var hash = 0;
  for (final unit in source.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

_BrandVisual _brandVisual(VirtualService service) {
  final key='${service.titleEn} ${service.slug}'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'),'');
  if(key.contains('telegram'))return const _BrandVisual.fa(FontAwesomeIcons.telegram,Color(0xFF229ED9));
  if(key.contains('instagram'))return const _BrandVisual.fa(FontAwesomeIcons.instagram,Color(0xFFE4405F));
  if(key.contains('whatsapp'))return const _BrandVisual.fa(FontAwesomeIcons.whatsapp,Color(0xFF25D366));
  if(key.contains('facebook'))return const _BrandVisual.fa(FontAwesomeIcons.facebookF,Color(0xFF1877F2));
  if(key.contains('pinterest'))return const _BrandVisual.fa(FontAwesomeIcons.pinterestP,Color(0xFFE60023));
  if(key.contains('tiktok'))return const _BrandVisual.fa(FontAwesomeIcons.tiktok,Color(0xFF111111));
  if(key.contains('youtube'))return const _BrandVisual.fa(FontAwesomeIcons.youtube,Color(0xFFFF0000));
  if(key.contains('twitter')||key=='x'||key.endsWith('virtualx'))return const _BrandVisual.fa(FontAwesomeIcons.xTwitter,Color(0xFF111111));
  if(key.contains('snapchat'))return const _BrandVisual.fa(FontAwesomeIcons.snapchat,Color(0xFFF7D600));
  if(key.contains('discord'))return const _BrandVisual.fa(FontAwesomeIcons.discord,Color(0xFF5865F2));
  if(key.contains('google')||key.contains('gmail'))return const _BrandVisual.fa(FontAwesomeIcons.google,Color(0xFF4285F4));
  if(key.contains('amazon'))return const _BrandVisual.fa(FontAwesomeIcons.amazon,Color(0xFFFF9900));
  if(key.contains('microsoft'))return const _BrandVisual.fa(FontAwesomeIcons.microsoft,Color(0xFF00A4EF));
  if(key.contains('apple'))return const _BrandVisual.fa(FontAwesomeIcons.apple,Color(0xFF111111));
  if(key.contains('linkedin'))return const _BrandVisual.fa(FontAwesomeIcons.linkedinIn,Color(0xFF0A66C2));
  if(key.contains('uber'))return const _BrandVisual.fa(FontAwesomeIcons.uber,Color(0xFF111111));
  if(key.contains('airbnb'))return const _BrandVisual.fa(FontAwesomeIcons.airbnb,Color(0xFFFF5A5F));
  if(key.contains('spotify'))return const _BrandVisual.fa(FontAwesomeIcons.spotify,Color(0xFF1DB954));
  return _BrandVisual.material(Icons.apps_rounded,_serviceFallbackColor(service));
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.service,this.size=40});
  final VirtualService service;
  final double size;

  Widget _fallback(_BrandVisual brand){
    return Center(
      child:brand.faIcon!=null
        ?FaIcon(brand.faIcon!,color:brand.color,size:size*.48)
        :Text(
            _serviceInitials(service),
            style:TextStyle(
              color:brand.color,
              fontSize:size*.28,
              fontWeight:FontWeight.w900,
              letterSpacing:-.4,
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context){
    final brand=_brandVisual(service);
    final uploaded=service.iconUrl?.trim()??'';
    return Container(
      width:size,height:size,
      decoration:BoxDecoration(
        color:brand.color.withValues(alpha:.10),
        borderRadius:BorderRadius.circular(size*.30),
      ),
      clipBehavior:Clip.antiAlias,
      child:uploaded.isNotEmpty
        ?Padding(
            padding:EdgeInsets.all(size*.12),
            child:Image.network(
              uploaded,
              width:size*.76,
              height:size*.76,
              fit:BoxFit.contain,
              cacheWidth:96,
              cacheHeight:96,
              filterQuality:FilterQuality.low,
              gaplessPlayback:true,
              errorBuilder:(_,__,___)=>_fallback(brand),
            ),
          )
        :_fallback(brand),
    );
  }
}

class _SearchPickerSheet<T> extends StatefulWidget {
  const _SearchPickerSheet({
    required this.title,
    required this.searchHint,
    required this.items,
    required this.searchText,
    required this.itemBuilder,
  });
  final String title;
  final String searchHint;
  final List<T> items;
  final String Function(T) searchText;
  final Widget Function(T) itemBuilder;

  @override
  State<_SearchPickerSheet<T>> createState()=>_SearchPickerSheetState<T>();
}

class _SearchPickerSheetState<T> extends State<_SearchPickerSheet<T>> {
  final search=TextEditingController();
  String query='';

  @override
  void dispose(){search.dispose();super.dispose();}

  @override
  Widget build(BuildContext context){
    final q=query.trim().toLowerCase();
    final rows=q.isEmpty?widget.items:widget.items.where((item)=>widget.searchText(item).toLowerCase().contains(q)).toList(growable:false);
    return Padding(
      padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(context).bottom),
      child:DraggableScrollableSheet(
        expand:false,
        initialChildSize:.82,
        minChildSize:.55,
        maxChildSize:.96,
        builder:(context,controller)=>Column(children:[
          const SizedBox(height:9),
          Container(width:44,height:5,decoration:BoxDecoration(color:const Color(0xFFD5E0E8),borderRadius:BorderRadius.circular(99))),
          Padding(
            padding:const EdgeInsets.fromLTRB(18,14,18,10),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(widget.title,style:const TextStyle(fontSize:19,fontWeight:FontWeight.w900)),
              const SizedBox(height:11),
              TextField(
                controller:search,
                autofocus:false,
                onChanged:(v)=>setState(()=>query=v),
                decoration:InputDecoration(prefixIcon:const Icon(Icons.search_rounded),hintText:widget.searchHint,suffixIcon:query.isEmpty?null:IconButton(onPressed:(){search.clear();setState(()=>query='');},icon:const Icon(Icons.close_rounded))),
              ),
            ]),
          ),
          Expanded(
            child:rows.isEmpty
              ?const Center(child:Text('No results',style:TextStyle(color:Color(0xFF718399))))
              :ListView.separated(
                controller:controller,
                padding:const EdgeInsets.fromLTRB(12,2,12,20),
                itemCount:rows.length,
                separatorBuilder:(_,__)=>const Divider(height:1,color:Color(0xFFEDF2F7)),
                itemBuilder:(context,index){
                  final item=rows[index];
                  return ListTile(
                    contentPadding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                    title:widget.itemBuilder(item),
                    onTap:()=>Navigator.pop(context,item),
                  );
                },
              ),
          ),
        ]),
      ),
    );
  }
}

class _SmartCountryCard extends StatelessWidget {
  const _SmartCountryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.country,
    required this.fa,
    required this.price,
    required this.busy,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VirtualCountry? country;
  final bool fa;
  final String price;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context)=>Card(
    child:Padding(
      padding:const EdgeInsets.all(16),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          CircleAvatar(backgroundColor:const Color(0xFFE4F4FF),child:Icon(icon,color:const Color(0xFF0D78C8))),
          const SizedBox(width:11),
          Expanded(child:Text(title,style:const TextStyle(fontWeight:FontWeight.w900,fontSize:15))),
          Text(price,style:const TextStyle(fontWeight:FontWeight.w900,color:Color(0xFF0D78C8))),
        ]),
        const SizedBox(height:7),
        Text(subtitle,style:const TextStyle(color:Color(0xFF607487),fontSize:11.5,height:1.4)),
        if(country!=null)...[
          const SizedBox(height:12),
          Container(
            padding:const EdgeInsets.all(11),
            decoration:BoxDecoration(color:const Color(0xFFF5FAFE),borderRadius:BorderRadius.circular(13)),
            child:Row(children:[
              Text(_countryFlag(country!),style:const TextStyle(fontSize:30)),
              const SizedBox(width:10),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(_countryDisplayName(country!),style:const TextStyle(fontWeight:FontWeight.w900)),
                Text('${country!.availableCount} ${fa?'موجود':'available'}',style:const TextStyle(fontSize:10.5,color:Color(0xFF718399))),
              ])),
              if(country!.maxRate!=null)Container(
                padding:const EdgeInsets.symmetric(horizontal:8,vertical:5),
                decoration:BoxDecoration(color:const Color(0xFFE7F8F1),borderRadius:BorderRadius.circular(99)),
                child:Text('${country!.maxRate!.toStringAsFixed(1)}%',style:const TextStyle(fontSize:10.5,fontWeight:FontWeight.w900,color:Color(0xFF0A8B5B))),
              ),
            ]),
          ),
        ],
        const SizedBox(height:10),
        SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:onTap,icon:const Icon(Icons.flash_on_rounded),label:Text(fa?'خرید هوشمند':'Smart buy'))),
      ]),
    ),
  );
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

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.icon,required this.label,required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
    decoration:BoxDecoration(
      color:const Color(0xFFF1F7FC),
      borderRadius:BorderRadius.circular(999),
      border:Border.all(color:const Color(0xFFDCE8F1)),
    ),
    child:Row(mainAxisSize:MainAxisSize.min,children:[
      Icon(icon,size:14,color:const Color(0xFF1686FF)),
      const SizedBox(width:5),
      Text('$label: ',style:const TextStyle(fontSize:10.5,color:Color(0xFF607487),fontWeight:FontWeight.w700)),
      Text(value,style:const TextStyle(fontSize:10.5,fontWeight:FontWeight.w900,color:Color(0xFF102235))),
    ]),
  );
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({
    required this.offer,
    required this.fa,
    required this.price,
    required this.busy,
    required this.onBuy,
    this.tags=const [],
    this.anyOperator=false,
  });
  final VirtualOffer offer;
  final bool fa;
  final String price;
  final bool busy;
  final VoidCallback onBuy;
  final List<String> tags;
  final bool anyOperator;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment:CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                backgroundColor: anyOperator?const Color(0xFFEAF7FF):const Color(0xFFE4F4FF),
                child: Icon(anyOperator?Icons.shuffle_rounded:Icons.cell_tower_rounded, color: const Color(0xFF0D78C8)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children:[
                      Expanded(
                        child:Text(
                          anyOperator?(fa?'هر اپراتور':'Any operator'):offer.operatorName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing:5,
                      crossAxisAlignment:WrapCrossAlignment.center,
                      children: [
                        Text('${offer.count} ${fa ? 'موجود' : 'available'}', style: const TextStyle(fontSize: 11, color: Color(0xFF607487))),
                        if (offer.deliveryPercent != null)
                          Row(mainAxisSize:MainAxisSize.min,children:[
                            const Icon(Icons.mark_email_read_outlined,size:14,color:Color(0xFF1686FF)),
                            const SizedBox(width:3),
                            Text(
                              '${offer.deliveryPercent!.toStringAsFixed(2)}% SMS',
                              style: TextStyle(
                                fontSize: 11,
                                color:(offer.deliveryPercent??0)>0?const Color(0xFF18A875):const Color(0xFF607487),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ]),
                        ...tags.map((tag)=>Container(
                          padding:const EdgeInsets.symmetric(horizontal:7,vertical:3),
                          decoration:BoxDecoration(color:const Color(0xFFEAF6FF),borderRadius:BorderRadius.circular(999)),
                          child:Text(tag,style:const TextStyle(fontSize:9.5,fontWeight:FontWeight.w800,color:Color(0xFF0D78C8))),
                        )),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width:10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0D78C8),fontSize:15)),
                  const SizedBox(height: 7),
                  FilledButton.tonal(
                    onPressed: busy ? null : onBuy,
                    style:FilledButton.styleFrom(minimumSize:const Size(72,40)),
                    child: Text(fa ? 'خرید' : 'Buy'),
                  ),
                ],
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
    required this.onBuyNew,
    this.onRefresh,
    this.onCancel,
    this.onFinish,
  });
  final VirtualOrder order;
  final bool fa;
  final String price;
  final VoidCallback? onRefresh;
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

  Color statusColor() {
    switch(order.status){
      case 'COMPLETED': return const Color(0xFF16A875);
      case 'CANCELLED':
      case 'REFUNDED': return const Color(0xFFE65454);
      case 'FAILED': return const Color(0xFFB42318);
      default:return const Color(0xFF1686FF);
    }
  }

  Color statusBackground() {
    switch(order.status){
      case 'COMPLETED': return const Color(0xFFE8F8F1);
      case 'CANCELLED':
      case 'REFUNDED': return const Color(0xFFFFEEEE);
      case 'FAILED': return const Color(0xFFFFE7E5);
      default:return const Color(0xFFEAF6FF);
    }
  }

  bool get hasMeaningfulFailure {
    final value=order.failureReason?.trim()??'';
    return value.isNotEmpty && value!='{}' && value!='[]' && value!='[object Object]';
  }

  Future<void> copy(BuildContext context, String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(label)));
  }

  @override
  Widget build(BuildContext context) {
    final terminal = ['COMPLETED', 'CANCELLED', 'REFUNDED', 'FAILED'].contains(order.status);
    final tone=statusColor();
    return Card(
      shape:RoundedRectangleBorder(
        borderRadius:BorderRadius.circular(16),
        side:BorderSide(color:tone.withValues(alpha:.22)),
      ),
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
                  decoration: BoxDecoration(color: statusBackground(), borderRadius: BorderRadius.circular(999)),
                  child: Text(statusLabel(), style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w900)),
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
                Text('${fa ? 'کشور' : 'Country'}: ${_orderCountryName(order.country)}', style: const TextStyle(fontSize: 12, color: Color(0xFF607487))),
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
            if (hasMeaningfulFailure) ...[
              const SizedBox(height: 8),
              Text(order.failureReason!, style: const TextStyle(color: Color(0xFFE65454), fontSize: 11)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onRefresh != null) OutlinedButton.icon(onPressed: onRefresh, icon: const Icon(Icons.refresh_rounded), label: Text(fa ? 'بررسی SMS' : 'Check SMS')),
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
