import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class AppUpdateInfo {
  const AppUpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseUrl,
    this.notes = '',
  });

  final String version;
  final String downloadUrl;
  final String releaseUrl;
  final String notes;
}

class AppUpdateService {
  static const _channel = MethodChannel('com.velixeo.velixeo/updater');
  static const _latestReleaseApi =
      'https://api.github.com/repos/afghanfollower1/velixeo-app/releases/latest';

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final current = await _channel.invokeMethod<String>('getAppVersion') ?? '0.0.0';
      final response = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'VELIXEO-Android',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latest = ((json['tag_name'] as String?) ?? '').replaceFirst(RegExp(r'^v'), '');
      if (latest.isEmpty || !_isNewer(latest, current)) return null;

      final assets = (json['assets'] as List?) ?? const [];
      Map<String, dynamic>? apk;
      for (final raw in assets) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final name = ((item['name'] as String?) ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apk = item;
          break;
        }
      }
      final downloadUrl = apk?['browser_download_url'] as String?;
      if (downloadUrl == null || downloadUrl.isEmpty) return null;

      return AppUpdateInfo(
        version: latest,
        downloadUrl: downloadUrl,
        releaseUrl: (json['html_url'] as String?) ?? '',
        notes: (json['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> canInstallPackages() async {
    try {
      return await _channel.invokeMethod<bool>('canInstallPackages') ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> openInstallPermission() async {
    await _channel.invokeMethod<void>('openInstallPermission');
  }

  Future<void> downloadAndInstall(AppUpdateInfo update) async {
    await _channel.invokeMethod<void>('downloadAndInstallApk', {
      'url': update.downloadUrl,
      'version': update.version,
    });
  }

  bool _isNewer(String latest, String current) {
    List<int> parts(String value) {
      final clean = value.split('+').first.split('-').first;
      return clean.split('.').map((part) => int.tryParse(part) ?? 0).toList();
    }

    final a = parts(latest);
    final b = parts(current);
    final length = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < length; i++) {
      final av = i < a.length ? a[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (av != bv) return av > bv;
    }
    return false;
  }
}

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  final service = AppUpdateService();
  bool checked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (checked) return;
    checked = true;
    final update = await service.checkForUpdate();
    if (!mounted || update == null) return;
    await _showUpdate(update);
  }

  Future<void> _showUpdate(AppUpdateInfo update) async {
    var installing = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: !installing,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update_alt_rounded, color: Color(0xFF1686FF)),
              SizedBox(width: 10),
              Expanded(child: Text('VELIXEO update')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Version ' + update.version + ' is ready.',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'VELIXEO can download the signed update inside the app and open Android’s installer, so you do not need to manually download future APK files.',
                style: TextStyle(height: 1.45),
              ),
              if (installing) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('Downloading update…', style: TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            if (!installing)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Later'),
              ),
            FilledButton.icon(
              onPressed: installing
                  ? null
                  : () async {
                      final allowed = await service.canInstallPackages();
                      if (!allowed) {
                        await service.openInstallPermission();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Enable “Allow from this source”, return to VELIXEO, then tap Update again. This permission is normally needed only once.',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => installing = true);
                      try {
                        await service.downloadAndInstall(update);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (!context.mounted) return;
                        setDialogState(() => installing = false);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Update download failed. Please try again.')),
                        );
                      }
                    },
              icon: const Icon(Icons.download_rounded),
              label: Text(installing ? 'Downloading…' : 'Update now'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
