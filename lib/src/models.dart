import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';
part 'models.g.dart';

typedef Json = Map<String, dynamic>;

@freezed
class const BotUser(final int id, final String name, final String email)
    with _$BotUser;

@freezed
class const Project({
  required final int id,
  required final String path,
  required final String cloneUrl,
  required final String mergeMethod,
  required final String squashOption,
  required final bool automaticRebase,
  final bool mergedResultsPipelines = false,
}) with _$Project {
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

@freezed
@JsonSerializable()
class const MergeRequest({
  required final int iid,
  required final String title,
  required final String url,
  required final String sha,
  @JsonKey(name: 'target') required final String targetBranch,
  @JsonKey(name: 'source') required final String sourceBranch,
  required final String state,
  required final bool draft,
  required final List<int> assignees,
  required final String authorName,
  required final String authorEmail,
  required final DateTime createdAt,
  final String? mergeCommitSha,
  final int? sourceProjectId,
}) with _$MergeRequest {
  bool eligible(int botId, String target) =>
      state == 'opened' &&
      !draft &&
      targetBranch == target &&
      assignees.contains(botId);

  factory MergeRequest.fromJson(Json json) => _$MergeRequestFromJson(json);

  Json toJson() => _$MergeRequestToJson(this);
}

@freezed
class const Pipeline(final int id, final String sha, final String status)
    with _$Pipeline;

@freezed
class const BatchRef(
  final int iid,
  final String url,
  final String state,
  final String sha, {
  final String? mergeCommitSha,
  final String? sourceBranch,
  final String? targetBranch,
  final String? detailedMergeStatus,
}) with _$BatchRef;

/// A transport failure has an unknown outcome: reconcile before retrying writes.
class const RemoteException(final String message, {final int? statusCode})
    implements Exception {
  @override
  String toString() => message;
}

class const AssemblyConflict(final int iid, final String detail)
    implements Exception {
  @override
  String toString() => 'MR !$iid cannot be applied: $detail';
}
