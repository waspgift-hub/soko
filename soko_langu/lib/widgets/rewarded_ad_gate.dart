import 'dart:async';
import 'package:flutter/material.dart';
import '../services/rewarded_ad_service.dart';
import '../extensions/context_tr.dart';

class RewardedAdGate {
  static final _rewardedAdService = RewardedAdService();

  static Future<bool> require(
    BuildContext context,
    String action, {
    String? title,
    String? message,
  }) async {
    if (await AdGateService.hasPassedGate(action)) return true;

    final passed = await _showGateDialog(context, title, message);
    if (passed) {
      await AdGateService.markGatePassed(action);
    }
    return passed;
  }

  static Future<bool> _showGateDialog(
    BuildContext context,
    String? title,
    String? message,
  ) async {
    final completer = Completer<bool>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.play_circle_outline, color: Colors.orange, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title ?? context.tr('watch_ad')),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message ?? context.tr('ad_required')),
            const SizedBox(height: 8),
            Text(
              context.tr('watch_ad_to_continue'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              completer.complete(false);
            },
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _rewardedAdService.preload();
              final earned = await _rewardedAdService.show(
                onUserEarned: () {},
              );
              completer.complete(earned);
            },
            icon: const Icon(Icons.play_arrow, size: 18),
            label: Text(context.tr('watch_ad')),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    return completer.future;
  }
}
