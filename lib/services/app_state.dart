import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/models.dart';
import 'api_service.dart';
import 'local_db.dart';
import 'push_service.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

/// Holds the session: current user, login status, and a presence heartbeat
/// that keeps the user marked online while the app is in the foreground.
class AppState extends ChangeNotifier {
  final _api = ApiService.instance;
  AuthStatus status = AuthStatus.unknown;
  UserMini? me;
  Timer? _heartbeat;

  Future<void> bootstrap() async {
    await _api.loadTokens();
    if (_api.isLoggedIn) {
      final u = await _api.me();
      if (u != null) {
        me = u;
        status = AuthStatus.loggedIn;
        _startHeartbeat();
        PushService.instance.init();
      } else {
        await _api.clearTokens();
        status = AuthStatus.loggedOut;
      }
    } else {
      status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<String?> login(String username, String password) async {
    final ok = await _api.login(username, password);
    if (!ok) return 'Wrong username or password.';
    me = await _api.me();
    status = AuthStatus.loggedIn;
    _startHeartbeat();
    PushService.instance.init();
    notifyListeners();
    return null;
  }

  Future<void> logout() async {
    _heartbeat?.cancel();
    await LocalDb.instance.clearAll();
    await _api.logout();
    me = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  void _startHeartbeat() {
    _heartbeat?.cancel();
    _api.heartbeat();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      _api.heartbeat();
    });
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    super.dispose();
  }
}