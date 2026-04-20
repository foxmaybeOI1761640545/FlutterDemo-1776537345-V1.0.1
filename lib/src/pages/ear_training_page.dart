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

class EarTrainingPage extends StatefulWidget {
  const EarTrainingPage({super.key});

  @override
  State<EarTrainingPage> createState() => _EarTrainingPageState();
}

class _EarTrainingPageState extends State<EarTrainingPage> {
  static const List<String> _degrees = <String>[
    "Do",
    "Re",
    "Mi",
    "Fa",
    "Sol",
    "La",
    "Ti",
  ];
  static const Map<String, String> _degreeNoteAssetPaths = <String, String>{
    "Do": "audio/ear-note-do.wav",
    "Re": "audio/ear-note-re.wav",
    "Mi": "audio/ear-note-mi.wav",
    "Fa": "audio/ear-note-fa.wav",
    "Sol": "audio/ear-note-sol.wav",
    "La": "audio/ear-note-la.wav",
    "Ti": "audio/ear-note-ti.wav",
  };
  static const String _defaultNoteAssetPath = "audio/ear-note-do.wav";
  static const String _hintAssetPath = "audio/beep-subdivision.wav";

  final Random _random = Random();
  final AudioPlayer _notePlayer = AudioPlayer();
  final AudioPlayer _hintPlayer = AudioPlayer();

  int _currentTab = 0;
  int _questionCount = 10;
  EarTrainingSpeed _speed = EarTrainingSpeed.standard;
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

  @override
  void initState() {
    super.initState();
    unawaited(_configureAudioPlayers());
  }

  @override
  void dispose() {
    _cancelAudioSequence();
    unawaited(_notePlayer.dispose());
    unawaited(_hintPlayer.dispose());
    _modeATimer?.cancel();
    _modeBFeedbackTimer?.cancel();
    super.dispose();
  }

  String? get _modeACurrentDegree {
    if (_modeAQuestions.isEmpty || _modeAIndex >= _modeAQuestions.length) {
      return null;
    }
    return _modeAQuestions[_modeAIndex];
  }

  String? get _modeBCurrentDegree {
    if (_modeBQuestions.isEmpty || _modeBIndex >= _modeBQuestions.length) {
      return null;
    }
    return _modeBQuestions[_modeBIndex];
  }

  Future<void> _configureAudioPlayers() async {
    try {
      await _notePlayer.setReleaseMode(ReleaseMode.stop);
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
    unawaited(_hintPlayer.stop());
    return _audioSequenceToken;
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

  Future<void> _playDegree(String degree, {double volume = 0.9}) async {
    final String assetPath = _degreeNoteAssetPaths[degree] ?? _defaultNoteAssetPath;
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
    final String? degree = _modeACurrentDegree;
    if (degree == null) {
      return;
    }

    switch (_modeAPhase) {
      case _ModeAPhase.tonic:
        unawaited(_playDegree("Do"));
        break;
      case _ModeAPhase.target:
        unawaited(_playDegree(degree, volume: 0.94));
        break;
      case _ModeAPhase.replay:
        unawaited(_playDegree(degree, volume: 0.94));
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
    required String degree,
    required int token,
    bool requireModeBRunning = true,
  }) async {
    await _playDegree("Do");
    await Future<void>.delayed(_modeBPromptGap);
    if (!mounted || token != _audioSequenceToken) {
      return;
    }
    if (requireModeBRunning && !_modeBRunning) {
      return;
    }
    await _playDegree(degree, volume: 0.94);
  }

  void _playCurrentModeBPrompt() {
    final String? degree = _modeBCurrentDegree;
    if (!_modeBRunning || degree == null) {
      return;
    }
    final int token = _cancelAudioSequence();
    unawaited(_playModeBPrompt(degree: degree, token: token));
  }

  List<String> _buildQuestionSet(int count, {List<String>? seedPool}) {
    if (count <= 0) {
      return <String>[];
    }

    final List<String> pool = seedPool == null || seedPool.isEmpty
        ? List<String>.from(_degrees)
        : List<String>.from(seedPool);
    final List<String> uniquePool = pool.toSet().toList();
    if (uniquePool.isEmpty) {
      return <String>[];
    }
    if (uniquePool.length == 1) {
      return List<String>.filled(count, uniquePool.first);
    }

    final List<String> result = <String>[];
    if (seedPool == null && count >= _degrees.length) {
      result.addAll(_degrees);
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

  String _modeAPhaseLabel(String degree) {
    return switch (_modeAPhase) {
      _ModeAPhase.tonic => "Build tonic center (Do)",
      _ModeAPhase.target => "Play target note",
      _ModeAPhase.think => "Think and decide the degree",
      _ModeAPhase.answer => "Answer: $degree",
      _ModeAPhase.replay => "Replay correct note: $degree",
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
      final String degree = _modeAQuestions[_modeAIndex];
      if (_modeAPhase == _ModeAPhase.answer || _modeAPhase == _ModeAPhase.replay) {
        _modeAAnswer = degree;
      }
      _modeAStatus = _modeAPhaseLabel(degree);
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
        final String degree = _modeACurrentDegree ?? "-";
        _modeAStatus = "Resume: ${_modeAPhaseLabel(degree)}";
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
      _modeBStatus = "Play tonic + target, waiting answer";
      _modeBWrongCounts.clear();
    });
    _playCurrentModeBPrompt();
  }

  void _submitModeB(String selected) {
    if (!_modeBRunning || _modeBLocked || _modeBQuestions.isEmpty) {
      return;
    }

    final String answer = _modeBQuestions[_modeBIndex];
    final bool isCorrect = selected == answer;
    _modeBFeedbackTimer?.cancel();

    setState(() {
      _modeBLocked = true;
      _modeBSelected = selected;
      if (isCorrect) {
        _modeBCorrect += 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? "Correct: $answer (auto replay on)"
            : "Correct: $answer";
        _modeBStatus = "Correct";
      } else {
        _modeBWrongCounts[answer] = (_modeBWrongCounts[answer] ?? 0) + 1;
        _modeBFeedback = _autoPlayAnswerInModeB
            ? "Wrong, answer is $answer (auto replay on)"
            : "Wrong, answer is $answer";
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
        await _playDegree(answerToReplay, volume: 0.94);
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
      _modeBStatus = "Play tonic + target, waiting answer";
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
                Text("Answer display: ${_modeAAnswer ?? "Waiting"}"),
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

  ButtonStyle _modeBChoiceStyle(String degree) {
    final String? answer = _modeBCurrentDegree;
    Color? backgroundColor;
    Color? foregroundColor;

    if (_modeBLocked && answer != null) {
      if (degree == answer) {
        backgroundColor = Colors.green.shade600;
        foregroundColor = Colors.white;
      } else if (degree == _modeBSelected) {
        backgroundColor = Colors.red.shade600;
        foregroundColor = Colors.white;
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
      children: <Widget>[
        Text("Mode B: Listen -> Choose", style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text("Choose one from Do Re Mi Fa Sol La Ti."),
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
                  children: _degrees.map((String degree) {
                    return SizedBox(
                      width: 92,
                      child: FilledButton(
                        onPressed: _modeBRunning ? () => _submitModeB(degree) : null,
                        style: _modeBChoiceStyle(degree),
                        child: Text(degree),
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
            .map((MapEntry<String, int> entry) => "${entry.key} x${entry.value}")
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
                    final int token = _cancelAudioSequence();
                    unawaited(
                      _playModeBPrompt(
                        degree: "Mi",
                        token: token,
                        requireModeBRunning: false,
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Played test prompt: Do -> Mi")),
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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF1E2A3E),
            Color(0xFF192537),
            Color(0xFF0E1C2E),
            Color(0xFF0C2032),
          ],
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
