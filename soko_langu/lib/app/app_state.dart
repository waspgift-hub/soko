import 'package:flutter/foundation.dart';

class AppStateNotifier extends ChangeNotifier {
  bool appInitialized = false;
  bool isAuthenticated = false;
  bool isAdmin = false;
  bool onboardingChecked = false;
  bool hasCompletedOnboarding = true;

  /// Selected shell tab. Kept outside [MainScreen] because account switches
  /// rebuild the shell, and losing the tab mid-flow strands the user on Home.
  int mainTabIndex = 0;

  /// No notifyListeners: GoRouter observes this notifier for auth routing, and
  /// refreshing it on every tap would rebuild the whole shell.
  void setMainTabIndex(int index) => mainTabIndex = index;

  void setAppInitialized() {
    appInitialized = true;
    notifyListeners();
  }

  void setOnboarding({required bool completed}) {
    hasCompletedOnboarding = completed;
    onboardingChecked = true;
    notifyListeners();
  }

  void setAuthState({required bool authenticated, bool admin = false}) {
    isAuthenticated = authenticated;
    isAdmin = admin;
    notifyListeners();
  }
}

final appStateNotifier = AppStateNotifier();
