import "dart:async";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

import "models.dart";

enum _ClickKind {
  strong,
  normal,
  weak,
  subdivision,
}

const Map<MetronomeTone, Map<_ClickKind, String>> _toneAssetPaths =
    <MetronomeTone, Map<_ClickKind, String>>{
  MetronomeTone.digital: <_ClickKind, String>{
    _ClickKind.strong: "audio/digital-strong.wav",
    _ClickKind.normal: "audio/digital-normal.wav",
    // Dedicated weak assets are not available yet, so use lighter subdivision timbre.
    _ClickKind.weak: "audio/digital-subdivision.wav",
    _ClickKind.subdivision: "audio/digital-subdivision.wav",
  },
  MetronomeTone.wood: <_ClickKind, String>{
    _ClickKind.strong: "audio/wood-strong.wav",
    _ClickKind.normal: "audio/wood-normal.wav",
    _ClickKind.weak: "audio/wood-subdivision.wav",
    _ClickKind.subdivision: "audio/wood-subdivision.wav",
  },
  MetronomeTone.beep: <_ClickKind, String>{
    _ClickKind.strong: "audio/beep-strong.wav",
    _ClickKind.normal: "audio/beep-normal.wav",
    _ClickKind.weak: "audio/beep-subdivision.wav",
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

  final Map<String, AudioPool> _pools = <String, AudioPool>{};
  final Map<String, Future<AudioPool>> _poolLoaders = <String, Future<AudioPool>>{};
  final Set<Future<void> Function()> _pendingLowLatencyStops =
      <Future<void> Function()>{};
  final Set<Timer> _activeLowLatencyStopTimers = <Timer>{};
  Future<void>? _iosAudioContextLoader;
  bool _iosAudioContextConfigured = false;

  Timer? _timer;
  int _tickCounter = 0;

  MetronomeConfig _config = MetronomeConfig.fromSettings(AppSettings.defaults());
  double _volume = 0.8;
  MetronomeTone _tone = MetronomeTone.digital;
  final Set<MetronomeTone> _warmedTones = <MetronomeTone>{};
  final Set<MetronomeTone> _warmingTones = <MetronomeTone>{};
  bool _isDisposed = false;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;
  bool get _isAndroidPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  double _masterVolumeForPlatform() {
    if (!_isIOSPlatform) {
      return _volume;
    }
    // iOS needs slightly stronger scaling to reach parity with Android loudness.
    return (_volume * 1.2).clamp(0, 1).toDouble();
  }

  double _maxEffectiveVolumeForPlatform() {
    if (!_isIOSPlatform) {
      return 1;
    }
    // iOS platform audio can accept > 1 in some backends; keep a guarded ceiling.
    return 1.35;
  }

  double _platformLevelGain(_ClickKind kind) {
    if (!_isIOSPlatform) {
      return 1;
    }
    return switch (kind) {
      _ClickKind.strong => 1.08,
      _ClickKind.normal => 1.2,
      _ClickKind.weak => 1.45,
      _ClickKind.subdivision => 1.58,
    };
  }

  PlayerMode get _poolPlayerMode =>
      _isAndroidPlatform ? PlayerMode.lowLatency : PlayerMode.mediaPlayer;

  int get _poolMinPlayers => _isAndroidPlatform ? 4 : 2;

  int get _poolMaxPlayers => _isAndroidPlatform ? 24 : 8;

  Duration _lowLatencyRecycleDelay(_ClickKind kind) {
    final int clipMs = switch (kind) {
      _ClickKind.strong => 34,
      _ClickKind.normal => 28,
      _ClickKind.weak => 22,
      _ClickKind.subdivision => 22,
    };
    return Duration(milliseconds: clipMs + 12);
  }

  Future<AudioPool> _ensurePool(String assetPath) {
    if (_isDisposed) {
      return Future<AudioPool>.error(
        StateError("MetronomeEngine has been disposed."),
      );
    }

    final AudioPool? existing = _pools[assetPath];
    if (existing != null) {
      return Future<AudioPool>.value(existing);
    }

    final Future<AudioPool>? existingLoader = _poolLoaders[assetPath];
    if (existingLoader != null) {
      return existingLoader;
    }

    final Future<AudioPool> loader = (() async {
      await _ensurePlatformAudioContext();
      final AudioPool pool = await AudioPool.createFromAsset(
        path: assetPath,
        minPlayers: _poolMinPlayers,
        maxPlayers: _poolMaxPlayers,
        playerMode: _poolPlayerMode,
      );
      if (_isDisposed) {
        await pool.dispose();
        throw StateError("MetronomeEngine has been disposed.");
      }
      _pools[assetPath] = pool;
      return pool;
    })().whenComplete(() {
      _poolLoaders.remove(assetPath);
    });

    _poolLoaders[assetPath] = loader;
    return loader;
  }

  void updateConfig(MetronomeConfig config) {
    if (_isDisposed) {
      return;
    }
    final MetronomeConfig next = config.normalized();
    final bool needsTimerRestart =
        next.bpm != _config.bpm || next.subdivision != _config.subdivision;
    _config = next;
    if (_isPlaying && needsTimerRestart) {
      _restartTimer();
    }
  }

  void updateAudio({required double volume, required MetronomeTone tone}) {
    if (_isDisposed) {
      return;
    }
    _volume = volume.clamp(0, 1).toDouble();
    final MetronomeTone normalizedTone = tone;
    final bool toneChanged = normalizedTone != _tone;
    _tone = normalizedTone;
    if (!disablePlatformAudio && (toneChanged || !_warmedTones.contains(_tone))) {
      unawaited(_ensurePlatformAudioContext());
      unawaited(_warmUpTone(_tone));
    }
  }

  void start() {
    if (_isDisposed || _isPlaying) {
      return;
    }
    _isPlaying = true;
    _tickCounter = 0;
    if (!disablePlatformAudio) {
      unawaited(_ensurePlatformAudioContext());
      unawaited(_warmUpTone(_tone));
    }
    _handleTick();
    _restartTimer();
  }

  void stop() {
    if (_isDisposed || !_isPlaying) {
      return;
    }

    _timer?.cancel();
    _timer = null;
    _isPlaying = false;

    for (final Timer recycleTimer in _activeLowLatencyStopTimers.toList()) {
      recycleTimer.cancel();
    }
    _activeLowLatencyStopTimers.clear();

    for (final Future<void> Function() stopFn in _pendingLowLatencyStops.toList()) {
      unawaited(_invokeLowLatencyStop(stopFn));
    }
    _pendingLowLatencyStops.clear();

    onStop();
  }

  void dispose() {
    if (_isDisposed) {
      return;
    }
    stop();
    _isDisposed = true;

    _timer?.cancel();
    _timer = null;

    for (final Timer recycleTimer in _activeLowLatencyStopTimers.toList()) {
      recycleTimer.cancel();
    }
    _activeLowLatencyStopTimers.clear();
    _pendingLowLatencyStops.clear();

    for (final AudioPool pool in _pools.values.toList()) {
      unawaited(pool.dispose());
    }
    _pools.clear();
    _poolLoaders.clear();
    _warmedTones.clear();
    _warmingTones.clear();
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
        case AccentLevel.weak:
          kind = _ClickKind.weak;
          levelScale = 0.62;
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
    final double effectiveVolume = (_masterVolumeForPlatform() *
            levelScale *
            _platformLevelGain(kind))
        .clamp(0, _maxEffectiveVolumeForPlatform())
        .toDouble();

    unawaited(
      _playAsset(
        assetPath: assetPath,
        kind: kind,
        volume: effectiveVolume,
      ),
    );
  }

  Future<void> _playAsset({
    required String assetPath,
    required _ClickKind kind,
    required double volume,
  }) async {
    if (_isDisposed || !_isPlaying) {
      return;
    }

    try {
      final AudioPool pool = await _ensurePool(assetPath);
      if (_isDisposed || !_isPlaying) {
        return;
      }

      final Future<void> Function() stopFn = await pool.start(volume: volume);
      if (_poolPlayerMode != PlayerMode.lowLatency) {
        return;
      }

      _pendingLowLatencyStops.add(stopFn);
      late final Timer recycleTimer;
      recycleTimer = Timer(_lowLatencyRecycleDelay(kind), () {
        _activeLowLatencyStopTimers.remove(recycleTimer);
        if (!_pendingLowLatencyStops.remove(stopFn)) {
          return;
        }
        unawaited(_invokeLowLatencyStop(stopFn));
      });
      _activeLowLatencyStopTimers.add(recycleTimer);
    } catch (error) {
      debugPrint("Audio playback failed for $assetPath: $error");
    }
  }

  Future<void> _invokeLowLatencyStop(Future<void> Function() stopFn) async {
    try {
      await stopFn();
    } catch (error) {
      debugPrint("Audio stop failed: $error");
    }
  }

  Future<void> _ensurePlatformAudioContext() {
    if (_isDisposed || disablePlatformAudio || !_isIOSPlatform) {
      return Future<void>.value();
    }
    if (_iosAudioContextConfigured) {
      return Future<void>.value();
    }
    final Future<void>? inFlight = _iosAudioContextLoader;
    if (inFlight != null) {
      return inFlight;
    }

    final Future<void> loader = (() async {
      try {
        await AudioPlayer.global.setAudioContext(
          AudioContextConfig(
            route: AudioContextConfigRoute.system,
            focus: AudioContextConfigFocus.gain,
            respectSilence: false,
            stayAwake: false,
          ).build(),
        );
        _iosAudioContextConfigured = true;
      } catch (error) {
        debugPrint("iOS audio context setup failed: $error");
      } finally {
        _iosAudioContextLoader = null;
      }
    })();

    _iosAudioContextLoader = loader;
    return loader;
  }

  Future<void> _warmUpTone(MetronomeTone tone) async {
    if (_isDisposed || _warmedTones.contains(tone) || _warmingTones.contains(tone)) {
      return;
    }
    _warmingTones.add(tone);

    try {
      final Map<_ClickKind, String> paths =
          _toneAssetPaths[tone] ?? _toneAssetPaths[MetronomeTone.digital]!;
      await Future.wait<AudioPool>(
        paths.values.toSet().map(_ensurePool),
      );
      if (!_isDisposed) {
        _warmedTones.add(tone);
      }
    } catch (error) {
      debugPrint("Audio warm-up failed for ${tone.storageValue}: $error");
    } finally {
      _warmingTones.remove(tone);
    }
  }
}
