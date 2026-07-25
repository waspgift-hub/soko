import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'google_loading.dart';
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
      builder: (_) => _PaymentBannerContent(
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

class _PaymentBannerContent extends StatefulWidget {
  final PaymentBannerType type;
  final String title;
  final String? subtitle;
  final String? amount;
  final VoidCallback onDismiss;

  const _PaymentBannerContent({
    required this.type,
    required this.title,
    this.subtitle,
    this.amount,
    required this.onDismiss,
  });

  @override
  State<_PaymentBannerContent> createState() => _PaymentBannerContentState();
}

class _PaymentBannerContentState extends State<_PaymentBannerContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accent => widget.type == PaymentBannerType.success
      ? const Color(0xFF2D9F4E)
      : const Color(0xFFE53935);

  IconData get _icon => widget.type == PaymentBannerType.success
      ? Icons.check_circle_rounded
      : Icons.cancel_rounded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom + 24;

    return Stack(
      children: [
        GestureDetector(
          onTap: widget.onDismiss,
          child: FadeTransition(
            opacity: _fade,
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
        ),
        SlideTransition(
          position: _slide,
          child: FadeTransition(
            opacity: _fade,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(left: 32, right: 32, bottom: bottom),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: widget.onDismiss,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? cs.surface.withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _accent.withValues(alpha: isDark ? 0.5 : 0.25),
                              width: 1,
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: _accent.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(_icon, color: _accent, size: 26),
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
                                    constraints: const BoxConstraints(maxWidth: 120),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      widget.amount!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: _accent,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: widget.onDismiss,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
            ),
          ),
        ),
      ],
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
    String? processingSubtitle,
    VoidCallback? onSuccess,
    void Function(String msg)? onError,
  }) {
    dismiss();
    _entry = OverlayEntry(
      builder: (_) => _RealtimeBanner(
        orderId: orderId,
        successStatuses: successStatuses,
        processingTitle: processingTitle,
        successTitle: successTitle,
        successSubtitle: successSubtitle,
        failedTitle: failedTitle,
        processingSubtitle: processingSubtitle,
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

class _RealtimeBanner extends StatefulWidget {
  final String orderId;
  final List<String> successStatuses;
  final String processingTitle;
  final String successTitle;
  final String? successSubtitle;
  final String failedTitle;
  final String? processingSubtitle;
  final VoidCallback? onSuccess;
  final void Function(String msg)? onError;

  const _RealtimeBanner({
    required this.orderId,
    required this.successStatuses,
    required this.processingTitle,
    required this.successTitle,
    this.successSubtitle,
    required this.failedTitle,
    this.processingSubtitle,
    this.onSuccess,
    this.onError,
  });

  @override
  State<_RealtimeBanner> createState() => _RealtimeBannerState();
}

class _RealtimeBannerState extends State<_RealtimeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  bool _done = false;
  String _errorMsg = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    _startPolling();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 7), (_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    if (_done) return;
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
            final reason = result['failureReason'] as String? ?? 'Payment failed';
            if (mounted && !_done) {
              widget.onError?.call(reason);
              _finish();
            }
          } else if (widget.successStatuses.contains(status)) {
            if (mounted && !_done) {
              widget.onSuccess?.call();
              _finish();
            }
          }
        }
      }
    } catch (_) {}
  }

  void _finish() {
    if (_done) return;
    _done = true;
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) RealtimePaymentBanner.dismiss();
    });
  }

  Color _accent(bool ok, bool fail) {
    if (ok) return const Color(0xFF2D9F4E);
    if (fail) return const Color(0xFFE53935);
    return const Color(0xFF2D6A4F);
  }

  IconData _icon(bool ok, bool fail) {
    if (ok) return Icons.check_circle_rounded;
    if (fail) return Icons.cancel_rounded;
    return Icons.payment_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).padding.bottom + 24;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final status = data?['status'] as String? ?? 'pending';

        final isOk = widget.successStatuses.contains(status);
        final isFail = status == 'failed' || status == 'cancelled';
        final isLoading = !isOk && !isFail;

        if (isOk && !_done) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            widget.onSuccess?.call();
            _finish();
          });
        }
        if (isFail && !_done) {
          final reason = data?['failureReason'] as String? ??
              data?['errorMessage'] as String? ??
              'Payment failed';
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _errorMsg = reason;
            widget.onError?.call(reason);
            _finish();
          });
        }

        final accent = _accent(isOk, isFail);
        final icon = _icon(isOk, isFail);
        final title = isOk
            ? widget.successTitle
            : isFail
                ? widget.failedTitle
                : widget.processingTitle;
        final subtitle = isLoading
            ? widget.processingSubtitle
            : isOk
                ? widget.successSubtitle
                : _errorMsg.isNotEmpty ? _errorMsg : null;

        return FadeTransition(
          opacity: _fade,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (isOk || isFail) RealtimePaymentBanner.dismiss();
                },
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(left: 32, right: 32, bottom: bottom),
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: GestureDetector(
                      onTap: () {
                        if (isOk || isFail) RealtimePaymentBanner.dismiss();
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? cs.surface.withValues(alpha: 0.5)
                                  : Colors.white.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: accent.withValues(alpha: isDark ? 0.5 : 0.25),
                                width: 1,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 300),
                                      child: Icon(icon, key: ValueKey(icon), color: accent, size: 24),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          title,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: isDark ? Colors.white : cs.onSurface,
                                          ),
                                        ),
                                        if (subtitle != null && subtitle.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              subtitle,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: isDark
                                                    ? Colors.white.withValues(alpha: 0.7)
                                                    : isFail
                                                        ? accent
                                                        : cs.onSurface.withValues(alpha: 0.6),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isLoading)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: GoogleLoading(size: 22, strokeWidth: 2.5),
                                      ),
                                    ),
                                  if (isOk || isFail)
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: RealtimePaymentBanner.dismiss,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
              ),
            ],
          ),
        );
      },
    );
  }
}
