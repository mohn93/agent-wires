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
    final includeDescendants = params['include_descendants'] != 'false';
    final descendantDepth =
        int.tryParse(params['descendant_depth'] ?? '3') ?? 3;

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

    final body = <String, dynamic>{
      'widget_type': w.runtimeType.toString(),
      'ancestor_types': ancestors,
      'properties': props,
    };
    if (includeDescendants) {
      body['descendants'] =
          _collectDescendants(element, maxDepth: descendantDepth);
    }
    return developer.ServiceExtensionResponse.result(jsonEncode(body));
  }

  /// Walks descendants of [root] up to [maxDepth] levels. Returns one entry
  /// per element with depth, widget type, visible text when present, and —
  /// for [CustomPaint] descendants — the `painter` runtime type and `size`.
  /// The CustomPaint metadata lets the agent diagnose "this region is
  /// drawn pixels, I can't address inner parts" without having to guess
  /// from a Listener that wraps a Canvas (the agent flagged this for the
  /// PrecisionReactiveSlider's 20px thumb).
  ///
  /// Capped at 500 entries to handle deep Material/Cupertino subtrees
  /// (each interactive widget can stack 20+ plumbing layers).
  static List<Map<String, dynamic>> _collectDescendants(
    Element root, {
    required int maxDepth,
  }) {
    const cap = 500;
    final out = <Map<String, dynamic>>[];
    void visit(Element e, int depth) {
      if (out.length >= cap || depth > maxDepth) return;
      if (depth > 0) {
        final entry = <String, dynamic>{
          'depth': depth,
          'widget_type': e.widget.runtimeType.toString(),
        };
        final text = _extractText(e.widget);
        if (text != null && text.isNotEmpty) entry['visible_text'] = text;
        final w = e.widget;
        if (w is CustomPaint) {
          if (w.painter != null) {
            entry['painter'] = w.painter.runtimeType.toString();
          }
          if (w.foregroundPainter != null) {
            entry['foreground_painter'] =
                w.foregroundPainter.runtimeType.toString();
          }
          final ro = e.renderObject;
          if (ro is RenderBox && ro.hasSize) {
            entry['size'] = '${ro.size.width}x${ro.size.height}';
          }
        }
        out.add(entry);
      }
      e.visitChildren((c) => visit(c, depth + 1));
    }

    visit(root, 0);
    return out;
  }

  static String? _extractText(Widget w) {
    if (w is Text) return w.data;
    if (w is RichText) return w.text.toPlainText();
    return null;
  }
}
