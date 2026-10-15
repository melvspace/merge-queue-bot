import 'models.dart';

class Candidate {
  final String baseSha;
  final List<MergeRequest> members;
  final DateTime createdAt;
  String phase;
  String? sha;
  String? expectedRemoteSha;
  DateTime? startedAt;
  List<int>? pipelineIds;
  final List<int> finalized;
  final List<int> closing;

  Candidate({
    required this.baseSha,
    required this.members,
    required this.createdAt,
    this.phase = 'assembling',
    this.sha,
    this.expectedRemoteSha,
    this.startedAt,
    this.pipelineIds,
    List<int>? finalized,
    List<int>? closing,
  }) : finalized = finalized ?? [],
       closing = closing ?? [];

  Json toJson() => {
    'baseSha': baseSha,
    'members': members.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'phase': phase,
    'sha': sha,
    'expectedRemoteSha': expectedRemoteSha,
    'startedAt': startedAt?.toIso8601String(),
    'pipelineIds': pipelineIds,
    'finalized': finalized,
    'closing': closing,
  };

  factory Candidate.fromJson(Json j) => Candidate(
    baseSha: j['baseSha'] as String,
    members: (j['members'] as List)
        .map((m) => MergeRequest.fromJson(Map<String, dynamic>.from(m as Map)))
        .toList(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    phase: j['phase'] as String,
    sha: j['sha'] as String?,
    expectedRemoteSha: j['expectedRemoteSha'] as String?,
    startedAt: j['startedAt'] == null
        ? null
        : DateTime.parse(j['startedAt'] as String),
    pipelineIds: (j['pipelineIds'] as List?)?.cast<int>(),
    finalized: (j['finalized'] as List).cast<int>(),
    closing: (j['closing'] as List? ?? []).cast<int>(),
  );
}

class Rejection {
  final MergeRequest member;
  final String reason;
  final String marker;
  final List<int> previousAssignees;
  final bool deliveredUpdate;
  Rejection(
    this.member,
    this.reason,
    this.marker,
    this.previousAssignees, {
    this.deliveredUpdate = false,
  });
  Json toJson() => {
    'member': member.toJson(),
    'reason': reason,
    'marker': marker,
    'previousAssignees': previousAssignees,
    'deliveredUpdate': deliveredUpdate,
  };
  factory Rejection.fromJson(Json j) => Rejection(
    MergeRequest.fromJson(Map<String, dynamic>.from(j['member'] as Map)),
    j['reason'] as String,
    j['marker'] as String,
    (j['previousAssignees'] as List).cast<int>(),
    deliveredUpdate: j['deliveredUpdate'] as bool? ?? false,
  );
}

class QueueState {
  final String key;
  final String branch;
  List<List<int>> groups;
  Candidate? candidate;
  int? batchIid;
  String? batchUrl;
  String? paused;
  String? lastPublishedSha;
  DateTime? lastCandidateAt;
  final List<Rejection> rejections;
  QueueState({
    required this.key,
    required this.branch,
    List<List<int>>? groups,
    this.candidate,
    this.batchIid,
    this.batchUrl,
    this.paused,
    this.lastPublishedSha,
    this.lastCandidateAt,
    List<Rejection>? rejections,
  }) : groups = groups ?? [],
       rejections = rejections ?? [];
  Json toJson() => {
    'key': key,
    'branch': branch,
    'groups': groups,
    'candidate': candidate?.toJson(),
    'batchIid': batchIid,
    'batchUrl': batchUrl,
    'paused': paused,
    'lastPublishedSha': lastPublishedSha,
    'lastCandidateAt': lastCandidateAt?.toIso8601String(),
    'rejections': rejections.map((r) => r.toJson()).toList(),
  };
  factory QueueState.fromJson(Json j) => QueueState(
    key: j['key'] as String,
    branch: j['branch'] as String,
    groups: (j['groups'] as List).map((g) => (g as List).cast<int>()).toList(),
    candidate: j['candidate'] == null
        ? null
        : Candidate.fromJson(Map<String, dynamic>.from(j['candidate'] as Map)),
    batchIid: j['batchIid'] as int?,
    batchUrl: j['batchUrl'] as String?,
    paused: j['paused'] as String?,
    lastPublishedSha: j['lastPublishedSha'] as String?,
    lastCandidateAt: j['lastCandidateAt'] == null
        ? null
        : DateTime.parse(j['lastCandidateAt'] as String),
    rejections: (j['rejections'] as List)
        .map((r) => Rejection.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );
}
