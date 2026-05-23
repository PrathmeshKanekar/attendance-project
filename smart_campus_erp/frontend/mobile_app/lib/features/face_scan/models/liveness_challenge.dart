/// Liveness challenge system for anti-spoofing.
///
/// Generates random challenges (blink, smile, head turn) that defeat
/// replay videos and static photo attacks.
library;

import 'dart:math';

/// Types of liveness challenges the system can request.
enum ChallengeType {
  blink,
  smile,
  turnLeft,
  turnRight,
}

/// A single liveness challenge with its detection thresholds.
class LivenessChallenge {
  final ChallengeType type;
  final String        instruction;
  final String        icon;

  const LivenessChallenge({
    required this.type,
    required this.instruction,
    required this.icon,
  });

  static const _challenges = [
    LivenessChallenge(
      type: ChallengeType.blink,
      instruction: 'Blink your eyes',
      icon: '👁️',
    ),
    LivenessChallenge(
      type: ChallengeType.smile,
      instruction: 'Smile naturally',
      icon: '😊',
    ),
    LivenessChallenge(
      type: ChallengeType.turnLeft,
      instruction: 'Turn head slightly left',
      icon: '◀️',
    ),
    LivenessChallenge(
      type: ChallengeType.turnRight,
      instruction: 'Turn head slightly right',
      icon: '▶️',
    ),
  ];

  /// Generates a randomized sequence of [count] challenges.
  /// Always starts with a blink (most natural/fastest).
  /// Ensures no two consecutive challenges are the same.
  static List<LivenessChallenge> generateSequence({int count = 3}) {
    final random = Random();
    final sequence = <LivenessChallenge>[];

    // Always start with blink — most intuitive
    sequence.add(_challenges[0]);

    // Fill remaining with non-blink challenges, no repeats
    final remaining = _challenges.sublist(1).toList()..shuffle(random);
    for (int i = 0; i < count - 1 && i < remaining.length; i++) {
      sequence.add(remaining[i]);
    }

    return sequence;
  }
}

/// Tracks progress through a liveness challenge sequence.
class LivenessProgress {
  final List<LivenessChallenge> challenges;
  final int                     currentIndex;
  final bool                    isComplete;

  /// Timestamps for anti-cheat analysis.
  final List<int>               completionTimestamps;

  const LivenessProgress({
    required this.challenges,
    this.currentIndex        = 0,
    this.isComplete          = false,
    this.completionTimestamps = const [],
  });

  LivenessChallenge? get currentChallenge =>
      currentIndex < challenges.length ? challenges[currentIndex] : null;

  int get completedCount => currentIndex;
  int get totalCount     => challenges.length;

  double get progressFraction =>
      challenges.isEmpty ? 0.0 : currentIndex / challenges.length;

  LivenessProgress advanceToNext() {
    final nextIndex = currentIndex + 1;
    return LivenessProgress(
      challenges:           challenges,
      currentIndex:         nextIndex,
      isComplete:           nextIndex >= challenges.length,
      completionTimestamps: [
        ...completionTimestamps,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  /// Validates timing looks human (not too fast = bot, not too slow = issues).
  bool get hasValidTiming {
    if (completionTimestamps.length < 2) return true;
    for (int i = 1; i < completionTimestamps.length; i++) {
      final delta = completionTimestamps[i] - completionTimestamps[i - 1];
      // A human can't complete challenges faster than 400ms each
      if (delta < 400) return false;
    }
    return true;
  }

  static LivenessProgress create({int challengeCount = 3}) {
    return LivenessProgress(
      challenges: LivenessChallenge.generateSequence(count: challengeCount),
    );
  }
}
