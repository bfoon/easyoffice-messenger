// Models mirror the DRF serializers in apps/mobile_api/serializers.py so the
// JSON shapes line up exactly.

class UserMini {
  final String id;
  final String username;
  final String fullName;
  final String initials;
  final String avatarUrl;

  UserMini({
    required this.id,
    required this.username,
    required this.fullName,
    required this.initials,
    required this.avatarUrl,
  });

  factory UserMini.fromJson(Map<String, dynamic> j) => UserMini(
        id: '${j['id']}',
        username: j['username'] ?? '',
        fullName: j['full_name'] ?? '',
        initials: j['initials'] ?? '?',
        avatarUrl: j['avatar_url'] ?? '',
      );
}

class ReactionSummary {
  final String emoji;
  final int count;
  final bool mine;
  ReactionSummary({required this.emoji, required this.count, required this.mine});

  factory ReactionSummary.fromJson(Map<String, dynamic> j) => ReactionSummary(
        emoji: j['emoji'] ?? '',
        count: j['count'] ?? 0,
        mine: j['mine'] ?? false,
      );
}

class PollOption {
  final String id;
  final String text;
  final int voteCount;
  final bool votedByMe;
  PollOption({required this.id, required this.text, required this.voteCount, required this.votedByMe});

  factory PollOption.fromJson(Map<String, dynamic> j) => PollOption(
        id: '${j['id']}',
        text: j['text'] ?? '',
        voteCount: j['vote_count'] ?? 0,
        votedByMe: j['voted_by_me'] ?? false,
      );
}

class Poll {
  final String id;
  final String question;
  final bool allowMultiple;
  final bool isAnonymous;
  final bool allowVoteChange;
  final bool isClosed;
  final bool isEffectivelyClosed;
  final int totalVotes;
  final List<PollOption> options;

  Poll({
    required this.id,
    required this.question,
    required this.allowMultiple,
    required this.isAnonymous,
    required this.allowVoteChange,
    required this.isClosed,
    required this.isEffectivelyClosed,
    required this.totalVotes,
    required this.options,
  });

  factory Poll.fromJson(Map<String, dynamic> j) => Poll(
        id: '${j['id']}',
        question: j['question'] ?? '',
        allowMultiple: j['allow_multiple'] ?? false,
        isAnonymous: j['is_anonymous'] ?? false,
        allowVoteChange: j['allow_vote_change'] ?? true,
        isClosed: j['is_closed'] ?? false,
        isEffectivelyClosed: j['is_effectively_closed'] ?? false,
        totalVotes: j['total_votes'] ?? 0,
        options: ((j['options'] ?? []) as List)
            .map((o) => PollOption.fromJson(o))
            .toList(),
      );
}

class ReplyPreview {
  final String id;
  final String senderName;
  final String content;
  final String messageType;
  ReplyPreview({required this.id, required this.senderName, required this.content, required this.messageType});

  factory ReplyPreview.fromJson(Map<String, dynamic> j) => ReplyPreview(
        id: '${j['id']}',
        senderName: j['sender_name'] ?? '',
        content: j['content'] ?? '',
        messageType: j['message_type'] ?? 'text',
      );
}

class ChatMessage {
  final String id;
  final String roomId;
  final UserMini? sender;
  final String content;
  final String messageType;
  final String fileUrl;
  final String fileName;
  final int fileSize;
  final List<ReactionSummary> reactions;
  final bool isDeleted;
  final bool isEdited;
  final DateTime? createdAt;
  final ReplyPreview? replyTo;
  final Poll? poll;
  bool isMine;

  ChatMessage({
    required this.id,
    required this.roomId,
    required this.sender,
    required this.content,
    required this.messageType,
    required this.fileUrl,
    required this.fileName,
    required this.fileSize,
    required this.reactions,
    required this.isDeleted,
    required this.isEdited,
    required this.createdAt,
    required this.replyTo,
    required this.poll,
    required this.isMine,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    DateTime? created;
    final raw = j['created_at'];
    if (raw is String && raw.isNotEmpty) {
      created = DateTime.tryParse(raw);
    }
    return ChatMessage(
      id: '${j['id']}',
      roomId: '${j['room_id'] ?? ''}',
      sender: j['sender'] is Map<String, dynamic>
          ? UserMini.fromJson(j['sender'])
          : null,
      content: j['content'] ?? '',
      messageType: j['message_type'] ?? 'text',
      fileUrl: j['file_url'] ?? '',
      fileName: j['file_name'] ?? '',
      fileSize: j['file_size'] ?? 0,
      reactions: ((j['reactions_summary'] ?? []) as List)
          .map((r) => ReactionSummary.fromJson(r))
          .toList(),
      isDeleted: j['is_deleted'] ?? false,
      isEdited: j['is_edited'] ?? false,
      createdAt: created,
      replyTo: j['reply_to'] is Map<String, dynamic>
          ? ReplyPreview.fromJson(j['reply_to'])
          : null,
      poll: j['poll'] is Map<String, dynamic> ? Poll.fromJson(j['poll']) : null,
      isMine: j['is_mine'] ?? false,
    );
  }
}

class LastMessage {
  final String preview;
  final String senderName;
  final DateTime? createdAt;
  LastMessage({required this.preview, required this.senderName, required this.createdAt});

  factory LastMessage.fromJson(Map<String, dynamic> j) => LastMessage(
        preview: j['preview'] ?? '',
        senderName: j['sender_name'] ?? '',
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}'),
      );
}

class ChatRoom {
  final String id;
  final String name;
  final String roomType;
  final String title;
  final String avatarUrl;
  final String initials;
  final UserMini? otherUser;
  final bool isArchived;
  final bool isReadonly;
  final int unread;
  final int memberCount;
  final LastMessage? lastMessage;
  final DateTime? updatedAt;
  final List<UserMini> members;

  ChatRoom({
    required this.id,
    required this.name,
    required this.roomType,
    required this.title,
    required this.avatarUrl,
    required this.initials,
    required this.otherUser,
    required this.isArchived,
    required this.isReadonly,
    required this.unread,
    required this.memberCount,
    required this.lastMessage,
    required this.updatedAt,
    required this.members,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> j) => ChatRoom(
        id: '${j['id']}',
        name: j['name'] ?? '',
        roomType: j['room_type'] ?? 'group',
        title: j['title'] ?? (j['name'] ?? 'Chat'),
        avatarUrl: j['avatar_url'] ?? '',
        initials: j['initials'] ?? '#',
        otherUser: j['other_user'] is Map<String, dynamic>
            ? UserMini.fromJson(j['other_user'])
            : null,
        isArchived: j['is_archived'] ?? false,
        isReadonly: j['is_readonly'] ?? false,
        unread: j['unread'] ?? 0,
        memberCount: j['member_count'] ?? 0,
        lastMessage: j['last_message'] is Map<String, dynamic>
            ? LastMessage.fromJson(j['last_message'])
            : null,
        updatedAt: DateTime.tryParse('${j['updated_at'] ?? ''}'),
        members: ((j['members'] ?? []) as List)
            .map((e) => UserMini.fromJson(e))
            .toList(),
      );

  bool get isDirect => roomType == 'direct';
}