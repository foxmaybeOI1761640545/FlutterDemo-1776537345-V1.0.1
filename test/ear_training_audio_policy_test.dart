import "package:audioplayers/audioplayers.dart";
import "package:flutter_test/flutter_test.dart";

import "package:flutter_demo/src/ear_training_audio_policy.dart";

void main() {
  test("wait player modes use mediaPlayer only", () {
    expect(
      EarTrainingAudioWaitPolicy.waitPlayerModes,
      const <PlayerMode>[PlayerMode.mediaPlayer],
    );
  });

  test("timeout assumption requires flag and mediaPlayer mode", () {
    expect(
      EarTrainingAudioWaitPolicy.shouldAssumeWaitCompletedAfterTimeout(
        allowTimeoutAsSuccess: true,
        mode: PlayerMode.mediaPlayer,
      ),
      isTrue,
    );
    expect(
      EarTrainingAudioWaitPolicy.shouldAssumeWaitCompletedAfterTimeout(
        allowTimeoutAsSuccess: false,
        mode: PlayerMode.mediaPlayer,
      ),
      isFalse,
    );
    expect(
      EarTrainingAudioWaitPolicy.shouldAssumeWaitCompletedAfterTimeout(
        allowTimeoutAsSuccess: true,
        mode: PlayerMode.lowLatency,
      ),
      isFalse,
    );
  });

  test("prompt failure policy unlocks answer flow", () {
    expect(
      EarTrainingAudioWaitPolicy.shouldUnlockAnswerAfterPromptFailure(),
      isTrue,
    );
  });
}
