import 'dart:io';

import 'package:merge_queue_bot/src/config.dart';
import 'package:merge_queue_bot/src/models.dart';
import 'package:test/test.dart';

const minimal = '''
gitlab:
  url: https://gitlab.example.test
projects:
  - id: group/project
    target_branches: [main]
''';

void main() {
  test('deserializes all grouped settings from YAML and JSON', () {
    final yaml = BotConfig.parse('''
gitlab:
  url: https://gitlab.example.test/gitlab
  token_env: QUEUE_GITLAB_TOKEN
  token_file: /run/secrets/token
storage:
  database: /data/state.sqlite
  work_directory: /data/clones
queue:
  poll_interval_seconds: 3
  collect_window_seconds: 0
  max_batch_size: 4
pipelines:
  discovery_seconds: 0
  timeout_seconds: 900
projects:
  - id: 123
    target_branches: [main, release/1]
    landing_mode: fast_forward_push
  - id: another/project
    target_branches: [main]
    landing_mode: merge
''');
    final json = BotConfig.fromJson({
      'gitlab': {
        'url': 'https://gitlab.example.test/gitlab',
        'token_env': 'QUEUE_GITLAB_TOKEN',
        'token_file': '/run/secrets/token',
      },
      'storage': {
        'database': '/data/state.sqlite',
        'work_directory': '/data/clones',
      },
      'queue': {
        'poll_interval_seconds': 3,
        'collect_window_seconds': 0,
        'max_batch_size': 4,
      },
      'pipelines': {'discovery_seconds': 0, 'timeout_seconds': 900},
      'projects': [
        {
          'id': 123,
          'target_branches': ['main', 'release/1'],
          'landing_mode': 'fast_forward_push',
        },
        {
          'id': 'another/project',
          'target_branches': ['main'],
          'landing_mode': 'merge',
        },
      ],
    });

    for (final config in [yaml, json]) {
      expect(
        config.gitlab.url,
        Uri.parse('https://gitlab.example.test/gitlab'),
      );
      expect(config.storage.database, '/data/state.sqlite');
      expect(config.storage.workDirectory, '/data/clones');
      expect(config.gitlab.tokenEnvironment, 'QUEUE_GITLAB_TOKEN');
      expect(config.gitlab.tokenFile, '/run/secrets/token');
      expect(config.queue.pollInterval, const Duration(seconds: 3));
      expect(config.queue.collectWindow, Duration.zero);
      expect(config.pipelines.discoveryWindow, Duration.zero);
      expect(config.pipelines.timeout, const Duration(seconds: 900));
      expect(config.queue.maxBatchSize, 4);
      expect(config.projects.first.id, '123');
      expect(config.projects.first.targets, ['main', 'release/1']);
      expect(config.projects.first.landingMode, LandingMode.fastForwardPush);
      expect(config.projects.last.landingMode, LandingMode.merge);
    }
  });

  test('null landing mode uses the default', () {
    final config = BotConfig.parse('$minimal    landing_mode: null\n');

    expect(config.projects.single.landingMode, LandingMode.merge);
  });

  test('validation errors identify grouped configuration paths', () {
    for (final (source, path) in [
      (
        minimal.replaceFirst(
          'https://gitlab.example.test',
          'ftp://gitlab.example.test',
        ),
        'gitlab.url',
      ),
      (
        '$minimal\npipelines:\n  discovery_seconds: invalid\n',
        'pipelines.discovery_seconds',
      ),
      ('$minimal\nqueue:\n  max_batch_size: 0\n', 'queue.max_batch_size'),
      ('$minimal\nstorage:\n  database: ""\n', 'storage.database'),
      (minimal.replaceFirst('  url:', '  unknown:'), 'gitlab.unknown'),
      ('$minimal\nqueue:\n  unknown: 0\n', 'queue.unknown'),
      ('$minimal    landing_mode: invalid\n', 'projects[0].landing_mode'),
    ]) {
      expect(
        () => BotConfig.parse(source),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains(path),
          ),
        ),
      );
    }
  });

  for (final mode in [
    'unknown',
    'fastForwardPush',
    'true',
    '123',
    '[]',
    '{}',
  ]) {
    test('rejects invalid landing mode $mode', () {
      expect(
        () => BotConfig.parse('$minimal    landing_mode: $mode\n'),
        throwsFormatException,
      );
    });
  }

  test('rejects unknown grouped top-level and nested options', () {
    for (final option in [
      'unknown: true',
      'gitlabs: {}',
      'storage: {databse: /data/state.sqlite}',
      'queue: {poll_interval_second: 5}',
      'pipelines: {discovery_second: 10}',
    ]) {
      expect(
        () => BotConfig.parse('$minimal$option\n'),
        throwsFormatException,
        reason: option,
      );
    }

    expect(
      () => BotConfig.parse(minimal.replaceFirst('  url:', '  urll:')),
      throwsFormatException,
    );
  });

  for (final key in [
    'gitlab_url',
    'token_env',
    'token_file',
    'database',
    'work_directory',
    'poll_interval_seconds',
    'collect_window_seconds',
    'max_batch_size',
    'pipeline_discovery_seconds',
    'pipeline_timeout_seconds',
  ]) {
    test('rejects legacy top-level option $key', () {
      expect(
        () => BotConfig.parse('$minimal$key: null\n'),
        throwsFormatException,
      );
    });
  }

  for (final section in ['gitlab', 'storage', 'queue', 'pipelines']) {
    for (final value in ['null', '[]', 'true', '123', 'text']) {
      test('rejects a non-map $section section: $value', () {
        final source = section == 'gitlab'
            ? minimal.replaceFirst(
                'gitlab:\n  url: https://gitlab.example.test',
                'gitlab: $value',
              )
            : '$minimal$section: $value\n';

        expect(() => BotConfig.parse(source), throwsFormatException);
      });
    }
  }

  test('deserializes minimal JSON with the same defaults as YAML', () {
    final config = BotConfig.fromJson({
      'gitlab': {'url': 'https://gitlab.example.test'},
      'storage': <String, dynamic>{},
      'queue': <String, dynamic>{},
      'pipelines': <String, dynamic>{},
      'projects': [
        {
          'id': 'group/project',
          'target_branches': ['main'],
        },
      ],
    });
    final yaml = BotConfig.parse(minimal);

    expect(config.gitlab.url, yaml.gitlab.url);
    expect(config.storage.database, yaml.storage.database);
    expect(config.storage.workDirectory, yaml.storage.workDirectory);
    expect(config.gitlab.tokenEnvironment, yaml.gitlab.tokenEnvironment);
    expect(config.gitlab.tokenFile, yaml.gitlab.tokenFile);
    expect(config.queue.pollInterval, yaml.queue.pollInterval);
    expect(config.queue.collectWindow, yaml.queue.collectWindow);
    expect(config.pipelines.discoveryWindow, yaml.pipelines.discoveryWindow);
    expect(config.pipelines.timeout, yaml.pipelines.timeout);
    expect(config.queue.maxBatchSize, yaml.queue.maxBatchSize);
    expect(config.projects.single.id, yaml.projects.single.id);
    expect(config.projects.single.targets, yaml.projects.single.targets);
    expect(
      config.projects.single.landingMode,
      yaml.projects.single.landingMode,
    );
  });

  test('rejects a flat configuration', () {
    expect(
      () => BotConfig.parse('''
gitlab_url: https://gitlab.example.test
projects:
  - id: group/project
    target_branches: [main]
'''),
      throwsFormatException,
    );
  });

  test('deserializes project IDs and target branches directly', () {
    final numeric = ProjectConfig.fromJson({
      'id': 123,
      'target_branches': ['main', 'release/1'],
    });
    final named = ProjectConfig.fromJson({
      'id': 'group/project',
      'target_branches': ['main'],
    });

    expect(numeric.id, '123');
    expect(numeric.targets, ['main', 'release/1']);
    expect(named.id, 'group/project');
    expect(named.targets, ['main']);
  });

  test('applies validation when deserializing JSON directly', () {
    expect(
      () => BotConfig.fromJson({
        'gitlab': {'url': 'https://gitlab.example.test'},
        'pipelines': {'timeout_seconds': 10},
        'projects': [
          {
            'id': 'group/project',
            'target_branches': ['main'],
          },
        ],
      }),
      throwsFormatException,
    );

    expect(
      () => BotConfig.fromJson({
        'gitlab': {'url': 'https://gitlab.example.test'},
        'projects': [
          {
            'id': 'group/project',
            'target_branches': ['main'],
            'unknown': true,
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('deserializes nested YAML maps and aliased target lists', () {
    final config = BotConfig.parse('''
gitlab:
  url: https://gitlab.example.test
projects:
  - id: 123
    target_branches: &targets [main, release/1]
  - id: group/other
    target_branches: *targets
''');

    expect(config.projects.map((project) => project.id), [
      '123',
      'group/other',
    ]);
    expect(config.projects.first.targets, ['main', 'release/1']);
    expect(config.projects.last.targets, ['main', 'release/1']);
  });

  test('uses the agreed operational defaults', () {
    final config = BotConfig.parse(minimal);

    expect(config.gitlab.url, Uri.parse('https://gitlab.example.test'));
    expect(config.storage.database, 'data/queue.sqlite');
    expect(config.storage.workDirectory, 'data/repositories');
    expect(config.gitlab.tokenEnvironment, 'GITLAB_TOKEN');
    expect(config.gitlab.tokenFile, isNull);
    expect(config.queue.pollInterval, const Duration(seconds: 30));
    expect(config.queue.collectWindow, const Duration(seconds: 30));
    expect(config.pipelines.discoveryWindow, const Duration(seconds: 10));
    expect(config.pipelines.timeout, const Duration(minutes: 60));
    expect(config.queue.maxBatchSize, 10);
    expect(config.projects.single.id, 'group/project');
    expect(config.projects.single.targets, ['main']);
    expect(config.projects.single.landingMode, LandingMode.merge);
  });

  test(
    'accepts custom settings, integer project IDs, and multiple targets',
    () {
      final config = BotConfig.parse('''
gitlab:
  url: https://gitlab.example.test/gitlab
  token_env: QUEUE_GITLAB_TOKEN
  token_file: /run/secrets/token
storage:
  database: /data/state.sqlite
  work_directory: /data/clones
queue:
  poll_interval_seconds: 3
  collect_window_seconds: 0
  max_batch_size: 4
pipelines:
  discovery_seconds: 0
  timeout_seconds: 900
projects:
  - id: 123
    target_branches: [main, release/1]
  - id: another/project
    target_branches: [main]
''');

      expect(config.gitlab.url.path, '/gitlab');
      expect(config.storage.database, '/data/state.sqlite');
      expect(config.storage.workDirectory, '/data/clones');
      expect(config.gitlab.tokenEnvironment, 'QUEUE_GITLAB_TOKEN');
      expect(config.gitlab.tokenFile, '/run/secrets/token');
      expect(config.queue.pollInterval, const Duration(seconds: 3));
      expect(config.queue.collectWindow, Duration.zero);
      expect(config.pipelines.discoveryWindow, Duration.zero);
      expect(config.pipelines.timeout, const Duration(seconds: 900));
      expect(config.queue.maxBatchSize, 4);
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

  for (final (section, key) in [
    ('storage', 'database'),
    ('storage', 'work_directory'),
    ('gitlab', 'token_env'),
    ('gitlab', 'token_file'),
  ]) {
    for (final value in ["''", "'   '", '123']) {
      test('rejects invalid $key value $value', () {
        expect(
          () => BotConfig.parse(_withOption(section, key, value)),
          throwsFormatException,
        );
      });
    }
  }

  for (final (section, key) in [
    ('queue', 'poll_interval_seconds'),
    ('queue', 'collect_window_seconds'),
    ('pipelines', 'discovery_seconds'),
    ('pipelines', 'timeout_seconds'),
    ('queue', 'max_batch_size'),
  ]) {
    for (final value in ['-1', '-9223372036854775808', '1.5', "'10'", 'true']) {
      test('rejects invalid $key value $value', () {
        expect(
          () => BotConfig.parse(_withOption(section, key, value)),
          throwsFormatException,
        );
      });
    }
  }

  for (final (section, key) in [
    ('queue', 'poll_interval_seconds'),
    ('pipelines', 'timeout_seconds'),
    ('queue', 'max_batch_size'),
  ]) {
    test('rejects zero $key', () {
      expect(
        () => BotConfig.parse(_withOption(section, key, '0')),
        throwsFormatException,
      );
    });
  }

  for (final timeout in [9, 10]) {
    test('requires pipeline timeout $timeout to exceed discovery window', () {
      expect(
        () => BotConfig.parse(
          _withOption('pipelines', 'timeout_seconds', '$timeout'),
        ),
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
    '[{id: 1.5, target_branches: [main]}]',
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
          'gitlab: {url: https://gitlab.example.test}\nprojects: $projects\n',
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
      () => BotConfig.parse('gitlab: {url: https://gitlab.example.test}'),
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
      final config = BotConfig.parse(
        _withOption('gitlab', 'token_env', 'QUEUE_TOKEN'),
      );

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
      final config = BotConfig.parse(
        _withOption('gitlab', 'token_file', file.path),
      );

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
      final config = BotConfig.parse(
        _withOption('gitlab', 'token_file', file.path),
      );

      expect(
        () => config.readToken({'GITLAB_TOKEN': 'fallback'}),
        throwsStateError,
      );
    });

    test('surfaces an unreadable configured token file', () {
      final config = BotConfig.parse(
        _withOption('gitlab', 'token_file', '${temporary.path}/missing'),
      );

      expect(
        () => config.readToken({'GITLAB_TOKEN': 'fallback'}),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}

String _withOption(String section, String key, String value) {
  if (section == 'gitlab') {
    return minimal.replaceFirst(
      '  url: https://gitlab.example.test',
      '  url: https://gitlab.example.test\n  $key: $value',
    );
  }

  return '$minimal$section:\n  $key: $value\n';
}
