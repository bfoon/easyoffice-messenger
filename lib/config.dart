/// Central configuration for the EasyOffice Messenger app.
///
/// IMPORTANT: confirm [apiBase] matches how the mobile_api app is mounted on
/// your server. The Django `mobile_api/urls.py` defines routes like
/// `auth/login/`, `rooms/`, etc. They are almost certainly included under a
/// prefix such as `/api/mobile/` or `/mobile/`. Set [apiPrefix] to match.
library;

class AppConfig {
  /// Scheme + host of your EasyOffice deployment. No trailing slash.
  static const String host = 'https://easyoffice.gm';

  /// Path prefix where `apps.mobile_api.urls` is included in the root urls.py.
  /// If unsure, check your project's main urls.py for a line like:
  ///   path('api/mobile/', include('apps.mobile_api.urls'))
  static const String apiPrefix = '/api/mobile';

  /// Path where the chat WebSocket is routed (Django Channels routing.py).
  /// The ChatConsumer expects a `room_id` kwarg, so the URL pattern is
  /// typically: ws/chat/<room_id>/
  static const String wsChatPath = '/ws/chat';

  // ── Derived ────────────────────────────────────────────────────────────
  static String get apiBase => '$host$apiPrefix';

  static Uri api(String path) =>
      Uri.parse('$apiBase${path.startsWith('/') ? path : '/$path'}');

  /// Build the ws:// or wss:// URL for a room. Carries the JWT as a query
  /// param so an auth middleware can authenticate the socket if cookies are
  /// unavailable (common for mobile).
  static Uri wsRoom(String roomId, String accessToken) {
    final wsScheme = host.startsWith('https') ? 'wss' : 'ws';
    final bare = host.replaceFirst(RegExp(r'^https?://'), '');
    return Uri.parse('$wsScheme://$bare$wsChatPath/$roomId/?token=$accessToken');
  }
}
