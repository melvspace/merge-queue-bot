import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'config.dart';
import 'models.dart';
import 'ports.dart';
import 'state.dart';
import 'store.dart';

/// A tick never waits for CI: independent queues progress concurrently.
class MergeQueue({
  required final Hosting hosting,
  required final Repository repository,
  required final Store store,
  required final BotConfig config,
  required final Project project,
  required final String target,
  required final BotUser bot,
  DateTime Function()? clock,
  void Function(String)? log,
}) {
  final DateTime Function() clock = clock ?? DateTime.now;
  final void Function(String) log = log ?? print;
  late final QueueState state;
  bool _ticking = false;
  bool _retryPaused = false;

  this {
    final key = '${project.id}:$target';
    final suffix = sha256.convert(utf8.encode(key)).toString().substring(0, 16);

    state = store.load(key, 'merge-queue/$suffix');
    _retryPaused = state.paused != null;
  }

  void _save() => store.save(state);
  void _log(String message) => log('[${project.path}:$target] $message');

  Future<void> tick() async {
    if (_ticking) throw StateError('Overlapping ticks for ${state.key}');

    _ticking = true;

    try {
      await _tick();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tick() async {
    // Always reconcile the merge before inspecting source eligibility. Source
    // changes after a completed merge belong to bookkeeping, not a new batch.
    if (await _reconcileLanded()) return;

    // Resolve an uncertain merge outcome before discarding a paused candidate.
    if (_retryPaused) {
      _retryPaused = false;
      state.paused = null;
      state.candidate = null;
      _save();
    }

    if (state.paused != null) {
      await _reportPause();

      return;
    }

    await _drainRejections();

    final items = (await hosting.openMergeRequests(
      project.id,
      target,
    )).where((m) => !m.sourceBranch.startsWith('merge-queue/')).toList();
    store.observe(state.key, items, bot.id, clock().toUtc());

    final candidate = state.candidate;

    if (candidate != null && !await _unchanged(candidate)) {
      _log('Candidate invalidated by base or source changes; rebuilding.');
      state.candidate = null;
      _save();

      return;
    }

    if (state.candidate == null) {
      if (!await _plan()) return;

      if (!await _unchanged(state.candidate!)) {
        state.candidate = null;
        _save();
        await _drainRejections();

        return;
      }
    }

    final current = state.candidate!;

    if (current.phase == 'assembling') {
      try {
        current.sha = await repository.assemble(
          project,
          target,
          current.baseSha,
          current.members,
          current.createdAt,
        );
      } on AssemblyConflict catch (error) {
        final member = current.members.firstWhere((m) => m.iid == error.iid);
        _reject(member, error.detail);
        state.candidate = null;
        _save();
        await _drainRejections();

        return;
      }

      current.phase = 'publishing';
      _save(); // Persist the SHA and lease before pushing anything.
    }

    if (current.phase == 'publishing') {
      await _publish(current);

      return;
    }

    if (current.phase == 'observing' || current.phase == 'merging') {
      await _observe(current);
    }
  }

  Future<bool> _plan() async {
    final waiting = store.waiting(state.key, bot.id, target);
    final eligible = {for (final e in waiting) e.mr.iid: e.mr};

    // Keep recovery groups in order, removing only items no longer eligible.
    state.groups = state.groups
        .map((g) => g.where(eligible.containsKey).toList())
        .where((g) => g.isNotEmpty)
        .toList();

    if (state.groups.isEmpty) {
      if (waiting.isEmpty) {
        _save();

        return false;
      }

      if (clock().toUtc().difference(waiting.first.enqueuedAt) <
          config.collectWindow) {
        _save();

        return false;
      }

      state.groups.add(
        waiting.take(config.maxBatchSize).map((e) => e.mr.iid).toList(),
      );
    }

    // Validate ownership before any force-push to a reused branch.
    if (state.batchIid == null) {
      final existing = await hosting.findBatch(
        project.id,
        state.branch,
        target,
      );

      if (existing != null) {
        state.batchIid = existing.iid;
        state.batchUrl = existing.url;
        state.lastPublishedSha = existing.sha;
      }
    }

    final remote = await repository.remoteBranch(project, state.branch);

    if (remote != null && remote != state.lastPublishedSha) {
      await _pause(
        'Batch branch changed outside the bot; refusing to overwrite it.',
      );

      return false;
    }

    // Git dates have second precision. Ensure rebuilds produce fresh SHAs even
    // when multiple attempts happen within one second or after a clock rollback.
    var timestamp = clock().toUtc();
    final last = state.lastCandidateAt;

    if (last != null &&
        timestamp.millisecondsSinceEpoch ~/ 1000 <=
            last.millisecondsSinceEpoch ~/ 1000) {
      timestamp = DateTime.fromMillisecondsSinceEpoch(
        (last.millisecondsSinceEpoch ~/ 1000 + 1) * 1000,
        isUtc: true,
      );
    }

    state.lastCandidateAt = timestamp;
    state.candidate = Candidate(
      baseSha: await hosting.branchSha(project.id, target),
      members: state.groups.first.map((id) => eligible[id]!).toList(),
      createdAt: timestamp,
      expectedRemoteSha: remote,
    );
    _save();

    return true;
  }

  Future<bool> _unchanged(Candidate candidate) async {
    if (await hosting.branchSha(project.id, target) != candidate.baseSha) {
      return false;
    }

    for (final member in candidate.members) {
      final live = await hosting.mergeRequest(project.id, member.iid);

      if (live.sha != member.sha || !live.eligible(bot.id, target)) {
        return false;
      }

      final sourceSha = await repository.sourceSha(project, live);

      if (sourceSha == null) {
        _reject(
          member,
          'Source branch is missing. Restore it before retrying.',
        );
        _save();

        return false;
      }

      if (sourceSha != member.sha) return false;
    }

    return true;
  }

  String _description(Candidate c) =>
      '<!-- merge-queue-bot -->\n'
      'Batch into `$target` from `${c.baseSha}`.\n\n'
      '${c.members.map((m) => '- [!${m.iid}](${m.url}) `${m.sha}`').join('\n')}\n\n'
      'Candidate: `${c.sha}`.\n'
      'Pipeline discovery window: ${config.discoveryWindow.inSeconds}s. '
      'No pipelines found during that window means this batch can merge untested.';

  Future<void> _publish(Candidate c) async {
    // On a crash after a push, the remote SHA already equals the intent.
    final remote = await repository.remoteBranch(project, state.branch);

    if (remote != c.sha) {
      if (remote != c.expectedRemoteSha) {
        await _pause('Batch branch lease changed; refusing to force-push.');

        return;
      }

      await repository.publish(
        project,
        target,
        state.branch,
        c.sha!,
        c.expectedRemoteSha,
      );
    }

    state.lastPublishedSha = c.sha;
    _save();

    final batch = await hosting.ensureBatch(
      project.id,
      state.branch,
      target,
      _description(c),
    );
    state.batchIid = batch.iid;
    state.batchUrl = batch.url;
    _save();

    await hosting.describeBatch(project.id, batch.iid, _description(c));
    c.startedAt = clock().toUtc(); // After both push and MR creation/update.
    c.phase = 'observing';
    _save();
    _log('Published ${c.sha} with ${c.members.length} MRs: ${batch.url}');
  }

  Future<void> _observe(Candidate c) async {
    final elapsed = clock().toUtc().difference(c.startedAt!);

    if (elapsed >= config.pipelineTimeout) {
      await _pause(
        'Pipeline/merge timeout after ${config.pipelineTimeout.inSeconds}s.',
      );

      return;
    }

    final batch = await hosting.batch(project.id, state.batchIid!);

    if (!_matchesQueue(batch)) {
      await _pause('Batch MR source or target was changed outside the bot.');

      return;
    }

    if (batch.state != 'opened') return; // Reconciled at the next tick.

    // GitLab updates MR head metadata asynchronously after a force-push.
    if (batch.sha != c.sha) return;

    if (elapsed < config.discoveryWindow) return;

    if (c.pipelineIds == null) {
      final pipelines = await hosting.pipelines(project.id, batch.iid, c.sha!);
      c.pipelineIds = pipelines
          .where((p) => p.sha == c.sha)
          .map((p) => p.id)
          .toSet()
          .toList();
      _save(); // Frozen once, including the deliberately empty list.
      _log('Discovered ${c.pipelineIds!.length} pipelines for ${c.sha}.');
    }

    final pipelines = await Future.wait(
      c.pipelineIds!.map((id) => hosting.pipeline(project.id, id)),
    );

    if (pipelines.any((p) => p.sha != c.sha)) {
      await _pause(
        'A discovered pipeline no longer matches the candidate SHA.',
      );

      return;
    }

    if (pipelines.any((p) => p.status == 'canceled' || p.status == 'skipped')) {
      await _pause(
        'A pipeline was canceled or skipped. Restart the service to retry.',
      );

      return;
    }

    const terminal = {'success', 'failed'};

    if (pipelines.any((p) => !terminal.contains(p.status))) return;

    if (pipelines.any((p) => p.status == 'failed')) {
      await _failed(c);

      return;
    }

    // Revalidate project settings and all inputs immediately before merging.
    try {
      (await hosting.project(project.id.toString())).validate();
    } on StateError catch (error) {
      await _pause('Project settings no longer support this queue: $error');

      return;
    }

    if (!await _unchanged(c)) {
      state.candidate = null;
      _save();

      return;
    }

    if (await repository.remoteBranch(project, state.branch) != c.sha) {
      await _pause('Batch branch changed after pipeline discovery.');

      return;
    }

    final ready = await hosting.batch(project.id, batch.iid);

    if (!_matchesQueue(ready)) {
      await _pause('Batch MR source or target was changed outside the bot.');

      return;
    }

    if (ready.sha != c.sha || !await _mergeable(ready)) return;

    c.phase = 'merging';
    _save();

    try {
      await hosting.mergeBatch(project.id, batch.iid, c.sha!);
    } on RemoteException catch (error) {
      // The API response can be lost after a successful merge. Resolve that
      // before rebuilding, pausing, or retrying the request.
      if (await _reconcileLanded()) return;

      if (!await _unchanged(c)) {
        state.candidate = null;
        _save();

        return;
      }

      if (error.statusCode == 405 || error.statusCode == 422) {
        // GitLab can still be recomputing mergeability after a force-push.
        // Missing status on older instances also waits until the timeout.
        await _mergeable(await hosting.batch(project.id, batch.iid));

        return;
      }

      if (error.statusCode == 403) {
        await _pause('GitLab refused the batch merge: $error');

        return;
      }

      rethrow;
    }

    await _reconcileLanded();
  }

  Future<bool> _mergeable(BatchRef batch) async {
    final status = batch.detailedMergeStatus;

    if (status == null || status == 'mergeable') return true;

    const waiting = {
      'unchecked',
      'checking',
      'preparing',
      'approvals_syncing',
      'ci_still_running',
    };

    if (waiting.contains(status)) return false;

    if (status == 'need_rebase' || status == 'conflict') {
      state.candidate = null;
      _save();

      return false;
    }

    await _pause('GitLab blocks this batch: $status.');

    return false;
  }

  Future<void> _failed(Candidate c) async {
    final group = state.groups.removeAt(0);

    if (group.length == 1) {
      final link = state.batchUrl ?? 'batch MR';
      _reject(
        c.members.single,
        'Pipeline failed for this MR alone. See $link.',
      );
    } else {
      final middle = (group.length + 1) ~/ 2;
      state.groups.insertAll(0, [
        group.sublist(0, middle),
        group.sublist(middle),
      ]);
      _log(
        'Failed batch split into groups of $middle and ${group.length - middle}.',
      );
    }

    state.candidate = null;
    _save();
    await _drainRejections();
  }

  void _reject(MergeRequest member, String reason) {
    final digest = sha256
        .convert(utf8.encode(reason))
        .toString()
        .substring(0, 12);

    state.rejections.add(
      Rejection(
        member,
        reason,
        'rejected:${member.iid}:${member.sha}:$digest',
        store.previousAssignees(state.key, member.iid),
      ),
    );

    state.groups = state.groups
        .map((g) => g.where((id) => id != member.iid).toList())
        .where((g) => g.isNotEmpty)
        .toList();
  }

  Future<void> _drainRejections() async {
    while (state.rejections.isNotEmpty) {
      final action = state.rejections.first;
      var live = await hosting.mergeRequest(project.id, action.member.iid);

      await hosting.commentOnce(
        project.id,
        live.iid,
        action.marker,
        action.deliveredUpdate
            ? '${action.reason}\n\nThe bot is returning this open MR to its '
                  'previous assignees. Reassign the bot when the remaining changes are ready.'
            : 'Removed frozen version `${action.member.sha}` from the merge queue. '
                  '${action.reason}\n\nResolve the problem and reassign the bot to retry.',
      );

      live = await hosting.mergeRequest(project.id, action.member.iid);
      // Do not remove a newly updated MR on account of its obsolete version.
      final restoreDelivered =
          action.deliveredUpdate &&
          live.state == 'opened' &&
          live.targetBranch == target &&
          live.assignees.contains(bot.id);

      if (restoreDelivered ||
          (!action.deliveredUpdate &&
              live.sha == action.member.sha &&
              live.eligible(bot.id, target))) {
        final assignees = {...live.assignees, ...action.previousAssignees}
          ..remove(bot.id);
        await hosting.setAssignees(
          project.id,
          live.iid,
          assignees.toList()..sort(),
        );
        store.markUnassigned(state.key, live.iid);
      } else if (!live.assignees.contains(bot.id)) {
        store.markUnassigned(state.key, live.iid);
      }

      state.rejections.removeAt(0);
      _save();
    }
  }

  Future<bool> _reconcileLanded() async {
    if (state.batchIid == null) return false;

    final batch = await hosting.batch(project.id, state.batchIid!);

    if (batch.state == 'closed') {
      if (_retryPaused) {
        _retryPaused = false;
        state.batchIid = null;
        state.batchUrl = null;
        state.paused = null;
        state.candidate = null;
        _save();

        return false;
      }

      if (state.paused == null) {
        await _pause('The batch MR was closed outside the bot.');
      }

      return true;
    }

    if (!_matchesQueue(batch)) {
      if (state.paused == null) {
        await _pause('Batch MR source or target was changed outside the bot.');
      }

      return true;
    }

    if (batch.state != 'merged') return false;

    final c = state.candidate;

    if (c == null ||
        c.sha == null ||
        batch.sha != c.sha ||
        (batch.mergeCommitSha != null && batch.mergeCommitSha != c.sha) ||
        !await repository.contains(project, target, c.sha!)) {
      if (state.paused == null) {
        await _pause(
          'Merged batch differs from the recorded candidate; manual reconciliation required.',
        );
      }

      return true;
    }

    c.phase = 'finalizing';
    _save();

    for (final member in c.members) {
      if (c.finalized.contains(member.iid)) continue;

      store.suppress(state.key, member.iid);
      var live = await hosting.mergeRequest(project.id, member.iid);
      final marker = 'landed:${c.sha}:${member.iid}';

      await hosting.commentOnce(
        project.id,
        member.iid,
        marker,
        'Version `${member.sha}` landed in [batch !${batch.iid}](${batch.url}) '
        'at commit `${c.sha}`. Original source branch retained.',
      );

      live = await hosting.mergeRequest(project.id, member.iid);
      var sourceSha = await repository.sourceSha(project, live);

      if (live.sha == member.sha &&
          sourceSha == member.sha &&
          live.state == 'opened') {
        if (!c.closing.contains(member.iid)) {
          c.closing.add(member.iid);
          _save();
        }

        await hosting.closeMergeRequest(project.id, member.iid);
        live = await hosting.mergeRequest(project.id, member.iid);
        sourceSha = await repository.sourceSha(project, live);
      }

      if (live.sha != member.sha || sourceSha != member.sha) {
        if (live.state == 'closed' && c.closing.contains(member.iid)) {
          await hosting.reopenMergeRequest(project.id, member.iid);
          live = await hosting.mergeRequest(project.id, member.iid);
        }

        await hosting.commentOnce(
          project.id,
          member.iid,
          '$marker:updated',
          'The source no longer matches delivered version `${member.sha}`. '
              'The bot will leave this MR open. Reassign it when remaining changes are ready.',
        );

        if (live.state == 'opened' &&
            live.targetBranch == target &&
            live.assignees.contains(bot.id)) {
          state.rejections.add(
            Rejection(
              live,
              'Version `${member.sha}` already landed in [batch !${batch.iid}](${batch.url}). '
                  'The current source has undelivered changes.',
              '$marker:remaining',
              store.previousAssignees(state.key, member.iid),
              deliveredUpdate: true,
            ),
          );
        }
      }

      c.finalized.add(member.iid);
      _save();
    }

    state.groups.removeAt(0);
    state.candidate = null;
    state.batchIid = null;
    state.batchUrl = null;
    state.paused = null;
    _save();
    await _drainRejections();
    _log('Batch !${batch.iid} landed at ${c.sha}.');

    return true;
  }

  Future<void> _pause(String reason) async {
    state.paused = reason;
    _save();
    _log('PAUSED: $reason');
    await _reportPause();
  }

  bool _matchesQueue(BatchRef batch) =>
      (batch.sourceBranch == null || batch.sourceBranch == state.branch) &&
      (batch.targetBranch == null || batch.targetBranch == target);

  Future<void> _reportPause() async {
    if (state.batchIid == null || state.paused == null) return;

    final digest = sha256
        .convert(utf8.encode(state.paused!))
        .toString()
        .substring(0, 12);

    await hosting.commentOnce(
      project.id,
      state.batchIid!,
      'paused:${state.candidate?.sha ?? 'none'}:$digest',
      'Queue paused: ${state.paused}\n\nRestart the service after resolving the problem.',
    );
  }
}
