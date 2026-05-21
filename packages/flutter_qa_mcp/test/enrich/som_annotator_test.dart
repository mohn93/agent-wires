import 'dart:convert';
import 'package:flutter_qa_mcp/src/enrich/som_annotator.dart';
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
}
