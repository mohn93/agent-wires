import 'package:flutter/material.dart';

enum Classification { promote, skip, collapse }

class Classifier {
  static const Set<String> _promote = {
    'ElevatedButton', 'TextButton', 'OutlinedButton', 'IconButton',
    'FloatingActionButton', 'TextField', 'TextFormField',
    'Switch', 'Checkbox', 'Radio', 'Slider',
    'DropdownButton', 'PopupMenuButton',
    'AppBar', 'BottomNavigationBar', 'Tab', 'Drawer',
    'Dialog', 'AlertDialog', 'BottomSheet', 'SnackBar',
    'ListTile', 'GestureDetector', 'InkWell', 'Listener',
  };

  static const Set<String> _collapse = {
    'Text', 'RichText', 'Icon', 'ImageIcon',
  };

  // ignore: unused_field
  static const Set<String> _skip = {
    'Padding', 'Center', 'Align', 'SizedBox', 'Container',
    'Expanded', 'Flexible', 'Row', 'Column', 'Stack', 'Wrap',
    'ConstrainedBox', 'FractionallySizedBox',
    'Theme', 'MediaQuery', 'DefaultTextStyle', 'IconTheme',
    'Directionality', 'Material',
    'Builder', 'LayoutBuilder', 'AnimatedBuilder',
    'ValueListenableBuilder', 'StreamBuilder',
  };

  static Classification classifyByType(String widgetType) {
    if (_promote.contains(widgetType)) return Classification.promote;
    if (_collapse.contains(widgetType)) return Classification.collapse;
    return Classification.skip;
  }

  static Classification classify(Widget w) {
    if (w is GestureDetector) {
      return _hasGestureHandler(w) ? Classification.promote : Classification.skip;
    }
    if (w is InkWell) {
      return (w.onTap != null || w.onLongPress != null || w.onDoubleTap != null)
          ? Classification.promote
          : Classification.skip;
    }
    return classifyByType(w.runtimeType.toString());
  }

  static bool _hasGestureHandler(GestureDetector g) {
    return g.onTap != null ||
        g.onLongPress != null ||
        g.onDoubleTap != null ||
        g.onPanStart != null ||
        g.onHorizontalDragStart != null ||
        g.onVerticalDragStart != null;
  }
}
