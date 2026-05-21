import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/version.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI (ws://...)')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln(parser.usage);
    return;
  }
  if (parsed['version'] as bool) {
    stdout.writeln(packageVersion);
    return;
  }
  final attach = parsed['attach'] as String?;
  if (attach == null) {
    stderr.writeln('--attach <vm-service-uri> is required');
    exit(64);
  }

  final vm = await VmClient.connect(Uri.parse(attach));
  final transport = StdioTransport(input: stdin, output: stdout);
  final protocol = McpProtocol(tools: perceptionTools(vm));

  await for (final msg in transport.incoming) {
    final resp = await protocol.handle(msg);
    if (resp != null) transport.send(resp);
  }
}
