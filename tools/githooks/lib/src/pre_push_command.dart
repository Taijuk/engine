// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.12

import 'dart:io' as io;

import 'package:args/command_runner.dart';
import 'package:clang_tidy/clang_tidy.dart';
import 'package:path/path.dart' as path;

/// The command that implements the pre-push githook
class PrePushCommand extends Command<bool> {
  @override
  final String name = 'pre-push';

  @override
  final String description = 'Checks to run before a "git push"';

  @override
  Future<bool> run() async {
    final Stopwatch sw = Stopwatch()..start();
    final bool verbose = globalResults!['verbose']! as bool;
    final String flutterRoot = globalResults!['flutter']! as String;
    final List<bool> checkResults = await Future.wait<bool>(<Future<bool>>[
      _runClangTidy(flutterRoot, verbose),
      _runFormatter(flutterRoot, verbose),
    ]);
    sw.stop();
    io.stdout.writeln('pre-push checks finished in ${sw.elapsed}');
    return !checkResults.contains(false);
  }

  Future<bool> _runClangTidy(String flutterRoot, bool verbose) async {
    // First ensure that out/host_debug/compile_commands.json exists by running
    // //flutter/tools/gn.
    final io.File compileCommands = io.File(path.join(
      flutterRoot,
      '..',
      'out',
      'host_debug',
      'compile_commands.json',
    ));
    if (!compileCommands.existsSync()) {
      final bool gnResult = await _runCheck(
        flutterRoot,
        path.join(flutterRoot, 'tools', 'gn'),
        <String>[],
        'GN for host_debug',
        verbose: verbose,
      );
      if (!gnResult) {
        return false;
      }
    }
    final StringBuffer outBuffer = StringBuffer();
    final StringBuffer errBuffer = StringBuffer();
    final ClangTidy clangTidy = ClangTidy(
      buildCommandsPath: compileCommands,
      repoPath: io.Directory(flutterRoot),
      outSink: outBuffer,
      errSink: errBuffer,
    );
    final int clangTidyResult = await clangTidy.run();
    if (clangTidyResult != 0) {
      io.stderr.write(errBuffer);
      return false;
    }
    return true;
  }

  Future<bool> _runFormatter(String flutterRoot, bool verbose) {
    final String ext = io.Platform.isWindows ? '.bat' : '.sh';
    return _runCheck(
      flutterRoot,
      path.join(flutterRoot, 'ci', 'format$ext'),
      <String>[],
      'Formatting check',
      verbose: verbose,
    );
  }

  Future<bool> _runCheck(
    String flutterRoot,
    String scriptPath,
    List<String> scriptArgs,
    String checkName, {
    bool verbose = false,
  }) async {
    if (verbose) {
      io.stdout.writeln('Starting "$checkName": $scriptPath');
    }
    final io.ProcessResult result = await io.Process.run(
      scriptPath,
      scriptArgs,
      workingDirectory: flutterRoot,
    );
    if (result.exitCode != 0) {
      final StringBuffer message = StringBuffer();
      message.writeln('Check "$checkName" failed.');
      message.writeln('command: $scriptPath ${scriptArgs.join(" ")}');
      message.writeln('working directory: $flutterRoot');
      message.writeln('exit code: ${result.exitCode}');
      message.writeln('stdout:');
      message.writeln(result.stdout);
      message.writeln('stderr:');
      message.writeln(result.stderr);
      io.stderr.write(message.toString());
      return false;
    }
    if (verbose) {
      io.stdout.writeln('Check "$checkName" finished successfully.');
    }
    return true;
  }
}