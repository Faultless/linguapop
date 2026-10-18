import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:linguapop/services/import/import_service.dart';

void main() {
  test('UTF-8 Japanese text decodes intact', () {
    const text = '吾輩は猫である。名前はまだ無い。';
    expect(ImportService.decodeText(Uint8List.fromList(utf8.encode(text))), text);
  });

  test('a UTF-8 BOM is dropped', () {
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('猫')]);
    expect(ImportService.decodeText(bytes), '猫');
  });

  test('invalid UTF-8 still decodes rather than throwing', () {
    expect(ImportService.decodeText(Uint8List.fromList([0x82, 0xA0])), isNotEmpty);
  });
}
