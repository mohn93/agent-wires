import 'package:flutter_qa_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('throws ArgumentError for invalid URI scheme', () async {
    expect(
      () => VmClient.connect(Uri.parse('http://localhost:1234')),
      throwsArgumentError,
    );
  });
}
