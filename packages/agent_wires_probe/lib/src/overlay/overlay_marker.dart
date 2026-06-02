import 'package:flutter/widgets.dart';

/// Wraps the action-overlay layer. The snapshot walker checks for this widget
/// type and skips the subtree, so the overlay — which is only for a human
/// watching — never appears in what the agent perceives.
class AgentWiresOverlayMarker extends StatelessWidget {
  const AgentWiresOverlayMarker({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
