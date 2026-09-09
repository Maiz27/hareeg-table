import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/match_replay_timeline.dart';
import 'package:hareeg_table/domain/classic_hareeg/replay/replay_review_state.dart';
import 'package:hareeg_table/domain/classic_hareeg/reporting/match_action_transcript.dart';

import '../../../support/completed_match_fixture.dart';

const _slow = Timeout(Duration(minutes: 5));

late MatchReplayTimeline _timeline;

ReplayReviewState get _start => ReplayReviewState.atStart(_timeline);

void main() {
  setUpAll(() {
    final state = buildCompletedMatch(seed: 13).recorderState;
    final transcript = MatchActionTranscript(
      initialSnapshot: state.initialSnapshot!,
      entries: state.entries,
    );
    _timeline =
        (MatchReplayTimeline.build(transcript) as ReplayTimelineBuilt).timeline;
  });

  test('a review starts at the first frame', timeout: _slow, () {
    expect(_start.cursor, 0);
    expect(_start.stepNumber, 1);
    expect(_start.length, _timeline.length);
    expect(_start.previousFrame, isNull);
    expect(_start.frame.kind, ReplayFrameKind.initial);
  });

  test('navigation never mutates the state it was called on', timeout: _slow, () {
    final origin = _start.seekTo(50);
    origin
      ..stepForward()
      ..stepBack()
      ..nextRound()
      ..previousRound()
      ..seekTo(3);
    expect(origin.cursor, 50);
  });

  test('the ends are walls, not wraps', timeout: _slow, () {
    final first = _start;
    expect(first.canStepBack, isFalse);
    expect(first.stepBack().cursor, 0);

    final last = _start.seekToEnd();
    expect(last.cursor, _timeline.length - 1);
    expect(last.canStepForward, isFalse);
    expect(last.stepForward().cursor, _timeline.length - 1);
  });

  test('seeking clamps and does not depend on where you came from', timeout: _slow, () {
    expect(_start.seekTo(-40).cursor, 0);
    expect(_start.seekTo(_timeline.length + 500).cursor, _timeline.length - 1);

    // A slider drag and a restored position are both legitimate sources of an
    // out-of-range request; neither is a programming error worth crashing over.
    final fromStart = _start.seekTo(120);
    final fromEnd = _start.seekToEnd().seekTo(120);
    expect(fromStart.cursor, fromEnd.cursor);
    expect(fromStart.frame.index, fromEnd.frame.index);
  });

  test('a seek then a step equals seeking one further', timeout: _slow, () {
    final random = Random(20260825);
    for (var i = 0; i < 50; i++) {
      final index = random.nextInt(_timeline.length - 1);
      expect(
        _start.seekTo(index).stepForward().cursor,
        _start.seekTo(index + 1).cursor,
        reason: 'index $index',
      );
    }
  });

  test('stepping back visits every frame in order', timeout: _slow, () {
    var state = _start.seekTo(25);
    final visited = <int>[];
    while (state.canStepBack) {
      state = state.stepBack();
      visited.add(state.cursor);
    }
    expect(visited, [for (var i = 24; i >= 0; i--) i]);
  });

  test('the previous frame is the state a move was decided from', timeout: _slow, () {
    final state = _start.seekTo(10);
    expect(state.previousFrame, isNotNull);
    expect(state.previousFrame!.index, 9);
  });

  test('round jumps land exactly on a round start', timeout: _slow, () {
    expect(_timeline.roundNumbers.length, greaterThan(1));

    var state = _start;
    for (final round in _timeline.roundNumbers.skip(1)) {
      state = state.nextRound();
      expect(state.cursor, _timeline.startIndexOfRound(round));
      expect(state.roundNumber, round);
    }

    // Nowhere left to go forward from the last round.
    expect(state.canGoNextRound, isFalse);
    expect(state.nextRound().cursor, state.cursor);
  });

  test('back rewinds within a round before leaving it', timeout: _slow, () {
    // The behaviour of a track-skip control: the first press restarts the
    // round you are in, the second takes you to the one before.
    final secondRound = _timeline.roundNumbers[1];
    final secondStart = _timeline.startIndexOfRound(secondRound)!;

    final midRound = _start.seekTo(secondStart + 3);
    expect(midRound.canGoPreviousRound, isTrue);

    final rewound = midRound.previousRound();
    expect(rewound.cursor, secondStart);

    final wentBack = rewound.previousRound();
    expect(
      wentBack.cursor,
      _timeline.startIndexOfRound(_timeline.roundNumbers.first),
    );
  });

  test('there is nowhere back to go from the very start', timeout: _slow, () {
    expect(_start.canGoPreviousRound, isFalse);
    expect(_start.previousRound().cursor, 0);
  });
}
