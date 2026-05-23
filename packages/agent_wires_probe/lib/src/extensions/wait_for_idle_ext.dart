import 'dart:convert';
import 'dart:developer' as developer;
import '../sync/idle_predicate.dart';

class WaitForIdleExtension {
  static const String name = 'ext.qa.wait_for_idle';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '10000') ?? 10000;
    final idle = await IdlePredicate.waitUntilIdle(
      timeout: Duration(milliseconds: timeoutMs),
    );
    return developer.ServiceExtensionResponse.result(
      jsonEncode({'success': true, 'idle': idle}),
    );
  }
}
