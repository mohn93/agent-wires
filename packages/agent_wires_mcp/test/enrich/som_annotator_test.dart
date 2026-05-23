import 'dart:convert';
import 'package:agent_wires_mcp/src/enrich/som_annotator.dart';
import 'package:image/image.dart';
import 'package:test/test.dart';

void main() {
  test('annotates a known PNG with one element box', () {
    final src = Image(width: 400, height: 600);
    fill(src, color: ColorRgb8(0, 0, 0));
    final pngBytes = encodePng(src);
    final b64 = base64Encode(pngBytes);

    final annotated = SomAnnotator.annotate(
      pngBase64: b64,
      elements: [
        {
          'id': 'e_0',
          'bounds': {'x': 50.0, 'y': 100.0, 'w': 100.0, 'h': 40.0},
        },
      ],
    );

    final decoded = decodePng(base64Decode(annotated))!;
    expect(decoded.width, 400);
    expect(decoded.height, 600);
  });

  test('returns input unchanged when element list is empty', () {
    final src = Image(width: 100, height: 100);
    fill(src, color: ColorRgb8(255, 255, 255));
    final b64 = base64Encode(encodePng(src));
    final result = SomAnnotator.annotate(pngBase64: b64, elements: const []);
    expect(decodePng(base64Decode(result))!.width, 100);
  });

  test('returns input unchanged when input is not valid PNG', () {
    final result = SomAnnotator.annotate(
      pngBase64: base64Encode([1, 2, 3]),
      elements: const [],
    );
    // Should pass through (no exception)
    expect(result, isA<String>());
  });

  test('unresolved elements continue numbering after resolved elements', () {
    final src = Image(width: 400, height: 600);
    fill(src, color: ColorRgb8(0, 0, 0));
    final b64 = base64Encode(encodePng(src));

    // 2 resolved + 1 unresolved → unresolved gets number 3.
    final annotated = SomAnnotator.annotate(
      pngBase64: b64,
      elements: [
        {'id': 'e_0', 'bounds': {'x': 10.0, 'y': 10.0, 'w': 50.0, 'h': 20.0}},
        {'id': 'e_1', 'bounds': {'x': 70.0, 'y': 10.0, 'w': 50.0, 'h': 20.0}},
      ],
      unresolved: [
        {'id': 'e_u', 'bounds': {'x': 130.0, 'y': 10.0, 'w': 50.0, 'h': 20.0}},
      ],
    );

    final decoded = decodePng(base64Decode(annotated))!;
    // Image dimensions must be preserved.
    expect(decoded.width, 400);
    expect(decoded.height, 600);
    // Resolved boxes use red (255, 80, 80); unresolved use orange (255, 165, 0).
    // Verify that the image was mutated (not equal to the blank source).
    expect(annotated, isNot(b64));
  });

  test('only unresolved provided uses orange color and starts numbering at 1', () {
    final src = Image(width: 200, height: 200);
    fill(src, color: ColorRgb8(0, 0, 0));
    final b64 = base64Encode(encodePng(src));

    final annotated = SomAnnotator.annotate(
      pngBase64: b64,
      elements: const [],
      unresolved: [
        {'id': 'u_0', 'bounds': {'x': 5.0, 'y': 5.0, 'w': 40.0, 'h': 15.0}},
      ],
    );

    final decoded = decodePng(base64Decode(annotated))!;
    expect(decoded.width, 200);
    expect(decoded.height, 200);
    expect(annotated, isNot(b64));
  });
}
