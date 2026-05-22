import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class TextInputDriver {
  /// Sets the text on a TextField / EditableText rooted at `element`.
  /// Throws if no EditableTextState is found in the subtree.
  static Future<void> setText(Element element, String value) async {
    final editable = _findEditableTextState(element);
    if (editable == null) {
      throw StateError(
        'no EditableTextState in subtree of ${element.widget.runtimeType}',
      );
    }
    editable.userUpdateTextEditingValue(
      TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      ),
      SelectionChangedCause.keyboard,
    );
  }

  static EditableTextState? _findEditableTextState(Element root) {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }
    visit(root);
    return found;
  }
}
