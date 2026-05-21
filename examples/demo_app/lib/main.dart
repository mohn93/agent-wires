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
      navigatorObservers: [FlutterQAProbe.routeTracker],
      initialRoute: '/',
      routes: {
        '/': (_) => const HomeScreen(),
        '/cart': (_) => const CartScreen(),
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
          ],
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
