import 'package:demo_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home renders and stays alive for the MCP harness', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Go to cart'), findsOneWidget);

    // `tester.pump(Duration)` uses fake-async time and returns instantly,
    // which tears the widget tree down before our MCP harness can attach.
    // `runAsync` escapes the fake-async zone, so this blocks for real wall time.
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(minutes: 5));
    });
  }, timeout: const Timeout(Duration(minutes: 6)));
}
