import "package:audioplayers/audioplayers.dart";

class EarTrainingAudioWaitPolicy {
  const EarTrainingAudioWaitPolicy._();

  static const List<PlayerMode> waitPlayerModes = <PlayerMode>[
    PlayerMode.mediaPlayer,
  ];

  static bool shouldAssumeWaitCompletedAfterTimeout({
    required bool allowTimeoutAsSuccess,
    required PlayerMode mode,
  }) {
    return allowTimeoutAsSuccess && mode == PlayerMode.mediaPlayer;
  }

  static bool shouldUnlockAnswerAfterPromptFailure() {
    return true;
  }
}
