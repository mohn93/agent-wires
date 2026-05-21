import '../map/semantic_map.dart';
import 'sourceloc_proposer.dart';

class SnapshotEnricher {
  static Map<String, dynamic> enrich({
    required Map<String, dynamic> raw,
    required SemanticMap map,
  }) {
    final elements = <Map<String, dynamic>>[
      ...((raw['elements'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e)),
    ];
    final unresolvedOut = <Map<String, dynamic>>[];

    for (final element in ((raw['unresolved'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))) {
      final fp = element['fingerprint'] as String?;
      final mapped = fp == null ? null : map.get(fp);

      // Fix 3: skip dismissed entries entirely.
      if (mapped?.dismissed == true) continue;

      if (mapped?.humanLabel != null) {
        // Fix 2: for an unresolved element being promoted by a human label,
        // set label, label_source, AND persistent_label.
        element['label'] = mapped!.humanLabel;
        element['label_source'] = 'human';
        element['persistent_label'] = mapped.humanLabel;
        elements.add(element);
        continue;
      }

      final proposals = <Map<String, dynamic>>[];
      final loc = element['creation_location'] as String?;
      final srcProp = SourceLocProposer.propose(creationLocation: loc);
      if (srcProp != null) {
        proposals.add(srcProp.toJson());
      }
      if (mapped != null) {
        for (final p in mapped.proposals) {
          proposals.add(p.toJson());
        }
      }
      if (proposals.isNotEmpty) {
        element['proposals'] = proposals;
      }
      unresolvedOut.add(element);
    }

    // Fix 2: for already-resolved elements with a human label, keep the
    // original label/label_source intact and add persistent_label alongside.
    for (final el in elements) {
      final fp = el['fingerprint'] as String?;
      final mapped = fp == null ? null : map.get(fp);
      if (mapped?.humanLabel != null) {
        el['persistent_label'] = mapped!.humanLabel;
      }
    }

    return {
      ...raw,
      'elements': elements,
      'unresolved': unresolvedOut,
    };
  }
}
