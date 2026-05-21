import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
// ignore: unused_import — visitAncestorElements callback type lives in widgets
import 'package:flutter/widgets.dart';
import '../tree/classifier.dart';
import '../tree/raw_node.dart';
import '../tree/walker.dart';

class InspectExtension {
  static const String name = 'ext.qa.inspect';

  static Future<developer.ServiceExtensionResponse> handle(
    String method,
    Map<String, String> params,
  ) async {
    final id = params['element_id'];
    if (id == null || id.isEmpty) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.invalidParams,
        jsonEncode({'error': 'element_id required'}),
      );
    }

    final raw = ElementTreeWalker.walkFromRoot();

    // Apply the same filter as SnapshotBuilder so that the index (e_N) lines up.
    var idx = 0;
    RawNode? found;
    for (final node in raw) {
      final cls = Classifier.classify(node.element.widget);
      if (cls != Classification.promote) continue;
      if (node.bounds == null) continue; // off-screen / not laid out
      if (id == 'e_$idx') {
        found = node;
        break;
      }
      idx++;
    }

    if (found == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': 'element not found'}),
      );
    }

    final w = found.element.widget;
    final props = <String, String>{};
    final builder = DiagnosticPropertiesBuilder();
    w.debugFillProperties(builder);
    for (final p in builder.properties) {
      props[p.name ?? '?'] = p.value?.toString() ?? '';
    }

    final ancestors = <String>[];
    found.element.visitAncestorElements((a) {
      ancestors.add(a.widget.runtimeType.toString());
      return ancestors.length < 20;
    });

    return developer.ServiceExtensionResponse.result(jsonEncode({
      'widget_type': found.widgetType,
      'creation_location': found.creationLocation,
      'ancestor_types': ancestors,
      'properties': props,
    }));
  }
}
