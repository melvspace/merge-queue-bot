import 'package:merge_queue_bot/src/models.dart';
import 'package:test/test.dart';

void main() {
  const project = Project(
    id: 1,
    path: 'group/repo',
    cloneUrl: '',
    mergeMethod: 'ff',
    squashOption: 'never',
    automaticRebase: false,
  );

  test(
    'reports every incompatible setting with actual and expected values',
    () {
      final invalid = project.copyWith(
        mergeMethod: 'merge',
        squashOption: 'always',
        automaticRebase: true,
        mergedResultsPipelines: true,
      );

      expect(
        invalid.validate,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'group/repo has incompatible project settings: '
                'merge_method="merge"; expected "ff" (fast-forward) | '
                'squash_option="always"; expected "never", "default_off", '
                'or "default_on" (disabled or optional) | '
                'automatic_rebase_enabled=true; expected false | '
                'merge_pipelines_enabled=true; expected false.',
          ),
        ),
      );
    },
  );

  test('reports only settings that are incompatible', () {
    expect(
      project.copyWith(automaticRebase: true).validate,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'group/repo has incompatible project settings: '
              'automatic_rebase_enabled=true; expected false.',
        ),
      ),
    );
  });

  test('accepts disabled and optional squashing', () {
    for (final option in ['never', 'default_off', 'default_on']) {
      expect(project.copyWith(squashOption: option).validate, returnsNormally);
    }
  });

  test('push landing accepts every supported GitLab merge method', () {
    for (final method in ['ff', 'merge', 'rebase_merge']) {
      expect(
        () => project
            .copyWith(mergeMethod: method)
            .validate(landingMode: LandingMode.fastForwardPush),
        returnsNormally,
      );
    }
  });

  test('push landing still rejects incompatible settings', () {
    for (final invalid in [
      project.copyWith(mergeMethod: 'unknown'),
      project.copyWith(squashOption: 'always'),
      project.copyWith(automaticRebase: true),
      project.copyWith(mergedResultsPipelines: true),
    ]) {
      expect(
        () => invalid.validate(landingMode: LandingMode.fastForwardPush),
        throwsStateError,
      );
    }
  });
}
