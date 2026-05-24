import 'package:flutter/material.dart';
import '../icons/icon_role_map.dart';
import 'snapshot_builder.dart';

enum LabelSource { textChild, icon, semantics, sourceLocation, none }

class InferredRole {
  InferredRole({
    required this.role,
    required this.label,
    required this.labelSource,
  });

  final String role;
  final String? label;
  final LabelSource labelSource;
}

class RoleInference {
  static const Map<String, String> _roleByType = {
    'ElevatedButton': 'button',
    'TextButton': 'button',
    'OutlinedButton': 'button',
    'IconButton': 'button',
    'FloatingActionButton': 'button',
    'TextField': 'textfield',
    'TextFormField': 'textfield',
    'EditableText': 'textfield',
    'Switch': 'switch',
    'Checkbox': 'checkbox',
    'Radio': 'radio',
    'Slider': 'slider',
    'ListTile': 'list_item',
    'AppBar': 'appbar',
    'Tab': 'tab',
    'GestureDetector': 'tappable',
    'InkWell': 'tappable',
    'Listener': 'tappable',
  };

  /// Maximum descendant Text widgets concatenated into a single label.
  /// Higher → richer disambiguation between sibling cards (e.g. one
  /// "Sub Total" invoice card vs. another). Lower → tighter labels.
  static const int _maxLabelParts = 4;

  /// Maximum total length of the combined label. Long enough to keep
  /// a card's identifying text but short enough to not spam the agent.
  static const int _maxLabelChars = 80;

  static InferredRole infer(Element e) {
    final type = e.widget.runtimeType.toString();
    final role = _roleByType[type] ?? 'unknown';

    final text = _descendantText(e);
    if (text != null && text.isNotEmpty) {
      return InferredRole(role: role, label: text, labelSource: LabelSource.textChild);
    }

    final iconRole = _firstDescendantIconRole(e);
    if (iconRole != null) {
      return InferredRole(role: role, label: iconRole, labelSource: LabelSource.icon);
    }

    return InferredRole(role: role, label: null, labelSource: LabelSource.none);
  }

  /// Collects up to [_maxLabelParts] descendant Text/RichText strings in
  /// DFS order and joins them with " · ". Single-Text widgets (e.g. a
  /// button "Submit") still produce just "Submit"; multi-Text rows (an
  /// invoice card with header + amount + status + number) get a label
  /// that actually distinguishes them from siblings.
  static String? _descendantText(Element root) {
    final parts = <String>[];
    var totalLen = 0;

    void visit(Element e) {
      if (parts.length >= _maxLabelParts) return;
      if (totalLen >= _maxLabelChars) return;
      // Don't pull text from occluded subtrees (a buried page underneath
      // a pushed route, or a page underneath an opaque modal barrier).
      // A surviving ancestor (the root Listener, the Navigator's Theater)
      // would otherwise label itself with text from screens the user
      // can't see.
      if (SnapshotBuilder.occludedElements.contains(e)) return;
      final w = e.widget;
      // Skip Icon subtrees — their internal RichText carries icon codepoints,
      // not human-readable text.
      if (w is Icon) return;
      String? s;
      if (w is Text && (w.data?.isNotEmpty ?? false)) {
        s = w.data;
      } else if (w is RichText) {
        final t = w.text.toPlainText();
        if (t.isNotEmpty && !_isIconFontString(t)) s = t;
      }
      if (s != null) {
        final trimmed = s.trim();
        if (trimmed.isNotEmpty &&
            (parts.isEmpty || parts.last != trimmed)) {
          parts.add(trimmed);
          totalLen += trimmed.length + 3; // " · "
        }
        // Texts don't have meaningful descendants for label collection.
        return;
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    if (parts.isEmpty) return null;
    var combined = parts.join(' · ');
    if (combined.length > _maxLabelChars) {
      combined = '${combined.substring(0, _maxLabelChars - 1)}…';
    }
    return combined;
  }

  /// Returns true when every code unit in [s] falls in the Unicode Private Use
  /// Area (U+E000–U+F8FF), which is where Material / Cupertino icon fonts live.
  static bool _isIconFontString(String s) {
    for (final c in s.runes) {
      if (c < 0xE000 || c > 0xF8FF) return false;
    }
    return true;
  }

  static String? _firstDescendantIconRole(Element root) {
    String? found;
    void visit(Element e) {
      if (found != null) return;
      if (SnapshotBuilder.occludedElements.contains(e)) return;
      final w = e.widget;
      if (w is Icon && w.icon != null) {
        final r = IconRoleMap.roleFor(w.icon!);
        if (r != null) {
          found = r;
          return;
        }
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }
}
