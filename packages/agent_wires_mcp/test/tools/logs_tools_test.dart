import 'package:agent_wires_mcp/src/tools/logs_tools.dart';
import 'package:test/test.dart';

void main() {
  group('capLogPayload (#6 get_logs size)', () {
    test('truncates an oversized stack field and marks how much was dropped',
        () {
      final huge = 'x' * 50000;
      final capped = capLogPayload({
        'entries': [
          {'timestamp': 't1', 'level': 'error', 'message': 'boom', 'stack': huge}
        ],
        'count': 1,
      }, maxFieldChars: 4000);
      final stack =
          ((capped['entries'] as List).first as Map)['stack'] as String;
      expect(stack.length, lessThan(4100),
          reason: 'a single stack must not blow the client token budget');
      expect(stack, startsWith('xxxx'));
      expect(stack, contains('truncated'));
      expect(stack, contains('46000'), reason: 'reports dropped char count');
    });

    test('truncates oversized message and error fields too', () {
      final capped = capLogPayload({
        'entries': [
          {
            'timestamp': 't',
            'level': 'error',
            'message': 'm' * 9000,
            'error': 'e' * 9000,
          }
        ],
      }, maxFieldChars: 4000);
      final e = (capped['entries'] as List).first as Map;
      expect((e['message'] as String).length, lessThan(4100));
      expect((e['error'] as String).length, lessThan(4100));
    });

    test('leaves short fields and other keys untouched', () {
      final input = {
        'entries': [
          {'timestamp': 't', 'level': 'info', 'message': 'hi', 'stack': 'short'}
        ],
        'count': 1,
        'cursor': 't',
      };
      expect(capLogPayload(input, maxFieldChars: 4000), input);
    });

    test('handles empty / missing entries gracefully', () {
      expect(capLogPayload({'entries': const [], 'count': 0}),
          {'entries': const [], 'count': 0});
      expect(capLogPayload({'count': 0}), {'count': 0});
    });
  });
}
