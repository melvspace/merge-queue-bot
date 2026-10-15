import 'models.dart';

abstract interface class Hosting {
  Future<BotUser> currentUser();
  Future<Project> project(String id);
  Future<String> branchSha(int projectId, String branch);
  Future<List<MergeRequest>> openMergeRequests(int projectId, String target);
  Future<MergeRequest> mergeRequest(int projectId, int iid);
  Future<BatchRef?> findBatch(int projectId, String branch, String target);
  Future<BatchRef> batch(int projectId, int iid);

  /// Find by source/target before creating; validate the bot ownership marker.
  Future<BatchRef> ensureBatch(
    int projectId,
    String branch,
    String target,
    String description,
  );
  Future<void> describeBatch(int projectId, int iid, String description);
  Future<List<Pipeline>> pipelines(int projectId, int batchIid, String sha);
  Future<Pipeline> pipeline(int projectId, int pipelineId);
  Future<void> mergeBatch(int projectId, int iid, String sha);
  Future<void> commentOnce(int projectId, int iid, String marker, String body);
  Future<void> setAssignees(int projectId, int iid, List<int> assignees);
  Future<void> closeMergeRequest(int projectId, int iid);
  Future<void> reopenMergeRequest(int projectId, int iid);
  void close();
}

abstract interface class Repository {
  Future<String> assemble(
    Project project,
    String target,
    String baseSha,
    List<MergeRequest> members,
    DateTime timestamp,
  );
  Future<String?> remoteBranch(Project project, String branch);
  Future<String?> sourceSha(Project project, MergeRequest member);

  /// Uses an exact remote SHA lease; null means the remote branch must not exist.
  Future<void> publish(
    Project project,
    String target,
    String branch,
    String sha,
    String? expectedRemoteSha,
  );
  Future<bool> contains(Project project, String target, String sha);
}
