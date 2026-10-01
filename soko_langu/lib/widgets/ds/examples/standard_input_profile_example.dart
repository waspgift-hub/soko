import 'package:flutter/material.dart';

import '../../../theme/app_dimens.dart';
import '../ds_button.dart';
import '../ds_card.dart';
import '../input_validators.dart';
import '../standard_input_field.dart';

/// Reference wiring for a profile editor — the harder half of a form: a
/// disabled read-only field, a phone number with a fixed `+255` prefix, a
/// multiline bio with a live counter, and a submit that locks the whole form
/// while saving and then reports per-field success.
class StandardInputProfileExample extends StatefulWidget {
  const StandardInputProfileExample({super.key});

  @override
  State<StandardInputProfileExample> createState() =>
      _StandardInputProfileExampleState();
}

class _StandardInputProfileExampleState
    extends State<StandardInputProfileExample> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Juma Ally');
  final _email = TextEditingController(text: 'juma@sokovibe.co.tz');
  final _phone = TextEditingController(text: '714 000 000');
  final _bio = TextEditingController(text: 'Sells used phones and parts.');

  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saved = false;
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DsCard(
      elevation: DsCardElevation.low,
      child: Form(
        key: _formKey,
        autovalidateMode: _saved
            ? AutovalidateMode.always
            : AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StandardInputField(
              controller: _name,
              label: 'Full name',
              hint: 'Your name as buyers will see it',
              prefixIcon: Icons.person_outline_rounded,
              size: DsFieldSize.lg,
              clearable: true,
              showSuccess: _saved,
              validateOnChange: true,
              enabled: !_saving,
              textCapitalization: TextCapitalization.words,
              validator: (v) => DsValidators.minLength(
                2,
                v,
                message: 'Enter at least 2 characters',
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            // Email is owned by the account provider: visible for reference,
            // but not editable here, so it renders dimmed and rejects focus.
            StandardInputField(
              controller: _email,
              label: 'Email',
              helperText: 'Contact support to change your email',
              prefixIcon: Icons.mail_outline_rounded,
              keyboard: DsKeyboard.email,
              enabled: false,
              suffixIcon: Icons.lock_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.s4),
            StandardInputField(
              controller: _phone,
              label: 'Phone number',
              hint: '714 000 000',
              keyboard: DsKeyboard.phone,
              prefixText: '+255',
              enabled: !_saving,
              clearable: true,
              showSuccess: _saved,
              validateOnChange: true,
              validateOnBlur: true,
              onChanged: (value) => setState(() => _saved = false),
              validator: (v) => DsValidators.phone(
                v,
                message: 'Enter a valid number, e.g. 714 000 000',
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            StandardInputField(
              controller: _bio,
              label: 'Bio',
              hint: 'What do you sell?',
              keyboard: DsKeyboard.multiline,
              minLines: 3,
              maxLines: 6,
              maxLength: 160,
              showCounter: true,
              enabled: !_saving,
              onChanged: (value) => setState(() => _saved = false),
              validator: (v) => DsValidators.maxLength(
                160,
                v,
                message: 'Keep it under 160 characters',
              ),
            ),
            const SizedBox(height: AppSpacing.s6),
            DsButton(
              label: _saved ? 'Saved' : 'Save changes',
              loading: _saving,
              icon: _saved ? Icons.check_rounded : null,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
