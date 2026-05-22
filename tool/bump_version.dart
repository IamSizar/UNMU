// Bumps the `version:` line in pubspec.yaml.
//
// Usage:
//   dart run tool/bump_version.dart --type patch
//   dart run tool/bump_version.dart --type minor
//   dart run tool/bump_version.dart --type major
//   dart run tool/bump_version.dart --type build
//
// Reads pubspec.yaml as plain text (not via the `yaml` package) so the
// script has zero dependencies — important because CI runs it before
// `flutter pub get` has restored anything.
//
// The bump rules:
//   patch  → 1.2.3+5  becomes 1.2.4+1
//   minor  → 1.2.3+5  becomes 1.3.0+1
//   major  → 1.2.3+5  becomes 2.0.0+1
//   build  → 1.2.3+5  becomes 1.2.3+6   (semver name unchanged)
//
// On success: prints the new "name+build" string and exits 0.
// On error:   prints a message to stderr and exits non-zero.

import 'dart:io';

void main(List<String> args) {
  final type = _parseType(args);
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('pubspec.yaml not found in current directory');
    exit(2);
  }

  final lines = pubspec.readAsLinesSync();
  final versionLineIndex = lines.indexWhere(
    (l) => l.startsWith('version:'),
  );
  if (versionLineIndex < 0) {
    stderr.writeln('no `version:` line in pubspec.yaml');
    exit(2);
  }

  final current = lines[versionLineIndex]
      .substring('version:'.length)
      .trim();
  final parsed = _Version.parse(current);
  final next = parsed.bump(type);

  lines[versionLineIndex] = 'version: ${next.toString()}';
  pubspec.writeAsStringSync('${lines.join('\n')}\n');

  stdout.writeln(next.toString());
}

enum _BumpType { patch, minor, major, build }

_BumpType _parseType(List<String> args) {
  final idx = args.indexOf('--type');
  if (idx < 0 || idx + 1 >= args.length) {
    stderr.writeln('missing --type <patch|minor|major|build>');
    exit(2);
  }
  switch (args[idx + 1]) {
    case 'patch':
      return _BumpType.patch;
    case 'minor':
      return _BumpType.minor;
    case 'major':
      return _BumpType.major;
    case 'build':
      return _BumpType.build;
    default:
      stderr.writeln('unknown --type "${args[idx + 1]}"');
      exit(2);
  }
}

class _Version {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const _Version(this.major, this.minor, this.patch, this.build);

  static _Version parse(String raw) {
    final plus = raw.indexOf('+');
    final namePart = plus < 0 ? raw : raw.substring(0, plus);
    final buildPart = plus < 0 ? '0' : raw.substring(plus + 1);
    final segments = namePart.split('.');
    if (segments.length != 3) {
      stderr.writeln('expected semver name "X.Y.Z" in pubspec — got "$raw"');
      exit(2);
    }
    return _Version(
      int.parse(segments[0]),
      int.parse(segments[1]),
      int.parse(segments[2]),
      int.parse(buildPart),
    );
  }

  _Version bump(_BumpType type) {
    switch (type) {
      case _BumpType.major:
        return _Version(major + 1, 0, 0, 1);
      case _BumpType.minor:
        return _Version(major, minor + 1, 0, 1);
      case _BumpType.patch:
        return _Version(major, minor, patch + 1, 1);
      case _BumpType.build:
        return _Version(major, minor, patch, build + 1);
    }
  }

  @override
  String toString() => '$major.$minor.$patch+$build';
}
