import 'dart:io' show File;

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart';
import 'package:file/file.dart' hide File;
import 'package:patrol_cli/src/base/exceptions.dart';

const _kDefaultTestFileSuffix = '_test.dart';

/// Discovers integration tests.
class TestFinder {
  TestFinder({required Directory testDir})
      : _integrationTestDirectory = testDir,
        _fs = testDir.fileSystem;

  final Directory _integrationTestDirectory;
  final FileSystem _fs;

  String findTest(
    String target, [
    String testFileSuffix = _kDefaultTestFileSuffix,
  ]) {
    final testFiles = findTests([target], testFileSuffix);
    if (testFiles.length > 1) {
      throwToolExit(
        'target $target is ambiguous, '
        'it matches multiple test targets: ${testFiles.join(', ')}',
      );
    }

    return testFiles.single;
  }

  /// Checks that every element of [targets] is a valid target.
  ///
  /// A target is valid if it:
  ///
  ///  * is a path to a Dart test file, or
  ///
  ///  * is a path to a directory recursively containing at least one Dart test
  ///    file
  List<String> findTests(
    List<String> targets, [
    String testFileSuffix = _kDefaultTestFileSuffix,
  ]) {
    final testFiles = <String>[];

    for (final target in targets) {
      if (target.endsWith(testFileSuffix)) {
        final isFile = _fs.isFileSync(target);
        if (!isFile) {
          throwToolExit('target file $target does not exist');
        }
        testFiles.add(_fs.file(target).absolute.path);
      } else if (_fs.isDirectorySync(target)) {
        final foundTargets = findAllTests(
          directory: _fs.directory(target),
          testFileSuffix: testFileSuffix,
        );
        if (foundTargets.isEmpty) {
          throwToolExit(
            'target directory $target does not contain any tests',
          );
        }

        testFiles.addAll(foundTargets);
      } else {
        throwToolExit('target $target is invalid');
      }
    }

    return testFiles;
  }

  /// Recursively searches the `integration_test` directory and returns files
  /// ending with defined [testFileSuffix]. If [testFileSuffix] is not defined,
  /// the default suffix `_test.dart` is used.
  List<String> findAllTests({
    Directory? directory,
    Set<String> excludes = const {},
    String testFileSuffix = _kDefaultTestFileSuffix,
  }) {
    directory ??= _integrationTestDirectory;

    if (!directory.existsSync()) {
      throwToolExit("Directory ${directory.path} doesn't exist");
    }

    return directory
        .listSync(recursive: true, followLinks: false)
        .sorted((a, b) => a.path.compareTo(b.path))
        // Find only test files
        .where(
          (fileSystemEntity) {
            final hasSuffix = fileSystemEntity.path.endsWith(testFileSuffix);
            final isFile = _fs.isFileSync(fileSystemEntity.path);
            return hasSuffix && isFile;
          },
        )
        // Filter out excluded files
        .where((fileSystemEntity) {
          // TODO: Doesn't handle excluded passes as absolute paths
          final isExcluded = excludes.contains(fileSystemEntity.path);
          return !isExcluded;
        })
        .map((entity) => entity.absolute.path)
        .toList();
  }

  /// Recursively searches the `integration_test` directory and returns files
  /// matching the given tags.
  List<String> findTestsForTags(List<String> tags) {
    return findAllTests().where((test) => _matchesTags(test, tags)).toList();
  }

  bool _matchesTags(String path, List<String> tags) {
    final parseResult = parseString(
      content: File(path).readAsStringSync(),
      throwIfDiagnostics: false,
    );
    final firstChild = parseResult.unit.root.childEntities.firstOrNull;

    if (firstChild is ImportDirective) {
      final tagAnnotation = firstChild.metadata.firstOrNull;
      if (tagAnnotation != null && tagAnnotation.name.toString() == 'Tags') {
        final argumentList = tagAnnotation.arguments?.arguments.firstOrNull;
        if (argumentList is ListLiteral?) {
          final isMatch = argumentList?.elements
              .whereType<SimpleStringLiteral>()
              .map((literal) => literal.value)
              .any((element) => tags.contains(element));

          return isMatch ?? false;
        }
      }
    }

    return false;
  }
}
