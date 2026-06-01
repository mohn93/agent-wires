/// The agent_wires_probe package version, surfaced over `ext.qa.ping` so the
/// MCP server can detect and warn on probe/server version skew — protocol
/// drift between the two has been observed to cause odd hangs (#6).
///
/// Keep this in sync with `pubspec.yaml`.
const String probeVersion = '0.1.5';
