import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../services/user_service.dart';
import '../../extensions/context_tr.dart';
import '../../utils/helpers.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();
  final _moodController = TextEditingController();
  final _picker = ImagePicker();
  final _userService = UserService();

  UserProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  String? _imagePath;
  double? _latitude;
  double? _longitude;
  List<MapEntry<TextEditingController, TextEditingController>> _paymentEntries =
      [];

  static const List<String> _paymentMethodHints = ['Google Pay', 'Bank Name'];

  static const List<String> _moodOptions = [
    '😊 Happy',
    '😢 Sad',
    '😡 Angry',
    '😴 Tired',
    '🤩 Excited',
    '😐 Neutral',
    '❤️ In Love',
    '🙏 Grateful',
    '🔥 Motivated',
    '🎉 Celebrating',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    _moodController.dispose();
    for (final e in _paymentEntries) {
      e.key.dispose();
      e.value.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final profile = await _userService.getProfile(uid);
    if (mounted) {
      setState(() {
        _profile = profile;
        _nameController.text =
            profile?.displayName ??
            FirebaseAuth.instance.currentUser?.displayName ??
            '';
        _usernameController.text = profile?.username ?? '';
        _bioController.text = profile?.bio ?? '';
        _emailController.text =
            profile?.email ?? FirebaseAuth.instance.currentUser?.email ?? '';
        _phoneController.text = profile?.phone ?? '';
        _locationController.text = profile?.location ?? '';
        _moodController.text = profile?.mood ?? '';
        _latitude = profile?.latitude;
        _longitude = profile?.longitude;
        _imagePath = profile?.profileImage;
        if (profile != null) {
          _paymentEntries = profile.paymentNumbers.entries
              .map(
                (e) => MapEntry(
                  TextEditingController(text: e.key),
                  TextEditingController(text: e.value),
                ),
              )
              .toList();
        }
        _loading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final granted = await requestPermissionWithDialog(
      context,
      Permission.photos,
      'permission_photos',
    );
    if (!granted) return;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _imagePath = image.path);
    }
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
      }
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied'),
          ),
        );
      }
      return;
    }

    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    try {
      final placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final addr = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
          p.country,
        ].where((s) => s != null && s.isNotEmpty).join(', ');
        setState(() {
          _locationController.text = addr;
          _latitude = pos.latitude;
          _longitude = pos.longitude;
        });
      }
    } catch (_) {
      setState(() {
        _locationController.text = '${pos.latitude}, ${pos.longitude}';
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
    }
  }

  void _addPaymentMethod() {
    setState(() {
      _paymentEntries.add(
        MapEntry(TextEditingController(), TextEditingController()),
      );
    });
  }

  void _removePaymentMethod(int index) {
    _paymentEntries[index].key.dispose();
    _paymentEntries[index].value.dispose();
    setState(() => _paymentEntries.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      String imageUrl = _profile?.profileImage ?? '';

      if (_imagePath != null && (_profile?.profileImage != _imagePath)) {
        if (_imagePath!.startsWith('http')) {
          imageUrl = _imagePath!;
        } else {
          imageUrl = await _userService.uploadProfileImage(_imagePath!);
        }
      }

      final paymentNumbers = <String, String>{};
      for (final e in _paymentEntries) {
        final name = e.key.text.trim();
        final number = e.value.text.trim();
        if (name.isNotEmpty && number.isNotEmpty) {
          paymentNumbers[name] = number;
        }
      }

      final username = _usernameController.text.trim().toLowerCase();
      final taken = await _userService.isUsernameTaken(username, uid);
      if (taken) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Username already taken'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _saving = false);
        return;
      }

      final profile = UserProfile(
        uid: uid,
        displayName: _nameController.text.trim(),
        username: username,
        bio: _bioController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        location: _locationController.text.trim(),
        mood: _moodController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        profileImage: imageUrl,
        paymentNumbers: paymentNumbers,
      );

      await _userService.saveProfile(profile);

      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        profile.displayName,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Profile saved!")));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(title: Text(context.tr('edit_profile'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(context.tr('edit_profile')),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.tr('save'),
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.green,
                    backgroundImage: _imagePath != null
                        ? (_imagePath!.startsWith('http')
                              ? NetworkImage(_imagePath!)
                              : FileImage(File(_imagePath!)) as ImageProvider)
                        : null,
                    child: _imagePath == null
                        ? Text(
                            user?.displayName != null
                                ? user!.displayName![0].toUpperCase()
                                : user?.email != null
                                ? user!.email![0].toUpperCase()
                                : "U",
                            style: const TextStyle(
                              fontSize: 40,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.tr('display_name'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.tr('required')
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  hintText: 'choose a unique username',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.alternate_email,
                    color: Colors.green,
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Username is required';
                  }
                  if (v.trim().contains(' ')) return 'No spaces allowed';
                  if (v.trim().length < 3) return 'At least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: InputDecoration(
                  labelText: context.tr('bio'),
                  hintText: 'Tell us about yourself...',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: context.tr('email'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.email, color: Colors.green),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: context.tr('phone'),
                  hintText: '+255 712 345 678',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: context.tr('location'),
                  hintText: 'Dar es Salaam, Tanzania',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.location_on,
                    color: Colors.green,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.my_location, color: Colors.green),
                    onPressed: _getCurrentLocation,
                    tooltip: 'Get current location',
                  ),
                ),
              ),
              if (_latitude != null && _longitude != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _moodController,
                decoration: InputDecoration(
                  labelText: 'Mood',
                  hintText: 'How are you feeling?',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.emoji_emotions,
                    color: Colors.green,
                  ),
                  suffixIcon: PopupMenuButton<String>(
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.green,
                    ),
                    onSelected: (v) => _moodController.text = v,
                    itemBuilder: (_) => _moodOptions
                        .map((m) => PopupMenuItem(value: m, child: Text(m)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('payment_methods'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addPaymentMethod,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.tr('add_payment')),
                  ),
                ],
              ),
              if (_paymentEntries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "No payment methods added yet",
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ...List.generate(_paymentEntries.length, (index) {
                final entry = _paymentEntries[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            if (textEditingValue.text.isEmpty) return [];
                            return _paymentMethodHints.where(
                              (h) => h.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                            );
                          },
                          fieldViewBuilder:
                              (context, controller, focusNode, onSubmitted) {
                                entry.key.text = controller.text;
                                return TextField(
                                  controller: controller,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Method',
                                    hintText: 'Payment number',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  onChanged: (v) => entry.key.text = v,
                                );
                              },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: entry.value,
                          decoration: const InputDecoration(
                            labelText: 'Number',
                            hintText: '0712 345 678',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.remove_circle,
                          color: Colors.red,
                        ),
                        onPressed: () => _removePaymentMethod(index),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
