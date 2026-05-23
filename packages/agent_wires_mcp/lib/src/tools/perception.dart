import 'dart:convert';
import '../enrich/snapshot_enricher.dart';
import '../enrich/som_annotator.dart';
import '../map/semantic_map.dart';
import '../mcp/tool.dart';
import '../session/app_session.dart';

List<Tool> perceptionTools(AppSession session, SemanticMap map) => [
      Tool(
        name: 'snapshot',
        description:
            'PRIMARY PERCEPTION TOOL — call this first, and again after every '
            'action. Returns a denoised semantic tree of the visible screen: '
            'every actionable element gets a stable `element_id`, a `role` '
            '(button | textfield | tappable | ...), a human `label`, and '
            'on-screen `bounds`. Pass those `element_id`s to tap, enter_text, '
            'long_press, etc. Prefer this over `screenshot` — it is smaller, '
            'faster, and gives you ids you can act on. Element ids are only '
            'valid until the next frame; re-snapshot after any state change.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          final vm = await session.ensureReady();
          final raw = await vm.callExtension('ext.qa.snapshot');
          final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
          return _toolResult(jsonEncode(enriched));
        },
      ),
      Tool(
        name: 'inspect',
        description:
            'Drills into one element by `element_id` — returns the full '
            'widget chain (ancestors), properties, render-object info, and '
            'source location. Use this when `snapshot` shows something you '
            'do not understand or when you need a specific widget property '
            '(e.g. "is this Checkbox actually checked?"). Not needed for '
            'normal interaction — `snapshot` already has enough to tap things.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'element_id': {'type': 'string'},
          },
          'required': ['element_id'],
        },
        handler: (args) async {
          final id = args['element_id'] as String?;
          if (id == null) {
            return _toolError('element_id required');
          }
          final vm = await session.ensureReady();
          final json = await vm.callExtension('ext.qa.inspect', {'element_id': id});
          return _toolResult(jsonEncode(json));
        },
      ),
      Tool(
        name: 'screenshot',
        description:
            'Returns raw pixels (base64 PNG) of the current frame. '
            'ALMOST ALWAYS PREFER `snapshot` INSTEAD — snapshot gives you '
            'structured element_ids you can act on; screenshot gives you '
            'pixels you have to vision-parse. Use screenshot only when (a) '
            'you need to show the user what the screen looks like, (b) you '
            'need pixel-perfect details like colors or rendered text, or (c) '
            'something is drawn via Canvas/Skia and has no widget semantics '
            'so `snapshot` cannot see it. If showing to a human, pass '
            '`annotated: true` to overlay numbered Set-of-Mark boxes matching '
            'the latest snapshot — much more useful than raw pixels.',
        inputSchema: {
          'type': 'object',
          'properties': {'annotated': <String, dynamic>{'type': 'boolean'}},
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final shotJson = await vm.callExtension('ext.qa.screenshot');
          final annotated = args['annotated'] == true;
          if (!annotated) {
            return _toolResult(jsonEncode(shotJson));
          }
          final snapRaw = await vm.callExtension('ext.qa.snapshot');
          final enriched = SnapshotEnricher.enrich(raw: snapRaw, map: map);
          final elements = ((enriched['elements'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          final unresolvedList = ((enriched['unresolved'] as List?) ?? const [])
              .cast<Map<String, dynamic>>();
          final pngB64 = shotJson['data_base64'] as String;
          final annotatedPng = SomAnnotator.annotate(
            pngBase64: pngB64,
            elements: elements,
            unresolved: unresolvedList,
          );
          return _toolResult(jsonEncode({
            ...shotJson,
            'data_base64': annotatedPng,
            'annotated': true,
            'element_count': elements.length,
            'unresolved_count': unresolvedList.length,
          }));
        },
      ),
    ];

Map<String, dynamic> _toolResult(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };

Map<String, dynamic> _toolError(String message) => {
      'isError': true,
      'content': [
        {'type': 'text', 'text': message},
      ],
    };
