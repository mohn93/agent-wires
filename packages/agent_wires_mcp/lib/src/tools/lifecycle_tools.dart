import 'dart:convert';

import '../mcp/tool.dart';
import '../session/app_session.dart';

/// Tools that govern the app lifecycle itself — boot it, query state, stop it.
///
/// These are deliberately listed first in `tools/list` so agents discover them
/// before reaching for perception/action tools. Description text instructs the
/// agent to call `boot_app` once at the start of a session.
List<Tool> lifecycleTools(AppSession session) => [
      Tool(
        name: 'boot_app',
        description:
            'Boots the configured Flutter app on a device/simulator and '
            'attaches the probe. Call this ONCE at the start of a session. '
            'First call on a cold cache can take 30s–2min while flutter '
            'compiles. Returns the resulting app state and VM service URI. '
            'Idempotent — if already booted, returns immediately.\n\n'
            'After this succeeds, the typical agent loop is:\n'
            '  1. `snapshot` — see what is on screen, get element_ids\n'
            '  2. pick the element you want\n'
            '  3. `tap` / `enter_text` / `scroll` / etc.\n'
            '  4. `wait_for_idle` (or wait_for_route / wait_for_element)\n'
            '  5. `snapshot` again — element_ids from step 1 are now stale\n\n'
            'Use `screenshot` only when you specifically need pixels.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          try {
            await session.ensureReady();
          } catch (e) {
            return _toolError('boot_app failed: $e');
          }
          return _toolResult(jsonEncode(_statusPayload(session)));
        },
      ),
      Tool(
        name: 'app_status',
        description:
            'Returns the current lifecycle state of the app under test '
            '(idle | booting | ready | exited), plus the VM service URI and '
            'last error if any. Cheap; safe to poll. Never starts the app.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async => _toolResult(jsonEncode(_statusPayload(session))),
      ),
      Tool(
        name: 'stop_app',
        description:
            'Stops the running Flutter app and detaches the probe. Use this '
            'to free the device or recover from a stuck session. After this '
            'returns, the session is exited; the agent must call boot_app '
            'again to drive the app.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          await session.dispose();
          return _toolResult(jsonEncode(_statusPayload(session)));
        },
      ),
    ];

Map<String, dynamic> _statusPayload(AppSession session) => {
      'state': session.state.name,
      if (session.vmServiceUri != null)
        'vm_service_uri': session.vmServiceUri.toString(),
      if (session.deviceId != null) 'device_id': session.deviceId,
      if (session.lastError != null) 'last_error': session.lastError,
    };

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
