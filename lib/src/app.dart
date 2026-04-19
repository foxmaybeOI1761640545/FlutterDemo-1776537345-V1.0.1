import "dart:async";

import "package:flutter/material.dart";

import "models.dart";
import "pages/home_shell.dart";
import "storage.dart";

class PulseBeatApp extends StatefulWidget {
  const PulseBeatApp({super.key});

  @override
  State<PulseBeatApp> createState() => _PulseBeatAppState();
}

class _PulseBeatAppState extends State<PulseBeatApp> {
  final LocalStorageService _storageService = LocalStorageService();

  bool _isLoading = true;
  AppSettings _settings = AppSettings.defaults();
  List<MetronomePreset> _presets = <MetronomePreset>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadInitialState());
  }

  Future<void> _loadInitialState() async {
    final StoredAppState state = await _storageService.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = state.settings;
      _presets = state.presets;
      _isLoading = false;
    });
  }

  void _updateSettings(AppSettings next) {
    setState(() {
      _settings = next;
    });
    unawaited(_storageService.saveSettings(next));
  }

  void _updatePresets(List<MetronomePreset> next) {
    final List<MetronomePreset> normalized = List<MetronomePreset>.from(next)
      ..sort(
        (MetronomePreset a, MetronomePreset b) =>
            b.lastUsedAtEpochMs.compareTo(a.lastUsedAtEpochMs),
      );

    setState(() {
      _presets = normalized.take(kMaxPresetCount).toList();
    });
    unawaited(_storageService.savePresets(normalized));
  }

  Future<void> _clearLocalData() async {
    await _storageService.clearAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = AppSettings.defaults();
      _presets = <MetronomePreset>[];
    });
  }

  ThemeData _buildTheme({required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;
    final Color seed = const Color(0xFF2AD8FF);
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF070B18) : const Color(0xFFF4F7FF),
      fontFamily: "Segoe UI",
      textTheme: ThemeData(brightness: brightness).textTheme.apply(
            fontFamily: "Segoe UI",
            fontFamilyFallback: unifiedFontFallback,
          ),
      cardTheme: CardThemeData(
        color: isDark
            ? const Color.fromRGBO(17, 24, 44, 0.76)
            : const Color.fromRGBO(255, 255, 255, 0.86),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? const Color.fromRGBO(9, 15, 30, 0.88)
            : const Color.fromRGBO(241, 246, 255, 0.95),
        indicatorColor: isDark ? const Color(0x332AD8FF) : const Color(0x552AD8FF),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "PulseBeat",
      theme: _buildTheme(brightness: Brightness.light),
      darkTheme: _buildTheme(brightness: Brightness.dark),
      themeMode: _settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : HomeShell(
              settings: _settings,
              presets: _presets,
              onSettingsChanged: _updateSettings,
              onPresetsChanged: _updatePresets,
              onClearLocalData: _clearLocalData,
            ),
    );
  }
}
