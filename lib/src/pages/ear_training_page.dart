import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../l10n/app_locale.dart";
import "../widgets/section_pill_button.dart";

enum EarTrainingSpeed {
  slow,
  standard,
}

extension EarTrainingSpeedExtension on EarTrainingSpeed {
  String labelFor(AppLanguage language) {
    return switch (this) {
      EarTrainingSpeed.slow => language == AppLanguage.zh ? "慢速" : "Slow",
      EarTrainingSpeed.standard => language == AppLanguage.zh ? "标准" : "Standard",
    };
  }

  String get label => labelFor(AppLanguage.zh);
}

enum _ModeBPromptFlow {
  fixedLeadInThenTarget2345678,
}

extension _ModeBPromptFlowExtension on _ModeBPromptFlow {
  String labelFor(AppLanguage language) {
    return language == AppLanguage.zh
        ? "12345678 1 1 -> Re/Mi/Fa/Sol/La/Ti/Do'"
        : "12345678 1 1 -> Re/Mi/Fa/Sol/La/Ti/Do'";
  }

  String waitingStatusFor(AppLanguage language) {
    return language == AppLanguage.zh
        ? "播放 12345678 1 1 + 目标音(Re~Do')，等待作答"
        : "Play 12345678 1 1 + target(Re~Do'), waiting answer";
  }
}

enum _EarMode {
  listenAndReveal,
  listenAndChoose,
}

enum _ModeAPhase {
  tonic,
  target,
  think,
  answer,
  replay,
}

enum _ModeBDetailTone {
  idle,
  waiting,
  correct,
  wrong,
}

class _DegreeSpec {
  const _DegreeSpec({
    required this.degree,
    required this.slug,
    required this.label,
  });

  final String degree;
  final String slug;
  final String label;
}

class _EarNoteSpec {
  const _EarNoteSpec({
    required this.id,
    required this.degree,
    required this.octave,
    required this.label,
    required this.assetPath,
  });

  final String id;
  final String degree;
  final int octave;
  final String label;
  final String assetPath;
}

class EarTrainingPage extends StatefulWidget {
  const EarTrainingPage({
    this.isActive = true,
    required this.onLanguageChanged,
    super.key,
  });

  final bool isActive;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  State<EarTrainingPage> createState() => _EarTrainingPageState();
}

class _EarTrainingPageState extends State<EarTrainingPage> {
  static const List<_DegreeSpec> _degrees = <_DegreeSpec>[
    _DegreeSpec(degree: "2", slug: "2-Re", label: "Re"),
    _DegreeSpec(degree: "3", slug: "3-Mi", label: "Mi"),
    _DegreeSpec(degree: "4", slug: "4-Fa", label: "Fa"),
    _DegreeSpec(degree: "5", slug: "5-Sol", label: "Sol"),
    _DegreeSpec(degree: "6", slug: "6-La", label: "La"),
    _DegreeSpec(degree: "7", slug: "7-Ti", label: "Ti"),
    _DegreeSpec(degree: "8", slug: "8-Do", label: "Do"),
  ];
  static const int _baseOctave = 5;
  static const int _assetMinOctave = 5;
  static const int _assetMaxOctave = 5;
  static const String _defaultNoteId = "2_5";
  static const String _defaultNoteAssetPath = "audio/12345678/2-Re.WAV";
  static const String _modeBDefaultKeyLeadInAssetPath = "audio/12345678/12345678-1-1.WAV";
  static const String _hintAssetPath = "audio/beep-subdivision.wav";
  static const Duration _defaultNoteDuration = Duration(milliseconds: 4200);
  static const Duration _defaultLeadInDuration = Duration(milliseconds: 5200);
  static const Duration _defaultHintDuration = Duration(milliseconds: 200);
  static final Map<String, _EarNoteSpec> _noteCatalog = (() {
    final Map<String, _EarNoteSpec> catalog = <String, _EarNoteSpec>{};
    for (int octave = _assetMinOctave; octave <= _assetMaxOctave; octave++) {
      for (final _DegreeSpec degreeSpec in _degrees) {
        final String noteId = _noteId(degreeSpec.degree, octave);
        catalog[noteId] = _EarNoteSpec(
          id: noteId,
          degree: degreeSpec.degree,
          octave: octave,
          label: degreeSpec.label,
          assetPath: "audio/12345678/${degreeSpec.slug}.WAV",
        );
      }
    }
    return catalog;
  })();
  static final Map<String, int> _degreeOrder = <String, int>{
    for (int index = 0; index < _degrees.length; index++)
      _degrees[index].degree: index,
  };

  static String _noteId(String degree, int octave) {
    return "${degree}_$octave";
  }

  final Random _random = Random();
  final AudioPlayer _notePlayer = AudioPlayer();
  final AudioPlayer _leadInPlayer = AudioPlayer();
  final AudioPlayer _hintPlayer = AudioPlayer();

  int _currentTab = 0;
  int _questionCount = 10;
  EarTrainingSpeed _speed = EarTrainingSpeed.standard;
  _ModeBPromptFlow _modeBPromptFlow =
      _ModeBPromptFlow.fixedLeadInThenTarget2345678;
  bool _autoPlayAnswerInModeB = true;
  bool _autoAdvanceToNextQuestion = true;
  bool _errorHintEnabled = true;

  int _todayCompletedSets = 0;
  Duration _todayTrainingDuration = Duration.zero;
  int _streakDays = 1;

  final Stopwatch _modeAWatch = Stopwatch();
  Timer? _modeATimer;
  List<String> _modeAQuestions = <String>[];
  int _modeAIndex = 0;
  _ModeAPhase _modeAPhase = _ModeAPhase.tonic;
  bool _modeARunning = false;
  bool _modeAPaused = false;
  bool _modeAAutoPausedByVisibility = false;
  int _modeAReplayCount = 0;
  String _modeAStatus = "未开始";
  String? _modeAAnswer;

  final Stopwatch _modeBWatch = Stopwatch();
  Timer? _modeBFeedbackTimer;
  List<String> _modeBQuestions = <String>[];
  int _modeBIndex = 0;
  bool _modeBRunning = false;
  bool _modeBPaused = false;
  bool _modeBAutoPausedByVisibility = false;
  bool _modeBPromptReadyForAnswer = false;
  bool _modeBLocked = false;
  int _modeBFeedbackToken = 0;
  int _modeBCorrect = 0;
  int _modeBReplayCount = 0;
  String _modeBStatus = "未开始";
  String? _modeBSelected;
  String? _modeBFeedback;
  final Map<String, int> _modeBWrongCounts = <String, int>{};

  _SessionRecord? _latestModeARecord;
  _SessionRecord? _latestModeBRecord;
  final List<_SessionRecord> _history = <_SessionRecord>[];
  int _audioSequenceToken = 0;
  final Map<String, Duration> _assetDurationCache = <String, Duration>{};
  final Map<String, Future<Duration>> _assetDurationLoaders =
      <String, Future<Duration>>{};
  Future<void>? _iosAudioContextLoader;
  bool _iosAudioContextConfigured = false;
  Future<void> _playerStopBarrier = Future<void>.value();

  AppLanguage get _language => context.appLanguage;

  String _t({
    required String zh,
    required String en,
  }) {
    return _language == AppLanguage.zh ? zh : en;
  }

  bool get _isIOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  _EarNoteSpec get _defaultNoteSpec {
    return _noteCatalog[_defaultNoteId] ??
        const _EarNoteSpec(
          id: _defaultNoteId,
          degree: "2",
          octave: _baseOctave,
          label: "Re",
          assetPath: _defaultNoteAssetPath,
        );
  }

  List<_EarNoteSpec> get _activeNotes {
    const int minOctave = _assetMinOctave;
    const int maxOctave = _assetMaxOctave;
    final List<_EarNoteSpec> notes = <_EarNoteSpec>[];
    for (int octave = minOctave; octave <= maxOctave; octave++) {
      for (final _DegreeSpec degreeSpec in _degrees) {
        final String noteId = _noteId(degreeSpec.degree, octave);
        final _EarNoteSpec? note = _noteCatalog[noteId];
        if (note != null) {
          notes.add(note);
        }
      }
    }
    if (notes.isEmpty) {
      notes.add(_defaultNoteSpec);
    }
    return notes;
  }

  List<String> get _activeNoteIds {
    return _activeNotes
        .map((_EarNoteSpec note) => note.id)
        .toList(growable: false);
  }

  List<_EarNoteSpec> get _modeBChoiceNotes {
    final List<String> fallbackIds = _activeNoteIds;
    final Set<String> ids = (_modeBRunning && _modeBQuestions.isNotEmpty)
        ? _modeBQuestions.toSet()
        : fallbackIds.toSet();
    final List<_EarNoteSpec> notes = ids.map(_resolveNote).toList(growable: false)
      ..sort((_EarNoteSpec a, _EarNoteSpec b) {
        final int octaveCompare = a.octave.compareTo(b.octave);
        if (octaveCompare != 0) {
          return octaveCompare;
        }
        final int degreeA = _degreeOrder[a.degree] ?? 0;
        final int degreeB = _degreeOrder[b.degree] ?? 0;
        return degreeA.compareTo(degreeB);
      });
    if (notes.isEmpty) {
      return _activeNotes;
    }
    return notes;
  }

  bool get _singleOctaveMode => true;

  _EarNoteSpec _resolveNote(String noteId) {
    return _noteCatalog[noteId] ?? _defaultNoteSpec;
  }

  String _noteDisplayLabel(String noteId) {
    final _EarNoteSpec? note = _noteCatalog[noteId];
    if (note == null) {
      return noteId;
    }
    if (note.degree == "8") {
      return "${note.label}'";
    }
    if (_singleOctaveMode && note.octave == _baseOctave) {
      return note.label;
    }
    return note.label;
  }

  String _tonicNoteIdFor(String noteId) {
    final int octave = _resolveNote(noteId).octave;
    final String tonicId = _noteId("8", octave);
    if (_noteCatalog.containsKey(tonicId)) {
      return tonicId;
    }
    return _defaultNoteId;
  }

  bool _canContinueModeBPrompt({
    required int token,
    required bool requireModeBRunning,
  }) {
    if (!mounted || token != _audioSequenceToken) {
      return false;
    }
    if (requireModeBRunning && !_modeBRunning) {
      return false;
    }
    if (_modeBPaused) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_configureAudioPlayers());
  }

  @override
  void didUpdateWidget(covariant EarTrainingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncPlaybackWithVisibility();
    }
  }

  @override
  void dispose() {
    _cancelAudioSequence();
    unawaited(_notePlayer.dispose());
    unawaited(_leadInPlayer.dispose());
    unawaited(_hintPlayer.dispose());
    _modeATimer?.cancel();
    _modeBFeedbackTimer?.cancel();
    super.dispose();
  }

  String? get _modeACurrentNoteId {
    if (_modeAQuestions.isEmpty || _modeAIndex >= _modeAQuestions.length) {
      return null;
    }
    return _modeAQuestions[_modeAIndex];
  }

  String? get _modeBCurrentNoteId {
    if (_modeBQuestions.isEmpty || _modeBIndex >= _modeBQuestions.length) {
      return null;
    }
    return _modeBQuestions[_modeBIndex];
  }

  Future<void> _configureAudioPlayers() async {
    try {
      await _notePlayer.setReleaseMode(ReleaseMode.stop);
      await _leadInPlayer.setReleaseMode(ReleaseMode.stop);
      await _hintPlayer.setReleaseMode(ReleaseMode.stop);
      await _ensurePlatformAudioContext();
    } catch (error) {
      debugPrint("Ear training audio init failed: $error");
    }
  }

  Future<void> _ensurePlatformAudioContext() {
    if (!_isIOSPlatform || _iosAudioContextConfigured) {
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
        debugPrint("Ear training iOS audio context setup failed: $error");
      } finally {
        _iosAudioContextLoader = null;
      }
    })();

    _iosAudioContextLoader = loader;
    return loader;
  }

  int _cancelAudioSequence() {
    _audioSequenceToken += 1;
    _queueStopAllPlayers();
    return _audioSequenceToken;
  }

  Future<void> _safeStopPlayer(AudioPlayer player, String playerTag) async {
    try {
      await player.stop();
    } catch (error) {
      debugPrint("Ear training $playerTag stop failed: $error");
    }
  }

  void _queueStopAllPlayers() {
    _playerStopBarrier = _playerStopBarrier
        .catchError((Object _) {})
        .then((_) async {
          await Future.wait<void>(<Future<void>>[
            _safeStopPlayer(_notePlayer, "note"),
            _safeStopPlayer(_leadInPlayer, "lead-in"),
            _safeStopPlayer(_hintPlayer, "hint"),
          ]);
        });
  }

  Future<void> _waitForPendingPlayerStops() {
    return _playerStopBarrier.catchError((Object _) {});
  }

  void _invalidateModeBFeedbackTimer() {
    _modeBFeedbackTimer?.cancel();
    _modeBFeedbackToken += 1;
  }

  String _bundleAssetPath(String assetPath) {
    if (assetPath.startsWith("assets/")) {
      return assetPath;
    }
    return "assets/$assetPath";
  }

  Duration? _tryParseWavDuration(ByteData data) {
    final Uint8List bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (bytes.length < 44) {
      return null;
    }
    String readFourCc(int offset) {
      if (offset + 4 > bytes.length) {
        return "";
      }
      return String.fromCharCodes(bytes.sublist(offset, offset + 4));
    }

    if (readFourCc(0) != "RIFF" || readFourCc(8) != "WAVE") {
      return null;
    }

    int? byteRate;
    int? dataChunkSize;
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final String chunkId = readFourCc(offset);
      final int chunkSize = data.getUint32(offset + 4, Endian.little);
      final int payloadOffset = offset + 8;
      if (payloadOffset + chunkSize > bytes.length) {
        break;
      }

      if (chunkId == "fmt " && chunkSize >= 16) {
        byteRate = data.getUint32(payloadOffset + 8, Endian.little);
      } else if (chunkId == "data") {
        dataChunkSize = chunkSize;
      }

      if (byteRate != null && dataChunkSize != null) {
        break;
      }
      offset = payloadOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (byteRate == null || dataChunkSize == null || byteRate <= 0) {
      return null;
    }
    final int micros = ((dataChunkSize * 1000000) / byteRate).round();
    if (micros <= 0) {
      return null;
    }
    return Duration(microseconds: micros);
  }

  Future<Duration> _assetDuration(
    String assetPath, {
    required Duration fallback,
  }) async {
    final Duration? cached = _assetDurationCache[assetPath];
    if (cached != null) {
      return cached;
    }
    final Future<Duration>? inFlight = _assetDurationLoaders[assetPath];
    if (inFlight != null) {
      return inFlight;
    }

    final Future<Duration> loader = (() async {
      Duration resolved = fallback;
      try {
        final ByteData data = await rootBundle.load(_bundleAssetPath(assetPath));
        final Duration? parsed = _tryParseWavDuration(data);
        if (parsed != null) {
          resolved = parsed;
        }
      } catch (_) {
        resolved = fallback;
      } finally {
        _assetDurationLoaders.remove(assetPath);
      }
      _assetDurationCache[assetPath] = resolved;
      return resolved;
    })();

    _assetDurationLoaders[assetPath] = loader;
    return loader;
  }

  Future<Duration> _noteDurationById(String noteId) {
    final String assetPath = _resolveNote(noteId).assetPath;
    return _assetDuration(assetPath, fallback: _defaultNoteDuration);
  }

  Future<void> _warmUpNoteDurations(Iterable<String> noteIds) async {
    final Set<String> uniqueIds = noteIds.toSet();
    if (uniqueIds.isEmpty) {
      return;
    }
    await Future.wait<Duration>(uniqueIds.map(_noteDurationById));
  }

  Future<void> _warmUpModeBPromptDurations(Iterable<String> noteIds) async {
    await Future.wait<Duration>(<Future<Duration>>[
      _leadInDuration(),
      _assetDuration(_hintAssetPath, fallback: _defaultHintDuration),
      ...noteIds.toSet().map(_noteDurationById),
    ]);
  }

  Future<Duration> _modeBReplayStartDelay({required bool withHint}) async {
    if (!withHint) {
      return Duration.zero;
    }
    final Duration hintDuration = await _assetDuration(
      _hintAssetPath,
      fallback: _defaultHintDuration,
    );
    return _scaleDuration(
      hintDuration,
      factor: 0.55,
      minMilliseconds: 80,
      maxMilliseconds: 260,
    );
  }

  Future<Duration> _modeBPromptGapDuration(String noteId) async {
    final Duration targetDuration = await _noteDurationById(noteId);
    return _scaleDuration(
      targetDuration,
      factor: 0.035,
      minMilliseconds: 80,
      maxMilliseconds: 260,
    );
  }

  Duration _modeBReplayTailDuration(Duration answerDuration) {
    return _scaleDuration(
      answerDuration,
      factor: 0.07,
      minMilliseconds: 140,
      maxMilliseconds: 760,
    );
  }

  Duration _modeBHintSettleDuration(Duration hintDuration) {
    return _scaleDuration(
      hintDuration,
      factor: 0.45,
      minMilliseconds: 40,
      maxMilliseconds: 360,
    );
  }

  Future<Duration> _modeBAutoAdvanceDelay({
    required bool isCorrect,
    required String answerNoteId,
  }) async {
    final Duration answerDuration = await _noteDurationById(answerNoteId);
    if (!_autoPlayAnswerInModeB) {
      final int ms = (answerDuration.inMilliseconds * 0.22)
          .round()
          .clamp(450, 1200)
          .toInt();
      return Duration(milliseconds: ms);
    }

    final bool withHint = !isCorrect && _errorHintEnabled;
    final Duration replayStartDelay = await _modeBReplayStartDelay(withHint: withHint);
    Duration delay =
        replayStartDelay + answerDuration + _modeBReplayTailDuration(answerDuration);

    if (withHint) {
      final Duration hintDuration = await _assetDuration(
        _hintAssetPath,
        fallback: _defaultHintDuration,
      );
      final Duration hintWindow =
          hintDuration + _modeBHintSettleDuration(hintDuration);
      if (hintWindow > delay) {
        delay = hintWindow;
      }
    }

    return delay;
  }

  bool get _isModeATabVisible => widget.isActive && _currentTab == 1;

  bool get _isModeBTabVisible => widget.isActive && _currentTab == 2;

  void _pauseModeAForVisibility() {
    if (!_modeARunning || _modeAPaused) {
      return;
    }
    _modeATimer?.cancel();
    _modeAWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeAPaused = true;
      _modeAAutoPausedByVisibility = true;
      _modeAStatus = _t(zh: "已暂停", en: "Paused");
    });
  }

  void _resumeModeAForVisibility() {
    if (!_modeARunning || !_modeAPaused || !_modeAAutoPausedByVisibility) {
      return;
    }
    _modeAWatch.start();
    setState(() {
      _modeAPaused = false;
      _modeAAutoPausedByVisibility = false;
      final String? noteId = _modeACurrentNoteId;
      _modeAStatus = noteId == null
          ? _t(zh: "继续", en: "Resume")
          : _t(
              zh: "继续：${_modeAPhaseLabel(noteId)}",
              en: "Resume: ${_modeAPhaseLabel(noteId)}",
            );
    });
    _playModeAPhaseAudio();
    _scheduleModeAAdvance();
  }

  void _pauseModeBForVisibility() {
    if (!_modeBRunning || _modeBPaused) {
      return;
    }
    _invalidateModeBFeedbackTimer();
    _modeBWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeBPaused = true;
      _modeBAutoPausedByVisibility = true;
      _modeBPromptReadyForAnswer = false;
      _modeBStatus = _t(zh: "已暂停", en: "Paused");
    });
  }

  bool _isCurrentModeBAnswerCorrect() {
    if (_modeBQuestions.isEmpty ||
        _modeBIndex < 0 ||
        _modeBIndex >= _modeBQuestions.length) {
      return false;
    }
    final String? selected = _modeBSelected;
    if (selected == null) {
      return false;
    }
    return selected == _modeBQuestions[_modeBIndex];
  }

  void _resumeModeBForVisibility() {
    if (!_modeBRunning || !_modeBPaused || !_modeBAutoPausedByVisibility) {
      return;
    }
    _modeBWatch.start();
    setState(() {
      _modeBPaused = false;
      _modeBAutoPausedByVisibility = false;
      _modeBStatus = _modeBLocked
          ? _t(zh: "已核对答案", en: "Answer checked")
          : _modeBPromptFlow.waitingStatusFor(_language);
    });
    if (_modeBLocked) {
      if (_autoAdvanceToNextQuestion) {
        final String? answerNoteId = _modeBCurrentNoteId;
        if (answerNoteId == null) {
          _advanceModeB();
          return;
        }
        final bool isCorrect = _isCurrentModeBAnswerCorrect();
        _invalidateModeBFeedbackTimer();
        final int feedbackToken = _modeBFeedbackToken;
        final int answerIndex = _modeBIndex;
        unawaited(() async {
          final Duration delay = await _modeBAutoAdvanceDelay(
            isCorrect: isCorrect,
            answerNoteId: answerNoteId,
          );
          if (!mounted ||
              !_modeBRunning ||
              _modeBPaused ||
              !_modeBLocked ||
              _modeBIndex != answerIndex ||
              feedbackToken != _modeBFeedbackToken) {
            return;
          }
          _modeBFeedbackTimer = Timer(delay, _advanceModeB);
        }());
      }
      return;
    }
    _playCurrentModeBPrompt();
  }

  void _syncPlaybackWithVisibility() {
    if (_isModeATabVisible) {
      _resumeModeAForVisibility();
    } else {
      _pauseModeAForVisibility();
    }

    if (_isModeBTabVisible) {
      _resumeModeBForVisibility();
    } else {
      _pauseModeBForVisibility();
    }

    if (!widget.isActive || (_currentTab != 1 && _currentTab != 2)) {
      _cancelAudioSequence();
    }
  }

  Future<void> _playAsset(
    AudioPlayer player, {
    required String assetPath,
    required double volume,
    required Duration fallbackDuration,
  }) async {
    await _ensurePlatformAudioContext();
    await _waitForPendingPlayerStops();
    final Duration expectedDuration = await _assetDuration(
      assetPath,
      fallback: fallbackDuration,
    );
    final List<PlayerMode> tryModes = _preferredPlayerModes(expectedDuration);
    await player.stop();
    Object? lastError;
    for (final PlayerMode mode in tryModes) {
      try {
        await player.play(
          AssetSource(assetPath),
          volume: volume,
          mode: mode,
        );
        return;
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      throw lastError;
    }
    throw StateError("Audio playback failed without error: $assetPath");
  }

  List<PlayerMode> _preferredPlayerModes(Duration expectedDuration) {
    if (expectedDuration >= const Duration(milliseconds: 900)) {
      return <PlayerMode>[PlayerMode.mediaPlayer, PlayerMode.lowLatency];
    }
    return <PlayerMode>[PlayerMode.lowLatency, PlayerMode.mediaPlayer];
  }

  Duration _playbackTimeoutFor(Duration duration) {
    final Duration buffer = _scaleDuration(
      duration,
      factor: 0.24,
      minMilliseconds: 450,
      maxMilliseconds: 2500,
    );
    final Duration timeout = duration + buffer;
    final Duration floor = _scaleDuration(
      duration,
      factor: 1,
      minMilliseconds: 1600,
      maxMilliseconds: 12000,
    );
    if (timeout < floor) {
      return floor;
    }
    return timeout;
  }

  Duration _scaleDuration(
    Duration base, {
    required double factor,
    required int minMilliseconds,
    required int maxMilliseconds,
    int addMilliseconds = 0,
  }) {
    final int scaled = (base.inMilliseconds * factor).round() + addMilliseconds;
    final int clamped = scaled.clamp(minMilliseconds, maxMilliseconds).toInt();
    return Duration(milliseconds: clamped);
  }

  Future<Duration> _leadInDuration() {
    return _assetDuration(
      _modeBDefaultKeyLeadInAssetPath,
      fallback: _defaultLeadInDuration,
    );
  }

  Future<void> _playDefaultKeyLeadInAsset() async {
    await _ensurePlatformAudioContext();
    await _waitForPendingPlayerStops();
    await _leadInPlayer.stop();
    final Duration leadInDuration = await _leadInDuration();
    final Duration timeout = _playbackTimeoutFor(leadInDuration);

    try {
      bool timedOut = false;
      final Future<void> completed = _leadInPlayer.onPlayerComplete.first;
      await _leadInPlayer.play(
        AssetSource(_modeBDefaultKeyLeadInAssetPath),
        volume: 0.92,
        mode: PlayerMode.mediaPlayer,
      );
      await completed.timeout(timeout, onTimeout: () {
        timedOut = true;
        return Future<void>.value();
      });
      if (timedOut) {
        await _leadInPlayer.stop();
        throw TimeoutException(
          "Lead-in playback timeout: $_modeBDefaultKeyLeadInAssetPath",
          timeout,
        );
      }
    } catch (error) {
      debugPrint("Ear training lead-in playback failed: $error");
      rethrow;
    }
  }

  Future<bool> _playAssetAndWait(
    AudioPlayer player, {
    required String assetPath,
    required double volume,
    required Duration fallbackDuration,
    required bool allowTimeoutAsSuccess,
  }) async {
    await _ensurePlatformAudioContext();
    await _waitForPendingPlayerStops();
    final Duration expectedDuration = await _assetDuration(
      assetPath,
      fallback: fallbackDuration,
    );
    final Duration timeout = _playbackTimeoutFor(expectedDuration);
    // Waiting for completion relies on event semantics that are not reliable
    // in lowLatency mode across backends, so keep wait-path on mediaPlayer.
    const List<PlayerMode> tryModes = <PlayerMode>[PlayerMode.mediaPlayer];
    await player.stop();
    Object? lastError;
    for (final PlayerMode mode in tryModes) {
      try {
        bool timedOut = false;
        final Future<void> completed = player.onPlayerComplete.first;
        await player.play(
          AssetSource(assetPath),
          volume: volume,
          mode: mode,
        );
        await completed.timeout(timeout, onTimeout: () {
          timedOut = true;
          return Future<void>.value();
        });
        if (timedOut) {
          if (allowTimeoutAsSuccess && mode == PlayerMode.mediaPlayer) {
            // Some iOS backends may miss completion callbacks for long assets.
            // When playback started successfully in media mode, treat timeout as done.
            await player.stop();
            return true;
          }
          await player.stop();
          continue;
        }
        return true;
      } catch (error) {
        lastError = error;
        await player.stop();
      }
    }
    if (lastError != null) {
      debugPrint("Ear training wait playback failed: $lastError");
    }
    return false;
  }

  Future<void> _playNote(String noteId, {double volume = 0.9}) async {
    final String assetPath = _resolveNote(noteId).assetPath;
    try {
      await _playAsset(
        _notePlayer,
        assetPath: assetPath,
        volume: volume.clamp(0, 1).toDouble(),
        fallbackDuration: _defaultNoteDuration,
      );
    } catch (error) {
      debugPrint("Ear training note playback failed: $error");
    }
  }

  Future<bool> _playNoteAndWait(
    String noteId, {
    double volume = 0.9,
    bool allowTimeoutAsSuccess = false,
  }) async {
    final String assetPath = _resolveNote(noteId).assetPath;
    try {
      final bool played = await _playAssetAndWait(
        _notePlayer,
        assetPath: assetPath,
        volume: volume.clamp(0, 1).toDouble(),
        fallbackDuration: _defaultNoteDuration,
        allowTimeoutAsSuccess: allowTimeoutAsSuccess,
      );
      if (!played) {
        debugPrint("Ear training note wait playback did not complete: $assetPath");
        return false;
      }
      return true;
    } catch (error) {
      debugPrint("Ear training note wait playback failed: $error");
      return false;
    }
  }

  Future<void> _playHintSound() async {
    try {
      await _playAsset(
        _hintPlayer,
        assetPath: _hintAssetPath,
        volume: 0.78,
        fallbackDuration: _defaultHintDuration,
      );
    } catch (error) {
      debugPrint("Ear training hint playback failed: $error");
    }
  }

  void _playModeAPhaseAudio() {
    if (!_modeARunning || _modeAPaused || !_isModeATabVisible) {
      return;
    }
    final String? noteId = _modeACurrentNoteId;
    if (noteId == null) {
      return;
    }

    switch (_modeAPhase) {
      case _ModeAPhase.tonic:
        unawaited(_playNote(_tonicNoteIdFor(noteId)));
        break;
      case _ModeAPhase.target:
        unawaited(_playNote(noteId, volume: 0.94));
        break;
      case _ModeAPhase.replay:
        unawaited(_playNote(noteId, volume: 0.94));
        break;
      case _ModeAPhase.think:
      case _ModeAPhase.answer:
        break;
    }
  }

  Future<void> _playModeBPrompt({
    required String noteId,
    required int token,
    bool requireModeBRunning = true,
  }) async {
    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }

    try {
      await _playDefaultKeyLeadInAsset();
    } catch (_) {
      // Keep prompt flow stable even if lead-in asset fails once.
    }

    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }
    final Duration promptGap = await _modeBPromptGapDuration(noteId);
    if (promptGap > Duration.zero) {
      await Future<void>.delayed(promptGap);
    }

    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }
    final bool played = await _playNoteAndWait(
      noteId,
      volume: 0.94,
      allowTimeoutAsSuccess: _isIOSPlatform,
    );

    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }
    if (!played) {
      if (requireModeBRunning) {
        setState(() {
          _modeBPromptReadyForAnswer = true;
          _modeBStatus = _t(
            zh: "提示播放失败，请点击“重播提示”",
            en: "Prompt issue detected, answer unlocked (Replay available)",
          );
        });
      }
      return;
    }

    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }
    if (requireModeBRunning) {
      setState(() {
        _modeBPromptReadyForAnswer = true;
        _modeBStatus = _t(zh: "提示已播放完成，请作答", en: "Prompt completed, choose answer");
      });
    }
  }

  void _playCurrentModeBPrompt() {
    final String? noteId = _modeBCurrentNoteId;
    if (!_modeBRunning || _modeBPaused || !_isModeBTabVisible || noteId == null) {
      return;
    }
    final int token = _cancelAudioSequence();
    setState(() {
      _modeBPromptReadyForAnswer = false;
      _modeBStatus = _t(zh: "提示播放中...", en: "Prompt playing...");
    });
    unawaited(_playModeBPrompt(noteId: noteId, token: token));
  }

  List<String> _buildQuestionSet(int count, {List<String>? seedPool}) {
    if (count <= 0) {
      return <String>[];
    }

    final List<String> defaultPool = _activeNoteIds;
    final List<String> pool = seedPool == null || seedPool.isEmpty
        ? List<String>.from(defaultPool)
        : List<String>.from(seedPool);
    final List<String> uniquePool = pool.toSet().toList();
    if (uniquePool.isEmpty) {
      return <String>[];
    }
    if (uniquePool.length == 1) {
      return List<String>.filled(count, uniquePool.first);
    }

    final List<String> result = <String>[];
    if (seedPool == null && count >= defaultPool.length) {
      result.addAll(defaultPool);
    }

    while (result.length < count) {
      result.add(pool[_random.nextInt(pool.length)]);
    }

    result.shuffle(_random);

    for (int i = 2; i < result.length; i++) {
      final String current = result[i];
      if (current == result[i - 1] && current == result[i - 2]) {
        final List<String> alternatives =
            uniquePool.where((String item) => item != current).toList();
        result[i] = alternatives[_random.nextInt(alternatives.length)];
      }
    }

    return result;
  }

  String _modeAPhaseLabel(String noteId) {
    final String answerLabel = _noteDisplayLabel(noteId);
    final String tonicLabel = _noteDisplayLabel(_tonicNoteIdFor(noteId));
    return switch (_modeAPhase) {
      _ModeAPhase.tonic => _t(
          zh: "建立主音中心（$tonicLabel）",
          en: "Build tonic center ($tonicLabel)",
        ),
      _ModeAPhase.target => _t(zh: "播放目标音", en: "Play target note"),
      _ModeAPhase.think => _t(zh: "思考并判断音名", en: "Think and decide the note"),
      _ModeAPhase.answer => _t(zh: "答案：$answerLabel", en: "Answer: $answerLabel"),
      _ModeAPhase.replay => _t(
          zh: "重播正确音：$answerLabel",
          en: "Replay correct note: $answerLabel",
        ),
    };
  }

  String _modeADurationNoteIdForPhase(_ModeAPhase phase, String questionNoteId) {
    return switch (phase) {
      _ModeAPhase.tonic => _tonicNoteIdFor(questionNoteId),
      _ModeAPhase.target ||
      _ModeAPhase.think ||
      _ModeAPhase.answer ||
      _ModeAPhase.replay => questionNoteId,
    };
  }

  Duration _modeAPhaseDuration(_ModeAPhase phase, String noteId) {
    final bool slow = _speed == EarTrainingSpeed.slow;
    final String durationNoteId = _modeADurationNoteIdForPhase(phase, noteId);
    final String assetPath = _resolveNote(durationNoteId).assetPath;
    final Duration noteDuration =
        _assetDurationCache[assetPath] ?? _defaultNoteDuration;
    return switch (phase) {
      _ModeAPhase.tonic || _ModeAPhase.target || _ModeAPhase.replay => slow
          ? _scaleDuration(
              noteDuration,
              factor: 1.18,
              addMilliseconds: 520,
              minMilliseconds: 4800,
              maxMilliseconds: 9000,
            )
          : _scaleDuration(
              noteDuration,
              factor: 1.03,
              addMilliseconds: 260,
              minMilliseconds: 3600,
              maxMilliseconds: 7000,
            ),
      _ModeAPhase.think => slow
          ? _scaleDuration(
              noteDuration,
              factor: 0.56,
              addMilliseconds: 260,
              minMilliseconds: 1800,
              maxMilliseconds: 4300,
            )
          : _scaleDuration(
              noteDuration,
              factor: 0.40,
              addMilliseconds: 160,
              minMilliseconds: 1200,
              maxMilliseconds: 3200,
            ),
      _ModeAPhase.answer => slow
          ? _scaleDuration(
              noteDuration,
              factor: 0.30,
              addMilliseconds: 120,
              minMilliseconds: 900,
              maxMilliseconds: 2400,
            )
          : _scaleDuration(
              noteDuration,
              factor: 0.22,
              addMilliseconds: 70,
              minMilliseconds: 700,
              maxMilliseconds: 1800,
            ),
    };
  }

  _ModeAPhase _nextModeAPhase(_ModeAPhase current) {
    return switch (current) {
      _ModeAPhase.tonic => _ModeAPhase.target,
      _ModeAPhase.target => _ModeAPhase.think,
      _ModeAPhase.think => _ModeAPhase.answer,
      _ModeAPhase.answer => _ModeAPhase.replay,
      _ModeAPhase.replay => _ModeAPhase.tonic,
    };
  }

  void _startModeA() {
    unawaited(_startModeAInternal());
  }

  Future<void> _startModeAInternal() async {
    _modeATimer?.cancel();
    _cancelAudioSequence();
    _modeAWatch.reset();

    final List<String> questions = _buildQuestionSet(_questionCount);
    if (questions.isEmpty) {
      return;
    }
    final Set<String> warmUpNoteIds = <String>{
      ...questions,
      ...questions.map(_tonicNoteIdFor),
    };
    await _warmUpNoteDurations(warmUpNoteIds);
    if (!mounted) {
      return;
    }
    _modeAWatch.start();

    setState(() {
      _currentTab = 1;
      _modeAQuestions = questions;
      _modeAIndex = 0;
      _modeAPhase = _ModeAPhase.tonic;
      _modeARunning = true;
      _modeAPaused = false;
      _modeAAutoPausedByVisibility = false;
      _modeAReplayCount = 0;
      _modeAAnswer = null;
      _modeAStatus = _modeAPhaseLabel(_modeAQuestions[_modeAIndex]);
    });
    _syncPlaybackWithVisibility();
    _playModeAPhaseAudio();
    _scheduleModeAAdvance();
  }

  void _scheduleModeAAdvance() {
    if (!_modeARunning || _modeAPaused || !_isModeATabVisible || _modeAQuestions.isEmpty) {
      return;
    }
    final String? noteId = _modeACurrentNoteId;
    if (noteId == null) {
      return;
    }
    _modeATimer?.cancel();
    _modeATimer = Timer(_modeAPhaseDuration(_modeAPhase, noteId), _advanceModeA);
  }

  void _advanceModeA() {
    if (!mounted || !_modeARunning || _modeAPaused || !_isModeATabVisible || _modeAQuestions.isEmpty) {
      return;
    }

    final _ModeAPhase nextPhase = _nextModeAPhase(_modeAPhase);
    final bool toNextQuestion = nextPhase == _ModeAPhase.tonic;

    if (toNextQuestion) {
      if (_modeAIndex + 1 >= _modeAQuestions.length) {
        _finishModeA();
        return;
      }

      setState(() {
        _modeAIndex += 1;
        _modeAPhase = nextPhase;
        _modeAAnswer = null;
        _modeAStatus = _modeAPhaseLabel(_modeAQuestions[_modeAIndex]);
      });
      _playModeAPhaseAudio();
      _scheduleModeAAdvance();
      return;
    }

    setState(() {
      _modeAPhase = nextPhase;
      final String noteId = _modeAQuestions[_modeAIndex];
      if (_modeAPhase == _ModeAPhase.answer || _modeAPhase == _ModeAPhase.replay) {
        _modeAAnswer = noteId;
      }
      _modeAStatus = _modeAPhaseLabel(noteId);
    });
    _playModeAPhaseAudio();
    _scheduleModeAAdvance();
  }

  void _toggleModeAPause() {
    if (!_modeARunning) {
      return;
    }
    if (_modeAPaused) {
      _modeAWatch.start();
      setState(() {
        _modeAPaused = false;
        _modeAAutoPausedByVisibility = false;
        final String? noteId = _modeACurrentNoteId;
        _modeAStatus = noteId == null
            ? _t(zh: "继续", en: "Resume")
            : _t(
                zh: "继续：${_modeAPhaseLabel(noteId)}",
                en: "Resume: ${_modeAPhaseLabel(noteId)}",
              );
      });
      _scheduleModeAAdvance();
      return;
    }

    _modeATimer?.cancel();
    _modeAWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeAPaused = true;
      _modeAAutoPausedByVisibility = false;
      _modeAStatus = _t(zh: "已暂停", en: "Paused");
    });
  }

  void _replayModeAQuestion() {
    if (!_modeARunning || _modeAQuestions.isEmpty) {
      return;
    }
    _modeATimer?.cancel();
    setState(() {
      _modeAReplayCount += 1;
      _modeAPhase = _ModeAPhase.tonic;
      _modeAAnswer = null;
      _modeAStatus = _modeAPhaseLabel(_modeAQuestions[_modeAIndex]);
      _modeAPaused = false;
      _modeAAutoPausedByVisibility = false;
    });
    _playModeAPhaseAudio();
    _scheduleModeAAdvance();
  }

  void _exitModeA() {
    _modeATimer?.cancel();
    _modeAWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeARunning = false;
      _modeAPaused = false;
      _modeAAutoPausedByVisibility = false;
      _modeAStatus = _t(zh: "已停止", en: "Stopped");
    });
  }

  void _finishModeA() {
    _modeATimer?.cancel();
    _modeAWatch.stop();
    _cancelAudioSequence();

    final _SessionRecord record = _SessionRecord(
      mode: _EarMode.listenAndReveal,
      questionCount: _modeAQuestions.length,
      correctCount: null,
      replayCount: _modeAReplayCount,
      duration: _modeAWatch.elapsed,
      wrongCounts: const <String, int>{},
      finishedAt: DateTime.now(),
    );

    setState(() {
      _modeARunning = false;
      _modeAPaused = false;
      _modeAAutoPausedByVisibility = false;
      _modeAStatus = _t(zh: "已完成", en: "Finished");
      _todayCompletedSets += 1;
      _todayTrainingDuration += record.duration;
      _latestModeARecord = record;
      _currentTab = 3;
      _history.insert(0, record);
      if (_history.length > 20) {
        _history.removeRange(20, _history.length);
      }
    });
    _syncPlaybackWithVisibility();
  }

  void _startModeB({List<String>? customQuestions}) {
    unawaited(_startModeBInternal(customQuestions: customQuestions));
  }

  Future<void> _startModeBInternal({List<String>? customQuestions}) async {
    _invalidateModeBFeedbackTimer();
    _cancelAudioSequence();
    _modeBWatch.reset();

    final List<String> questions = customQuestions == null || customQuestions.isEmpty
        ? _buildQuestionSet(_questionCount)
        : List<String>.from(customQuestions);
    if (questions.isEmpty) {
      return;
    }
    await _warmUpModeBPromptDurations(questions);
    if (!mounted) {
      return;
    }
    _modeBWatch.start();

    setState(() {
      _currentTab = 2;
      _modeBQuestions = questions;
      _modeBIndex = 0;
      _modeBRunning = true;
      _modeBPaused = false;
      _modeBAutoPausedByVisibility = false;
      _modeBPromptReadyForAnswer = false;
      _modeBLocked = false;
      _modeBCorrect = 0;
      _modeBReplayCount = 0;
      _modeBSelected = null;
      _modeBFeedback = null;
      _modeBStatus = _modeBPromptFlow.waitingStatusFor(_language);
      _modeBWrongCounts.clear();
    });
    _syncPlaybackWithVisibility();
    _playCurrentModeBPrompt();
  }

  void _submitModeB(String selected) {
    if (!_modeBRunning ||
        _modeBPaused ||
        !_modeBPromptReadyForAnswer ||
        _modeBLocked ||
        _modeBQuestions.isEmpty) {
      return;
    }

    final String answer = _modeBQuestions[_modeBIndex];
    final String answerLabel = _noteDisplayLabel(answer);
    final bool isCorrect = selected == answer;
    _invalidateModeBFeedbackTimer();

    setState(() {
      _modeBLocked = true;
      _modeBPromptReadyForAnswer = false;
      _modeBSelected = selected;
      if (isCorrect) {
        _modeBCorrect += 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? _t(
                zh: "正确：$answerLabel（自动回放已开启）",
                en: "Correct: $answerLabel (auto replay on)",
              )
            : _t(zh: "正确：$answerLabel", en: "Correct: $answerLabel");
        _modeBStatus = _t(zh: "正确", en: "Correct");
      } else {
        _modeBWrongCounts[answer] = (_modeBWrongCounts[answer] ?? 0) + 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? _t(
                zh: "错误，正确答案是 $answerLabel（自动回放已开启）",
                en: "Wrong, answer is $answerLabel (auto replay on)",
              )
            : _t(
                zh: "错误，正确答案是 $answerLabel",
                en: "Wrong, answer is $answerLabel",
              );
        _modeBStatus = _errorHintEnabled
            ? _t(zh: "错误（提示音已开启）", en: "Wrong (hint sound on)")
            : _t(zh: "错误", en: "Wrong");
      }
    });

    _cancelAudioSequence();
    if (!isCorrect && _errorHintEnabled) {
      unawaited(_playHintSound());
    }
    if (_autoPlayAnswerInModeB) {
      final String answerToReplay = answer;
      final bool withHint = !isCorrect && _errorHintEnabled;
      unawaited(() async {
        final Duration delay = await _modeBReplayStartDelay(withHint: withHint);
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        if (!mounted || !_modeBRunning || _modeBPaused || !_isModeBTabVisible) {
          return;
        }
        await _playNote(answerToReplay, volume: 0.94);
      }());
    }

    if (_autoAdvanceToNextQuestion) {
      final int feedbackToken = _modeBFeedbackToken;
      final int answerIndex = _modeBIndex;
      final String answerToReplay = answer;
      unawaited(() async {
        final Duration delay = await _modeBAutoAdvanceDelay(
          isCorrect: isCorrect,
          answerNoteId: answerToReplay,
        );
        if (!mounted ||
            !_modeBRunning ||
            _modeBPaused ||
            !_modeBLocked ||
            _modeBIndex != answerIndex ||
            feedbackToken != _modeBFeedbackToken) {
          return;
        }
        _modeBFeedbackTimer = Timer(delay, _advanceModeB);
      }());
    }
  }

  void _advanceModeB() {
    if (!mounted || !_modeBRunning || _modeBPaused) {
      return;
    }
    _invalidateModeBFeedbackTimer();

    if (_modeBIndex + 1 >= _modeBQuestions.length) {
      _finishModeB();
      return;
    }

    setState(() {
      _modeBIndex += 1;
      _modeBLocked = false;
      _modeBPromptReadyForAnswer = false;
      _modeBSelected = null;
      _modeBFeedback = null;
      _modeBStatus = _modeBPromptFlow.waitingStatusFor(_language);
    });
    _playCurrentModeBPrompt();
  }

  void _finishModeB() {
    _invalidateModeBFeedbackTimer();
    _modeBWatch.stop();
    _cancelAudioSequence();

    final _SessionRecord record = _SessionRecord(
      mode: _EarMode.listenAndChoose,
      questionCount: _modeBQuestions.length,
      correctCount: _modeBCorrect,
      replayCount: _modeBReplayCount,
      duration: _modeBWatch.elapsed,
      wrongCounts: Map<String, int>.from(_modeBWrongCounts),
      finishedAt: DateTime.now(),
    );

    setState(() {
      _modeBRunning = false;
      _modeBPaused = false;
      _modeBAutoPausedByVisibility = false;
      _modeBPromptReadyForAnswer = false;
      _modeBLocked = false;
      _modeBStatus = _t(zh: "已完成", en: "Finished");
      _todayCompletedSets += 1;
      _todayTrainingDuration += record.duration;
      _latestModeBRecord = record;
      _currentTab = 3;
      _history.insert(0, record);
      if (_history.length > 20) {
        _history.removeRange(20, _history.length);
      }
    });
    _syncPlaybackWithVisibility();
  }

  void _exitModeB() {
    _invalidateModeBFeedbackTimer();
    _modeBWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeBRunning = false;
      _modeBPaused = false;
      _modeBAutoPausedByVisibility = false;
      _modeBPromptReadyForAnswer = false;
      _modeBLocked = false;
      _modeBStatus = _t(zh: "已停止", en: "Stopped");
    });
  }

  void _replayModeBQuestion() {
    if (!_modeBRunning || _modeBPaused) {
      return;
    }
    setState(() {
      _modeBReplayCount += 1;
      _modeBStatus = _t(zh: "已重播当前提示", en: "Replayed current prompt");
    });
    _playCurrentModeBPrompt();
  }

  List<String> _buildWrongRedoQuestions() {
    final Map<String, int> source = _latestModeBRecord?.wrongCounts ?? <String, int>{};
    if (source.isEmpty) {
      return _buildQuestionSet(_questionCount);
    }

    final List<String> pool = <String>[];
    source.forEach((String degree, int times) {
      final int repeat = times.clamp(1, 3);
      pool.addAll(List<String>.filled(repeat, degree));
    });

    return _buildQuestionSet(_questionCount, seedPool: pool);
  }

  void _startWrongRedo() {
    _startModeB(customQuestions: _buildWrongRedoQuestions());
  }

  _SessionRecord? _latestRecordByMode(_EarMode mode) {
    for (final _SessionRecord record in _history) {
      if (record.mode == mode) {
        return record;
      }
    }
    return null;
  }

  void _syncLatestRecordsFromHistory() {
    _latestModeARecord = _latestRecordByMode(_EarMode.listenAndReveal);
    _latestModeBRecord = _latestRecordByMode(_EarMode.listenAndChoose);
  }

  Future<void> _deleteHistoryRecord(_SessionRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_t(zh: "删除历史记录", en: "Delete History Item")),
          content: Text(_t(zh: "删除这条训练记录吗？", en: "Delete this training record?")),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_t(zh: "取消", en: "Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_t(zh: "删除", en: "Delete")),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _history.remove(record);
      _syncLatestRecordsFromHistory();
    });
  }

  Future<void> _clearHistoryRecords() async {
    if (_history.isEmpty) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_t(zh: "清空历史", en: "Clear History")),
          content: Text(
            _t(zh: "删除最近所有训练记录吗？", en: "Delete all recent history records?"),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_t(zh: "取消", en: "Cancel")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_t(zh: "清空", en: "Clear")),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _history.clear();
      _syncLatestRecordsFromHistory();
    });
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    final String mm = minutes.toString().padLeft(2, "0");
    final String ss = seconds.toString().padLeft(2, "0");
    return "$mm:$ss";
  }

  Widget _buildQuestionCountSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <int>[10, 20].map((int count) {
        return SectionPillButton(
          label: _t(zh: "$count 题", en: "$count Q"),
          selected: _questionCount == count,
          onPressed: _questionCount == count
              ? null
              : () {
            setState(() {
              _questionCount = count;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildSpeedSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: EarTrainingSpeed.values.map((EarTrainingSpeed speed) {
        return SectionPillButton(
          label: speed.labelFor(_language),
          selected: _speed == speed,
          onPressed: _speed == speed
              ? null
              : () {
            setState(() {
              _speed = speed;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildModeBPromptFlowSelector() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: <Widget>[
        SectionPillBadge(
          icon: Icons.graphic_eq_rounded,
          label: _modeBPromptFlow.labelFor(_language),
        ),
      ],
    );
  }

  Widget _buildSubTabs() {
    final List<_SubTabItem> tabs = <_SubTabItem>[
      _SubTabItem(index: 0, icon: Icons.home_rounded, label: _t(zh: "主页", en: "Home")),
      _SubTabItem(
        index: 1,
        icon: Icons.hearing_rounded,
        label: _t(zh: "听后揭示", en: "Listen->Reveal"),
      ),
      _SubTabItem(
        index: 2,
        icon: Icons.touch_app_rounded,
        label: _t(zh: "听后选择", en: "Listen->Choose"),
      ),
      _SubTabItem(index: 3, icon: Icons.insights_rounded, label: _t(zh: "历史记录", en: "History")),
      _SubTabItem(index: 4, icon: Icons.settings_rounded, label: _t(zh: "设置", en: "Settings")),
    ];

    final List<Widget> tabButtons = <Widget>[];
    for (int index = 0; index < tabs.length; index++) {
      final _SubTabItem item = tabs[index];
      if (index > 0) {
        tabButtons.add(const SizedBox(width: 10));
      }
      tabButtons.add(
        SectionPillButton(
          icon: item.icon,
          label: item.label,
          selected: item.index == _currentTab,
          onPressed: item.index == _currentTab
              ? null
              : () {
                  setState(() {
                    _currentTab = item.index;
                  });
                  _syncPlaybackWithVisibility();
                },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: tabButtons),
      ),
    );
  }

  Widget _buildHomeTab(ThemeData theme) {
    final _SessionRecord? latestB = _latestModeBRecord;
    final String latestAccuracy = latestB == null
        ? "--"
        : "${(latestB.accuracy * 100).toStringAsFixed(0)}%";

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text(_t(zh: "音阶听音训练", en: "Scale Ear Trainer"), style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          _t(
            zh: "每天 5-10 分钟，建立主音中心与音级识别。",
            en: "5-10 minutes daily to build tonic center and degree recognition.",
          ),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "今日训练", en: "Today"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(
                  _t(
                    zh: "建议：听后揭示 1 组 + 听后选择 1 组。",
                    en: "Suggested: 1 set Listen->Reveal + 1 set Listen->Choose.",
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _startModeA,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_t(zh: "开始模式 A", en: "Start Mode A")),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _startModeB,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_t(zh: "开始模式 B", en: "Start Mode B")),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "训练参数", en: "Training Params"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(_t(zh: "题目数量", en: "Question count")),
                const SizedBox(height: 6),
                _buildQuestionCountSelector(),
                const SizedBox(height: 10),
                Text(_t(zh: "速度", en: "Speed")),
                const SizedBox(height: 6),
                _buildSpeedSelector(),
                const SizedBox(height: 10),
                Text(_t(zh: "模式 B 提示流程", en: "Mode B prompt flow")),
                const SizedBox(height: 6),
                _buildModeBPromptFlowSelector(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "快速统计", en: "Quick Stats"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(_t(zh: "今日完成组数：$_todayCompletedSets", en: "Sets today: $_todayCompletedSets")),
                Text(
                  _t(
                    zh: "今日训练时长：${_formatDuration(_todayTrainingDuration)}",
                    en: "Time today: ${_formatDuration(_todayTrainingDuration)}",
                  ),
                ),
                Text(_t(zh: "连续天数：$_streakDays", en: "Streak days: $_streakDays")),
                Text(
                  _t(
                    zh: "最近模式 B 准确率：$latestAccuracy",
                    en: "Latest Mode B accuracy: $latestAccuracy",
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentTab = 3;
                    });
                    _syncPlaybackWithVisibility();
                  },
                  icon: const Icon(Icons.insights_rounded),
                  label: Text(_t(zh: "打开历史记录页", en: "Open History")),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeATab(ThemeData theme) {
    final int total = _modeAQuestions.length;
    final int current = total == 0 ? 0 : (_modeAIndex + 1).clamp(1, total);
    final double progress = total == 0 ? 0 : current / total;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text(_t(zh: "模式 A：听后揭示", en: "Mode A: Listen -> Reveal"), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          _t(
            zh: "流程：主音中心 -> 目标音 -> 思考 -> 答案 -> 重播",
            en: "Flow: tonic -> target -> think -> answer -> replay",
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "状态", en: "Status"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(_t(zh: "题目：$current / $total", en: "Question: $current / $total")),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text(_t(zh: "阶段：$_modeAStatus", en: "Phase: $_modeAStatus")),
                Text(
                  _t(
                    zh:
                        "答案显示：${_modeAAnswer == null ? "等待中" : _noteDisplayLabel(_modeAAnswer!)}",
                    en:
                        "Answer display: ${_modeAAnswer == null ? "Waiting" : _noteDisplayLabel(_modeAAnswer!)}",
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _modeARunning ? null : _startModeA,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_t(zh: "开始", en: "Start")),
                    ),
                    if (_modeARunning)
                      FilledButton.tonalIcon(
                        onPressed: _toggleModeAPause,
                        icon: Icon(
                          _modeAPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(
                          _modeAPaused
                              ? _t(zh: "继续", en: "Resume")
                              : _t(zh: "暂停", en: "Pause"),
                        ),
                      ),
                    if (_modeARunning)
                      OutlinedButton.icon(
                        onPressed: _replayModeAQuestion,
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(_t(zh: "重播", en: "Replay")),
                      ),
                    if (_modeARunning)
                      TextButton.icon(
                        onPressed: _exitModeA,
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: Text(_t(zh: "退出", en: "Exit")),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  ButtonStyle _modeBChoiceStyle(ThemeData theme, String noteId) {
    final String? answer = _modeBCurrentNoteId;
    Color? backgroundColor;
    Color? foregroundColor;
    BorderSide borderSide = BorderSide.none;

    if (_modeBLocked && answer != null) {
      if (noteId == answer) {
        backgroundColor = theme.brightness == Brightness.dark
            ? const Color(0xFF2D7A46)
            : const Color(0xFF1E6B39);
        foregroundColor = Colors.white;
        borderSide = BorderSide(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFA7E3B9)
              : const Color(0xFF0E5A2B),
          width: 2,
        );
      } else if (noteId == _modeBSelected) {
        backgroundColor = theme.colorScheme.error;
        foregroundColor = theme.colorScheme.onError;
        borderSide = BorderSide(
          color: theme.brightness == Brightness.dark
              ? const Color(0xFFFFC6C4)
              : const Color(0xFF7A1E1E),
          width: 2,
        );
      }
    }

    return FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: const Size(0, 46),
      side: borderSide,
      disabledBackgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(
        theme.brightness == Brightness.dark ? 0.62 : 0.78,
      ),
      disabledForegroundColor: theme.colorScheme.onSurface.withOpacity(
        theme.brightness == Brightness.dark ? 0.82 : 0.72,
      ),
    );
  }

  Widget _buildModeBTab(ThemeData theme) {
    final int total = _modeBQuestions.length;
    final int current = total == 0 ? 0 : (_modeBIndex + 1).clamp(1, total);
    final double progress = total == 0 ? 0 : current / total;
    final List<_EarNoteSpec> choiceNotes = _modeBChoiceNotes;
    final bool denseChoices = choiceNotes.length > 14;
    final bool singleOctaveChoices =
        choiceNotes.map((_EarNoteSpec note) => note.octave).toSet().length <= 1;
    final bool showDisabledOneDoSlot =
        singleOctaveChoices && choiceNotes.length == _degrees.length;
    final String? answerId = _modeBCurrentNoteId;
    final bool answeredCorrectly =
        _modeBLocked &&
        _modeBSelected != null &&
        answerId != null &&
        _modeBSelected == answerId;
    final _ModeBDetailTone modeBDetailTone;
    final String? modeBDetailMessage;
    if (_modeBFeedback != null) {
      modeBDetailMessage = _modeBFeedback!;
      modeBDetailTone = answeredCorrectly
          ? _ModeBDetailTone.correct
          : _ModeBDetailTone.wrong;
    } else if (_modeBRunning && !_modeBLocked && !_modeBPromptReadyForAnswer) {
      modeBDetailMessage = _t(
        zh: "请等待提示音播放结束后再作答。",
        en: "Wait for prompt playback to finish before choosing.",
      );
      modeBDetailTone = _ModeBDetailTone.waiting;
    } else {
      modeBDetailMessage = null;
      modeBDetailTone = _ModeBDetailTone.idle;
    }

    final IconData detailIcon = switch (modeBDetailTone) {
      _ModeBDetailTone.correct => Icons.check_circle_rounded,
      _ModeBDetailTone.wrong => Icons.cancel_rounded,
      _ModeBDetailTone.waiting => Icons.hearing_rounded,
      _ModeBDetailTone.idle => Icons.info_outline_rounded,
    };
    final Color detailBackgroundColor = switch (modeBDetailTone) {
      _ModeBDetailTone.correct => theme.brightness == Brightness.dark
          ? const Color(0x332D7A46)
          : const Color(0x221E6B39),
      _ModeBDetailTone.wrong => theme.brightness == Brightness.dark
          ? const Color(0x33B95A58)
          : const Color(0x22B95A58),
      _ModeBDetailTone.waiting => theme.colorScheme.secondaryContainer.withOpacity(0.28),
      _ModeBDetailTone.idle => Colors.transparent,
    };
    final Color detailBorderColor = switch (modeBDetailTone) {
      _ModeBDetailTone.correct => theme.brightness == Brightness.dark
          ? const Color(0xFF80D39A)
          : const Color(0xFF246E3D),
      _ModeBDetailTone.wrong => theme.brightness == Brightness.dark
          ? const Color(0xFFFFB4AB)
          : const Color(0xFF8E2F2C),
      _ModeBDetailTone.waiting => theme.colorScheme.secondary.withOpacity(0.58),
      _ModeBDetailTone.idle => Colors.transparent,
    };
    final Color detailTextColor = switch (modeBDetailTone) {
      _ModeBDetailTone.correct => theme.brightness == Brightness.dark
          ? const Color(0xFFC9F2D5)
          : const Color(0xFF195830),
      _ModeBDetailTone.wrong => theme.brightness == Brightness.dark
          ? const Color(0xFFFFD5CF)
          : const Color(0xFF7A2724),
      _ModeBDetailTone.waiting => theme.colorScheme.onSecondaryContainer,
      _ModeBDetailTone.idle => theme.colorScheme.onSurface.withOpacity(0.72),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text(_t(zh: "模式 B：听后选择", en: "Mode B: Listen -> Choose"), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          singleOctaveChoices
              ? _t(
                  zh: "请在 Re Mi Fa Sol La Ti Do' 中选择一个。",
                  en: "Choose one from Re Mi Fa Sol La Ti Do'.",
                )
              : _t(
                  zh: "请从当前集合中选择（${choiceNotes.length} 个音，2~8）。",
                  en: "Choose one from active set (${choiceNotes.length} notes, 2~8).",
                ),
        ),
        const SizedBox(height: 4),
        Text(
          _t(
            zh: "提示流程：${_modeBPromptFlow.labelFor(_language)}",
            en: "Prompt flow: ${_modeBPromptFlow.labelFor(_language)}",
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "状态", en: "Status"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(_t(zh: "题目：$current / $total", en: "Question: $current / $total")),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text(_t(zh: "当前状态：$_modeBStatus", en: "State: $_modeBStatus")),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 42),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: modeBDetailMessage == null
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: modeBDetailMessage == null
                          ? Colors.transparent
                          : detailBackgroundColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: modeBDetailMessage == null
                            ? Colors.transparent
                            : detailBorderColor,
                        width: modeBDetailMessage == null ? 0 : 1.5,
                      ),
                    ),
                    child: modeBDetailMessage == null
                        ? const SizedBox.shrink()
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(detailIcon, size: 18, color: detailTextColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  modeBDetailMessage,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: detailTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (showDisabledOneDoSlot)
                      SizedBox(
                        width: denseChoices ? 82 : 92,
                        child: const FilledButton(
                          onPressed: null,
                          child: Text("Do"),
                        ),
                      ),
                    ...choiceNotes.map((_EarNoteSpec note) {
                      return SizedBox(
                        width: denseChoices ? 82 : 92,
                        child: FilledButton(
                          onPressed: (_modeBRunning && !_modeBPaused)
                              && !_modeBLocked
                              && _modeBPromptReadyForAnswer
                              ? () => _submitModeB(note.id)
                              : null,
                          style: _modeBChoiceStyle(theme, note.id),
                          child: Text(_noteDisplayLabel(note.id)),
                        ),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _modeBRunning ? null : _startModeB,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(_t(zh: "开始", en: "Start")),
                    ),
                    if (_modeBRunning)
                      OutlinedButton.icon(
                        onPressed: _replayModeBQuestion,
                        icon: const Icon(Icons.replay_rounded),
                        label: Text(_t(zh: "重播提示", en: "Replay Prompt")),
                      ),
                    if (_modeBRunning)
                      OutlinedButton.icon(
                        onPressed: _finishModeB,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(_t(zh: "完成", en: "Finish")),
                      ),
                    if (_modeBRunning)
                      TextButton.icon(
                        onPressed: _exitModeB,
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: Text(_t(zh: "退出", en: "Exit")),
                      ),
                  ],
                ),
                if (_modeBRunning && _modeBLocked && !_autoAdvanceToNextQuestion) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _advanceModeB,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: Text(_t(zh: "下一题", en: "Next")),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordCard(ThemeData theme, _SessionRecord record) {
    final String accuracyText = record.correctCount == null
        ? _t(zh: "N/A（该模式不统计）", en: "N/A (not tracked in this mode)")
        : "${(record.accuracy * 100).toStringAsFixed(1)}%";
    final String wrongText = record.wrongCounts.isEmpty
        ? _t(zh: "无", en: "None")
        : record.wrongCounts.entries
            .map(
              (MapEntry<String, int> entry) =>
                  "${_noteDisplayLabel(entry.key)} x${entry.value}",
            )
            .join("  ");

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(record.modeLabelFor(_language), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_t(zh: "题目数：${record.questionCount}", en: "Questions: ${record.questionCount}")),
            Text(_t(zh: "时长：${_formatDuration(record.duration)}", en: "Duration: ${_formatDuration(record.duration)}")),
            Text(_t(zh: "准确率：$accuracyText", en: "Accuracy: $accuracyText")),
            Text(_t(zh: "重播次数：${record.replayCount}", en: "Replay count: ${record.replayCount}")),
            const SizedBox(height: 6),
            Text(_t(zh: "错误项：$wrongText", en: "Wrong items: $wrongText")),
            const SizedBox(height: 6),
            Text(
              _t(
                zh:
                    "完成时间：${record.finishedAt.year.toString().padLeft(4, "0")}-"
                    "${record.finishedAt.month.toString().padLeft(2, "0")}-"
                    "${record.finishedAt.day.toString().padLeft(2, "0")} "
                    "${record.finishedAt.hour.toString().padLeft(2, "0")}:"
                    "${record.finishedAt.minute.toString().padLeft(2, "0")}",
                en:
                    "Completed: ${record.finishedAt.year.toString().padLeft(4, "0")}-"
                    "${record.finishedAt.month.toString().padLeft(2, "0")}-"
                    "${record.finishedAt.day.toString().padLeft(2, "0")} "
                    "${record.finishedAt.hour.toString().padLeft(2, "0")}:"
                    "${record.finishedAt.minute.toString().padLeft(2, "0")}",
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text(_t(zh: "历史记录", en: "History"), style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_latestModeARecord == null && _latestModeBRecord == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                _t(
                  zh: "暂无训练记录，开始一次训练后可查看指标。",
                  en: "No sessions yet. Start one to see metrics.",
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        if (_latestModeARecord != null) ...<Widget>[
          Text(_t(zh: "最近模式 A", en: "Latest Mode A"), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildRecordCard(theme, _latestModeARecord!),
        ],
        if (_latestModeBRecord != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_t(zh: "最近模式 B", en: "Latest Mode B"), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildRecordCard(theme, _latestModeBRecord!),
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _startModeA,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_t(zh: "运行模式 A", en: "Run Mode A")),
            ),
            FilledButton.tonalIcon(
              onPressed: _startModeB,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(_t(zh: "运行模式 B", en: "Run Mode B")),
            ),
            FilledButton.tonalIcon(
              onPressed: (_latestModeBRecord != null &&
                      _latestModeBRecord!.wrongCounts.isNotEmpty)
                  ? _startWrongRedo
                  : null,
              icon: const Icon(Icons.replay_circle_filled_rounded),
              label: Text(_t(zh: "仅错题复习", en: "Wrong-only Review")),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(_t(zh: "最近记录", en: "Recent History"), style: theme.textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: _history.isEmpty ? null : _clearHistoryRecords,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: Text(_t(zh: "清空", en: "Clear")),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                _t(zh: "暂无历史记录", en: "No history yet"),
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ..._history.take(8).map((_SessionRecord record) {
          final String accuracy = record.correctCount == null
              ? _t(zh: "N/A", en: "N/A")
              : "${(record.accuracy * 100).toStringAsFixed(0)}%";
          return Card(
            child: ListTile(
              title: Text(record.modeLabelFor(_language)),
              subtitle: Text(
                _t(
                  zh: "${record.questionCount} 题 | ${_formatDuration(record.duration)} | $accuracy",
                  en: "${record.questionCount} Q | ${_formatDuration(record.duration)} | $accuracy",
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    "${record.finishedAt.hour.toString().padLeft(2, "0")}:"
                    "${record.finishedAt.minute.toString().padLeft(2, "0")}",
                  ),
                  IconButton(
                    tooltip: _t(zh: "删除", en: "Delete"),
                    onPressed: () => _deleteHistoryRecord(record),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSettingsTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text(_t(zh: "听音训练设置", en: "Ear Training Settings"), style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "默认项", en: "Defaults"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(_t(zh: "题目数量", en: "Question count")),
                const SizedBox(height: 6),
                _buildQuestionCountSelector(),
                const SizedBox(height: 10),
                Text(_t(zh: "速度", en: "Speed")),
                const SizedBox(height: 6),
                _buildSpeedSelector(),
                const SizedBox(height: 10),
                Text(_t(zh: "模式 B 提示流程", en: "Mode B prompt flow")),
                const SizedBox(height: 6),
                _buildModeBPromptFlowSelector(),
                const SizedBox(height: 10),
                Text(_t(zh: "全局语言", en: "Global language")),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    ChoiceChip(
                      label: Text(_t(zh: "中文", en: "Chinese")),
                      selected: _language == AppLanguage.zh,
                      onSelected: (_) {
                        widget.onLanguageChanged(AppLanguage.zh);
                      },
                    ),
                    ChoiceChip(
                      label: Text(_t(zh: "英文", en: "English")),
                      selected: _language == AppLanguage.en,
                      onSelected: (_) {
                        widget.onLanguageChanged(AppLanguage.en);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  _t(zh: "模式 B 自动回放答案", en: "Mode B auto answer replay"),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _autoPlayAnswerInModeB,
                onChanged: (bool value) {
                  setState(() {
                    _autoPlayAnswerInModeB = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  _t(zh: "自动进入下一题", en: "Auto next question"),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _autoAdvanceToNextQuestion,
                onChanged: (bool value) {
                  setState(() {
                    _autoAdvanceToNextQuestion = value;
                  });
                },
              ),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                title: Text(
                  _t(zh: "错误提示音", en: "Error hint sound"),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                value: _errorHintEnabled,
                onChanged: (bool value) {
                  setState(() {
                    _errorHintEnabled = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_t(zh: "音频测试", en: "Audio test"), style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final String testNoteId = _noteId("3", _baseOctave);
                    final int token = _cancelAudioSequence();
                    unawaited(
                      _playModeBPrompt(
                        noteId: testNoteId,
                        token: token,
                        requireModeBRunning: false,
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _t(
                            zh: "已播放测试提示（${_modeBPromptFlow.labelFor(_language)}）",
                            en: "Played test prompt (${_modeBPromptFlow.labelFor(_language)})",
                          ),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.volume_up_rounded),
                  label: Text(_t(zh: "播放测试提示", en: "Play test prompt")),
                ),
                const SizedBox(height: 10),
                Text(
                  _t(
                    zh: "建议：每天 5 分钟，佩戴耳机并在安静环境中训练。",
                    en: "Tip: 5 minutes daily, with headphones in a quiet place.",
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  ThemeData _buildEarTrainingTheme(ThemeData base) {
    final ColorScheme colorScheme = base.colorScheme;
    final TextStyle buttonTextStyle = (base.textTheme.labelLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
      fontSize: 15,
      height: 1.32,
    );
    final RoundedRectangleBorder buttonShape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return base.copyWith(
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: buttonShape,
          textStyle: buttonTextStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: buttonShape,
          textStyle: buttonTextStyle.copyWith(fontWeight: FontWeight.w600),
          side: BorderSide(color: colorScheme.outline.withOpacity(0.72)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: buttonShape,
          textStyle: buttonTextStyle.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final List<Color> backgroundGradient = isDark
        ? <Color>[
            Color.alphaBlend(colorScheme.primary.withOpacity(0.11), colorScheme.surface),
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.08), colorScheme.surface),
            Color.alphaBlend(colorScheme.tertiary.withOpacity(0.07), colorScheme.surface),
            colorScheme.surface,
          ]
        : <Color>[
            Color.alphaBlend(colorScheme.secondary.withOpacity(0.21), colorScheme.surface),
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
        ),
      ),
      child: Theme(
        data: _buildEarTrainingTheme(theme),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _buildSubTabs(),
              Expanded(
                child: IndexedStack(
                  index: _currentTab,
                  children: <Widget>[
                    Builder(
                      builder: (BuildContext context) => _buildHomeTab(Theme.of(context)),
                    ),
                    Builder(
                      builder: (BuildContext context) => _buildModeATab(Theme.of(context)),
                    ),
                    Builder(
                      builder: (BuildContext context) => _buildModeBTab(Theme.of(context)),
                    ),
                    Builder(
                      builder: (BuildContext context) => _buildResultsTab(Theme.of(context)),
                    ),
                    Builder(
                      builder: (BuildContext context) => _buildSettingsTab(Theme.of(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTabItem {
  const _SubTabItem({
    required this.index,
    required this.icon,
    required this.label,
  });

  final int index;
  final IconData icon;
  final String label;
}

class _SessionRecord {
  const _SessionRecord({
    required this.mode,
    required this.questionCount,
    required this.correctCount,
    required this.replayCount,
    required this.duration,
    required this.wrongCounts,
    required this.finishedAt,
  });

  final _EarMode mode;
  final int questionCount;
  final int? correctCount;
  final int replayCount;
  final Duration duration;
  final Map<String, int> wrongCounts;
  final DateTime finishedAt;

  String modeLabelFor(AppLanguage language) {
    return switch (mode) {
      _EarMode.listenAndReveal => language == AppLanguage.zh
          ? "模式 A 听后揭示"
          : "Mode A Listen->Reveal",
      _EarMode.listenAndChoose => language == AppLanguage.zh
          ? "模式 B 听后选择"
          : "Mode B Listen->Choose",
    };
  }

  double get accuracy {
    if (correctCount == null || questionCount == 0) {
      return 0;
    }
    return correctCount! / questionCount;
  }
}
