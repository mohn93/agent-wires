import 'dart:convert';
import 'package:crypto/crypto.dart';

class Fingerprint {
  static String compute({
    required String? creationLocation,
    required String widgetType,
    required List<String> ancestorTypes,
    required int siblingIndex,
    required String? visibleText,
  }) {
    final raw = StringBuffer()
      ..write(creationLocation ?? '?')
      ..write('|')
      ..write(widgetType)
      ..write('|')
      ..write(ancestorTypes.join('>'))
      ..write('|')
      ..write(siblingIndex)
      ..write('|')
      ..write(visibleText ?? '');
    final digest = sha1.convert(utf8.encode(raw.toString())).toString();
    return 'f_${digest.substring(0, 12)}';
  }
}
