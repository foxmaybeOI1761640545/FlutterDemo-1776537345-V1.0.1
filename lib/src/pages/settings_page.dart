import "package:flutter/material.dart";

import "../l10n/app_locale.dart";
import "../models.dart";

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.settings,
    required this.onSettingsChanged,
    required this.onClearLocalData,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;
  final VoidCallback onClearLocalData;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLanguage language = context.appLanguage;
    final bool isDark = theme.brightness == Brightness.dark;
    final List<Color> backgroundGradient = isDark
        ? <Color>[
            Color.alphaBlend(colorScheme.primary.withOpacity(0.1), colorScheme.surface),
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.08), colorScheme.surface),
            colorScheme.surface,
          ]
        : <Color>[
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.18), colorScheme.surface),
            Color.alphaBlend(colorScheme.primary.withOpacity(0.11), colorScheme.surface),
            colorScheme.surface,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: backgroundGradient,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                Text(
                  context.tr(zh: "设置", en: "Settings"),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr(zh: "音频", en: "Audio"),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.volume_up_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Slider(
                                value: settings.volume,
                                min: 0,
                                max: 1,
                                divisions: 20,
                                label: "${(settings.volume * 100).round()}%",
                                onChanged: (double value) {
                                  onSettingsChanged(settings.copyWith(volume: value));
                                },
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: Text(
                                "${(settings.volume * 100).round()}%",
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(zh: "音色", en: "Tone"),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: MetronomeTone.values.map((MetronomeTone tone) {
                            return ChoiceChip(
                              label: Text(tone.labelFor(language)),
                              selected: tone == settings.tone,
                              onSelected: (_) {
                                onSettingsChanged(settings.copyWith(tone: tone));
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr(zh: "默认参数", en: "Default Parameters"),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.tr(
                            zh: "默认 BPM: ${settings.defaultBpm}",
                            en: "Default BPM: ${settings.defaultBpm}",
                          ),
                        ),
                        Slider(
                          value: settings.defaultBpm.toDouble(),
                          min: kMinBpm.toDouble(),
                          max: kMaxBpm.toDouble(),
                          divisions: kMaxBpm - kMinBpm,
                          label: settings.defaultBpm.toString(),
                          onChanged: (double value) {
                            onSettingsChanged(
                              settings.copyWith(defaultBpm: value.round()),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          context.tr(zh: "默认拍号", en: "Default Time Signature"),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kSupportedSignatures.map((TimeSignatureDefinition item) {
                            return ChoiceChip(
                              label: Text(item.key),
                              selected: item.key == settings.defaultTimeSignature,
                              onSelected: (_) {
                                onSettingsChanged(
                                  settings.copyWith(defaultTimeSignature: item.key),
                                );
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(zh: "默认切分", en: "Default Subdivision"),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: Subdivision.values.map((Subdivision item) {
                            return ChoiceChip(
                              label: Text(item.labelFor(language)),
                              selected: item == settings.defaultSubdivision,
                              onSelected: (_) {
                                onSettingsChanged(
                                  settings.copyWith(defaultSubdivision: item),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          context.tr(zh: "界面与数据", en: "UI & Data"),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(zh: "语言", en: "Language"),
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            ChoiceChip(
                              label: Text(context.tr(zh: "中文", en: "Chinese")),
                              selected: settings.language == AppLanguage.zh,
                              onSelected: (_) {
                                onSettingsChanged(
                                  settings.copyWith(language: AppLanguage.zh),
                                );
                              },
                            ),
                            ChoiceChip(
                              label: Text(context.tr(zh: "英文", en: "English")),
                              selected: settings.language == AppLanguage.en,
                              onSelected: (_) {
                                onSettingsChanged(
                                  settings.copyWith(language: AppLanguage.en),
                                );
                              },
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            context.tr(zh: "深色主题", en: "Dark Theme"),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: settings.darkTheme,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(darkTheme: value));
                          },
                        ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          title: Text(
                            context.tr(
                              zh: "视觉提示（高亮当前拍）",
                              en: "Visual Hints (Highlight Active Beat)",
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value: settings.visualHints,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(visualHints: value));
                          },
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: onClearLocalData,
                          icon: const Icon(Icons.cleaning_services_rounded),
                          label: Text(
                            context.tr(zh: "清除本地数据", en: "Clear Local Data"),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.tr(
                            zh: "离线模式，无需账号和网络。",
                            en: "Offline mode. No account or network required.",
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(zh: "关于：PulseBeat", en: "About: PulseBeat"),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
