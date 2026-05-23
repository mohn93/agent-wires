import 'dart:convert';
import 'dart:io';
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
            'valid until the next frame; re-snapshot after any state change.\n\n'
            'By default returns only labelled/actionable elements. The '
            'unresolved list (elements with no inferable label — decorative '
            'Listeners, unlabeled Switches, etc.) is hidden and replaced '
            'with `unresolved_count`. Pass `include_unresolved: true` only '
            'when you specifically need to address an unlabeled element '
            '(e.g. typing into a hidden pin-code field).',
        inputSchema: {
          'type': 'object',
          'properties': {
            'include_unresolved': {
              'type': 'boolean',
              'description':
                  'Include the verbose unresolved[] array of unlabeled '
                  'elements. Default false — usually 10–25k chars of noise.',
            },
          },
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final raw = await vm.callExtension('ext.qa.snapshot');
          final enriched = SnapshotEnricher.enrich(raw: raw, map: map);
          final includeUnresolved = args['include_unresolved'] == true;
          if (!includeUnresolved) {
            final unresolved = enriched['unresolved'];
            final count = unresolved is List ? unresolved.length : 0;
            enriched.remove('unresolved');
            enriched['unresolved_count'] = count;
          }
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
            'Captures the current frame as PNG and writes it to a tmp file; '
            'returns `{path, width, height, size_bytes}`. Read the file at '
            '`path` with your own image-viewing tool.\n\n'
            'ALMOST ALWAYS PREFER `snapshot` INSTEAD — snapshot gives you '
            'structured element_ids you can act on; screenshot gives you '
            'pixels you have to vision-parse. Use screenshot only when (a) '
            'you need to show the user what the screen looks like, (b) you '
            'need pixel-perfect details like colors or rendered text, or (c) '
            'something is drawn via Canvas/Skia and has no widget semantics '
            'so `snapshot` cannot see it. If showing to a human, pass '
            '`annotated: true` to overlay numbered Set-of-Mark boxes matching '
            'the latest snapshot — much more useful than raw pixels. Set '
            '`return_base64: true` only if you cannot read from disk (rare); '
            'PNGs are commonly 300k+ base64 chars and burn context.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'annotated': <String, dynamic>{'type': 'boolean'},
            'return_base64': <String, dynamic>{
              'type': 'boolean',
              'description':
                  'Return base64 PNG in `data_base64` instead of writing to '
                  'disk. Default false; the base64 is large and noisy.',
            },
          },
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final shotJson = await vm.callExtension('ext.qa.screenshot');
          final annotated = args['annotated'] == true;
          final returnBase64 = args['return_base64'] == true;

          var pngB64 = shotJson['data_base64'] as String;
          var elementCount = 0;
          var unresolvedCount = 0;
          if (annotated) {
            final snapRaw = await vm.callExtension('ext.qa.snapshot');
            final enriched = SnapshotEnricher.enrich(raw: snapRaw, map: map);
            final elements = ((enriched['elements'] as List?) ?? const [])
                .cast<Map<String, dynamic>>();
            final unresolvedList =
                ((enriched['unresolved'] as List?) ?? const [])
                    .cast<Map<String, dynamic>>();
            pngB64 = SomAnnotator.annotate(
              pngBase64: pngB64,
              elements: elements,
              unresolved: unresolvedList,
            );
            elementCount = elements.length;
            unresolvedCount = unresolvedList.length;
          }

          final pngBytes = base64Decode(pngB64);
          final payload = <String, dynamic>{
            'format': 'png',
            'width': shotJson['width'],
            'height': shotJson['height'],
            'size_bytes': pngBytes.length,
            if (annotated) ...{
              'annotated': true,
              'element_count': elementCount,
              'unresolved_count': unresolvedCount,
            },
          };

          if (returnBase64) {
            payload['data_base64'] = pngB64;
          } else {
            final path = _writeTmpPng(pngBytes, annotated: annotated);
            payload['path'] = path;
          }
          return _toolResult(jsonEncode(payload));
        },
      ),
    ];

String _writeTmpPng(List<int> bytes, {required bool annotated}) {
  final dir = Directory.systemTemp.createTempSync('agent_wires_screenshot_');
  final suffix = annotated ? '_annotated' : '';
  final file = File(
    '${dir.path}/screenshot${suffix}_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  file.writeAsBytesSync(bytes);
  return file.path;
}

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
