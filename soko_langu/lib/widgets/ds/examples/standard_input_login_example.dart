import 'package:flutter/material.dart';

import '../../../theme/app_dimens.dart';
import '../ds_button.dart';
import '../ds_card.dart';
import '../input_validators.dart';
import '../standard_input_field.dart';

/// Reference wiring for a credential form: one [GlobalKey] for the [Form],
/// owned controllers, a password field with the automatic visibility toggle,
/// and a submit that only runs once validation passes.
///
/// Copy the shape, not the copy: production screens pass `context.tr('key')`
/// strings and the `AuthNotifier` call instead of the demo submit.
class StandardInputLoginExample extends StatefulWidget {
  const StandardInputLoginExample({super.key});

  @override
  State<StandardInputLoginExample> createState() =>
      _StandardInputLoginExampleState();
}

class _StandardInputLoginExampleState extends State<StandardInputLoginExample> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController(text: 'juma@sokovibe.co.tz');
  final _password = TextEditingController();
  final _emailFocus = FocusNode();

  bool _submitting = false;
  String? _serverError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // A server-side failure is fed back as `errorText` so the field chrome
    // reacts exactly like a local validation error.
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) {
      _emailFocus.requestFocus();
      return;
    }
    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _serverError = 'Wrong email or password. Try again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return DsCard(
      elevation: DsCardElevation.low,
      child: Form(
        key: _formKey,
        // Validating only after the first submit avoids yelling at a user who
        // is still typing their first field.
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StandardInputField(
              controller: _email,
              focusNode: _emailFocus,
              label: 'Email',
              hint: 'juma@sokovibe.co.tz',
              prefixIcon: Icons.alternate_email_rounded,
              keyboard: DsKeyboard.email,
              textInputAction: TextInputAction.next,
              clearable: true,
              showSuccess: true,
              // Runs the same rule on every keystroke so the green state can
              // appear, and so the error clears while the user fixes it.
              validateOnChange: true,
              errorText: _serverError,
              validator: (v) =>
                  DsValidators.email(v, message: 'Enter a valid email address'),
            ),
            const SizedBox(height: AppSpacing.s4),
            StandardInputField(
              controller: _password,
              label: 'Password',
              hint: 'At least 8 characters',
              prefixIcon: Icons.lock_outline_rounded,
              // `DsKeyboard.password` turns on the show/hide toggle, the
              // password autofill hint and the correct capitalisation.
              keyboard: DsKeyboard.password,
              textInputAction: TextInputAction.done,
              enabled: !_submitting,
              showSuccess: true,
              onSubmitted: (_) => _submit(),
              validator: (v) => DsValidators.password(v),
            ),
            const SizedBox(height: AppSpacing.s2),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting ? null : _submit,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            DsButton(
              label: 'Sign in',
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
