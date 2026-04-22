import "package:flutter/material.dart";

import "../models.dart";
import "../widgets/repeat_action_icon_button.dart";

class MetronomePage extends StatelessWidget {
  const MetronomePage({
    required this.config,
    required this.language,
    required this.isPlaying,
    required this.activeBeat,
    required this.activeSubTick,
    required this.visualHintsEnabled,
    required this.tapCount,
    required this.onBpmMinus,
    required this.onBpmPlus,
    required this.onSetBpm,
    required this.onTimeSignatureChanged,
    required this.onSubdivisionChanged,
    required this.onAccentChanged,
    required this.onTogglePlay,
    required this.onTapTempo,
    required this.onOpenPresets,
    required this.onOpenSettings,
    super.key,
  });

  final MetronomeConfig config;
  final AppLanguage language;
  final bool isPlaying;
  final int activeBeat;
  final int activeSubTick;
  final bool visualHintsEnabled;
  final int tapCount;
  final VoidCallback onBpmMinus;
  final VoidCallback onBpmPlus;
  final ValueChanged<int> onSetBpm;
  final ValueChanged<String> onTimeSignatureChanged;
  final ValueChanged<Subdivision> onSubdivisionChanged;
  final void Function(int beatIndex, AccentLevel level) onAccentChanged;
  final VoidCallback onTogglePlay;
  final VoidCallback onTapTempo;
  final VoidCallback onOpenPresets;
  final VoidCallback onOpenSettings;

  Future<void> _showBpmInputDialog(BuildContext context) async {
    String t({required String zh, required String en}) {
      return language == AppLanguage.zh ? zh : en;
    }

    final TextEditingController controller =
        TextEditingController(text: config.bpm.toString());
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(t(zh: "输入 BPM", en: "Input BPM")),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: "20 - 240"),
            onSubmitted: (String value) {
              final int? parsed = int.tryParse(value);
              if (parsed != null) {
                Navigator.of(context).pop(parsed);
              }
            },
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t(zh: "取消", en: "Cancel")),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(int.tryParse(controller.text.trim()));
              },
              child: Text(t(zh: "确认", en: "Confirm")),
            ),
          ],
        );
      },
    );
    if (result != null) {
      onSetBpm(result.clamp(kMinBpm, kMaxBpm).toInt());
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TimeSignatureDefinition signature = resolveSignature(config.timeSignature);
    final bool wideLayout = MediaQuery.sizeOf(context).width >= 980;
    final bool isDark = theme.brightness == Brightness.dark;
    final List<Color> backgroundGradient = isDark
        ? <Color>[
            Color.alphaBlend(colorScheme.primary.withOpacity(0.11), colorScheme.surface),
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.08), colorScheme.surface),
            Color.alphaBlend(colorScheme.tertiary.withOpacity(0.08), colorScheme.surface),
            colorScheme.surface,
          ]
        : <Color>[
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.2), colorScheme.surface),
            Color.alphaBlend(colorScheme.primary.withOpacity(0.12), colorScheme.surface),
            Color.alphaBlend(colorScheme.tertiary.withOpacity(0.08), colorScheme.surface),
            colorScheme.surface,
          ];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: backgroundGradient,
          stops: <double>[0, 0.35, 0.72, 1],
        ),
      ),
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wideLayout ? 1120 : 860),
              child: wideLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          flex: 7,
                          child: _MainPanel(
                            theme: theme,
                            language: language,
                            config: config,
                            signature: signature,
                            isPlaying: isPlaying,
                            activeBeat: activeBeat,
                            activeSubTick: activeSubTick,
                            visualHintsEnabled: visualHintsEnabled,
                            tapCount: tapCount,
                            onBpmMinus: onBpmMinus,
                            onBpmPlus: onBpmPlus,
                            onRequestBpmInput: () => _showBpmInputDialog(context),
                            onTimeSignatureChanged: onTimeSignatureChanged,
                            onSubdivisionChanged: onSubdivisionChanged,
                            onAccentChanged: onAccentChanged,
                            onTogglePlay: onTogglePlay,
                            onTapTempo: onTapTempo,
                            onOpenPresets: onOpenPresets,
                            onOpenSettings: onOpenSettings,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: _SidePanel(
                            language: language,
                            config: config,
                            isPlaying: isPlaying,
                            tapCount: tapCount,
                            onTogglePlay: onTogglePlay,
                            onTapTempo: onTapTempo,
                            onBpmMinus: onBpmMinus,
                            onBpmPlus: onBpmPlus,
                            onRequestBpmInput: () => _showBpmInputDialog(context),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: <Widget>[
                        _MainPanel(
                          theme: theme,
                          language: language,
                          config: config,
                          signature: signature,
                          isPlaying: isPlaying,
                          activeBeat: activeBeat,
                          activeSubTick: activeSubTick,
                          visualHintsEnabled: visualHintsEnabled,
                          tapCount: tapCount,
                          onBpmMinus: onBpmMinus,
                          onBpmPlus: onBpmPlus,
                          onRequestBpmInput: () => _showBpmInputDialog(context),
                          onTimeSignatureChanged: onTimeSignatureChanged,
                          onSubdivisionChanged: onSubdivisionChanged,
                          onAccentChanged: onAccentChanged,
                          onTogglePlay: onTogglePlay,
                          onTapTempo: onTapTempo,
                          onOpenPresets: onOpenPresets,
                          onOpenSettings: onOpenSettings,
                        ),
                        const SizedBox(height: 16),
                        _SidePanel(
                          language: language,
                          config: config,
                          isPlaying: isPlaying,
                          tapCount: tapCount,
                          onTogglePlay: onTogglePlay,
                          onTapTempo: onTapTempo,
                          onBpmMinus: onBpmMinus,
                          onBpmPlus: onBpmPlus,
                          onRequestBpmInput: () => _showBpmInputDialog(context),
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

class _MainPanel extends StatelessWidget {
  const _MainPanel({
    required this.theme,
    required this.language,
    required this.config,
    required this.signature,
    required this.isPlaying,
    required this.activeBeat,
    required this.activeSubTick,
    required this.visualHintsEnabled,
    required this.tapCount,
    required this.onBpmMinus,
    required this.onBpmPlus,
    required this.onRequestBpmInput,
    required this.onTimeSignatureChanged,
    required this.onSubdivisionChanged,
    required this.onAccentChanged,
    required this.onTogglePlay,
    required this.onTapTempo,
    required this.onOpenPresets,
    required this.onOpenSettings,
  });

  final ThemeData theme;
  final AppLanguage language;
  final MetronomeConfig config;
  final TimeSignatureDefinition signature;
  final bool isPlaying;
  final int activeBeat;
  final int activeSubTick;
  final bool visualHintsEnabled;
  final int tapCount;
  final VoidCallback onBpmMinus;
  final VoidCallback onBpmPlus;
  final VoidCallback onRequestBpmInput;
  final ValueChanged<String> onTimeSignatureChanged;
  final ValueChanged<Subdivision> onSubdivisionChanged;
  final void Function(int beatIndex, AccentLevel level) onAccentChanged;
  final VoidCallback onTogglePlay;
  final VoidCallback onTapTempo;
  final VoidCallback onOpenPresets;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    String t({required String zh, required String en}) {
      return language == AppLanguage.zh ? zh : en;
    }

    final Color titleColor = theme.colorScheme.onSurface.withOpacity(0.74);
    final bool compactMetrics = MediaQuery.sizeOf(context).width < 600;
    final List<Widget> metricCards = <Widget>[
      _MetricCard(
        title: t(zh: "速度 BPM", en: "Tempo BPM"),
        value: config.bpm.toString(),
        subtitle: tempoTermForLanguage(config.bpm, language),
        onTap: onRequestBpmInput,
        width: compactMetrics ? double.infinity : 170,
      ),
      _MetricCard(
        title: t(zh: "拍号", en: "Time Signature"),
        value: signature.key,
        subtitle: t(
          zh: "每小节 ${signature.numerator} 拍",
          en: "${signature.numerator} beats per bar",
        ),
        width: compactMetrics ? double.infinity : 170,
      ),
      _MetricCard(
        title: t(zh: "切分", en: "Subdivision"),
        value: config.subdivision.labelFor(language),
        subtitle: t(
          zh: "${config.subdivision.ticksPerBeat} tick/拍",
          en: "${config.subdivision.ticksPerBeat} ticks/beat",
        ),
        width: compactMetrics ? double.infinity : 170,
      ),
      _MetricCard(
        title: t(zh: "状态", en: "State"),
        value: isPlaying
            ? t(zh: "播放中", en: "Playing")
            : t(zh: "已停止", en: "Stopped"),
        subtitle: isPlaying
            ? t(
                zh: "第 ${(activeBeat < 0 ? 0 : activeBeat) + 1} 拍",
                en: "Beat ${(activeBeat < 0 ? 0 : activeBeat) + 1}",
              )
            : t(zh: "准备开始", en: "Ready"),
        width: compactMetrics ? double.infinity : 170,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.graphic_eq_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  t(zh: "PulseBeat 离线节拍器", en: "PulseBeat Offline Metronome"),
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(onPressed: onOpenPresets, icon: const Icon(Icons.bookmarks_rounded)),
                IconButton(onPressed: onOpenSettings, icon: const Icon(Icons.settings_rounded)),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                if (!compactMetrics) {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: metricCards,
                  );
                }

                const double spacing = 8;
                final double cardWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: metricCards
                      .map((Widget card) => SizedBox(width: cardWidth, child: card))
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 18),
            Text(t(zh: "重音编辑", en: "Accent Matrix"), style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            _AccentMatrix(
              language: language,
              signature: signature,
              accents: config.accents,
              activeBeat: activeBeat,
              visualHintsEnabled: visualHintsEnabled,
              onAccentChanged: onAccentChanged,
            ),
            const SizedBox(height: 18),
            Text(
              t(zh: "拍号切换", en: "Time Signature"),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kSupportedSignatures.map((TimeSignatureDefinition item) {
                final bool selected = item.key == config.timeSignature;
                return ChoiceChip(
                  label: Text(item.key),
                  selected: selected,
                  onSelected: (_) => onTimeSignatureChanged(item.key),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Text(t(zh: "切分", en: "Subdivision"), style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Subdivision.values.map((Subdivision subdivision) {
                return ChoiceChip(
                  label: Text(
                    subdivision.labelFor(language),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                  showCheckmark: false,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  selected: subdivision == config.subdivision,
                  onSelected: (_) => onSubdivisionChanged(subdivision),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    t(
                      zh:
                          "播放指示: ${visualHintsEnabled ? "已开启" : "已关闭"} | 当前切分 tick ${activeSubTick < 0 ? 0 : activeSubTick + 1}",
                      en:
                          "Visual hints: ${visualHintsEnabled ? "On" : "Off"} | Current subdivision tick ${activeSubTick < 0 ? 0 : activeSubTick + 1}",
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(color: titleColor),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: onTapTempo,
                  icon: const Icon(Icons.touch_app_rounded),
                  label: Text(
                    tapCount >= 4
                        ? t(zh: "TAP ($tapCount)", en: "TAP ($tapCount)")
                        : "TAP",
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                RepeatActionIconButton(
                  icon: Icons.remove_rounded,
                  tooltip: t(zh: "减速", en: "Slower"),
                  onPressed: onBpmMinus,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTogglePlay,
                    icon: Icon(
                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(
                      isPlaying ? t(zh: "暂停", en: "Pause") : t(zh: "开始播放", en: "Play"),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                RepeatActionIconButton(
                  icon: Icons.add_rounded,
                  tooltip: t(zh: "加速", en: "Faster"),
                  onPressed: onBpmPlus,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onRequestBpmInput,
                icon: const Icon(Icons.keyboard_rounded),
                label: Text(
                  t(
                    zh: "输入 BPM (${config.bpm})",
                    en: "Input BPM (${config.bpm})",
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.language,
    required this.config,
    required this.isPlaying,
    required this.tapCount,
    required this.onTogglePlay,
    required this.onTapTempo,
    required this.onBpmMinus,
    required this.onBpmPlus,
    required this.onRequestBpmInput,
  });

  final AppLanguage language;
  final MetronomeConfig config;
  final bool isPlaying;
  final int tapCount;
  final VoidCallback onTogglePlay;
  final VoidCallback onTapTempo;
  final VoidCallback onBpmMinus;
  final VoidCallback onBpmPlus;
  final VoidCallback onRequestBpmInput;

  @override
  Widget build(BuildContext context) {
    String t({required String zh, required String en}) {
      return language == AppLanguage.zh ? zh : en;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            _PlayDial(
              language: language,
              isPlaying: isPlaying,
              bpm: config.bpm,
              onTogglePlay: onTogglePlay,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: RepeatActionFilledButton(
                    onPressed: onBpmMinus,
                    tooltip: t(zh: "按住持续减速", en: "Hold to decrease continuously"),
                    child: const Text("-1 BPM"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: RepeatActionFilledButton(
                    onPressed: onBpmPlus,
                    tooltip: t(zh: "按住持续加速", en: "Hold to increase continuously"),
                    child: const Text("+1 BPM"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: onRequestBpmInput,
              icon: const Icon(Icons.keyboard_rounded),
              label: Text(
                t(
                  zh: "输入 BPM (${config.bpm})",
                  en: "Input BPM (${config.bpm})",
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: onTapTempo,
              child: Text(tapCount >= 4 ? "TAP $tapCount" : "TAP"),
            ),
            const SizedBox(height: 8),
            Text(
              t(
                zh: "拍号 ${config.timeSignature} | 切分 ${config.subdivision.labelFor(language)}",
                en:
                    "Time signature ${config.timeSignature} | Subdivision ${config.subdivision.labelFor(language)}",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    this.onTap,
    this.width = 170,
  });

  final String title;
  final String value;
  final String subtitle;
  final VoidCallback? onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: width,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: theme.colorScheme.outline.withOpacity(0.24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary)),
              const SizedBox(height: 3),
              Text(subtitle, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentMatrix extends StatelessWidget {
  const _AccentMatrix({
    required this.language,
    required this.signature,
    required this.accents,
    required this.activeBeat,
    required this.visualHintsEnabled,
    required this.onAccentChanged,
  });

  final AppLanguage language;
  final TimeSignatureDefinition signature;
  final List<AccentLevel> accents;
  final int activeBeat;
  final bool visualHintsEnabled;
  final void Function(int beatIndex, AccentLevel level) onAccentChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<AccentLevel> rowOrder = <AccentLevel>[
      AccentLevel.strong,
      AccentLevel.normal,
      AccentLevel.weak,
      AccentLevel.mute,
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: theme.colorScheme.surface.withOpacity(0.45),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.24)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              const SizedBox(width: 38),
              for (int beat = 0; beat < signature.numerator; beat++)
                Expanded(child: Center(child: Text("${beat + 1}"))),
            ],
          ),
          const SizedBox(height: 6),
          for (final AccentLevel level in rowOrder)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 38, child: Text(level.shortLabelFor(language))),
                  for (int beat = 0; beat < signature.numerator; beat++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: _AccentCell(
                          selected: accents[beat] == level,
                          active: visualHintsEnabled && activeBeat == beat,
                          color: level.color(theme),
                          onTap: () => onAccentChanged(beat, level),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccentCell extends StatelessWidget {
  const _AccentCell({
    required this.selected,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final bool selected;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              width: active ? 1.6 : 1,
              color: active
                  ? colorScheme.primary
                  : theme.colorScheme.outline.withOpacity(0.35),
            ),
            color: selected ? color.withOpacity(active ? 0.84 : 0.6) : Colors.transparent,
          ),
        ),
      ),
    );
  }
}

class _PlayDial extends StatelessWidget {
  const _PlayDial({
    required this.language,
    required this.isPlaying,
    required this.bpm,
    required this.onTogglePlay,
  });

  final AppLanguage language;
  final bool isPlaying;
  final int bpm;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    String t({required String zh, required String en}) {
      return language == AppLanguage.zh ? zh : en;
    }

    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTogglePlay,
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              theme.colorScheme.surface.withOpacity(0.95),
              theme.colorScheme.surface.withOpacity(0.72),
              theme.colorScheme.primary.withOpacity(0.2),
            ],
            stops: const <double>[0.52, 0.85, 1],
          ),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.24)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isPlaying ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 54,
                color: isPlaying ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 18),
            Text("$bpm BPM", style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 4),
            Text(
              isPlaying ? t(zh: "点击暂停", en: "Tap to pause") : t(zh: "点击开始", en: "Tap to play"),
            ),
          ],
        ),
      ),
    );
  }
}

