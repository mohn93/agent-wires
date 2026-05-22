import 'dart:convert';
import 'dart:developer' as developer;

import '../logs/log_buffer.dart';

class GetLogsExtension {
  static const String name = 'ext.qa.get_logs';

  /// The buffer is owned by the probe and bound in [bind] when the
  /// probe installs. Tests use the same binding to inject fakes.
  static LogBuffer? _buffer;
  static void bind(LogBuffer buffer) => _buffer = buffer;

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final buf = _buffer;
    if (buf == null) {
      return developer.ServiceExtensionResponse.result(jsonEncode({
        'entries': const <Map<String, dynamic>>[],
        'count': 0,
      }));
    }
    final since = params['since'];
    final limit = int.tryParse(params['limit'] ?? '') ?? 200;
    final entries = buf.query(since: since, limit: limit);
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'entries': entries.map((e) => e.toJson()).toList(),
      'count': entries.length,
      'cursor': entries.isEmpty ? since : entries.last.timestamp,
    }));
  }
}
