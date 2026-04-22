import "dart:math" as math;

import "package:flutter/material.dart";

import "../l10n/app_locale.dart";
import "../metronome_engine.dart";
import "../models.dart";
import "../widgets/section_pill_button.dart";
import "ear_training_page.dart";
import "metronome_page.dart";
import "presets_page.dart";
import "settings_page.dart";

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.settings,
    required this.presets,
    required this.onSettingsChanged,
    required this.onPresetsChanged,
    required this.onClearLocalData,
    super.key,
  });

  final AppSettings settings;
  final List<MetronomePreset> presets;
  final ValueChanged<AppSettings> onSettingsChanged;
  final ValueChanged<List<MetronomePreset>> onPresetsChanged;
  final Future<void> Function() onClearLocalData;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late MetronomeConfig _config;
  late final MetronomeEngine _engine;

  int _mainTab = 0;
  int _metronomeTab = 0;
  int _activeBeat = -1;
  int _activeSubTick = -1;
  final List<DateTime> _tapRecords = <DateTime>[];

  @override
  void initState() {
    super.initState();
    _config = MetronomeConfig.fromSettings(widget.settings).normalized();
    _engine = MetronomeEngine(
      onTick: _handleTick,
      onStop: _handlePlaybackStop,
    )
      ..updateConfig(_config)
      ..updateAudio(volume: widget.settings.volume, tone: widget.settings.tone);
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.volume != widget.settings.volume ||
        oldWidget.settings.tone != widget.settings.tone) {
      _engine.updateAudio(volume: widget.settings.volume, tone: widget.settings.tone);
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  bool get _isPlaying => _engine.isPlaying;

  void _handleTick(int beat, int subTick) {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBeat = beat;
      _activeSubTick = subTick;
    });
  }

  void _handlePlaybackStop() {
    if (!mounted) {
      return;
    }
    setState(() {
      _activeBeat = -1;
      _activeSubTick = -1;
    });
  }

  void _applyConfig(MetronomeConfig next) {
    final MetronomeConfig normalized = next.normalized();
    setState(() {
      _config = normalized;
    });
    _engine.updateConfig(normalized);
  }

  void _setBpm(int bpm) {
    _applyConfig(_config.copyWith(bpm: bpm.clamp(kMinBpm, kMaxBpm).toInt()));
  }

  void _changeBpmBy(int delta) {
    _setBpm((_config.bpm + delta).clamp(kMinBpm, kMaxBpm).toInt());
  }

  void _setTimeSignature(String key) {
    final TimeSignatureDefinition signature = resolveSignature(key);
    final List<AccentLevel> nextAccents = List<AccentLevel>.generate(
      signature.numerator,
      (int index) {
        if (index < _config.accents.length) {
          return _config.accents[index];
        }
        return index == 0 ? AccentLevel.strong : AccentLevel.normal;
      },
    );
    _applyConfig(
      _config.copyWith(
        timeSignature: signature.key,
        accents: nextAccents,
      ),
    );
  }

  void _setSubdivision(Subdivision subdivision) {
    _applyConfig(_config.copyWith(subdivision: subdivision));
  }

  void _setAccent(int beatIndex, AccentLevel level) {
    if (beatIndex < 0 || beatIndex >= _config.accents.length) {
      return;
    }
    final List<AccentLevel> nextAccents = List<AccentLevel>.from(_config.accents);
    nextAccents[beatIndex] = level;
    _applyConfig(_config.copyWith(accents: nextAccents));
  }

  void _togglePlayback() {
    if (_isPlaying) {
      _engine.stop();
      setState(() {
        _activeBeat = -1;
        _activeSubTick = -1;
      });
      return;
    }
    _engine.start();
    setState(() {});
  }

  void _tapTempo() {
    final DateTime now = DateTime.now();
    if (_tapRecords.isNotEmpty && now.difference(_tapRecords.last) > const Duration(seconds: 2)) {
      _tapRecords.clear();
    }
    _tapRecords.add(now);
    if (_tapRecords.length > 8) {
      _tapRecords.removeAt(0);
    }

    if (_tapRecords.length >= 4) {
      double total = 0;
      for (int i = 1; i < _tapRecords.length; i++) {
        total += _tapRecords[i].difference(_tapRecords[i - 1]).inMilliseconds;
      }
      final double averageMs = total / (_tapRecords.length - 1);
      if (averageMs > 0) {
        _setBpm((60000 / averageMs).round());
      }
    }
    setState(() {});
  }

  Future<void> _saveCurrentPreset() async {
    final TextEditingController controller = TextEditingController(
      text: context.tr(
        zh: "预设 ${widget.presets.length + 1}",
        en: "Preset ${widget.presets.length + 1}",
      ),
    );
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.tr(zh: "保存预设", en: "Save Preset")),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            decoration: InputDecoration(
              hintText: context.tr(
                zh: "示例：慢速 C 大调",
                en: "Example: Slow C Major",
              ),
            ),
            onSubmitted: (String value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr(zh: "取消", en: "Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(context.tr(zh: "保存", en: "Save")),
            ),
          ],
        );
      },
    );

    if (name == null || name.trim().isEmpty) {
      return;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final MetronomePreset preset = MetronomePreset(
      id: "${now}_${math.Random().nextInt(99999)}",
      name: name.trim(),
      config: _config,
      createdAtEpochMs: now,
      lastUsedAtEpochMs: now,
    );

    widget.onPresetsChanged(
      <MetronomePreset>[preset, ...widget.presets].take(kMaxPresetCount).toList(),
    );

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.tr(
            zh: "预设已保存：${preset.name}",
            en: "Preset saved: ${preset.name}",
          ),
        ),
      ),
    );
  }

  void _loadPreset(MetronomePreset preset, {bool switchToMain = false}) {
    _applyConfig(preset.config);
    final int now = DateTime.now().millisecondsSinceEpoch;
    final List<MetronomePreset> updated = widget.presets
        .map(
          (MetronomePreset item) => item.id == preset.id
              ? item.copyWith(lastUsedAtEpochMs: now)
              : item,
        )
        .toList();
    widget.onPresetsChanged(updated);
    if (switchToMain) {
      setState(() {
        _mainTab = 1;
        _metronomeTab = 0;
      });
    }
  }

  void _deletePreset(String presetId) {
    widget.onPresetsChanged(
      widget.presets.where((MetronomePreset p) => p.id != presetId).toList(),
    );
  }

  void _updateSettings(AppSettings settings) {
    widget.onSettingsChanged(settings);
    if (settings.volume != widget.settings.volume || settings.tone != widget.settings.tone) {
      _engine.updateAudio(volume: settings.volume, tone: settings.tone);
    }
  }

  void _updateLanguage(AppLanguage language) {
    _updateSettings(widget.settings.copyWith(language: language));
  }

  Future<void> _clearAllLocalData() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(context.tr(zh: "清除本地数据", en: "Clear Local Data")),
          content: Text(
            context.tr(
              zh: "该操作会重置设置并删除全部预设，且无法撤销。",
              en: "This resets settings and removes all presets. This action cannot be undone.",
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.tr(zh: "取消", en: "Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.tr(zh: "清除", en: "Clear")),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    _engine.stop();
    await widget.onClearLocalData();
    final AppSettings defaults = AppSettings.defaults();
    _engine.updateAudio(volume: defaults.volume, tone: defaults.tone);
    _applyConfig(MetronomeConfig.fromSettings(defaults));

    setState(() {
      _tapRecords.clear();
      _activeBeat = -1;
      _activeSubTick = -1;
      _mainTab = 1;
      _metronomeTab = 0;
    });
  }

  void _switchMainTab(int index) {
    if (_mainTab == index) {
      return;
    }
    if (index == 0 && _isPlaying) {
      _engine.stop();
      _handlePlaybackStop();
    }
    setState(() {
      _mainTab = index;
    });
  }

  Widget _buildMetronomeSubTabs(BuildContext context) {
    final List<_MetronomeSubTabItem> tabs = <_MetronomeSubTabItem>[
      _MetronomeSubTabItem(
        index: 0,
        icon: Icons.speed_rounded,
        label: context.tr(zh: "节拍器", en: "Metronome"),
      ),
      _MetronomeSubTabItem(
        index: 1,
        icon: Icons.library_music_rounded,
        label: context.tr(zh: "预设", en: "Presets"),
      ),
      _MetronomeSubTabItem(
        index: 2,
        icon: Icons.settings_rounded,
        label: context.tr(zh: "设置", en: "Settings"),
      ),
    ];

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List<Widget>.generate(tabs.length * 2 - 1, (int index) {
              if (index.isOdd) {
                return const SizedBox(width: 10);
              }
              final _MetronomeSubTabItem item = tabs[index ~/ 2];
              final bool selected = _metronomeTab == item.index;
              return SectionPillButton(
                icon: item.icon,
                label: item.label,
                selected: selected,
                onPressed: selected
                    ? null
                    : () {
                        setState(() {
                          _metronomeTab = item.index;
                        });
                      },
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildMetronomeWorkspace(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildMetronomeSubTabs(context),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: IndexedStack(
              index: _metronomeTab,
              children: <Widget>[
                MetronomePage(
                  config: _config,
                  language: widget.settings.language,
                  isPlaying: _isPlaying,
                  activeBeat: _activeBeat,
                  activeSubTick: _activeSubTick,
                  visualHintsEnabled: widget.settings.visualHints,
                  tapCount: _tapRecords.length,
                  onBpmMinus: () => _changeBpmBy(-1),
                  onBpmPlus: () => _changeBpmBy(1),
                  onSetBpm: _setBpm,
                  onTimeSignatureChanged: _setTimeSignature,
                  onSubdivisionChanged: _setSubdivision,
                  onAccentChanged: _setAccent,
                  onTogglePlay: _togglePlayback,
                  onTapTempo: _tapTempo,
                  onOpenPresets: () => setState(() => _metronomeTab = 1),
                  onOpenSettings: () => setState(() => _metronomeTab = 2),
                ),
                PresetsPage(
                  presets: widget.presets,
                  onSaveCurrent: _saveCurrentPreset,
                  onLoadPreset: (MetronomePreset preset) =>
                      _loadPreset(preset, switchToMain: true),
                  onDeletePreset: _deletePreset,
                ),
                SettingsPage(
                  settings: widget.settings,
                  onSettingsChanged: _updateSettings,
                  onClearLocalData: _clearAllLocalData,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _mainTab,
        children: <Widget>[
          EarTrainingPage(
            isActive: _mainTab == 0,
            onLanguageChanged: _updateLanguage,
          ),
          _buildMetronomeWorkspace(context),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mainTab,
        onDestinationSelected: _switchMainTab,
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.hearing_rounded),
            label: context.tr(zh: "听音", en: "Ear"),
          ),
          NavigationDestination(
            icon: const Icon(Icons.speed_rounded),
            label: context.tr(zh: "节拍器", en: "Metronome"),
          ),
        ],
      ),
    );
  }
}

class _MetronomeSubTabItem {
  const _MetronomeSubTabItem({
    required this.index,
    required this.icon,
    required this.label,
  });

  final int index;
  final IconData icon;
  final String label;
}
