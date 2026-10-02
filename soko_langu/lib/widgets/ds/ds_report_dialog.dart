import 'package:flutter/material.dart';
import '../../extensions/context_tr.dart';
import 'ds_button.dart';

/// Quick report reasons — shared by the fast dialog and the full screen so
/// categories never drift apart. Values are the wire format sent to the
/// backend and must stay English; [dsReportReasonKeys] maps each to its
/// display string.
const dsReportReasons = [
  'Scam',
  'Fake product',
  'Wrong information',
  'Harassment',
  'Prohibited item',
  'Other',
];

const dsReportReasonKeys = {
  'Scam': 'report_reason_scam',
  'Fake product': 'report_reason_fake_product',
  'Wrong information': 'report_reason_wrong_info',
  'Harassment': 'report_reason_harassment',
  'Prohibited item': 'report_reason_inappropriate',
  'Other': 'report_reason_other',
};

String dsReportReasonLabel(BuildContext context, String reason) {
  final key = dsReportReasonKeys[reason];
  return key == null ? reason : context.tr(key, reason);
}

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
        title: Text(context.tr('report')),
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
                  title: Text(dsReportReasonLabel(ctx, r)),
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
            child: Text(context.tr('cancel')),
          ),
          DsButton(
            label: context.tr('continue'),
            onPressed: () => Navigator.pop(ctx, selected),
          ),
        ],
      ),
    ),
  );
}
