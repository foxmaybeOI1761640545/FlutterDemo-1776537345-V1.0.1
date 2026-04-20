import "package:flutter/material.dart";

const List<String> unifiedFontFallback = <String>[
  "Microsoft YaHei UI",
  "Microsoft YaHei",
  "PingFang SC",
  "Noto Sans CJK SC",
  "Noto Sans SC",
  "Source Han Sans SC",
  "Arial Unicode MS",
];

const int kMinBpm = 20;
const int kMaxBpm = 240;
const int kMaxPresetCount = 50;

const List<TimeSignatureDefinition> kSupportedSignatures = <TimeSignatureDefinition>[
  TimeSignatureDefinition(key: "2/4", numerator: 2, denominator: 4),
  TimeSignatureDefinition(key: "3/4", numerator: 3, denominator: 4),
  TimeSignatureDefinition(key: "4/4", numerator: 4, denominator: 4),
  TimeSignatureDefinition(key: "6/8", numerator: 6, denominator: 8),
];

final Map<String, TimeSignatureDefinition> _signatureByKey =
    <String, TimeSignatureDefinition>{
      for (final TimeSignatureDefinition signature in kSupportedSignatures)
        signature.key: signature,
    };

TimeSignatureDefinition resolveSignature(String key) {
  return _signatureByKey[key] ?? kSupportedSignatures[2];
}

class TimeSignatureDefinition {
  const TimeSignatureDefinition({
    required this.key,
    required this.numerator,
    required this.denominator,
  });

  final String key;
  final int numerator;
  final int denominator;
}

enum Subdivision {
  none,
  eighth,
  sixteenth,
  triplet,
}

extension SubdivisionExtension on Subdivision {
  int get ticksPerBeat {
    return switch (this) {
      Subdivision.none => 1,
      Subdivision.eighth => 2,
      Subdivision.sixteenth => 4,
      Subdivision.triplet => 3,
    };
  }

  String get label {
    return switch (this) {
      Subdivision.none => "无切分",
      Subdivision.eighth => "8分",
      Subdivision.sixteenth => "16分",
      Subdivision.triplet => "三连音",
    };
  }

  String get storageValue {
    return switch (this) {
      Subdivision.none => "none",
      Subdivision.eighth => "eighth",
      Subdivision.sixteenth => "sixteenth",
      Subdivision.triplet => "triplet",
    };
  }

  static Subdivision fromStorage(String? value) {
    for (final Subdivision subdivision in Subdivision.values) {
      if (subdivision.storageValue == value) {
        return subdivision;
      }
    }
    return Subdivision.none;
  }
}

enum AccentLevel {
  strong,
  normal,
  weak,
  mute,
}

extension AccentLevelExtension on AccentLevel {
  String get label {
    return switch (this) {
      AccentLevel.strong => "强拍",
      AccentLevel.normal => "中拍",
      AccentLevel.weak => "弱拍",
      AccentLevel.mute => "静音",
    };
  }

  String get shortLabel {
    return switch (this) {
      AccentLevel.strong => "强",
      AccentLevel.normal => "中",
      AccentLevel.weak => "弱",
      AccentLevel.mute => "静",
    };
  }

  String get storageValue {
    return switch (this) {
      AccentLevel.strong => "strong",
      AccentLevel.normal => "normal",
      AccentLevel.weak => "weak",
      AccentLevel.mute => "mute",
    };
  }

  Color color(ThemeData theme) {
    return switch (this) {
      AccentLevel.strong => theme.colorScheme.primary,
      AccentLevel.normal => theme.colorScheme.secondary,
      AccentLevel.weak => theme.colorScheme.tertiary,
      AccentLevel.mute => theme.colorScheme.outline,
    };
  }

  static AccentLevel fromStorage(String? value) {
    for (final AccentLevel level in AccentLevel.values) {
      if (level.storageValue == value) {
        return level;
      }
    }
    return AccentLevel.normal;
  }
}

enum MetronomeTone {
  digital,
  wood,
  beep,
}

extension MetronomeToneExtension on MetronomeTone {
  String get label {
    return switch (this) {
      MetronomeTone.digital => "Digital",
      MetronomeTone.wood => "Wood",
      MetronomeTone.beep => "Beep",
    };
  }

  String get storageValue {
    return switch (this) {
      MetronomeTone.digital => "digital",
      MetronomeTone.wood => "wood",
      MetronomeTone.beep => "beep",
    };
  }

  static MetronomeTone fromStorage(String? value) {
    for (final MetronomeTone tone in MetronomeTone.values) {
      if (tone.storageValue == value) {
        return tone;
      }
    }
    return MetronomeTone.digital;
  }
}

class AppSettings {
  const AppSettings({
    required this.volume,
    required this.tone,
    required this.defaultBpm,
    required this.defaultTimeSignature,
    required this.defaultSubdivision,
    required this.darkTheme,
    required this.visualHints,
  });

  final double volume;
  final MetronomeTone tone;
  final int defaultBpm;
  final String defaultTimeSignature;
  final Subdivision defaultSubdivision;
  final bool darkTheme;
  final bool visualHints;

  factory AppSettings.defaults() {
    return const AppSettings(
      volume: 0.8,
      tone: MetronomeTone.digital,
      defaultBpm: 120,
      defaultTimeSignature: "4/4",
      defaultSubdivision: Subdivision.none,
      darkTheme: true,
      visualHints: true,
    );
  }

  AppSettings copyWith({
    double? volume,
    MetronomeTone? tone,
    int? defaultBpm,
    String? defaultTimeSignature,
    Subdivision? defaultSubdivision,
    bool? darkTheme,
    bool? visualHints,
  }) {
    return AppSettings(
      volume: volume ?? this.volume,
      tone: tone ?? this.tone,
      defaultBpm: defaultBpm ?? this.defaultBpm,
      defaultTimeSignature: defaultTimeSignature ?? this.defaultTimeSignature,
      defaultSubdivision: defaultSubdivision ?? this.defaultSubdivision,
      darkTheme: darkTheme ?? this.darkTheme,
      visualHints: visualHints ?? this.visualHints,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "volume": volume,
      "tone": tone.storageValue,
      "defaultBpm": defaultBpm,
      "defaultTimeSignature": defaultTimeSignature,
      "defaultSubdivision": defaultSubdivision.storageValue,
      "darkTheme": darkTheme,
      "visualHints": visualHints,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final AppSettings defaults = AppSettings.defaults();
    final int bpmCandidate = (json["defaultBpm"] as num?)?.round() ?? defaults.defaultBpm;
    final String signatureCandidate = json["defaultTimeSignature"] as String? ??
        defaults.defaultTimeSignature;

    return AppSettings(
      volume: ((json["volume"] as num?)?.toDouble() ?? defaults.volume)
          .clamp(0.0, 1.0)
          .toDouble(),
      tone: MetronomeToneExtension.fromStorage(json["tone"] as String?),
      defaultBpm: bpmCandidate.clamp(kMinBpm, kMaxBpm).toInt(),
      defaultTimeSignature: resolveSignature(signatureCandidate).key,
      defaultSubdivision: SubdivisionExtension.fromStorage(
        json["defaultSubdivision"] as String?,
      ),
      darkTheme: json["darkTheme"] as bool? ?? defaults.darkTheme,
      visualHints: json["visualHints"] as bool? ?? defaults.visualHints,
    );
  }
}

class MetronomeConfig {
  const MetronomeConfig({
    required this.bpm,
    required this.timeSignature,
    required this.subdivision,
    required this.accents,
  });

  final int bpm;
  final String timeSignature;
  final Subdivision subdivision;
  final List<AccentLevel> accents;

  int get numerator => resolveSignature(timeSignature).numerator;

  factory MetronomeConfig.fromSettings(AppSettings settings) {
    final TimeSignatureDefinition signature =
        resolveSignature(settings.defaultTimeSignature);
    return MetronomeConfig(
      bpm: settings.defaultBpm,
      timeSignature: signature.key,
      subdivision: settings.defaultSubdivision,
      accents: List<AccentLevel>.generate(
        signature.numerator,
        (int index) => index == 0 ? AccentLevel.strong : AccentLevel.normal,
      ),
    );
  }

  MetronomeConfig copyWith({
    int? bpm,
    String? timeSignature,
    Subdivision? subdivision,
    List<AccentLevel>? accents,
  }) {
    return MetronomeConfig(
      bpm: bpm ?? this.bpm,
      timeSignature: timeSignature ?? this.timeSignature,
      subdivision: subdivision ?? this.subdivision,
      accents: accents ?? List<AccentLevel>.from(this.accents),
    ).normalized();
  }

  MetronomeConfig normalized() {
    final TimeSignatureDefinition signature = resolveSignature(timeSignature);
    final List<AccentLevel> normalizedAccents = List<AccentLevel>.generate(
      signature.numerator,
      (int index) {
        if (index < accents.length) {
          return accents[index];
        }
        return index == 0 ? AccentLevel.strong : AccentLevel.normal;
      },
    );

    return MetronomeConfig(
      bpm: bpm.clamp(kMinBpm, kMaxBpm).toInt(),
      timeSignature: signature.key,
      subdivision: subdivision,
      accents: normalizedAccents,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "bpm": bpm,
      "timeSignature": timeSignature,
      "subdivision": subdivision.storageValue,
      "accents": accents.map((AccentLevel e) => e.storageValue).toList(),
    };
  }

  factory MetronomeConfig.fromJson(Map<String, dynamic> json) {
    final int bpmCandidate = (json["bpm"] as num?)?.round() ?? 120;
    final String signatureCandidate = json["timeSignature"] as String? ?? "4/4";
    final List<dynamic> accentsRaw = json["accents"] as List<dynamic>? ?? <dynamic>[];

    return MetronomeConfig(
      bpm: bpmCandidate,
      timeSignature: signatureCandidate,
      subdivision: SubdivisionExtension.fromStorage(json["subdivision"] as String?),
      accents: accentsRaw
          .map((dynamic value) => AccentLevelExtension.fromStorage(value as String?))
          .toList(),
    ).normalized();
  }
}

class MetronomePreset {
  const MetronomePreset({
    required this.id,
    required this.name,
    required this.config,
    required this.createdAtEpochMs,
    required this.lastUsedAtEpochMs,
  });

  final String id;
  final String name;
  final MetronomeConfig config;
  final int createdAtEpochMs;
  final int lastUsedAtEpochMs;

  MetronomePreset copyWith({
    String? id,
    String? name,
    MetronomeConfig? config,
    int? createdAtEpochMs,
    int? lastUsedAtEpochMs,
  }) {
    return MetronomePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      config: config ?? this.config,
      createdAtEpochMs: createdAtEpochMs ?? this.createdAtEpochMs,
      lastUsedAtEpochMs: lastUsedAtEpochMs ?? this.lastUsedAtEpochMs,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      "id": id,
      "name": name,
      "config": config.toJson(),
      "createdAtEpochMs": createdAtEpochMs,
      "lastUsedAtEpochMs": lastUsedAtEpochMs,
    };
  }

  factory MetronomePreset.fromJson(Map<String, dynamic> json) {
    return MetronomePreset(
      id: json["id"] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
      name: json["name"] as String? ?? "未命名预设",
      config: MetronomeConfig.fromJson(
        (json["config"] as Map<String, dynamic>?) ?? <String, dynamic>{},
      ),
      createdAtEpochMs: (json["createdAtEpochMs"] as num?)?.round() ??
          DateTime.now().millisecondsSinceEpoch,
      lastUsedAtEpochMs: (json["lastUsedAtEpochMs"] as num?)?.round() ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class StoredAppState {
  const StoredAppState({
    required this.settings,
    required this.presets,
  });

  final AppSettings settings;
  final List<MetronomePreset> presets;
}

String tempoTerm(int bpm) {
  if (bpm < 40) {
    return "Grave";
  }
  if (bpm < 60) {
    return "Largo";
  }
  if (bpm < 76) {
    return "Adagio";
  }
  if (bpm < 108) {
    return "Andante";
  }
  if (bpm < 120) {
    return "Moderato";
  }
  if (bpm < 156) {
    return "Allegro";
  }
  if (bpm < 176) {
    return "Vivace";
  }
  return "Presto";
}

String formatDateTime(int epochMs) {
  final DateTime dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, "0");

  return "${dt.year}-${two(dt.month)}-${two(dt.day)} "
      "${two(dt.hour)}:${two(dt.minute)}";
}
