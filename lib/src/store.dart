import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'state.dart';

class const QueueEntry(final MergeRequest mr, final DateTime enqueuedAt);

/// Whole queue snapshots keep state transitions atomic without an ORM.
class Store(String path) {
  final Database _db = _open(path);

  this {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA synchronous = FULL');
    _db.execute('PRAGMA busy_timeout = 5000');

    final version =
        _db.select('PRAGMA user_version').first['user_version'] as int;

    if (version > 1) {
      throw StateError('Database schema is newer than this bot.');
    }

    _db.execute('''CREATE TABLE IF NOT EXISTS queues (
      key TEXT PRIMARY KEY, state TEXT NOT NULL)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS metadata (
      key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
    _db.execute('''CREATE TABLE IF NOT EXISTS observations (
      queue TEXT NOT NULL, iid INTEGER NOT NULL, snapshot TEXT NOT NULL,
      assigned INTEGER NOT NULL, enqueued_at TEXT,
      previous_assignees TEXT NOT NULL, suppressed INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(queue, iid))''');
    _db.execute('PRAGMA user_version = 1');
  }

  static Database _open(String path) {
    if (path != ':memory:') File(path).parent.createSync(recursive: true);

    return sqlite3.open(path);
  }

  void bindIdentity(String identity) {
    final rows = _db.select("SELECT value FROM metadata WHERE key='identity'");

    if (rows.isNotEmpty && rows.first['value'] != identity) {
      throw StateError(
        'This database belongs to another GitLab instance or bot account.',
      );
    }

    _db.execute(
      "INSERT OR IGNORE INTO metadata(key,value) VALUES ('identity',?)",
      [identity],
    );
  }

  QueueState load(String key, String branch) {
    final rows = _db.select('SELECT state FROM queues WHERE key = ?', [key]);

    return rows.isEmpty
        ? QueueState(key: key, branch: branch)
        : QueueState.fromJson(
            jsonDecode(rows.first['state'] as String) as Json,
          );
  }

  void save(QueueState state) => _db.execute(
    'INSERT OR REPLACE INTO queues(key,state) VALUES (?,?)',
    [state.key, jsonEncode(state.toJson())],
  );

  void observe(
    String queue,
    List<MergeRequest> items,
    int botId,
    DateTime now,
  ) {
    _db.execute('BEGIN IMMEDIATE');

    try {
      final seen = <int>{};

      for (final mr in items) {
        seen.add(mr.iid);

        final old = _db.select(
          'SELECT * FROM observations WHERE queue=? AND iid=?',
          [queue, mr.iid],
        );
        final assigned = mr.assignees.contains(botId);
        final row = old.firstOrNull;
        final wasAssigned = row?['assigned'] == 1;
        final previous = !assigned
            ? mr.assignees
            : row == null
            ? <int>[]
            : (jsonDecode(row['previous_assignees'] as String) as List)
                  .cast<int>();
        final enqueued = assigned
            ? (wasAssigned
                  ? row!['enqueued_at'] as String?
                  : now.toIso8601String())
            : null;
        final suppressed = assigned && wasAssigned && row?['suppressed'] == 1;

        _db.execute(
          '''INSERT OR REPLACE INTO observations
          (queue,iid,snapshot,assigned,enqueued_at,previous_assignees,suppressed)
          VALUES (?,?,?,?,?,?,?)''',
          [
            queue,
            mr.iid,
            jsonEncode(mr.toJson()),
            assigned ? 1 : 0,
            enqueued,
            jsonEncode(previous),
            suppressed ? 1 : 0,
          ],
        );
      }

      for (final row in _db.select(
        'SELECT iid FROM observations WHERE queue=?',
        [queue],
      )) {
        if (!seen.contains(row['iid'])) {
          _db.execute(
            'UPDATE observations SET assigned=0,enqueued_at=NULL,suppressed=0 '
            'WHERE queue=? AND iid=?',
            [queue, row['iid']],
          );
        }
      }

      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<QueueEntry> waiting(String queue, int botId, String target) {
    final result = _db
        .select(
          'SELECT snapshot,enqueued_at FROM observations '
          'WHERE queue=? AND assigned=1 AND suppressed=0 AND enqueued_at IS NOT NULL',
          [queue],
        )
        .map(
          (row) => QueueEntry(
            MergeRequest.fromJson(
              jsonDecode(row['snapshot'] as String) as Json,
            ),
            DateTime.parse(row['enqueued_at'] as String),
          ),
        )
        .where((e) => e.mr.eligible(botId, target))
        .toList();

    result.sort((a, b) {
      var order = a.enqueuedAt.compareTo(b.enqueuedAt);

      if (order == 0) order = a.mr.createdAt.compareTo(b.mr.createdAt);

      return order != 0 ? order : a.mr.iid.compareTo(b.mr.iid);
    });

    return result;
  }

  List<int> previousAssignees(String queue, int iid) {
    final rows = _db.select(
      'SELECT previous_assignees FROM observations '
      'WHERE queue=? AND iid=?',
      [queue, iid],
    );

    return rows.isEmpty
        ? []
        : (jsonDecode(rows.first['previous_assignees'] as String) as List)
              .cast<int>();
  }

  void suppress(String queue, int iid) => _db.execute(
    'UPDATE observations SET suppressed=1 WHERE queue=? AND iid=?',
    [queue, iid],
  );

  /// Our own unassignment is observable even if a human reassigns between polls.
  void markUnassigned(String queue, int iid) => _db.execute(
    'UPDATE observations SET assigned=0,enqueued_at=NULL,suppressed=0 '
    'WHERE queue=? AND iid=?',
    [queue, iid],
  );

  void close() => _db.close();
}
