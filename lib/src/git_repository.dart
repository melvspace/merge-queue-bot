import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'models.dart';
import 'ports.dart';

/// Builds immutable candidates in private checkouts, one per project and target.
class GitRepository({
  required final String workDirectory,
  required final String token,
  required final BotUser bot,
  required final Uri gitlabUrl,
  final Duration timeout = const Duration(minutes: 5),
  final bool allowFileRemotes = false,
}) implements Repository {
  final Map<String, Future<void>> _locks = {};

  this {
    if (!['http', 'https'].contains(gitlabUrl.scheme) ||
        gitlabUrl.host.isEmpty ||
        gitlabUrl.userInfo.isNotEmpty) {
      throw ArgumentError(
        'gitlabUrl must be an HTTP(S) URL without credentials.',
      );
    }

    if (timeout <= Duration.zero) {
      throw ArgumentError('Git timeout must be positive.');
    }
  }

  @override
  Future<String> assemble(
    Project project,
    String target,
    String baseSha,
    List<MergeRequest> members,
    DateTime timestamp,
  ) => _inCheckout(project, target, (directory) async {
    _validateSha(baseSha);
    await _fetchBase(project, target, directory);
    final actualBase = (await _git(directory, [
      'rev-parse',
      'refs/merge-queue/base',
    ])).stdout.trim();

    if (actualBase != baseSha) {
      throw const RemoteException('Target changed before candidate assembly.');
    }

    for (final member in members) {
      _validateSha(member.sha);

      if (member.iid <= 0 || member.targetBranch != target) {
        throw ArgumentError('Candidate contains an invalid merge request.');
      }

      await _git(directory, [
        'fetch',
        '--quiet',
        '--no-tags',
        project.cloneUrl,
        '+refs/merge-requests/${member.iid}/head:'
            'refs/merge-queue/sources/${member.iid}',
      ]);
      final fetched = (await _git(directory, [
        'rev-parse',
        'refs/merge-queue/sources/${member.iid}',
      ])).stdout.trim();

      if (fetched != member.sha) {
        throw RemoteException(
          'MR !${member.iid} changed before candidate assembly.',
        );
      }
    }

    await _git(directory, [
      'checkout',
      '--quiet',
      '--detach',
      '--force',
      baseSha,
    ]);
    await _git(directory, ['clean', '--quiet', '-ffdx']);

    for (final member in members) {
      final merge = await _git(directory, [
        'merge',
        '--squash',
        '--no-commit',
        member.sha,
      ], check: false);

      if (merge.exitCode != 0) {
        await _git(directory, ['reset', '--hard', '--quiet', 'HEAD']);
        final details = merge.stderr.trim().isEmpty
            ? merge.stdout
            : merge.stderr;

        throw AssemblyConflict(member.iid, _redact(details).trim());
      }

      final changes = await _git(directory, [
        'diff',
        '--cached',
        '--quiet',
      ], check: false);

      if (changes.exitCode == 0) {
        throw AssemblyConflict(member.iid, 'no changes relative to target');
      }

      if (changes.exitCode != 1) {
        throw RemoteException(_failure('diff', changes));
      }

      final date = '${timestamp.toUtc().millisecondsSinceEpoch ~/ 1000} +0000';
      final title = member.title
          .replaceAll(
            RegExp(r'\[(?:skip ci|ci skip)\]', caseSensitive: false),
            '',
          )
          .trim();
      await _git(
        directory,
        [
          'commit',
          '--quiet',
          '--no-gpg-sign',
          '-m',
          title.isEmpty ? 'Merge MR !${member.iid}' : title,
          '-m',
          member.url,
        ],
        environment: {
          'GIT_AUTHOR_NAME': member.authorName,
          'GIT_AUTHOR_EMAIL': member.authorEmail,
          'GIT_AUTHOR_DATE': date,
          'GIT_COMMITTER_NAME': bot.name,
          'GIT_COMMITTER_EMAIL': bot.email,
          'GIT_COMMITTER_DATE': date,
        },
      );
    }

    final sha = (await _git(directory, ['rev-parse', 'HEAD'])).stdout.trim();

    // Keep candidates reachable across crashes, resets, and Git garbage collection.
    await _git(directory, [
      'update-ref',
      'refs/merge-queue/candidates/$sha',
      sha,
    ]);

    return sha;
  });

  @override
  Future<String?> remoteBranch(Project project, String branch) async {
    final directory = Directory(workDirectory);
    await directory.create(recursive: true);
    await _validateBranch(directory.path, branch);

    return _remoteRef(project, 'refs/heads/$branch');
  }

  @override
  Future<String?> sourceSha(Project project, MergeRequest member) async {
    if (member.sourceProjectId == project.id) {
      return remoteBranch(project, member.sourceBranch);
    }

    if (member.iid <= 0) throw ArgumentError('Invalid merge request number.');

    return _remoteRef(project, 'refs/merge-requests/${member.iid}/head');
  }

  Future<String?> _remoteRef(Project project, String ref) async {
    _validateRemote(project);
    final directory = Directory(workDirectory);
    await directory.create(recursive: true);
    final valid = await _git(directory.path, [
      'check-ref-format',
      ref,
    ], check: false);

    if (valid.exitCode != 0) throw ArgumentError('Invalid Git ref.');

    final output = await _git(directory.path, [
      'ls-remote',
      project.cloneUrl,
      ref,
    ]);

    for (final line in const LineSplitter().convert(output.stdout)) {
      final fields = line.split('\t');

      if (fields.length == 2 && fields[1] == ref) {
        _validateSha(fields[0]);

        return fields[0];
      }
    }

    return null;
  }

  @override
  Future<void> publish(
    Project project,
    String target,
    String branch,
    String sha,
    String? expectedRemoteSha,
  ) => _inCheckout(project, target, (directory) async {
    _validateSha(sha);

    if (expectedRemoteSha != null) _validateSha(expectedRemoteSha);

    await _validateBranch(directory, branch);

    if (branch == target) {
      throw ArgumentError('A candidate must not overwrite its target branch.');
    }

    final candidate = await _git(directory, [
      'rev-parse',
      '--verify',
      'refs/merge-queue/candidates/$sha',
    ]);

    if (candidate.stdout.trim() != sha) {
      throw const RemoteException('Stored candidate does not match its SHA.');
    }

    await _git(directory, [
      'push',
      '--porcelain',
      '--force-with-lease=refs/heads/$branch:${expectedRemoteSha ?? ''}',
      project.cloneUrl,
      '$sha:refs/heads/$branch',
    ]);
  });

  @override
  Future<void> fastForward(
    Project project,
    String target,
    String baseSha,
    String sha,
  ) => _inCheckout(project, target, (directory) async {
    _validateSha(baseSha);
    _validateSha(sha);
    final candidate = await _git(directory, [
      'rev-parse',
      '--verify',
      'refs/merge-queue/candidates/$sha',
    ]);

    if (candidate.stdout.trim() != sha) {
      throw const RemoteException('Stored candidate does not match its SHA.');
    }

    final ancestor = await _git(directory, [
      'merge-base',
      '--is-ancestor',
      baseSha,
      sha,
    ], check: false);

    if (ancestor.exitCode == 1) {
      throw const RemoteException('Candidate does not descend from its base.');
    }

    if (ancestor.exitCode != 0) {
      throw RemoteException(_failure('merge-base', ancestor));
    }

    // Git skips the lease check for an already up-to-date destination.
    if (await _remoteRef(project, 'refs/heads/$target') != baseSha) {
      throw const RemoteException('Target changed before fast-forward push.');
    }

    await _git(directory, [
      'push',
      '--porcelain',
      '--force-with-lease=refs/heads/$target:$baseSha',
      project.cloneUrl,
      '$sha:refs/heads/$target',
    ]);
  });

  @override
  Future<bool> contains(Project project, String target, String sha) =>
      _inCheckout(project, target, (directory) async {
        _validateSha(sha);
        await _fetchBase(project, target, directory);
        final exists = await _git(directory, [
          'cat-file',
          '-e',
          '$sha^{commit}',
        ], check: false);

        if (exists.exitCode != 0) return false;

        final ancestor = await _git(directory, [
          'merge-base',
          '--is-ancestor',
          sha,
          'refs/merge-queue/base',
        ], check: false);

        if (ancestor.exitCode > 1) {
          throw RemoteException(_failure('merge-base', ancestor));
        }

        return ancestor.exitCode == 0;
      });

  Future<T> _inCheckout<T>(
    Project project,
    String target,
    Future<T> Function(String) action,
  ) async {
    _validateRemote(project);
    final targetKey = sha256.convert(utf8.encode(target)).toString();
    final directory = p.join(workDirectory, '${project.id}', targetKey);
    final previous = _locks[directory] ?? Future<void>.value();
    final completion = Completer<void>();
    _locks[directory] = completion.future;
    await previous;

    try {
      await Directory(directory).create(recursive: true);
      await _validateBranch(directory, target);

      if (!await Directory(p.join(directory, '.git')).exists()) {
        await _git(directory, [
          'init',
          '--quiet',
          '--initial-branch=merge-queue',
        ]);
      }

      return await action(directory);
    } finally {
      completion.complete();

      if (identical(_locks[directory], completion.future)) {
        _locks.remove(directory);
      }
    }
  }

  Future<void> _fetchBase(
    Project project,
    String target,
    String directory,
  ) async {
    await _git(directory, [
      'fetch',
      '--quiet',
      '--no-tags',
      project.cloneUrl,
      '+refs/heads/$target:refs/merge-queue/base',
    ]);
  }

  void _validateRemote(Project project) {
    final remote = Uri.tryParse(project.cloneUrl);

    if (allowFileRemotes && remote?.scheme == 'file') return;

    if (remote == null ||
        !['http', 'https'].contains(remote.scheme) ||
        remote.origin != gitlabUrl.origin ||
        remote.userInfo.isNotEmpty ||
        remote.hasQuery ||
        remote.hasFragment) {
      throw ArgumentError(
        'Project clone URL must use the configured GitLab origin.',
      );
    }
  }

  void _validateSha(String value) {
    if (!RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$').hasMatch(value)) {
      throw ArgumentError('Invalid Git commit SHA.');
    }
  }

  Future<void> _validateBranch(String directory, String branch) async {
    if (branch.isEmpty || branch.startsWith('-')) {
      throw ArgumentError('Invalid Git branch name.');
    }

    final result = await _git(directory, [
      'check-ref-format',
      'refs/heads/$branch',
    ], check: false);

    if (result.exitCode != 0) throw ArgumentError('Invalid Git branch name.');
  }

  Future<_GitResult> _git(
    String directory,
    List<String> arguments, {
    bool check = true,
    Map<String, String> environment = const {},
  }) async {
    final processEnvironment = Map<String, String>.fromEntries(
      Platform.environment.entries.where(
        (entry) => !entry.key.startsWith('GIT_'),
      ),
    );
    final authorization = base64.encode(utf8.encode('oauth2:$token'));
    final config = {
      'core.hooksPath': '/dev/null',
      'core.autocrlf': 'false',
      'commit.gpgsign': 'false',
      'credential.helper': '',
      'http.followRedirects': 'false',
      'protocol.allow': 'never',
      'protocol.http.allow': 'always',
      'protocol.https.allow': 'always',
      if (allowFileRemotes) 'protocol.file.allow': 'always',
      'http.${gitlabUrl.origin}/.extraHeader':
          'Authorization: Basic $authorization',
    };
    processEnvironment.addAll({
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_AUTHOR_NAME': bot.name,
      'GIT_AUTHOR_EMAIL': bot.email,
      'GIT_COMMITTER_NAME': bot.name,
      'GIT_COMMITTER_EMAIL': bot.email,
      'GIT_CONFIG_COUNT': '${config.length}',
      for (final (index, key) in config.keys.indexed)
        'GIT_CONFIG_KEY_$index': key,
      for (final (index, value) in config.values.indexed)
        'GIT_CONFIG_VALUE_$index': value,
      'LC_ALL': 'C',
      ...environment,
    });

    try {
      final process = await Process.start(
        'git',
        arguments,
        workingDirectory: directory,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      final values =
          await Future.wait<Object>([
            process.stdout.transform(systemEncoding.decoder).join(),
            process.stderr.transform(systemEncoding.decoder).join(),
            process.exitCode,
          ]).timeout(
            timeout,
            onTimeout: () {
              process.kill(ProcessSignal.sigkill);
              throw RemoteException('git ${arguments.first} timed out.');
            },
          );
      final result = _GitResult(
        values[2] as int,
        values[0] as String,
        values[1] as String,
      );

      if (check && result.exitCode != 0) {
        throw RemoteException(_failure(arguments.first, result));
      }

      return result;
    } on ProcessException catch (error) {
      throw RemoteException('Cannot run Git: ${_redact(error.message)}');
    }
  }

  String _failure(String command, _GitResult result) =>
      'git $command failed (${result.exitCode}): ${_redact(result.stderr).trim()}';

  String _redact(String text) {
    if (token.isEmpty) return text;

    return text
        .replaceAll(token, '[redacted]')
        .replaceAll(Uri.encodeComponent(token), '[redacted]')
        .replaceAll(base64.encode(utf8.encode('oauth2:$token')), '[redacted]');
  }
}

class const _GitResult(
  final int exitCode,
  final String stdout,
  final String stderr,
);
