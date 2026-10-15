// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectConfig _$ProjectConfigFromJson(Map json) =>
    $checkedCreate('ProjectConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['id', 'target_branches']);
      final val = ProjectConfig(
        $checkedConvert('id', (v) => _projectIdFromJson(v)),
        $checkedConvert('target_branches', (v) => _targetsFromJson(v as List)),
      );
      return val;
    }, fieldKeyMap: const {'targets': 'target_branches'});

BotConfig _$BotConfigFromJson(Map json) => $checkedCreate(
  'BotConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
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
      ],
    );
    final val = BotConfig(
      gitlabUrl: $checkedConvert('gitlab_url', (v) => Uri.parse(v as String)),
      database: $checkedConvert(
        'database',
        (v) => v as String? ?? 'data/queue.sqlite',
      ),
      workDirectory: $checkedConvert(
        'work_directory',
        (v) => v as String? ?? 'data/repositories',
      ),
      tokenEnvironment: $checkedConvert(
        'token_env',
        (v) => v as String? ?? 'GITLAB_TOKEN',
      ),
      tokenFile: $checkedConvert('token_file', (v) => v as String?),
      pollInterval: $checkedConvert(
        'poll_interval_seconds',
        (v) => v == null ? const Duration(seconds: 30) : _secondsFromJson(v),
      ),
      collectWindow: $checkedConvert(
        'collect_window_seconds',
        (v) => v == null ? const Duration(seconds: 30) : _secondsFromJson(v),
      ),
      discoveryWindow: $checkedConvert(
        'pipeline_discovery_seconds',
        (v) => v == null ? const Duration(seconds: 10) : _secondsFromJson(v),
      ),
      pipelineTimeout: $checkedConvert(
        'pipeline_timeout_seconds',
        (v) => v == null ? const Duration(minutes: 60) : _secondsFromJson(v),
      ),
      maxBatchSize: $checkedConvert(
        'max_batch_size',
        (v) => v == null ? 10 : _integerFromJson(v),
      ),
      projects: $checkedConvert(
        'projects',
        (v) => (v as List<dynamic>)
            .map((e) => ProjectConfig.fromJson(e as Map))
            .toList(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'gitlabUrl': 'gitlab_url',
    'workDirectory': 'work_directory',
    'tokenEnvironment': 'token_env',
    'tokenFile': 'token_file',
    'pollInterval': 'poll_interval_seconds',
    'collectWindow': 'collect_window_seconds',
    'discoveryWindow': 'pipeline_discovery_seconds',
    'pipelineTimeout': 'pipeline_timeout_seconds',
    'maxBatchSize': 'max_batch_size',
  },
);
