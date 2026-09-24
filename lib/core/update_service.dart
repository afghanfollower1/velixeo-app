import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../design/velixeo_design.dart';

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

class AppUpdateDownloadState {
  const AppUpdateDownloadState({
    required this.downloadId,
    required this.status,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    this.version,
    this.reason,
  });

  final int downloadId;
  final String status;
  final int downloadedBytes;
  final int totalBytes;
  final double progress;
  final String? version;
  final int? reason;

  bool get isActive =>
      status == 'pending' || status == 'running' || status == 'paused';
  bool get isSuccessful => status == 'successful';
  bool get isFailed => status == 'failed' || status == 'missing';

  factory AppUpdateDownloadState.fromJson(Map<dynamic, dynamic> json) {
    int asInt(dynamic value, [int fallback = 0]) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? fallback;
    }

    double asDouble(dynamic value, [double fallback = -1]) {
      if (value is double) return value;
      if (value is num) return value.toDouble();
      return double.tryParse('$value') ?? fallback;
    }

    return AppUpdateDownloadState(
      downloadId: asInt(json['downloadId'], -1),
      status: '${json['status'] ?? 'unknown'}',
      downloadedBytes: asInt(json['downloadedBytes']),
      totalBytes: asInt(json['totalBytes'], -1),
      progress: asDouble(json['progress']),
      version: json['version']?.toString(),
      reason: json['reason'] == null ? null : asInt(json['reason']),
    );
  }
}

class AppUpdateService {
  static const _channel = MethodChannel('com.velixeo.velixeo/updater');
  static const _latestReleaseApi =
      'https://api.github.com/repos/afghanfollower1/velixeo-app/releases/latest';

  Future<AppUpdateInfo?> checkForUpdate() async {
    try {
      final current =
          await _channel.invokeMethod<String>('getAppVersion') ?? '0.0.0';
      final response = await http
          .get(
            Uri.parse(_latestReleaseApi),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'VELIXEO-Android',
              'Cache-Control': 'no-cache, no-store, max-age=0',
              'Pragma': 'no-cache',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final latest =
          ((json['tag_name'] as String?) ?? '').replaceFirst(RegExp(r'^v'), '');
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

  Future<AppUpdateDownloadState> startUpdateDownload(
    AppUpdateInfo update,
  ) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'startUpdateDownload',
      {
        'url': update.downloadUrl,
        'version': update.version,
      },
    );
    if (raw == null) {
      throw PlatformException(
        code: 'download_start_failed',
        message: 'Android DownloadManager did not return a download state.',
      );
    }
    return AppUpdateDownloadState.fromJson(raw);
  }

  Future<AppUpdateDownloadState?> getUpdateDownloadStatus(
    int downloadId,
  ) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getUpdateDownloadStatus',
      {'downloadId': downloadId},
    );
    if (raw == null) return null;
    return AppUpdateDownloadState.fromJson(raw);
  }

  Future<void> openDownloadedUpdate(int downloadId) async {
    await _channel.invokeMethod<void>(
      'openDownloadedUpdate',
      {'downloadId': downloadId},
    );
  }

  Future<void> cancelUpdateDownload(int downloadId) async {
    await _channel.invokeMethod<void>(
      'cancelUpdateDownload',
      {'downloadId': downloadId},
    );
  }

  bool _isNewer(String latest, String current) {
    List<int> parts(String value) {
      final clean = value.split('+').first.split('-').first;
      return clean
          .split('.')
          .map((part) => int.tryParse(part) ?? 0)
          .toList();
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
  const AppUpdateGate({
    super.key,
    required this.child,
    required this.fa,
  });

  final Widget child;
  final bool fa;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  final service = AppUpdateService();
  bool _checking = false;
  bool _dialogOpen = false;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check(force: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_check());
    }
  }

  Future<void> _check({bool force = false}) async {
    if (_checking || _dialogOpen) return;
    final now = DateTime.now();
    if (!force &&
        _lastCheck != null &&
        now.difference(_lastCheck!) < const Duration(seconds: 30)) {
      return;
    }

    _checking = true;
    _lastCheck = now;
    try {
      final update = await service.checkForUpdate();
      if (!mounted || update == null || _dialogOpen) return;
      _dialogOpen = true;
      try {
        await (widget.fa ? _showPersianUpdate(update) : _showEnglishUpdate(update));
      } finally {
        _dialogOpen = false;
      }
    } finally {
      _checking = false;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 0) return '-';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _showPersianUpdate(AppUpdateInfo update) async {
    var downloading = false;
    var progress = -1.0;
    var downloadedBytes = 0;
    var totalBytes = -1;
    var statusText = widget.fa ? 'آمادهٔ دریافت' : 'Ready to download';
    int? downloadId;
    var dialogClosed = false;

    Future<void> watchDownload(
      BuildContext dialogContext,
      StateSetter setDialogState,
      int id,
    ) async {
      while (!dialogClosed) {
        AppUpdateDownloadState? state;
        try {
          state = await service.getUpdateDownloadStatus(id);
        } catch (_) {
          state = null;
        }

        if (dialogClosed || !dialogContext.mounted) return;

        if (state == null) {
          setDialogState(() {
            downloading = false;
            statusText = widget.fa ? 'وضعیت به‌روزرسانی در دسترس نیست.' : 'Update status is unavailable.';
          });
          return;
        }
        final current = state;

        setDialogState(() {
          progress = current.progress;
          downloadedBytes = current.downloadedBytes;
          totalBytes = current.totalBytes;
          statusText = switch (current.status) {
            'pending' => widget.fa ? 'در انتظار Download Manager اندروید…' : 'Waiting for Android Download Manager...',
            'running' => widget.fa ? 'در حال دریافت در پس‌زمینه…' : 'Downloading in background...',
            'paused' => widget.fa ? 'دریافت متوقف شده؛ اندروید دوباره تلاش می‌کند.' : 'Download paused. Android will retry automatically.',
            'successful' => widget.fa ? 'دریافت کامل شد؛ نصب‌کننده باز می‌شود…' : 'Download complete. Opening installer...',
            'failed' => widget.fa ? 'دریافت ناموفق بود.' : 'Download failed.',
            _ => widget.fa ? 'در حال آماده‌سازی…' : 'Preparing update...',
          };
        });

        if (current.isSuccessful) {
          try {
            await service.openDownloadedUpdate(id);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          } catch (_) {
            if (dialogContext.mounted) {
              setDialogState(() {
                downloading = false;
                statusText = widget.fa
                    ? 'دریافت کامل شد، اما نصب‌کننده باز نشد.'
                    : 'Download finished, but Android could not open the installer.';
              });
            }
          }
          return;
        }

        if (current.isFailed) {
          if (dialogContext.mounted) {
            setDialogState(() => downloading = false);
          }
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final percent =
              progress >= 0 ? '${(progress * 100).clamp(0, 100).round()}%' : null;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: Color(0xFF4BA6CB),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.fa ? 'به‌روزرسانی VELIXEO' : 'VELIXEO update')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fa
                      ? 'نسخهٔ جدید ' + update.version + ' آماده است.'
                      : 'Version ' + update.version + ' is ready.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: VelixeoBrand.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.fa
                      ? 'دریافت با Download Manager اندروید انجام می‌شود و در پس‌زمینه هم ادامه پیدا می‌کند.'
                      : 'The update uses Android Download Manager and can continue in the background.',
                  style: const TextStyle(height: 1.55, fontSize: 12, color: VelixeoBrand.muted),
                ),
                if (downloading) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: progress >= 0
                        ? progress.clamp(0.0, 1.0).toDouble()
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (percent != null)
                        Text(
                          percent,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  if (downloadedBytes > 0 || totalBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6E8194),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    widget.fa
                        ? 'می‌توانی از VELIXEO خارج شوی؛ اندروید دریافت را ادامه می‌دهد و وضعیت را در اعلان‌ها نشان می‌دهد.'
                        : 'You can leave VELIXEO now. Android will keep downloading and show the update in the notification area.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6E8194),
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!downloading)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(widget.fa ? 'بعداً' : 'Later'),
                ),
              if (downloading && downloadId != null)
                TextButton(
                  onPressed: () async {
                    final id = downloadId!;
                    await service.cancelUpdateDownload(id);
                    if (!dialogContext.mounted) return;
                    setDialogState(() {
                      downloading = false;
                      progress = -1;
                      downloadedBytes = 0;
                      totalBytes = -1;
                      downloadId = null;
                      statusText = widget.fa ? 'دریافت لغو شد.' : 'Download cancelled.';
                    });
                  },
                  child: Text(widget.fa ? 'لغو دریافت' : 'Cancel'),
                ),
              FilledButton.icon(
                onPressed: downloading
                    ? null
                    : () async {
                        final allowed = await service.canInstallPackages();
                        if (!allowed) {
                          await service.openInstallPermission();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.fa
                                    ? 'گزینهٔ «اجازه از این منبع» را فعال کن، به VELIXEO برگرد و دوباره به‌روزرسانی را بزن.'
                                    : 'Enable "Allow from this source", return to VELIXEO, then tap Update again. This permission is normally needed only once.',
                              ),
                            ),
                          );
                          return;
                        }

                        try {
                          final initial =
                              await service.startUpdateDownload(update);
                          if (!dialogContext.mounted) return;
                          downloadId = initial.downloadId;
                          setDialogState(() {
                            downloading = true;
                            progress = initial.progress;
                            downloadedBytes = initial.downloadedBytes;
                            totalBytes = initial.totalBytes;
                            statusText = initial.isSuccessful
                                ? (widget.fa ? 'دریافت کامل شد؛ نصب‌کننده باز می‌شود…' : 'Download complete. Opening installer...')
                                : (widget.fa ? 'در حال دریافت در پس‌زمینه…' : 'Downloading in background...');
                          });
                          unawaited(
                            watchDownload(
                              dialogContext,
                              setDialogState,
                              initial.downloadId,
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.fa
                                    ? 'دریافت به‌روزرسانی شروع نشد. دوباره تلاش کن.'
                                    : 'Update download could not start. Please try again.',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  downloading
                      ? (progress >= 0
                          ? '${(progress * 100).clamp(0, 100).round()}%'
                          : (widget.fa ? 'در حال دریافت…' : 'Downloading...'))
                      : (widget.fa ? 'همین حالا به‌روزرسانی' : 'Update now'),
                ),
              ),
            ],
          );
        },
      ),
    );

    dialogClosed = true;
  }

Future<void> _showEnglishUpdate(AppUpdateInfo update) async {
    var downloading = false;
    var progress = -1.0;
    var downloadedBytes = 0;
    var totalBytes = -1;
    var statusText = widget.fa ? 'آمادهٔ دریافت' : 'Ready to download';
    int? downloadId;
    var dialogClosed = false;

    Future<void> watchDownload(
      BuildContext dialogContext,
      StateSetter setDialogState,
      int id,
    ) async {
      while (!dialogClosed) {
        AppUpdateDownloadState? state;
        try {
          state = await service.getUpdateDownloadStatus(id);
        } catch (_) {
          state = null;
        }

        if (dialogClosed || !dialogContext.mounted) return;

        if (state == null) {
          setDialogState(() {
            downloading = false;
            statusText = widget.fa ? 'وضعیت به‌روزرسانی در دسترس نیست.' : 'Update status is unavailable.';
          });
          return;
        }
        final current = state;

        setDialogState(() {
          progress = current.progress;
          downloadedBytes = current.downloadedBytes;
          totalBytes = current.totalBytes;
          statusText = switch (current.status) {
            'pending' => widget.fa ? 'در انتظار Download Manager اندروید…' : 'Waiting for Android Download Manager...',
            'running' => widget.fa ? 'در حال دریافت در پس‌زمینه…' : 'Downloading in background...',
            'paused' => widget.fa ? 'دریافت متوقف شده؛ اندروید دوباره تلاش می‌کند.' : 'Download paused. Android will retry automatically.',
            'successful' => widget.fa ? 'دریافت کامل شد؛ نصب‌کننده باز می‌شود…' : 'Download complete. Opening installer...',
            'failed' => widget.fa ? 'دریافت ناموفق بود.' : 'Download failed.',
            _ => widget.fa ? 'در حال آماده‌سازی…' : 'Preparing update...',
          };
        });

        if (current.isSuccessful) {
          try {
            await service.openDownloadedUpdate(id);
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          } catch (_) {
            if (dialogContext.mounted) {
              setDialogState(() {
                downloading = false;
                statusText = widget.fa
                    ? 'دریافت کامل شد، اما نصب‌کننده باز نشد.'
                    : 'Download finished, but Android could not open the installer.';
              });
            }
          }
          return;
        }

        if (current.isFailed) {
          if (dialogContext.mounted) {
            setDialogState(() => downloading = false);
          }
          return;
        }

        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final percent =
              progress >= 0 ? '${(progress * 100).clamp(0, 100).round()}%' : null;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(
                  Icons.system_update_alt_rounded,
                  color: Color(0xFF4BA6CB),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.fa ? 'به‌روزرسانی VELIXEO' : 'VELIXEO update')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fa
                      ? 'نسخهٔ جدید ' + update.version + ' آماده است.'
                      : 'Version ' + update.version + ' is ready.',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: VelixeoBrand.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.fa
                      ? 'دریافت با Download Manager اندروید انجام می‌شود و در پس‌زمینه هم ادامه پیدا می‌کند.'
                      : 'The update uses Android Download Manager and can continue in the background.',
                  style: const TextStyle(height: 1.55, fontSize: 12, color: VelixeoBrand.muted),
                ),
                if (downloading) ...[
                  const SizedBox(height: 18),
                  LinearProgressIndicator(
                    value: progress >= 0
                        ? progress.clamp(0.0, 1.0).toDouble()
                        : null,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          statusText,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      if (percent != null)
                        Text(
                          percent,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                    ],
                  ),
                  if (downloadedBytes > 0 || totalBytes > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_formatBytes(downloadedBytes)} / ${_formatBytes(totalBytes)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF6E8194),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    widget.fa
                        ? 'می‌توانی از VELIXEO خارج شوی؛ اندروید دریافت را ادامه می‌دهد و وضعیت را در اعلان‌ها نشان می‌دهد.'
                        : 'You can leave VELIXEO now. Android will keep downloading and show the update in the notification area.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6E8194),
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!downloading)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(widget.fa ? 'بعداً' : 'Later'),
                ),
              if (downloading && downloadId != null)
                TextButton(
                  onPressed: () async {
                    final id = downloadId!;
                    await service.cancelUpdateDownload(id);
                    if (!dialogContext.mounted) return;
                    setDialogState(() {
                      downloading = false;
                      progress = -1;
                      downloadedBytes = 0;
                      totalBytes = -1;
                      downloadId = null;
                      statusText = widget.fa ? 'دریافت لغو شد.' : 'Download cancelled.';
                    });
                  },
                  child: Text(widget.fa ? 'لغو دریافت' : 'Cancel'),
                ),
              FilledButton.icon(
                onPressed: downloading
                    ? null
                    : () async {
                        final allowed = await service.canInstallPackages();
                        if (!allowed) {
                          await service.openInstallPermission();
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.fa
                                    ? 'گزینهٔ «اجازه از این منبع» را فعال کن، به VELIXEO برگرد و دوباره به‌روزرسانی را بزن.'
                                    : 'Enable "Allow from this source", return to VELIXEO, then tap Update again. This permission is normally needed only once.',
                              ),
                            ),
                          );
                          return;
                        }

                        try {
                          final initial =
                              await service.startUpdateDownload(update);
                          if (!dialogContext.mounted) return;
                          downloadId = initial.downloadId;
                          setDialogState(() {
                            downloading = true;
                            progress = initial.progress;
                            downloadedBytes = initial.downloadedBytes;
                            totalBytes = initial.totalBytes;
                            statusText = initial.isSuccessful
                                ? (widget.fa ? 'دریافت کامل شد؛ نصب‌کننده باز می‌شود…' : 'Download complete. Opening installer...')
                                : (widget.fa ? 'در حال دریافت در پس‌زمینه…' : 'Downloading in background...');
                          });
                          unawaited(
                            watchDownload(
                              dialogContext,
                              setDialogState,
                              initial.downloadId,
                            ),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                widget.fa
                                    ? 'دریافت به‌روزرسانی شروع نشد. دوباره تلاش کن.'
                                    : 'Update download could not start. Please try again.',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  downloading
                      ? (progress >= 0
                          ? '${(progress * 100).clamp(0, 100).round()}%'
                          : (widget.fa ? 'در حال دریافت…' : 'Downloading...'))
                      : (widget.fa ? 'همین حالا به‌روزرسانی' : 'Update now'),
                ),
              ),
            ],
          );
        },
      ),
    );

    dialogClosed = true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
