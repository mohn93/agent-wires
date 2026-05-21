import 'dart:convert';
import 'dart:developer' as developer;
import '../tree/snapshot_builder.dart';

class SnapshotExtension {
  static const String name = 'ext.qa.snapshot';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    try {
      final snap = SnapshotBuilder.build();
      return developer.ServiceExtensionResponse.result(jsonEncode(snap.toJson()));
    } catch (e, st) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': e.toString(), 'stack': st.toString()}),
      );
    }
  }
}
