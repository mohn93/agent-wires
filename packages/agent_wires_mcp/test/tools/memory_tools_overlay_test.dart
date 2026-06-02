import 'dart:io';
import 'package:agent_wires_mcp/src/map/semantic_map.dart';
import 'package:agent_wires_mcp/src/session/app_session.dart';
import 'package:agent_wires_mcp/src/tools/memory_tools.dart';
import 'package:agent_wires_mcp/src/vm/client.dart';
import 'package:test/test.dart';

void main() {
  test('label_element with element_id calls ext.qa.inspect to highlight',
      () async {
    final vm = _RecordingVm();
    final session = AppSession.attached(vm);
    final tmp = await Directory.systemTemp.createTemp('memory_tools_overlay_');
    final map = SemanticMap(projectRoot: tmp.path);

    final tools = memoryTools(map, session: session);
    final label = tools.firstWhere((t) => t.name == 'label_element');

    await label.handler({'element_id': 'e_3', 'name': 'Submit'});

    expect(vm.calls.where((c) => c.$1 == 'ext.qa.inspect'), isNotEmpty);
    final inspectCall =
        vm.calls.firstWhere((c) => c.$1 == 'ext.qa.inspect');
    expect(inspectCall.$2?['element_id'], 'e_3');

    await tmp.delete(recursive: true);
  });
}

class _RecordingVm extends VmClient {
  _RecordingVm() : super.test();

  final List<(String, Map<String, dynamic>?)> calls = [];

  @override
  Future<Map<String, dynamic>> callExtension(
    String name, [
    Map<String, dynamic>? args,
  ]) async {
    calls.add((name, args));
    if (name == 'ext.qa.snapshot') {
      return {
        'elements': [
          {'id': 'e_3', 'fingerprint': 'fp_e3'},
        ],
      };
    }
    return {'ok': true};
  }
}
