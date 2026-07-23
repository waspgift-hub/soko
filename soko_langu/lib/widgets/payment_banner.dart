import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'google_loading.dart';
import '../extensions/context_tr.dart';
import '../services/api_config.dart';

enum PaymentBannerType { success, failed }

class PaymentBanner {
  static OverlayEntry? _entry;
  static Timer? _timer;

  static void show({
    required BuildContext context,
    required PaymentBannerType type,
    required String title,
    String? subtitle,
    String? amount,
    Duration duration = const Duration(seconds: 4),
  }) {
    dismiss();

    _entry = OverlayEntry(
      builder: (_) => _PaymentBanner(
        type: type,
        title: title,
        subtitle: subtitle,
        amount: amount,
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

class _PaymentBanner extends StatefulWidget {
  final PaymentBannerType type;
  final String title;
  final String? subtitle;
  final String? amount;
  final VoidCallback onDismiss;

  const _PaymentBanner({
    required this.type,
    required this.title,
    this.subtitle,
    this.amount,
    required this.onDismiss,
  });

  @override
  State<_PaymentBanner> createState() => _PaymentBannerState();
}

class _PaymentBannerState extends State<_PaymentBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.6),
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

  Color _accentColor() => widget.type == PaymentBannerType.success
      ? const Color(0xFF2D9F4E)
      : const Color(0xFFE53935);

  IconData _icon() => widget.type == PaymentBannerType.success
      ? Icons.check_circle_rounded
      : Icons.cancel_rounded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom + 16;
    final accent = _accentColor();

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: bottom),
            child: GestureDetector(
              onTap: widget.onDismiss,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? [
                                accent.withValues(alpha: 0.2),
                                cs.surface.withValues(alpha: 0.25),
                              ]
                            : [
                                Colors.white.withValues(alpha: 0.85),
                                Colors.white.withValues(alpha: 0.7),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accent.withValues(alpha: isDark ? 0.4 : 0.3),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: isDark ? 0.3 : 0.15),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_icon(), color: accent, size: 26),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isDark ? Colors.white : cs.onSurface,
                                ),
                              ),
                              if (widget.subtitle != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : cs.onSurface.withValues(alpha: 0.6),
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (widget.amount != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            constraints: const BoxConstraints(maxWidth: 140),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              widget.amount!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: accent,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(Icons.close, size: 18),
                          onPressed: widget.onDismiss,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.5)
                      : cs.onSurface.withValues(alpha: 0.4),
                ),
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

class RealtimePaymentBanner {
  static OverlayEntry? _entry;

  static void show({
    required BuildContext context,
    required String orderId,
    required List<String> successStatuses,
    required String processingTitle,
    required String successTitle,
    String? successSubtitle,
    required String failedTitle,
    VoidCallback? onSuccess,
    void Function(String msg)? onError,
  }) {
    dismiss();
    _entry = OverlayEntry(
      builder: (_) => _RealtimePaymentBannerWidget(
        orderId: orderId,
        successStatuses: successStatuses,
        processingTitle: processingTitle,
        successTitle: successTitle,
        successSubtitle: successSubtitle,
        failedTitle: failedTitle,
        onSuccess: onSuccess,
        onError: onError,
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  static void dismiss() {
    _entry?.remove();
    _entry = null;
  }
}

class _RealtimePaymentBannerWidget extends StatefulWidget {
  final String orderId;
  final List<String> successStatuses;
  final String processingTitle;
  final String successTitle;
  final String? successSubtitle;
  final String failedTitle;
  final VoidCallback? onSuccess;
  final void Function(String msg)? onError;

  const _RealtimePaymentBannerWidget({
    required this.orderId,
    required this.successStatuses,
    required this.processingTitle,
    required this.successTitle,
    this.successSubtitle,
    required this.failedTitle,
    this.onSuccess,
    this.onError,
  });

  @override
  State<_RealtimePaymentBannerWidget> createState() =>
      _RealtimePaymentBannerWidgetState();
}

class _RealtimePaymentBannerWidgetState
    extends State<_RealtimePaymentBannerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  bool _handled = false;
  String _statusText = '';
  Timer? _timeoutTimer;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _animCtrl.forward();

    _startTimeoutTimer();
    _startPolling();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _timeoutTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(const Duration(seconds: 60), () {
      if (!_handled && mounted) {
        setState(() {
          _statusText = context.tr('payment_timeout');
        });
        widget.onError?.call('Payment timeout - no confirmation from Mongike');
        _handleDone();
      }
    });
  }

  Future<void> _pollServerStatus() async {
    if (_handled) return;
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final resp = await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/api/transaction-status/${widget.orderId}'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final result = jsonDecode(resp.body) as Map<String, dynamic>;
        if (result['success'] == true) {
          final status = result['status'] as String? ?? 'pending';
          if (status == 'failed' || status == 'cancelled') {
            final reason = result['failureReason'] as String? ?? context.tr('payment_failed_try_again');
            if (mounted && !_handled) {
              widget.onError?.call(reason);
              _handleDone();
            }
          } else if (widget.successStatuses.contains(status)) {
            if (mounted && !_handled) {
              widget.onSuccess?.call();
              _handleDone();
            }
          }
        }
      }
    } catch (_) {}
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      _pollServerStatus();
    });
  }

  void _handleDone() {
    if (_handled) return;
    _handled = true;
    _timeoutTimer?.cancel();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) RealtimePaymentBanner.dismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom + 16;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final status = data?['status'] as String? ?? 'pending';

        final isSuccess = widget.successStatuses.contains(status);
        final isFailed = status == 'failed' || status == 'cancelled';
        final isProcessing = !isSuccess && !isFailed;

        if (isSuccess && !_handled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSuccess?.call();
            _handleDone();
          });
        }

        if (isFailed && !_handled) {
          final reason =
              data?['failureReason'] as String? ??
              data?['errorMessage'] as String? ??
              context.tr('payment_failed_try_again');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _statusText = reason;
            widget.onError?.call(reason);
            _handleDone();
          });
        }

        Color accent;
        IconData icon;
        String title;
        Widget? trailing;

        if (isSuccess) {
          accent = const Color(0xFF2D9F4E);
          icon = Icons.check_circle_rounded;
          title = widget.successTitle;
        } else if (isFailed) {
          accent = const Color(0xFFE53935);
          icon = Icons.cancel_rounded;
          title = widget.failedTitle;
        } else {
          accent = cs.primary;
          icon = Icons.payment_rounded;
          title = widget.processingTitle;
          trailing = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GoogleLoading(size: 22, strokeWidth: 2.5),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: RealtimePaymentBanner.dismiss,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, size: 14, color: Colors.white.withValues(alpha: 0.7)),
                ),
              ),
            ],
          );
        }

        return FadeTransition(
          opacity: _fadeAnim,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: bottom + 88,
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: GestureDetector(
                  onTap: () {
                    if (isSuccess || isFailed) RealtimePaymentBanner.dismiss();
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    accent.withValues(alpha: 0.25),
                                    cs.surface.withValues(alpha: 0.3),
                                  ]
                                : [
                                    Colors.white.withValues(alpha: 0.92),
                                    Colors.white.withValues(alpha: 0.78),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: accent.withValues(
                              alpha: isDark ? 0.4 : 0.25,
                            ),
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(
                                alpha: isDark ? 0.25 : 0.12,
                              ),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 400),
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: AnimatedSwitcher(
                                duration:
                                    const Duration(milliseconds: 300),
                                child: Icon(
                                  icon,
                                  key: ValueKey(icon),
                                  color: accent,
                                  size: 26,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: isDark
                                          ? Colors.white
                                          : cs.onSurface,
                                    ),
                                  ),
                                  if (isProcessing)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        context.tr('check_phone_enter_pin'),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.6)
                                              : cs.onSurface.withValues(alpha: 0.6),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (isSuccess &&
                                      widget.successSubtitle != null)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(top: 2),
                                      child: Text(
                                        widget.successSubtitle!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.6,
                                                )
                                              : cs.onSurface.withValues(
                                                  alpha: 0.6,
                                                ),
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (_statusText.isNotEmpty &&
                                      (isFailed || _handled))
                                    Text(
                                      _statusText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.7,
                                              )
                                            : accent,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (trailing != null) ...[
                              const SizedBox(width: 8),
                              Flexible(child: trailing),
                            ],
                            if (isSuccess || isFailed)
                              Flexible(
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: RealtimePaymentBanner.dismiss,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : cs.onSurface.withValues(alpha: 0.4),
                                ),
                              ),
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
      },
    );
  }
}
