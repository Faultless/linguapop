import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

/// Guards the F-Droid build recipe against drifting away from the app.
///
/// F-Droid's buildserver refuses an APK whose versionCode isn't the one the
/// recipe promised, and a build there takes the better part of an hour to
/// tell you so. Everything below is checkable in milliseconds.
void main() {
  late Map recipe;
  late String pubspec;

  setUpAll(() {
    recipe = loadYaml(
        File('fdroid/com.linguapop.linguapop.yml').readAsStringSync()) as Map;
    pubspec = File('pubspec.yaml').readAsStringSync();
  });

  /// `version: 7.3.0+11`
  (String, int) pubspecVersion() {
    final m = RegExp(r'^version:\s*([\d.]+)\+(\d+)', multiLine: true)
        .firstMatch(pubspec)!;
    return (m.group(1)!, int.parse(m.group(2)!));
  }

  /// The ABI index each split APK's versionCode is offset by, per F-Droid's
  /// submission guide: `versionCode * 10 + abi`, ordered so a later release
  /// of any ABI outranks an earlier release of every ABI. Applied in
  /// `android/app/build.gradle.kts`, not by Flutter.
  const abiIndex = {
    'app-armeabi-v7a-release.apk': 1,
    'app-arm64-v8a-release.apk': 2,
    'app-x86_64-release.apk': 3,
  };

  test('every build entry matches the version in pubspec.yaml', () {
    final (name, code) = pubspecVersion();
    for (final build in recipe['Builds'] as List) {
      final output = (build['output'] as String).split('/').last;
      expect(abiIndex.containsKey(output), isTrue,
          reason: 'unknown output $output');
      expect(build['versionName'], name);
      expect(build['versionCode'], code * 10 + abiIndex[output]!,
          reason: '$output carries the wrong versionCode');
    }
  });

  test('gradle applies the same ABI scheme the recipe declares', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    for (final entry in abiIndex.entries) {
      final abi =
          entry.key.replaceFirst('app-', '').replaceFirst('-release.apk', '');
      expect(gradle, contains('"$abi" to ${entry.value}'),
          reason: 'gradle must map $abi to ${entry.value}');
    }
    expect(gradle, contains('variant.versionCode * 10 + abiVersionCode'));
  });

  test('version codes only ever go up', () {
    // Android refuses an update whose versionCode went backwards. The old
    // scheme (Flutter's own) shipped arm64 as high as 2012, so nothing under
    // the current scheme may land at or below that.
    const highestUnderOldScheme = 2012;
    for (final b in recipe['Builds'] as List) {
      expect(b['versionCode'] as int, greaterThan(highestUnderOldScheme));
    }
  });

  test('VercodeOperation derives exactly the declared versionCodes', () {
    final (_, code) = pubspecVersion();
    final derived = [
      // Every operation is of the form `10 * %c + n`.
      for (final op in recipe['VercodeOperation'] as List)
        code * 10 + int.parse(op.toString().split('+').last.trim()),
    ];
    final declared = [
      for (final b in recipe['Builds'] as List) b['versionCode'] as int,
    ];
    expect(derived, declared);
    expect(derived, orderedEquals(derived.toList()..sort()),
        reason: 'F-Droid requires armeabi-v7a < arm64-v8a < x86_64');
  });

  test('CurrentVersion tracks the highest build', () {
    final (name, _) = pubspecVersion();
    final codes = [
      for (final b in recipe['Builds'] as List) b['versionCode'] as int,
    ];
    expect(recipe['CurrentVersion'], name);
    expect(recipe['CurrentVersionCode'], codes.reduce((a, b) => a > b ? a : b));
  });

  test('every build is pinned to a full commit hash', () {
    // F-Droid asks for a hash, not a tag or branch: a tag can be moved after
    // review, a hash cannot.
    for (final build in recipe['Builds'] as List) {
      expect(build['commit'], matches(RegExp(r'^[0-9a-f]{40}$')),
          reason: 'commit must be a full 40-character hash');
    }
  });

  test('the pinned commit is the one the release tag points at', () {
    final (name, _) = pubspecVersion();
    final rev = Process.runSync('git', ['rev-list', '-n', '1', 'v$name']);
    // Skipped before the tag exists — the recipe is pinned while cutting the
    // release, which is necessarily before the tag is pushed.
    if (rev.exitCode != 0) return;
    final sha = (rev.stdout as String).trim();
    for (final build in recipe['Builds'] as List) {
      expect(build['commit'], sha,
          reason: 'recipe points somewhere other than tag v$name');
    }
  });

  test('UpdateCheckData reads the version out of pubspec.yaml', () {
    final parts = (recipe['UpdateCheckData'] as String).split('|');
    expect(parts.first, 'pubspec.yaml');
    final (name, code) = pubspecVersion();
    expect(RegExp(parts[1]).firstMatch(pubspec)!.group(1), '$code');
    expect(RegExp(parts[3]).firstMatch(pubspec)!.group(1), name);
  });

  test('the recipe strips signing via the marker gradle still carries', () {
    // F-Droid signs with its own key, so the APK has to come out unsigned.
    // The strip keys off an explicit marker rather than the shape of the
    // code, which changed once already and silently broke the sed.
    final prebuild =
        ((recipe['Builds'] as List).first['prebuild'] as List).join('\n');
    expect(prebuild, contains('FDROID-STRIP'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final marked =
        gradle.split('\n').where((l) => l.contains('FDROID-STRIP')).toList();
    expect(marked, hasLength(1),
        reason: 'exactly one line may carry the strip marker');
    expect(marked.single, contains('signingConfig ='));
  });

  test('the pinned NDK matches the one gradle builds against', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    final pinned =
        RegExp(r'ndkVersion\s*=\s*"([\d.]+)"').firstMatch(gradle)!.group(1);
    for (final build in recipe['Builds'] as List) {
      expect('${build['ndk']}', pinned);
    }
  });

  test('the pinned Flutter version is recorded for the recipe to read', () {
    expect(File('FLUTTER_VERSION').existsSync(), isTrue);
    expect(File('FLUTTER_VERSION').readAsStringSync().trim(), isNotEmpty);
    final prebuild =
        ((recipe['Builds'] as List).first['prebuild'] as List).join('\n');
    expect(prebuild, contains('FLUTTER_VERSION'));
  });
}
