// packages/flutter_probe_mcp/lib/src/map/semantic_map.dart
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'map_record.dart';

class SemanticMap {
  SemanticMap({required this.projectRoot});
  final String projectRoot;
  final Map<String, MapEntry> _entries = {};

  Iterable<MapEntry> get entries => _entries.values;

  MapEntry? get(String fingerprint) => _entries[fingerprint];

  void upsert(MapEntry entry) {
    _entries[entry.fingerprint] = entry;
  }

  void delete(String fingerprint) {
    _entries.remove(fingerprint);
  }

  String get _filePath => p.join(projectRoot, '.flutter_qa', 'map.json');

  Future<void> load() async {
    final file = File(_filePath);
    if (!file.existsSync()) return;
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final list = (raw['entries'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .map(MapEntry.fromJson);
    _entries.clear();
    for (final e in list) {
      _entries[e.fingerprint] = e;
    }
  }

  Future<void> save() async {
    final dir = Directory(p.dirname(_filePath));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final body = {
      'version': 1,
      'entries': _entries.values.map((e) => e.toJson()).toList(),
    };
    final tmp = File('$_filePath.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(body));
    await tmp.rename(_filePath);
  }
}
