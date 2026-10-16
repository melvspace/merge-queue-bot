// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Candidate _$CandidateFromJson(Map<String, dynamic> json) => Candidate(
  baseSha: json['baseSha'] as String,
  members: (json['members'] as List<dynamic>)
      .map((e) => MergeRequest.fromJson(e as Map<String, dynamic>))
      .toList(),
  createdAt: DateTime.parse(json['createdAt'] as String),
  landingMode:
      $enumDecodeNullable(_$LandingModeEnumMap, json['landingMode']) ??
      LandingMode.merge,
  phase: json['phase'] as String? ?? 'assembling',
  sha: json['sha'] as String?,
  expectedRemoteSha: json['expectedRemoteSha'] as String?,
  startedAt: json['startedAt'] == null
      ? null
      : DateTime.parse(json['startedAt'] as String),
  pipelineIds: (json['pipelineIds'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  finalized: (json['finalized'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  closing: (json['closing'] as List<dynamic>?)
      ?.map((e) => (e as num).toInt())
      .toList(),
);

Map<String, dynamic> _$CandidateToJson(Candidate instance) => <String, dynamic>{
  'baseSha': instance.baseSha,
  'members': instance.members.map((e) => e.toJson()).toList(),
  'createdAt': instance.createdAt.toIso8601String(),
  'landingMode': _$LandingModeEnumMap[instance.landingMode]!,
  'phase': instance.phase,
  'sha': instance.sha,
  'expectedRemoteSha': instance.expectedRemoteSha,
  'startedAt': instance.startedAt?.toIso8601String(),
  'pipelineIds': instance.pipelineIds,
  'finalized': instance.finalized,
  'closing': instance.closing,
};

const _$LandingModeEnumMap = {
  LandingMode.merge: 'merge',
  LandingMode.fastForwardPush: 'fast_forward_push',
};

Rejection _$RejectionFromJson(Map<String, dynamic> json) => Rejection(
  MergeRequest.fromJson(json['member'] as Map<String, dynamic>),
  json['reason'] as String,
  json['marker'] as String,
  (json['previousAssignees'] as List<dynamic>)
      .map((e) => (e as num).toInt())
      .toList(),
  deliveredUpdate: json['deliveredUpdate'] as bool? ?? false,
);

Map<String, dynamic> _$RejectionToJson(Rejection instance) => <String, dynamic>{
  'member': instance.member.toJson(),
  'reason': instance.reason,
  'marker': instance.marker,
  'previousAssignees': instance.previousAssignees,
  'deliveredUpdate': instance.deliveredUpdate,
};

QueueState _$QueueStateFromJson(Map<String, dynamic> json) => QueueState(
  key: json['key'] as String,
  branch: json['branch'] as String,
  groups: (json['groups'] as List<dynamic>?)
      ?.map((e) => (e as List<dynamic>).map((e) => (e as num).toInt()).toList())
      .toList(),
  candidate: json['candidate'] == null
      ? null
      : Candidate.fromJson(json['candidate'] as Map<String, dynamic>),
  batchIid: (json['batchIid'] as num?)?.toInt(),
  batchUrl: json['batchUrl'] as String?,
  paused: json['paused'] as String?,
  lastPublishedSha: json['lastPublishedSha'] as String?,
  lastCandidateAt: json['lastCandidateAt'] == null
      ? null
      : DateTime.parse(json['lastCandidateAt'] as String),
  rejections: (json['rejections'] as List<dynamic>?)
      ?.map((e) => Rejection.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$QueueStateToJson(QueueState instance) =>
    <String, dynamic>{
      'key': instance.key,
      'branch': instance.branch,
      'candidate': instance.candidate?.toJson(),
      'batchIid': instance.batchIid,
      'batchUrl': instance.batchUrl,
      'paused': instance.paused,
      'lastPublishedSha': instance.lastPublishedSha,
      'lastCandidateAt': instance.lastCandidateAt?.toIso8601String(),
      'groups': instance.groups,
      'rejections': instance.rejections.map((e) => e.toJson()).toList(),
    };
