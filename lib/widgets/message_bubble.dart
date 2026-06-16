import 'package:flutter/material.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../theme/eo_theme.dart';

/// A single chat message. The signature touch is the asymmetric corner: the
/// bubble's "tail" corner (bottom-right for me, bottom-left for them) is
/// squared while the other three are generously rounded.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.showSender,
    this.onReact,
    this.onReply,
    this.onVote,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool showSender;
  final void Function(String emoji)? onReact;
  final VoidCallback? onReply;
  final void Function(List<String> optionIds)? onVote;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = mine ? EoColors.signalTeal : EoColors.surface;
    final textColor = mine ? EoColors.onTeal : EoColors.ink;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine ? 20 : 5),
      bottomRight: Radius.circular(mine ? 5 : 20),
    );

    if (message.isDeleted) {
      return _systemLine('Message removed');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Column(
        crossAxisAlignment: align,
        children: [
          if (showSender && !mine && message.sender != null)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 3),
              child: Text(
                message.sender!.fullName,
                style: EoTheme.display(12.5, w: FontWeight.w600, color: EoColors.deepTeal),
              ),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: radius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.replyTo != null) _replyChip(mine),
                  if (message.poll != null)
                    _pollBlock(message.poll!, textColor)
                  else if (message.messageType == 'image' && message.fileUrl.isNotEmpty)
                    _imageBlock(context)
                  else if (message.messageType == 'file' && message.fileUrl.isNotEmpty)
                    _fileBlock(context, textColor)
                  else
                    _linkedText(message.content, textColor),
                  // Caption under an image/file, if any.
                  if ((message.messageType == 'image' || message.messageType == 'file') &&
                      message.content.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _linkedText(message.content, textColor, size: 14.5),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _time(message.createdAt),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.6),
                          fontSize: 10.5,
                        ),
                      ),
                      if (message.isEdited) ...[
                        const SizedBox(width: 5),
                        Text('edited',
                            style: TextStyle(
                                color: textColor.withValues(alpha: 0.6),
                                fontSize: 10.5,
                                fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (message.reactions.isNotEmpty) _reactionRow(),
        ],
      ),
    );
  }

  /// Renders text with clickable links. URLs open in the browser.
  Widget _linkedText(String text, Color textColor, {double size = 15.5}) {
    return Linkify(
      text: text,
      onOpen: (link) async {
        final uri = Uri.tryParse(link.url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      style: TextStyle(color: textColor, fontSize: size, height: 1.32),
      linkStyle: TextStyle(
        color: textColor == EoColors.onTeal ? Colors.white : EoColors.deepTeal,
        decoration: TextDecoration.underline,
        fontSize: size,
        height: 1.32,
      ),
      options: const LinkifyOptions(humanize: false),
    );
  }

  Widget _replyChip(bool mine) {
    final r = message.replyTo!;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: (mine ? EoColors.onTeal : EoColors.deepTeal).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: EoColors.deepTeal.withValues(alpha: 0.5), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(r.senderName,
              style: EoTheme.display(11.5, w: FontWeight.w600, color: mine ? EoColors.onTeal : EoColors.deepTeal)),
          Text(r.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: (mine ? EoColors.onTeal : EoColors.ink).withValues(alpha: 0.85))),
        ],
      ),
    );
  }

  Widget _imageBlock(BuildContext context) {
    return GestureDetector(
      onTap: () => _openImageViewer(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          message.fileUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              height: 160,
              width: 200,
              alignment: Alignment.center,
              color: EoColors.sandDeep,
              child: const CircularProgressIndicator(color: EoColors.deepTeal, strokeWidth: 2),
            );
          },
          errorBuilder: (_, __, ___) => _fileBlock(context, EoColors.ink),
        ),
      ),
    );
  }

  void _openImageViewer(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            IconButton(
              icon: const Icon(Icons.download_rounded, color: Colors.white),
              tooltip: 'Open / download',
              onPressed: () => _downloadFile(context),
            ),
          ],
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(message.fileUrl, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
  }

  Widget _fileBlock(BuildContext context, Color textColor) {
    return GestureDetector(
      onTap: () => _downloadFile(context),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: textColor, size: 22),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(message.fileName.isEmpty ? 'Attachment' : message.fileName,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.fileSize > 0)
                      Text(_size(message.fileSize), style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
                    const SizedBox(width: 6),
                    Icon(Icons.download_rounded, size: 13, color: textColor.withValues(alpha: 0.6)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadFile(BuildContext context) async {
    final url = message.fileUrl;
    if (url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file.')),
      );
    }
  }

  Widget _pollBlock(Poll poll, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Icon(Icons.bar_chart_rounded, size: 18, color: textColor),
          const SizedBox(width: 6),
          Flexible(child: Text(poll.question, style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 15))),
        ]),
        const SizedBox(height: 8),
        ...poll.options.map((o) {
          final pct = poll.totalVotes == 0 ? 0.0 : o.voteCount / poll.totalVotes;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              onTap: poll.isEffectivelyClosed ? null : () => onVote?.call([o.id]),
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                children: [
                  Container(
                    height: 34,
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: pct.clamp(0.0, 1.0),
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: EoColors.deepTeal.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        if (o.votedByMe) Icon(Icons.check_circle, size: 15, color: textColor),
                        if (o.votedByMe) const SizedBox(width: 5),
                        Expanded(child: Text(o.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: textColor, fontSize: 13.5))),
                        Text('${o.voteCount}', style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        Text('${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}${poll.isEffectivelyClosed ? ' • closed' : ''}',
            style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 11)),
      ],
    );
  }

  Widget _reactionRow() {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
      child: Wrap(
        spacing: 5,
        children: message.reactions.map((r) {
          return GestureDetector(
            onTap: () => onReact?.call(r.emoji),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: r.mine ? EoColors.signalTeal.withValues(alpha: 0.18) : EoColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: r.mine ? EoColors.signalTeal : EoColors.divider),
              ),
              child: Text('${r.emoji} ${r.count}', style: const TextStyle(fontSize: 12)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _systemLine(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(text,
              style: const TextStyle(color: EoColors.inkSoft, fontStyle: FontStyle.italic, fontSize: 12.5)),
        ),
      );

  static String _time(DateTime? dt) {
    if (dt == null) return '';
    return DateFormat('HH:mm').format(dt.toLocal());
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}