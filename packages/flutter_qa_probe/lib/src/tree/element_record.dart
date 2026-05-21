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
  final List<Proposal> proposals;

  Map<String, dynamic> toJson() => {
        'id': id,
        'fingerprint': fingerprint,
        'widget_type': widgetType,
        'role': role,
        if (label != null) 'label': label,
        'label_source': labelSource,
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
  SnapshotRecord({required this.route, required this.viewport, required this.elements, this.unresolved = const <ElementRecord>[]});
  final String? route;
  final Size viewport;
  final List<ElementRecord> elements;
  final List<ElementRecord> unresolved;

  Map<String, dynamic> toJson() => {
        if (route != null) 'route': route,
        'viewport': {'w': viewport.width, 'h': viewport.height},
        'elements': elements.map((e) => e.toJson()).toList(),
        'unresolved': unresolved.map((e) => e.toJson()).toList(),
      };
}
