import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'git_repository.dart';
import 'gitlab.dart';
import 'queue.dart';
import 'store.dart';

/// An OS lock is released on crashes. Never unlink the lock file while running.
class InstanceLock._(final RandomAccessFile _file) {
  static Future<InstanceLock> acquire(String database) async {
    final file = File('${p.normalize(p.absolute(database))}.lock');
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.append);

    try {
      await handle.lock(FileLock.exclusive);

      return InstanceLock._(handle);
    } on FileSystemException {
      await handle.close();
      throw StateError('Another bot instance is using this database.');
    }
  }

  Future<void> close() => _file.close();
}

class BotService(
  final BotConfig config,
  final String token, {
  void Function(String)? log,
}) {
  final void Function(String) _output = log ?? print;
  bool _stopping = false;
  final Set<Completer<void>> _waiters = {};

  void stop() {
    _stopping = true;

    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void _log(String message) => _output(
    '${DateTime.now().toUtc().toIso8601String()} '
    '${message.replaceAll(token, '[REDACTED]')}',
  );

  Future<void> run({bool once = false}) async {
    final lock = await InstanceLock.acquire(config.database);
    Store? store;
    final hosting = GitLab(url: config.gitlabUrl, token: token);

    try {
      store = Store(config.database);
      final user = await hosting.currentUser();
      store.bindIdentity(
        '${config.gitlabUrl.toString().replaceFirst(RegExp(r'/+$'), '')}:${user.id}',
      );

      final repository = GitRepository(
        workDirectory: config.workDirectory,
        token: token,
        bot: user,
        gitlabUrl: config.gitlabUrl,
      );
      final queues = <MergeQueue>[];
      final seen = <String>{};

      for (final configured in config.projects) {
        final project = await hosting.project(configured.id);
        project.validate();

        for (final target in configured.targets) {
          if (!seen.add('${project.id}:$target')) {
            throw StateError(
              'Duplicate resolved project/target: ${project.path}:$target',
            );
          }

          await hosting.branchSha(project.id, target);
          queues.add(
            MergeQueue(
              hosting: hosting,
              repository: repository,
              store: store,
              config: config,
              project: project,
              target: target,
              bot: user,
              log: _log,
            ),
          );
        }
      }

      _log('Started as ${user.name}; managing ${queues.length} queues.');
      await Future.wait(queues.map((queue) => _runQueue(queue, once)));
    } finally {
      hosting.close();
      store?.close();
      await lock.close();
    }
  }

  Future<void> _runQueue(MergeQueue queue, bool once) async {
    while (!_stopping) {
      try {
        await queue.tick();
      } catch (error) {
        // Persisted intent is reconciled on the next tick. Never auto-retry a
        // mutation in the HTTP transport: its outcome might already be durable.
        _log('[${queue.project.path}:${queue.target}] Tick failed: $error');

        if (once) rethrow;
      }

      if (once) return;

      var delay = config.pollInterval;
      final c = queue.state.candidate;

      if (queue.state.paused == null &&
          c?.phase == 'observing' &&
          c?.pipelineIds == null &&
          c?.startedAt != null) {
        final remaining = c!.startedAt!
            .add(config.discoveryWindow)
            .difference(DateTime.now().toUtc());

        if (remaining > Duration.zero && remaining < delay) delay = remaining;

        if (remaining <= Duration.zero) delay = const Duration(seconds: 1);
      }

      if (queue.state.paused == null &&
          c == null &&
          queue.state.groups.isEmpty) {
        final waiting = queue.store.waiting(
          queue.state.key,
          queue.bot.id,
          queue.target,
        );

        if (waiting.isNotEmpty) {
          final remaining = waiting.first.enqueuedAt
              .add(config.collectWindow)
              .difference(DateTime.now().toUtc());

          if (remaining > Duration.zero && remaining < delay) delay = remaining;
        }
      }

      await _wait(delay);
    }
  }

  Future<void> _wait(Duration duration) async {
    if (_stopping) return;

    final waiter = Completer<void>();
    _waiters.add(waiter);
    final timer = Timer(duration, () => waiter.complete());

    try {
      await waiter.future;
    } finally {
      timer.cancel();
      _waiters.remove(waiter);
    }
  }
}
