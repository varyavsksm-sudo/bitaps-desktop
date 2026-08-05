// Стартовая уборка за прошлой сессией (cleanupStale): решение по liveness + строки реестра.
//
// Зачем именно эти тесты. Сама уборка неотделима от ОС (reg.exe, сокеты, taskkill), но её
// РЕШЕНИЕ — чистая функция, и перепутать ветки недопустимо: «снять при живом движке» —
// fail-open (гасим трафик другой копии), «не снять при мёртвом» — у человека нет интернета
// после краша/перезагрузки. Рядом фиксируются парсеры строк реестра, от которых решение
// зависит: порт движка из ProxyServer, слияние ProxyOverride и отбор СВОИХ xray.exe по пути.
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/desktop_engine.dart';

void main() {
  group('decideStaleCleanup: решение уборки по liveness', () {
    test('прокси не наш — не трогаем никогда', () {
      expect(SystemProxy.decideStaleCleanup(proxyIsOurs: false, engineAlive: false),
          StaleCleanup.nothing);
      expect(SystemProxy.decideStaleCleanup(proxyIsOurs: false, engineAlive: true),
          StaleCleanup.nothing,
          reason: 'даже при живом порту чужой прокси не наш — не лезем');
    });

    test('прокси наш и порт слушает — туннель другой ЖИВОЙ копии, прокси держим', () {
      expect(SystemProxy.decideStaleCleanup(proxyIsOurs: true, engineAlive: true),
          StaleCleanup.keptAlive,
          reason: 'снять прокси у живого туннеля = fail-open (аудит п.1/п.4)');
    });

    test('прокси наш и порт молчит — протухший: снимаем и добиваем сироту', () {
      expect(SystemProxy.decideStaleCleanup(proxyIsOurs: true, engineAlive: false),
          StaleCleanup.cleaned,
          reason: 'иначе после краша/перезагрузки у человека «нет интернета» (аудит п.3)');
    });
  });

  group('winProxyServerPorts: порты движка из ProxyServer', () {
    test('разбирает типовую строку http/https/socks', () {
      expect(
        SystemProxy.winProxyServerPorts(
            'http=127.0.0.1:40000;https=127.0.0.1:40001;socks=127.0.0.1:40002'),
        {40000, 40001, 40002},
      );
    });

    test('дедупликация и формат «просто хост:порт»', () {
      expect(SystemProxy.winProxyServerPorts('127.0.0.1:40000'), {40000});
      expect(
        SystemProxy.winProxyServerPorts('http=127.0.0.1:40000;socks=127.0.0.1:40000'),
        {40000},
      );
    });

    test('чужие адреса и мусор игнорируются', () {
      expect(SystemProxy.winProxyServerPorts('http=10.0.0.1:8080'), isEmpty,
          reason: 'прокси не на localhost — портов движка в нём нет');
      expect(SystemProxy.winProxyServerPorts(''), isEmpty);
      expect(SystemProxy.winProxyServerPorts('127.0.0.1:99999'), isEmpty,
          reason: 'порт вне диапазона не считается');
      expect(SystemProxy.winProxyServerPorts('127.0.0.1:0'), isEmpty);
    });
  });

  group('winProxyOverride: обход прокси при нашем включении', () {
    test('пусто — только <local>', () {
      expect(SystemProxy.winProxyOverride(''), '<local>');
    });

    test('чужие записи сохраняются, <local> добавляется в конец', () {
      expect(SystemProxy.winProxyOverride('contoso.com; 192.168.* '),
          'contoso.com;192.168.*;<local>');
    });

    test('<local> не дублируется (регистр не важен)', () {
      expect(SystemProxy.winProxyOverride('<local>'), '<local>');
      expect(SystemProxy.winProxyOverride('contoso.com;<LOCAL>'), 'contoso.com;<local>');
    });
  });

  group('parseOwnEnginePids: только xray.exe нашей установки', () {
    const csv = '"ProcessId","ExecutablePath"\r\n'
        '"1234","C:\\Program Files\\bitaps VPN\\xray.exe"\r\n'
        '"5678","C:\\Users\\u\\AppData\\Local\\Happ\\xray.exe"\r\n'
        '"9012",\r\n';

    test('путь наш — берём; чужой и пустой — нет', () {
      expect(
        SystemProxy.parseOwnEnginePids(csv, r'C:\Program Files\bitaps VPN'),
        [1234],
        reason: 'xray Happ — чужой процесс, добивать его нельзя',
      );
    });

    test('регистр пути и слэши не важны', () {
      expect(
        SystemProxy.parseOwnEnginePids(csv, 'c:/program files/BITAPS vpn/'),
        [1234],
      );
    });

    test('битый ввод — пустой список, без исключений', () {
      expect(SystemProxy.parseOwnEnginePids('', r'C:\x'), isEmpty);
      expect(SystemProxy.parseOwnEnginePids('мусор\n"abc","C:\\x\\xray.exe"', r'C:\x'), isEmpty);
    });
  });
}
