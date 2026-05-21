import 'dart:async';
import 'dart:convert';

class StdioTransport {
  StdioTransport({required Stream<List<int>> input, required StreamSink<List<int>> output})
      : _output = output {
    _incoming = input
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .map((line) => jsonDecode(line) as Map<String, dynamic>);
  }

  late final Stream<Map<String, dynamic>> _incoming;
  final StreamSink<List<int>> _output;

  Stream<Map<String, dynamic>> get incoming => _incoming;

  void send(Map<String, dynamic> message) {
    _output.add(utf8.encode('${jsonEncode(message)}\n'));
  }
}
