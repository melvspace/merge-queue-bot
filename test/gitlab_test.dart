import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:merge_queue_bot/src/gitlab.dart';
import 'package:merge_queue_bot/src/models.dart';
import 'package:test/test.dart';

const _token = 'test-service-account-secret';
const _marker = '<!-- merge-queue-bot -->';

Json _user({String? email = 'bot@example.test'}) => {
  'id': 7,
  'username': 'merge-bot',
  'name': 'Merge Bot',
  'email': email,
};

Json _project([Json changes = const {}]) => {
  'id': 1,
  'path_with_namespace': 'group/repository',
  'http_url_to_repo': 'https://gitlab.example.test/group/repository.git',
  'merge_method': 'ff',
  'squash_option': 'default_off',
  'automatic_rebase_enabled': false,
  'merge_pipelines_enabled': false,
  ...changes,
};

Json _mr({int iid = 12, Json changes = const {}}) => {
  'iid': iid,
  'title': 'Deliver change $iid',
  'web_url':
      'https://gitlab.example.test/group/repository/-/merge_requests/$iid',
  'sha': 'candidate-sha',
  'source_branch': 'feature/$iid',
  'target_branch': 'main',
  'source_project_id': 1,
  'target_project_id': 1,
  'state': 'opened',
  'draft': false,
  'assignees': [
    {'id': 7},
  ],
  'author': {'id': 19, 'username': 'contributor', 'name': 'Contributor'},
  'created_at': '2026-10-10T10:00:00Z',
  'merge_commit_sha': null,
  ...changes,
};

Json _batch([Json changes = const {}]) => _mr(
  iid: 33,
  changes: {
    'source_branch': 'merge-queue/main',
    'description': '$_marker\n\nBatch contents.',
    'author': _user(),
    ...changes,
  },
);

Json _pipeline(
  int id, {
  String sha = 'candidate-sha',
  String ref = 'merge-queue/main',
  String status = 'running',
}) => {'id': id, 'sha': sha, 'ref': ref, 'status': status};

http.Response _json(
  Object? value, {
  int status = 200,
  Map<String, String> headers = const {},
}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json', ...headers},
);

GitLab _gitlab(
  FutureOr<http.Response> Function(http.Request) respond, {
  Duration requestTimeout = const Duration(seconds: 30),
}) => GitLab(
  url: Uri.parse('https://gitlab.example.test/gitlab/'),
  token: _token,
  client: MockClient((request) async => respond(request)),
  requestTimeout: requestTimeout,
);

void main() {
  group('GitLab requests', () {
    test(
      'preserves an instance subpath and encodes namespaced project ids',
      () async {
        final api = _gitlab((request) {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            'https://gitlab.example.test/gitlab/api/v4/projects/group%2Frepository',
          );
          expect(request.headers['PRIVATE-TOKEN'], _token);
          expect(request.followRedirects, isFalse);

          return _json(_project());
        });
        addTearDown(api.close);

        final project = await api.project('group/repository');

        expect(project.id, 1);
        expect(project.path, 'group/repository');
      },
    );

    test('encodes complete branch names as one path parameter', () async {
      final api = _gitlab((request) {
        expect(
          request.url.toString(),
          'https://gitlab.example.test/gitlab/api/v4/projects/1/repository/branches/release%2F1+fix',
        );

        return _json({
          'commit': {'id': 'base-sha'},
        });
      });
      addTearDown(api.close);

      expect(await api.branchSha(1, 'release/1+fix'), 'base-sha');
    });

    test(
      'caches the service account and tolerates a missing private email',
      () async {
        var calls = 0;
        final api = _gitlab((request) {
          calls++;

          return _json(_user(email: null));
        });
        addTearDown(api.close);

        final user = await api.currentUser();

        expect(user.email, '7-merge-bot@users.noreply.gitlab.example.test');
        expect(identical(await api.currentUser(), user), isTrue);
        expect(calls, 1);
      },
    );

    for (final settings in [
      {'merge_method': 'merge'},
      {'squash_option': 'always'},
      {'squash_option': 'unknown'},
      {'automatic_rebase_enabled': true},
      {'merge_pipelines_enabled': true},
    ]) {
      test('rejects incompatible project settings $settings', () async {
        final api = _gitlab((request) => _json(_project(settings)));
        addTearDown(api.close);

        expect((await api.project('1')).validate, throwsStateError);
      });
    }

    for (final option in ['never', 'default_off', 'default_on']) {
      test(
        'accepts supported optional/disabled squash policy $option',
        () async {
          final api = _gitlab(
            (request) => _json(_project({'squash_option': option})),
          );
          addTearDown(api.close);

          expect((await api.project('1')).squashOption, option);
        },
      );
    }

    test(
      'accepts older project responses without automatic rebase field',
      () async {
        final data = _project()..remove('automatic_rebase_enabled');
        final api = _gitlab((request) => _json(data));
        addTearDown(api.close);

        expect((await api.project('1')).automaticRebase, isFalse);
      },
    );

    test('returns status codes without server bodies or credentials', () async {
      final api = _gitlab(
        (request) => _json({
          'message': 'Server reflected $_token and private content',
        }, status: 403),
      );
      addTearDown(api.close);

      await expectLater(
        api.currentUser(),
        throwsA(
          isA<RemoteException>()
              .having((error) => error.statusCode, 'HTTP status', 403)
              .having(
                (error) => error.toString(),
                'safe message',
                allOf(
                  isNot(contains(_token)),
                  isNot(contains('private content')),
                ),
              ),
        ),
      );
    });

    test('rejects redirects without following them', () async {
      var calls = 0;
      final api = _gitlab((request) {
        calls++;

        expect(request.followRedirects, isFalse);

        return http.Response(
          _token,
          302,
          headers: {'location': 'https://foreign.example.test/collect'},
        );
      });
      addTearDown(api.close);

      await expectLater(
        api.currentUser(),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.statusCode,
            'HTTP status',
            302,
          ),
        ),
      );
      expect(calls, 1);
    });

    test('sanitizes transport errors and timeout failures', () async {
      final failed = _gitlab((request) => throw http.ClientException(_token));
      addTearDown(failed.close);

      await expectLater(
        failed.currentUser(),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.toString(),
            'safe message',
            isNot(contains(_token)),
          ),
        ),
      );

      final timedOut = _gitlab(
        (request) => Completer<http.Response>().future,
        requestTimeout: const Duration(milliseconds: 1),
      );
      addTearDown(timedOut.close);

      await expectLater(
        timedOut.currentUser(),
        throwsA(
          isA<RemoteException>().having(
            (error) => error.toString(),
            'timeout',
            contains('timed out'),
          ),
        ),
      );
    });

    for (final payload in ['not json $_token', '[]', '{"id":"7"}']) {
      test(
        'rejects malformed user JSON safely: ${payload.length} chars',
        () async {
          final api = _gitlab((request) => http.Response(payload, 200));
          addTearDown(api.close);

          await expectLater(
            api.currentUser(),
            throwsA(
              isA<RemoteException>().having(
                (error) => error.toString(),
                'safe message',
                isNot(contains(_token)),
              ),
            ),
          );
        },
      );
    }
  });

  group('merge request monitoring', () {
    test(
      'paginates all open MRs and retains unassigned author identity',
      () async {
        final pages = <String?>[];
        final api = _gitlab((request) {
          expect(request.url.queryParameters['target_branch'], 'release/next');
          expect(request.url.queryParameters['scope'], 'all');
          expect(
            request.url.queryParameters.containsKey('assignee_id'),
            isFalse,
          );

          pages.add(request.url.queryParameters['page']);

          if (pages.length == 1) {
            return _json(
              [
                _mr(
                  changes: {
                    'target_branch': 'release/next',
                    'assignees': <Object?>[],
                  },
                ),
              ],
              headers: {'x-next-page': '2'},
            );
          }

          return _json(
            [
              _mr(
                iid: 13,
                changes: {
                  'target_branch': 'release/next',
                  'author': {
                    'id': 20,
                    'username': 'alice',
                    'name': 'Alice',
                    'public_email': 'alice@example.test',
                  },
                },
              ),
              _mr(iid: 14, changes: {'target_branch': 'other'}),
            ],
            headers: {'x-next-page': ''},
          );
        });
        addTearDown(api.close);

        final requests = await api.openMergeRequests(1, 'release/next');

        expect(pages, ['1', '2']);
        expect(requests.map((mr) => mr.iid), [12, 13]);
        expect(requests.first.assignees, isEmpty);
        expect(requests.first.authorName, 'Contributor');
        expect(
          requests.first.authorEmail,
          '19-contributor@users.noreply.gitlab.example.test',
        );
        expect(requests.last.authorEmail, 'alice@example.test');
      },
    );

    test('reads MR iid, state, draft and merge commit SHA', () async {
      final api = _gitlab((request) {
        expect(request.url.path, endsWith('/merge_requests/12'));

        return _json(
          _mr(
            changes: {
              'state': 'merged',
              'draft': true,
              'merge_commit_sha': 'landed-sha',
              'source_project_id': 52,
            },
          ),
        );
      });
      addTearDown(api.close);

      final request = await api.mergeRequest(1, 12);

      expect(request.state, 'merged');
      expect(request.draft, isTrue);
      expect(request.mergeCommitSha, 'landed-sha');
      expect(request.sourceProjectId, 52);
      expect(MergeRequest.fromJson(request.toJson()).sourceProjectId, 52);

      final legacy = request.toJson()..remove('sourceProjectId');

      expect(MergeRequest.fromJson(legacy).sourceProjectId, isNull);
      expect(request.createdAt, DateTime.utc(2026, 10, 10, 10));
    });
  });

  group('batch ownership and landing', () {
    test('finds a marked bot-owned MR before creating another', () async {
      final methods = <String>[];
      final api = _gitlab((request) {
        methods.add(request.method);

        if (request.url.path.endsWith('/user')) return _json(_user());

        expect(
          request.url.queryParameters['source_branch'],
          'merge-queue/main',
        );
        expect(
          request.url.queryParameters.containsKey('target_branch'),
          isFalse,
        );

        return _json([
          _batch({'detailed_merge_status': 'checking'}),
        ]);
      });
      addTearDown(api.close);

      final batch = await api.ensureBatch(
        1,
        'merge-queue/main',
        'main',
        'Contents',
      );

      expect(batch.iid, 33);
      expect(batch.sourceBranch, 'merge-queue/main');
      expect(batch.targetBranch, 'main');
      expect(batch.detailedMergeStatus, 'checking');
      expect(methods, everyElement('GET'));
    });

    for (final changes in [
      {'description': 'A human MR'},
      {
        'author': {'id': 19},
      },
      {'target_branch': 'other'},
      {'source_project_id': 2},
    ]) {
      test('refuses an unsafe existing branch MR: $changes', () async {
        final api = _gitlab((request) {
          expect(request.method, 'GET');

          if (request.url.path.endsWith('/user')) return _json(_user());

          return _json([_batch(changes)]);
        });
        addTearDown(api.close);

        await expectLater(
          api.ensureBatch(1, 'merge-queue/main', 'main', 'Contents'),
          throwsStateError,
        );
      });
    }

    test('findBatch paginates and rejects duplicate open queue MRs', () async {
      final api = _gitlab((request) {
        if (request.url.path.endsWith('/user')) return _json(_user());

        if (request.url.queryParameters['page'] == '1') {
          return _json([_batch()], headers: {'x-next-page': '2'});
        }

        return _json([
          _batch({'iid': 34}),
        ]);
      });
      addTearDown(api.close);

      await expectLater(
        api.findBatch(1, 'merge-queue/main', 'main'),
        throwsStateError,
      );
    });

    test(
      'creates a nonsquashing batch with ownership marker and keeps branch',
      () async {
        Json? body;
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          if (request.method == 'GET') return _json(<Object?>[]);

          expect(request.method, 'POST');
          expect(request.headers['content-type'], contains('application/json'));

          body = jsonDecode(request.body) as Json;

          return _json(_batch(), status: 201);
        });
        addTearDown(api.close);

        await api.ensureBatch(1, 'merge-queue/main', 'main', 'Contents');

        expect(body, containsPair('squash', false));
        expect(body, containsPair('remove_source_branch', false));
        expect(body, containsPair('source_branch', 'merge-queue/main'));
        expect(body, containsPair('target_branch', 'main'));
        expect(body!['description'], '$_marker\n\nContents');
      },
    );

    test(
      'updates batch description without removing its ownership marker',
      () async {
        Json? body;
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          if (request.method == 'GET') return _json(_batch());

          body = jsonDecode(request.body) as Json;

          return _json(_batch());
        });
        addTearDown(api.close);

        await api.describeBatch(1, 33, 'New contents');

        expect(body!['description'], '$_marker\n\nNew contents');
        expect(body!['squash'], isFalse);
        expect(body!['remove_source_branch'], isFalse);
      },
    );

    test(
      'merges with the exact head guard and no auto merge or extra squash',
      () async {
        Json? body;
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          if (request.method == 'GET') return _json(_batch());

          expect(request.method, 'PUT');
          expect(request.url.path, endsWith('/merge_requests/33/merge'));

          body = jsonDecode(request.body) as Json;

          return _json(
            _batch({'state': 'merged', 'merge_commit_sha': 'candidate-sha'}),
          );
        });
        addTearDown(api.close);

        await api.mergeBatch(1, 33, 'candidate-sha');

        expect(body, {
          'sha': 'candidate-sha',
          'squash': false,
          'should_remove_source_branch': false,
          'auto_merge': false,
        });

        final batch = await api.batch(1, 33);

        expect(batch.sha, 'candidate-sha');
      },
    );
  });

  group('pipeline discovery', () {
    test(
      'unions paginated branch and MR pipelines only for the candidate',
      () async {
        final visited = <String>[];
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          final path = request.url.path;

          if (path.endsWith('/merge_requests/33')) return _json(_batch());

          visited.add('$path?page=${request.url.queryParameters['page']}');

          if (path.endsWith('/merge_requests/33/pipelines')) {
            if (request.url.queryParameters['page'] == '1') {
              return _json(
                [
                  _pipeline(2),
                  _pipeline(3, ref: 'refs/merge-requests/33/head'),
                ],
                headers: {'x-next-page': '2'},
              );
            }

            return _json([
              _pipeline(4, sha: 'obsolete-sha'),
              _pipeline(5, sha: 'synthetic-merged-result'),
              _pipeline(6, ref: 'refs/merge-requests/33/head'),
            ]);
          }

          expect(request.url.queryParameters['sha'], 'candidate-sha');
          expect(request.url.queryParameters['ref'], 'merge-queue/main');

          if (request.url.queryParameters['page'] == '1') {
            return _json(
              [
                _pipeline(1),
                _pipeline(8, ref: 'other-branch'),
                _pipeline(9, sha: 'obsolete-sha'),
              ],
              headers: {'x-next-page': '2'},
            );
          }

          return _json([_pipeline(2)]);
        });
        addTearDown(api.close);

        final pipelines = await api.pipelines(1, 33, 'candidate-sha');

        expect(pipelines.map((pipeline) => pipeline.id), [1, 2, 3, 6]);
        expect(visited, hasLength(4));
      },
    );

    test('reads pipeline-level status without triggering CI', () async {
      final api = _gitlab((request) {
        expect(request.method, 'GET');
        expect(request.url.path, endsWith('/projects/1/pipelines/99'));

        return _json(_pipeline(99, status: 'failed'));
      });
      addTearDown(api.close);

      final pipeline = await api.pipeline(1, 99);

      expect(pipeline.status, 'failed');
      expect(pipeline.sha, 'candidate-sha');
    });
  });

  group('bookkeeping', () {
    test(
      'commentOnce finds a previous attempt on a later notes page',
      () async {
        var writes = 0;
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          if (request.method == 'POST') {
            writes++;

            return _json({'id': 42}, status: 201);
          }

          if (request.url.queryParameters['page'] == '1') {
            return _json(
              [
                {
                  'body': 'Other comment',
                  'author': {'id': 19},
                },
              ],
              headers: {'x-next-page': '2'},
            );
          }

          return _json([
            {
              'body': 'Delivered.\n\n<!-- merge-queue-bot:landed:abc -->',
              'author': _user(),
            },
          ]);
        });
        addTearDown(api.close);

        await api.commentOnce(1, 12, 'landed:abc', 'Delivered.');

        expect(writes, 0);
      },
    );

    test(
      'commentOnce writes a stable marker and repeated calls do not duplicate',
      () async {
        final notes = <Json>[];
        var writes = 0;
        final api = _gitlab((request) {
          if (request.url.path.endsWith('/user')) return _json(_user());

          if (request.method == 'GET') return _json(notes);

          final note = jsonDecode(request.body) as Json;
          note['author'] = _user();
          notes.add(note);
          writes++;

          return _json({'id': 42}, status: 201);
        });
        addTearDown(api.close);

        await api.commentOnce(1, 12, 'landed:abc', 'Delivered.');
        await api.commentOnce(1, 12, 'landed:abc', 'Delivered.');

        expect(writes, 1);
        expect(
          notes.single['body'],
          'Delivered.\n\n<!-- merge-queue-bot:landed:abc -->',
        );
      },
    );

    test('commentOnce ignores a marker copied by a different author', () async {
      var writes = 0;
      final api = _gitlab((request) {
        if (request.url.path.endsWith('/user')) return _json(_user());

        if (request.method == 'GET') {
          return _json([
            {
              'body': '<!-- merge-queue-bot:landed:abc -->',
              'author': {'id': 19},
            },
          ]);
        }

        writes++;

        return _json({'id': 42}, status: 201);
      });
      addTearDown(api.close);

      await api.commentOnce(1, 12, 'landed:abc', 'Delivered.');

      expect(writes, 1);
    });

    test(
      'sends complete assignee arrays including empty, close and reopen',
      () async {
        final bodies = <Json>[];
        final api = _gitlab((request) {
          expect(request.method, 'PUT');
          expect(request.url.path, endsWith('/merge_requests/12'));

          bodies.add(jsonDecode(request.body) as Json);

          return _json({'iid': 12});
        });
        addTearDown(api.close);

        await api.setAssignees(1, 12, [19, 20]);
        await api.setAssignees(1, 12, []);
        await api.closeMergeRequest(1, 12);
        await api.reopenMergeRequest(1, 12);

        expect(bodies, [
          {
            'assignee_ids': [19, 20],
          },
          {'assignee_ids': <int>[]},
          {'state_event': 'close'},
          {'state_event': 'reopen'},
        ]);
      },
    );
  });

  group('pagination safety', () {
    test(
      'follows same-resource Link next URLs when page headers are absent',
      () async {
        final pages = <String?>[];
        final api = _gitlab((request) {
          pages.add(request.url.queryParameters['page']);

          if (pages.length == 1) {
            final next = request.url.replace(
              queryParameters: {...request.url.queryParameters, 'page': '2'},
            );

            return _json([_mr()], headers: {'link': '<$next>; rel="next"'});
          }

          return _json([_mr(iid: 13)]);
        });
        addTearDown(api.close);

        final requests = await api.openMergeRequests(1, 'main');

        expect(requests.map((mr) => mr.iid), [12, 13]);
        expect(pages, ['1', '2']);
      },
    );

    test('does not send the token to a foreign pagination URL', () async {
      var calls = 0;
      final api = _gitlab((request) {
        calls++;

        return _json(
          [_mr()],
          headers: {
            'link': '<https://foreign.example.test/collect?page=2>; rel="next"',
          },
        );
      });
      addTearDown(api.close);

      await expectLater(
        api.openMergeRequests(1, 'main'),
        throwsA(isA<RemoteException>()),
      );
      expect(calls, 1);
    });

    test('rejects repeated pagination URLs instead of looping', () async {
      var calls = 0;
      final api = _gitlab((request) {
        calls++;

        return _json([_mr()], headers: {'x-next-page': '1'});
      });
      addTearDown(api.close);

      await expectLater(
        api.openMergeRequests(1, 'main'),
        throwsA(isA<RemoteException>()),
      );
      expect(calls, 1);
    });
  });
}
