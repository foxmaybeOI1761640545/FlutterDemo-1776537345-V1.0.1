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

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF151E37), Color(0xFF222945), Color(0xFF0E1327)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                Text("璁剧疆", style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("闊抽", style: theme.textTheme.titleMedium),
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
                        Text("闊宠壊", style: theme.textTheme.titleSmall),
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
                        Text("榛樿鍙傛暟", style: theme.textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Text("榛樿 BPM: ${settings.defaultBpm}"),
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
                        Text("榛樿鎷嶅彿", style: theme.textTheme.titleSmall),
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
                        Text("榛樿鍒囧垎", style: theme.textTheme.titleSmall),
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
                        Text("鐣岄潰涓庢暟鎹?, style: theme.textTheme.titleMedium),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("娣辫壊涓婚"),
                          value: settings.darkTheme,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(darkTheme: value));
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text("瑙嗚鎻愮ず锛堝綋鍓嶆媿楂樹寒锛?),
                          value: settings.visualHints,
                          onChanged: (bool value) {
                            onSettingsChanged(settings.copyWith(visualHints: value));
                          },
                        ),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: onClearLocalData,
                          icon: const Icon(Icons.cleaning_services_rounded),
                          label: const Text("娓呯悊鏈湴鏁版嵁"),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "绂荤嚎杩愯锛屼笉渚濊禆璐﹀彿涓庣綉缁溿€?,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "鍏充簬搴旂敤锛歅ulseBeat MVP v2.0.1",
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
