import 'package:merge_queue_bot/src/models.dart';
import 'package:merge_queue_bot/src/ports.dart';

const testBot = BotUser(99, 'Queue Bot', 'bot@example.test');
const testProject = Project(
  id: 1,
  path: 'group/repo',
  cloneUrl: 'https://gitlab.example.test/group/repo.git',
  mergeMethod: 'ff',
  squashOption: 'default_off',
  automaticRebase: false,
);

MergeRequest member(
  int iid, {
  String? sha,
  String state = 'opened',
  String target = 'main',
  String? source,
  bool draft = false,
  List<int> assignees = const [99],
  DateTime? createdAt,
  int? sourceProjectId,
}) => MergeRequest(
  iid: iid,
  title: 'Change $iid',
  url: 'https://gitlab.example.test/group/repo/-/merge_requests/$iid',
  sha: sha ?? 'source-$iid',
  targetBranch: target,
  sourceBranch: source ?? 'feature-$iid',
  state: state,
  draft: draft,
  assignees: assignees,
  authorName: 'Author $iid',
  authorEmail: 'author$iid@example.test',
  createdAt: createdAt ?? DateTime.utc(2026, 10, 15),
  sourceProjectId: sourceProjectId,
);

class FakeHosting implements Hosting {
  final Map<int, MergeRequest> members = {};
  final Map<int, BatchRef> batches = {};
  final Map<int, String> batchBranches = {};
  final Map<int, Pipeline> pipelineData = {};
  final Map<String, String> branches = {'main': 'base-0'};
  final Set<String> landedShas = {};
  final Map<String, String> comments = {};
  final List<int> closedMembers = [];
  final List<int> reopenedMembers = [];
  final List<int> pipelineReads = [];
  final List<String> discoveredShas = [];
  final List<String> mergedShas = [];
  final List<int> mergedBatches = [];
  final List<int> mergeAttempts = [];
  final Map<int, String> descriptions = {};
  Project settings = testProject;
  String? publishedSha;
  bool failMergeAfterLanding = false;
  bool failCommentAfterWrite = false;
  bool failEnsureAfterCreate = false;
  bool failAssigneesAfterWrite = false;
  RemoteException? failNextMerge;
  Future<void> Function()? beforeMerge;
  Future<void> Function(int iid)? afterComment;
  Future<void> Function(int iid)? afterClose;
  int _nextBatch = 1000;

  @override
  Future<BotUser> currentUser() async => testBot;

  @override
  Future<Project> project(String id) async => settings;

  @override
  Future<String> branchSha(int projectId, String branch) async =>
      branches[branch]!;

  @override
  Future<List<MergeRequest>> openMergeRequests(
    int projectId,
    String target,
  ) async => members.values
      .where((mr) => mr.state == 'opened' && mr.targetBranch == target)
      .toList();

  @override
  Future<MergeRequest> mergeRequest(int projectId, int iid) async =>
      members[iid]!;

  @override
  Future<BatchRef?> findBatch(
    int projectId,
    String branch,
    String target,
  ) async {
    for (final batch in batches.values) {
      if (batch.state == 'opened' && batchBranches[batch.iid] == branch) {
        return batch;
      }
    }

    return null;
  }

  @override
  Future<BatchRef> batch(int projectId, int iid) async => batches[iid]!;

  @override
  Future<BatchRef> ensureBatch(
    int projectId,
    String branch,
    String target,
    String description,
  ) async {
    final existing = await findBatch(projectId, branch, target);

    if (existing != null) return existing;

    final iid = _nextBatch++;
    final created = BatchRef(
      iid,
      'https://gitlab.example.test/batches/$iid',
      'opened',
      publishedSha!,
      sourceBranch: branch,
      targetBranch: target,
      detailedMergeStatus: 'mergeable',
    );
    batches[iid] = created;
    batchBranches[iid] = branch;
    descriptions[iid] = description;

    if (failEnsureAfterCreate) {
      failEnsureAfterCreate = false;
      throw const RemoteException('MR create response lost');
    }

    return created;
  }

  @override
  Future<void> describeBatch(int projectId, int iid, String description) async {
    descriptions[iid] = description;
  }

  @override
  Future<List<Pipeline>> pipelines(
    int projectId,
    int batchIid,
    String sha,
  ) async {
    discoveredShas.add(sha);

    // Include other SHAs deliberately: the engine must enforce its own binding.
    return pipelineData.values.toList();
  }

  @override
  Future<Pipeline> pipeline(int projectId, int pipelineId) async {
    pipelineReads.add(pipelineId);

    return pipelineData[pipelineId]!;
  }

  @override
  Future<void> mergeBatch(int projectId, int iid, String sha) async {
    mergeAttempts.add(iid);
    await beforeMerge?.call();

    if (failNextMerge case final error?) {
      failNextMerge = null;
      throw error;
    }

    final old = batches[iid]!;

    if (old.sha != sha || old.state != 'opened') {
      throw const RemoteException('Merge precondition failed', statusCode: 409);
    }

    mergedShas.add(sha);
    mergedBatches.add(iid);
    batches[iid] = old.copyWith(state: 'merged', sha: sha, mergeCommitSha: sha);
    branches['main'] = sha;
    landedShas.add(sha);

    if (failMergeAfterLanding) {
      failMergeAfterLanding = false;
      throw const RemoteException('Merge response lost');
    }
  }

  @override
  Future<void> commentOnce(
    int projectId,
    int iid,
    String marker,
    String body,
  ) async {
    comments.putIfAbsent('$iid:$marker', () => body);
    await afterComment?.call(iid);

    if (failCommentAfterWrite) {
      failCommentAfterWrite = false;
      throw const RemoteException('Comment response lost');
    }
  }

  @override
  Future<void> setAssignees(int projectId, int iid, List<int> assignees) async {
    members[iid] = members[iid]!.copyWith(assignees: assignees);

    if (failAssigneesAfterWrite) {
      failAssigneesAfterWrite = false;
      throw const RemoteException('Assignment response lost');
    }
  }

  @override
  Future<void> closeMergeRequest(int projectId, int iid) async {
    closedMembers.add(iid);
    members[iid] = members[iid]!.copyWith(state: 'closed');
    await afterClose?.call(iid);
  }

  @override
  Future<void> reopenMergeRequest(int projectId, int iid) async {
    reopenedMembers.add(iid);
    members[iid] = members[iid]!.copyWith(state: 'opened');
  }

  void recordPush(String branch, String sha) {
    publishedSha = sha;

    for (final existing in batches.values.toList()) {
      if (existing.state == 'opened' && batchBranches[existing.iid] == branch) {
        batches[existing.iid] = existing.copyWith(
          sha: sha,
          mergeCommitSha: null,
        );
      }
    }
  }

  void setBatchStatus(int iid, String? status, {String? state}) {
    final old = batches[iid]!;
    batches[iid] = old.copyWith(
      state: state ?? old.state,
      detailedMergeStatus: status,
    );
  }

  @override
  void close() {}
}

class Assembly(
  final String base,
  final List<int> members,
  final DateTime timestamp,
  final String sha,
);

class Publication(final String branch, final String sha, final String? lease);

class FakeRepository(final FakeHosting hosting) implements Repository {
  final Map<String, String> branches = {};
  final List<Assembly> assemblies = [];
  final List<Publication> publications = [];
  final Set<int> conflicts = {};
  final Map<int, String?> sourceShas = {};
  bool failPublishAfterPush = false;

  @override
  Future<String> assemble(
    Project project,
    String target,
    String baseSha,
    List<MergeRequest> members,
    DateTime timestamp,
  ) async {
    for (final mr in members) {
      if (conflicts.contains(mr.iid)) {
        throw AssemblyConflict(mr.iid, 'shared file conflict');
      }
    }

    final sha = 'candidate-${assemblies.length + 1}';
    assemblies.add(
      Assembly(baseSha, members.map((mr) => mr.iid).toList(), timestamp, sha),
    );

    return sha;
  }

  @override
  Future<String?> remoteBranch(Project project, String branch) async =>
      branches[branch];

  @override
  Future<String?> sourceSha(Project project, MergeRequest member) async =>
      sourceShas.containsKey(member.iid)
      ? sourceShas[member.iid]
      : hosting.members[member.iid]?.sha;

  @override
  Future<void> publish(
    Project project,
    String target,
    String branch,
    String sha,
    String? expectedRemoteSha,
  ) async {
    if (branches[branch] != expectedRemoteSha) {
      throw const RemoteException('Branch lease changed');
    }

    publications.add(Publication(branch, sha, expectedRemoteSha));
    branches[branch] = sha;
    hosting.recordPush(branch, sha);

    if (failPublishAfterPush) {
      failPublishAfterPush = false;
      throw const RemoteException('Push response lost');
    }
  }

  @override
  Future<bool> contains(Project project, String target, String sha) async =>
      hosting.landedShas.contains(sha);
}
