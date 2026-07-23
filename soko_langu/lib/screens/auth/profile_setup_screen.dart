import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../notifiers/auth_notifier.dart';

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
    if (_gender == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tafadhali chagua jinsia'))); return; }
    if (_dob == null) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tafadhali weka tarehe ya kuzaliwa'))); return; }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imeshindwa: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Kamilisha Profaili Yako')),
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
                Text('Kamilisha Profaili', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: cs.onSurface), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Tafadhali jaza taarifa zako ili kuendelea', style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Jina Kamili', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Tafadhali weka jina lako' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: InputDecoration(labelText: 'Jinsia', prefixIcon: Icon(Icons.wc), border: OutlineInputBorder()),
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
                    decoration: InputDecoration(labelText: 'Tarehe ya Kuzaliwa', prefixIcon: Icon(Icons.calendar_today), border: OutlineInputBorder()),
                    child: Text(_dob != null ? '${_dob!.day}/${_dob!.month}/${_dob!.year}' : 'Bofya kuchagua tarehe'),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _locationController,
                  decoration: InputDecoration(labelText: 'Makazi / Eneo', prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder()),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Tafadhali weka eneo lako' : null,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                    child: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Hifadhi na Endelea', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
