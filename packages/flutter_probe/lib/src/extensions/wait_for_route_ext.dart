import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import '../probe.dart';

class WaitForRouteExtension {
  static const String name = 'ext.qa.wait_for_route';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final target = params['route'];
    if (target == null || target.isEmpty) {
      return _ok({'success': false, 'error': 'route required'});
    }
    final timeoutMs = int.tryParse(params['timeout_ms'] ?? '10000') ?? 10000;
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    while (DateTime.now().isBefore(deadline)) {
      if (FlutterProbe.routeTracker.currentRoute == target) {
        return _ok({'success': true, 'matched': true});
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return _ok({
      'success': true,
      'matched': false,
      'current_route': FlutterProbe.routeTracker.currentRoute,
    });
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> body) =>
      developer.ServiceExtensionResponse.result(jsonEncode(body));
}
