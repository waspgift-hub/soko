import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../notifiers/auth_notifier.dart';
import '../../extensions/context_tr.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  String? _gender;
  DateTime? _dob;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_gender == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('select_gender')))); return; }
    if (_dob == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('select_dob')))); return; }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': _nameController.text.trim(),
        'gender': _gender,
        'dateOfBirth': '${_dob!.year}-${_dob!.month.toString().padLeft(2, '0')}-${_dob!.day.toString().padLeft(2, '0')}',
        'location': _locationController.text.trim(),
      }, SetOptions(merge: true));
      await context.read<AuthNotifier>().completeProfileSetup();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('imeshindwa').replaceAll('{0}', '$e'))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('complete_profile_title'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.person_outline, size: 64, color: cs.primary),
                const SizedBox(height: 16),
                Text(context.tr('complete_profile'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(context.tr('fill_details_to_continue'), style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: context.tr('full_name'), prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? context.tr('enter_name') : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: InputDecoration(labelText: context.tr('gender'), prefixIcon: Icon(Icons.wc), border: OutlineInputBorder()),
                  items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                  onChanged: (v) => setState(() => _gender = v),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: context, initialDate: DateTime(2000), firstDate: DateTime(1940), lastDate: DateTime.now().subtract(const Duration(days: 365*13)));
                    if (picked != null) setState(() => _dob = picked);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(labelText: context.tr('date_of_birth'), prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()),
                    child: Text(_dob != null ? '${_dob!.day}/${_dob!.month}/${_dob!.year}' : context.tr('tap_to_select_date')),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(labelText: context.tr('location_residence'), prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? context.tr('enter_location') : null,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(context.tr('save_and_continue'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
