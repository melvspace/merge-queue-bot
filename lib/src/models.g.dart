// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

MergeRequest _$MergeRequestFromJson(Map<String, dynamic> json) => MergeRequest(
  iid: (json['iid'] as num).toInt(),
  title: json['title'] as String,
  url: json['url'] as String,
  sha: json['sha'] as String,
  targetBranch: json['target'] as String,
  sourceBranch: json['source'] as String,
  state: json['state'] as String,
  draft: json['draft'] as bool,
  assignees: (json['assignees'] as List<dynamic>)
      .map((e) => (e as num).toInt())
      .toList(),
  authorName: json['authorName'] as String,
  authorEmail: json['authorEmail'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  mergeCommitSha: json['mergeCommitSha'] as String?,
  sourceProjectId: (json['sourceProjectId'] as num?)?.toInt(),
);

Map<String, dynamic> _$MergeRequestToJson(MergeRequest instance) =>
    <String, dynamic>{
      'iid': instance.iid,
      'title': instance.title,
      'url': instance.url,
      'sha': instance.sha,
      'target': instance.targetBranch,
      'source': instance.sourceBranch,
      'state': instance.state,
      'draft': instance.draft,
      'assignees': instance.assignees,
      'authorName': instance.authorName,
      'authorEmail': instance.authorEmail,
      'createdAt': instance.createdAt.toIso8601String(),
      'mergeCommitSha': instance.mergeCommitSha,
      'sourceProjectId': instance.sourceProjectId,
    };
