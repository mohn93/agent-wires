import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/version.dart';

void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI to attach to (ws://...)')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final ArgResults parsed;
  try {
    parsed = parser.parse(args);
  } catch (e) {
    stderr.writeln('argument error: $e');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (parsed['help'] as bool) {
    stdout.writeln('flutter_qa_mcp — MCP server for Flutter QA agents\n');
    stdout.writeln(parser.usage);
    return;
  }
  if (parsed['version'] as bool) {
    stdout.writeln(packageVersion);
    return;
  }
  stderr.writeln('not yet implemented');
  exit(70);
}
