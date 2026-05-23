import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Extracts the current runtime value of stateful widgets and returns it as
/// a short, agent-friendly string.
///
/// Returns null for widgets that have no inherent state (Button, ListTile,
/// AppBar, etc.) — caller should omit the `state` field from the snapshot
/// record entirely.
class StateInference {
  static String? infer(Widget w) {
    if (w is Switch) return w.value ? 'on' : 'off';
    if (w is SwitchListTile) return w.value ? 'on' : 'off';
    if (w is CupertinoSwitch) return w.value ? 'on' : 'off';

    if (w is Checkbox) return _checkboxValue(w.value, w.tristate);
    if (w is CheckboxListTile) return _checkboxValue(w.value, w.tristate);

    // Radio.groupValue / onChanged are deprecated in favour of RadioGroup,
    // but the underlying widget still works and we need groupValue here to
    // decide selected/unselected.
    if (w is Radio) {
      // ignore: deprecated_member_use
      return w.value == w.groupValue ? 'selected' : 'unselected';
    }
    if (w is RadioListTile) {
      // ignore: deprecated_member_use
      return w.value == w.groupValue ? 'selected' : 'unselected';
    }

    if (w is Slider) {
      final v = w.value.toStringAsFixed(2);
      // Include the range only when bounds aren't the trivial 0..1 default.
      final hasCustomRange = w.min != 0.0 || w.max != 1.0;
      return hasCustomRange ? '$v (${w.min}..${w.max})' : v;
    }
    if (w is RangeSlider) {
      final lo = w.values.start.toStringAsFixed(2);
      final hi = w.values.end.toStringAsFixed(2);
      return '$lo..$hi (${w.min}..${w.max})';
    }

    return null;
  }

  static String _checkboxValue(bool? value, bool tristate) {
    if (value == null) return tristate ? 'indeterminate' : 'unchecked';
    return value ? 'checked' : 'unchecked';
  }
}
