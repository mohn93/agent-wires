import 'dart:async';
import 'dart:convert';

import '../mcp/tool.dart';
import '../runner/device_lister.dart';
import '../session/app_session.dart';

/// Tools that govern the app lifecycle itself — boot it, query state, stop it.
///
/// These are deliberately listed first in `tools/list` so agents discover them
/// before reaching for perception/action tools. Description text instructs the
/// agent to call `boot_app` once at the start of a session.
List<Tool> lifecycleTools(AppSession session) => [
      Tool(
        name: 'list_devices',
        description:
            'Returns every device flutter can target right now — connected '
            'phones, booted simulators, macOS desktop, Chrome. Each entry '
            'is `{id, name, platform, is_emulator, is_supported, sdk}`. '
            'Call this BEFORE boot_app when more than one device might be '
            'available (a plugged-in phone PLUS a booted simulator is the '
            'classic 10-min-hang trigger — flutter picks the phone and '
            'stalls on signing). Ask the user which to use, then pass that '
            'id to `boot_app({device_id: "..."})`. Safe to call any time; '
            'cheap (~1s).',
        inputSchema: {'type': 'object', 'properties': {}},
        handler: (_) async {
          try {
            final devices = await DeviceLister.list();
            return _toolResult(jsonEncode({
              'devices': devices.map((d) => d.toJson()).toList(),
            }));
          } catch (e) {
            return _toolError('list_devices failed: $e');
          }
        },
      ),
      Tool(
        name: 'boot_app',
        description:
            'Boots the configured Flutter app on a device/simulator and '
            'attaches the probe. Call this ONCE at the start of a session. '
            'First call on a cold cache can take 30s–10min while flutter '
            'compiles (large apps with firebase, native plugins, etc. land '
            'on the upper end). Returns the resulting app state and VM '
            'service URI. Idempotent — if already booted, returns '
            'immediately. If a prior boot timed out or was stopped, just '
            'call boot_app again; it will reset and retry.\n\n'
            'DEVICE SELECTION: If more than one device might be available '
            '(plugged-in phone + booted simulator is the classic case), '
            'call `list_devices` first and ASK THE USER which to use; '
            'flutter\'s default pick can stall for minutes on signing for '
            'a physical device. Pass the chosen id as `device_id`. The '
            'selection sticks until the next stop_app.\n\n'
            'For long boots, pass `wait: false` — boot_app returns '
            'immediately with state="booting", and you can poll '
            '`app_status` to watch `latest_progress` ("Running Xcode '
            'build...", "Installing Pods...") and decide whether to keep '
            'waiting or `stop_app`. Subsequent action tools (snapshot, '
            'tap, etc.) auto-wait for the boot to finish.\n\n'
            'After this succeeds, the typical agent loop is:\n'
            '  1. `snapshot` — see what is on screen, get element_ids\n'
            '  2. pick the element you want\n'
            '  3. `tap` / `enter_text` / `scroll` / etc.\n'
            '  4. `wait_for_idle` (or wait_for_route / wait_for_element)\n'
            '  5. `snapshot` again — element_ids from step 1 are now stale\n\n'
            'Use `screenshot` only when you specifically need pixels.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'device_id': {
              'type': 'string',
              'description':
                  'Device id from `list_devices`. Overrides any default '
                  'set at MCP registration time. Sticks until the next '
                  'stop_app. Omit to use whatever was already configured '
                  '(or let flutter pick).',
            },
            'wait': {
              'type': 'boolean',
              'description':
                  'When false, kick off the boot in the background and '
                  'return state="booting" immediately so you can poll '
                  'app_status during a long compile. Default true (block '
                  'until ready). Use false when you expect the boot to '
                  'take more than a minute or two.',
            },
          },
        },
        handler: (args) async {
          final deviceId = args['device_id'];
          if (deviceId is String && deviceId.isNotEmpty) {
            try {
              session.selectDevice(deviceId);
            } catch (e) {
              return _toolError('device selection rejected: $e');
            }
          }
          final wait = args['wait'] != false;
          if (wait) {
            try {
              await session.ensureReady();
            } catch (e) {
              return _toolError('boot_app failed: $e');
            }
            return _toolResult(jsonEncode(_statusPayload(session)));
          }
          // Fire-and-forget: kick off the boot but don't await it. Errors
          // surface via app_status.lastError on the next poll. Subsequent
          // tool calls (snapshot etc.) auto-wait via ensureReady's shared
          // boot future.
          unawaited(_fireAndForgetBoot(session));
          return _toolResult(jsonEncode(_statusPayload(session)));
        },
      ),
      Tool(
        name: 'app_status',
        description:
            'Returns the current lifecycle state of the app under test '
            '(idle | booting | ready | exited), the VM service URI, last '
            'error if any, and `latest_progress` — the most recent message '
            'from `flutter run --machine` (e.g. "Running Xcode build...", '
            '"Installing Pods...", "Launching lib/main.dart on iPhone 15..."). '
            'When boot_app appears stuck, call app_status to see what step '
            'it is on; a stale latest_progress for several minutes means '
            'the underlying flutter process is hung. Cheap; safe to poll. '
            'Never starts the app.',
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

Future<void> _fireAndForgetBoot(AppSession session) async {
  try {
    await session.ensureReady();
  } catch (_) {
    // Errors are observable via app_status.last_error on the next poll.
    // Swallowing here prevents an unhandled-exception crash on the MCP
    // server's root zone.
  }
}

Map<String, dynamic> _statusPayload(AppSession session) => {
      'state': session.state.name,
      if (session.vmServiceUri != null)
        'vm_service_uri': session.vmServiceUri.toString(),
      if (session.deviceId != null) 'device_id': session.deviceId,
      if (session.lastError != null) 'last_error': session.lastError,
      if (session.latestProgress != null)
        'latest_progress': session.latestProgress,
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
