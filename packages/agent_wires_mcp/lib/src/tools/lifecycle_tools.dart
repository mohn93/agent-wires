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
      Tool(
        name: 'hot_reload',
        description:
            'Re-injects edited Dart sources into the running app and '
            'reassembles the widget tree. App state and current route are '
            'preserved. Takes ~1–3s.\n\n'
            'USE WHEN: the user has just edited source code and you want to '
            'verify the change without losing the current screen / login.\n'
            'DO NOT USE: as a generic "the app seems stuck" recovery — that '
            'is what wait_for_idle, snapshot, or stop_app + boot_app are '
            'for. Reflexive reloads waste time on no-op rebuilds.\n\n'
            'After this returns, your existing `element_id`s are STALE — '
            'call `snapshot` again before any further action. If the '
            'response has `success: false`, read `message`/`notices`: the '
            'reload was rejected (usually a compile error or a '
            'hot-reload-incompatible change like a new field on an enum). '
            'Tell the user what failed; do not retry blindly.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          try {
            final result = await session.hotReload();
            return _toolResult(jsonEncode(result));
          } catch (e) {
            return _toolError('hot_reload failed: $e');
          }
        },
      ),
      Tool(
        name: 'hot_restart',
        description:
            'Tears down the Dart isolate and re-runs `main()`. App state is '
            'LOST — back to splash/login screen. Takes ~3–8s. Slower than '
            'hot_reload but always works as long as the app compiles.\n\n'
            'USE WHEN: hot_reload was rejected (e.g. main() changed, '
            'top-level state needs to re-init), or the app is in an '
            'unrecoverable in-memory state. \n'
            'DO NOT USE: when hot_reload would suffice — the user will '
            'have to log in again. Also unsupported in attached mode '
            '(`serve --attach`): the caller owns the flutter process there.\n\n'
            'After this returns, your `element_id`s, route_stack, and any '
            'login session are all stale. Call `snapshot` and probably '
            'have to drive the login flow again.',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          try {
            final result = await session.hotRestart();
            return _toolResult(jsonEncode(result));
          } catch (e) {
            return _toolError('hot_restart failed: $e');
          }
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
