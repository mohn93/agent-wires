import 'package:flutter_qa_probe/src/source/ast_parser.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
