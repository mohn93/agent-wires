import '../map/map_record.dart';
import '../source/ast_parser.dart';

class SourceLocProposer {
  /// Parses `creationLocation` (format "file:line:column") and returns a label
  /// proposal derived from the enclosing function/method name.
  static ProposalRecord? propose({required String? creationLocation}) {
    if (creationLocation == null) return null;
    final parts = creationLocation.split(':');
    if (parts.length < 3) return null;
    final column = int.tryParse(parts.last);
    final line = int.tryParse(parts[parts.length - 2]);
    final file = parts.take(parts.length - 2).join(':');
    if (column == null || line == null || file.isEmpty) return null;

    final fn = AstParser.enclosingFunction(filePath: file, line: line, column: column);
    if (fn == null) return null;

    return ProposalRecord(
      source: 'source_location',
      label: _humanize(fn),
      confidence: 0.7,
      firstSeen: DateTime.now(),
    );
  }

  /// Turns a Dart identifier into a human-readable label.
  /// _buildRemoveButton → "Remove Button"
  /// onCheckoutPressed → "Checkout Pressed"
  static String _humanize(String identifier) {
    var name = identifier.startsWith('_') ? identifier.substring(1) : identifier;
    // Drop common prefixes
    for (final prefix in ['build', 'on']) {
      if (name.length > prefix.length &&
          name.toLowerCase().startsWith(prefix.toLowerCase()) &&
          name[prefix.length].toUpperCase() == name[prefix.length]) {
        name = name.substring(prefix.length);
        break;
      }
    }
    if (name.isEmpty) return identifier;
    // Capitalize the first letter
    name = name[0].toUpperCase() + name.substring(1);
    // Insert a space before each subsequent uppercase letter
    return name.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
  }
}
