import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_qa_mcp/src/dashboard/server.dart';
import 'package:flutter_qa_mcp/src/map/semantic_map.dart';
import 'package:flutter_qa_mcp/src/mcp/protocol.dart';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:flutter_qa_mcp/src/runner/flutter_runner.dart';
import 'package:flutter_qa_mcp/src/tools/action_tools.dart';
import 'package:flutter_qa_mcp/src/tools/memory_tools.dart';
import 'package:flutter_qa_mcp/src/tools/perception.dart';
import 'package:flutter_qa_mcp/src/tools/sync_tools.dart';
import 'package:flutter_qa_mcp/src/version.dart';
import 'package:flutter_qa_mcp/src/vm/client.dart';

Future<void> main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('-')).toList();
  final subcommand = positional.isNotEmpty ? positional.first : 'serve';
  final rest = [...args]..removeWhere((a) => a == subcommand);

  switch (subcommand) {
    case 'review':
      return _runReview(rest);
    case 'run':
      return _runRun(rest);
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

/// `flutter_qa_mcp run [-d <device>] [--project <flutter app dir>]`
///
/// One-shot wrapper: launches `flutter run --machine` on the given app,
/// discovers its VM service URI, and serves MCP over stdio. This is what
/// an MCP client (Claude Desktop, Cursor, etc.) should spawn so the user
/// doesn't have to copy/paste a URI every time.
Future<void> _runRun(List<String> args) async {
  final parser = ArgParser()
    ..addOption('device', abbr: 'd', help: 'Device id (default: flutter picks)')
    ..addOption('project',
        defaultsTo: Directory.current.path,
        help: 'Flutter app directory')
    ..addOption('flavor', help: 'Flutter build flavor (passed to flutter run)')
    ..addOption('target',
        abbr: 't', help: 'Entry-point .dart file (passed to flutter run)')
    ..addMultiOption('dart-define',
        help: 'Forwarded as --dart-define=KEY=VALUE (repeatable)')
    ..addOption('map-root', help: 'Project root for .flutter_qa/map.json')
    ..addFlag('help', abbr: 'h', negatable: false);
  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln(
        'flutter_qa_mcp run — boot a Flutter app and serve MCP in one step\n');
    stdout.writeln(parser.usage);
    return;
  }
  final project = parsed['project'] as String;
  final mapRoot = (parsed['map-root'] as String?) ?? project;
  final flavor = parsed['flavor'] as String?;
  final target = parsed['target'] as String?;
  final dartDefines = parsed['dart-define'] as List<String>;

  final extraArgs = <String>[
    if (flavor != null) ...['--flavor', flavor],
    if (target != null) ...['-t', target],
    for (final d in dartDefines) '--dart-define=$d',
  ];

  final runner = FlutterRunner(
    workingDirectory: project,
    deviceId: parsed['device'] as String?,
    flutterArgs: extraArgs,
  );
  stderr.writeln('flutter_qa_mcp: booting Flutter app in $project ...');
  await runner.start();
  stderr.writeln('flutter_qa_mcp: VM service @ ${runner.vmServiceUri}');

  final map = SemanticMap(projectRoot: mapRoot);
  await map.load();

  final vm = await VmClient.connect(runner.vmServiceUri);
  stderr.writeln('flutter_qa_mcp: attached to QA isolate, serving MCP.');

  await _serveStdio(vm: vm, map: map, onShutdown: () async {
    await vm.dispose();
    await runner.stop();
  });
}

Future<void> _runServe(List<String> args) async {
  final parser = ArgParser()
    ..addOption('attach', help: 'VM service URI (http(s):// or ws(s)://)')
    ..addOption('map-root',
        defaultsTo: Directory.current.path,
        help: 'Project root for .flutter_qa/map.json')
    ..addFlag('version', negatable: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final parsed = parser.parse(args);
  if (parsed['help'] as bool) {
    stdout.writeln('flutter_qa_mcp — MCP server for Flutter QA agents\n');
    stdout.writeln('Subcommands:');
    stdout.writeln('  run     boot a Flutter app and serve MCP in one step (preferred)');
    stdout.writeln('  serve   attach to an already-running VM service URI');
    stdout.writeln('  review  open the QA review dashboard\n');
    stdout.writeln('Flags for `serve` (the default subcommand):');
    stdout.writeln(parser.usage);
    return;
  }
  if (parsed['version'] as bool) {
    stdout.writeln(packageVersion);
    return;
  }
  final attach = parsed['attach'] as String?;
  if (attach == null) {
    stderr.writeln('--attach <vm-service-uri> is required for `serve`');
    stderr.writeln('(prefer `flutter_qa_mcp run` so the URI is auto-discovered)');
    exit(64);
  }
  final map = SemanticMap(projectRoot: parsed['map-root'] as String);
  await map.load();
  final vm = await VmClient.connect(Uri.parse(attach));
  await _serveStdio(vm: vm, map: map, onShutdown: () async {
    await vm.dispose();
  });
}

Future<void> _serveStdio({
  required VmClient vm,
  required SemanticMap map,
  required Future<void> Function() onShutdown,
}) async {
  final transport = StdioTransport(input: stdin, output: stdout);
  final protocol = McpProtocol(tools: [
    ...perceptionTools(vm, map),
    ...actionTools(vm),
    ...syncTools(vm),
    ...memoryTools(map, vm: vm),
  ]);

  late StreamSubscription sigint;
  sigint = ProcessSignal.sigint.watch().listen((_) async {
    await sigint.cancel();
    await onShutdown();
    exit(0);
  });

  await for (final msg in transport.incoming) {
    final resp = await protocol.handle(msg);
    if (resp != null) transport.send(resp);
  }
  await onShutdown();
}
