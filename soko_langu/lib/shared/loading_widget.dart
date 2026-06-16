import 'package:flutter/material.dart';
import '../widgets/google_loading.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;

  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GoogleLoading(size: 24, strokeWidth: 2),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(message!, style: TextStyle(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.94))),
          ],
        ],
      ),
    );
  }
}

