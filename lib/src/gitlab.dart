import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'ports.dart';

/// GitLab REST transport. It never follows redirects with the service token.
class GitLab({
  required Uri url,
  required String token,
  http.Client? client,
  Duration requestTimeout = const Duration(seconds: 30),
}) implements Hosting {
  static const _batchMarker = '<!-- merge-queue-bot -->';

  final Uri _url = url;
  final String _token = token;
  final http.Client _client = client ?? http.Client();
  final Duration _requestTimeout = requestTimeout;
  BotUser? _user;

  this {
    if (!['https', 'http'].contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw ArgumentError('GitLab URL must be an HTTP(S) instance URL.');
    }

    if (token.trim().isEmpty || requestTimeout <= Duration.zero) {
      throw ArgumentError('A token and positive request timeout are required.');
    }
  }

  @override
  Future<BotUser> currentUser() async {
    final cached = _user;

    if (cached != null) return cached;

    final user = await _get(['user']);
    final result = BotUser(
      _integer(user['id']),
      _name(user),
      _email(user, allowPrivate: true),
    );
    _user = result;

    return result;
  }

  @override
  Future<Project> project(String id) async {
    final data = await _get(['projects', id]);
    final result = Project(
      id: _integer(data['id']),
      path: _string(data['path_with_namespace']),
      cloneUrl: _string(data['http_url_to_repo']),
      mergeMethod: _string(data['merge_method']),
      squashOption: _string(data['squash_option']),
      // Exposed by GET /projects/:id since GitLab 19.4. Older responses omit
      // this field; automatic rebase must remain disabled on those instances.
      automaticRebase: _boolean(data['automatic_rebase_enabled'] ?? false),
      mergedResultsPipelines: _boolean(
        data['merge_pipelines_enabled'] ?? false,
      ),
    );
    result.validate();

    return result;
  }

  @override
  Future<String> branchSha(int projectId, String branch) async {
    final data = await _get([
      'projects',
      '$projectId',
      'repository',
      'branches',
      branch,
    ]);

    return _string(_object(data['commit'])['id']);
  }

  @override
  Future<List<MergeRequest>> openMergeRequests(
    int projectId,
    String target,
  ) async {
    final data = await _list(_mergeRequests(projectId), {
      'state': 'opened',
      'target_branch': target,
      'scope': 'all',
      'order_by': 'created_at',
      'sort': 'asc',
    });

    // Include unassigned MRs so polling can remember previous assignees.
    return data
        .map(_mergeRequest)
        .where((mr) => mr.state == 'opened' && mr.targetBranch == target)
        .toList();
  }

  @override
  Future<MergeRequest> mergeRequest(int projectId, int iid) async =>
      _mergeRequest(await _get(_mergeRequestPath(projectId, iid)));

  @override
  Future<BatchRef?> findBatch(
    int projectId,
    String branch,
    String target,
  ) async {
    // Do not filter by target: an existing MR with the same source branch and a
    // different target must prevent the caller from overwriting that branch.
    final requests = await _list(_mergeRequests(projectId), {
      'state': 'opened',
      'source_branch': branch,
      'scope': 'all',
    });
    BatchRef? result;

    for (final request in requests) {
      if (request['state'] != 'opened' || request['source_branch'] != branch) {
        continue;
      }

      await _ownedBatch(request, projectId, branch: branch, target: target);

      if (result != null) {
        throw StateError('Multiple open merge requests use the queue branch.');
      }

      result = _batchRef(request);
    }

    return result;
  }

  @override
  Future<BatchRef> batch(int projectId, int iid) async {
    final data = await _get(_mergeRequestPath(projectId, iid));
    await _ownedBatch(data, projectId);

    return _batchRef(data);
  }

  @override
  Future<BatchRef> ensureBatch(
    int projectId,
    String branch,
    String target,
    String description,
  ) async {
    final existing = await findBatch(projectId, branch, target);

    if (existing != null) return existing;

    final data = await _write('POST', _mergeRequests(projectId), {
      'source_branch': branch,
      'target_branch': target,
      'title': 'Merge queue: $target',
      'description': _description(description),
      'squash': false,
      'remove_source_branch': false,
    });
    await _ownedBatch(data, projectId, branch: branch, target: target);

    return _batchRef(data);
  }

  @override
  Future<void> describeBatch(int projectId, int iid, String description) async {
    await batch(projectId, iid);

    await _write('PUT', _mergeRequestPath(projectId, iid), {
      'description': _description(description),
      'squash': false,
      'remove_source_branch': false,
    });
  }

  @override
  Future<List<Pipeline>> pipelines(
    int projectId,
    int batchIid,
    String sha,
  ) async {
    final request = await _get(_mergeRequestPath(projectId, batchIid));
    await _ownedBatch(request, projectId);

    final branch = _string(request['source_branch']);
    final branchPipelines = await _list(
      ['projects', '$projectId', 'pipelines'],
      {'sha': sha, 'ref': branch},
    );
    final mrPipelines = await _list([
      ..._mergeRequestPath(projectId, batchIid),
      'pipelines',
    ]);
    final result = <int, Pipeline>{};

    for (final data in branchPipelines) {
      // The ref check also excludes pipelines for another branch at this SHA.
      if (data['sha'] == sha && data['ref'] == branch) {
        final pipeline = _pipeline(data);
        result[pipeline.id] = pipeline;
      }
    }

    for (final data in mrPipelines) {
      // Merged-results pipelines use synthetic SHAs and are intentionally not
      // eligible: this adapter only observes the exact published candidate.
      if (data['sha'] == sha) {
        final pipeline = _pipeline(data);
        result[pipeline.id] = pipeline;
      }
    }

    return result.values.toList();
  }

  @override
  Future<Pipeline> pipeline(int projectId, int pipelineId) async => _pipeline(
    await _get(['projects', '$projectId', 'pipelines', '$pipelineId']),
  );

  @override
  Future<void> mergeBatch(int projectId, int iid, String sha) async {
    await batch(projectId, iid);

    await _write(
      'PUT',
      [..._mergeRequestPath(projectId, iid), 'merge'],
      {
        'sha': sha,
        'squash': false,
        'should_remove_source_branch': false,
        'auto_merge': false,
      },
    );
  }

  @override
  Future<void> commentOnce(
    int projectId,
    int iid,
    String marker,
    String body,
  ) async {
    if (marker.isEmpty || marker.contains('-->')) {
      throw ArgumentError('A stable comment marker is required.');
    }

    final token = '<!-- merge-queue-bot:$marker -->';
    final path = [..._mergeRequestPath(projectId, iid), 'notes'];
    final bot = await currentUser();
    final notes = await _list(path);

    if (notes.any(
      (note) =>
          _object(note['author'])['id'] == bot.id &&
          _string(note['body']).contains(token),
    )) {
      return;
    }

    await _write('POST', path, {'body': '${body.trimRight()}\n\n$token'});
  }

  @override
  Future<void> setAssignees(int projectId, int iid, List<int> assignees) async {
    await _write('PUT', _mergeRequestPath(projectId, iid), {
      'assignee_ids': assignees,
    });
  }

  @override
  Future<void> closeMergeRequest(int projectId, int iid) async {
    await _write('PUT', _mergeRequestPath(projectId, iid), {
      'state_event': 'close',
    });
  }

  @override
  Future<void> reopenMergeRequest(int projectId, int iid) async {
    await _write('PUT', _mergeRequestPath(projectId, iid), {
      'state_event': 'reopen',
    });
  }

  @override
  void close() => _client.close();

  Future<void> _ownedBatch(
    Json data,
    int projectId, {
    String? branch,
    String? target,
  }) async {
    final bot = await currentUser();

    if (_object(data['author'])['id'] != bot.id ||
        !(_nullableString(data['description']) ?? '').contains(_batchMarker) ||
        (data['source_project_id'] != null &&
            data['source_project_id'] != projectId) ||
        (data['target_project_id'] != null &&
            data['target_project_id'] != projectId) ||
        (branch != null && data['source_branch'] != branch) ||
        (target != null && data['target_branch'] != target)) {
      throw StateError(
        'The queue merge request is not owned by this bot or '
        'does not match its configured source and target.',
      );
    }
  }

  String _description(String value) =>
      value.contains(_batchMarker) ? value : '$_batchMarker\n\n$value';

  MergeRequest _mergeRequest(Json data) {
    final author = _object(data['author']);
    final assignees =
        data['assignees'] ?? [if (data['assignee'] != null) data['assignee']];

    return MergeRequest(
      iid: _integer(data['iid']),
      title: _string(data['title']),
      url: _string(data['web_url']),
      sha: _string(data['sha']),
      targetBranch: _string(data['target_branch']),
      sourceBranch: _string(data['source_branch']),
      state: _string(data['state']),
      draft: _boolean(data['draft'] ?? data['work_in_progress'] ?? false),
      assignees: _array(assignees)
          .map((value) => _integer(_object(value)['id']))
          .toList(),
      authorName: _name(author),
      authorEmail: _email(author),
      createdAt: _date(data['created_at']),
      mergeCommitSha: _nullableString(data['merge_commit_sha']),
      sourceProjectId: data['source_project_id'] == null
          ? null
          : _integer(data['source_project_id']),
    );
  }

  BatchRef _batchRef(Json data) => BatchRef(
    _integer(data['iid']),
    _string(data['web_url']),
    _string(data['state']),
    _string(data['sha']),
    mergeCommitSha: _nullableString(data['merge_commit_sha']),
    sourceBranch: _string(data['source_branch']),
    targetBranch: _string(data['target_branch']),
    detailedMergeStatus: _nullableString(data['detailed_merge_status']),
  );

  Pipeline _pipeline(Json data) => Pipeline(
    _integer(data['id']),
    _string(data['sha']),
    _string(data['status']),
  );

  String _name(Json user) {
    final name = _nullableString(user['name']);

    return name != null && name.trim().isNotEmpty
        ? name
        : _string(user['username']);
  }

  String _email(Json user, {bool allowPrivate = false}) {
    final email = _nullableString(
      (allowPrivate ? user['email'] : null) ?? user['public_email'],
    );

    if (email != null && email.trim().isNotEmpty) return email;

    return '${_integer(user['id'])}-${_string(user['username'])}'
        '@users.noreply.${_url.host}';
  }

  List<String> _mergeRequests(int projectId) => [
    'projects',
    '$projectId',
    'merge_requests',
  ];

  List<String> _mergeRequestPath(int projectId, int iid) => [
    ..._mergeRequests(projectId),
    '$iid',
  ];

  Uri _uri(List<String> path, [Map<String, String> query = const {}]) =>
      _url.replace(
        pathSegments: [
          ..._url.pathSegments.where((segment) => segment.isNotEmpty),
          'api',
          'v4',
          ...path,
        ],
        queryParameters: query.isEmpty ? null : query,
      );

  Future<Json> _get(List<String> path) async =>
      _object(_decode(await _request('GET', _uri(path))));

  Future<Json> _write(String method, List<String> path, Json body) async {
    final response = await _request(method, _uri(path), body);

    return response.body.isEmpty
        ? <String, dynamic>{}
        : _object(_decode(response));
  }

  Future<List<Json>> _list(
    List<String> path, [
    Map<String, String> query = const {},
  ]) async {
    var uri = _uri(path, {...query, 'per_page': '100', 'page': '1'});
    final visited = <Uri>{};
    final result = <Json>[];

    while (true) {
      if (!visited.add(uri)) {
        throw const RemoteException('GitLab returned a pagination loop.');
      }

      final response = await _request('GET', uri);
      final page = _array(_decode(response)).map(_object).toList();
      result.addAll(page);

      final next = _nextPage(uri, response, page.length);

      if (next == null) return result;

      uri = next;
    }
  }

  Uri? _nextPage(Uri current, http.Response response, int count) {
    final link = response.headers['link'];

    if (link != null) {
      for (final part in link.split(',')) {
        if (!RegExp(r';\s*rel\s*=\s*"?next"?(?:\s*;|\s*$)').hasMatch(part)) {
          continue;
        }

        final match = RegExp(r'^\s*<([^>]+)>').firstMatch(part);
        final parsed = match == null ? null : Uri.tryParse(match.group(1)!);
        final next = parsed == null ? null : current.resolveUri(parsed);

        if (next == null ||
            next.scheme != current.scheme ||
            next.host != current.host ||
            next.port != current.port ||
            next.userInfo.isNotEmpty ||
            next.path != current.path ||
            next.hasFragment) {
          throw const RemoteException(
            'GitLab returned an unsafe pagination link.',
          );
        }

        return next;
      }
    }

    final nextPage = response.headers['x-next-page'];

    if (nextPage != null) {
      if (nextPage.isEmpty) return null;

      final number = int.tryParse(nextPage);

      if (number == null || number < 1) {
        throw const RemoteException('GitLab returned invalid pagination.');
      }

      return current.replace(
        queryParameters: {...current.queryParameters, 'page': '$number'},
      );
    }

    if (link != null || count < 100) return null;

    final number = int.parse(current.queryParameters['page'] ?? '1');

    return current.replace(
      queryParameters: {...current.queryParameters, 'page': '${number + 1}'},
    );
  }

  Future<http.Response> _request(String method, Uri uri, [Json? body]) async {
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..headers['PRIVATE-TOKEN'] = _token
      ..headers['Accept'] = 'application/json';

    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;

    try {
      response = await (() async {
        final streamed = await _client.send(request);

        return http.Response.fromStream(streamed);
      })().timeout(_requestTimeout);
    } on TimeoutException {
      throw const RemoteException(
        'GitLab request timed out; reconcile before retrying.',
      );
    } catch (_) {
      // Transport error messages may contain credentials or response bodies.
      throw const RemoteException(
        'GitLab transport failed; reconcile before retrying.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RemoteException(
        'GitLab $method request failed with HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }

    return response;
  }

  Object? _decode(http.Response response) {
    try {
      return jsonDecode(response.body);
    } on FormatException {
      throw const RemoteException('GitLab returned invalid JSON.');
    }
  }

  Json _object(Object? value) {
    if (value is Json) return value;

    throw const RemoteException('GitLab returned an invalid object.');
  }

  List<dynamic> _array(Object? value) {
    if (value is List<dynamic>) return value;

    throw const RemoteException('GitLab returned an invalid list.');
  }

  int _integer(Object? value) {
    if (value is int) return value;

    throw const RemoteException('GitLab returned an invalid integer.');
  }

  String _string(Object? value) {
    if (value is String) return value;

    throw const RemoteException('GitLab returned an invalid string.');
  }

  String? _nullableString(Object? value) =>
      value == null ? null : _string(value);

  bool _boolean(Object? value) {
    if (value is bool) return value;

    throw const RemoteException('GitLab returned an invalid boolean.');
  }

  DateTime _date(Object? value) {
    final result = DateTime.tryParse(_string(value));

    if (result != null) return result;

    throw const RemoteException('GitLab returned an invalid timestamp.');
  }
}
