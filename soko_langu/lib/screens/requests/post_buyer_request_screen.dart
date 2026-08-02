import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/buyer_request_service.dart';
import '../../widgets/google_loading.dart';
import '../../extensions/context_tr.dart';

class PostBuyerRequestScreen extends StatefulWidget {
  const PostBuyerRequestScreen({super.key});

  @override
  State<PostBuyerRequestScreen> createState() => _PostBuyerRequestScreenState();
}

class _PostBuyerRequestScreenState extends State<PostBuyerRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _waCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _budgetCtrl.dispose();
    _descCtrl.dispose();
    _waCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('post_request_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: context.tr('request_title'),
                    hintText: context.tr('request_title_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? context.tr('request_title') : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _budgetCtrl,
                  decoration: InputDecoration(
                    labelText: context.tr('request_budget'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final val = double.tryParse(v ?? '');
                    return (val == null || val <= 0) ? context.tr('enter_budget') : null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descCtrl,
                  decoration: InputDecoration(
                    labelText: context.tr('request_description'),
                    hintText: context.tr('request_description_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _waCtrl,
                  decoration: InputDecoration(
                    labelText: context.tr('request_whatsapp'),
                    hintText: context.tr('request_whatsapp_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) {
                    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    return (digits.length < 9) ? context.tr('invalid_whatsapp') : null;
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: GoogleLoading(size: 16, strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(context.tr('submit_request')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await BuyerRequestService().addRequest(
        title: _titleCtrl.text.trim(),
        budget: double.parse(_budgetCtrl.text.trim()),
        description: _descCtrl.text.trim(),
        whatsapp: _waCtrl.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('request_posted')),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('imeshindwa').replaceAll('{0}', '$e')),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
