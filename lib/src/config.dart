import 'dart:io';

import 'package:json_annotation/json_annotation.dart';
import 'package:yaml/yaml.dart';

import 'models.dart';

part 'config.g.dart';

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const ProjectConfig(
  @JsonKey(fromJson: _projectIdFromJson) final String id,
  @JsonKey(name: 'target_branches', fromJson: _targetsFromJson)
  final List<String> targets, {
  @JsonKey(name: 'landing_mode')
  final LandingMode landingMode = LandingMode.merge,
}) {
  factory ProjectConfig.fromJson(Map json) => _$ProjectConfigFromJson(json);
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const GitLabConfig({
  @JsonKey(required: true, disallowNullValue: true) required final Uri url,
  @JsonKey(name: 'token_env') final String tokenEnvironment = 'GITLAB_TOKEN',
  final String? tokenFile,
}) {
  factory GitLabConfig.fromJson(Map json) => _$GitLabConfigFromJson(json);

  void _validate() {
    if (!{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      throw FormatException('gitlab.url must be an HTTP(S) instance URL.');
    }

    for (final entry in {
      'gitlab.token_env': tokenEnvironment,
      'gitlab.token_file': ?tokenFile,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw FormatException('${entry.key} must be a nonempty string.');
      }
    }
  }
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const StorageConfig({
  final String database = 'data/queue.sqlite',
  final String workDirectory = 'data/repositories',
}) {
  factory StorageConfig.fromJson(Map json) => _$StorageConfigFromJson(json);

  void _validate() {
    for (final entry in {
      'storage.database': database,
      'storage.work_directory': workDirectory,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw FormatException('${entry.key} must be a nonempty string.');
      }
    }
  }
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const QueueConfig({
  @JsonKey(name: 'poll_interval_seconds', fromJson: _secondsFromJson)
  final Duration pollInterval = const Duration(seconds: 30),
  @JsonKey(name: 'collect_window_seconds', fromJson: _secondsFromJson)
  final Duration collectWindow = const Duration(seconds: 30),
  @JsonKey(fromJson: _integerFromJson) final int maxBatchSize = 10,
}) {
  factory QueueConfig.fromJson(Map json) => _$QueueConfigFromJson(json);

  void _validate() {
    if (pollInterval.inSeconds < 1) {
      throw FormatException(
        'queue.poll_interval_seconds must be an integer >= 1.',
      );
    }

    if (collectWindow.isNegative) {
      throw FormatException(
        'queue.collect_window_seconds must be an integer >= 0.',
      );
    }

    if (maxBatchSize < 1) {
      throw FormatException('queue.max_batch_size must be an integer >= 1.');
    }
  }
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const PipelineConfig({
  @JsonKey(name: 'discovery_seconds', fromJson: _secondsFromJson)
  final Duration discoveryWindow = const Duration(seconds: 10),
  @JsonKey(name: 'timeout_seconds', fromJson: _secondsFromJson)
  final Duration timeout = const Duration(minutes: 60),
}) {
  factory PipelineConfig.fromJson(Map json) => _$PipelineConfigFromJson(json);

  void _validate() {
    if (discoveryWindow.isNegative) {
      throw FormatException(
        'pipelines.discovery_seconds must be an integer >= 0.',
      );
    }

    if (timeout.inSeconds < 1) {
      throw FormatException(
        'pipelines.timeout_seconds must be an integer >= 1.',
      );
    }

    if (timeout <= discoveryWindow) {
      throw FormatException(
        'pipelines.timeout_seconds must exceed pipelines.discovery_seconds.',
      );
    }
  }
}

@JsonSerializable(
  anyMap: true,
  checked: true,
  createToJson: false,
  disallowUnrecognizedKeys: true,
  fieldRename: FieldRename.snake,
)
class const BotConfig({
  @JsonKey(required: true, disallowNullValue: true)
  required final GitLabConfig gitlab,
  @JsonKey(disallowNullValue: true)
  final StorageConfig storage = const StorageConfig(),
  @JsonKey(disallowNullValue: true)
  final QueueConfig queue = const QueueConfig(),
  @JsonKey(disallowNullValue: true)
  final PipelineConfig pipelines = const PipelineConfig(),
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
        'Invalid ${_configurationErrorPath(error, json)}: '
        '${error.message ?? error.innerError}',
      );
    }
  }

  void _validate() {
    gitlab._validate();
    storage._validate();
    queue._validate();
    pipelines._validate();

    if (projects.isEmpty) {
      throw FormatException('projects must be a nonempty list.');
    }

    final seen = <String>{};

    for (final (index, project) in projects.indexed) {
      final path = 'projects[$index].target_branches';

      if (project.targets.isEmpty) {
        throw FormatException('$path must be a nonempty list.');
      }

      for (final (branchIndex, branch) in project.targets.indexed) {
        if (branch.isEmpty ||
            branch.startsWith('-') ||
            branch.startsWith('merge-queue/') ||
            !seen.add('${project.id}:$branch')) {
          throw FormatException(
            '$path[$branchIndex] contains an invalid or duplicate branch: $branch',
          );
        }
      }
    }
  }

  String readToken([Map<String, String>? environment]) {
    final token =
        (gitlab.tokenFile == null
                ? (environment ?? Platform.environment)[gitlab.tokenEnvironment]
                : File(gitlab.tokenFile!).readAsStringSync())
            ?.trim();

    if (token == null ||
        token.isEmpty ||
        token.contains('\n') ||
        token.contains('\r')) {
      throw StateError(
        'A nonempty GitLab token is required via '
        '${gitlab.tokenFile == null ? gitlab.tokenEnvironment : 'gitlab.token_file'}.',
      );
    }

    return token;
  }
}

String _configurationErrorPath(CheckedFromJsonException error, Map json) {
  while (error.innerError is CheckedFromJsonException) {
    error = error.innerError! as CheckedFromJsonException;
  }

  var prefix = switch (error.className) {
    'GitLabConfig' => 'gitlab',
    'StorageConfig' => 'storage',
    'QueueConfig' => 'queue',
    'PipelineConfig' => 'pipelines',
    'ProjectConfig' => 'projects',
    _ => '',
  };
  final projects = json['projects'];

  if (prefix == 'projects' && projects is List) {
    final index = projects.indexWhere(
      (project) => identical(project, error.map),
    );

    if (index >= 0) prefix = 'projects[$index]';
  }

  final key =
      error.key ??
      switch (error.innerError) {
        UnrecognizedKeysException(:final unrecognizedKeys) =>
          unrecognizedKeys.first,
        _ => null,
      };

  final path = [if (prefix.isNotEmpty) prefix, ?key].join('.');

  return path.isEmpty ? 'configuration' : path;
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
