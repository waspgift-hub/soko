import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../extensions/context_tr.dart';
import '../services/ads/ad_config.dart';
import '../services/ads/ad_manager.dart';

/// Rewarded-ad gate for marketplace actions.
///
/// The gate itself is a screen concern; the ad is not. Every ad decision —
/// eligibility, Blue Tick exemption, frequency, backoff, lifecycle — belongs to
/// [AdManager], and this widget only asks "may the user proceed?".
///
/// Correctness fixes carried over from the previous hand-rolled dialog:
/// * The dialog future is always completed. Previously a system back press, or a
///   torn-down context during `preload()`, left the `Completer` unresolved and
///   the awaiting action (unlocking a contact, creating a flash sale) hung
///   forever with no way out.
/// * A re-entrancy guard means two rapid taps cannot overwrite the callback on
///   a shared `RewardedAd` instance and orphan the first future.
class RewardedAdGate {
  RewardedAdGate._();

  static bool _inFlight = false;

  /// Runs the gate for [action]. Returns true when the user may proceed.
  ///
  /// [placement] identifies the ad slot for frequency accounting. [action] is
  /// the persisted "already unlocked" key.
  static Future<bool> require(
    BuildContext context, {
    required String action,
    required AdPlacement placement,
    String? title,
    String? message,
  }) async {
    final manager = context.read<AdManager>();

    // Ad-exempt sellers are never asked to watch anything.
    if (manager.verification.isSelfAdExempt &&
        manager.config.adsExemptBlueTickEnabled) {
      return true;
    }
    if (_inFlight) return false;
    if (await manager.hasPassedGate(action)) return true;

    _inFlight = true;
    try {
      final passed = await _showGateDialog(
        context,
        manager,
        placement,
        title,
        message,
      );
      if (passed) await manager.markGatePassed(action);
      return passed;
    } finally {
      _inFlight = false;
    }
  }

  static Future<bool> _showGateDialog(
    BuildContext context,
    AdManager manager,
    AdPlacement placement,
    String? title,
    String? message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      // canPop: false blocks the system back button, which the old dialog
      // allowed — that was the hang path.
      builder: (ctx) => _GateDialog(
        manager: manager,
        placement: placement,
        title: title,
        message: message,
      ),
    );
    // showDialog resolves to null if the route is popped programmatically
    // (e.g. by a parent Navigator), so the outcome is normalised to a bool.
    return result ?? false;
  }
}

class _GateDialog extends StatefulWidget {
  const _GateDialog({
    required this.manager,
    required this.placement,
    this.title,
    this.message,
  });

  final AdManager manager;
  final AdPlacement placement;
  final String? title;
  final String? message;

  @override
  State<_GateDialog> createState() => _GateDialogState();
}

class _GateDialogState extends State<_GateDialog> {
  bool _isLoading = false;
  bool _unavailable = false;

  Future<void> _watch() async {
    if (mounted) setState(() => _isLoading = true);
    final earned = await widget.manager.showRewarded(
      widget.placement,
      onUserEarned: _recordRewardedAdView,
    );
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      // Distinguish "ad failed" from "user cancelled" so the copy is honest.
      _unavailable = !earned && !widget.manager.isRewardedLoaded;
    });
    Navigator.of(context).pop(earned);
  }

  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.play_circle_outline, color: cs.tertiary, size: 28),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title ?? context.tr('watch_ad'))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message ?? context.tr('ad_required')),
            const SizedBox(height: 8),
            Text(
              _unavailable
                  ? context.tr('ad_unavailable_try_later')
                  : context.tr('watch_ad_to_continue'),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _cancel,
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: _isLoading || _unavailable ? null : _watch,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.play_arrow, size: 18),
            label: Text(_isLoading ? context.tr('loading') : context.tr('watch_ad')),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.tertiary,
              foregroundColor: cs.surface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Records a completed rewarded view as first-party ad revenue.
///
/// Guarded with [onError] because the previous implementation fired an
/// unawaited Firestore write whose failure surfaced as an unhandled async error.
void _recordRewardedAdView() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  // Revenue telemetry must never break the user flow.
  unawaited(
    FirebaseFirestore.instance.collection('ad_views').add({
      'buyerId': uid,
      'timestamp': FieldValue.serverTimestamp(),
      'processed': false,
    }).then<void>(
      (_) {},
      onError: (Object error, StackTrace _) {
        debugPrint('RewardedAdGate: ad_views write failed — $error');
      },
    ),
  );
}
