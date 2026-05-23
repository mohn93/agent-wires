import 'package:flutter/widgets.dart';

class Proposal {
  Proposal({required this.source, required this.label, required this.confidence});
  final String source;
  final String label;
  final double confidence;
  Map<String, dynamic> toJson() => {
        'source': source,
        'label': label,
        'confidence': confidence,
      };
}

class ElementRecord {
  ElementRecord({
    required this.id,
    required this.fingerprint,
    required this.widgetType,
    required this.role,
    required this.label,
    required this.labelSource,
    required this.bounds,
    required this.creationLocation,
    required this.enabled,
    this.state,
    this.proposals = const [],
  });

  final String id;
  final String fingerprint;
  final String widgetType;
  final String role;
  final String? label;
  final String labelSource;
  final Rect? bounds;
  final String? creationLocation;
  final bool enabled;

  /// Current runtime value of stateful widgets — `"on"`/`"off"` for
  /// Switch/SwitchListTile, `"checked"`/`"unchecked"`/`"indeterminate"` for
  /// Checkbox/CheckboxListTile, `"selected"`/`"unselected"` for Radio,
  /// the slider position for Slider, etc. Null for widgets that have no
  /// inherent state (Button, ListTile, etc.).
  ///
  /// Mutable so a post-pass can copy the state of a contained Switch up to
  /// its labelled ListTile wrapper, sparing the agent from having to inspect
  /// a separate inner element to read a toggle's value.
  String? state;
  final List<Proposal> proposals;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'widget_type': widgetType,
        'role': role,
        if (label != null) 'label': label,
        'label_source': labelSource,
        if (state != null) 'state': state,
        if (bounds != null)
          'bounds': {
            'x': bounds!.left,
            'y': bounds!.top,
            'w': bounds!.width,
            'h': bounds!.height,
          },
        if (creationLocation != null) 'creation_location': creationLocation,
        'enabled': enabled,
        if (proposals.isNotEmpty) 'proposals': proposals.map((p) => p.toJson()).toList(),
      };
}

class SnapshotRecord {
  SnapshotRecord({
    required this.route,
    required this.routeStack,
    required this.viewport,
    required this.elements,
    this.unresolved = const <ElementRecord>[],
  });
  final String? route;

  /// Every observed navigator's current top-of-stack route, most recent
  /// first. For AutoRoute tab apps where the outer route stays `MainRoute`
  /// across bottom-nav switches, this distinguishes the active tab —
  /// `["DomainsRoute", "MainRoute"]` vs. `["InvoicesRoute", "MainRoute"]`.
  final List<String> routeStack;

  final Size viewport;
  final List<ElementRecord> elements;
  final List<ElementRecord> unresolved;

  Map<String, dynamic> toJson() => {
        if (route != null) 'route': route,
        if (routeStack.isNotEmpty) 'route_stack': routeStack,
        'viewport': {'w': viewport.width, 'h': viewport.height},
        'elements': elements.map((e) => e.toJson()).toList(),
        'unresolved': unresolved.map((e) => e.toJson()).toList(),
      };
}
