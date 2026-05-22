import 'package:flutter/material.dart';
import 'package:flutter_probe/src/icons/icon_role_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shopping_cart maps to "cart"', () {
    expect(IconRoleMap.roleFor(Icons.shopping_cart), 'cart');
  });
  test('delete maps to "delete"', () {
    expect(IconRoleMap.roleFor(Icons.delete), 'delete');
  });
  test('arrow_back maps to "back"', () {
    expect(IconRoleMap.roleFor(Icons.arrow_back), 'back');
  });
  test('close maps to "dismiss"', () {
    expect(IconRoleMap.roleFor(Icons.close), 'dismiss');
  });
  test('unknown icon returns null', () {
    expect(IconRoleMap.roleFor(const IconData(0x99999)), isNull);
  });
}
