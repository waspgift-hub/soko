import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_dimens.dart';
import '../../theme/app_typography.dart';
import '../../widgets/ds/ds.dart';
import '../../widgets/ds/examples/standard_input_login_example.dart';
import '../../widgets/ds/examples/standard_input_profile_example.dart';
import '../../widgets/soko_app_bar.dart';

/// Design review surface for [StandardInputField]: every state, size and
/// variant side by side, plus the two reference forms. Open it on any target —
/// `flutter run -d chrome` is enough to review the field without an emulator.
class StandardInputGalleryScreen extends StatefulWidget {
  const StandardInputGalleryScreen({super.key});

  @override
  State<StandardInputGalleryScreen> createState() =>
      _StandardInputGalleryScreenState();
}

class _StandardInputGalleryScreenState
    extends State<StandardInputGalleryScreen> {
  final _successDemo = TextEditingController(text: 'juma@sokovibe.co.tz');
  final _multilineDemo = TextEditingController(
    text: 'Phones, chargers and cases. Delivery within Dar es Salaam.',
  );

  @override
  void dispose() {
    _successDemo.dispose();
    _multilineDemo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.bgCanvas,
      appBar: const SokoAppBar(title: 'Standard Input Field'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s5),
        children: [
          _section(context, 'States', [
            const StandardInputField(
              label: 'Idle',
              hint: 'Seller name',
              prefixIcon: Icons.storefront_outlined,
            ),
            const SizedBox(height: AppSpacing.s4),
            // Autofocus so the focused chrome is visible on open.
            StandardInputField(
              label: 'Focused',
              hint: 'Tap or type here',
              prefixIcon: Icons.search_rounded,
              keyboard: DsKeyboard.search,
              autofocus: true,
            ),
            const SizedBox(height: AppSpacing.s4),
            const StandardInputField(
              label: 'Error',
              hint: 'buyer@sokovibe.co.tz',
              prefixIcon: Icons.mail_outline_rounded,
              errorText: 'Email domain is not allowed',
            ),
            const SizedBox(height: AppSpacing.s4),
            StandardInputField(
              controller: _successDemo,
              label: 'Success',
              prefixIcon: Icons.alternate_email_rounded,
              keyboard: DsKeyboard.email,
              showSuccess: true,
              clearable: true,
            ),
            const SizedBox(height: AppSpacing.s4),
            const StandardInputField(
              label: 'Disabled',
              hint: 'Set by verification',
              prefixIcon: Icons.verified_user_outlined,
              enabled: false,
            ),
            const SizedBox(height: AppSpacing.s4),
            const StandardInputField(
              label: 'Helper text',
              hint: '+255 714 000 000',
              helperText: 'Buyers use this to reach you on delivery day',
              prefixIcon: Icons.phone_outlined,
              keyboard: DsKeyboard.phone,
            ),
          ]),
          _section(context, 'Sizes', [
            const StandardInputField(
              size: DsFieldSize.sm,
              label: 'Small — 44dp',
              prefixIcon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.s3),
            const StandardInputField(
              size: DsFieldSize.md,
              label: 'Medium — 52dp',
              prefixIcon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.s3),
            const StandardInputField(
              size: DsFieldSize.lg,
              label: 'Large — 58dp',
              prefixIcon: Icons.lock_outline_rounded,
            ),
          ]),
          _section(context, 'Variants', [
            const StandardInputField(
              variant: DsFieldVariant.soft,
              label: 'Soft — extruded',
              prefixIcon: Icons.payments_outlined,
              keyboard: DsKeyboard.decimal,
              prefixText: 'TSh',
            ),
            const SizedBox(height: AppSpacing.s3),
            const StandardInputField(
              variant: DsFieldVariant.inset,
              label: 'Inset — recessed',
              prefixIcon: Icons.filter_alt_outlined,
            ),
            const SizedBox(height: AppSpacing.s3),
            const StandardInputField(
              variant: DsFieldVariant.flat,
              label: 'Flat — border only',
              prefixIcon: Icons.place_outlined,
            ),
          ]),
          _section(context, 'Rich content', [
            const StandardInputField(
              label: 'Password with toggle',
              hint: 'At least 8 characters',
              prefixIcon: Icons.lock_outline_rounded,
              keyboard: DsKeyboard.password,
            ),
            const SizedBox(height: AppSpacing.s3),
            StandardInputField(
              controller: _multilineDemo,
              label: 'Bio',
              hint: 'What do you sell?',
              keyboard: DsKeyboard.multiline,
              minLines: 3,
              maxLines: 6,
              maxLength: 160,
              showCounter: true,
            ),
            const SizedBox(height: AppSpacing.s3),
            const StandardInputField(
              label: 'Disabled, with trailing lock',
              helperText: 'Contact support to change your email',
              prefixIcon: Icons.mail_outline_rounded,
              keyboard: DsKeyboard.email,
              enabled: false,
              suffixIcon: Icons.lock_outline_rounded,
            ),
          ]),
          _section(context, 'Example — login', const [
            StandardInputLoginExample(),
          ]),
          _section(context, 'Example — profile update', const [
            StandardInputProfileExample(),
          ]),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: AppTypography.monoLabel(scheme.contentMuted),
          ),
          const SizedBox(height: AppSpacing.s3),
          DsCard(
            elevation: DsCardElevation.low,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}
