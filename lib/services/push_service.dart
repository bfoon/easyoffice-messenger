import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Handles Firebase Cloud Messaging: permission, token retrieval, and
/// registering the token with our server. Foreground display and tap
/// handling are wired in a later step.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    try {
      // Ask the user for notification permission (Android 13+ requires it;
      // older Android grants automatically).
      await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get the device token and send it to the server.
      final token = await _fcm.getToken();
      if (token != null) {
        if (kDebugMode) debugPrint('FCM token: $token');
        await ApiService.instance.registerDeviceToken(token);
      }

      // If the token is rotated by Firebase, re-register the new one.
      _fcm.onTokenRefresh.listen((newToken) {
        ApiService.instance.registerDeviceToken(newToken);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('PushService init failed: $e');
    }
  }
}