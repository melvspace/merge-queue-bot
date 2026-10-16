import 'package:merge_queue_bot/src/config.dart';
import 'package:merge_queue_bot/src/models.dart';
import 'package:merge_queue_bot/src/queue.dart';
import 'package:merge_queue_bot/src/store.dart';
import 'package:test/test.dart';

import 'support/fakes.dart';

void main() {
  late _Fixture fixture;

  setUp(() => fixture = _Fixture());
  tearDown(() => fixture.store.close());

  group('fast-forward push landing', () {
    setUp(() {
      fixture = _Fixture.replace(
        fixture,
        landingMode: LandingMode.fastForwardPush,
      );
      fixture.hosting.settings = testProject.copyWith(
        mergeMethod: 'rebase_merge',
      );
    });

    test(
      'lands the tested SHA and retires the batch without the merge API',
      () async {
        await fixture.publish([member(1), member(2)]);

        final sha = fixture.sha;
        final batch = fixture.queue.state.batchIid!;
        fixture.hosting.pipelineData[1] = Pipeline(1, sha, 'running');
        fixture.advance(10);

        await fixture.tick();

        expect(fixture.repository.fastForwards, isEmpty);

        fixture.hosting.pipelineData[1] = Pipeline(1, sha, 'success');

        await fixture.tick();

        expect(fixture.repository.fastForwards.single.sha, sha);
        expect(fixture.repository.fastForwards.single.lease, 'base-0');
        expect(fixture.hosting.branches['main'], sha);
        expect(fixture.hosting.mergeAttempts, isEmpty);
        expect(fixture.hosting.closedMembers, [1, 2]);
        expect(fixture.hosting.closedBatches, [batch]);
        expect(fixture.queue.state.candidate, isNull);

        fixture.hosting.members[3] = member(3);

        await fixture.tick();

        expect(fixture.queue.state.batchIid, isNot(batch));
        expect(fixture.hosting.batches[batch]!.sha, sha);
      },
    );

    for (final status in [
      null,
      'unchecked',
      'checking',
      'preparing',
      'ci_still_running',
    ]) {
      test('requires explicit mergeability after $status', () async {
        await fixture.publish([member(1)]);

        final iid = fixture.queue.state.batchIid!;
        fixture.hosting.setBatchStatus(iid, status);
        fixture.advance(10);

        await fixture.tick();

        expect(fixture.repository.fastForwards, isEmpty);
        expect(fixture.queue.state.candidate!.phase, 'observing');

        fixture.hosting.setBatchStatus(iid, 'mergeable');

        await fixture.tick();

        expect(fixture.repository.fastForwards, hasLength(1));
      });
    }

    for (final status in [
      'not_approved',
      'discussions_not_resolved',
      'ci_must_pass',
      'status_checks_must_pass',
      'unknown',
    ]) {
      test('does not push when GitLab reports $status', () async {
        await fixture.publish([member(1)]);

        fixture.hosting.setBatchStatus(fixture.queue.state.batchIid!, status);
        fixture.advance(10);

        await fixture.tick();

        expect(fixture.repository.fastForwards, isEmpty);
        expect(fixture.queue.state.paused, contains(status));
        expect(fixture.hosting.closedMembers, isEmpty);
      });
    }

    test('rebuilds after losing the target lease at push time', () async {
      await fixture.publish([member(1)]);

      fixture.repository.beforeFastForward = () async {
        fixture.hosting.branches['main'] = 'base-1';
      };
      fixture.advance(10);

      await fixture.tick();

      expect(fixture.repository.fastForwards, isEmpty);
      expect(fixture.hosting.branches['main'], 'base-1');
      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.hosting.closedMembers, isEmpty);

      await fixture.tick();

      expect(fixture.repository.assemblies.last.base, 'base-1');
    });

    test('reconciles a lost push response with an opened batch MR', () async {
      await fixture.publish([member(1)]);

      fixture.repository.failFastForwardAfterPush = true;
      fixture.advance(10);

      await fixture.tick();
      fixture.restart();

      await fixture.tick();

      expect(fixture.repository.fastForwards, hasLength(1));
      expect(fixture.hosting.closedMembers, [1]);
      expect(fixture.queue.state.candidate, isNull);
    });

    test('accepts GitLab marking a pushed batch merged', () async {
      await fixture.publish([member(1)]);

      final sha = fixture.sha;
      final iid = fixture.queue.state.batchIid!;
      fixture.repository.afterFastForward = () async {
        fixture.hosting.batches[iid] = fixture.hosting.batches[iid]!.copyWith(
          state: 'merged',
          mergeCommitSha: sha,
        );
      };
      fixture.advance(10);

      await fixture.tick();

      expect(fixture.repository.fastForwards, hasLength(1));
      expect(fixture.hosting.closedBatches, isEmpty);
      expect(fixture.hosting.closedMembers, [1]);
      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.queue.state.paused, isNull);
    });

    test('recovers after a crash, target advance, and source update', () async {
      await fixture.publish([member(1)]);

      final sha = fixture.sha;
      fixture.repository.afterFastForward = () async {
        throw StateError('Process stopped after target push');
      };
      fixture.advance(10);

      await expectLater(fixture.tick(), throwsStateError);

      expect(fixture.queue.state.candidate!.phase, 'merging');

      fixture.hosting.branches['main'] = 'subsequent-commit';
      fixture.hosting.members[1] = member(1, sha: 'new-source');
      fixture.landingMode = LandingMode.merge;
      fixture.restart();

      await fixture.tick();

      expect(fixture.hosting.landedShas, contains(sha));
      expect(fixture.repository.fastForwards, hasLength(1));
      expect(fixture.hosting.members[1]!.state, 'opened');
      expect(fixture.hosting.members[1]!.assignees, isEmpty);
      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.repository.assemblies, hasLength(1));
    });

    test('recovers when a batch close response is lost', () async {
      await fixture.publish([member(1)]);

      final batch = fixture.queue.state.batchIid!;
      fixture.hosting.afterClose = (iid) async {
        if (iid == batch) throw const RemoteException('Close response lost');
      };
      fixture.advance(10);

      await expectLater(fixture.tick(), throwsA(isA<RemoteException>()));

      expect(fixture.queue.state.candidate!.phase, 'finalizing');
      expect(fixture.hosting.batches[batch]!.state, 'closed');

      fixture.hosting.afterClose = null;
      fixture.restart();

      await fixture.tick();

      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.hosting.closedMembers, [1]);
      expect(fixture.hosting.closedBatches, [batch]);
      expect(fixture.repository.fastForwards, hasLength(1));
    });

    test(
      'pauses a rejected push and retains intent for reconciliation',
      () async {
        await fixture.publish([member(1)]);

        fixture.repository.failFastForward = const RemoteException(
          'Protected branch rejected',
        );
        fixture.advance(10);

        await fixture.tick();
        await fixture.tick();

        expect(
          fixture.queue.state.paused,
          contains('Protected branch rejected'),
        );
        expect(fixture.queue.state.candidate!.phase, 'merging');
        expect(fixture.hosting.closedMembers, isEmpty);
        expect(fixture.repository.fastForwards, isEmpty);
      },
    );

    test(
      'rebuilds an unlanded candidate when the configured mode changes',
      () async {
        await fixture.publish([member(1)]);

        fixture.landingMode = LandingMode.merge;
        fixture.hosting.settings = testProject;
        fixture.restart();

        await fixture.tick();

        expect(fixture.queue.state.candidate, isNull);

        await fixture.tick();

        expect(fixture.queue.state.candidate!.landingMode, LandingMode.merge);
        expect(fixture.repository.fastForwards, isEmpty);
      },
    );
  });

  test(
    'collects FIFO eligible originals, caps batches, and freezes membership',
    () async {
      fixture = _Fixture.replace(
        fixture,
        collect: const Duration(seconds: 30),
        maxBatch: 2,
      );
      fixture.hosting.members.addAll({
        3: member(3),
        1: member(1),
        2: member(2, draft: true),
        4: member(4, assignees: [10]),
        5: member(5, source: 'merge-queue/another'),
        6: member(6, target: 'release'),
        7: member(7, state: 'closed'),
      });

      await fixture.tick();

      expect(fixture.repository.assemblies, isEmpty);

      fixture.advance(29);
      await fixture.tick();

      expect(fixture.repository.assemblies, isEmpty);

      fixture.advance(1);
      await fixture.tick();

      expect(fixture.repository.assemblies.single.members, [1, 3]);

      fixture.hosting.members[8] = member(8);

      await fixture.tick();

      expect(fixture.queue.state.candidate!.members.map((mr) => mr.iid), [
        1,
        3,
      ]);
      expect(fixture.hosting.descriptions.values.single, contains('source-1'));
      expect(fixture.hosting.descriptions.values.single, contains('source-3'));
    },
  );

  test(
    'merges with no discovered pipelines only after the discovery window',
    () async {
      await fixture.publish([member(1), member(2)]);

      final candidate = fixture.sha;
      final batch = fixture.queue.state.batchIid;

      fixture.advance(9);
      await fixture.tick();

      expect(fixture.hosting.discoveredShas, isEmpty);
      expect(fixture.hosting.mergedShas, isEmpty);

      fixture.advance(1);
      await fixture.tick();

      expect(fixture.hosting.mergedShas, [candidate]);
      expect(fixture.hosting.batches[batch]!.state, 'merged');
      expect(fixture.hosting.closedMembers, [1, 2]);
      expect(
        fixture.hosting.comments.values,
        everyElement(contains('https://gitlab.example.test/batches/$batch')),
      );
      expect(fixture.queue.state.candidate, isNull);
    },
  );

  test('freezes matching pipeline IDs and ignores late pipelines', () async {
    await fixture.publish([member(1)]);

    fixture.hosting.pipelineData.addAll({
      1: Pipeline(1, fixture.sha, 'running'),
      2: const Pipeline(2, 'unrelated-sha', 'failed'),
    });

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.candidate!.pipelineIds, [1]);
    expect(fixture.hosting.mergedShas, isEmpty);

    fixture.hosting.pipelineData[3] = Pipeline(3, fixture.sha, 'failed');
    fixture.hosting.pipelineData[1] = Pipeline(1, fixture.sha, 'success');

    await fixture.tick();

    expect(fixture.hosting.mergedShas, hasLength(1));
    expect(fixture.hosting.discoveredShas, hasLength(1));
    expect(fixture.hosting.pipelineReads, [1, 1]);
  });

  test('waits for every frozen pipeline to finish before landing', () async {
    await fixture.publish([member(1)]);

    final sha = fixture.sha;
    fixture.hosting.pipelineData.addAll({
      1: Pipeline(1, sha, 'success'),
      2: Pipeline(2, sha, 'pending'),
    });

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.hosting.mergedShas, isEmpty);

    fixture.hosting.pipelineData[2] = Pipeline(2, sha, 'success');

    await fixture.tick();

    expect(fixture.hosting.mergedShas, [sha]);
  });

  test(
    'discovers no pipelines immediately with a zero discovery window',
    () async {
      fixture = _Fixture.replace(fixture, discovery: Duration.zero);

      await fixture.publish([member(1)]);
      await fixture.tick();

      expect(fixture.hosting.mergedShas, hasLength(1));
    },
  );

  for (final status in ['canceled', 'skipped']) {
    test(
      '$status pipelines pause without blaming originals; restart rebuilds',
      () async {
        await fixture.publish([member(1), member(2)]);

        final originalSha = fixture.sha;
        final originalBatch = fixture.queue.state.batchIid;
        fixture.hosting.pipelineData[1] = Pipeline(1, originalSha, status);

        fixture.advance(10);
        await fixture.tick();

        expect(fixture.queue.state.paused, contains('canceled or skipped'));
        expect(fixture.queue.state.groups, [
          [1, 2],
        ]);
        expect(fixture.hosting.members[1]!.assignees, [99]);

        final publications = fixture.repository.publications.length;

        await fixture.tick();

        expect(fixture.repository.publications, hasLength(publications));
        expect(fixture.hosting.comments, hasLength(1));

        fixture.restart();
        await fixture.tick();

        expect(fixture.queue.state.paused, isNull);
        expect(fixture.sha, isNot(originalSha));
        expect(fixture.queue.state.batchIid, originalBatch);
        expect(fixture.repository.publications.last.lease, originalSha);
        expect(fixture.queue.state.candidate!.pipelineIds, isNull);
      },
    );
  }

  test(
    'running pipelines time out without splitting or unassignment',
    () async {
      await fixture.publish([member(1), member(2)]);

      fixture.hosting.pipelineData[1] = Pipeline(1, fixture.sha, 'running');

      fixture.advance(10);
      await fixture.tick();

      fixture.advance(50);
      await fixture.tick();

      expect(fixture.queue.state.paused, contains('timeout'));
      expect(fixture.queue.state.groups, [
        [1, 2],
      ]);
      expect(fixture.hosting.members[1]!.assignees, [99]);
      expect(fixture.hosting.mergedShas, isEmpty);
    },
  );

  test('splits failures FIFO, reuses open MRs, preserves merged batch links, and defers arrivals', () async {
    await fixture.publish([member(1), member(2), member(3), member(4)]);

    final initialBatch = fixture.queue.state.batchIid;

    await fixture.finishPipeline('failed');

    expect(fixture.queue.state.groups, [
      [1, 2],
      [3, 4],
    ]);

    fixture.hosting.members[5] = member(5);

    await fixture.tick();

    expect(fixture.repository.assemblies.last.members, [1, 2]);
    expect(fixture.queue.state.batchIid, initialBatch);

    await fixture.finishPipeline('success');

    expect(fixture.hosting.batches[initialBatch]!.state, 'merged');
    expect(fixture.queue.state.groups, [
      [3, 4],
    ]);

    final firstLanded = fixture.hosting.mergedShas.last;

    await fixture.tick();

    expect(fixture.repository.assemblies.last.base, firstLanded);
    expect(fixture.repository.assemblies.last.members, [3, 4]);

    final secondBatch = fixture.queue.state.batchIid;

    expect(secondBatch, isNot(initialBatch));

    await fixture.finishPipeline('failed');

    expect(fixture.queue.state.groups, [
      [3],
      [4],
    ]);

    await fixture.tick();

    expect(fixture.queue.state.batchIid, secondBatch);

    await fixture.finishPipeline('success');

    expect(fixture.hosting.batches[secondBatch]!.state, 'merged');

    await fixture.tick();

    expect(fixture.repository.assemblies.last.members, [4]);

    await fixture.finishPipeline('failed');

    expect(fixture.hosting.members[4]!.assignees, isEmpty);
    expect(fixture.hosting.members[4]!.state, 'opened');
    expect(fixture.hosting.closedMembers, [1, 2, 3]);
    expect(fixture.repository.assemblies.map((a) => a.members), [
      [1, 2, 3, 4],
      [1, 2],
      [3, 4],
      [3],
      [4],
    ]);

    final originalOneComment = fixture.hosting.comments.entries
        .singleWhere((e) => e.key.startsWith('1:landed:'))
        .value;
    final originalThreeComment = fixture.hosting.comments.entries
        .singleWhere((e) => e.key.startsWith('3:landed:'))
        .value;

    expect(originalOneComment, contains('/batches/$initialBatch'));
    expect(originalThreeComment, contains('/batches/$secondBatch'));

    await fixture.tick();

    expect(fixture.repository.assemblies.last.members, [5]);
  });

  test('conflicts restore previously observed assignees and preserve current coassignees', () async {
    fixture.hosting.members[1] = member(1, assignees: [7, 8]);

    await fixture.tick();

    fixture.hosting.members[1] = member(1, assignees: [99, 12]);
    fixture.hosting.members[2] = member(2);
    fixture.repository.conflicts.add(1);

    await fixture.tick();

    expect(fixture.hosting.members[1]!.assignees, [7, 8, 12]);
    expect(fixture.hosting.members[1]!.state, 'opened');
    expect(
      fixture.hosting.comments.values.single,
      contains('shared file conflict'),
    );
    expect(fixture.queue.state.groups, [
      [2],
    ]);

    await fixture.tick();

    expect(fixture.repository.assemblies.single.members, [2]);
    expect(fixture.hosting.mergedShas, isEmpty);
  });

  test(
    'unknown previous assignees removes only the bot after individual failure',
    () async {
      await fixture.publish([
        member(1, assignees: [13, 99]),
      ]);
      await fixture.finishPipeline('failed');

      expect(fixture.hosting.members[1]!.assignees, [13]);
      expect(
        fixture.hosting.comments.values.single,
        contains('failed for this MR alone'),
      );
    },
  );

  test(
    'a source update during rejection reporting retains the new assignment',
    () async {
      fixture.hosting.members[1] = member(1);
      fixture.repository.conflicts.add(1);
      fixture.hosting.afterComment = (iid) async {
        fixture.hosting.members[iid] = fixture.hosting.members[iid]!.copyWith(
          sha: 'new-source-after-conflict',
        );
      };

      await fixture.tick();

      expect(fixture.hosting.members[1]!.sha, 'new-source-after-conflict');
      expect(fixture.hosting.members[1]!.assignees, [99]);
    },
  );

  test(
    'rejection preserves coassignees added while the comment is sent',
    () async {
      fixture.hosting.members[1] = member(1, assignees: [7, 99]);
      fixture.repository.conflicts.add(1);
      fixture.hosting.afterComment = (iid) async {
        fixture.hosting.members[iid] = fixture.hosting.members[iid]!.copyWith(
          assignees: [7, 12, 99],
        );
      };

      await fixture.tick();

      expect(fixture.hosting.members[1]!.assignees, [7, 12]);
    },
  );

  test(
    'target advancement rebuilds using the same MR and a fresh pipeline window',
    () async {
      await fixture.publish([member(1)]);

      final oldSha = fixture.sha;
      final batch = fixture.queue.state.batchIid;
      fixture.hosting.branches['main'] = 'external-base';

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.hosting.mergedShas, isEmpty);

      await fixture.tick();

      expect(fixture.repository.assemblies.last.base, 'external-base');
      expect(fixture.sha, isNot(oldSha));
      expect(fixture.queue.state.batchIid, batch);
      expect(fixture.queue.state.candidate!.pipelineIds, isNull);

      await fixture.tick();

      expect(fixture.hosting.discoveredShas, isEmpty);
    },
  );

  for (final change in ['source', 'draft', 'closed', 'unassigned', 'target']) {
    test(
      '$change changes invalidate an in-flight candidate before landing',
      () async {
        await fixture.publish([member(1), member(2)]);

        final old = fixture.hosting.members[1]!;
        fixture.hosting.members[1] = switch (change) {
          'source' => old.copyWith(sha: 'updated-source'),
          'draft' => old.copyWith(draft: true),
          'closed' => old.copyWith(state: 'closed'),
          'unassigned' => old.copyWith(assignees: [3]),
          _ => old.copyWith(targetBranch: 'release'),
        };

        fixture.advance(10);
        await fixture.tick();

        expect(fixture.queue.state.candidate, isNull);
        expect(fixture.hosting.mergedShas, isEmpty);

        await fixture.tick();

        expect(
          fixture.queue.state.candidate!.members.map((m) => m.iid),
          change == 'source' ? [1, 2] : [2],
        );

        if (change == 'source') {
          expect(
            fixture.queue.state.candidate!.members.first.sha,
            'updated-source',
          );
        }
      },
    );
  }

  test('refuses to overwrite a batch branch changed externally', () async {
    await fixture.publish([member(1)]);

    fixture.repository.branches[fixture.queue.state.branch] = 'human-edit';

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.paused, contains('branch changed'));
    expect(fixture.hosting.mergedShas, isEmpty);
    expect(fixture.repository.publications, hasLength(1));
  });

  test('a discovered pipeline changing SHA pauses the queue', () async {
    await fixture.publish([member(1)]);

    fixture.hosting.pipelineData[1] = Pipeline(1, fixture.sha, 'running');

    fixture.advance(10);
    await fixture.tick();

    fixture.hosting.pipelineData[1] = const Pipeline(
      1,
      'foreign-sha',
      'success',
    );

    await fixture.tick();

    expect(fixture.queue.state.paused, contains('no longer matches'));
    expect(fixture.hosting.mergedShas, isEmpty);
    expect(fixture.hosting.closedMembers, isEmpty);
  });

  for (final branch in ['source', 'target']) {
    test('editing the batch $branch branch pauses before merge', () async {
      await fixture.publish([member(1)]);

      final iid = fixture.queue.state.batchIid!;
      final old = fixture.hosting.batches[iid]!;
      fixture.hosting.batches[iid] = BatchRef(
        iid,
        old.url,
        'opened',
        old.sha,
        sourceBranch: branch == 'source' ? 'other-source' : old.sourceBranch,
        targetBranch: branch == 'target' ? 'other-target' : old.targetBranch,
      );

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.queue.state.paused, isNotNull);
      expect(fixture.hosting.mergedShas, isEmpty);
      expect(fixture.hosting.closedMembers, isEmpty);
    });
  }

  test(
    'an externally merged unexpected commit cannot finalize originals',
    () async {
      await fixture.publish([member(1)]);

      final iid = fixture.queue.state.batchIid!;
      final old = fixture.hosting.batches[iid]!;
      fixture.hosting.batches[iid] = BatchRef(
        iid,
        old.url,
        'merged',
        'unexpected-candidate',
        mergeCommitSha: 'unexpected-candidate',
      );
      fixture.hosting.landedShas.add('unexpected-candidate');

      await fixture.tick();

      expect(
        fixture.queue.state.paused,
        contains('differs from the recorded candidate'),
      );
      expect(fixture.hosting.closedMembers, isEmpty);
      expect(fixture.hosting.members[1]!.state, 'opened');
    },
  );

  test('rebuild timestamps advance even within the same second', () async {
    await fixture.publish([member(1)]);

    final first = fixture.repository.assemblies.single.timestamp;
    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      sha: 'new-source',
    );

    await fixture.tick();
    await fixture.tick();

    final second = fixture.repository.assemblies.last.timestamp;

    expect(second.difference(first), const Duration(seconds: 1));

    fixture.now = fixture.now.subtract(const Duration(minutes: 5));
    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      sha: 'newer-source',
    );

    await fixture.tick();
    await fixture.tick();

    expect(
      fixture.repository.assemblies.last.timestamp.difference(second),
      const Duration(seconds: 1),
    );
  });

  test('revalidates project merge settings before the merge call', () async {
    await fixture.publish([member(1)]);

    fixture.hosting.settings = const Project(
      id: 1,
      path: 'group/repo',
      cloneUrl: '',
      mergeMethod: 'merge',
      squashOption: 'always',
      automaticRebase: false,
    );

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.paused, isNotNull);
    expect(fixture.hosting.mergedShas, isEmpty);
  });

  for (final status in [
    'unchecked',
    'checking',
    'preparing',
    'approvals_syncing',
    'ci_still_running',
  ]) {
    test('$status mergeability waits and retries without rebuilding', () async {
      await fixture.publish([member(1)]);

      final sha = fixture.sha;
      final iid = fixture.queue.state.batchIid!;
      fixture.hosting.setBatchStatus(iid, status);

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.queue.state.paused, isNull);
      expect(fixture.hosting.mergeAttempts, isEmpty);
      expect(fixture.sha, sha);

      fixture.hosting.setBatchStatus(iid, 'mergeable');

      await fixture.tick();

      expect(fixture.hosting.mergedShas, [sha]);
      expect(fixture.repository.assemblies, hasLength(1));
    });
  }

  for (final status in ['need_rebase', 'conflict']) {
    test(
      '$status mergeability rebuilds instead of pausing or splitting',
      () async {
        await fixture.publish([member(1), member(2)]);

        final sha = fixture.sha;
        final iid = fixture.queue.state.batchIid!;
        fixture.hosting.setBatchStatus(iid, status);

        fixture.advance(10);
        await fixture.tick();

        expect(fixture.queue.state.candidate, isNull);
        expect(fixture.queue.state.paused, isNull);
        expect(fixture.queue.state.groups, [
          [1, 2],
        ]);
        expect(fixture.hosting.mergeAttempts, isEmpty);

        fixture.hosting.setBatchStatus(iid, 'mergeable');

        await fixture.tick();

        expect(fixture.queue.state.batchIid, iid);
        expect(fixture.sha, isNot(sha));
        expect(fixture.queue.state.candidate!.pipelineIds, isNull);
        expect(fixture.repository.publications.last.lease, sha);
      },
    );
  }

  for (final status in ['not_approved', 'discussions_not_resolved']) {
    test('$status mergeability pauses without removing originals', () async {
      await fixture.publish([member(1)]);

      fixture.hosting.setBatchStatus(fixture.queue.state.batchIid!, status);

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.queue.state.paused, isNotNull);
      expect(fixture.hosting.mergeAttempts, isEmpty);
      expect(fixture.hosting.members[1]!.assignees, [99]);
    });
  }

  for (final code in [405, 422]) {
    for (final status in ['checking', null]) {
      test(
        '$code followed by $status mergeability waits then retries',
        () async {
          await fixture.publish([member(1)]);

          final sha = fixture.sha;
          final iid = fixture.queue.state.batchIid!;
          fixture.hosting.failNextMerge = RemoteException(
            'Not ready',
            statusCode: code,
          );
          fixture.hosting.beforeMerge = () async {
            fixture.hosting.setBatchStatus(iid, status);
          };

          fixture.advance(10);
          await fixture.tick();

          expect(fixture.queue.state.paused, isNull);
          expect(fixture.hosting.mergedShas, isEmpty);
          expect(fixture.sha, sha);
          expect(fixture.hosting.mergeAttempts, [iid]);

          fixture.hosting.beforeMerge = null;
          fixture.hosting.setBatchStatus(iid, 'mergeable');

          await fixture.tick();

          expect(fixture.hosting.mergedShas, [sha]);
          expect(fixture.hosting.mergeAttempts, [iid, iid]);
          expect(fixture.repository.assemblies, hasLength(1));
        },
      );
    }
  }

  test('a 403 merge refusal pauses instead of retrying indefinitely', () async {
    await fixture.publish([member(1)]);

    fixture.hosting.failNextMerge = const RemoteException(
      'Forbidden',
      statusCode: 403,
    );

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.paused, isNotNull);
    expect(fixture.hosting.mergeAttempts, hasLength(1));
    expect(fixture.hosting.mergedShas, isEmpty);

    await fixture.tick();

    expect(fixture.hosting.mergeAttempts, hasLength(1));
  });

  test('a closed batch pauses until restart then creates a fresh MR', () async {
    await fixture.publish([member(1), member(2)]);

    final sha = fixture.sha;
    final iid = fixture.queue.state.batchIid!;
    fixture.hosting.setBatchStatus(iid, 'not_open', state: 'closed');

    await fixture.tick();

    expect(fixture.queue.state.paused, isNotNull);
    expect(fixture.queue.state.batchIid, iid);

    await fixture.tick();

    expect(fixture.hosting.batches, hasLength(1));

    fixture.restart();
    await fixture.tick();

    expect(fixture.queue.state.paused, isNull);
    expect(fixture.queue.state.batchIid, isNot(iid));
    expect(fixture.sha, isNot(sha));
    expect(fixture.queue.state.groups, [
      [1, 2],
    ]);
    expect(fixture.hosting.batches[iid]!.state, 'closed');
    expect(fixture.repository.publications.last.lease, sha);
  });

  test(
    'restart rebuilds a paused candidate after its branch was deleted',
    () async {
      await fixture.publish([member(1)]);

      final sha = fixture.sha;
      final iid = fixture.queue.state.batchIid!;
      fixture.hosting.pipelineData[1] = Pipeline(1, sha, 'canceled');

      fixture.advance(10);
      await fixture.tick();

      fixture.repository.branches.remove(fixture.queue.state.branch);

      fixture.restart();
      await fixture.tick();

      expect(fixture.queue.state.paused, isNull);
      expect(fixture.queue.state.batchIid, iid);
      expect(fixture.sha, isNot(sha));
      expect(fixture.repository.publications.last.lease, isNull);
    },
  );

  test('a changed live source ref leaves an original open while the MR API lags', () async {
    fixture.hosting.members[1] = member(1, assignees: [7]);

    await fixture.tick();

    fixture.hosting.members[1] = member(1, assignees: [12, 99]);

    await fixture.tick();

    fixture.hosting.beforeMerge = () async {
      fixture.repository.sourceShas[1] = 'undelivered-live-source';
    };

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.hosting.members[1]!.sha, 'source-1');
    expect(fixture.hosting.members[1]!.state, 'opened');
    expect(fixture.hosting.closedMembers, isEmpty);
    expect(fixture.hosting.members[1]!.assignees, [7, 12]);
    expect(fixture.hosting.mergedShas, hasLength(1));
    expect(
      fixture.hosting.comments.values.any(
        (text) => text.contains('source no longer matches delivered version'),
      ),
      isTrue,
    );

    // The bot performed the unassignment itself, so it must recognize immediate
    // reassignment even without a poll observing the unassigned interval.
    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      sha: 'undelivered-live-source',
      assignees: [7, 12, 99],
    );

    await fixture.tick();

    expect(
      fixture.queue.state.candidate!.members.single.sha,
      'undelivered-live-source',
    );
  });

  test('a changed live source invalidates an in-flight candidate while API metadata lags', () async {
    await fixture.publish([member(1)]);

    fixture.repository.sourceShas[1] = 'new-live-source';

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.candidate, isNull);
    expect(fixture.hosting.mergedShas, isEmpty);

    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      sha: 'new-live-source',
    );

    await fixture.tick();

    expect(
      fixture.queue.state.candidate!.members.single.sha,
      'new-live-source',
    );
    expect(fixture.repository.assemblies, hasLength(2));
  });

  test(
    'an initially missing source branch is rejected without publishing',
    () async {
      fixture.hosting.members[1] = member(1, assignees: [12, 99]);
      fixture.repository.sourceShas[1] = null;

      await fixture.tick();

      expect(fixture.queue.state.candidate, isNull);
      expect(fixture.queue.state.groups, isEmpty);
      expect(fixture.hosting.members[1]!.assignees, [12]);
      expect(fixture.hosting.members[1]!.state, 'opened');
      expect(fixture.repository.assemblies, isEmpty);
      expect(fixture.repository.publications, isEmpty);
      expect(fixture.hosting.batches, isEmpty);
      expect(
        fixture.hosting.comments.values.single,
        contains('Source branch is missing'),
      );

      await fixture.tick();

      expect(fixture.repository.publications, isEmpty);
    },
  );

  test('a deleted source branch invalidates an observing batch and cannot republish', () async {
    await fixture.publish([
      member(1, assignees: [12, 99]),
    ]);

    fixture.repository.sourceShas[1] = null;

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.queue.state.candidate, isNull);

    await fixture.tick();

    expect(fixture.hosting.members[1]!.assignees, [12]);
    expect(fixture.queue.state.groups, isEmpty);
    expect(fixture.queue.state.rejections, isEmpty);
    expect(
      fixture.hosting.comments.values.single,
      contains('Source branch is missing'),
    );

    for (var i = 0; i < 3; i++) {
      await fixture.tick();
    }

    expect(fixture.repository.assemblies, hasLength(1));
    expect(fixture.repository.publications, hasLength(1));
    expect(fixture.hosting.mergedShas, isEmpty);
    expect(fixture.hosting.closedMembers, isEmpty);
  });

  test(
    'a live source ref changing during close reopens despite stale API SHA',
    () async {
      await fixture.publish([member(1)]);

      fixture.hosting.afterClose = (iid) async {
        fixture.repository.sourceShas[iid] = 'new-live-source';
      };

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.hosting.members[1]!.sha, 'source-1');
      expect(fixture.hosting.members[1]!.state, 'opened');
      expect(fixture.hosting.reopenedMembers, [1]);
      expect(fixture.hosting.members[1]!.assignees, isEmpty);
      expect(
        fixture.hosting.comments.values.any(
          (text) => text.contains('source no longer matches delivered version'),
        ),
        isTrue,
      );
    },
  );

  test('an updated original made draft still restores assignees after landing', () async {
    fixture.hosting.members[1] = member(1, assignees: [7]);

    await fixture.tick();

    fixture.hosting.members[1] = member(1, assignees: [12, 99]);

    await fixture.tick();

    fixture.hosting.afterClose = (iid) async {
      fixture.hosting.members[iid] = fixture.hosting.members[iid]!.copyWith(
        sha: 'remaining-draft-source',
        draft: true,
      );
    };

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.hosting.members[1]!.state, 'opened');
    expect(fixture.hosting.members[1]!.draft, isTrue);
    expect(fixture.hosting.members[1]!.assignees, [7, 12]);
    expect(fixture.hosting.reopenedMembers, [1]);
    expect(fixture.queue.state.rejections, isEmpty);

    // Becoming ready and immediately reassigning must be enough to queue the
    // remaining version, with no poll required between removal and assignment.
    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      draft: false,
      assignees: [7, 12, 99],
    );

    await fixture.tick();

    expect(
      fixture.queue.state.candidate!.members.single.sha,
      'remaining-draft-source',
    );
  });

  test('updated-original assignee restoration survives a lost write response and restart', () async {
    fixture.hosting.members[1] = member(1, assignees: [7]);

    await fixture.tick();

    fixture.hosting.members[1] = member(1, assignees: [12, 99]);

    await fixture.tick();

    fixture.hosting.afterClose = (iid) async {
      fixture.hosting.members[iid] = fixture.hosting.members[iid]!.copyWith(
        sha: 'remaining-source',
      );
    };
    fixture.hosting.failAssigneesAfterWrite = true;

    fixture.advance(10);

    await expectLater(fixture.tick(), throwsA(isA<RemoteException>()));
    expect(fixture.hosting.members[1]!.state, 'opened');
    expect(fixture.hosting.members[1]!.assignees, [7, 12]);
    expect(fixture.queue.state.rejections.single.deliveredUpdate, isTrue);

    final comments = fixture.hosting.comments.length;

    fixture.restart();
    await fixture.tick();

    expect(fixture.queue.state.rejections, isEmpty);
    expect(fixture.hosting.comments, hasLength(comments));
    expect(fixture.hosting.mergedShas, hasLength(1));

    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      assignees: [7, 12, 99],
    );

    await fixture.tick();

    expect(
      fixture.queue.state.candidate!.members.single.sha,
      'remaining-source',
    );
  });

  test(
    'reconciles a lost merge response without repeating the merge',
    () async {
      await fixture.publish([member(1)]);

      fixture.hosting.failMergeAfterLanding = true;

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.hosting.mergedShas, hasLength(1));
      expect(fixture.hosting.closedMembers, [1]);
      expect(fixture.queue.state.candidate, isNull);

      fixture.restart();
      await fixture.tick();

      expect(fixture.hosting.mergedShas, hasLength(1));
    },
  );

  test(
    'restarts after a lost push response without rebuilding or repushing',
    () async {
      fixture.hosting.members[1] = member(1);
      fixture.repository.failPublishAfterPush = true;

      await expectLater(fixture.tick(), throwsA(isA<RemoteException>()));
      expect(fixture.queue.state.candidate!.phase, 'publishing');

      final sha = fixture.sha;

      fixture.restart();
      await fixture.tick();

      expect(fixture.repository.assemblies, hasLength(1));
      expect(fixture.repository.publications, hasLength(1));
      expect(fixture.sha, sha);
      expect(fixture.queue.state.candidate!.phase, 'observing');
    },
  );

  test(
    'recovers MR creation after a lost response by reusing the existing MR',
    () async {
      fixture.hosting.members[1] = member(1);
      fixture.hosting.failEnsureAfterCreate = true;

      await expectLater(fixture.tick(), throwsA(isA<RemoteException>()));
      expect(fixture.hosting.batches, hasLength(1));

      fixture.restart();
      await fixture.tick();

      expect(fixture.hosting.batches, hasLength(1));
      expect(fixture.repository.publications, hasLength(1));
      expect(fixture.queue.state.batchIid, fixture.hosting.batches.keys.single);
    },
  );

  test(
    'restarts finalization without duplicating comments or merge calls',
    () async {
      await fixture.publish([member(1), member(2)]);

      fixture.hosting.failCommentAfterWrite = true;

      fixture.advance(10);

      await expectLater(fixture.tick(), throwsA(isA<RemoteException>()));
      expect(fixture.queue.state.candidate!.phase, 'finalizing');

      fixture.restart();
      await fixture.tick();

      expect(fixture.hosting.mergedShas, hasLength(1));
      expect(fixture.hosting.comments, hasLength(2));
      expect(fixture.hosting.closedMembers, [1, 2]);
      expect(fixture.queue.state.candidate, isNull);
    },
  );

  test('new source commits during close reopen the original and require reassignment', () async {
    await fixture.publish([member(1)]);

    fixture.hosting.afterClose = (iid) async {
      fixture.hosting.members[iid] = fixture.hosting.members[iid]!.copyWith(
        sha: 'undelivered-source',
      );
    };

    fixture.advance(10);
    await fixture.tick();

    expect(fixture.hosting.members[1]!.state, 'opened');
    expect(fixture.hosting.reopenedMembers, [1]);
    expect(fixture.hosting.members[1]!.assignees, isEmpty);
    expect(
      fixture.hosting.comments.values.any(
        (text) => text.contains('source no longer matches delivered version'),
      ),
      isTrue,
    );

    await fixture.tick();

    expect(fixture.queue.state.candidate, isNull);
    expect(fixture.repository.assemblies, hasLength(1));

    fixture.hosting.members[1] = fixture.hosting.members[1]!.copyWith(
      assignees: [99],
    );

    await fixture.tick();

    expect(fixture.repository.assemblies, hasLength(2));
    expect(
      fixture.queue.state.candidate!.members.single.sha,
      'undelivered-source',
    );
  });

  test(
    'restart preserves a frozen discovery list and recovery group order',
    () async {
      await fixture.publish([member(1), member(2), member(3)]);
      await fixture.finishPipeline('failed');
      fixture.restart();

      expect(fixture.queue.state.groups, [
        [1, 2],
        [3],
      ]);

      await fixture.tick();

      fixture.hosting.pipelineData[2] = Pipeline(2, fixture.sha, 'running');

      fixture.advance(10);
      await fixture.tick();

      expect(fixture.queue.state.candidate!.pipelineIds, [2]);

      final sha = fixture.sha;

      fixture.restart();

      fixture.hosting.pipelineData[3] = Pipeline(3, sha, 'failed');
      fixture.hosting.pipelineData[2] = Pipeline(2, sha, 'success');

      await fixture.tick();

      expect(fixture.hosting.mergedShas, [sha]);
      expect(fixture.queue.state.groups, [
        [3],
      ]);
    },
  );
}

class _Fixture({
  final Duration collect = Duration.zero,
  final Duration discovery = const Duration(seconds: 10),
  final int maxBatch = 10,
  var LandingMode landingMode = LandingMode.merge,
}) {
  final Store store = Store(':memory:');
  final FakeHosting hosting = FakeHosting();
  late final FakeRepository repository = FakeRepository(hosting);
  DateTime now = DateTime.utc(2026, 10, 15, 12);
  late MergeQueue queue;

  this {
    restart();
  }

  static _Fixture replace(
    _Fixture old, {
    Duration? collect,
    Duration? discovery,
    int? maxBatch,
    LandingMode? landingMode,
  }) {
    old.store.close();

    return _Fixture(
      collect: collect ?? old.collect,
      discovery: discovery ?? old.discovery,
      maxBatch: maxBatch ?? old.maxBatch,
      landingMode: landingMode ?? old.landingMode,
    );
  }

  void restart() {
    queue = MergeQueue(
      hosting: hosting,
      repository: repository,
      store: store,
      config: BotConfig(
        gitlab: GitLabConfig(url: Uri.parse('https://gitlab.example.test')),
        storage: const StorageConfig(
          database: ':memory:',
          workDirectory: '/tmp/codex/queue-test',
        ),
        queue: QueueConfig(collectWindow: collect, maxBatchSize: maxBatch),
        pipelines: PipelineConfig(
          discoveryWindow: discovery,
          timeout: const Duration(seconds: 60),
        ),
        projects: const [
          ProjectConfig('1', ['main']),
        ],
      ),
      project: testProject,
      target: 'main',
      bot: testBot,
      landingMode: landingMode,
      clock: () => now,
      log: (_) {},
    );
  }

  String get sha => queue.state.candidate!.sha!;
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
  Future<void> tick() => queue.tick();

  Future<void> publish(List<MergeRequest> members) async {
    hosting.members.addEntries(members.map((mr) => MapEntry(mr.iid, mr)));

    await tick();

    if (collect != Duration.zero) {
      now = now.add(collect);
      await tick();
    }

    expect(queue.state.candidate!.phase, 'observing');
  }

  Future<void> finishPipeline(String status) async {
    final id = hosting.pipelineData.length + 1;
    hosting.pipelineData[id] = Pipeline(id, sha, status);
    now = now.add(discovery);

    await tick();
  }
}
