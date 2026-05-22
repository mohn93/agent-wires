# flutter_qa_probe

Runtime probe that exposes a Flutter app's widget tree to QA agents via the Dart VM service.

## Install

Add as a dev dependency in your Flutter app's `pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_qa_probe:
    path: ../packages/flutter_qa_probe   # or git: / hosted: when published
```

## Use

```dart
import 'package:flutter_qa_probe/flutter_qa_probe.dart';

void main() {
  FlutterQAProbe.install();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorObservers: [FlutterQAProbe.routeTracker.createObserver()],
      // ...
    );
  }
}
```

`install()` is a no-op in release builds. Requires `--track-widget-creation` (default in debug and profile mode under `flutter run`).

## Exposed VM service extensions

- `ext.qa.ping` — health check
- `ext.qa.snapshot` — denoised semantic tree
- `ext.qa.inspect` — full widget chain for one element_id
- `ext.qa.screenshot` — base64 PNG of the current frame
