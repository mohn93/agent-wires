import 'package:flutter/material.dart';
import '../icons/icon_role_map.dart';

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

  static InferredRole infer(Element e) {
    final type = e.widget.runtimeType.toString();
    final role = _roleByType[type] ?? 'unknown';

    final text = _firstDescendantText(e);
    if (text != null && text.isNotEmpty) {
      return InferredRole(role: role, label: text, labelSource: LabelSource.textChild);
    }

    final iconRole = _firstDescendantIconRole(e);
    if (iconRole != null) {
      return InferredRole(role: role, label: iconRole, labelSource: LabelSource.icon);
    }

    return InferredRole(role: role, label: null, labelSource: LabelSource.none);
  }

  static String? _firstDescendantText(Element root) {
    String? found;
    void visit(Element e) {
      if (found != null) return;
      final w = e.widget;
      // Skip Icon subtrees — their internal RichText carries icon codepoints,
      // not human-readable text, and would be picked up before the Icon widget.
      if (w is Icon) return;
      if (w is Text && (w.data?.isNotEmpty ?? false)) {
        found = w.data;
        return;
      }
      if (w is RichText) {
        final s = w.text.toPlainText();
        // Exclude strings that consist solely of private-use / icon-font codepoints
        // (Material Icons live in the Unicode Private Use Area: U+E000–U+F8FF).
        if (s.isNotEmpty && !_isIconFontString(s)) {
          found = s;
          return;
        }
      }
      e.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
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
