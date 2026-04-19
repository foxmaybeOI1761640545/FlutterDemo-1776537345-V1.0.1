import "package:flutter/material.dart";

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

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xFF101A36), Color(0xFF0F1326)],
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
                      Text("预设管理", style: theme.textTheme.headlineSmall),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: onSaveCurrent,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text("保存当前配置"),
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
                                  "还没有预设，先在节拍器页调整参数后点击保存。",
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
                                  title: Text(preset.name, style: theme.textTheme.titleMedium),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      "${preset.config.bpm} BPM"
                                      " | ${preset.config.timeSignature}"
                                      " | ${preset.config.subdivision.label}"
                                      " | 最近使用 ${formatDateTime(preset.lastUsedAtEpochMs)}",
                                    ),
                                  ),
                                  trailing: Wrap(
                                    spacing: 6,
                                    children: <Widget>[
                                      IconButton(
                                        tooltip: "加载预设",
                                        onPressed: () => onLoadPreset(preset),
                                        icon: const Icon(Icons.playlist_add_check_rounded),
                                      ),
                                      IconButton(
                                        tooltip: "删除",
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
