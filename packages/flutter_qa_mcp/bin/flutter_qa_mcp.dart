import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/dashboard/server.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/version.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';

Future<void> main(List<String> args) async {
  // Identify subcommand vs flag-only invocation.
  final positional = args.where((a) => !a.startsWith('-')).toList();
  final subcommand = positional.isNotEmpty ? positional.first : 'serve';

  // Strip the subcommand from the args so each handler sees only its own flags.
  final rest = [...args]..removeWhere((a) => a == subcommand);

  switch (subcommand) {
    case 'review':
      return _runReview(rest);
    case 'serve':
    default:
      return _runServe(rest);
  }
}

Future<void> _runReview(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', defaultsTo: '7345')
    ..addOption('project-root', defaultsTo: Directory.current.path)
    ..addFlag('help', abbr: 'h', negatable: false);
  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('flutter_qa_mcp review — open the QA review dashboard\n');
    stdout.writeln(parser.usage);
    return;
  }
  final port = int.tryParse(parsed['port'] as String) ?? 7345;
  final root = parsed['project-root'] as String;
  final map = SemanticMap(projectRoot: root);
  await map.load();
  final server = DashboardServer(map: map);
  await server.start(port: port);
  stdout.writeln('Dashboard running at http://localhost:${server.port}');
  stdout.writeln('Press Ctrl+C to stop.');
  await ProcessSignal.sigint.watch().first;
  await server.stop();
}

Future<void> _runServe(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI (ws://...)')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('flutter_qa_mcp — MCP server for Flutter QA agents\n');
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

  final map = SemanticMap(projectRoot: Directory.current.path);
  await map.load();

  final vm = await VmClient.connect(Uri.parse(attach));
  final transport = StdioTransport(input: stdin, output: stdout);
  final protocol = McpProtocol(tools: [
    ...perceptionTools(vm, map),
    ...actionTools(vm),
    ...syncTools(vm),
    ...memoryTools(map),
  ]);

  await for (final msg in transport.incoming) {
    final resp = await protocol.handle(msg);
    if (resp != null) transport.send(resp);
  }
}
