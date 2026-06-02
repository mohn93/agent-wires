const String packageVersion = '0.1.6';

/// The agent_wires_probe version this MCP build is designed to pair with. The
/// probe reports its own version over `ext.qa.ping`; `app_status` warns when
/// the running app's probe differs, since protocol drift between probe and
/// server has been observed to cause odd hangs (#6). Bump alongside the probe.
const String recommendedProbeVersion = '0.1.7';
