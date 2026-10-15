import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:merge_queue_bot/merge_queue_bot.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'config.yaml',
      help: 'Path to the YAML configuration.',
    )
    ..addFlag(
      'check-config',
      negatable: false,
      help: 'Validate YAML without connecting to GitLab.',
    )
    ..addFlag(
      'once',
      negatable: false,
      help: 'Run one reconciliation tick for every queue and exit.',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  String? token;
  final subscriptions = <StreamSubscription<ProcessSignal>>[];

  try {
    final args = parser.parse(arguments);

    if (args['help'] as bool) {
      stdout.writeln(
        'Usage: merge_queue_bot --config config.yaml\n${parser.usage}',
      );

      return;
    }

    if (args.rest.isNotEmpty) {
      throw FormatException('Unexpected positional arguments.');
    }

    final config = BotConfig.parse(
      File(args['config'] as String).readAsStringSync(),
    );

    if (args['check-config'] as bool) {
      stdout.writeln(
        'Configuration is valid (${config.projects.length} projects).',
      );

      return;
    }

    token = config.readToken();
    final service = BotService(config, token);

    for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
      subscriptions.add(signal.watch().listen((_) => service.stop()));
    }

    await service.run(once: args['once'] as bool);
  } catch (error) {
    var message = error.toString();

    if (token != null) message = message.replaceAll(token, '[REDACTED]');

    stderr.writeln('merge_queue_bot: $message');
    exitCode = 1;
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
