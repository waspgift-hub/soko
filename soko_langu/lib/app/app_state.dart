import 'package:flutter/foundation.dart';

class AppStateNotifier extends ChangeNotifier {
  bool appInitialized = false;
  bool isAuthenticated = false;
  bool isAdmin = false;

  void setAppInitialized() {
    appInitialized = true;
    notifyListeners();
  }

  void setAuthState({required bool authenticated, bool admin = false}) {
    isAuthenticated = authenticated;
    isAdmin = admin;
    notifyListeners();
  }
}

final appStateNotifier = AppStateNotifier();
