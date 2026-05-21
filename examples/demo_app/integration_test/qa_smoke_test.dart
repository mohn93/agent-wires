// examples/demo_app/integration_test/qa_smoke_test.dart
import 'package:demo_app/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home renders and contains "Go to cart"', (tester) async {
    app.main();
    await tester.pumpAndSettle();
    expect(find.text('Go to cart'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
  });
}
