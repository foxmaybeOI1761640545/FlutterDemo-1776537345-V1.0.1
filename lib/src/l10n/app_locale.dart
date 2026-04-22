import "package:flutter/material.dart";

enum AppLanguage {
  zh,
  en,
}

extension AppLanguageExtension on AppLanguage {
  String get storageValue {
    return switch (this) {
      AppLanguage.zh => "zh",
      AppLanguage.en => "en",
    };
  }

  Locale get locale {
    return switch (this) {
      AppLanguage.zh => const Locale("zh"),
      AppLanguage.en => const Locale("en"),
    };
  }

  static AppLanguage fromStorage(String? value) {
    return value == AppLanguage.en.storageValue ? AppLanguage.en : AppLanguage.zh;
  }
}

class AppLocaleScope extends InheritedWidget {
  const AppLocaleScope({
    required this.language,
    required super.child,
    super.key,
  });

  final AppLanguage language;

  static AppLanguage of(BuildContext context) {
    final AppLocaleScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    return scope?.language ?? AppLanguage.zh;
  }

  @override
  bool updateShouldNotify(AppLocaleScope oldWidget) {
    return oldWidget.language != language;
  }
}

extension BuildContextLocaleExtension on BuildContext {
  AppLanguage get appLanguage => AppLocaleScope.of(this);

  bool get isChinese => appLanguage == AppLanguage.zh;

  String tr({
    required String zh,
    required String en,
  }) {
    return isChinese ? zh : en;
  }
}
