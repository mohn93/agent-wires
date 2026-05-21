import 'dart:async';
import 'dart:convert';
import 'package:flutter_qa_mcp/src/mcp/transport.dart';
import 'package:test/test.dart';

void main() {
  test('decodes single-line JSON messages from stdin stream', () async {
    final input = Stream<List<int>>.fromIterable([
      utf8.encode('{"jsonrpc":"2.0","id":1,"method":"ping"}\n'),
      utf8.encode('{"jsonrpc":"2.0","id":2,"method":"pong"}\n'),
    ]);
    final outBuf = <List<int>>[];
    final transport = StdioTransport(input: input, output: _CollectSink(outBuf));
    final received = await transport.incoming.take(2).toList();
    expect(received[0]['method'], 'ping');
    expect(received[1]['method'], 'pong');
  });

  test('send writes a single line of JSON', () async {
    final outBuf = <List<int>>[];
    final transport = StdioTransport(
      input: const Stream.empty(),
      output: _CollectSink(outBuf),
    );
    transport.send({'jsonrpc': '2.0', 'id': 1, 'result': {'ok': true}});
    await Future<void>.delayed(Duration.zero);
    final text = utf8.decode(outBuf.expand((b) => b).toList());
    expect(text.trim(), '{"jsonrpc":"2.0","id":1,"result":{"ok":true}}');
  });
}

class _CollectSink implements StreamSink<List<int>> {
  _CollectSink(this.buf);
  final List<List<int>> buf;
  @override
  void add(List<int> data) => buf.add(data);
  @override
  Future close() async {}
  @override
  Future addStream(Stream<List<int>> stream) async {
    await for (final c in stream) buf.add(c);
  }
  @override
  void addError(error, [StackTrace? st]) {}
  @override
  Future get done => Future.value();
}
