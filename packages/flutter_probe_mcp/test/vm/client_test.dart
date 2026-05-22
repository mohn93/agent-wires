import 'package:flutter_probe_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('throws ArgumentError for unsupported URI scheme', () async {
    expect(
      () => VmClient.connect(Uri.parse('ftp://localhost:1234')),
      throwsArgumentError,
    );
  });

  // The ws-URI normalisation is exercised indirectly by e2e tests against a
  // real device; here we just confirm http/ws/https/wss are all accepted by
  // the entry point (the actual socket connect will then fail, but that's
  // beyond the input-validation contract).
  test('accepts http, https, ws, wss schemes without throwing ArgumentError',
      () async {
    for (final uri in [
      'http://127.0.0.1:55555/abc=/',
      'https://127.0.0.1:55555/abc=/',
      'ws://127.0.0.1:55555/abc=/ws',
      'wss://127.0.0.1:55555/abc=/ws',
    ]) {
      try {
        await VmClient.connect(Uri.parse(uri));
      } on ArgumentError {
        fail('connect should not reject $uri');
      } catch (_) {
        // Connection failures are expected — no real VM on that port.
      }
    }
  });
}
