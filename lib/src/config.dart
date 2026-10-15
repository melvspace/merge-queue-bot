import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:yaml/yaml.dart';

part 'config.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
)
class const ProjectConfig(
  @JsonKey(fromJson: _projectIdFromJson) final String id,
  @JsonKey(name: 'target_branches', fromJson: _targetsFromJson)
  final List<String> targets,
) {
  factory ProjectConfig.fromJson(Map json) => _$ProjectConfigFromJson(json);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const BotConfig({
  required final Uri gitlabUrl,
  @JsonKey(defaultValue: 'data/queue.sqlite') required final String database,
  @JsonKey(defaultValue: 'data/repositories')
  required final String workDirectory,
  @JsonKey(name: 'token_env') final String tokenEnvironment = 'GITLAB_TOKEN',
  final String? tokenFile,
  @JsonKey(name: 'poll_interval_seconds', fromJson: _secondsFromJson)
  final Duration pollInterval = const Duration(seconds: 30),
  @JsonKey(name: 'collect_window_seconds', fromJson: _secondsFromJson)
  final Duration collectWindow = const Duration(seconds: 30),
  @JsonKey(name: 'pipeline_discovery_seconds', fromJson: _secondsFromJson)
  final Duration discoveryWindow = const Duration(seconds: 10),
  @JsonKey(name: 'pipeline_timeout_seconds', fromJson: _secondsFromJson)
  final Duration pipelineTimeout = const Duration(minutes: 60),
  @JsonKey(fromJson: _integerFromJson) final int maxBatchSize = 10,
  required final List<ProjectConfig> projects,
}) {
  factory BotConfig.parse(String source) {
    final data = loadYaml(source);

    if (data is! Map) {
      throw FormatException('Configuration must be a YAML map.');
    }

    return BotConfig.fromJson(data);
  }

  factory BotConfig.fromJson(Map json) {
    try {
      final config = _$BotConfigFromJson(json);
      config._validate();

      return config;
    } on CheckedFromJsonException catch (error) {
      throw FormatException(
        'Invalid ${error.key ?? 'configuration'}: '
        '${error.message ?? error.innerError}',
      );
    }
  }

  void _validate() {
    if (!{'http', 'https'}.contains(gitlabUrl.scheme) ||
        gitlabUrl.host.isEmpty ||
        gitlabUrl.userInfo.isNotEmpty ||
        gitlabUrl.hasQuery ||
        gitlabUrl.hasFragment) {
      throw FormatException('gitlab_url must be an HTTP(S) instance URL.');
    }

    for (final entry in {
      'database': database,
      'work_directory': workDirectory,
      'token_env': tokenEnvironment,
      'token_file': ?tokenFile,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw FormatException('${entry.key} must be a nonempty string.');
      }
    }

    for (final (key, duration, minimum) in [
      ('poll_interval_seconds', pollInterval, 1),
      ('collect_window_seconds', collectWindow, 0),
      ('pipeline_discovery_seconds', discoveryWindow, 0),
      ('pipeline_timeout_seconds', pipelineTimeout, 1),
    ]) {
      if (duration.inSeconds < minimum) {
        throw FormatException('$key must be an integer >= $minimum.');
      }
    }

    if (maxBatchSize < 1) {
      throw FormatException('max_batch_size must be an integer >= 1.');
    }

    if (pipelineTimeout <= discoveryWindow) {
      throw FormatException('Pipeline timeout must exceed discovery window.');
    }

    if (projects.isEmpty) {
      throw FormatException('projects must be a nonempty list.');
    }

    final seen = <String>{};

    for (final project in projects) {
      if (project.targets.isEmpty) {
        throw FormatException('target_branches must be a nonempty list.');
      }

      for (final branch in project.targets) {
        if (branch.isEmpty ||
            branch.startsWith('-') ||
            branch.startsWith('merge-queue/') ||
            !seen.add('${project.id}:$branch')) {
          throw FormatException('Invalid or duplicate target branch: $branch');
        }
      }
    }
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

String _projectIdFromJson(Object? value) {
  if ((value is! String && value is! int) || value.toString().isEmpty) {
    throw FormatException('Project id must be a nonempty string or integer.');
  }

  return value.toString();
}

List<String> _targetsFromJson(List<dynamic> value) =>
    List<String>.unmodifiable(value.cast<String>());

int _integerFromJson(Object? value) {
  if (value is! int) throw FormatException('Expected an integer.');

  return value;
}

Duration _secondsFromJson(Object? value) {
  final seconds = _integerFromJson(value);

  if (seconds < 0) throw FormatException('Seconds must be nonnegative.');

  return Duration(seconds: seconds);
}
