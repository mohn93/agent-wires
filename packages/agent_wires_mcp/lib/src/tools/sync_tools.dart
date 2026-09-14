import 'dart:convert';
import '../mcp/tool.dart';
import '../session/app_session.dart';

/// The probe waits up to `timeout_ms` before answering, so the VM-service
/// call must be allowed to outlive that wait — otherwise a legitimate long
/// `wait_for_element` reads as a dead socket. Margin covers the snapshot
/// polling inside the probe plus transport.
Duration callTimeoutFor(Object? timeoutMs, {required int probeDefaultMs}) {
  final ms = switch (timeoutMs) {
    num n => n.toInt(),
    String s => num.tryParse(s)?.toInt() ?? probeDefaultMs,
    _ => probeDefaultMs,
  };
  // Bound the wait so a typo (timeout_ms: 30000000) cannot hang a tool call.
  final bounded = ms.clamp(0, maxProbeWaitMs);
  return Duration(milliseconds: bounded) + const Duration(seconds: 10);
}

/// Longest probe-side wait a sync tool will honour (10 minutes).
const int maxProbeWaitMs = 10 * 60 * 1000;

List<Tool> syncTools(AppSession session) => [
      Tool(
        name: 'wait_for_idle',
        description:
            'GENERIC POST-ACTION SYNC. Returns when there are no pending '
            'frames, no running animations, and no in-flight HTTP. Use this '
            'after any action when you do not know specifically what to wait '
            'for ("I tapped Submit, now wait for things to settle"). Bounded '
            'by `timeout_ms` (default 10000).\n\n'
            'On timeout, returns `{idle: false, blocked_by: [...]}` listing '
            'what is still active (`scheduled_frame`, `transient_callback`, '
            '`in_flight_http:N`) so you know whether to wait longer, retry, '
            'or just proceed.\n\n'
            'Animation-heavy screens (sliders with springs, fade chips) may '
            'never settle — pass `ignore_animations: true` to wait only for '
            'HTTP to finish and skip the frame/animation checks.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'timeout_ms': {'type': 'integer'},
            'ignore_animations': {
              'type': 'boolean',
              'description':
                  'Skip the scheduled-frame and transient-callback checks; '
                      'wait only for in-flight HTTP. Use on screens with '
                      'continuous animations that never settle.',
            },
          },
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtensionWithTimeout(
            'ext.qa.wait_for_idle',
            {
              if (args['timeout_ms'] != null)
                'timeout_ms': args['timeout_ms'].toString(),
              if (args['ignore_animations'] == true)
                'ignore_animations': 'true',
            },
            callTimeoutFor(args['timeout_ms'], probeDefaultMs: 10000),
          );
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_route',
        description:
            'NAVIGATION SYNC. Returns when the current named route matches '
            '`route`. Use after taps that navigate (Sign In → MainRoute, '
            'tapping a list item → DetailRoute) when you know the route '
            'name. More precise than `wait_for_idle` — does not return '
            'until the new screen is mounted.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'route': {'type': 'string'},
            'timeout_ms': {'type': 'integer'},
          },
          'required': ['route'],
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtensionWithTimeout(
            'ext.qa.wait_for_route',
            {
              'route': args['route'],
              if (args['timeout_ms'] != null)
                'timeout_ms': args['timeout_ms'].toString(),
            },
            callTimeoutFor(args['timeout_ms'], probeDefaultMs: 10000),
          );
          return _result(jsonEncode(json));
        },
      ),
      Tool(
        name: 'wait_for_element',
        description:
            'CONTENT SYNC. Returns when an element matching `label` and/or '
            '`role` appears in the snapshot. Use when you are waiting for a '
            'specific widget to render (a toast, a row in a list that loads '
            'async, a button that becomes enabled). Polls the snapshot — '
            'cheaper than re-snapshotting in a loop yourself.\n\n'
            '`label` matches exactly by default. Labels are inferred from '
            'descendant text (e.g. "Domains · Manage your domains"), so when '
            'you only know part of it pass `match: "substring"` for a '
            'case-insensitive, word-boundary match (an exact hit still wins). '
            'The response says which via `match`: "exact" | "substring" | '
            '"role", and echoes the matched `label` and `element_id`.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'label': {'type': 'string'},
            'role': {'type': 'string'},
            'match': {
              'type': 'string',
              'enum': ['exact', 'substring'],
              'description':
                  'How `label` is compared. "exact" (default) or "substring" '
                  '(case-insensitive, word-boundary).',
            },
            'timeout_ms': {'type': 'integer'},
          },
        },
        handler: (args) async {
          final vm = await session.ensureReady();
          final json = await vm.callExtensionWithTimeout(
            'ext.qa.wait_for_element',
            {
              if (args['label'] != null) 'label': args['label'],
              if (args['role'] != null) 'role': args['role'],
              if (args['match'] != null) 'match': args['match'].toString(),
              if (args['timeout_ms'] != null)
                'timeout_ms': args['timeout_ms'].toString(),
            },
            callTimeoutFor(args['timeout_ms'], probeDefaultMs: 5000),
          );
          return _result(jsonEncode(json));
        },
      ),
    ];

Map<String, dynamic> _result(String text) => {
      'content': [
        {'type': 'text', 'text': text},
      ],
    };
