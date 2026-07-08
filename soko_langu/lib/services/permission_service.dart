import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum AppPermission { storage, camera, location, notification }

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  Future<bool> requestWithDialog(BuildContext context, AppPermission permission) async {
    final p = _mapPermission(permission);
    if (await p.isGranted) return true;
    final status = await p.request();
    return status.isGranted;
  }

  Permission _mapPermission(AppPermission p) {
    switch (p) {
      case AppPermission.storage: return Permission.storage;
      case AppPermission.camera: return Permission.camera;
      case AppPermission.location: return Permission.location;
      case AppPermission.notification: return Permission.notification;
    }
  }
}
