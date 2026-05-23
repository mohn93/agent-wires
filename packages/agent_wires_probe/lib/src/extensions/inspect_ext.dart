import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
// ignore: unused_import — visitAncestorElements callback type lives in widgets
import 'package:flutter/widgets.dart';
import '../resolver/element_resolver.dart';

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

    final element = ElementResolver.resolve(id);

    if (element == null) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        jsonEncode({'error': 'element not found'}),
      );
    }

    final w = element.widget;
    final props = <String, String>{};
    final builder = DiagnosticPropertiesBuilder();
    w.debugFillProperties(builder);
    for (final p in builder.properties) {
      props[p.name ?? '?'] = p.value?.toString() ?? '';
    }

    final ancestors = <String>[];
    element.visitAncestorElements((a) {
      ancestors.add(a.widget.runtimeType.toString());
      return ancestors.length < 20;
    });

    return developer.ServiceExtensionResponse.result(jsonEncode({
      'widget_type': w.runtimeType.toString(),
      'ancestor_types': ancestors,
      'properties': props,
    }));
  }
}
