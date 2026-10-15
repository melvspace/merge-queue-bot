import 'package:freezed_annotation/freezed_annotation.dart';

import 'models.dart';

part 'state.freezed.dart';
part 'state.g.dart';

@JsonSerializable(explicitToJson: true)
class Candidate({
  required final String baseSha,
  required final List<MergeRequest> members,
  required final DateTime createdAt,
  var String phase = 'assembling',
  var String? sha,
  var String? expectedRemoteSha,
  var DateTime? startedAt,
  var List<int>? pipelineIds,
  List<int>? finalized,
  List<int>? closing,
}) {
  final List<int> finalized = finalized ?? [];
  final List<int> closing = closing ?? [];

  factory Candidate.fromJson(Json json) => _$CandidateFromJson(json);

  Json toJson() => _$CandidateToJson(this);
}

@freezed
@JsonSerializable(explicitToJson: true)
class const Rejection(
  final MergeRequest member,
  final String reason,
  final String marker,
  final List<int> previousAssignees, {
  final bool deliveredUpdate = false,
}) with _$Rejection {
  factory Rejection.fromJson(Json json) => _$RejectionFromJson(json);

  Json toJson() => _$RejectionToJson(this);
}

@JsonSerializable(explicitToJson: true)
class QueueState({
  required final String key,
  required final String branch,
  List<List<int>>? groups,
  var Candidate? candidate,
  var int? batchIid,
  var String? batchUrl,
  var String? paused,
  var String? lastPublishedSha,
  var DateTime? lastCandidateAt,
  List<Rejection>? rejections,
}) {
  List<List<int>> groups = groups ?? [];
  final List<Rejection> rejections = rejections ?? [];

  factory QueueState.fromJson(Json json) => _$QueueStateFromJson(json);

  Json toJson() => _$QueueStateToJson(this);
}
