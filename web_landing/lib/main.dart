import 'package:flutter/material.dart';
import 'localization/app_strings.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SokoVibeWebApp());
}

class SokoVibeWebApp extends StatefulWidget {
  const SokoVibeWebApp({super.key});

  @override
  State<SokoVibeWebApp> createState() => _SokoVibeWebAppState();
}

class _SokoVibeWebAppState extends State<SokoVibeWebApp> {
  final AppStrings _strings = AppStrings();

  @override
  void initState() {
    super.initState();
    _strings.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _strings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppStringsProvider(
      strings: _strings,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        onGenerateTitle: (ctx) => _strings.t('doc_title'),
        theme: SokoWebTheme.light(),
        initialRoute: AppRoutes.home,
        onGenerateRoute: onGenerateRoute,
      ),
    );
  }
}
