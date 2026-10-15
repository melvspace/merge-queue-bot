import 'dart:io';

import 'package:merge_queue_bot/src/config.dart';
import 'package:test/test.dart';

const minimal = '''
gitlab_url: https://gitlab.example.test
projects:
  - id: group/project
    target_branches: [main]
''';

void main() {
  test('uses the agreed operational defaults', () {
    final config = BotConfig.parse(minimal);
    expect(config.gitlabUrl, Uri.parse('https://gitlab.example.test'));
    expect(config.database, 'data/queue.sqlite');
    expect(config.workDirectory, 'data/repositories');
    expect(config.tokenEnvironment, 'GITLAB_TOKEN');
    expect(config.tokenFile, isNull);
    expect(config.pollInterval, const Duration(seconds: 30));
    expect(config.collectWindow, const Duration(seconds: 30));
    expect(config.discoveryWindow, const Duration(seconds: 10));
    expect(config.pipelineTimeout, const Duration(minutes: 60));
    expect(config.maxBatchSize, 10);
    expect(config.projects.single.id, 'group/project');
    expect(config.projects.single.targets, ['main']);
  });

  test(
    'accepts custom settings, integer project IDs, and multiple targets',
    () {
      final config = BotConfig.parse('''
gitlab_url: https://gitlab.example.test/gitlab
database: /data/state.sqlite
work_directory: /data/clones
token_env: QUEUE_GITLAB_TOKEN
token_file: /run/secrets/token
poll_interval_seconds: 3
collect_window_seconds: 0
pipeline_discovery_seconds: 0
pipeline_timeout_seconds: 900
max_batch_size: 4
projects:
  - id: 123
    target_branches: [main, release/1]
  - id: another/project
    target_branches: [main]
''');
      expect(config.gitlabUrl.path, '/gitlab');
      expect(config.database, '/data/state.sqlite');
      expect(config.workDirectory, '/data/clones');
      expect(config.tokenEnvironment, 'QUEUE_GITLAB_TOKEN');
      expect(config.tokenFile, '/run/secrets/token');
      expect(config.pollInterval, const Duration(seconds: 3));
      expect(config.collectWindow, Duration.zero);
      expect(config.discoveryWindow, Duration.zero);
      expect(config.pipelineTimeout, const Duration(seconds: 900));
      expect(config.maxBatchSize, 4);
      expect(config.projects.map((project) => project.id), [
        '123',
        'another/project',
      ]);
      expect(config.projects.first.targets, ['main', 'release/1']);
      expect(
        () => config.projects.first.targets.add('other'),
        throwsUnsupportedError,
      );
    },
  );

  for (final source in ['', '[]', 'plain text', 'true']) {
    test('rejects a configuration that is not a YAML map: $source', () {
      expect(() => BotConfig.parse(source), throwsFormatException);
    });
  }

  test('rejects unknown top-level options', () {
    expect(
      () => BotConfig.parse('${minimal}pipeline_discovery_second: 20\n'),
      throwsFormatException,
    );
  });

  for (final url in [
    'gitlab.example.test',
    'ftp://gitlab.example.test',
    'https:///missing-host',
    'https://bot:token@gitlab.example.test',
    'https://gitlab.example.test?token=secret',
    'https://gitlab.example.test#fragment',
  ]) {
    test('rejects invalid instance URL $url', () {
      expect(
        () => BotConfig.parse(
          minimal.replaceFirst('https://gitlab.example.test', url),
        ),
        throwsFormatException,
      );
    });
  }

  for (final key in ['database', 'work_directory', 'token_env', 'token_file']) {
    for (final value in ["''", "'   '", '123']) {
      test('rejects invalid $key value $value', () {
        expect(
          () => BotConfig.parse('$minimal$key: $value\n'),
          throwsFormatException,
        );
      });
    }
  }

  for (final key in [
    'poll_interval_seconds',
    'collect_window_seconds',
    'pipeline_discovery_seconds',
    'pipeline_timeout_seconds',
    'max_batch_size',
  ]) {
    for (final value in ['-1', '1.5', "'10'", 'true']) {
      test('rejects invalid $key value $value', () {
        expect(
          () => BotConfig.parse('$minimal$key: $value\n'),
          throwsFormatException,
        );
      });
    }
  }

  for (final key in [
    'poll_interval_seconds',
    'pipeline_timeout_seconds',
    'max_batch_size',
  ]) {
    test('rejects zero $key', () {
      expect(() => BotConfig.parse('$minimal$key: 0\n'), throwsFormatException);
    });
  }

  for (final timeout in [9, 10]) {
    test('requires pipeline timeout $timeout to exceed discovery window', () {
      expect(
        () => BotConfig.parse('${minimal}pipeline_timeout_seconds: $timeout\n'),
        throwsFormatException,
      );
    });
  }

  for (final projects in [
    '[]',
    '{}',
    '[123]',
    '[{id: project}]',
    '[{target_branches: [main]}]',
    '[{id: project, target_branches: []}]',
    '[{id: project, target_branches: main}]',
    '[{id: true, target_branches: [main]}]',
    "[{id: '', target_branches: [main]}]",
    '[{id: project, target_branches: [main], unknown: true}]',
    "[{id: project, target_branches: ['']}]",
    '[{id: project, target_branches: [123]}]',
    '[{id: project, target_branches: [-main]}]',
    '[{id: project, target_branches: [merge-queue/main]}]',
    '[{id: project, target_branches: [main, main]}]',
    '[{id: project, target_branches: [main]}, {id: project, target_branches: [main]}]',
  ]) {
    test('rejects invalid project configuration $projects', () {
      expect(
        () => BotConfig.parse(
          'gitlab_url: https://gitlab.example.test\nprojects: $projects\n',
        ),
        throwsFormatException,
      );
    });
  }

  test('requires GitLab URL and at least one project', () {
    expect(
      () =>
          BotConfig.parse('projects: [{id: project, target_branches: [main]}]'),
      throwsFormatException,
    );
    expect(
      () => BotConfig.parse('gitlab_url: https://gitlab.example.test'),
      throwsFormatException,
    );
  });

  group('token loading', () {
    late Directory temporary;

    setUp(() {
      Directory('/tmp/codex').createSync(recursive: true);
      temporary = Directory('/tmp/codex').createTempSync('queue-config-test-');
    });
    tearDown(() => temporary.deleteSync(recursive: true));

    test('reads and trims only the configured environment variable', () {
      final config = BotConfig.parse('${minimal}token_env: QUEUE_TOKEN\n');
      expect(
        config.readToken({'QUEUE_TOKEN': '  secret-token \n'}),
        'secret-token',
      );
      expect(
        () => config.readToken({'GITLAB_TOKEN': 'wrong-variable'}),
        throwsStateError,
      );
    });

    test('mounted secret file takes precedence over environment', () {
      final file = File('${temporary.path}/token')
        ..writeAsStringSync('file-token\n');
      final config = BotConfig.parse('${minimal}token_file: ${file.path}\n');
      expect(
        config.readToken({'GITLAB_TOKEN': 'environment-token'}),
        'file-token',
      );
      file.writeAsStringSync('changed-token\n');
      expect(config.readToken({}), 'changed-token');
    });

    for (final token in [null, '', ' \n ', 'first\nsecond', 'first\rsecond']) {
      test(
        'rejects a missing or invalid token ${token == null ? 'null' : token.codeUnits}',
        () {
          final config = BotConfig.parse(minimal);
          expect(
            () => config.readToken({'GITLAB_TOKEN': ?token}),
            throwsStateError,
          );
        },
      );
    }

    test('rejects a blank token file even when environment has a token', () {
      final file = File('${temporary.path}/token')..writeAsStringSync(' \n ');
      final config = BotConfig.parse('${minimal}token_file: ${file.path}\n');
      expect(
        () => config.readToken({'GITLAB_TOKEN': 'fallback'}),
        throwsStateError,
      );
    });

    test('surfaces an unreadable configured token file', () {
      final config = BotConfig.parse(
        '${minimal}token_file: ${temporary.path}/missing\n',
      );
      expect(
        () => config.readToken({'GITLAB_TOKEN': 'fallback'}),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
