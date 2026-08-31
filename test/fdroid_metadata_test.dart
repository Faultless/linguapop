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

  /// Flutter's `--split-per-abi` versionCode offsets. The ABI index map
  /// reserves 3 for x86, so x86_64 is 4 — assuming 3 is what a failed
  /// F-Droid build once cost.
  const abiOffset = {
    'app-armeabi-v7a-release.apk': 1000,
    'app-arm64-v8a-release.apk': 2000,
    'app-x86_64-release.apk': 4000,
  };

  test('every build entry matches the version in pubspec.yaml', () {
    final (name, code) = pubspecVersion();
    for (final build in recipe['Builds'] as List) {
      final output = (build['output'] as String).split('/').last;
      expect(abiOffset.containsKey(output), isTrue,
          reason: 'unknown output $output');
      expect(build['versionName'], name);
      expect(build['versionCode'], abiOffset[output]! + code,
          reason: '$output carries the wrong versionCode');
    }
  });

  test('VercodeOperation derives exactly the declared versionCodes', () {
    final (_, code) = pubspecVersion();
    final derived = [
      for (final op in recipe['VercodeOperation'] as List)
        int.parse((op as String).replaceAll('%c', '$code').split('+')[1].trim()) +
            code,
    ];
    final declared = [
      for (final b in recipe['Builds'] as List) b['versionCode'] as int,
    ];
    expect(derived..sort(), declared..sort());
  });

  test('CurrentVersion tracks the highest build', () {
    final (name, _) = pubspecVersion();
    final codes = [
      for (final b in recipe['Builds'] as List) b['versionCode'] as int,
    ];
    expect(recipe['CurrentVersion'], name);
    expect(recipe['CurrentVersionCode'], codes.reduce((a, b) => a > b ? a : b));
  });

  test('every build is pinned to the release tag for this version', () {
    final (name, _) = pubspecVersion();
    for (final build in recipe['Builds'] as List) {
      expect(build['commit'], 'v$name');
    }
  });

  test('UpdateCheckData reads the version out of pubspec.yaml', () {
    final parts = (recipe['UpdateCheckData'] as String).split('|');
    expect(parts.first, 'pubspec.yaml');
    final (name, code) = pubspecVersion();
    expect(RegExp(parts[1]).firstMatch(pubspec)!.group(1), '$code');
    expect(RegExp(parts[3]).firstMatch(pubspec)!.group(1), name);
  });

  test('the recipe strips the debug signing config', () {
    // F-Droid signs with its own key, so the APK has to come out unsigned.
    final prebuild =
        ((recipe['Builds'] as List).first['prebuild'] as List).join('\n');
    expect(prebuild, contains('signingConfig'));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('signingConfig = signingConfigs.getByName("debug")'),
        reason: 'the line the recipe deletes must still exist to be deleted');
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
