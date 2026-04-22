import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";

import "l10n/app_locale.dart";
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

  ColorScheme _buildColorScheme({required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: isDark ? const Color(0xFFC88482) : const Color(0xFFBA5D62),
      brightness: brightness,
    );

    return base.copyWith(
      primary: isDark ? const Color(0xFFD08C8A) : const Color(0xFFB65D62),
      onPrimary: isDark ? const Color(0xFF211619) : const Color(0xFFFFF7F4),
      primaryContainer: isDark ? const Color(0xFF5A3436) : const Color(0xFFE9C4C2),
      onPrimaryContainer: isDark ? const Color(0xFFF8DAD8) : const Color(0xFF3D1F21),
      secondary: isDark ? const Color(0xFFC5B083) : const Color(0xFFD8C49A),
      onSecondary: isDark ? const Color(0xFF2C2417) : const Color(0xFF4A3A21),
      secondaryContainer: isDark ? const Color(0xFF584B2F) : const Color(0xFFF0E5CC),
      onSecondaryContainer: isDark ? const Color(0xFFF3E8CF) : const Color(0xFF3F3120),
      tertiary: isDark ? const Color(0xFF9DADC6) : const Color(0xFF7A8DA9),
      onTertiary: isDark ? const Color(0xFF172131) : const Color(0xFFF4F7FB),
      surface: isDark ? const Color(0xFF151B27) : const Color(0xFFF2ECE3),
      onSurface: isDark ? const Color(0xFFECE4D8) : const Color(0xFF2F2A25),
      surfaceContainer: isDark ? const Color(0xFF1D2431) : const Color(0xFFF7F2EA),
      surfaceContainerHigh: isDark ? const Color(0xFF242D3A) : const Color(0xFFF3ECE3),
      surfaceContainerHighest: isDark ? const Color(0xFF2D3746) : const Color(0xFFECE2D6),
      outline: isDark ? const Color(0xFF5B6575) : const Color(0xFFD4C5B4),
      outlineVariant: isDark ? const Color(0xFF424B5A) : const Color(0xFFE2D6C8),
      error: isDark ? const Color(0xFFE58B88) : const Color(0xFFB95A58),
      onError: isDark ? const Color(0xFF2F0F12) : const Color(0xFFFFF7F6),
      errorContainer: isDark ? const Color(0xFF5E2D33) : const Color(0xFFF1D0D0),
      onErrorContainer: isDark ? const Color(0xFFFFDBDA) : const Color(0xFF4E2025),
    );
  }

  ThemeData _buildTheme({required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;
    final ColorScheme colorScheme = _buildColorScheme(brightness: brightness);
    final TextTheme textTheme = ThemeData(brightness: brightness).textTheme.apply(
          fontFamily: "Segoe UI",
          fontFamilyFallback: unifiedFontFallback,
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );
    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.42)),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      canvasColor: colorScheme.surface,
      fontFamily: "Segoe UI",
      textTheme: textTheme.copyWith(
        headlineSmall: textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        titleMedium: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurface.withOpacity(isDark ? 0.92 : 0.86),
        ),
        bodySmall: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(isDark ? 0.78 : 0.72),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? colorScheme.surfaceContainerHighest.withOpacity(0.36)
            : colorScheme.surfaceContainerHighest.withOpacity(0.52),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.3),
        ),
        hintStyle: TextStyle(
          color: colorScheme.onSurface.withOpacity(isDark ? 0.55 : 0.48),
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark
            ? colorScheme.surfaceContainer.withOpacity(0.88)
            : colorScheme.surfaceContainer.withOpacity(0.94),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.58)),
        ),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest.withOpacity(0.42)
            : colorScheme.surfaceContainerHighest.withOpacity(0.46),
        selectedColor: colorScheme.secondaryContainer,
        disabledColor: colorScheme.surfaceContainerHighest.withOpacity(0.24),
        side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.64)),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          color: colorScheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ).copyWith(
          overlayColor: MaterialStatePropertyAll<Color>(
            colorScheme.onPrimary.withOpacity(0.08),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: colorScheme.outline.withOpacity(0.62)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.secondary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateProperty.resolveWith((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.surface;
        }),
        trackColor: MaterialStateProperty.resolveWith((Set<MaterialState> states) {
          if (states.contains(MaterialState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline.withOpacity(0.48);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colorScheme.primary,
        inactiveTrackColor: colorScheme.outlineVariant,
        thumbColor: colorScheme.primary,
        overlayColor: colorScheme.primary.withOpacity(0.14),
        valueIndicatorColor: colorScheme.primaryContainer,
        valueIndicatorTextStyle: TextStyle(
          color: colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.54)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHigh
            : colorScheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: colorScheme.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark
            ? Color.alphaBlend(
                colorScheme.primary.withOpacity(0.08),
                colorScheme.surfaceContainer,
              )
            : Color.alphaBlend(
                colorScheme.secondary.withOpacity(0.16),
                colorScheme.surfaceContainer,
              ),
        indicatorColor: isDark
            ? colorScheme.primaryContainer.withOpacity(0.58)
            : colorScheme.primaryContainer,
        labelTextStyle: MaterialStateProperty.resolveWith((Set<MaterialState> states) {
          return TextStyle(
            fontWeight: states.contains(MaterialState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(MaterialState.selected)
                ? colorScheme.onSurface
                : colorScheme.onSurface.withOpacity(0.78),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLanguage language = _settings.language;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "PulseBeat",
      locale: language.locale,
      supportedLocales: const <Locale>[
        Locale("zh"),
        Locale("en"),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: _buildTheme(brightness: Brightness.light),
      darkTheme: _buildTheme(brightness: Brightness.dark),
      themeMode: _settings.darkTheme ? ThemeMode.dark : ThemeMode.light,
      home: _isLoading
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : AppLocaleScope(
              language: language,
              child: HomeShell(
                settings: _settings,
                presets: _presets,
                onSettingsChanged: _updateSettings,
                onPresetsChanged: _updatePresets,
                onClearLocalData: _clearLocalData,
              ),
            ),
    );
  }
}
