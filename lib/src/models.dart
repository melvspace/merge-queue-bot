typedef Json = Map<String, dynamic>;

class BotUser {
  final int id;
  final String name;
  final String email;
  const BotUser(this.id, this.name, this.email);
}

class Project {
  final int id;
  final String path;
  final String cloneUrl;
  final String mergeMethod;
  final String squashOption;
  final bool automaticRebase;
  final bool mergedResultsPipelines;
  const Project({
    required this.id,
    required this.path,
    required this.cloneUrl,
    required this.mergeMethod,
    required this.squashOption,
    required this.automaticRebase,
    this.mergedResultsPipelines = false,
  });

  void validate() {
    if (mergeMethod != 'ff' ||
        !const {'never', 'default_off', 'default_on'}.contains(squashOption) ||
        automaticRebase ||
        mergedResultsPipelines) {
      throw StateError(
        '$path requires fast-forward merges, optional/disabled '
        'squashing, automatic rebase disabled, and merged-results pipelines '
        'disabled.',
      );
    }
  }
}

class MergeRequest {
  final int iid;
  final String title;
  final String url;
  final String sha;
  final String targetBranch;
  final String sourceBranch;
  final String state;
  final bool draft;
  final List<int> assignees;
  final String authorName;
  final String authorEmail;
  final DateTime createdAt;
  final String? mergeCommitSha;
  final int? sourceProjectId;

  const MergeRequest({
    required this.iid,
    required this.title,
    required this.url,
    required this.sha,
    required this.targetBranch,
    required this.sourceBranch,
    required this.state,
    required this.draft,
    required this.assignees,
    required this.authorName,
    required this.authorEmail,
    required this.createdAt,
    this.mergeCommitSha,
    this.sourceProjectId,
  });

  bool eligible(int botId, String target) =>
      state == 'opened' &&
      !draft &&
      targetBranch == target &&
      assignees.contains(botId);

  Json toJson() => {
    'iid': iid,
    'title': title,
    'url': url,
    'sha': sha,
    'target': targetBranch,
    'source': sourceBranch,
    'state': state,
    'draft': draft,
    'assignees': assignees,
    'authorName': authorName,
    'authorEmail': authorEmail,
    'createdAt': createdAt.toIso8601String(),
    'mergeCommitSha': mergeCommitSha,
    'sourceProjectId': sourceProjectId,
  };

  factory MergeRequest.fromJson(Json j) => MergeRequest(
    iid: j['iid'] as int,
    title: j['title'] as String,
    url: j['url'] as String,
    sha: j['sha'] as String,
    targetBranch: j['target'] as String,
    sourceBranch: j['source'] as String,
    state: j['state'] as String,
    draft: j['draft'] as bool,
    assignees: (j['assignees'] as List).cast<int>(),
    authorName: j['authorName'] as String,
    authorEmail: j['authorEmail'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    mergeCommitSha: j['mergeCommitSha'] as String?,
    sourceProjectId: j['sourceProjectId'] as int?,
  );
}

class Pipeline {
  final int id;
  final String sha;
  final String status;
  const Pipeline(this.id, this.sha, this.status);
}

class BatchRef {
  final int iid;
  final String url;
  final String state;
  final String sha;
  final String? mergeCommitSha;
  final String? sourceBranch;
  final String? targetBranch;
  final String? detailedMergeStatus;
  const BatchRef(
    this.iid,
    this.url,
    this.state,
    this.sha, {
    this.mergeCommitSha,
    this.sourceBranch,
    this.targetBranch,
    this.detailedMergeStatus,
  });
}

/// A transport failure has an unknown outcome: reconcile before retrying writes.
class RemoteException implements Exception {
  final String message;
  final int? statusCode;
  const RemoteException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class AssemblyConflict implements Exception {
  final int iid;
  final String detail;
  const AssemblyConflict(this.iid, this.detail);
  @override
  String toString() => 'MR !$iid cannot be applied: $detail';
}
