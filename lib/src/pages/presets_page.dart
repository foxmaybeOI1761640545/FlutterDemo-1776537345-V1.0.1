import "package:flutter/material.dart";

import "../l10n/app_locale.dart";
import "../models.dart";

class PresetsPage extends StatelessWidget {
  const PresetsPage({
    required this.presets,
    required this.onSaveCurrent,
    required this.onLoadPreset,
    required this.onDeletePreset,
    super.key,
  });

  final List<MetronomePreset> presets;
  final VoidCallback onSaveCurrent;
  final ValueChanged<MetronomePreset> onLoadPreset;
  final ValueChanged<String> onDeletePreset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLanguage language = context.appLanguage;
    final bool isDark = theme.brightness == Brightness.dark;
    final List<Color> backgroundGradient = isDark
        ? <Color>[
            Color.alphaBlend(colorScheme.primary.withOpacity(0.09), colorScheme.surface),
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.08), colorScheme.surface),
            colorScheme.surface,
          ]
        : <Color>[
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.2), colorScheme.surface),
            Color.alphaBlend(colorScheme.primary.withOpacity(0.1), colorScheme.surface),
            colorScheme.surface,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: backgroundGradient,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        context.tr(zh: "预设管理", en: "Presets"),
                        style: theme.textTheme.headlineSmall,
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onSaveCurrent,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                          context.tr(zh: "保存当前配置", en: "Save Current"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: presets.isEmpty
                        ? Card(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  context.tr(
                                    zh: "还没有预设，先在节拍器页调整参数后点击保存。",
                                    en: "No presets yet. Configure metronome and tap save.",
                                  ),
                                  style: theme.textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: presets.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (BuildContext context, int index) {
                              final MetronomePreset preset = presets[index];
                              return Card(
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  title: Text(
                                    preset.name,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      "${preset.config.bpm} BPM"
                                      " | ${preset.config.timeSignature}"
                                      " | ${preset.config.subdivision.labelFor(language)}"
                                      " | ${context.tr(zh: "最近使用", en: "Last used")} "
                                      "${formatDateTime(preset.lastUsedAtEpochMs)}",
                                    ),
                                  ),
                                  trailing: Wrap(
                                    spacing: 6,
                                    children: <Widget>[
                                      IconButton(
                                        tooltip: context.tr(zh: "加载预设", en: "Load preset"),
                                        onPressed: () => onLoadPreset(preset),
                                        icon: const Icon(Icons.playlist_add_check_rounded),
                                      ),
                                      IconButton(
                                        tooltip: context.tr(zh: "删除", en: "Delete"),
                                        onPressed: () => onDeletePreset(preset.id),
                                        icon: const Icon(Icons.delete_outline_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
