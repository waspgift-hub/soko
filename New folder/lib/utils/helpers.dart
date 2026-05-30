import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import '../services/cloudinary_service.dart';

Future<bool> requestPermissionWithDialog(
  BuildContext context,
  Permission permission,
  String explanationKey,
) async {
  var status = await permission.request();
  if (status.isGranted) return true;

  if (status.isPermanentlyDenied) {
    if (context.mounted) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Permission Required'),
          content: Text(
            'This permission was permanently denied. Please enable it in app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (open == true) {
        await openAppSettings();
        status = await permission.request();
        return status.isGranted;
      }
    }
    return false;
  }

  return false;
}

Future<bool> _requestMediaPermissions(BuildContext context) async {
  if (!Platform.isAndroid) {
    return requestPermissionWithDialog(
      context,
      Permission.photos,
      'permission_photos',
    );
  }

  final androidVersion =
      int.tryParse(
        Platform.operatingSystemVersion.split('(').last.split('.').first,
      ) ??
      0;

  if (androidVersion >= 33) {
    for (final p in [Permission.photos, Permission.videos, Permission.audio]) {
      final granted = await requestPermissionWithDialog(
        context,
        p,
        p.toString(),
      );
      if (!granted) return false;
    }
    return true;
  }

  return requestPermissionWithDialog(
    context,
    Permission.storage,
    'permission_storage',
  );
}

Future<List<PlatformFile>?> pickMedia(BuildContext context) async {
  final granted = await _requestMediaPermissions(context);
  if (!granted) return null;

  if (!context.mounted) return null;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.media,
    allowMultiple: true,
  );

  return result?.files;
}

Future<String?> pickAndUploadImage(BuildContext context) async {
  final picker = ImagePicker();

  final granted = await requestPermissionWithDialog(
    context,
    Permission.photos,
    'permission_photos',
  );
  if (!granted) return null;

  if (!context.mounted) return null;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) {
      if (context.mounted) Navigator.pop(context);
      return null;
    }

    final url = await CloudinaryService.uploadImage(image, folder: 'uploads');

    if (context.mounted) Navigator.pop(context);
    return url;
  } catch (e) {
    if (context.mounted) Navigator.pop(context);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to upload image. Check your connection.'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return null;
  }
}
