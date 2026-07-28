import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/ride_provider.dart';
import '../../app/routes.dart';
import '../../extensions/context_tr.dart';

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _typeCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _regCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();

  @override
  void dispose() {
    _typeCtrl.dispose();
    _modelCtrl.dispose();
    _colorCtrl.dispose();
    _regCtrl.dispose();
    _licenseCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<RideProvider>();
    final ok = await provider.registerDriver(
      type: _typeCtrl.text,
      model: _modelCtrl.text,
      color: _colorCtrl.text,
      regNumber: _regCtrl.text,
      licenseNumber: _licenseCtrl.text,
    );
    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('registration_successful'))),
      );
      context.pushReplacement(AppRoutes.driverHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<RideProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(context.tr('register_driver')),
        backgroundColor: cs.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('vehicle_info'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: null,
                decoration: InputDecoration(
                  labelText: context.tr('vehicle_type'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: ['Sedan', 'SUV', 'Hatchback', 'Motorcycle', 'Bajaji', 'Van', 'Other']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => _typeCtrl.text = v ?? '',
                validator: (v) => v == null ? context.tr('required') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _modelCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('vehicle_model'),
                  hintText: 'e.g. Toyota Corolla',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _colorCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('vehicle_color'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _regCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('vehicle_reg'),
                  hintText: 'e.g. T xxx ABC',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (v) => v == null || v.isEmpty ? context.tr('required') : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _licenseCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('license_number'),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: provider.loading ? null : _register,
                  child: provider.loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(context.tr('save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
