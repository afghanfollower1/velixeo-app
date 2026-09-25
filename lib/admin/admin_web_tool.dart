import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/api_service.dart';

enum AdminTone { blue, green, purple, peach }

class AdminTool {
  const AdminTool({
    required this.keyName,
    required this.titleFa,
    required this.titleEn,
    required this.subtitleFa,
    required this.subtitleEn,
    required this.icon,
    required this.path,
    this.tone = AdminTone.blue,
  });

  final String keyName;
  final String titleFa;
  final String titleEn;
  final String subtitleFa;
  final String subtitleEn;
  final IconData icon;
  final String path;
  final AdminTone tone;

  String title(bool fa) => fa ? titleFa : titleEn;
  String subtitle(bool fa) => fa ? subtitleFa : subtitleEn;
}

class AdminWebToolPage extends StatefulWidget {
  const AdminWebToolPage({
    super.key,
    required this.api,
    required this.fa,
    required this.tool,
  });

  final ApiService api;
  final bool fa;
  final AdminTool tool;

  @override
  State<AdminWebToolPage> createState() => _AdminWebToolPageState();
}

class _AdminWebToolPageState extends State<AdminWebToolPage> {
  WebViewController? _web;
  bool _loading = true;
  bool _recovering = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    if (_recovering) return;
    _recovering = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final path = await widget.api.adminMobileSessionPath(
        widget.tool.path,
        fa: widget.fa,
      );
      late final WebViewController controller;
      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFF6F9FC))
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) {
              if (mounted) setState(() => _loading = true);
            },
            onPageFinished: (_) async {
              try {
                await controller.runJavaScript(_mobileAdminScript);
              } catch (_) {}
              if (mounted) setState(() => _loading = false);
            },
            onNavigationRequest: (request) async {
              final uri = Uri.tryParse(request.url);
              if (uri == null) return NavigationDecision.prevent;
              if (uri.host == Uri.parse(ApiService.baseUrl).host) {
                if (uri.path == '/admin/login') {
                  unawaited(_boot());
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              }
              if (uri.scheme == 'http' || uri.scheme == 'https') {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
              return NavigationDecision.prevent;
            },
            onWebResourceError: (error) {
              if (!mounted || error.isForMainFrame == false) return;
              setState(() {
                _loading = false;
                _error = error.description;
              });
            },
          ),
        )
        ..loadRequest(Uri.parse(ApiService.baseUrl + path));
      if (mounted) setState(() => _web = controller);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    } finally {
      _recovering = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fa = widget.fa;
    return Directionality(
      textDirection: fa ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: const Color(0xFFF6F9FC),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            onPressed: () async {
              if (_web != null && await _web!.canGoBack()) {
                await _web!.goBack();
              } else if (mounted) {
                Navigator.maybePop(context);
              }
            },
            icon: Icon(fa ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded),
          ),
          title: Text(
            widget.tool.title(fa),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          actions: [
            IconButton(
              onPressed: () => _web?.reload(),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Stack(
          children: [
            if (_web != null) WebViewWidget(controller: _web!),
            if (_error != null)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFFF6F9FC),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.cloud_off_outlined,
                            size: 38,
                            color: Color(0xFF8EA0AA),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            fa
                                ? 'بخش مدیریت باز نشد. دوباره تلاش کن.'
                                : 'The management tool could not be opened.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _boot,
                            child: Text(fa ? 'تلاش دوباره' : 'Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_loading)
              const Align(
                alignment: Alignment.topCenter,
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: Color(0xFF38BDF8),
                  backgroundColor: Color(0xFFE8F6FC),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

const String _mobileAdminScript = r'''
(() => {
  document.documentElement.classList.add('vx-app-admin-web');
  document.querySelectorAll('.admin-sidebar,.admin-top,.footer,.vx-locale,.vx-admin-menu-toggle,.vx-admin-backdrop')
    .forEach((node) => { node.style.display = 'none'; });

  const shell = document.querySelector('.admin-shell');
  if (shell) {
    shell.style.display = 'block';
    shell.style.minHeight = 'auto';
  }
  const main = document.querySelector('.admin-main');
  if (main) {
    main.style.padding = '10px 12px 22px';
    main.style.width = '100%';
    main.style.maxWidth = '100%';
  }

  document.querySelectorAll('table').forEach((table) => {
    table.classList.add('vx-mobile-admin-table');
    const labels = Array.from(table.querySelectorAll('thead th'))
      .map((cell) => (cell.textContent || '').trim());
    table.querySelectorAll('tbody tr').forEach((row) => {
      Array.from(row.children).forEach((cell, index) => {
        if (!cell.dataset.label) cell.dataset.label = labels[index] || 'Details';
      });
    });
  });

  if (document.getElementById('vx-app-admin-web-style')) return;
  const style = document.createElement('style');
  style.id = 'vx-app-admin-web-style';
  style.textContent = [
    'html,body{background:#f6f9fc!important;overflow-x:hidden!important}',
    '.admin-main{direction:inherit!important}',
    '#route-content{max-width:100%!important}',
    '.card{border-radius:18px!important;padding:16px!important;margin-bottom:14px!important}',
    '.grid,.grid.eq,.forms,.stats,.dashboard-kpis{grid-template-columns:1fr!important;gap:12px!important}',
    '.tabs{padding:6px!important;background:#edf5fa!important;border:0!important;border-radius:13px!important;margin-bottom:12px!important}',
    '.tab{min-height:36px!important;padding:7px 12px!important;font-size:11px!important;border:0!important;border-radius:9px!important}',
    '.tab.active{background:#fff!important;color:#2288b1!important}',
    '.order-filterbar{grid-template-columns:1fr!important}',
    '.field input,.field select,.field textarea,.order-filterbar input,.order-filterbar select{font-size:13px!important;min-height:46px!important}',
    '.btn{min-height:42px!important;font-size:12px!important}',
    '.tablewrap{overflow:visible!important}',
    'table.vx-mobile-admin-table,table.vx-mobile-admin-table tbody{display:block!important;width:100%!important;min-width:0!important}',
    'table.vx-mobile-admin-table thead{position:absolute!important;width:1px!important;height:1px!important;overflow:hidden!important;clip-path:inset(50%)!important}',
    'table.vx-mobile-admin-table tbody tr{display:block!important;border:1px solid #e5edf3!important;border-radius:16px!important;padding:4px 13px!important;margin:0 0 13px!important;background:#fcfdff!important}',
    'table.vx-mobile-admin-table td{display:flex!important;align-items:flex-start!important;justify-content:space-between!important;gap:12px!important;padding:10px 0!important;width:100%!important;border:0!important;border-bottom:1px solid #eef3f6!important;text-align:start!important;font-size:11px!important;white-space:normal!important;line-height:1.85!important}',
    'table.vx-mobile-admin-table td:first-child{display:block!important;font-size:12px!important;font-weight:600!important;padding:12px 0!important}',
    'table.vx-mobile-admin-table td:last-child{border-bottom:0!important}',
    'table.vx-mobile-admin-table td:not(:first-child)::before{content:attr(data-label);font-size:10px;color:#93a4b0;flex-shrink:0;max-width:42%}',
    '.actions,.row,.between,.cardhead,.section-title{gap:8px!important}',
    '.cardhead{align-items:flex-start!important;flex-wrap:wrap!important}',
    '.notice{font-size:11px!important;line-height:1.9!important;padding:12px!important}',
    '.provider{grid-template-columns:40px minmax(0,1fr)!important;gap:9px!important}',
    '.provider>*:nth-child(n+3){grid-column:2!important}',
    '.modulehero,.nhero{min-height:130px!important}',
    'h1{font-size:21px!important}h2{font-size:16px!important}h3{font-size:14px!important}'
  ].join('');
  document.head.appendChild(style);
})();
''';
