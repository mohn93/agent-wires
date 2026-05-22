import 'package:flutter/widgets.dart';
import '../tree/snapshot_builder.dart';

class ElementResolver {
  /// Resolves `e_<idx>` to the live [Element] the snapshot reported at that
  /// index. Must use the same selection pass as [SnapshotBuilder.build] so
  /// the snapshot's labels and the resolver's elements stay in sync — a
  /// mismatch shows up as "no EditableTextState in subtree of Listener"
  /// when an action lands on a plumbing widget instead of its TextField.
  static Element? resolve(String elementId) {
    if (!elementId.startsWith('e_')) return null;
    final idx = int.tryParse(elementId.substring(2));
    if (idx == null || idx < 0) return null;

    final kept = SnapshotBuilder.keptNodes();
    if (idx >= kept.length) return null;
    return kept[idx].element;
  }
}
