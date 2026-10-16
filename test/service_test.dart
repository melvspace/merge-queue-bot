import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:merge_queue_bot/src/service.dart';
import 'package:merge_queue_bot/src/store.dart';
import 'package:test/test.dart';

void main() {
  test(
    'database instance lock excludes another process and releases on close',
    () async {
      final root = Directory('/tmp/codex')..createSync(recursive: true);
      final directory = root.createTempSync('merge-queue-lock-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final database = '${directory.path}/queue.sqlite';
      final script = File('${directory.path}/lock_probe.dart')
        ..writeAsStringSync('''
import 'dart:io';
Future<void> main(List<String> args) async {
  final handle = await File(args.single).open(mode: FileMode.append);
  try {
    await handle.lock(FileLock.exclusive);
  } on FileSystemException {
    exitCode = 7;
  } finally {
    await handle.close();
  }
}
''');

      final lock = await InstanceLock.acquire(database);

      try {
        final blocked = await Process.run(Platform.resolvedExecutable, [
          script.path,
          '$database.lock',
        ]);

        expect(blocked.exitCode, 7, reason: '${blocked.stderr}');
      } finally {
        await lock.close();
      }

      final acquired = await Process.run(Platform.resolvedExecutable, [
        script.path,
        '$database.lock',
      ]);

      expect(acquired.exitCode, 0, reason: '${acquired.stderr}');
    },
  );

  test('database cannot be reused for another instance or service account', () {
    final store = Store(':memory:');
    addTearDown(store.close);

    store.bindIdentity('https://gitlab.example.com:123');
    store.bindIdentity('https://gitlab.example.com:123');

    expect(
      () => store.bindIdentity('https://gitlab.other.com:123'),
      throwsStateError,
    );
    expect(
      () => store.bindIdentity('https://gitlab.example.com:456'),
      throwsStateError,
    );
  });

  test(
    'CLI exits promptly on SIGTERM while waiting for the next poll',
    () async {
      final root = Directory('/tmp/codex')..createSync(recursive: true);
      final directory = root.createTempSync('merge-queue-shutdown-');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final url = 'http://${server.address.address}:${server.port}';
      final polled = Completer<void>();

      server.listen((request) async {
        final Object response;
        switch (request.uri.path) {
          case '/api/v4/user':
            response = {
              'id': 42,
              'username': 'queue-bot',
              'name': 'Queue Bot',
              'email': 'queue@example.com',
            };
          case '/api/v4/projects/1':
            response = {
              'id': 1,
              'path_with_namespace': 'test/project',
              'http_url_to_repo': '$url/test/project.git',
              'merge_method': 'rebase_merge',
              'squash_option': 'never',
              'automatic_rebase_enabled': false,
              'merge_pipelines_enabled': false,
            };
          case '/api/v4/projects/1/repository/branches/main':
            response = {
              'commit': {'id': 'a' * 40},
            };
          case '/api/v4/projects/1/merge_requests':
            response = <Object>[];
          default:
            request.response.statusCode = HttpStatus.notFound;
            response = {'message': 'Unexpected request: ${request.uri}'};
        }

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();

        if (request.uri.path == '/api/v4/projects/1/merge_requests' &&
            !polled.isCompleted) {
          polled.complete();
        }
      });

      Process? process;
      final output = StringBuffer();
      final drains = <Future<void>>[];
      addTearDown(() async {
        process?.kill(ProcessSignal.sigkill);

        if (process != null) await process.exitCode;

        await Future.wait(drains);
        await server.close(force: true);
        await directory.delete(recursive: true);
      });

      final config = File('${directory.path}/config.yaml')
        ..writeAsStringSync('''
gitlab:
  url: $url
  token_env: MERGE_QUEUE_SHUTDOWN_TEST_TOKEN
storage:
  database: ${directory.path}/queue.sqlite
  work_directory: ${directory.path}/repositories
queue:
  poll_interval_seconds: 60
projects:
  - id: 1
    target_branches: [main]
    landing_mode: fast_forward_push
''');

      process = await Process.start(
        Platform.resolvedExecutable,
        ['run', 'bin/merge_queue_bot.dart', '--config', config.path],
        environment: {'MERGE_QUEUE_SHUTDOWN_TEST_TOKEN': 'test-token'},
      );
      drains.add(process.stdout.transform(utf8.decoder).forEach(output.write));
      drains.add(process.stderr.transform(utf8.decoder).forEach(output.write));

      await polled.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => fail('CLI did not reach its first poll: $output'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(process.kill(ProcessSignal.sigterm), isTrue);
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => fail('CLI remained alive after SIGTERM: $output'),
      );
      await Future.wait(drains);

      expect(exitCode, 0, reason: '$output');
    },
  );
}
