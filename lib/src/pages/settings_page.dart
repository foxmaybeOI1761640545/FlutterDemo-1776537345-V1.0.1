import "package:flutter/material.dart";

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
                Text("Settings", style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Audio", style: theme.textTheme.titleMedium),
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
                        Text("Tone", style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: MetronomeTone.values.map((MetronomeTone tone) {
                            return ChoiceChip(
                              label: Text(tone.label),
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
                        Text("Default Parameters", style: theme.textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Text("Default BPM: ${settings.defaultBpm}"),
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
                        Text("Default Time Signature", style: theme.textTheme.titleSmall),
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
                        Text("Default Subdivision", style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: Subdivision.values.map((Subdivision item) {
                            return ChoiceChip(
                              label: Text(item.label),
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
                        Text("UI & Data", style: theme.textTheme.titleMedium),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Dark theme"),
                          value: settings.darkTheme,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(darkTheme: value));
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("Visual hints (highlight active beat)"),
                          value: settings.visualHints,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(visualHints: value));
                          },
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: onClearLocalData,
                          icon: const Icon(Icons.cleaning_services_rounded),
                          label: const Text("Clear local data"),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Offline mode. No account or network required.",
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "About: PulseBeat MVP v2.0.9",
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
