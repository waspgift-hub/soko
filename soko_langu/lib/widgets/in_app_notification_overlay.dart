import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class InAppNotificationOverlay {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show({
    required BuildContext context,
    required String title,
    String body = '',
    String type = 'general',
    Map<String, dynamic>? data,
    VoidCallback? onTap,
    Duration duration = const Duration(seconds: 4),
  }) {
    dismiss();

    _entry = OverlayEntry(
      builder: (_) => _InAppNotificationBanner(
        title: title,
        body: body,
        type: type,
        data: data,
        onTap: onTap,
        onDismiss: dismiss,
      ),
    );

    Overlay.of(context).insert(_entry!);

    _timer = Timer(duration, dismiss);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _entry?.remove();
    _entry = null;
  }
}

class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic>? data;
  final VoidCallback? onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    this.body = '',
    required this.type,
    this.data,
    this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() => _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _iconColor() {
    switch (widget.type) {
      case 'payment':
      case 'escrow_release':
      case 'withdrawal':
        return const Color(0xFF40916C);
      case 'chat':
        return Colors.blue;
      case 'order':
      case 'boost':
        return Colors.orange;
      case 'disputed':
      case 'payment_failed':
        return Colors.red;
      default:
        return const Color(0xFF40916C);
    }
  }

  IconData _icon() {
    switch (widget.type) {
      case 'payment':
      case 'escrow_release':
      case 'withdrawal':
        return Icons.payment;
      case 'chat':
        return Icons.chat;
      case 'order':
        return Icons.shopping_bag;
      case 'boost':
        return Icons.rocket_launch;
      case 'disputed':
        return Icons.gavel;
      case 'payment_failed':
        return Icons.cancel;
      case 'refund':
        return Icons.money_off;
      case 'flash_sale':
        return Icons.flash_on;
      case 'product':
        return Icons.inventory_2;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.only(top: top, left: 12, right: 12),
            child: GestureDetector(
              onTap: () {
                widget.onDismiss();
                widget.onTap?.call();
              },
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
                  widget.onDismiss();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 100),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: Theme.of(context).brightness == Brightness.dark
                            ? [
                                Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                                Theme.of(context).colorScheme.surfaceContainerLow.withValues(alpha: 0.7),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.92),
                                Colors.white.withValues(alpha: 0.8),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _iconColor().withValues(alpha: 0.25),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _iconColor().withValues(alpha: 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: _iconColor().withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_icon(), color: _iconColor(), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.body.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.body,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: widget.onDismiss,
                        padding: const EdgeInsets.all(8),
                        constraints: const BoxConstraints(),
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}