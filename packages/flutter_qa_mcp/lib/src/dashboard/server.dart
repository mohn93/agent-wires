// packages/flutter_qa_mcp/lib/src/dashboard/server.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../map/map_record.dart';
import '../map/semantic_map.dart';

class DashboardServer {
  DashboardServer({required this.map});
  final SemanticMap map;

  HttpServer? _server;
  int get port => _server?.port ?? 0;

  Future<void> start({int port = 7345, String host = 'localhost'}) async {
    final router = Router()
      ..get('/api/labels', _getLabels)
      ..get('/api/unresolved', _getUnresolved)
      ..post('/api/label', _postLabel)
      ..post('/api/dismiss', _postDismiss)
      ..get('/', _serveIndex)
      ..get('/main.js', _serveJs)
      ..get('/style.css', _serveCss);

    final handler = const Pipeline().addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Response _getLabels(Request request) {
    final labels = map.entries
        .where((e) => e.humanLabel != null)
        .map((e) => e.toJson())
        .toList();
    return Response.ok(
      jsonEncode({'labels': labels}),
      headers: {'content-type': 'application/json'},
    );
  }

  Response _getUnresolved(Request request) {
    final unresolved = map.entries
        .where((e) => e.humanLabel == null && !e.dismissed)
        .map((e) => e.toJson())
        .toList();
    return Response.ok(
      jsonEncode({'unresolved': unresolved}),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> _postLabel(Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fp = body['fingerprint'] as String?;
    final name = body['name'] as String?;
    if (fp == null || name == null) {
      return Response.badRequest(body: jsonEncode({'error': 'fingerprint and name required'}));
    }
    final existing = map.get(fp);
    if (existing == null) {
      map.upsert(MapEntry(fingerprint: fp, humanLabel: name, observationCount: 1));
    } else {
      existing.humanLabel = name;
    }
    await map.save();
    return Response.ok(jsonEncode({'success': true}), headers: {'content-type': 'application/json'});
  }

  Future<Response> _postDismiss(Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final fp = body['fingerprint'] as String?;
    if (fp == null) {
      return Response.badRequest(body: jsonEncode({'error': 'fingerprint required'}));
    }
    final existing = map.get(fp);
    if (existing != null) {
      existing.dismissed = true;
    } else {
      map.upsert(MapEntry(fingerprint: fp, dismissed: true));
    }
    await map.save();
    return Response.ok(jsonEncode({'success': true}), headers: {'content-type': 'application/json'});
  }

  Response _serveIndex(Request request) => Response.ok(
        _indexHtml,
        headers: {'content-type': 'text/html'},
      );

  Response _serveJs(Request request) => Response.ok(
        _mainJs,
        headers: {'content-type': 'application/javascript'},
      );

  Response _serveCss(Request request) => Response.ok(
        _styleCss,
        headers: {'content-type': 'text/css'},
      );
}

// Scaffold static assets. Task 11 will replace these with the real review UI.
const String _indexHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Flutter QA Review</title>
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <h1>Flutter QA Review</h1>
    <div id="root">Loading…</div>
    <script src="/main.js"></script>
  </body>
</html>
''';

const String _mainJs = '''
async function load() {
  const root = document.getElementById('root');
  root.textContent = 'Dashboard scaffold — Task 11 will fill this in.';
}
load();
''';

const String _styleCss = '''
body { font-family: -apple-system, sans-serif; margin: 2rem; }
''';
