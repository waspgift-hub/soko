import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoLockService with WidgetsBindingObserver {
  static AutoLockService? _instance;
  static AutoLockService get instance => _instance ??= AutoLockService();
  Timer? _lockTimer;
  int _timeoutMinutes = 0;
  bool _isLocked = false;

  VoidCallback? onLock;

  void initialize() {
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _timeoutMinutes = prefs.getInt('auto_lock_minutes') ?? 0;
  }

  void resetTimer() {
    _lockTimer?.cancel();
    if (_timeoutMinutes <= 0) return;

    _lockTimer = Timer(Duration(minutes: _timeoutMinutes), () {
      _isLocked = true;
      onLock?.call();
    });
  }

  void unlock() {
    _isLocked = false;
    resetTimer();
  }

  bool get isLocked => _isLocked;

  Future<void> setTimeout(int minutes) async {
    _timeoutMinutes = minutes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('auto_lock_minutes', minutes);
    if (minutes <= 0) {
      _lockTimer?.cancel();
    } else {
      resetTimer();
    }
  }

  int get timeoutMinutes => _timeoutMinutes;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _lockTimer?.cancel();
      if (_timeoutMinutes > 0) {
        _lockTimer = Timer(Duration(minutes: _timeoutMinutes), () {
          _isLocked = true;
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isLocked) {
        _isLocked = false;
        onLock?.call();
      } else {
        resetTimer();
      }
    }
  }

  void dispose() {
    _lockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
