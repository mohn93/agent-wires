import 'dart:convert';
import 'dart:developer' as developer;

import '../sync/network_log.dart';

class GetNetworkExtension {
  static const String name = 'ext.qa.get_network';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final since = params['since'];
    final limit = int.tryParse(params['limit'] ?? '') ?? 100;
    final entries = NetworkLog.query(since: since, limit: limit);
    return developer.ServiceExtensionResponse.result(jsonEncode({
      'entries': entries.map((e) => e.toJson()).toList(),
      'count': entries.length,
      'cursor': entries.isEmpty ? since : entries.last.startedAt,
    }));
  }
}
