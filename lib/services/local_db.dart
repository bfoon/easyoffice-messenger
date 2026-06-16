import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/models.dart';

/// Local SQLite cache for rooms, messages, and users.
///
/// Design: local-first. The UI reads from here instantly, then the network
/// layer refreshes from the server and writes back here. The server stays the
/// source of truth; this is a cache, not a replacement.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'easyoffice_messenger.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE rooms (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            data TEXT NOT NULL,
            created_at TEXT
          )
        ''');
        await db.execute('CREATE INDEX idx_messages_room ON messages(room_id)');
        await db.execute('''
          CREATE TABLE users (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  // ── Rooms ──────────────────────────────────────────────────────────────

  Future<void> saveRooms(List<ChatRoom> rooms) async {
    final db = await _database;
    final batch = db.batch();
    for (final r in rooms) {
      batch.insert(
        'rooms',
        {
          'id': r.id,
          'data': jsonEncode(_roomToJson(r)),
          'updated_at': r.updatedAt?.toIso8601String() ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatRoom>> loadRooms() async {
    final db = await _database;
    final rows = await db.query('rooms', orderBy: 'updated_at DESC');
    return rows
        .map((row) => ChatRoom.fromJson(jsonDecode(row['data'] as String)))
        .toList();
  }

  // ── Messages ───────────────────────────────────────────────────────────

  Future<void> saveMessages(String roomId, List<ChatMessage> messages) async {
    final db = await _database;
    final batch = db.batch();
    for (final m in messages) {
      batch.insert(
        'messages',
        {
          'id': m.id,
          'room_id': roomId,
          'data': jsonEncode(_messageToJson(m)),
          'created_at': m.createdAt?.toIso8601String() ?? '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<ChatMessage>> loadMessages(String roomId) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where: 'room_id = ?',
      whereArgs: [roomId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => ChatMessage.fromJson(jsonDecode(row['data'] as String)))
        .toList();
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await _database;
    await db.delete('messages', where: 'id = ?', whereArgs: [messageId]);
  }

  // ── Users ──────────────────────────────────────────────────────────────

  Future<void> saveUsers(List<UserMini> users) async {
    final db = await _database;
    final batch = db.batch();
    for (final u in users) {
      batch.insert(
        'users',
        {'id': u.id, 'data': jsonEncode(_userToJson(u))},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<UserMini>> loadUsers() async {
    final db = await _database;
    final rows = await db.query('users');
    return rows
        .map((row) => UserMini.fromJson(jsonDecode(row['data'] as String)))
        .toList();
  }

  // ── Clear (on logout) ────────────────────────────────────────────────────

  Future<void> clearAll() async {
    final db = await _database;
    await db.delete('rooms');
    await db.delete('messages');
    await db.delete('users');
  }

  // ── JSON encoders (mirror the model fields so reload round-trips) ────────

  Map<String, dynamic> _userToJson(UserMini u) => {
        'id': u.id,
        'username': u.username,
        'full_name': u.fullName,
        'initials': u.initials,
        'avatar_url': u.avatarUrl,
      };

  Map<String, dynamic> _roomToJson(ChatRoom r) => {
        'id': r.id,
        'name': r.name,
        'room_type': r.roomType,
        'title': r.title,
        'avatar_url': r.avatarUrl,
        'initials': r.initials,
        'other_user': r.otherUser == null ? null : _userToJson(r.otherUser!),
        'is_archived': r.isArchived,
        'is_readonly': r.isReadonly,
        'unread': r.unread,
        'member_count': r.memberCount,
        'last_message': r.lastMessage == null
            ? null
            : {
                'preview': r.lastMessage!.preview,
                'sender_name': r.lastMessage!.senderName,
                'created_at': r.lastMessage!.createdAt?.toIso8601String(),
              },
        'updated_at': r.updatedAt?.toIso8601String(),
        'members': r.members.map(_userToJson).toList(),
      };

  Map<String, dynamic> _messageToJson(ChatMessage m) => {
        'id': m.id,
        'room_id': m.roomId,
        'sender': m.sender == null ? null : _userToJson(m.sender!),
        'content': m.content,
        'message_type': m.messageType,
        'file_url': m.fileUrl,
        'file_name': m.fileName,
        'file_size': m.fileSize,
        'reactions_summary': m.reactions
            .map((r) => {'emoji': r.emoji, 'count': r.count, 'mine': r.mine})
            .toList(),
        'is_deleted': m.isDeleted,
        'is_edited': m.isEdited,
        'created_at': m.createdAt?.toIso8601String(),
        'reply_to': m.replyTo == null
            ? null
            : {
                'id': m.replyTo!.id,
                'sender_name': m.replyTo!.senderName,
                'content': m.replyTo!.content,
                'message_type': m.replyTo!.messageType,
              },
        'poll': m.poll == null ? null : _pollToJson(m.poll!),
        'is_mine': m.isMine,
      };

  Map<String, dynamic> _pollToJson(Poll poll) => {
        'id': poll.id,
        'question': poll.question,
        'allow_multiple': poll.allowMultiple,
        'is_anonymous': poll.isAnonymous,
        'allow_vote_change': poll.allowVoteChange,
        'is_closed': poll.isClosed,
        'is_effectively_closed': poll.isEffectivelyClosed,
        'total_votes': poll.totalVotes,
        'options': poll.options
            .map((o) => {
                  'id': o.id,
                  'text': o.text,
                  'vote_count': o.voteCount,
                  'voted_by_me': o.votedByMe,
                })
            .toList(),
      };
}