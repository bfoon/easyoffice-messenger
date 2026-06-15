import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/eo_theme.dart';

/// Circular avatar that shows initials over a teal field, or a network image.
/// When [online] is true, a coral ring gently breathes around it — the app's
/// one deliberate piece of ambient motion.
class EoAvatar extends StatefulWidget {
  const EoAvatar({
    super.key,
    required this.initials,
    this.imageUrl = '',
    this.size = 46,
    this.online = false,
  });

  final String initials;
  final String imageUrl;
  final double size;
  final bool online;

  @override
  State<EoAvatar> createState() => _EoAvatarState();
}

class _EoAvatarState extends State<EoAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.online) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant EoAvatar old) {
    super.didUpdateWidget(old);
    if (widget.online && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.online && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final ringWidth = widget.online ? (2.0 + _c.value * 1.6) : 0.0;
        final ringOpacity = widget.online ? (0.5 + _c.value * 0.5) : 0.0;
        return Container(
          width: s,
          height: s,
          padding: EdgeInsets.all(widget.online ? 3 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: EoColors.coral.withValues(alpha: ringOpacity),
              width: ringWidth,
            ),
          ),
          child: child,
        );
      },
      child: ClipOval(
        child: widget.imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: widget.imageUrl,
                width: s,
                height: s,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initialsBox(),
                errorWidget: (_, __, ___) => _initialsBox(),
              )
            : _initialsBox(),
      ),
    );
  }

  Widget _initialsBox() {
    return Container(
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [EoColors.deepTeal, EoColors.signalTeal],
        ),
      ),
      child: Text(
        widget.initials,
        style: EoTheme.display(widget.size * 0.34, color: EoColors.onTeal),
      ),
    );
  }
}
