import 'dart:convert';
import 'dart:io';

import 'package:merge_queue_bot/src/models.dart';
import 'package:merge_queue_bot/src/state.dart';
import 'package:merge_queue_bot/src/store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preserves persisted merge request keys, nullable metadata, and UTC',
    () {
      final snapshot = memberSnapshot();
      final member = MergeRequest.fromJson(snapshot);

      expect(member.targetBranch, 'main');
      expect(member.sourceBranch, 'change-7');
      expect(member.createdAt, DateTime.utc(2026, 10, 15, 12));
      expect(member.createdAt.isUtc, isTrue);
      expect(member.toJson(), snapshot);

      final withoutMetadata = memberSnapshot()
        ..['sourceProjectId'] = null
        ..['mergeCommitSha'] = null;
      final decoded = MergeRequest.fromJson(withoutMetadata);

      expect(decoded.sourceProjectId, isNull);
      expect(decoded.mergeCommitSha, isNull);
      expect(decoded.toJson(), withoutMetadata);
    },
  );

  test(
    'copyWith updates source while preserving and explicitly clearing metadata',
    () {
      final member = MergeRequest.fromJson(memberSnapshot());
      final updated = member.copyWith(sha: 'updated-source');

      expect(updated.sha, 'updated-source');
      expect(updated.sourceProjectId, 23);
      expect(updated.mergeCommitSha, 'landed-sha');
      expect(updated.assignees, [99, 8]);
      expect(member.sha, 'source-sha');
      expect(member, MergeRequest.fromJson(memberSnapshot()));

      final cleared = updated.copyWith(
        sourceProjectId: null,
        mergeCommitSha: null,
      );

      expect(cleared.sourceProjectId, isNull);
      expect(cleared.mergeCommitSha, isNull);
      expect(cleared.targetBranch, 'main');
    },
  );

  test('preserves nested candidate snapshot and frozen pipeline IDs', () {
    final snapshot = candidateSnapshot();
    final candidate = Candidate.fromJson(snapshot);

    expect(candidate.members.single.iid, 7);
    expect(candidate.createdAt.isUtc, isTrue);
    expect(candidate.startedAt, DateTime.utc(2026, 10, 15, 12, 0, 2));
    expect(candidate.pipelineIds, [100, 101]);
    expect(candidate.finalized, [3]);
    expect(candidate.closing, [7]);
    expect(candidate.toJson(), snapshot);
  });

  test(
    'distinguishes undiscovered pipelines from a frozen empty pipeline set',
    () {
      final undiscovered = candidateSnapshot()..['pipelineIds'] = null;
      final empty = candidateSnapshot()..['pipelineIds'] = <int>[];

      expect(Candidate.fromJson(undiscovered).pipelineIds, isNull);
      expect(Candidate.fromJson(undiscovered).toJson(), undiscovered);
      expect(Candidate.fromJson(empty).pipelineIds, isEmpty);
      expect(Candidate.fromJson(empty).toJson(), empty);
    },
  );

  test('reads legacy candidate snapshots without closing bookkeeping', () {
    final legacy = candidateSnapshot()..remove('closing');
    final candidate = Candidate.fromJson(legacy);

    expect(candidate.closing, isEmpty);
    expect(candidate.toJson(), {...legacy, 'closing': <int>[]});
  });

  test(
    'legacy candidates default to API landing and push mode survives restart',
    () {
      final legacy = candidateSnapshot()..remove('landingMode');

      expect(Candidate.fromJson(legacy).landingMode, LandingMode.merge);

      final push = candidateSnapshot()..['landingMode'] = 'fast_forward_push';

      expect(Candidate.fromJson(push).landingMode, LandingMode.fastForwardPush);
      expect(Candidate.fromJson(push).toJson(), push);
    },
  );

  test('preserves rejection assignees and defaults legacy delivery intent', () {
    final snapshot = rejectionSnapshot();
    final rejection = Rejection.fromJson(snapshot);

    expect(rejection.previousAssignees, [8, 9]);
    expect(rejection.deliveredUpdate, isTrue);
    expect(rejection.toJson(), snapshot);

    final legacy = rejectionSnapshot()..remove('deliveredUpdate');
    final decoded = Rejection.fromJson(legacy);

    expect(decoded.deliveredUpdate, isFalse);
    expect(decoded.toJson(), {...legacy, 'deliveredUpdate': false});
  });

  test('preserves complete persisted queue recovery state', () {
    final snapshot = queueSnapshot();
    final state = QueueState.fromJson(snapshot);

    expect(state.groups, [
      [8, 9],
      [10],
    ]);
    expect(state.candidate!.members.single.sourceProjectId, 23);
    expect(state.rejections.single.member.iid, 7);
    expect(state.lastCandidateAt, DateTime.utc(2026, 10, 15, 12));
    expect(state.lastCandidateAt!.isUtc, isTrue);
    expect(state.toJson(), snapshot);
  });

  test('loads legacy SQLite snapshots and saves the compatible wire shape', () {
    Directory('/tmp/codex').createSync(recursive: true);

    final temporary = Directory('/tmp/codex').createTempSync('serialization-');
    addTearDown(() => temporary.deleteSync(recursive: true));

    final path = '${temporary.path}/queue.sqlite';
    final expected = queueSnapshot();
    final legacy = queueSnapshot();
    (legacy['candidate'] as Json).remove('closing');
    ((legacy['rejections'] as List).single as Json).remove('deliveredUpdate');
    (expected['candidate'] as Json)['closing'] = <int>[];
    ((expected['rejections'] as List).single as Json)['deliveredUpdate'] =
        false;

    final database = sqlite3.open(path);
    database.execute(
      'CREATE TABLE queues (key TEXT PRIMARY KEY, state TEXT NOT NULL)',
    );
    database.execute('INSERT INTO queues (key, state) VALUES (?, ?)', [
      '23:main',
      jsonEncode(legacy),
    ]);
    database.close();

    final store = Store(path);
    final recovered = store.load('23:main', 'ignored-branch');

    expect(recovered.toJson(), expected);

    store.save(recovered);
    store.close();

    final saved = sqlite3.open(path);
    final json = saved.select('SELECT state FROM queues').single['state'];
    saved.close();

    expect(jsonDecode(json as String), expected);
  });

  test('queue state retains mutable transitions after deserialization', () {
    final state = QueueState.fromJson(queueSnapshot());
    final candidate = state.candidate!;

    candidate.phase = 'observing';
    candidate.sha = 'rebuilt-sha';
    candidate.expectedRemoteSha = null;
    candidate.startedAt = null;
    candidate.pipelineIds = [];
    candidate.finalized.add(7);
    candidate.closing.clear();
    state.groups.first.removeLast();
    state.groups = [
      [10],
    ];
    state.rejections.clear();
    state.batchIid = null;
    state.batchUrl = null;
    state.paused = null;
    state.lastPublishedSha = 'rebuilt-sha';
    state.lastCandidateAt = null;

    expect(candidate.phase, 'observing');
    expect(candidate.sha, 'rebuilt-sha');
    expect(candidate.expectedRemoteSha, isNull);
    expect(candidate.startedAt, isNull);
    expect(candidate.pipelineIds, isEmpty);
    expect(candidate.finalized, [3, 7]);
    expect(candidate.closing, isEmpty);
    expect(state.groups, [
      [10],
    ]);
    expect(state.rejections, isEmpty);
    expect(state.batchIid, isNull);
    expect(state.batchUrl, isNull);
    expect(state.paused, isNull);
    expect(state.lastPublishedSha, 'rebuilt-sha');
    expect(state.lastCandidateAt, isNull);

    state.candidate = null;

    expect(state.candidate, isNull);
  });

  test(
    'mutable collection defaults are independent for each state instance',
    () {
      final first = Candidate(
        baseSha: 'base',
        members: [],
        createdAt: DateTime.utc(2026),
      );
      final second = Candidate(
        baseSha: 'base',
        members: [],
        createdAt: DateTime.utc(2026),
      );
      final firstQueue = QueueState(key: '1:main', branch: 'merge-queue/main');
      final secondQueue = QueueState(
        key: '2:main',
        branch: 'merge-queue/other',
      );

      first.finalized.add(7);
      first.closing.add(8);
      firstQueue.groups.add([7]);
      firstQueue.rejections.add(Rejection.fromJson(rejectionSnapshot()));

      expect(second.finalized, isEmpty);
      expect(second.closing, isEmpty);
      expect(secondQueue.groups, isEmpty);
      expect(secondQueue.rejections, isEmpty);
    },
  );
}

Json memberSnapshot() => {
  'iid': 7,
  'title': 'Change seven',
  'url': 'https://gitlab.example.test/project/-/merge_requests/7',
  'sha': 'source-sha',
  'target': 'main',
  'source': 'change-7',
  'state': 'opened',
  'draft': false,
  'assignees': [99, 8],
  'authorName': 'Author Seven',
  'authorEmail': 'seven@example.test',
  'createdAt': '2026-10-15T12:00:00.000Z',
  'mergeCommitSha': 'landed-sha',
  'sourceProjectId': 23,
};

Json candidateSnapshot() => {
  'landingMode': 'merge',
  'baseSha': 'base-sha',
  'members': [memberSnapshot()],
  'createdAt': '2026-10-15T12:00:00.000Z',
  'phase': 'finalizing',
  'sha': 'batch-sha',
  'expectedRemoteSha': 'previous-sha',
  'startedAt': '2026-10-15T12:00:02.000Z',
  'pipelineIds': [100, 101],
  'finalized': [3],
  'closing': [7],
};

Json rejectionSnapshot() => {
  'member': memberSnapshot(),
  'reason': 'source changed after delivery',
  'marker': '<!-- delivered update -->',
  'previousAssignees': [8, 9],
  'deliveredUpdate': true,
};

Json queueSnapshot() => {
  'key': '23:main',
  'branch': 'merge-queue/main',
  'groups': [
    [8, 9],
    [10],
  ],
  'candidate': candidateSnapshot(),
  'batchIid': 50,
  'batchUrl': 'https://gitlab.example.test/project/-/merge_requests/50',
  'paused': 'pipeline canceled',
  'lastPublishedSha': 'batch-sha',
  'lastCandidateAt': '2026-10-15T12:00:00.000Z',
  'rejections': [rejectionSnapshot()],
};
