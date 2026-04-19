import "dart:async";
import "dart:math" as math;
import "dart:typed_data";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/material.dart";

import "models.dart";

enum _ClickKind {
  strong,
  normal,
  subdivision,
}

class _ToneProfile {
  const _ToneProfile({
    required this.strongFrequencyHz,
    required this.normalFrequencyHz,
    required this.subdivisionFrequencyHz,
  });

  final double strongFrequencyHz;
  final double normalFrequencyHz;
  final double subdivisionFrequencyHz;
}

const Map<MetronomeTone, _ToneProfile> _toneProfiles = <MetronomeTone, _ToneProfile>{
  MetronomeTone.digital: _ToneProfile(
    strongFrequencyHz: 1880,
    normalFrequencyHz: 1340,
    subdivisionFrequencyHz: 960,
  ),
  MetronomeTone.wood: _ToneProfile(
    strongFrequencyHz: 660,
    normalFrequencyHz: 470,
    subdivisionFrequencyHz: 350,
  ),
  MetronomeTone.beep: _ToneProfile(
    strongFrequencyHz: 1120,
    normalFrequencyHz: 840,
    subdivisionFrequencyHz: 640,
  ),
};

class _ClickSoundCache {
  final Map<String, Uint8List> _cache = <String, Uint8List>{};

  Uint8List resolveBytes({required MetronomeTone tone, required _ClickKind kind}) {
    final String key = "${tone.storageValue}:${kind.name}";
    final Uint8List? cached = _cache[key];
    if (cached != null) {
      return cached;
    }

    final _ToneProfile profile = _toneProfiles[tone] ?? _toneProfiles[MetronomeTone.digital]!;
    late final double frequency;
    late final int durationMs;
    late final double gain;

    switch (kind) {
      case _ClickKind.strong:
        frequency = profile.strongFrequencyHz;
        durationMs = 34;
        gain = 0.9;
      case _ClickKind.normal:
        frequency = profile.normalFrequencyHz;
        durationMs = 28;
        gain = 0.75;
      case _ClickKind.subdivision:
        frequency = profile.subdivisionFrequencyHz;
        durationMs = 22;
        gain = 0.56;
    }

    final Uint8List bytes = _buildClickWav(
      frequencyHz: frequency,
      durationMs: durationMs,
      gain: gain,
    );
    _cache[key] = bytes;
    return bytes;
  }

  Uint8List _buildClickWav({
    required double frequencyHz,
    required int durationMs,
    required double gain,
  }) {
    const int sampleRate = 44100;
    final int totalSamples = (sampleRate * durationMs / 1000).round();
    final int dataLength = totalSamples * 2;
    final ByteData bytes = ByteData(44 + dataLength);

    void writeString(int offset, String value) {
      for (int i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    writeString(0, "RIFF");
    bytes.setUint32(4, 36 + dataLength, Endian.little);
    writeString(8, "WAVE");
    writeString(12, "fmt ");
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeString(36, "data");
    bytes.setUint32(40, dataLength, Endian.little);

    for (int i = 0; i < totalSamples; i++) {
      final double time = i / sampleRate;
      final double phase = 2 * math.pi * frequencyHz * time;
      final double decay = math.exp(-7.5 * i / totalSamples);
      final double wave = math.sin(phase) * decay * gain;
      final int sample = (wave * 32767).round().clamp(-32768, 32767).toInt();
      bytes.setInt16(44 + i * 2, sample, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }
}

class MetronomeEngine {
  MetronomeEngine({
    required this.onTick,
    required this.onStop,
  }) {
    for (final AudioPlayer player in _players) {
      unawaited(player.setReleaseMode(ReleaseMode.stop));
      unawaited(player.setPlayerMode(PlayerMode.lowLatency));
    }
  }

  final void Function(int beat, int subTick) onTick;
  final VoidCallback onStop;

  final List<AudioPlayer> _players =
      List<AudioPlayer>.generate(4, (int _) => AudioPlayer());
  final _ClickSoundCache _soundCache = _ClickSoundCache();

  Timer? _timer;
  int _tickCounter = 0;
  int _playerCursor = 0;

  MetronomeConfig _config = MetronomeConfig.fromSettings(AppSettings.defaults());
  double _volume = 0.8;
  MetronomeTone _tone = MetronomeTone.digital;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

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

    for (final AudioPlayer player in _players) {
      unawaited(player.stop());
    }

    onStop();
  }

  void dispose() {
    stop();
    for (final AudioPlayer player in _players) {
      unawaited(player.dispose());
    }
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

    final Uint8List bytes = _soundCache.resolveBytes(tone: _tone, kind: kind);
    _playerCursor = (_playerCursor + 1) % _players.length;
    final AudioPlayer player = _players[_playerCursor];

    unawaited(player.stop());
    unawaited(
      player.play(
        BytesSource(bytes),
        volume: (_volume * levelScale).clamp(0, 1).toDouble(),
      ),
    );
  }
}
