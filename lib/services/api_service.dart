import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/models.dart';
import '../models/files_models.dart';

/// Thin client over the EasyOffice mobile_api. Handles JWT storage, attaching
/// the Authorization header, and transparently refreshing an expired access
/// token once before giving up.
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const _kAccess = 'eo_access';
  static const _kRefresh = 'eo_refresh';

  String? _access;
  String? _refresh;

  String? get accessToken => _access;
  bool get isLoggedIn => _access != null;

  // ── Token lifecycle ──────────────────────────────────────────────────────

  Future<void> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    _access = prefs.getString(_kAccess);
    _refresh = prefs.getString(_kRefresh);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_access != null) await prefs.setString(_kAccess, _access!);
    if (_refresh != null) await prefs.setString(_kRefresh, _refresh!);
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        if (_access != null) 'Authorization': 'Bearer $_access',
      };

  // ── Core request with one-shot refresh-and-retry on 401 ───────────────────

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    bool retry = true,
  }) async {
    final uri = AppConfig.api(path);
    Future<http.Response> doIt() {
      final h = _headers();
      switch (method) {
        case 'GET':
          return http.get(uri, headers: h);
        case 'POST':
          return http.post(uri, headers: h, body: body == null ? null : jsonEncode(body));
        case 'PATCH':
          return http.patch(uri, headers: h, body: body == null ? null : jsonEncode(body));
        case 'DELETE':
          return http.delete(uri, headers: h, body: body == null ? null : jsonEncode(body));
        default:
          throw ArgumentError('Unsupported method $method');
      }
    }

    var res = await doIt();
    if (res.statusCode == 401 && retry && _refresh != null) {
      final refreshed = await refreshAccess();
      if (refreshed) res = await doIt();
    }
    return res;
  }

  Map<String, dynamic> _decode(http.Response r) {
    if (r.body.isEmpty) return {};
    final d = jsonDecode(r.body);
    return d is Map<String, dynamic> ? d : {'_list': d};
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<bool> login(String emailOrUsername, String password) async {
    final res = await http.post(
      AppConfig.api('auth/login/'),
      headers: {'Content-Type': 'application/json'},
      // Send under both keys so the backend can use whichever it expects.
      body: jsonEncode({
        'email': emailOrUsername,
        'username': emailOrUsername,
        'password': password,
      }),
    );
    if (res.statusCode == 200) {
      final d = _decode(res);
      // SimpleJWT-style tokens; be tolerant about key names.
      _access = d['access'] ?? d['access_token'] ?? d['token'];
      _refresh = d['refresh'] ?? d['refresh_token'];
      await _persist();
      return _access != null;
    }
    return false;
  }

  Future<bool> refreshAccess() async {
    if (_refresh == null) return false;
    final res = await http.post(
      AppConfig.api('auth/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': _refresh}),
    );
    if (res.statusCode == 200) {
      final d = _decode(res);
      _access = d['access'] ?? _access;
      if (d['refresh'] != null) _refresh = d['refresh'];
      await _persist();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    try {
      await _send('POST', 'auth/logout/', body: {'refresh': _refresh}, retry: false);
    } catch (_) {}
    await clearTokens();
  }

  Future<UserMini?> me() async {
    final res = await _send('GET', 'auth/me/');
    if (res.statusCode == 200) {
      final d = _decode(res);
      final user = d['user'] ?? d;
      return UserMini.fromJson(user);
    }
    return null;
  }

  // ── Rooms ──────────────────────────────────────────────────────────────────

  Future<List<ChatRoom>> rooms() async {
    final res = await _send('GET', 'rooms/');
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final list = d is List ? d : (d['rooms'] ?? d['results'] ?? d['_list'] ?? []);
      return (list as List).map((e) => ChatRoom.fromJson(e)).toList();
    }
    return [];
  }

  Future<ChatRoom?> directRoom(String userId) async {
    final res = await _send('POST', 'rooms/direct/', body: {'user_id': userId});
    if (res.statusCode == 200 || res.statusCode == 201) {
      final d = _decode(res);
      return ChatRoom.fromJson(d['room'] ?? d);
    }
    return null;
  }

  Future<List<ChatMessage>> messages(String roomId, {String? beforeId}) async {
    final q = beforeId != null ? '?before=$beforeId' : '';
    final res = await _send('GET', 'rooms/$roomId/messages/$q');
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final list = d is List ? d : (d['messages'] ?? d['results'] ?? d['_list'] ?? []);
      return (list as List).map((e) => ChatMessage.fromJson(e)).toList();
    }
    return [];
  }

  // ── File upload ─────────────────────────────────────────────────────────────

  /// Upload a picture or file to a room. Hits the server's
  /// rooms/<room_id>/upload/ endpoint with a multipart body. The server
  /// creates the ChatMessage and broadcasts it; the polling loop in the chat
  /// screen will then display it.
  Future<bool> uploadFile(String roomId, String filePath, {String caption = ''}) async {
    final uri = AppConfig.api('rooms/$roomId/upload/');
    final req = http.MultipartRequest('POST', uri);
    if (_access != null) req.headers['Authorization'] = 'Bearer $_access';
    req.fields['caption'] = caption;
    req.files.add(await http.MultipartFile.fromPath('file', filePath));

    final streamed = await req.send();
    if (streamed.statusCode == 401 && _refresh != null) {
      if (await refreshAccess()) {
        // Retry once with the refreshed token.
        return uploadFile(roomId, filePath, caption: caption);
      }
    }
    return streamed.statusCode == 200 || streamed.statusCode == 201;
  }

// This is a helper
  Future<http.Response?> httpGetAbsolute(String absoluteUrl, Map<String, String> headers) async {
    try {
      return await http.get(Uri.parse(absoluteUrl), headers: headers);
    } catch (e) {
      if (kDebugMode) debugPrint('httpGetAbsolute failed: $e');
      return null;
    }
  }


    // ── Files ───────────────────────────────────────────────────────────────────
 
  Future<List<RemoteFile>> files({String q = '', String category = '', String folder = ''}) async {
    final params = <String>[];
    if (q.isNotEmpty) params.add('q=${Uri.encodeQueryComponent(q)}');
    if (category.isNotEmpty) params.add('category=${Uri.encodeQueryComponent(category)}');
    if (folder.isNotEmpty) params.add('folder=${Uri.encodeQueryComponent(folder)}');
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
 
    final res = await _send('GET', 'files/$qs');
    if (res.statusCode == 200) {
      final d = _decode(res);
      final list = d['files'] ?? [];
      return (list as List).map((e) => RemoteFile.fromJson(e)).toList();
    }
    return [];
  }
 
  Future<RemoteFile?> fileDetail(String fileId) async {
    final res = await _send('GET', 'files/$fileId/');
    if (res.statusCode == 200) {
      return RemoteFile.fromJson(_decode(res));
    }
    return null;
  }
 
  // ── Signatures ───────────────────────────────────────────────────────────────
 
  Future<List<SignRequest>> signRequests({bool openOnly = true}) async {
    final res = await _send('GET', 'sign/requests/?status=${openOnly ? 'open' : 'all'}');
    if (res.statusCode == 200) {
      final d = _decode(res);
      final list = d['requests'] ?? [];
      return (list as List).map((e) => SignRequest.fromJson(e)).toList();
    }
    return [];
  }
 
  Future<SignDetail?> signDetail(String requestId) async {
    final res = await _send('GET', 'sign/requests/$requestId/');
    if (res.statusCode == 200) {
      return SignDetail.fromJson(_decode(res));
    }
    return null;
  }
 
  /// Fill one field. Returns true on success.
  Future<bool> signFillField(String requestId, String fieldId, String value) async {
    final res = await _send('POST', 'sign/requests/$requestId/fields/$fieldId/',
        body: {'value': value});
    return res.statusCode == 200;
  }
 
  /// Final submit. Returns null on success, or an error message.
  Future<String?> signSubmit(
    String requestId, {
    required String signatureData,
    required String signatureType, // draw | type
    bool saveSignature = false,
    String saveSignatureName = 'My Signature',
  }) async {
    final res = await _send('POST', 'sign/requests/$requestId/submit/', body: {
      'signature_data': signatureData,
      'signature_type': signatureType,
      'save_signature': saveSignature,
      'save_signature_name': saveSignatureName,
    });
    if (res.statusCode == 200) return null;
    final d = _decode(res);
    return d['error'] ?? 'Could not submit signature.';
  }
 
  Future<String?> signDecline(String requestId, String reason) async {
    final res = await _send('POST', 'sign/requests/$requestId/decline/',
        body: {'reason': reason});
    if (res.statusCode == 200) return null;
    final d = _decode(res);
    return d['error'] ?? 'Could not decline.';
  }
 
  /// The signing PDF needs the Authorization header. Returns the bytes, or null.
  Future<List<int>?> fetchSignPdf(String previewUrl) async {
    // previewUrl is an absolute URL returned by the server; fetch with auth.
    final headers = <String, String>{};
    if (accessToken != null) headers['Authorization'] = 'Bearer $accessToken';
    final res = await httpGetAbsolute(previewUrl, headers);
    if (res != null && res.statusCode == 200) return res.bodyBytes;
    return null;
  }

  // ── Messages ────────────────────────────────────────────────────────────────

  Future<bool> deleteMessage(String messageId) async {
    final res = await _send('DELETE', 'messages/$messageId/');
    return res.statusCode == 200 || res.statusCode == 204;
  }

  /// Edit a text message you sent. Returns true on success.
  Future<bool> editMessage(String messageId, String newContent) async {
    final res = await _send('PATCH', 'messages/$messageId/edit/',
        body: {'content': newContent});
    return res.statusCode == 200;
  }

  /// "Delete for me" — hide a message from your own view only. Others still
  /// see it. Returns true on success.
  Future<bool> hideMessage(String messageId) async {
    final res = await _send('POST', 'messages/$messageId/hide/', body: {});
    return res.statusCode == 200;
  }

  Future<List<ReactionSummary>> toggleReaction(String messageId, String emoji) async {
    final res = await _send('POST', 'messages/$messageId/react/', body: {'emoji': emoji});
    if (res.statusCode == 200) {
      final d = _decode(res);
      final list = d['reactions_summary'] ?? d['reactions'] ?? [];
      return (list as List).map((e) => ReactionSummary.fromJson(e)).toList();
    }
    return [];
  }

  // ── Polls ──────────────────────────────────────────────────────────────────

  Future<bool> createPoll(String roomId, String question, List<String> options,
      {bool allowMultiple = false, bool anonymous = false}) async {
    final res = await _send('POST', 'rooms/$roomId/polls/', body: {
      'question': question,
      'options': options,
      'allow_multiple': allowMultiple,
      'is_anonymous': anonymous,
    });
    return res.statusCode == 200 || res.statusCode == 201;
  }

  Future<Poll?> votePoll(String pollId, List<String> optionIds) async {
    final res = await _send('POST', 'polls/$pollId/vote/', body: {'options': optionIds});
    if (res.statusCode == 200) {
      final d = _decode(res);
      return Poll.fromJson(d['poll'] ?? d);
    }
    return null;
  }

  // ── Presence ─────────────────────────────────────────────────────────────────

  Future<void> heartbeat() async {
    try {
      await _send('POST', 'presence/heartbeat/', body: {});
    } catch (_) {}
  }

  Future<bool> isOnline(String userId) async {
    final res = await _send('GET', 'presence/$userId/');
    if (res.statusCode == 200) {
      final d = _decode(res);
      return d['online'] ?? d['is_online'] ?? false;
    }
    return false;
  }

  // ── Users ─────────────────────────────────────────────────────────────────────

  Future<List<UserMini>> searchUsers(String q) async {
    final res = await _send('GET', 'users/search/?q=${Uri.encodeQueryComponent(q)}');
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body);
      final list = d is List ? d : (d['results'] ?? d['users'] ?? d['_list'] ?? []);
      return (list as List).map((e) => UserMini.fromJson(e)).toList();
    }
    return [];
  }

  // ── Device push token ───────────────────────────────────────────────────────

  Future<void> registerDeviceToken(String token, {String platform = 'android'}) async {
    try {
      await _send('POST', 'device-tokens/', body: {'platform': platform, 'token': token});
    } catch (e) {
      if (kDebugMode) debugPrint('device token register failed: $e');
    }
  }

  // ── Tasks ───────────────────────────────────────────────────────────────────

  Future<List<TaskItem>> myTasks() async {
    final res = await _send('GET', 'tasks/');
    if (res.statusCode == 200) {
      final d = _decode(res);
      final list = d['tasks'] ?? [];
      return (list as List).map((e) => TaskItem.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<TaskItem>> myRecentClosedTasks() async {
    final res = await _send('GET', 'tasks/recent-closed/');
    if (res.statusCode == 200) {
      final d = _decode(res);
      final list = d['tasks'] ?? [];
      return (list as List).map((e) => TaskItem.fromJson(e)).toList();
    }
    return [];
  }

  Future<TaskItem?> taskDetail(String taskId) async {
    final res = await _send('GET', 'tasks/$taskId/');
    if (res.statusCode == 200) {
      return TaskItem.fromJson(_decode(res));
    }
    return null;
  }

  Future<bool> taskOnSite(String taskId, {double? lat, double? lng, String note = ''}) async {
    final res = await _send('POST', 'tasks/$taskId/on-site/', body: {
      if (lat != null) 'gps_latitude': lat.toStringAsFixed(6),
      if (lng != null) 'gps_longitude': lng.toStringAsFixed(6),
      'note': note,
    });
    return res.statusCode == 200;
  }

  Future<bool> taskClearOnSite(String taskId) async {
    final res = await _send('POST', 'tasks/$taskId/clear-on-site/', body: {});
    return res.statusCode == 200;
  }

  /// Returns null on success, or an error message string on failure.
  Future<String?> taskComplete(String taskId, String completionComment) async {
    final res = await _send('POST', 'tasks/$taskId/complete/',
        body: {'completion_comment': completionComment});
    if (res.statusCode == 200) return null;
    final d = _decode(res);
    return d['error'] ?? 'Could not complete the task.';
  }
}