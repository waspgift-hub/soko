import 'package:flutter/material.dart';
import 'ds_button.dart';

/// Quick report reasons — shared by the fast dialog and the full screen so
/// categories never drift apart.
const dsReportReasons = [
  'Scam',
  'Fake product',
  'Wrong information',
  'Harassment',
  'Prohibited item',
  'Other',
];

/// Fast report dialog for long-press flows. Returns the chosen reason, or
/// null on cancel — the caller opens the full ReportScreen for details.
Future<String?> showDsReportDialog(
  BuildContext context, {
  required String targetTitle,
}) {
  String selected = dsReportReasons.first;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Report'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                targetTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              ...dsReportReasons.map(
                (r) => RadioListTile<String>(
                  value: r,
                  groupValue: selected,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r),
                  onChanged: (v) =>
                      setState(() => selected = v ?? selected),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          DsButton(
            label: 'Continue',
            onPressed: () => Navigator.pop(ctx, selected),
          ),
        ],
      ),
    ),
  );
}
