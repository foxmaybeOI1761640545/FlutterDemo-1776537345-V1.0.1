import "dart:async";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/material.dart";

import "models.dart";

enum _ClickKind {
  strong,
  normal,
  subdivision,
}

const Map<MetronomeTone, Map<_ClickKind, String>> _toneAssetPaths =
    <MetronomeTone, Map<_ClickKind, String>>{
  MetronomeTone.digital: <_ClickKind, String>{
    _ClickKind.strong: "audio/digital-strong.wav",
    _ClickKind.normal: "audio/digital-normal.wav",
    _ClickKind.subdivision: "audio/digital-subdivision.wav",
  },
  MetronomeTone.wood: <_ClickKind, String>{
    _ClickKind.strong: "audio/wood-strong.wav",
    _ClickKind.normal: "audio/wood-normal.wav",
    _ClickKind.subdivision: "audio/wood-subdivision.wav",
  },
  MetronomeTone.beep: <_ClickKind, String>{
    _ClickKind.strong: "audio/beep-strong.wav",
    _ClickKind.normal: "audio/beep-normal.wav",
    _ClickKind.subdivision: "audio/beep-subdivision.wav",
  },
};

String _resolveSoundAsset(MetronomeTone tone, _ClickKind kind) {
  final Map<_ClickKind, String> byKind =
      _toneAssetPaths[tone] ?? _toneAssetPaths[MetronomeTone.digital]!;
  return byKind[kind] ?? byKind[_ClickKind.normal]!;
}

class MetronomeEngine {
  MetronomeEngine({
    required this.onTick,
    required this.onStop,
  });

  static bool disablePlatformAudio = false;

  final void Function(int beat, int subTick) onTick;
  final VoidCallback onStop;

  List<AudioPlayer>? _players;

  Timer? _timer;
  int _tickCounter = 0;
  int _playerCursor = 0;

  MetronomeConfig _config = MetronomeConfig.fromSettings(AppSettings.defaults());
  double _volume = 0.8;
  MetronomeTone _tone = MetronomeTone.digital;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  List<AudioPlayer> _ensurePlayers() {
    final List<AudioPlayer>? existing = _players;
    if (existing != null) {
      return existing;
    }

    final List<AudioPlayer> created =
        List<AudioPlayer>.generate(4, (int _) => AudioPlayer());
    for (final AudioPlayer player in created) {
      unawaited(player.setReleaseMode(ReleaseMode.stop));
    }
    _players = created;
    return created;
  }

  void updateConfig(MetronomeConfig config) {
    _config = config.normalized();
    if (_isPlaying) {
      _restartTimer();
    }
  }

  void updateAudio({required double volume, required MetronomeTone tone}) {
    _volume = volume.clamp(0, 1).toDouble();
    _tone = tone;
  }

  void start() {
    if (_isPlaying) {
      return;
    }
    _isPlaying = true;
    _tickCounter = 0;
    if (!disablePlatformAudio) {
      _ensurePlayers();
    }
    _handleTick();
    _restartTimer();
  }

  void stop() {
    if (!_isPlaying) {
      return;
    }

    _timer?.cancel();
    _timer = null;
    _isPlaying = false;

    for (final AudioPlayer player in _players ?? const <AudioPlayer>[]) {
      unawaited(player.stop());
    }

    onStop();
  }

  void dispose() {
    stop();
    for (final AudioPlayer player in _players ?? const <AudioPlayer>[]) {
      unawaited(player.dispose());
    }
    _players = null;
  }

  void _restartTimer() {
    _timer?.cancel();

    final int ticksPerBeat = _config.subdivision.ticksPerBeat;
    final int micros = (60000000 / (_config.bpm * ticksPerBeat)).round();
    final Duration interval =
        Duration(microseconds: micros.clamp(1000, 60000000).toInt());

    _timer = Timer.periodic(interval, (_) {
      _handleTick();
    });
  }

  void _handleTick() {
    final int ticksPerBeat = _config.subdivision.ticksPerBeat;
    final int beat = (_tickCounter ~/ ticksPerBeat) % _config.numerator;
    final int subTick = _tickCounter % ticksPerBeat;

    onTick(beat, subTick);
    _playSoundForTick(beat: beat, subTick: subTick);

    _tickCounter++;
  }

  void _playSoundForTick({required int beat, required int subTick}) {
    if (disablePlatformAudio || _volume <= 0) {
      return;
    }

    _ClickKind? kind;
    double levelScale = 1;

    if (subTick == 0) {
      final AccentLevel accent = _config.accents[beat];
      switch (accent) {
        case AccentLevel.strong:
          kind = _ClickKind.strong;
          levelScale = 1.0;
        case AccentLevel.normal:
          kind = _ClickKind.normal;
          levelScale = 0.85;
        case AccentLevel.mute:
          kind = null;
      }
    } else {
      kind = _ClickKind.subdivision;
      levelScale = 0.55;
    }

    if (kind == null) {
      return;
    }

    final String assetPath = _resolveSoundAsset(_tone, kind);
    final List<AudioPlayer> players = _ensurePlayers();
    final AudioPlayer player = players[_playerCursor];
    _playerCursor = (_playerCursor + 1) % players.length;

    unawaited(
      player.play(
        AssetSource(assetPath),
        volume: (_volume * levelScale).clamp(0, 1).toDouble(),
      ).catchError((Object error) {
        debugPrint("Audio playback failed for $assetPath: $error");
      }),
    );
  }
}
