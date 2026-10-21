import 'dart:convert';

import 'package:flutter_hbb/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared server config ignores private credentials on import and export', () {
    final incoming = <String, dynamic>{
      'host': 'id.example.com',
      'relay': 'relay.example.com',
      'api': 'https://api.example.com',
      'key': 'public-server-key',
      'secret': [1, 2, 3],
      'private_key': '••••••••••••••••••••',
      'access_key': 'private-secret',
      'allow_public': true,
    };
    final json = jsonEncode(incoming);
    final encoded = base64UrlEncode(utf8.encode(json)).split('').reversed.join('');
    for (final input in [json, encoded]) {
      final config = ServerConfig.decode(input);
      final exported = jsonDecode(utf8.decode(base64Url.decode(
        config.encode().split('').reversed.join(''),
      ))) as Map<String, dynamic>;
      expect(exported, {
        'host': 'id.example.com',
        'relay': 'relay.example.com',
        'api': 'https://api.example.com',
        'key': 'public-server-key',
      });
    }
  });
}
