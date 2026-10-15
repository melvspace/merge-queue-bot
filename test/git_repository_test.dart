import 'dart:io';

import 'package:merge_queue_bot/src/git_repository.dart';
import 'package:merge_queue_bot/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.create());
  tearDown(() async => fixture.root.delete(recursive: true));

  test(
    'squashes each MR, preserves metadata, and persists publishable candidates',
    () async {
      final first = await fixture.mr(1, [
        {'one.txt': 'first change\n'},
        {'one.txt': 'second change\n'},
      ]);
      final second = await fixture.mr(2, [
        {'two.txt': 'independent change\n'},
      ]);
      final repository = fixture.repository();
      final sha = await repository.assemble(
        fixture.project,
        'main',
        fixture.base,
        [first, second],
        fixture.timestamp,
      );
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        sha,
        null,
      );
      await fixture.git([
        'fetch',
        '--quiet',
        'origin',
        'refs/heads/merge-queue/main',
      ]);
      expect(
        await fixture.git(['rev-list', '--count', '${fixture.base}..$sha']),
        '2',
      );
      expect(await fixture.git(['show', '$sha:one.txt']), 'second change');
      expect(await fixture.git(['show', '$sha:two.txt']), 'independent change');
      expect(
        await fixture.git([
          'log',
          '-1',
          '--format=%an <%ae>|%cn <%ce>|%s|%b',
          '$sha~',
        ]),
        'Author 1 <author1@example.test>|Queue Bot <bot@example.test>|Change 1|'
        'https://gitlab.example.test/group/repo/-/merge_requests/1',
      );
      expect(
        await repository.remoteBranch(fixture.project, first.sourceBranch),
        first.sha,
      );
      expect(
        await repository.remoteBranch(fixture.project, second.sourceBranch),
        second.sha,
      );
      expect(await repository.contains(fixture.project, 'main', sha), isFalse);

      // A fresh adapter can publish the persisted candidate without rebuilding.
      await fixture.repository().publish(
        fixture.project,
        'main',
        'merge-queue/recovered',
        sha,
        null,
      );
      expect(
        await repository.remoteBranch(fixture.project, 'merge-queue/recovered'),
        sha,
      );
      await fixture.git(['push', '--quiet', 'origin', '$sha:refs/heads/main']);
      expect(await repository.contains(fixture.project, 'main', sha), isTrue);
      expect(
        await repository.remoteBranch(fixture.project, first.sourceBranch),
        first.sha,
      );
    },
  );

  test(
    'reports the conflicting MR and can rebuild after the conflict',
    () async {
      final first = await fixture.mr(1, [
        {'shared.txt': 'first\n'},
      ]);
      final second = await fixture.mr(2, [
        {'shared.txt': 'second\n'},
      ]);
      final repository = fixture.repository();
      await expectLater(
        repository.assemble(fixture.project, 'main', fixture.base, [
          first,
          second,
        ], fixture.timestamp),
        throwsA(isA<AssemblyConflict>().having((error) => error.iid, 'iid', 2)),
      );
      final sha = await repository.assemble(
        fixture.project,
        'main',
        fixture.base,
        [first],
        fixture.timestamp,
      );
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        sha,
        null,
      );
      expect(
        await repository.remoteBranch(fixture.project, 'main'),
        fixture.base,
      );
      expect(
        await repository.remoteBranch(fixture.project, second.sourceBranch),
        second.sha,
      );
    },
  );

  test(
    'rejects already-applied changes and strips CI skip title markers',
    () async {
      final member = await fixture.mr(1, [
        {'one.txt': 'one\n'},
      ], title: '[SKIP CI] Change [ci skip] 1');
      final repository = fixture.repository();
      final sha = await repository.assemble(
        fixture.project,
        'main',
        fixture.base,
        [member],
        fixture.timestamp,
      );
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        sha,
        null,
      );
      await fixture.git([
        'fetch',
        '--quiet',
        'origin',
        'refs/heads/merge-queue/main',
      ]);
      final message = await fixture.git(['log', '-1', '--format=%B', sha]);
      expect(message.toLowerCase(), isNot(contains('[skip ci]')));
      expect(message.toLowerCase(), isNot(contains('[ci skip]')));
      expect(message, startsWith('Change  1'));
      await fixture.git(['push', '--quiet', 'origin', '$sha:refs/heads/main']);
      await expectLater(
        repository.assemble(fixture.project, 'main', sha, [
          member,
        ], fixture.timestamp),
        throwsA(
          isA<AssemblyConflict>().having(
            (error) => error.detail,
            'detail',
            'no changes relative to target',
          ),
        ),
      );
    },
  );

  test(
    'resubmitted sources squash only remaining changes or fail on overlap',
    () async {
      final member = await fixture.mr(1, [
        {'one.txt': 'one\n'},
      ]);
      final repository = fixture.repository();
      final first = await repository.assemble(
        fixture.project,
        'main',
        fixture.base,
        [member],
        fixture.timestamp,
      );
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        first,
        null,
      );
      await fixture.git([
        'fetch',
        '--quiet',
        'origin',
        'refs/heads/merge-queue/main',
      ]);
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        '$first:refs/heads/main',
      ]);

      await fixture.write('two.txt', 'remaining change\n');
      await fixture.git(['add', '.']);
      await fixture.git([
        'commit',
        '--quiet',
        '-m',
        'Additional source change',
      ]);
      final updated = MergeRequest.fromJson({
        ...member.toJson(),
        'sha': await fixture.git(['rev-parse', 'HEAD']),
      });
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        'HEAD:refs/heads/source-1',
        'HEAD:refs/merge-requests/1/head',
      ]);
      final second = await repository.assemble(fixture.project, 'main', first, [
        updated,
      ], fixture.timestamp);
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        second,
        first,
      );
      await fixture.git([
        'fetch',
        '--quiet',
        'origin',
        'refs/heads/merge-queue/main',
      ]);
      expect(
        await fixture.git(['diff', '--name-only', first, second]),
        'two.txt',
      );
      expect(await fixture.git(['show', '$second:one.txt']), 'one');
      expect(
        await fixture.git(['show', '$second:two.txt']),
        'remaining change',
      );
      expect(
        await fixture.git(['rev-list', '--count', '$first..$second']),
        '1',
      );
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        '$second:refs/heads/main',
      ]);

      // Git cannot safely infer incremental edits to an originally added file
      // after its original ancestry was replaced by a squash commit.
      await fixture.write('one.txt', 'one\nchanged after squash\n');
      await fixture.git([
        'commit',
        '--quiet',
        '-am',
        'Overlapping source update',
      ]);
      final overlapping = MergeRequest.fromJson({
        ...member.toJson(),
        'sha': await fixture.git(['rev-parse', 'HEAD']),
      });
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        'HEAD:refs/heads/source-1',
        'HEAD:refs/merge-requests/1/head',
      ]);
      await expectLater(
        repository.assemble(fixture.project, 'main', second, [
          overlapping,
        ], fixture.timestamp),
        throwsA(isA<AssemblyConflict>()),
      );
      expect(await repository.remoteBranch(fixture.project, 'main'), second);
      expect(
        await repository.remoteBranch(fixture.project, 'source-1'),
        overlapping.sha,
      );
    },
  );

  test(
    'distinguishes stale MR heads and stale base from merge conflicts',
    () async {
      final member = await fixture.mr(1, [
        {'one.txt': 'one\n'},
      ]);
      await fixture.write('one.txt', 'updated\n');
      await fixture.git(['commit', '--quiet', '-am', 'Updated source']);
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        'HEAD:refs/merge-requests/1/head',
      ]);
      final repository = fixture.repository();
      await expectLater(
        repository.assemble(fixture.project, 'main', fixture.base, [
          member,
        ], fixture.timestamp),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.message,
            'message',
            contains('MR !1 changed'),
          ),
        ),
      );
      await fixture.git(['push', '--quiet', 'origin', 'HEAD:refs/heads/main']);
      await expectLater(
        repository.assemble(
          fixture.project,
          'main',
          fixture.base,
          [],
          fixture.timestamp,
        ),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.message,
            'message',
            contains('Target changed'),
          ),
        ),
      );
    },
  );

  test('uses exact leases for branch creation and replacement', () async {
    final first = await fixture.mr(1, [
      {'one.txt': 'one\n'},
    ]);
    final second = await fixture.mr(2, [
      {'two.txt': 'two\n'},
    ]);
    final repository = fixture.repository();
    final firstSha = await repository.assemble(
      fixture.project,
      'main',
      fixture.base,
      [first],
      fixture.timestamp,
    );
    final secondSha = await repository.assemble(
      fixture.project,
      'main',
      fixture.base,
      [second],
      fixture.timestamp,
    );
    await repository.publish(
      fixture.project,
      'main',
      'merge-queue/main',
      firstSha,
      null,
    );
    await expectLater(
      repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        secondSha,
        null,
      ),
      throwsA(isA<RemoteException>()),
    );
    expect(
      await repository.remoteBranch(fixture.project, 'merge-queue/main'),
      firstSha,
    );
    await repository.publish(
      fixture.project,
      'main',
      'merge-queue/main',
      secondSha,
      firstSha,
    );
    await expectLater(
      repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        firstSha,
        firstSha,
      ),
      throwsA(isA<RemoteException>()),
    );
    expect(
      await repository.remoteBranch(fixture.project, 'merge-queue/main'),
      secondSha,
    );
    await expectLater(
      repository.publish(
        fixture.project,
        'main',
        'main',
        firstSha,
        fixture.base,
      ),
      throwsArgumentError,
    );
    expect(
      await repository.remoteBranch(fixture.project, 'main'),
      fixture.base,
    );
  });

  test(
    'isolates concurrent target checkouts and their candidate references',
    () async {
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        'main:refs/heads/release',
      ]);
      await fixture.git(['branch', 'release', 'main']);
      final mainMember = await fixture.mr(1, [
        {'main.txt': 'main\n'},
      ]);
      final releaseMember = await fixture.mr(2, [
        {'release.txt': 'release\n'},
      ], target: 'release');
      final repository = fixture.repository();
      final candidates = await Future.wait([
        repository.assemble(fixture.project, 'main', fixture.base, [
          mainMember,
        ], fixture.timestamp),
        repository.assemble(fixture.project, 'release', fixture.base, [
          releaseMember,
        ], fixture.timestamp),
      ]);
      await repository.publish(
        fixture.project,
        'main',
        'merge-queue/main',
        candidates[0],
        null,
      );
      await repository.publish(
        fixture.project,
        'release',
        'merge-queue/release',
        candidates[1],
        null,
      );
      await expectLater(
        repository.publish(
          fixture.project,
          'main',
          'merge-queue/wrong',
          candidates[1],
          null,
        ),
        throwsA(isA<RemoteException>()),
      );
      expect(
        await repository.remoteBranch(fixture.project, 'merge-queue/main'),
        candidates[0],
      );
      expect(
        await repository.remoteBranch(fixture.project, 'merge-queue/release'),
        candidates[1],
      );
    },
  );

  test(
    'rejects credential-bearing and foreign clone URLs and unsafe refs',
    () async {
      final repository = fixture.repository();
      for (final url in [
        'https://other.example.test/repo.git',
        'https://oauth2:secret@gitlab.example.test/repo.git',
        'ssh://git@gitlab.example.test/repo.git',
        'https://gitlab.example.test/repo.git?secret=1',
      ]) {
        await expectLater(
          repository.remoteBranch(fixture.withUrl(url), 'main'),
          throwsArgumentError,
        );
      }
      await expectLater(
        repository.remoteBranch(fixture.project, '../main'),
        throwsArgumentError,
      );
      await expectLater(
        repository.remoteBranch(fixture.project, '-main'),
        throwsArgumentError,
      );
    },
  );

  test(
    'reads the live same-project source branch ahead of stale MR metadata',
    () async {
      final member = await fixture.mr(1, [
        {'one.txt': 'one\n'},
      ]);
      await fixture.write('one.txt', 'one\ntwo\n');
      await fixture.git(['commit', '--quiet', '-am', 'New source commit']);
      final latest = await fixture.git(['rev-parse', 'HEAD']);
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        'HEAD:refs/heads/source-1',
      ]);
      final repository = fixture.repository();
      expect(await repository.sourceSha(fixture.project, member), latest);
      expect(latest, isNot(member.sha));
      await fixture.git(['push', '--quiet', 'origin', ':refs/heads/source-1']);
      expect(await repository.sourceSha(fixture.project, member), isNull);
    },
  );

  test(
    'reads fork or unknown source projects through their target-project MR ref',
    () async {
      final fork = await fixture.mr(1, [
        {'fork.txt': 'fork\n'},
      ], sourceProjectId: 2);
      final unknown = await fixture.mr(2, [
        {'unknown.txt': 'unknown\n'},
      ], sourceProjectId: null);
      final repository = fixture.repository();
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        ':refs/heads/source-1',
        ':refs/heads/source-2',
      ]);
      expect(await repository.sourceSha(fixture.project, fork), fork.sha);
      expect(await repository.sourceSha(fixture.project, unknown), unknown.sha);
      await fixture.git([
        'push',
        '--quiet',
        'origin',
        ':refs/merge-requests/1/head',
      ]);
      expect(await repository.sourceSha(fixture.project, fork), isNull);
    },
  );
}

class _Fixture {
  final Directory root;
  final String seed;
  final String bare;
  late final String base;
  final timestamp = DateTime.utc(2026, 10, 15, 12);
  _Fixture(this.root)
    : seed = p.join(root.path, 'seed'),
      bare = p.join(root.path, 'remote.git');

  static Future<_Fixture> create() async {
    final temporary = await Directory('/tmp/codex').create(recursive: true);
    final fixture = _Fixture(
      await temporary.createTemp('git-repository-test-'),
    );
    await Directory(fixture.seed).create();
    await fixture.git(['init', '--quiet', '--bare', fixture.bare]);
    await fixture.git(['init', '--quiet', '--initial-branch=main']);
    await fixture.git(['config', 'user.name', 'Test Author']);
    await fixture.git(['config', 'user.email', 'test@example.test']);
    await fixture.git(['config', 'commit.gpgsign', 'false']);
    await fixture.write('shared.txt', 'base\n');
    await fixture.git(['add', '.']);
    await fixture.git(['commit', '--quiet', '-m', 'Base']);
    fixture.base = await fixture.git(['rev-parse', 'HEAD']);
    await fixture.git(['remote', 'add', 'origin', fixture.bare]);
    await fixture.git(['push', '--quiet', 'origin', 'main']);
    return fixture;
  }

  Project get project => withUrl(Uri.directory(bare).toString());

  Project withUrl(String url) => Project(
    id: 1,
    path: 'group/repo',
    cloneUrl: url,
    mergeMethod: 'ff',
    squashOption: 'default_off',
    automaticRebase: false,
  );

  GitRepository repository() => GitRepository(
    workDirectory: p.join(root.path, 'checkouts'),
    token: 'secret-test-token',
    bot: const BotUser(99, 'Queue Bot', 'bot@example.test'),
    gitlabUrl: Uri.parse('https://gitlab.example.test'),
    allowFileRemotes: true,
  );

  Future<MergeRequest> mr(
    int iid,
    List<Map<String, String>> commits, {
    String target = 'main',
    String? title,
    int? sourceProjectId = 1,
  }) async {
    await git(['checkout', '--quiet', '-b', 'source-$iid', target]);
    for (final changes in commits) {
      for (final entry in changes.entries) {
        await write(entry.key, entry.value);
      }
      await git(['add', '.']);
      await git(['commit', '--quiet', '-m', 'Source commit']);
    }
    final sha = await git(['rev-parse', 'HEAD']);
    await git([
      'push',
      '--quiet',
      'origin',
      'HEAD:refs/heads/source-$iid',
      'HEAD:refs/merge-requests/$iid/head',
    ]);
    return MergeRequest(
      iid: iid,
      title: title ?? 'Change $iid',
      url: 'https://gitlab.example.test/group/repo/-/merge_requests/$iid',
      sha: sha,
      targetBranch: target,
      sourceBranch: 'source-$iid',
      sourceProjectId: sourceProjectId,
      state: 'opened',
      draft: false,
      assignees: [99],
      authorName: 'Author $iid',
      authorEmail: 'author$iid@example.test',
      createdAt: timestamp,
    );
  }

  Future<void> write(String name, String text) async {
    final file = File(p.join(seed, name));
    await file.parent.create(recursive: true);
    await file.writeAsString(text);
  }

  Future<String> git(List<String> arguments) async {
    final result = await Process.run(
      'git',
      arguments,
      workingDirectory: seed,
      environment: {
        'GIT_CONFIG_NOSYSTEM': '1',
        'GIT_CONFIG_GLOBAL': '/dev/null',
      },
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')}: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }
}
