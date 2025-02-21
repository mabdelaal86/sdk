// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Converts a multi-test to a test using the new static error test framework
/// (see https://github.com/dart-lang/sdk/tree/main/docs/Testing.md#static-error-tests)
/// and a copy of the '/none' test.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart';
import 'package:path/path.dart' as p;
import 'package:test_runner/src/command_output.dart';
import 'package:test_runner/src/multitest.dart';
import 'package:test_runner/src/path.dart';
import 'package:test_runner/src/static_error.dart';
import 'package:test_runner/src/test_file.dart';
import 'package:test_runner/src/update_errors.dart';

import 'update_static_error_tests.dart' show dartPath;

final _analyzerPath = p.join('pkg', 'analyzer_cli', 'bin', 'analyzer.dart');

Future<List<StaticError>> getErrors(
    List<String> options, String filePath) async {
  var analyzerErrors = await _runAnalyzer(File(filePath), options);
  var cfeErrors = await _runCfe(File(filePath), options);
  return [...analyzerErrors, ...cfeErrors];
}

bool areSameErrors(List<StaticError> first, List<StaticError> second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; ++i) {
    if (first[i].compareTo(second[i]) != 0) return false;
  }
  return true;
}

/// Merges a list of error lists into a single list. The result is sorted with
/// respect to [StaticError.compareTo].
List<StaticError> mergeErrors(Iterable<List<StaticError>> errors) {
  // Using a [SplayTreeSet] here results in a sorted list.
  var result = SplayTreeSet<StaticError>();
  for (var list in errors) {
    result.addAll(list);
  }
  return result.toList();
}

const staticOutcomes = [
  "syntax error",
  "compile-time error",
  "static type warning",
];

class UnableToConvertException {
  final String message;
  UnableToConvertException(this.message);
  @override
  String toString() => "unable to convert: $message";
}

class CleanedMultiTest {
  final String text;
  final Map<String, String> subTests;
  CleanedMultiTest(this.text, this.subTests);
}

CleanedMultiTest removeMultiTestMarker(String test) {
  var buffer = StringBuffer();
  var subTests = <String, String>{};
  var lines = LineSplitter.split(test)
      .where((line) => !line.startsWith("// Test created from multitest named"))
      .toList();
  if (lines.length > 1 && lines.last.isEmpty) {
    // If the file ends with a newline, remove the empty line - the loop below
    // will add a newline to the end.
    lines.length--;
  }
  for (var line in lines) {
    var matches = multitestMarker.allMatches(line);
    if (matches.length > 1) {
      throw "internal error: cannot process line '$line'";
    } else if (matches.length == 1) {
      var match = matches.single;
      var annotation = Annotation.tryParse(line)!;
      if (annotation.outcomes.length != 1) {
        throw UnableToConvertException("annotation has multiple outcomes");
      }
      var outcome = annotation.outcomes.single;
      if (outcome == "continued" ||
          outcome == "ok" ||
          staticOutcomes.contains(outcome)) {
        line = line.substring(0, match.start).trimRight();
        if (line.endsWith("//")) {
          line = line.substring(0, line.length - 2).trimRight();
        }
        if (outcome != "continued") {
          subTests[annotation.key] = outcome;
        }
      } else {
        throw UnableToConvertException("test contains dynamic outcome");
      }
    }
    buffer.writeln(line);
  }
  return CleanedMultiTest(buffer.toString(), subTests);
}

Future createRuntimeTest(
    String testFilePath, String multiTestPath, bool writeToFile) async {
  var testName = basename(testFilePath);
  String runtimeTestBase;
  if (testName.endsWith("_test.dart")) {
    runtimeTestBase =
        testName.substring(0, testName.length - "_test.dart".length);
  } else if (testName.endsWith(".dart")) {
    runtimeTestBase = testName.substring(0, testName.length - ".dart".length);
  } else {
    runtimeTestBase = testName;
  }
  var runtimeTestPath = "${dirname(testFilePath)}/$runtimeTestBase"
      "_runtime_test.dart";
  var n = 1;
  while (await File(runtimeTestPath).exists()) {
    runtimeTestPath = "${dirname(testFilePath)}/$runtimeTestBase"
        "_runtime_${n++}_test.dart";
  }
  var testContent = await File(multiTestPath).readAsString();
  var cleanedMultiTest = removeMultiTestMarker(testContent);
  var runtimeTestContent = """
// TODO(multitest): This was automatically migrated from a multitest and may
// contain strange or dead code.

${cleanedMultiTest.text}""";
  if (writeToFile) {
    var outputFile = File(runtimeTestPath);
    await outputFile.writeAsString(runtimeTestContent, mode: FileMode.append);
    print("Runtime part of the test written to '$runtimeTestPath'.");
  } else {
    print("-- $runtimeTestPath:");
    print(runtimeTestContent);
  }
}

Future<void> convertFile(String testFilePath, bool writeToFile, bool verbose,
    List<String> experiments) async {
  var testFile = File(testFilePath);
  if (!await testFile.exists()) {
    print("File '${testFile.uri.toFilePath()}' not found");
    exitCode = 1;
    return;
  }
  // Read test file and setup output directory.
  var suiteDirectory = Path.raw(Uri.base.path);
  var content = await testFile.readAsString();
  var test = TestFile.read(suiteDirectory, testFilePath);
  if (!content.contains(multitestMarker)) {
    print("Test ${test.path.toNativePath()} is not a multi-test.");
    exitCode = 1;
    return;
  }
  var outputDirectory = await Directory(dirname(testFilePath)).createTemp();
  if (verbose) {
    print("Output directory for generated files: ${outputDirectory.uri.path}");
  }
  try {
    // Generate the sub-tests of the multi-test in [outputDirectory].
    var tests = [
      test,
      ...splitMultitest(test, outputDirectory.uri.toFilePath(), suiteDirectory)
    ];
    if (!tests[1].name.endsWith("/none")) {
      throw "internal error: expected second test to be the '/none' test";
    }
    // Remove the multi-test marker from the test. We do this here to fail fast
    // for cases we do not support, because generating the front-end errors is
    // quite slow.
    var cleanedTest = removeMultiTestMarker(content);
    var contentWithoutMarkers = cleanedTest.text;
    // Get the reported errors for the multi-test and all generated sub-tests
    // from the analyser and the common front-end.
    var options = [
      ...test.sharedOptions,
      if (experiments.isNotEmpty)
        "--enable-experiment=${experiments.join(',')}",
    ];

    var errors = <List<StaticError>>[];
    for (var test in tests) {
      if (verbose) {
        print("Processing ${test.path}");
      }
      errors.add(await getErrors(options, test.path.toNativePath()));
    }
    if (errors[1].isNotEmpty) {
      throw UnableToConvertException("internal error: errors in '/none' test");
    }
    // Check that the multi-test generates the same errors as all sub-tests
    // together - otherwise converting the test would be unsound.
    var sortedOriginalErrors = errors[0].toList()..sort();
    var mergedErrors = mergeErrors(errors.skip(2));
    if (!areSameErrors(sortedOriginalErrors, mergedErrors)) {
      if (verbose) {
        print("Sub-tests have different errors!\n\n"
            "Errors in sub-tests:\n$mergedErrors\n\n"
            "Errors in original test:\n$sortedOriginalErrors\n");
      }
      throw UnableToConvertException(
          "Test produces different errors than its sub-tests.");
    }
    // Insert the error message annotations for the static testing framework
    // and output the result.
    var annotatedContent =
        updateErrorExpectations(testFilePath, contentWithoutMarkers, errors[0]);
    if (writeToFile) {
      await testFile.writeAsString(annotatedContent);
      print("Converted test '${test.path.toNativePath()}'.");
    } else {
      print("-- ${test.path.toNativePath()}:");
      print(annotatedContent);
    }
    // Generate runtime tests for all sub-tests that are generated from the
    // 'none' case and those with 'ok' annotations.
    for (var i = 1; i < tests.length; ++i) {
      var test = tests[i].path.toNativePath();
      var base = basenameWithoutExtension(test);
      var key = base.split("_").last;
      if (key == "none" || cleanedTest.subTests[key] == "ok") {
        await createRuntimeTest(
            testFilePath, tests[i].path.toNativePath(), writeToFile);
      }
    }
  } on UnableToConvertException catch (exception) {
    print(
        "Could not convert ${test.path.toNativePath()}: ${exception.message}");
    exitCode = 1;
    return;
  } finally {
    outputDirectory.delete(recursive: true);
  }
}

Future<void> main(List<String> arguments) async {
  var parser = ArgParser();
  parser.addFlag("verbose", abbr: "v", help: "print additional information");
  parser.addFlag("write", abbr: "w", help: "write output to input file");
  parser.addMultiOption("enable-experiment",
      defaultsTo: <String>[], help: "Enable one or more experimental features");

  var results = parser.parse(arguments);
  if (results.rest.isEmpty) {
    print("Usage: convert_multi_test.dart [-v] [-w] <input files>");
    print(parser.usage);
    exitCode = 1;
    return;
  }
  var verbose = results["verbose"] as bool;
  var filePaths =
      results.rest.map((path) => Uri.base.resolve(path).toFilePath());
  var writeToFile = results["write"] as bool;
  for (var testFilePath in filePaths) {
    await convertFile(testFilePath, writeToFile, verbose,
        (results["enable-experiment"] as List).cast<String>());
  }
}

/// Invoke analyzer on [file] and gather all static errors it reports.
Future<List<StaticError>> _runAnalyzer(File file, List<String> options) async {
  var result = await Process.run(dartPath, [
    _analyzerPath,
    ...options,
    "--format=json",
    file.absolute.path,
  ]);

  // Analyzer returns 3 when it detects errors, 2 when it detects
  // warnings and --fatal-warnings is enabled, 1 when it detects
  // hints and --fatal-hints or --fatal-infos are enabled.
  if (result.exitCode < 0 || result.exitCode > 3) {
    print("Analyzer run failed: ${result.stdout}\n${result.stderr}");
    print("Error: failed to update ${file.path}");
    return const [];
  }

  var errors = <StaticError>[];
  var warnings = <StaticError>[];
  AnalysisCommandOutput.parseErrors(result.stdout as String, errors, warnings);

  return [...errors, ...warnings];
}

/// Invoke CFE on [file] and gather all static errors it reports.
Future<List<StaticError>> _runCfe(File file, List<String> options) async {
  var absolutePath = file.absolute.path;
  // TODO(rnystrom): Running the CFE command line each time is slow and wastes
  // time generating code, which we don't care about. Import it as a library or
  // at least run it in batch mode.
  var result = await Process.run(dartPath, [
    "pkg/front_end/tool/compile.dart",
    ...options,
    "--verify",
    "-o",
    "dev:null", // Output is only created for file URIs.
    absolutePath,
  ]);

  // Running the above command may generate a dill file next to the test, which
  // we don't want, so delete it if present.
  var dill = File("$absolutePath.dill");
  if (await dill.exists()) {
    await dill.delete();
  }

  if (result.exitCode != 0) {
    print("CFE run failed: ${result.stdout}\n${result.stderr}");
    print("Error: failed to update ${file.path}");
    return const [];
  }
  var errors = <StaticError>[];
  var warnings = <StaticError>[];
  FastaCommandOutput.parseErrors(result.stdout as String, errors, warnings);
  return [...errors, ...warnings];
}
