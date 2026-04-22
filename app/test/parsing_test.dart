import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:negern/core/models/engine_kind.dart';
import 'package:negern/core/parsing/awg_parser.dart';
import 'package:negern/core/parsing/subscription_parser.dart';
import 'package:negern/core/parsing/vless_parser.dart';

void main() {
  group('VlessParser', () {
    test('parses reality vless URI', () {
      const uri =
          'vless://11111111-2222-3333-4444-555555555555@host.example.com:443'
          '?security=reality&sni=www.microsoft.com&pbk=PUBKEY&sid=0123'
          '&fp=chrome&type=tcp&flow=xtls-rprx-vision#My%20Server';
      final r = VlessParser.parse(uri);
      expect(r.name, 'My Server');
      expect(r.config['address'], 'host.example.com');
      expect(r.config['port'], 443);
      expect(r.config['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(r.config['security'], 'reality');
      expect(r.config['pbk'], 'PUBKEY');
      expect(r.config['flow'], 'xtls-rprx-vision');
    });

    test('throws on missing uuid', () {
      expect(() => VlessParser.parse('vless://host.example.com:443'),
          throwsA(isA<VlessParseException>()));
    });
  });

  group('AwgParser', () {
    test('parses AmneziaWG 1.5 conf', () {
      const cfg = '''
[Interface]
PrivateKey = aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa=
Address = 10.8.0.2/32
DNS = 1.1.1.1, 8.8.8.8
Jc = 4
Jmin = 40
Jmax = 70
S1 = 50
S2 = 100
H1 = 1
H2 = 2
H3 = 3
H4 = 4

[Peer]
PublicKey = bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb=
Endpoint = awg.example.com:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
''';
      final r = AwgParser.parse(cfg);
      expect(r.config['privateKey'], startsWith('aaaa'));
      expect(r.config['address'], '10.8.0.2/32');
      expect(r.config['dns'], ['1.1.1.1', '8.8.8.8']);
      expect(r.config['jc'], 4);
      expect(r.config['h4'], 4);
      final peer = r.config['peer'] as Map;
      expect(peer['publicKey'], startsWith('bbbb'));
      expect(peer['endpoint'], 'awg.example.com:51820');
      expect(peer['allowedIPs'], ['0.0.0.0/0']);
    });

    test('throws without [Peer]', () {
      expect(
        () => AwgParser.parse('[Interface]\nPrivateKey=x'),
        throwsA(isA<AwgParseException>()),
      );
    });
  });

  group('SubscriptionParser', () {
    test('decodes base64 vless list', () {
      final plain = [
        'vless://uuid-1@a.example:443?security=none&type=tcp#A',
        'vless://uuid-2@b.example:8443?security=reality&pbk=X&type=tcp#B',
      ].join('\n');
      final b64 = base64.encode(utf8.encode(plain));
      final profiles = SubscriptionParser.parse(b64);
      expect(profiles.length, 2);
      expect(profiles[0].engine, EngineKind.vless);
      expect(profiles[0].name, 'A');
      expect(profiles[1].name, 'B');
    });
  });
}
