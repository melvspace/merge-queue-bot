import 'dart:io';

import 'package:merge_queue_bot/src/models.dart';
import 'package:merge_queue_bot/src/state.dart';
import 'package:merge_queue_bot/src/store.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String database;
  late Store store;
  final firstPoll = DateTime.utc(2026, 10, 15, 12);

  setUp(() {
    Directory('/tmp/codex').createSync(recursive: true);
    temporary = Directory('/tmp/codex').createTempSync('queue-store-test-');
    database = '${temporary.path}/nested/queue.sqlite';
    store = Store(database);
  });

  tearDown(() {
    store.close();
    temporary.deleteSync(recursive: true);
  });

  test('creates fresh state without writing another queue', () {
    final state = store.load('1:main', 'merge-queue/main');

    expect(state.key, '1:main');
    expect(state.branch, 'merge-queue/main');
    expect(state.candidate, isNull);
    expect(state.groups, isEmpty);
    expect(state.rejections, isEmpty);
    expect(state.paused, isNull);
  });

  test('round-trips recovery, frozen pipeline, and bookkeeping state', () {
    final member = mr(1, sourceProjectId: 123);
    final state = QueueState(
      key: '1:main',
      branch: 'merge-queue/main',
      groups: [
        [2, 3],
        [4],
      ],
      candidate: Candidate(
        baseSha: 'base',
        members: [member],
        createdAt: firstPoll,
        phase: 'finalizing',
        sha: 'candidate',
        expectedRemoteSha: 'previous',
        startedAt: firstPoll.add(const Duration(seconds: 2)),
        pipelineIds: [100, 101],
        finalized: [2],
        closing: [1],
      ),
      batchIid: 50,
      batchUrl: 'https://gitlab.example.test/project/-/merge_requests/50',
      paused: 'pipeline canceled',
      lastPublishedSha: 'candidate',
      lastCandidateAt: firstPoll,
      rejections: [
        Rejection(
          member,
          'source changed after delivery',
          '<!-- delivered update -->',
          [7, 8],
          deliveredUpdate: true,
        ),
      ],
    );

    store.save(state);
    store.close();
    store = Store(database);

    final recovered = store.load('1:main', 'ignored-branch');

    expect(recovered.toJson(), state.toJson());
    expect(recovered.candidate!.members.single.toJson(), member.toJson());
    expect(recovered.candidate!.members.single.sourceProjectId, 123);
    expect(recovered.rejections.single.member.sourceProjectId, 123);
    expect(recovered.rejections.single.deliveredUpdate, isTrue);

    recovered.candidate!.phase = 'landed';
    recovered.candidate!.pipelineIds = [];
    recovered.paused = null;
    recovered.rejections.clear();

    store.save(recovered);
    final updated = store.load('1:main', 'ignored-branch');

    expect(updated.candidate!.phase, 'landed');
    expect(updated.candidate!.pipelineIds, isEmpty);
    expect(updated.paused, isNull);
    expect(updated.rejections, isEmpty);
    expect(store.load('2:main', 'another-branch').candidate, isNull);
  });

  test('preserves assignment FIFO through polling and restart', () {
    final olderMr = mr(
      1,
      createdAt: firstPoll.subtract(const Duration(days: 2)),
    );
    final newerMr = mr(2, createdAt: firstPoll);

    store.observe('1:main', [newerMr], 99, firstPoll);

    final secondPoll = firstPoll.add(const Duration(seconds: 30));
    store.observe('1:main', [olderMr, newerMr], 99, secondPoll);

    store.close();
    store = Store(database);
    store.observe('1:main', [olderMr, newerMr], 99, secondPoll);

    final waiting = store.waiting('1:main', 99, 'main');

    expect(waiting.map((entry) => entry.mr.iid), [2, 1]);
    expect(waiting.map((entry) => entry.enqueuedAt), [firstPoll, secondPoll]);
  });

  test(
    'breaks simultaneous assignment ties by creation time then MR number',
    () {
      final earlier = firstPoll.subtract(const Duration(days: 1));

      store.observe(
        '1:main',
        [mr(3), mr(2, createdAt: earlier), mr(1, createdAt: earlier)],
        99,
        firstPoll,
      );

      expect(waitingIds(store), [1, 2, 3]);
    },
  );

  test('refreshes snapshots and returns only eligible assigned items', () {
    store.observe(
      '1:main',
      [
        mr(1),
        mr(2, draft: true),
        mr(3, state: 'closed'),
        mr(4, target: 'release'),
        mr(5, assignees: [7]),
      ],
      99,
      firstPoll,
    );

    expect(waitingIds(store), [1]);

    store.observe(
      '1:main',
      [
        mr(1, sha: 'updated-source'),
        mr(2),
        mr(3),
        mr(4, target: 'release'),
        mr(5, assignees: [7]),
      ],
      99,
      firstPoll.add(const Duration(seconds: 30)),
    );
    final waiting = store.waiting('1:main', 99, 'main');

    expect(waiting.map((entry) => entry.mr.iid), [1, 2, 3]);
    expect(waiting.first.mr.sha, 'updated-source');
    expect(waiting.map((entry) => entry.enqueuedAt), everyElement(firstPoll));
    expect(store.waiting('1:main', 99, 'release').single.mr.iid, 4);
  });

  test('restores only previously observed assignees without guessing', () {
    expect(store.previousAssignees('1:main', 1), isEmpty);

    store.observe(
      '1:main',
      [
        mr(1, assignees: [7, 8]),
      ],
      99,
      firstPoll,
    );
    store.observe(
      '1:main',
      [
        mr(1, assignees: [99]),
      ],
      99,
      firstPoll,
    );
    store.observe(
      '1:main',
      [
        mr(1, assignees: [99, 10]),
      ],
      99,
      firstPoll,
    );

    expect(store.previousAssignees('1:main', 1), [7, 8]);

    store.close();
    store = Store(database);

    expect(store.previousAssignees('1:main', 1), [7, 8]);

    store.observe(
      '1:main',
      [
        mr(1, assignees: [11]),
      ],
      99,
      firstPoll,
    );
    store.observe('1:main', [mr(1)], 99, firstPoll);

    expect(store.previousAssignees('1:main', 1), [11]);

    store.observe(
      '1:main',
      [
        mr(1),
        mr(2, assignees: [99, 12]),
      ],
      99,
      firstPoll,
    );

    expect(store.previousAssignees('1:main', 2), isEmpty);
  });

  test('suppresses rejected items until an observed assignment cycle', () {
    store.observe('1:main', [mr(1), mr(2)], 99, firstPoll);
    store.suppress('1:main', 1);

    expect(waitingIds(store), [2]);

    store.close();
    store = Store(database);

    final later = firstPoll.add(const Duration(minutes: 1));
    store.observe('1:main', [mr(1, sha: 'new-head'), mr(2)], 99, later);

    expect(waitingIds(store), [2]);

    store.observe(
      '1:main',
      [
        mr(1, assignees: [7]),
        mr(2),
      ],
      99,
      later,
    );
    store.observe('1:main', [mr(1), mr(2)], 99, later);

    expect(waitingIds(store), [2, 1]);
    expect(store.waiting('1:main', 99, 'main').last.enqueuedAt, later);
    expect(store.previousAssignees('1:main', 1), [7]);
  });

  test('a missing observation ends assignment and reappearance requeues', () {
    store.observe('1:main', [mr(1), mr(2)], 99, firstPoll);
    store.suppress('1:main', 1);
    store.observe('1:main', [mr(2)], 99, firstPoll);

    expect(waitingIds(store), [2]);

    final later = firstPoll.add(const Duration(minutes: 1));
    store.observe('1:main', [mr(1), mr(2)], 99, later);

    expect(waitingIds(store), [2, 1]);
    expect(store.waiting('1:main', 99, 'main').last.enqueuedAt, later);
  });

  test(
    'isolates observations, suppression, and previous assignees by queue',
    () {
      store.observe(
        '1:main',
        [
          mr(1, assignees: [7]),
        ],
        99,
        firstPoll,
      );
      store.observe(
        '2:main',
        [
          mr(1, assignees: [8]),
        ],
        99,
        firstPoll,
      );
      store.observe('1:main', [mr(1)], 99, firstPoll);
      store.observe('2:main', [mr(1)], 99, firstPoll);
      store.suppress('1:main', 1);

      expect(waitingIds(store), isEmpty);
      expect(waitingIds(store, '2:main'), [1]);
      expect(store.previousAssignees('1:main', 1), [7]);
      expect(store.previousAssignees('2:main', 1), [8]);

      store.observe('1:main', [], 99, firstPoll);

      expect(waitingIds(store, '2:main'), [1]);
    },
  );
}

List<int> waitingIds(Store store, [String queue = '1:main']) =>
    store.waiting(queue, 99, 'main').map((entry) => entry.mr.iid).toList();

MergeRequest mr(
  int iid, {
  List<int> assignees = const [99],
  DateTime? createdAt,
  String? sha,
  int? sourceProjectId,
  String state = 'opened',
  bool draft = false,
  String target = 'main',
}) => MergeRequest(
  iid: iid,
  title: 'Change $iid',
  url: 'https://gitlab.example.test/project/-/merge_requests/$iid',
  sha: sha ?? 'source-$iid',
  targetBranch: target,
  sourceBranch: 'change-$iid',
  sourceProjectId: sourceProjectId,
  state: state,
  draft: draft,
  assignees: assignees,
  authorName: 'Author $iid',
  authorEmail: 'author-$iid@example.test',
  createdAt: createdAt ?? DateTime.utc(2026, 10, 15, 12),
);
