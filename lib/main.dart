import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'library/library_screen.dart';
import 'models.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InkNoteApp());
}

class InkNoteApp extends StatefulWidget {
  const InkNoteApp({super.key});

  static InkNoteAppState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<InkNoteAppState>();

  @override
  State<InkNoteApp> createState() => InkNoteAppState();
}

class InkNoteAppState extends State<InkNoteApp> {
  AppSettings _settings = const AppSettings();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettingsStore.load();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  void updateSettings(AppSettings newSettings) {
    setState(() => _settings = newSettings);
  }

  ThemeMode get _themeMode {
    switch (_settings.themePreference) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
        return ThemeMode.system;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Ink Note',
      themeMode: _themeMode,
      theme: buildInkTheme(Brightness.light),
      darkTheme: buildInkTheme(Brightness.dark),
      home: _loading
          ? const _AppLoadingScreen()
          : const LibraryScreen(),
    );
  }
}

class _AppLoadingScreen extends StatelessWidget {
  const _AppLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator.adaptive()),
    );
  }
}
