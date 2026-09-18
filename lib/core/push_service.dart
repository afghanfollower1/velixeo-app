import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api_service.dart';

class PushService {
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  StreamSubscription<RemoteMessage>? _openedMessages;
  String? _registeredToken;
  bool _firebaseReady = false;

  Future<void> configure(
    ApiService api, {
    required Future<void> Function() onNotification,
    Future<void> Function(Map<String, String> data)? onNotificationOpened,
    Future<void> Function(String title, String body, Map<String, String> data)? onForegroundNotification,
  }) async {
    if (!Platform.isAndroid) return;

    final config = await api.pushConfig();
    if (!config.complete) return;

    if (!_firebaseReady) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: config.apiKey!,
            appId: config.appId!,
            messagingSenderId: config.messagingSenderId!,
            projectId: config.projectId!,
          ),
        );
      }
      _firebaseReady = true;
    }

    final messaging = FirebaseMessaging.instance;
    await messaging.setAutoInitEnabled(true);
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (permission.authorizationStatus == AuthorizationStatus.denied) return;

    String? token;
    for (var attempt = 0; attempt < 3; attempt += 1) {
      try {
        token = await messaging.getToken();
        if (token?.trim().isNotEmpty == true) break;
      } catch (_) {}
      await Future<void>.delayed(Duration(milliseconds: 700 * (attempt + 1)));
    }
    if (token?.trim().isNotEmpty == true) {
      _registeredToken = token!.trim();
      await api.registerPushDevice(_registeredToken!);
    }

    _tokenRefresh ??= messaging.onTokenRefresh.listen((nextToken) async {
      final clean = nextToken.trim();
      if (clean.isEmpty) return;
      _registeredToken = clean;
      try {
        await api.registerPushDevice(clean);
      } catch (_) {}
    });

    _foregroundMessages ??= FirebaseMessaging.onMessage.listen((message) async {
      try {
        await onNotification();
      } catch (_) {}
      final title = message.notification?.title?.trim() ?? '';
      final body = message.notification?.body?.trim() ?? '';
      if (onForegroundNotification != null && (title.isNotEmpty || body.isNotEmpty)) {
        try {
          await onForegroundNotification(title, body, Map<String, String>.from(message.data));
        } catch (_) {}
      }
    });

    Future<void> markOpened(RemoteMessage message) async {
      final notificationId = message.data['notificationId']?.trim();
      if (notificationId?.isNotEmpty == true) {
        try {
          await api.markNotificationRead(notificationId!);
        } catch (_) {}
      }
      try {
        await onNotification();
      } catch (_) {}
      if (onNotificationOpened != null) {
        try {
          await onNotificationOpened(Map<String, String>.from(message.data));
        } catch (_) {}
      }
    }

    _openedMessages ??= FirebaseMessaging.onMessageOpenedApp.listen(markOpened);

    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      await markOpened(initial);
    }
  }

  Future<void> unregister(ApiService api) async {
    final token = _registeredToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.unregisterPushDevice(token);
    } catch (_) {}
    _registeredToken = null;
  }

  Future<void> dispose() async {
    await _tokenRefresh?.cancel();
    await _foregroundMessages?.cancel();
    await _openedMessages?.cancel();
    _tokenRefresh = null;
    _foregroundMessages = null;
    _openedMessages = null;
  }
}
