import 'package:agent_wires_probe/src/tree/state_inference.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Switch reports on/off', () {
    expect(StateInference.infer(Switch(value: true, onChanged: (_) {})), 'on');
    expect(StateInference.infer(Switch(value: false, onChanged: (_) {})), 'off');
  });

  test('SwitchListTile reports on/off', () {
    expect(
      StateInference.infer(
        SwitchListTile(value: true, onChanged: (_) {}, title: const Text('x')),
      ),
      'on',
    );
  });

  test('Checkbox reports checked/unchecked/indeterminate', () {
    expect(
      StateInference.infer(Checkbox(value: true, onChanged: (_) {})),
      'checked',
    );
    expect(
      StateInference.infer(Checkbox(value: false, onChanged: (_) {})),
      'unchecked',
    );
    expect(
      StateInference.infer(
        Checkbox(value: null, tristate: true, onChanged: (_) {}),
      ),
      'indeterminate',
    );
  });

  test('Radio reports selected/unselected by comparing value to groupValue',
      () {
    expect(
      // ignore: deprecated_member_use
      StateInference.infer(Radio<int>(value: 1, groupValue: 1, onChanged: (_) {})),
      'selected',
    );
    expect(
      // ignore: deprecated_member_use
      StateInference.infer(Radio<int>(value: 1, groupValue: 2, onChanged: (_) {})),
      'unselected',
    );
  });

  test('Slider reports the current value (with custom range when set)', () {
    expect(
      StateInference.infer(Slider(value: 0.42, onChanged: (_) {})),
      '0.42',
    );
    expect(
      StateInference.infer(Slider(
        value: 50,
        min: 0,
        max: 100,
        onChanged: (_) {},
      )),
      '50.00 (0.0..100.0)',
    );
  });

  test('returns null for stateless widgets', () {
    expect(StateInference.infer(const Text('x')), isNull);
    expect(
      StateInference.infer(ElevatedButton(onPressed: () {}, child: const Text('x'))),
      isNull,
    );
  });
}
