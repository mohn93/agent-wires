import 'dart:io';
import 'package:flutter_probe_mcp/src/source/ast_parser.dart';
import 'package:test/test.dart';

void main() {
  test('returns enclosing method name for an offset inside the method body', () {
    const path = 'test/fixtures/sample_widget_file.dart';
    final name = AstParser.enclosingFunction(filePath: path, line: 5, column: 12);
    expect(name, '_buildRemoveButton');
  });

  test('returns null when file does not exist', () {
    final name = AstParser.enclosingFunction(filePath: 'nope.dart', line: 1, column: 1);
    expect(name, isNull);
  });

  test('re-parses when file is modified (mtime cache invalidation)', () async {
    final dir = await Directory.systemTemp.createTemp('ast_cache_test_');
    final file = File('${dir.path}/widget.dart');
    try {
      // Write initial version with a function named 'firstVersion'.
      await file.writeAsString('void firstVersion() {}');
      // Back-date the mtime by 2 seconds so the first parse has a past mtime.
      final past = DateTime.now().subtract(const Duration(seconds: 2));
      file.setLastModifiedSync(past);

      final name1 = AstParser.enclosingFunction(
        filePath: file.path,
        line: 1,
        column: 10,
      );
      expect(name1, 'firstVersion');

      // Overwrite with a different function name; mtime will be newer than cached.
      await file.writeAsString('void secondVersion() {}');

      final name2 = AstParser.enclosingFunction(
        filePath: file.path,
        line: 1,
        column: 10,
      );
      expect(name2, 'secondVersion',
          reason: 'cache should be invalidated after file is modified');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
