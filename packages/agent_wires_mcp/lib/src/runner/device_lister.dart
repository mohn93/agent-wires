import 'dart:convert';
import 'dart:io';

/// One device entry as returned by [DeviceLister.list]. Curated subset of
/// what `flutter devices --machine` emits — agents need id, human name,
/// and the "is this a real or simulated device?" + "can flutter target it?"
/// flags. Capabilities are dropped to keep the payload small.
class DeviceInfo {
  DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.isEmulator,
    required this.isSupported,
    this.sdk,
  });

  final String id;
  final String name;
  final String platform;
  final bool isEmulator;
  final bool isSupported;
  final String? sdk;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
        'is_emulator': isEmulator,
        'is_supported': isSupported,
        if (sdk != null) 'sdk': sdk,
      };
}

class DeviceLister {
  /// Spawns `flutter devices --machine` and returns the parsed list. Runs
  /// in the given working directory (some flutter setups care). Bounded by
  /// [timeout]; flutter typically responds in <2s.
  static Future<List<DeviceInfo>> list({
    String? workingDirectory,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final result = await Process.run(
      'flutter',
      ['devices', '--machine'],
      workingDirectory: workingDirectory,
    ).timeout(timeout);
    if (result.exitCode != 0) {
      throw StateError(
        'flutter devices --machine exited ${result.exitCode}: '
        '${result.stderr ?? result.stdout}',
      );
    }
    final stdout = result.stdout as String;
    return parse(stdout);
  }

  /// Visible for testing — `flutter devices --machine` JSON parser.
  static List<DeviceInfo> parse(String json) {
    final start = json.indexOf('[');
    if (start < 0) return const [];
    final decoded = jsonDecode(json.substring(start));
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((m) => m.cast<String, dynamic>())
        .map((m) => DeviceInfo(
              id: (m['id'] as String?) ?? '',
              name: (m['name'] as String?) ?? '',
              platform: (m['targetPlatform'] as String?) ?? '',
              isEmulator: (m['emulator'] as bool?) ?? false,
              isSupported: (m['isSupported'] as bool?) ?? true,
              sdk: m['sdk'] as String?,
            ))
        .where((d) => d.id.isNotEmpty)
        .toList();
  }
}
