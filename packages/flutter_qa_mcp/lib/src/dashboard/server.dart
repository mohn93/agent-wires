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
    final s = _server;
    if (s == null) return;
    try {
      await s.close().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await s.close(force: true);
    }
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
        .toList()
      ..sort((a, b) => b.observationCount.compareTo(a.observationCount));
    return Response.ok(
      jsonEncode({'unresolved': unresolved.map((e) => e.toJson()).toList()}),
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

const String _indexHtml = '''
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>Flutter QA Review</title>
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <header>
      <h1>Flutter QA — Review</h1>
      <div id="status" class="status">…</div>
    </header>
    <main>
      <section>
        <h2>Unresolved (<span id="unresolved-count">0</span>)</h2>
        <ul id="unresolved-list" class="list"></ul>
      </section>
      <section>
        <h2>Labeled (<span id="labeled-count">0</span>)</h2>
        <ul id="labeled-list" class="list compact"></ul>
      </section>
    </main>
    <script src="/main.js"></script>
  </body>
</html>
''';

const String _mainJs = r'''
const POLL_MS = 3000;

async function fetchJson(url, opts) {
  const res = await fetch(url, opts);
  if (!res.ok) throw new Error(res.statusText);
  return res.json();
}

function el(tag, attrs = {}, children = []) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'onclick') e.addEventListener('click', v);
    else e.setAttribute(k, v);
  }
  for (const c of children) {
    e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return e;
}

function renderUnresolved(entry) {
  const fp = entry.fingerprint;
  const top = (entry.proposals || []).slice().sort((a, b) => b.confidence - a.confidence)[0];
  const labelHint = top ? `${top.label} (from ${top.source}, ${(top.confidence * 100) | 0}%)` : '—';

  const input = el('input', {type: 'text', placeholder: top ? top.label : 'Enter label…'});

  const accept = el('button', {
    onclick: async () => {
      const name = (input.value || (top && top.label) || '').trim();
      if (!name) return;
      await fetchJson('/api/label', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({fingerprint: fp, name}),
      });
      refresh();
    },
  }, ['Accept']);

  const dismiss = el('button', {
    onclick: async () => {
      await fetchJson('/api/dismiss', {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({fingerprint: fp}),
      });
      refresh();
    },
  }, ['Dismiss']);

  return el('li', {}, [
    el('div', {class: 'fp'}, [fp]),
    el('div', {class: 'meta'}, [
      entry.creation_location || '(no source location)',
      ' • ',
      entry.screen_context || '(unknown screen)',
    ]),
    el('div', {class: 'hint'}, ['Proposal: ', labelHint]),
    el('div', {class: 'actions'}, [input, accept, dismiss]),
  ]);
}

function renderLabeled(entry) {
  return el('li', {}, [
    el('strong', {}, [entry.human_label || '(unlabeled)']),
    ' — ',
    el('code', {}, [entry.fingerprint]),
    ' (',
    String(entry.observation_count || 0),
    ' observations)',
  ]);
}

async function refresh() {
  document.getElementById('status').textContent = 'Refreshing…';
  try {
    const [unresolved, labeled] = await Promise.all([
      fetchJson('/api/unresolved'),
      fetchJson('/api/labels'),
    ]);
    const u = unresolved.unresolved || [];
    const l = labeled.labels || [];
    document.getElementById('unresolved-count').textContent = String(u.length);
    document.getElementById('labeled-count').textContent = String(l.length);

    const ul = document.getElementById('unresolved-list');
    ul.replaceChildren(...u.map(renderUnresolved));
    const ll = document.getElementById('labeled-list');
    ll.replaceChildren(...l.map(renderLabeled));

    document.getElementById('status').textContent = `Updated ${new Date().toLocaleTimeString()}`;
  } catch (e) {
    document.getElementById('status').textContent = `Error: ${e.message}`;
  }
}

refresh();
setInterval(refresh, POLL_MS);
''';

const String _styleCss = r'''
* { box-sizing: border-box; }
body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; margin: 2rem; color: #1a1a1a; background: #fafafa; }
header { display: flex; justify-content: space-between; align-items: baseline; border-bottom: 1px solid #ddd; padding-bottom: 0.5rem; margin-bottom: 1.5rem; }
.status { font-size: 0.85rem; color: #666; }
section { margin-bottom: 2rem; }
.list { list-style: none; padding: 0; }
.list li { padding: 1rem; background: white; border: 1px solid #e5e5e5; border-radius: 6px; margin-bottom: 0.75rem; }
.list.compact li { padding: 0.4rem 0.75rem; font-size: 0.9rem; }
.fp { font-family: monospace; font-size: 0.8rem; color: #888; }
.meta { font-size: 0.85rem; color: #555; margin: 0.25rem 0; }
.hint { font-size: 0.95rem; margin: 0.25rem 0; color: #224; }
.actions { display: flex; gap: 0.5rem; margin-top: 0.5rem; }
.actions input { flex: 1; padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; }
button { padding: 0.5rem 1rem; border: 1px solid #ccc; background: white; cursor: pointer; border-radius: 4px; }
button:hover { background: #f0f0f0; }
code { font-family: monospace; background: #eee; padding: 1px 4px; border-radius: 3px; }
''';
