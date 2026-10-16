// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'config.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectConfig _$ProjectConfigFromJson(Map json) => $checkedCreate(
  'ProjectConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const ['id', 'target_branches', 'landing_mode'],
    );
    final val = ProjectConfig(
      $checkedConvert('id', (v) => _projectIdFromJson(v)),
      $checkedConvert('target_branches', (v) => _targetsFromJson(v as List)),
      landingMode: $checkedConvert(
        'landing_mode',
        (v) =>
            $enumDecodeNullable(_$LandingModeEnumMap, v) ?? LandingMode.merge,
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'targets': 'target_branches',
    'landingMode': 'landing_mode',
  },
);

const _$LandingModeEnumMap = {
  LandingMode.merge: 'merge',
  LandingMode.fastForwardPush: 'fast_forward_push',
};

GitLabConfig _$GitLabConfigFromJson(Map json) => $checkedCreate(
  'GitLabConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const ['url', 'token_env', 'token_file'],
      requiredKeys: const ['url'],
      disallowNullValues: const ['url'],
    );
    final val = GitLabConfig(
      url: $checkedConvert('url', (v) => Uri.parse(v as String)),
      tokenEnvironment: $checkedConvert(
        'token_env',
        (v) => v as String? ?? 'GITLAB_TOKEN',
      ),
      tokenFile: $checkedConvert('token_file', (v) => v as String?),
    );
    return val;
  },
  fieldKeyMap: const {
    'tokenEnvironment': 'token_env',
    'tokenFile': 'token_file',
  },
);

StorageConfig _$StorageConfigFromJson(Map json) =>
    $checkedCreate('StorageConfig', json, ($checkedConvert) {
      $checkKeys(json, allowedKeys: const ['database', 'work_directory']);
      final val = StorageConfig(
        database: $checkedConvert(
          'database',
          (v) => v as String? ?? 'data/queue.sqlite',
        ),
        workDirectory: $checkedConvert(
          'work_directory',
          (v) => v as String? ?? 'data/repositories',
        ),
      );
      return val;
    }, fieldKeyMap: const {'workDirectory': 'work_directory'});

QueueConfig _$QueueConfigFromJson(Map json) => $checkedCreate(
  'QueueConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const [
        'poll_interval_seconds',
        'collect_window_seconds',
        'max_batch_size',
      ],
    );
    final val = QueueConfig(
      pollInterval: $checkedConvert(
        'poll_interval_seconds',
        (v) => v == null ? const Duration(seconds: 30) : _secondsFromJson(v),
      ),
      collectWindow: $checkedConvert(
        'collect_window_seconds',
        (v) => v == null ? const Duration(seconds: 30) : _secondsFromJson(v),
      ),
      maxBatchSize: $checkedConvert(
        'max_batch_size',
        (v) => v == null ? 10 : _integerFromJson(v),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'pollInterval': 'poll_interval_seconds',
    'collectWindow': 'collect_window_seconds',
    'maxBatchSize': 'max_batch_size',
  },
);

PipelineConfig _$PipelineConfigFromJson(Map json) => $checkedCreate(
  'PipelineConfig',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      allowedKeys: const ['discovery_seconds', 'timeout_seconds'],
    );
    final val = PipelineConfig(
      discoveryWindow: $checkedConvert(
        'discovery_seconds',
        (v) => v == null ? const Duration(seconds: 10) : _secondsFromJson(v),
      ),
      timeout: $checkedConvert(
        'timeout_seconds',
        (v) => v == null ? const Duration(minutes: 60) : _secondsFromJson(v),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'discoveryWindow': 'discovery_seconds',
    'timeout': 'timeout_seconds',
  },
);

BotConfig _$BotConfigFromJson(Map json) => $checkedCreate('BotConfig', json, (
  $checkedConvert,
) {
  $checkKeys(
    json,
    allowedKeys: const ['gitlab', 'storage', 'queue', 'pipelines', 'projects'],
    requiredKeys: const ['gitlab'],
    disallowNullValues: const ['gitlab', 'storage', 'queue', 'pipelines'],
  );
  final val = BotConfig(
    gitlab: $checkedConvert('gitlab', (v) => GitLabConfig.fromJson(v as Map)),
    storage: $checkedConvert(
      'storage',
      (v) =>
          v == null ? const StorageConfig() : StorageConfig.fromJson(v as Map),
    ),
    queue: $checkedConvert(
      'queue',
      (v) => v == null ? const QueueConfig() : QueueConfig.fromJson(v as Map),
    ),
    pipelines: $checkedConvert(
      'pipelines',
      (v) => v == null
          ? const PipelineConfig()
          : PipelineConfig.fromJson(v as Map),
    ),
    projects: $checkedConvert(
      'projects',
      (v) => (v as List<dynamic>)
          .map((e) => ProjectConfig.fromJson(e as Map))
          .toList(),
    ),
  );
  return val;
});
