import 'package:flutter/widgets.dart';
import '../probe.dart';
import 'classifier.dart';
import 'element_record.dart';
import 'fingerprint.dart';
import 'role_inference.dart';
import 'walker.dart';

class SnapshotBuilder {
  static SnapshotRecord build() {
    final raw = ElementTreeWalker.walkFromRoot();
    final elements = <ElementRecord>[];

    for (final node in raw) {
      final cls = Classifier.classify(node.element.widget);
      if (cls != Classification.promote) continue;
      if (node.bounds == null) continue; // off-screen / not laid out

      final ancestors = _ancestorTypes(node.element);
      final inferred = RoleInference.infer(node.element);
      final fp = Fingerprint.compute(
        creationLocation: node.creationLocation,
        widgetType: node.widgetType,
        ancestorTypes: ancestors,
        siblingIndex: node.siblingIndex,
        visibleText: inferred.label,
      );

      elements.add(ElementRecord(
        id: 'e_${elements.length}',
        fingerprint: fp,
        widgetType: node.widgetType,
        role: inferred.role,
        label: inferred.label,
        labelSource: inferred.labelSource.name,
        bounds: node.bounds,
        creationLocation: node.creationLocation,
        enabled: true,
      ));
    }

    final media = MediaQueryData.fromView(WidgetsBinding.instance.platformDispatcher.views.first);
    return SnapshotRecord(
      route: FlutterQAProbe.routeTracker.currentRoute,
      viewport: media.size,
      elements: elements,
    );
  }

  static List<String> _ancestorTypes(Element e) {
    final out = <String>[];
    e.visitAncestorElements((a) {
      out.add(a.widget.runtimeType.toString());
      return out.length < 10;
    });
    return out.reversed.toList();
  }
}
