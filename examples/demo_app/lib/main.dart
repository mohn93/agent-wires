// examples/demo_app/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_qa_probe/flutter_qa_probe.dart';

void main() {
  FlutterQAProbe.install();
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Demo',
      navigatorObservers: [FlutterQAProbe.routeTracker.createObserver()],
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/cart': (_) => const CartScreen(),
        '/stress': (_) => const StressScreen(),
      },
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Welcome'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/cart'),
              child: const Text('Go to cart'),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.shopping_cart),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/stress'),
              child: const Text('Stress test'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Long ListView screen used by perf benchmarks. ~6 widgets per row × 200 rows
/// ≈ 1200 logical widgets (plus Material/Scaffold/AppBar wrappers, well over
/// the 800-node target).
class StressScreen extends StatelessWidget {
  const StressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stress')),
      body: ListView.builder(
        itemCount: 200,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.label),
          title: Text('Item #$i'),
          subtitle: Text('Subtitle for item $i'),
          trailing: IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ),
      ),
    );
  }
}

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Item A'),
            trailing: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.delete),
            ),
          ),
          ListTile(
            title: const Text('Item B'),
            trailing: GestureDetector(
              onTap: () {},
              child: const Icon(Icons.delete),
            ),
          ),
        ],
      ),
    );
  }
}
