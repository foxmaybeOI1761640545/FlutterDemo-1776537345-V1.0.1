import "dart:async";
import "dart:math";

import "package:audioplayers/audioplayers.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";

enum EarTrainingSpeed {
  slow,
  standard,
}

extension EarTrainingSpeedExtension on EarTrainingSpeed {
  String get label {
    return switch (this) {
      EarTrainingSpeed.slow => "Slow",
      EarTrainingSpeed.standard => "Standard",
    };
  }
}

enum _ModeBPromptFlow {
  defaultKeyScale121ThenTarget,
  scaleThenTarget,
  tonicThenTarget,
}

extension _ModeBPromptFlowExtension on _ModeBPromptFlow {
  String get label {
    return switch (this) {
      _ModeBPromptFlow.defaultKeyScale121ThenTarget => "12345678 1 1 -> target",
      _ModeBPromptFlow.scaleThenTarget => "1234567 -> target",
      _ModeBPromptFlow.tonicThenTarget => "1 -> target",
    };
  }

  String get waitingStatus {
    return switch (this) {
      _ModeBPromptFlow.defaultKeyScale121ThenTarget =>
        "Play 12345678 1 1 + target, waiting answer",
      _ModeBPromptFlow.scaleThenTarget => "Play 1234567 + target, waiting answer",
      _ModeBPromptFlow.tonicThenTarget => "Play tonic + target, waiting answer",
    };
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

class _DegreeSpec {
  const _DegreeSpec({
    required this.degree,
    required this.slug,
  });

  final String degree;
  final String slug;
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
  const EarTrainingPage({super.key});

  @override
  State<EarTrainingPage> createState() => _EarTrainingPageState();
}

class _EarTrainingPageState extends State<EarTrainingPage> {
  static const List<_DegreeSpec> _degrees = <_DegreeSpec>[
    _DegreeSpec(degree: "Do", slug: "do"),
    _DegreeSpec(degree: "Re", slug: "re"),
    _DegreeSpec(degree: "Mi", slug: "mi"),
    _DegreeSpec(degree: "Fa", slug: "fa"),
    _DegreeSpec(degree: "Sol", slug: "sol"),
    _DegreeSpec(degree: "La", slug: "la"),
    _DegreeSpec(degree: "Ti", slug: "ti"),
  ];
  static const int _baseOctave = 5;
  static const int _assetMinOctave = 3;
  static const int _assetMaxOctave = 7;
  static const int _maxOctaveExpansion = 2;
  static const String _defaultNoteId = "Do_5";
  static const String _defaultNoteAssetPath = "audio/ear-piano-do5.wav";
  static const String _modeBDefaultKeyLeadInAssetPath = "audio/ear-mypiano-aaa.WAV";
  static const Duration _modeBDefaultKeyLeadInMaxDuration = Duration(seconds: 7);
  static const String _hintAssetPath = "audio/beep-subdivision.wav";
  static final Map<String, _EarNoteSpec> _noteCatalog = (() {
    final Map<String, _EarNoteSpec> catalog = <String, _EarNoteSpec>{};
    for (int octave = _assetMinOctave; octave <= _assetMaxOctave; octave++) {
      for (final _DegreeSpec degreeSpec in _degrees) {
        final String noteId = _noteId(degreeSpec.degree, octave);
        catalog[noteId] = _EarNoteSpec(
          id: noteId,
          degree: degreeSpec.degree,
          octave: octave,
          label: "${degreeSpec.degree}$octave",
          assetPath: "audio/ear-piano-${degreeSpec.slug}$octave.wav",
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
  int _lowOctaveExpansion = 0;
  int _highOctaveExpansion = 0;
  EarTrainingSpeed _speed = EarTrainingSpeed.standard;
  _ModeBPromptFlow _modeBPromptFlow =
      _ModeBPromptFlow.defaultKeyScale121ThenTarget;
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
  int _modeAReplayCount = 0;
  String _modeAStatus = "Not started";
  String? _modeAAnswer;

  final Stopwatch _modeBWatch = Stopwatch();
  Timer? _modeBFeedbackTimer;
  List<String> _modeBQuestions = <String>[];
  int _modeBIndex = 0;
  bool _modeBRunning = false;
  bool _modeBLocked = false;
  int _modeBCorrect = 0;
  int _modeBReplayCount = 0;
  String _modeBStatus = "Not started";
  String? _modeBSelected;
  String? _modeBFeedback;
  final Map<String, int> _modeBWrongCounts = <String, int>{};

  _SessionRecord? _latestModeARecord;
  _SessionRecord? _latestModeBRecord;
  final List<_SessionRecord> _history = <_SessionRecord>[];
  int _audioSequenceToken = 0;
  Future<void>? _iosAudioContextLoader;
  bool _iosAudioContextConfigured = false;

  bool get _isIOSPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  _EarNoteSpec get _defaultNoteSpec {
    return _noteCatalog[_defaultNoteId] ??
        const _EarNoteSpec(
          id: _defaultNoteId,
          degree: "Do",
          octave: _baseOctave,
          label: "Do5",
          assetPath: _defaultNoteAssetPath,
        );
  }

  List<_EarNoteSpec> get _activeNotes {
    final int minOctave = (_baseOctave - _lowOctaveExpansion)
        .clamp(_assetMinOctave, _assetMaxOctave)
        .toInt();
    final int maxOctave = (_baseOctave + _highOctaveExpansion)
        .clamp(_assetMinOctave, _assetMaxOctave)
        .toInt();
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

  bool get _singleOctaveMode =>
      _lowOctaveExpansion == 0 && _highOctaveExpansion == 0;

  _EarNoteSpec _resolveNote(String noteId) {
    return _noteCatalog[noteId] ?? _defaultNoteSpec;
  }

  String _noteDisplayLabel(String noteId) {
    final _EarNoteSpec? note = _noteCatalog[noteId];
    if (note == null) {
      return noteId;
    }
    if (_singleOctaveMode && note.octave == _baseOctave) {
      return note.degree;
    }
    return note.label;
  }

  String _tonicNoteIdFor(String noteId) {
    final int octave = _resolveNote(noteId).octave;
    final String tonicId = _noteId("Do", octave);
    if (_noteCatalog.containsKey(tonicId)) {
      return tonicId;
    }
    return _defaultNoteId;
  }

  List<String> _scaleNoteIdsFor(String noteId) {
    final int octave = _resolveNote(noteId).octave;
    final List<String> noteIds = _degrees
        .map((_DegreeSpec degreeSpec) => _noteId(degreeSpec.degree, octave))
        .where((String id) => _noteCatalog.containsKey(id))
        .toList(growable: false);
    if (noteIds.isEmpty) {
      return <String>[_tonicNoteIdFor(noteId)];
    }
    return noteIds;
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
    return true;
  }

  String get _octaveRangeSummary {
    final int minOctave = (_baseOctave - _lowOctaveExpansion)
        .clamp(_assetMinOctave, _assetMaxOctave)
        .toInt();
    final int maxOctave = (_baseOctave + _highOctaveExpansion)
        .clamp(_assetMinOctave, _assetMaxOctave)
        .toInt();
    final int noteCount = _activeNoteIds.length;
    return "Range C$minOctave-B$maxOctave ($noteCount notes)";
  }

  @override
  void initState() {
    super.initState();
    unawaited(_configureAudioPlayers());
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
    unawaited(_notePlayer.stop());
    unawaited(_leadInPlayer.stop());
    unawaited(_hintPlayer.stop());
    return _audioSequenceToken;
  }

  Future<void> _playDefaultKeyLeadInAsset() async {
    await _ensurePlatformAudioContext();
    await _leadInPlayer.stop();

    try {
      final Future<void> completed = _leadInPlayer.onPlayerComplete.first;
      await _leadInPlayer.play(
        AssetSource(_modeBDefaultKeyLeadInAssetPath),
        volume: 0.92,
        mode: PlayerMode.mediaPlayer,
      );
      await completed.timeout(
        _modeBDefaultKeyLeadInMaxDuration,
        onTimeout: () => Future<void>.value(),
      );
    } catch (error) {
      debugPrint("Ear training lead-in playback failed: $error");
      rethrow;
    }
  }

  List<String> _defaultKeyScale121NoteIds() {
    final int tonicOctave =
        _baseOctave.clamp(_assetMinOctave, _assetMaxOctave).toInt();
    final int upperTonicOctave =
        (tonicOctave + 1).clamp(_assetMinOctave, _assetMaxOctave).toInt();
    final List<String> noteIds = <String>[
      _noteId("Do", tonicOctave),
      _noteId("Re", tonicOctave),
      _noteId("Mi", tonicOctave),
      _noteId("Fa", tonicOctave),
      _noteId("Sol", tonicOctave),
      _noteId("La", tonicOctave),
      _noteId("Ti", tonicOctave),
      _noteId("Do", upperTonicOctave),
      _noteId("Do", tonicOctave),
      _noteId("Do", tonicOctave),
    ];
    return noteIds
        .where((String id) => _noteCatalog.containsKey(id))
        .toList(growable: false);
  }

  Future<void> _playAsset(
    AudioPlayer player, {
    required String assetPath,
    required double volume,
  }) async {
    await _ensurePlatformAudioContext();
    await player.stop();
    try {
      await player.play(
        AssetSource(assetPath),
        volume: volume,
        mode: PlayerMode.lowLatency,
      );
    } catch (_) {
      await player.play(
        AssetSource(assetPath),
        volume: volume,
        mode: PlayerMode.mediaPlayer,
      );
    }
  }

  Future<void> _playNote(String noteId, {double volume = 0.9}) async {
    final String assetPath = _resolveNote(noteId).assetPath;
    try {
      await _playAsset(
        _notePlayer,
        assetPath: assetPath,
        volume: volume.clamp(0, 1).toDouble(),
      );
    } catch (error) {
      debugPrint("Ear training note playback failed: $error");
    }
  }

  Future<void> _playHintSound() async {
    try {
      await _playAsset(
        _hintPlayer,
        assetPath: _hintAssetPath,
        volume: 0.78,
      );
    } catch (error) {
      debugPrint("Ear training hint playback failed: $error");
    }
  }

  void _playModeAPhaseAudio() {
    if (!_modeARunning) {
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

  Duration get _modeBPromptGap =>
      _speed == EarTrainingSpeed.slow
          ? const Duration(milliseconds: 750)
          : const Duration(milliseconds: 500);

  Future<void> _playModeBPrompt({
    required String noteId,
    required int token,
    bool requireModeBRunning = true,
  }) async {
    if (_modeBPromptFlow == _ModeBPromptFlow.defaultKeyScale121ThenTarget) {
      if (!_canContinueModeBPrompt(
        token: token,
        requireModeBRunning: requireModeBRunning,
      )) {
        return;
      }

      try {
        await _playDefaultKeyLeadInAsset();
      } catch (_) {
        for (final String leadInNoteId in _defaultKeyScale121NoteIds()) {
          if (!_canContinueModeBPrompt(
            token: token,
            requireModeBRunning: requireModeBRunning,
          )) {
            return;
          }
          await _playNote(leadInNoteId);
          await Future<void>.delayed(_modeBPromptGap);
        }
      }

      if (!_canContinueModeBPrompt(
        token: token,
        requireModeBRunning: requireModeBRunning,
      )) {
        return;
      }
      await Future<void>.delayed(_modeBPromptGap);
      if (!_canContinueModeBPrompt(
        token: token,
        requireModeBRunning: requireModeBRunning,
      )) {
        return;
      }
      await _playNote(noteId, volume: 0.94);
      return;
    }

    final List<String> leadInNotes = switch (_modeBPromptFlow) {
      _ModeBPromptFlow.scaleThenTarget => _scaleNoteIdsFor(noteId),
      _ModeBPromptFlow.tonicThenTarget => <String>[_tonicNoteIdFor(noteId)],
      _ModeBPromptFlow.defaultKeyScale121ThenTarget => _defaultKeyScale121NoteIds(),
    };

    for (final String leadInNoteId in leadInNotes) {
      if (!_canContinueModeBPrompt(
        token: token,
        requireModeBRunning: requireModeBRunning,
      )) {
        return;
      }
      await _playNote(leadInNoteId);
      await Future<void>.delayed(_modeBPromptGap);
    }

    if (!_canContinueModeBPrompt(
      token: token,
      requireModeBRunning: requireModeBRunning,
    )) {
      return;
    }
    await _playNote(noteId, volume: 0.94);
  }

  void _playCurrentModeBPrompt() {
    final String? noteId = _modeBCurrentNoteId;
    if (!_modeBRunning || noteId == null) {
      return;
    }
    final int token = _cancelAudioSequence();
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
      _ModeAPhase.tonic => "Build tonic center ($tonicLabel)",
      _ModeAPhase.target => "Play target note",
      _ModeAPhase.think => "Think and decide the note",
      _ModeAPhase.answer => "Answer: $answerLabel",
      _ModeAPhase.replay => "Replay correct note: $answerLabel",
    };
  }

  Duration _modeAPhaseDuration(_ModeAPhase phase) {
    final bool slow = _speed == EarTrainingSpeed.slow;
    return switch (phase) {
      _ModeAPhase.tonic => Duration(milliseconds: slow ? 1200 : 850),
      _ModeAPhase.target => Duration(milliseconds: slow ? 1100 : 700),
      _ModeAPhase.think => Duration(milliseconds: slow ? 2500 : 1800),
      _ModeAPhase.answer => Duration(milliseconds: slow ? 1300 : 950),
      _ModeAPhase.replay => Duration(milliseconds: slow ? 1100 : 750),
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
    _modeATimer?.cancel();
    _cancelAudioSequence();
    _modeAWatch
      ..reset()
      ..start();

    final List<String> questions = _buildQuestionSet(_questionCount);
    if (questions.isEmpty) {
      return;
    }

    setState(() {
      _currentTab = 1;
      _modeAQuestions = questions;
      _modeAIndex = 0;
      _modeAPhase = _ModeAPhase.tonic;
      _modeARunning = true;
      _modeAPaused = false;
      _modeAReplayCount = 0;
      _modeAAnswer = null;
      _modeAStatus = _modeAPhaseLabel(_modeAQuestions[_modeAIndex]);
    });
    _playModeAPhaseAudio();
    _scheduleModeAAdvance();
  }

  void _scheduleModeAAdvance() {
    if (!_modeARunning || _modeAPaused || _modeAQuestions.isEmpty) {
      return;
    }
    _modeATimer?.cancel();
    _modeATimer = Timer(_modeAPhaseDuration(_modeAPhase), _advanceModeA);
  }

  void _advanceModeA() {
    if (!mounted || !_modeARunning || _modeAPaused || _modeAQuestions.isEmpty) {
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
        final String? noteId = _modeACurrentNoteId;
        _modeAStatus = noteId == null
            ? "Resume"
            : "Resume: ${_modeAPhaseLabel(noteId)}";
      });
      _scheduleModeAAdvance();
      return;
    }

    _modeATimer?.cancel();
    _modeAWatch.stop();
    setState(() {
      _modeAPaused = true;
      _modeAStatus = "Paused";
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
      _modeAStatus = "Stopped";
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
      _modeAStatus = "Finished";
      _todayCompletedSets += 1;
      _todayTrainingDuration += record.duration;
      _latestModeARecord = record;
      _currentTab = 3;
      _history.insert(0, record);
      if (_history.length > 20) {
        _history.removeRange(20, _history.length);
      }
    });
  }

  void _startModeB({List<String>? customQuestions}) {
    _modeBFeedbackTimer?.cancel();
    _cancelAudioSequence();
    _modeBWatch
      ..reset()
      ..start();

    final List<String> questions = customQuestions == null || customQuestions.isEmpty
        ? _buildQuestionSet(_questionCount)
        : List<String>.from(customQuestions);
    if (questions.isEmpty) {
      return;
    }

    setState(() {
      _currentTab = 2;
      _modeBQuestions = questions;
      _modeBIndex = 0;
      _modeBRunning = true;
      _modeBLocked = false;
      _modeBCorrect = 0;
      _modeBReplayCount = 0;
      _modeBSelected = null;
      _modeBFeedback = null;
      _modeBStatus = _modeBPromptFlow.waitingStatus;
      _modeBWrongCounts.clear();
    });
    _playCurrentModeBPrompt();
  }

  void _submitModeB(String selected) {
    if (!_modeBRunning || _modeBLocked || _modeBQuestions.isEmpty) {
      return;
    }

    final String answer = _modeBQuestions[_modeBIndex];
    final String answerLabel = _noteDisplayLabel(answer);
    final bool isCorrect = selected == answer;
    _modeBFeedbackTimer?.cancel();

    setState(() {
      _modeBLocked = true;
      _modeBSelected = selected;
      if (isCorrect) {
        _modeBCorrect += 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? "Correct: $answerLabel (auto replay on)"
            : "Correct: $answerLabel";
        _modeBStatus = "Correct";
      } else {
        _modeBWrongCounts[answer] = (_modeBWrongCounts[answer] ?? 0) + 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? "Wrong, answer is $answerLabel (auto replay on)"
            : "Wrong, answer is $answerLabel";
        _modeBStatus = _errorHintEnabled ? "Wrong (hint sound on)" : "Wrong";
      }
    });

    _cancelAudioSequence();
    if (!isCorrect && _errorHintEnabled) {
      unawaited(_playHintSound());
    }
    if (_autoPlayAnswerInModeB) {
      final Duration delay =
          (!isCorrect && _errorHintEnabled)
              ? const Duration(milliseconds: 140)
              : Duration.zero;
      final String answerToReplay = answer;
      unawaited(() async {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        if (!mounted || !_modeBRunning) {
          return;
        }
        await _playNote(answerToReplay, volume: 0.94);
      }());
    }

    if (_autoAdvanceToNextQuestion) {
      _modeBFeedbackTimer = Timer(
        Duration(milliseconds: isCorrect ? 550 : 850),
        _advanceModeB,
      );
    }
  }

  void _advanceModeB() {
    if (!mounted || !_modeBRunning) {
      return;
    }
    _modeBFeedbackTimer?.cancel();

    if (_modeBIndex + 1 >= _modeBQuestions.length) {
      _finishModeB();
      return;
    }

    setState(() {
      _modeBIndex += 1;
      _modeBLocked = false;
      _modeBSelected = null;
      _modeBFeedback = null;
      _modeBStatus = _modeBPromptFlow.waitingStatus;
    });
    _playCurrentModeBPrompt();
  }

  void _finishModeB() {
    _modeBFeedbackTimer?.cancel();
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
      _modeBLocked = false;
      _modeBStatus = "Finished";
      _todayCompletedSets += 1;
      _todayTrainingDuration += record.duration;
      _latestModeBRecord = record;
      _currentTab = 3;
      _history.insert(0, record);
      if (_history.length > 20) {
        _history.removeRange(20, _history.length);
      }
    });
  }

  void _exitModeB() {
    _modeBFeedbackTimer?.cancel();
    _modeBWatch.stop();
    _cancelAudioSequence();
    setState(() {
      _modeBRunning = false;
      _modeBLocked = false;
      _modeBStatus = "Stopped";
    });
  }

  void _replayModeBQuestion() {
    if (!_modeBRunning) {
      return;
    }
    setState(() {
      _modeBReplayCount += 1;
      _modeBStatus = "Replayed current prompt";
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
      spacing: 8,
      runSpacing: 8,
      children: <int>[10, 20].map((int count) {
        return ChoiceChip(
          label: Text("$count Q"),
          selected: _questionCount == count,
          onSelected: (_) {
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
      spacing: 8,
      runSpacing: 8,
      children: EarTrainingSpeed.values.map((EarTrainingSpeed speed) {
        return ChoiceChip(
          label: Text(speed.label),
          selected: _speed == speed,
          onSelected: (_) {
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
      spacing: 8,
      runSpacing: 8,
      children: _ModeBPromptFlow.values.map((_ModeBPromptFlow flow) {
        return ChoiceChip(
          label: Text(flow.label),
          selected: _modeBPromptFlow == flow,
          onSelected: (_) {
            setState(() {
              _modeBPromptFlow = flow;
              if (_modeBRunning && !_modeBLocked) {
                _modeBStatus = _modeBPromptFlow.waitingStatus;
              }
            });
            if (_modeBRunning && !_modeBLocked) {
              _playCurrentModeBPrompt();
            }
          },
        );
      }).toList(),
    );
  }

  Widget _buildOctaveExpansionSelector({
    required String title,
    required int selected,
    required bool lowSide,
    required ValueChanged<int> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List<int>.generate(
            _maxOctaveExpansion + 1,
            (int index) => index,
          ).map((int value) {
            final String sign = value == 0
                ? ""
                : (lowSide ? "-" : "+");
            final String label = value == 0 ? "0" : "$sign$value";
            return ChoiceChip(
              label: Text(label),
              selected: selected == value,
              onSelected: (_) {
                onSelected(value);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSubTabs() {
    final List<_SubTabItem> tabs = <_SubTabItem>[
      const _SubTabItem(index: 0, icon: Icons.home_rounded, label: "Home"),
      const _SubTabItem(index: 1, icon: Icons.hearing_rounded, label: "Listen->Reveal"),
      const _SubTabItem(index: 2, icon: Icons.touch_app_rounded, label: "Listen->Choose"),
      const _SubTabItem(index: 3, icon: Icons.insights_rounded, label: "Results"),
      const _SubTabItem(index: 4, icon: Icons.settings_rounded, label: "Settings"),
    ];

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final _SubTabItem item = tabs[index];
          return ChoiceChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(item.icon, size: 16),
                const SizedBox(width: 6),
                Text(item.label),
              ],
            ),
            selected: item.index == _currentTab,
            onSelected: (_) {
              setState(() {
                _currentTab = item.index;
              });
            },
          );
        },
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
        Text("Scale Ear Trainer", style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          "5-10 minutes daily to build tonic center and degree recognition.",
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Today", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                const Text("Suggested: 1 set Listen->Reveal + 1 set Listen->Choose."),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _startModeA,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Start Mode A"),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _startModeB,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Start Mode B"),
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
                Text("Training Params", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                const Text("Question count"),
                const SizedBox(height: 6),
                _buildQuestionCountSelector(),
                const SizedBox(height: 10),
                const Text("Speed"),
                const SizedBox(height: 6),
                _buildSpeedSelector(),
                const SizedBox(height: 10),
                const Text("Mode B prompt flow"),
                const SizedBox(height: 6),
                _buildModeBPromptFlowSelector(),
                const SizedBox(height: 10),
                const Text("Octave range extension"),
                const SizedBox(height: 6),
                _buildOctaveExpansionSelector(
                  title: "Add lower octaves",
                  selected: _lowOctaveExpansion,
                  lowSide: true,
                  onSelected: (int value) {
                    setState(() {
                      _lowOctaveExpansion = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildOctaveExpansionSelector(
                  title: "Add higher octaves",
                  selected: _highOctaveExpansion,
                  lowSide: false,
                  onSelected: (int value) {
                    setState(() {
                      _highOctaveExpansion = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _octaveRangeSummary,
                  style: theme.textTheme.bodySmall,
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
                Text("Quick Stats", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text("Sets today: $_todayCompletedSets"),
                Text("Time today: ${_formatDuration(_todayTrainingDuration)}"),
                Text("Streak days: $_streakDays"),
                Text("Latest Mode B accuracy: $latestAccuracy"),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _currentTab = 3;
                    });
                  },
                  icon: const Icon(Icons.insights_rounded),
                  label: const Text("Open Results"),
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
        Text("Mode A: Listen -> Reveal", style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text("Flow: tonic -> target -> think -> answer -> replay"),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Status", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text("Question: $current / $total"),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text("Phase: $_modeAStatus"),
                Text(
                  "Answer display: ${_modeAAnswer == null ? "Waiting" : _noteDisplayLabel(_modeAAnswer!)}",
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _modeARunning ? null : _startModeA,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Start"),
                    ),
                    if (_modeARunning)
                      FilledButton.tonalIcon(
                        onPressed: _toggleModeAPause,
                        icon: Icon(
                          _modeAPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(_modeAPaused ? "Resume" : "Pause"),
                      ),
                    if (_modeARunning)
                      OutlinedButton.icon(
                        onPressed: _replayModeAQuestion,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text("Replay"),
                      ),
                    if (_modeARunning)
                      TextButton.icon(
                        onPressed: _exitModeA,
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: const Text("Exit"),
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

    if (_modeBLocked && answer != null) {
      if (noteId == answer) {
        backgroundColor = theme.colorScheme.secondaryContainer;
        foregroundColor = theme.colorScheme.onSecondaryContainer;
      } else if (noteId == _modeBSelected) {
        backgroundColor = theme.colorScheme.errorContainer;
        foregroundColor = theme.colorScheme.onErrorContainer;
      }
    }

    return FilledButton.styleFrom(
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      minimumSize: const Size(0, 46),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text("Mode B: Listen -> Choose", style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          singleOctaveChoices
              ? "Choose one from Do Re Mi Fa Sol La Ti."
              : "Choose one from active range (${choiceNotes.length} notes).",
        ),
        const SizedBox(height: 4),
        Text("Prompt flow: ${_modeBPromptFlow.label}"),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Status", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                Text("Question: $current / $total"),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 10),
                Text("State: $_modeBStatus"),
                if (_modeBFeedback != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(_modeBFeedback!),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: choiceNotes.map((_EarNoteSpec note) {
                    return SizedBox(
                      width: denseChoices ? 82 : 92,
                      child: FilledButton(
                        onPressed: _modeBRunning ? () => _submitModeB(note.id) : null,
                        style: _modeBChoiceStyle(theme, note.id),
                        child: Text(_noteDisplayLabel(note.id)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _modeBRunning ? null : _startModeB,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text("Start"),
                    ),
                    if (_modeBRunning)
                      OutlinedButton.icon(
                        onPressed: _replayModeBQuestion,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text("Replay Prompt"),
                      ),
                    if (_modeBRunning)
                      OutlinedButton.icon(
                        onPressed: _finishModeB,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text("Finish"),
                      ),
                    if (_modeBRunning)
                      TextButton.icon(
                        onPressed: _exitModeB,
                        icon: const Icon(Icons.exit_to_app_rounded),
                        label: const Text("Exit"),
                      ),
                  ],
                ),
                if (_modeBRunning && _modeBLocked && !_autoAdvanceToNextQuestion) ...<Widget>[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: _advanceModeB,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text("Next"),
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
        ? "N/A (not tracked in this mode)"
        : "${(record.accuracy * 100).toStringAsFixed(1)}%";
    final String wrongText = record.wrongCounts.isEmpty
        ? "None"
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
            Text(record.modeLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text("Questions: ${record.questionCount}"),
            Text("Duration: ${_formatDuration(record.duration)}"),
            Text("Accuracy: $accuracyText"),
            Text("Replay count: ${record.replayCount}"),
            const SizedBox(height: 6),
            Text("Wrong items: $wrongText"),
            const SizedBox(height: 6),
            Text(
              "Completed: ${record.finishedAt.year.toString().padLeft(4, "0")}-"
              "${record.finishedAt.month.toString().padLeft(2, "0")}-"
              "${record.finishedAt.day.toString().padLeft(2, "0")} "
              "${record.finishedAt.hour.toString().padLeft(2, "0")}:"
              "${record.finishedAt.minute.toString().padLeft(2, "0")}",
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
        Text("Results", style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        if (_latestModeARecord == null && _latestModeBRecord == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                "No sessions yet. Start one to see metrics.",
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
        if (_latestModeARecord != null) ...<Widget>[
          Text("Latest Mode A", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _buildRecordCard(theme, _latestModeARecord!),
        ],
        if (_latestModeBRecord != null) ...<Widget>[
          const SizedBox(height: 8),
          Text("Latest Mode B", style: theme.textTheme.titleMedium),
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
              label: const Text("Run Mode A"),
            ),
            FilledButton.tonalIcon(
              onPressed: _startModeB,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text("Run Mode B"),
            ),
            FilledButton.tonalIcon(
              onPressed: (_latestModeBRecord != null &&
                      _latestModeBRecord!.wrongCounts.isNotEmpty)
                  ? _startWrongRedo
                  : null,
              icon: const Icon(Icons.replay_circle_filled_rounded),
              label: const Text("Wrong-only Review"),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text("Recent History", style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_history.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                "No history yet",
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ),
        ..._history.take(8).map((_SessionRecord record) {
          final String accuracy = record.correctCount == null
              ? "N/A"
              : "${(record.accuracy * 100).toStringAsFixed(0)}%";
          return Card(
            child: ListTile(
              title: Text(record.modeLabel),
              subtitle: Text(
                "${record.questionCount} Q | ${_formatDuration(record.duration)} | $accuracy",
              ),
              trailing: Text(
                "${record.finishedAt.hour.toString().padLeft(2, "0")}:"
                "${record.finishedAt.minute.toString().padLeft(2, "0")}",
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
        Text("Ear Training Settings", style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text("Defaults", style: theme.textTheme.titleMedium),
                const SizedBox(height: 10),
                const Text("Question count"),
                const SizedBox(height: 6),
                _buildQuestionCountSelector(),
                const SizedBox(height: 10),
                const Text("Speed"),
                const SizedBox(height: 6),
                _buildSpeedSelector(),
                const SizedBox(height: 10),
                const Text("Mode B prompt flow"),
                const SizedBox(height: 6),
                _buildModeBPromptFlowSelector(),
                const SizedBox(height: 10),
                const Text("Octave range extension"),
                const SizedBox(height: 6),
                _buildOctaveExpansionSelector(
                  title: "Add lower octaves",
                  selected: _lowOctaveExpansion,
                  lowSide: true,
                  onSelected: (int value) {
                    setState(() {
                      _lowOctaveExpansion = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildOctaveExpansionSelector(
                  title: "Add higher octaves",
                  selected: _highOctaveExpansion,
                  lowSide: false,
                  onSelected: (int value) {
                    setState(() {
                      _highOctaveExpansion = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _octaveRangeSummary,
                  style: theme.textTheme.bodySmall,
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
                title: const Text("Mode B auto answer replay"),
                value: _autoPlayAnswerInModeB,
                onChanged: (bool value) {
                  setState(() {
                    _autoPlayAnswerInModeB = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text("Auto next question"),
                value: _autoAdvanceToNextQuestion,
                onChanged: (bool value) {
                  setState(() {
                    _autoAdvanceToNextQuestion = value;
                  });
                },
              ),
              SwitchListTile(
                title: const Text("Error hint sound"),
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
                Text("Audio test", style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    final String testNoteId = _noteId("Mi", _baseOctave);
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
                          "Played test prompt (${_modeBPromptFlow.label})",
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.volume_up_rounded),
                  label: const Text("Play test prompt"),
                ),
                const SizedBox(height: 10),
                Text(
                  "Tip: 5 minutes daily, with headphones in a quiet place.",
                  style: theme.textTheme.bodySmall,
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

  String get modeLabel {
    return switch (mode) {
      _EarMode.listenAndReveal => "Mode A Listen->Reveal",
      _EarMode.listenAndChoose => "Mode B Listen->Choose",
    };
  }

  double get accuracy {
    if (correctCount == null || questionCount == 0) {
      return 0;
    }
    return correctCount! / questionCount;
  }
}
