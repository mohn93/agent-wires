import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_qa_probe/src/logs/log_buffer.dart';
import 'package:flutter_qa_probe/src/logs/log_capture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debugPrint is teed into the buffer AND still reaches the original sink',
      () {
    final buf = LogBuffer();
    final original = debugPrint;
    final seenByOriginal = <String?>[];
    debugPrint = (String? msg, {int? wrapWidth}) => seenByOriginal.add(msg);
    addTearDown(() => debugPrint = original);

    LogCapture.install(buf);

    debugPrint('hello from a test');

    expect(seenByOriginal, contains('hello from a test'));
    final entries = buf.query();
    expect(entries.map((e) => e.message), contains('hello from a test'));
    expect(entries.last.level, 'debug');
  });

  test('FlutterError.onError captures the exception + stack', () {
    final buf = LogBuffer();
    LogCapture.install(buf);

    FlutterError.onError!(FlutterErrorDetails(
      exception: StateError('boom'),
      stack: StackTrace.fromString('fake stack'),
      library: 'test',
    ));

    final errs = buf.query().where((e) => e.level == 'error').toList();
    expect(errs, isNotEmpty);
    expect(errs.last.error, contains('boom'));
    expect(errs.last.stack, contains('fake stack'));
    expect(errs.last.loggerName, 'FlutterError');
  });
}
