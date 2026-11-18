import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../extensions/context_tr.dart';
import '../../services/buyer_request_service.dart';
import '../../widgets/google_loading.dart';

class PostBuyerRequestScreen extends StatefulWidget {
  const PostBuyerRequestScreen({super.key});

  @override
  State<PostBuyerRequestScreen> createState() => _PostBuyerRequestScreenState();
}

class _PostBuyerRequestScreenState extends State<PostBuyerRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _minBudgetCtrl = TextEditingController();
  final _maxBudgetCtrl = TextEditingController();
  final _requirementsCtrl = TextEditingController();

  String _condition = 'any';
  String _delivery = 'negotiable';
  int _expiryHours = 168;
  int _offerLimit = 10;

  List<int> _expiryOptions = const [24, 72, 168, 336];
  List<int> _offerLimitOptions = const [5, 10, 20];

  bool _submitting = false;
  bool _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final cfg = await BuyerRequestService().getConfig();
      final exp = (cfg['expiryOptionsHours'] as List?)?.map((e) => (e as num).toInt()).toList();
      final off = (cfg['offerLimitOptions'] as List?)?.map((e) => (e as num).toInt()).toList();
      if (mounted) {
        setState(() {
          if (exp != null && exp.isNotEmpty) _expiryOptions = exp;
          if (off != null && off.isNotEmpty) _offerLimitOptions = off;
          _expiryHours = (cfg['defaultExpiryHours'] as num?)?.toInt() ?? _expiryHours;
          _offerLimit = (cfg['defaultOfferLimit'] as num?)?.toInt() ?? _offerLimit;
          _loadingConfig = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingConfig = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _brandCtrl.dispose();
    _modelCtrl.dispose();
    _locationCtrl.dispose();
    _minBudgetCtrl.dispose();
    _maxBudgetCtrl.dispose();
    _requirementsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await BuyerRequestService().create({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'brand': _brandCtrl.text.trim(),
        'model': _modelCtrl.text.trim(),
        'condition': _condition,
        'location': _locationCtrl.text.trim(),
        'delivery': _delivery,
        'requirements': _requirementsCtrl.text.trim(),
        'minBudget': int.tryParse(_minBudgetCtrl.text.trim()) ?? 0,
        'maxBudget': int.tryParse(_maxBudgetCtrl.text.trim()) ?? 0,
        'expiresInHours': _expiryHours,
        'offerLimit': _offerLimit,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('request_posted'))));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingConfig) {
      return Scaffold(appBar: AppBar(title: Text(context.tr('post_request_title'))), body: const Center(child: GoogleLoading(size: 32)));
    }
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
                _field(_titleCtrl, context.tr('request_title'), required: true),
                const SizedBox(height: 12),
                _field(_descCtrl, context.tr('request_description'), maxLines: 3, required: true),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_brandCtrl, context.tr('brand'))),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_modelCtrl, context.tr('model'))),
                ]),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _condition,
                  decoration: InputDecoration(labelText: context.tr('condition'), border: const OutlineInputBorder()),
                  items: const ['any', 'new', 'used_like_new', 'used_good', 'used_fair']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _condition = v ?? 'any'),
                ),
                const SizedBox(height: 12),
                _field(_locationCtrl, context.tr('location')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _delivery,
                  decoration: InputDecoration(labelText: context.tr('delivery'), border: const OutlineInputBorder()),
                  items: const ['negotiable', 'pickup', 'delivery', 'either']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() => _delivery = v ?? 'negotiable'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _field(_minBudgetCtrl, context.tr('min_budget'), keyboardType: TextInputType.number, required: true)),
                  const SizedBox(width: 8),
                  Expanded(child: _field(_maxBudgetCtrl, context.tr('max_budget'), keyboardType: TextInputType.number, required: true)),
                ]),
                const SizedBox(height: 12),
                _field(_requirementsCtrl, context.tr('additional_requirements'), maxLines: 3),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _expiryHours,
                  decoration: InputDecoration(labelText: context.tr('request_expiration'), border: const OutlineInputBorder()),
                  items: _expiryOptions.map((h) => DropdownMenuItem(value: h, child: Text('$h h'))).toList(),
                  onChanged: (v) => setState(() => _expiryHours = v ?? _expiryHours),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _offerLimit,
                  decoration: InputDecoration(labelText: context.tr('max_sellers'), border: const OutlineInputBorder()),
                  items: _offerLimitOptions.map((n) => DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                  onChanged: (v) => setState(() => _offerLimit = v ?? _offerLimit),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting ? const SizedBox(width: 20, height: 20, child: GoogleLoading(size: 16, strokeWidth: 2)) : const Icon(Icons.send),
                    label: Text(context.tr('submit_request')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1, bool required = false, TextInputType? keyboardType}) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? label : null : null,
    );
  }
}