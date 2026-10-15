import 'dart:io';
import 'package:yaml/yaml.dart';

class ProjectConfig {
  final String id;
  final List<String> targets;
  const ProjectConfig(this.id, this.targets);
}

class BotConfig {
  final Uri gitlabUrl;
  final String database;
  final String workDirectory;
  final String tokenEnvironment;
  final String? tokenFile;
  final Duration pollInterval;
  final Duration collectWindow;
  final Duration discoveryWindow;
  final Duration pipelineTimeout;
  final int maxBatchSize;
  final List<ProjectConfig> projects;

  const BotConfig({
    required this.gitlabUrl,
    required this.database,
    required this.workDirectory,
    this.tokenEnvironment = 'GITLAB_TOKEN',
    this.tokenFile,
    this.pollInterval = const Duration(seconds: 30),
    this.collectWindow = const Duration(seconds: 30),
    this.discoveryWindow = const Duration(seconds: 10),
    this.pipelineTimeout = const Duration(minutes: 60),
    this.maxBatchSize = 10,
    required this.projects,
  });

  factory BotConfig.parse(String source) {
    final data = loadYaml(source);
    if (data is! Map) {
      throw FormatException('Configuration must be a YAML map.');
    }
    const keys = {
      'gitlab_url',
      'database',
      'work_directory',
      'token_env',
      'token_file',
      'poll_interval_seconds',
      'collect_window_seconds',
      'pipeline_discovery_seconds',
      'pipeline_timeout_seconds',
      'max_batch_size',
      'projects',
    };
    for (final key in data.keys) {
      if (!keys.contains(key)) throw FormatException('Unknown setting: $key');
    }
    String text(String key, [String? fallback]) {
      final value = data[key] ?? fallback;
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key must be a nonempty string.');
      }
      return value;
    }

    int number(String key, int fallback, {bool zero = false}) {
      final value = data[key] ?? fallback;
      if (value is! int || value < (zero ? 0 : 1)) {
        throw FormatException('$key must be an integer >= ${zero ? 0 : 1}.');
      }
      return value;
    }

    final url = Uri.parse(text('gitlab_url'));
    if (!{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw FormatException('gitlab_url must be an HTTP(S) instance URL.');
    }
    final projects = <ProjectConfig>[];
    final entries = data['projects'];
    if (entries is! List || entries.isEmpty) {
      throw FormatException('projects must be a nonempty list.');
    }
    final seen = <String>{};
    for (final entry in entries) {
      if (entry is! Map ||
          entry.keys.any((k) => k != 'id' && k != 'target_branches')) {
        throw FormatException(
          'Each project needs id and target_branches only.',
        );
      }
      final id = entry['id'];
      final targets = entry['target_branches'];
      if ((id is! String && id is! int) ||
          id.toString().isEmpty ||
          targets is! List ||
          targets.isEmpty) {
        throw FormatException(
          'Project id and nonempty target_branches required.',
        );
      }
      final branches = <String>[];
      for (final branch in targets) {
        if (branch is! String ||
            branch.isEmpty ||
            branch.startsWith('-') ||
            branch.startsWith('merge-queue/') ||
            !seen.add('$id:$branch')) {
          throw FormatException('Invalid or duplicate target branch: $branch');
        }
        branches.add(branch);
      }
      projects.add(ProjectConfig(id.toString(), List.unmodifiable(branches)));
    }
    final discovery = number('pipeline_discovery_seconds', 10, zero: true);
    final timeout = number('pipeline_timeout_seconds', 3600);
    if (timeout <= discovery) {
      throw FormatException('Pipeline timeout must exceed discovery window.');
    }
    return BotConfig(
      gitlabUrl: url,
      database: text('database', 'data/queue.sqlite'),
      workDirectory: text('work_directory', 'data/repositories'),
      tokenEnvironment: text('token_env', 'GITLAB_TOKEN'),
      tokenFile: data['token_file'] == null ? null : text('token_file'),
      pollInterval: Duration(seconds: number('poll_interval_seconds', 30)),
      collectWindow: Duration(
        seconds: number('collect_window_seconds', 30, zero: true),
      ),
      discoveryWindow: Duration(seconds: discovery),
      pipelineTimeout: Duration(seconds: timeout),
      maxBatchSize: number('max_batch_size', 10),
      projects: projects,
    );
  }

  String readToken([Map<String, String>? environment]) {
    final token =
        (tokenFile == null
                ? (environment ?? Platform.environment)[tokenEnvironment]
                : File(tokenFile!).readAsStringSync())
            ?.trim();
    if (token == null ||
        token.isEmpty ||
        token.contains('\n') ||
        token.contains('\r')) {
      throw StateError(
        'A nonempty GitLab token is required via '
        '${tokenFile == null ? tokenEnvironment : 'token_file'}.',
      );
    }
    return token;
  }
}
