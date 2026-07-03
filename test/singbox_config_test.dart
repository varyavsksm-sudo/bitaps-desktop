// Юнит-тесты чистого рантайм-критичного модуля singbox_config.dart (генератор sing-box конфига
// из share-link ключа). Плагинов не тянет → гоняется в обычном test-харнессе.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/singbox_config.dart';

void main() {
  group('outboundFromKey — VLESS + Reality', () {
    test('корректный VLESS+Reality с pbk собирается', () {
      const key =
          'vless://3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com&fp=chrome&pbk=PUBLICKEY123&sid=88';
      final out = outboundFromKey(key)!;
      expect(out['type'], 'vless');
      expect(out['tag'], 'proxy');
      expect(out['server'], 'vpn.bitaps.app');
      expect(out['server_port'], 443);
      expect(out['uuid'], '3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a');
      final tls = out['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], true);
      expect(tls['server_name'], 'www.microsoft.com');
      final reality = tls['reality'] as Map<String, dynamic>;
      expect(reality['enabled'], true);
      expect(reality['public_key'], 'PUBLICKEY123');
      expect(reality['short_id'], '88');
      expect((tls['utls'] as Map)['fingerprint'], 'chrome');
      // без transport для type=tcp
      expect(out.containsKey('transport'), false);
    });

    test('НЕГАТИВ: Reality без pbk → FormatException (а не битый конфиг)', () {
      const key =
          'vless://3a7c9f1e-0b2d-4e6f-9a1c-7b3e2f8d4c5a@vpn.bitaps.app:443?security=reality&type=tcp&sni=www.microsoft.com';
      expect(() => outboundFromKey(key), throwsFormatException);
      // и на верхнем уровне тоже фейлит, а не отдаёт полу-конфиг
      expect(() => singboxConfig(key), throwsFormatException);
    });
  });

  group('outboundFromKey — transports', () {
    test('VLESS ws-transport (path percent-decoded + Host header)', () {
      const key =
          'vless://uuid-ws@ws.example.com:443?security=tls&type=ws&path=%2Fvpn%2Fws&host=cdn.example.com';
      final out = outboundFromKey(key)!;
      final t = out['transport'] as Map<String, dynamic>;
      expect(t['type'], 'ws');
      expect(t['path'], '/vpn/ws'); // %2F → '/' через Uri.queryParameters
      expect((t['headers'] as Map)['Host'], 'cdn.example.com');
    });

    test('VLESS grpc-transport (service_name)', () {
      const key =
          'vless://uuid-grpc@grpc.example.com:2053?security=tls&type=grpc&serviceName=GunService';
      final out = outboundFromKey(key)!;
      final t = out['transport'] as Map<String, dynamic>;
      expect(t['type'], 'grpc');
      expect(t['service_name'], 'GunService');
    });
  });

  group('outboundFromKey — прочие протоколы / фолбэки', () {
    test('trojan: percent-decode пароля', () {
      // p%40ss%3Aword → 'p@ss:word'
      const key = 'trojan://p%40ss%3Aword@trojan.example.com:443?security=tls#name';
      final out = outboundFromKey(key)!;
      expect(out['type'], 'trojan');
      expect(out['password'], 'p@ss:word');
      expect((out['tls'] as Map)['enabled'], true);
    });

    test('vmess: base64 без паддинга декодируется (base64 fallback)', () {
      const vmessJson =
          '{"v":"2","ps":"n","add":"vm.example.com","port":"8443","id":"vmess-uuid","aid":"0","net":"ws","host":"h.example.com","path":"/p","tls":"tls"}';
      final b64 = base64.encode(utf8.encode(vmessJson)).replaceAll('=', ''); // без '='
      final out = outboundFromKey('vmess://$b64')!;
      expect(out['type'], 'vmess');
      expect(out['server'], 'vm.example.com');
      expect(out['server_port'], 8443);
      expect(out['uuid'], 'vmess-uuid');
      expect((out['tls'] as Map)['enabled'], true);
      expect((out['transport'] as Map)['type'], 'ws');
      expect((out['transport'] as Map)['path'], '/p');
    });

    test('shadowsocks форма A: base64(userinfo)@host:port', () {
      final userinfo = base64.encode(utf8.encode('aes-256-gcm:secretpass'));
      final out = outboundFromKey('ss://$userinfo@ss.example.com:8388#tag')!;
      expect(out['type'], 'shadowsocks');
      expect(out['server'], 'ss.example.com');
      expect(out['server_port'], 8388);
      expect(out['method'], 'aes-256-gcm');
      expect(out['password'], 'secretpass');
    });

    test('неизвестная схема → null', () {
      expect(outboundFromKey('ftp://nope.example.com'), isNull);
    });
  });

  group('singboxConfig — полный конфиг', () {
    const key =
        'vless://uuid-x@vpn.bitaps.app:443?security=reality&type=tcp&pbk=PUBKEY&sid=01';

    test('содержит tun-inbound, outbound proxy+direct и route', () {
      final cfg = singboxConfig(key);
      final inbounds = cfg['inbounds'] as List;
      expect((inbounds.first as Map)['type'], 'tun');
      final outbounds = cfg['outbounds'] as List;
      expect((outbounds[0] as Map)['tag'], 'proxy');
      expect((outbounds[1] as Map)['tag'], 'direct');
      expect(cfg.containsKey('dns'), true);
      expect(cfg.containsKey('route'), true);
    });

    test('singboxConfigJson отдаёт валидный JSON', () {
      final jsonStr = singboxConfigJson(key);
      final decoded = json.decode(jsonStr);
      expect(decoded, isA<Map>());
      expect(jsonStr.contains('"tag": "proxy"'), true);
    });

    test('невалидный ключ → FormatException', () {
      expect(() => singboxConfig('not-a-key'), throwsFormatException);
    });
  });
}
