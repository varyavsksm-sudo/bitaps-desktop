// Движок туннеля для ДЕСКТОПА: запускаем рядом лежащий xray-core на конфиге подписки.
//
// Почему xray, а не sing-box: узлы «белого списка» ходят транспортом xhttp, которого в sing-box
// нет. xray понимает все наши узлы, а записи подписки сами по себе уже его конфиги.
//
// Что здесь есть и чего намеренно нет:
//   • запуск/остановка процесса движка, ожидание готовности локального socks-входа;
//   • системный прокси (Windows/macOS/Linux) — включаем на время сессии и ОБЯЗАТЕЛЬНО снимаем;
//   • честные ошибки: не нашли движок / не поднялся / не встал прокси — говорим прямо.
// TUN-режим (полный перехват трафика всей системы) требует прав администратора и драйвера —
// это отдельный шаг; здесь режим системного прокси, который работает без прав и покрывает
// браузеры и большинство приложений, уважающих системные настройки.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Не нашли или не смогли запустить движок — вызывающий показывает текст пользователю.
class EngineUnavailable implements Exception {
  final String message;
  EngineUnavailable(this.message);
  @override
  String toString() => message;
}

/// Поиск бинаря движка. Порядок: рядом с исполняемым файлом (так его кладёт сборка),
/// затем каталог данных приложения (куда его можно доложить), затем PATH — для разработки.
class XrayBinary {
  static const String _name = 'xray';

  static String? locate({String? extraDir}) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final suffix = Platform.isWindows ? '.exe' : '';
    final candidates = <String>[
      if (extraDir != null) '$extraDir${Platform.pathSeparator}$_name$suffix',
      '$exeDir${Platform.pathSeparator}$_name$suffix',
      '$exeDir${Platform.pathSeparator}bin${Platform.pathSeparator}$_name$suffix',
      // Linux AppImage/tar.gz кладут бинарь рядом с data/
      '$exeDir${Platform.pathSeparator}data${Platform.pathSeparator}$_name$suffix',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    // PATH — только запасной путь (dev-машина, установленный вручную xray)
    final path = Platform.environment['PATH'] ?? '';
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final c = '$dir${Platform.pathSeparator}$_name$suffix';
      if (File(c).existsSync()) return c;
    }
    return null;
  }
}

/// Процесс движка с конфигом подписки.
class XrayProcess {
  XrayProcess._(this._proc, this.socksPort);

  final Process _proc;
  final int socksPort;
  final List<String> _errLines = [];
  bool _stopped = false;

  /// Последние строки лога движка — идут в текст ошибки, чтобы сбой был диагностируемым.
  String get lastError => _errLines.isEmpty ? '' : _errLines.take(4).join('\n');

  /// Запустить движок на готовом конфиге. Бросает [EngineUnavailable] с внятной причиной.
  static Future<XrayProcess> start(
    String configJson, {
    required int socksPort,
    String? binaryPath,
    Duration readyTimeout = const Duration(seconds: 12),
  }) async {
    final bin = binaryPath ?? XrayBinary.locate();
    if (bin == null) {
      throw EngineUnavailable('VPN-движок не найден в сборке');
    }
    // Конфиг отдаём движку через stdin (`-c stdin:`), а не файлом: в нём личный UUID подписки,
    // и на диске он не должен оказываться даже во временном каталоге.
    // XRAY_LOCATION_ASSET — каталог с geoip.dat/geosite.dat, они лежат рядом с бинарём;
    // без них правила «российские сайты мимо туннеля» не сработают.
    final engineDir = File(bin).parent.path;
    Process proc;
    try {
      proc = await Process.start(
        bin,
        ['run', '-c', 'stdin:'],
        runInShell: false,
        workingDirectory: engineDir,
        environment: {'XRAY_LOCATION_ASSET': engineDir},
      );
      proc.stdin.write(configJson);
      await proc.stdin.flush();
      await proc.stdin.close();
    } catch (e) {
      throw EngineUnavailable('не удалось запустить движок: $e');
    }
    final p = XrayProcess._(proc, socksPort);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(p._onLog);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(p._onLog);
    // Смерть процесса вне stop(): помечаем и пишем в лог. Без этого цикл готовности ниже
    // ждал бы весь таймаут уже умерший движок, а обрыв посреди сессии нигде не отражался.
    proc.exitCode.then((code) {
      if (p._stopped) return; // своя остановка — не событие
      p._exited = true;
      p._onLog('xray exited: $code');
    });
    // Готовность = локальный socks реально принимает соединения. Пока порт не слушает,
    // включать системный прокси нельзя — иначе весь трафик уедет в закрытый порт.
    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await p._socksReady()) return p;
      if (p._exited) {
        throw EngineUnavailable('движок завершился на старте:\n${p.lastError}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await p.stop();
    throw EngineUnavailable('движок не поднял локальный порт за ${readyTimeout.inSeconds} с');
  }

  bool _exited = false;

  void _onLog(String line) {
    if (line.trim().isEmpty) return;
    _errLines.insert(0, line.trim());
    if (_errLines.length > 20) _errLines.removeLast();
  }

  Future<bool> _socksReady() async {
    try {
      final s = await Socket.connect('127.0.0.1', socksPort,
          timeout: const Duration(milliseconds: 400));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Остановить движок и убрать временный конфиг. Идемпотентно.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _proc.kill(ProcessSignal.sigterm);
    // не ждём вечно: если движок завис, добиваем
    await _proc.exitCode.timeout(const Duration(seconds: 4), onTimeout: () {
      _proc.kill(ProcessSignal.sigkill);
      return -1;
    });
    _cleanup();
  }

  void _cleanup() {
    _exited = true; // конфиг жил только в stdin — удалять нечего
  }
}

/// Показания движка: счётчики трафика и задержки узлов. Движок отдаёт их сам по HTTP на
/// localhost (metrics.listen → /debug/vars), поэтому опрос дешёвый — без запуска процессов.
/// Считаем только узлы туннеля (node-*): прямой трафик мимо туннеля к «скорости VPN»
/// отношения не имеет.
class XrayStats {
  static Future<({int up, int down, Map<String, int?> pings})?> read(int metricsPort) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse('http://127.0.0.1:$metricsPort/debug/vars'));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      final body = await resp.transform(utf8.decoder).join();
      final decoded = json.decode(body);
      if (decoded is! Map) return null;
      var up = 0, down = 0;
      final outbound = (decoded['stats'] as Map?)?['outbound'];
      if (outbound is Map) {
        outbound.forEach((tag, v) {
          if (tag is! String || !tag.startsWith('node-') || v is! Map) return;
          up += (v['uplink'] as num?)?.toInt() ?? 0;
          down += (v['downlink'] as num?)?.toInt() ?? 0;
        });
      }
      final pings = <String, int?>{};
      final obs = decoded['observatory'];
      if (obs is Map) {
        obs.forEach((tag, v) {
          if (tag is! String || v is! Map) return;
          // У мёртвого узла поле alive отсутствует (proto3 опускает значение по умолчанию),
          // а задержка приходит заглушкой 99999999 — показывать её как пинг нельзя.
          final delay = (v['delay'] as num?)?.toInt();
          pings[tag] = (v['alive'] == true && delay != null && delay < 99999999) ? delay : null;
        });
      }
      return (up: up, down: down, pings: pings);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

/// Системный прокси на время сессии. Включаем ТОЛЬКО после готовности движка и снимаем всегда,
/// в том числе при падении: иначе пользователь останется без интернета с указателем в мёртвый порт.
class SystemProxy {
  static bool _enabled = false;
  static List<String> _macServices = [];

  // Снимок настроек прокси ДО нашего включения (у части пользователей свой прокси уже стоял):
  // disable() вернёт его, а не безусловное «выкл». null/пусто — снимка нет (свежий процесс,
  // напр. уборка за упавшей сессией) → прежнее поведение: просто снять.
  static Map<String, String>? _winSaved; // ProxyEnable (0/1) + ProxyServer
  static Map<String, String>? _linuxSaved; // mode + http host/port
  static final Map<String, Map<String, List<String>>> _macSaved = {}; // сервис → тип → строки вывода -get*proxy

  static bool get enabled => _enabled;

  static Future<bool> enable({required int socksPort, required int httpPort}) async {
    try {
      await _snapshot(); // до любой записи: потом вернуть систему как было
      if (Platform.isMacOS) {
        _macServices = await _macNetworkServices();
        if (_macServices.isEmpty) return false;
        final cmds = <List<String>>[
          for (final s in _macServices) ...[
            ['-setsocksfirewallproxy', s, '127.0.0.1', '$socksPort'],
            ['-setsocksfirewallproxystate', s, 'on'],
            ['-setwebproxy', s, '127.0.0.1', '$httpPort'],
            ['-setwebproxystate', s, 'on'],
            ['-setsecurewebproxy', s, '127.0.0.1', '$httpPort'],
            ['-setsecurewebproxystate', s, 'on'],
          ],
        ];
        await _macRun(cmds);
        _enabled = await _macApplied(socksPort);
        return _enabled;
      }
      if (Platform.isWindows) {
        // WinINet: прокси пользователя (без прав администратора). http/https обязательны —
        // многие приложения socks-строку игнорируют.
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        final value = 'http=127.0.0.1:$httpPort;https=127.0.0.1:$httpPort;socks=127.0.0.1:$socksPort';
        await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', value, '/f']);
        await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
        _enabled = await _winApplied(httpPort);
        return _enabled;
      }
      if (Platform.isLinux) {
        // gsettings читают только GTK-окружения. На KDE/LXQt и прочих запись «проходит», но
        // настройку никто не применяет (см. _linuxApplied — она читает те же ключи, что пишет,
        // и потому там врёт). Честно говорим «не поддержано» вместо ложного «защищено».
        final de = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase();
        const gtk = ['GNOME', 'UNITY', 'PANTHEON', 'CINNAMON', 'BUDGIE', 'MATE', 'XFCE'];
        // Пустое/незнакомое DE — тоже «не поддержано»: readback своих же ключей gsettings
        // ничего не доказывает о реальном применении, а fail-open с зелёным статусом хуже
        // честной ошибки (TunnelUnavailable покажет текст пользователю).
        if (de.isEmpty || !gtk.any(de.contains)) {
          stderr.writeln('system proxy: окружение «${de.isEmpty ? 'неизвестно' : de}» не читает gsettings — режим прокси не поддержан');
          return false;
        }
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
        for (final e in {'http': httpPort, 'https': httpPort, 'socks': socksPort}.entries) {
          await Process.run('gsettings', ['set', 'org.gnome.system.proxy.${e.key}', 'host', '127.0.0.1']);
          await Process.run('gsettings', ['set', 'org.gnome.system.proxy.${e.key}', 'port', '${e.value}']);
        }
        // На KDE и прочих не-GNOME средах команды проходят, но настройку никто не читает —
        // объявлять «защищено» в этом случае нельзя, поэтому проверяем чтением.
        _enabled = await _linuxApplied(socksPort);
        return _enabled;
      }
    } catch (_) {/* ниже вернём false — вызывающий честно скажет, что прокси не встал */}
    return false;
  }

  /// Снять системный прокси. Намеренно НЕ смотрим на флаг в памяти: после падения приложения
  /// (или его убийства) флаг сброшен, а прокси в системе остался — это ровно тот случай, когда
  /// уборка нужнее всего. Чужие настройки не трогаем: снимаем, только если прокси указывает на
  /// локальный адрес, то есть это наш.
  static Future<void> disable() async {
    _enabled = false;
    try {
      // Есть снимок: возвращаем чужие настройки ТОЛЬКО если текущие всё ещё наши (localhost).
      // Прокси сменился под нами — человек настроил свой сам: его выбор не трогаем вовсе.
      if (_winSaved != null || _linuxSaved != null || _macSaved.isNotEmpty) {
        if (await looksOurs()) await _restore();
        _winSaved = null;
        _linuxSaved = null;
        _macSaved.clear();
        _macServices = [];
        return;
      }
      if (Platform.isMacOS) {
        final services = _macServices.isNotEmpty ? _macServices : await _macNetworkServices();
        await _macRun([
          for (final s in services) ...[
            ['-setsocksfirewallproxystate', s, 'off'],
            ['-setwebproxystate', s, 'off'],
            ['-setsecurewebproxystate', s, 'off'],
          ],
        ]);
        _macServices = [];
        return;
      }
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
        return;
      }
      if (Platform.isLinux) {
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'none']);
        return;
      }
    } catch (_) {/* при выключении ошибки глотаем: главное — не мешать выходу */}
  }

  // ── снимок/восстановление чужих настроек (до нашего включения и после) ──
  static Future<void> _snapshot() async {
    try {
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        final en = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
        final srv = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
        _winSaved = {
          'enable': (en.stdout ?? '').toString().contains('0x1') ? '1' : '0',
          'server': RegExp(r'ProxyServer\s+REG_SZ\s+(\S.*)')
                  .firstMatch((srv.stdout ?? '').toString())?.group(1)?.trim() ?? '',
        };
        return;
      }
      if (Platform.isMacOS) {
        final services = _macServices.isNotEmpty ? _macServices : await _macNetworkServices();
        _macSaved.clear();
        for (final svc in services) {
          final m = <String, List<String>>{};
          for (final t in ['-getwebproxy', '-getsecurewebproxy', '-getsocksfirewallproxy']) {
            final r = await Process.run('/usr/sbin/networksetup', [t, svc]);
            m[t] = (r.stdout ?? '').toString().split('\n');
          }
          _macSaved[svc] = m;
        }
        return;
      }
      if (Platform.isLinux) {
        Future<String> get(String key, String field) async =>
            (await Process.run('gsettings', ['get', key, field]))
                .stdout?.toString().trim().replaceAll("'", '') ?? '';
        final mode = await get('org.gnome.system.proxy', 'mode');
        _linuxSaved = {
          'mode': mode.isEmpty ? 'none' : mode,
          'httpHost': await get('org.gnome.system.proxy.http', 'host'),
          'httpPort': await get('org.gnome.system.proxy.http', 'port'),
        };
        return;
      }
    } catch (_) {/* снимок не снялся — disable() отработает по-старому (просто снять) */}
  }

  static Future<void> _restore() async {
    try {
      if (Platform.isWindows && _winSaved != null) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        final srv = _winSaved!['server'] ?? '';
        if (srv.isNotEmpty) {
          await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', srv, '/f']);
        }
        await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', _winSaved!['enable'] ?? '0', '/f']);
        return;
      }
      if (Platform.isMacOS) {
        final cmds = <List<String>>[];
        for (final e in _macSaved.entries) {
          for (final t in ['-getwebproxy', '-getsecurewebproxy', '-getsocksfirewallproxy']) {
            final lines = e.value[t] ?? const <String>[];
            String f(String k) => lines
                .firstWhere((l) => l.startsWith('$k:'), orElse: () => '')
                .split(':').last.trim();
            final host = f('Server'), port = f('Port'), on = f('Enabled') == 'Yes';
            final set = t.replaceFirst('-get', '-set'); // -getwebproxy → -setwebproxy
            if (host.isNotEmpty) cmds.add([set, e.key, host, port]);
            cmds.add(['${set}state', e.key, on ? 'on' : 'off']);
          }
        }
        if (cmds.isNotEmpty) await _macRun(cmds);
        _macServices = [];
        return;
      }
      if (Platform.isLinux && _linuxSaved != null) {
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.http', 'host', _linuxSaved!['httpHost'] ?? '']);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.http', 'port', _linuxSaved!['httpPort'] ?? '0']);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', _linuxSaved!['mode'] ?? 'none']);
        return;
      }
    } catch (_) {/* восстановление best-effort: хуже, чем надо, не сделаем */}
  }

  /// Выполнить пачку команд networksetup. Сначала пробуем как есть: если приложение уже
  /// запущено с нужными правами, лишний запрос пароля не нужен. Не получилось — повторяем
  /// ОДНИМ вызовом с правами администратора, чтобы система спросила пароль один раз на всю
  /// операцию, а не на каждую команду. (Смена сетевых настроек в macOS требует root.)
  /// Бросает [EngineUnavailable] при ненулевом exitCode osascript: отмена пароля («User
  /// canceled», -128) раньше проглатывалась — команды не выполнялись, а вызывающий считал
  /// прокси применённым/снятым. Вызывающие сами решают по факту: enable() вернёт false,
  /// disable()/_restore() проглотят, но unblock() перепроверит looksOurs().
  static Future<void> _macRun(List<List<String>> cmds) async {
    var allOk = true;
    for (final args in cmds) {
      final r = await Process.run('/usr/sbin/networksetup', args);
      if (r.exitCode != 0) { allOk = false; break; }
    }
    if (allOk) return;
    final script = cmds.map((a) => '/usr/sbin/networksetup ${a.map(_shellQuote).join(' ')}').join(' ; ');
    // экранирование для строки AppleScript: обратный слэш и кавычки
    final applescript = script.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    final r = await Process.run('osascript', [
      '-e',
      'do shell script "$applescript" with administrator privileges',
    ]);
    if (r.exitCode != 0) {
      final err = (r.stderr ?? '').toString().trim();
      throw EngineUnavailable(
          'macOS не дала сменить системный прокси (код ${r.exitCode})${err.isEmpty ? '' : ': $err'}');
    }
  }

  static String _shellQuote(String a) => "'${a.replaceAll("'", r"'\''")}'";

  // ── подтверждение по факту ──
  // Команды настройки прокси возвращают успех и там, где их результат никто не читает
  // (KDE вместо GNOME, macOS без прав администратора). Поэтому после записи перечитываем.
  static Future<bool> _macApplied(int socksPort) async {
    if (_macServices.isEmpty) return false;
    // Частичное применение — НЕ успех: сервис без нашего прокси ходит напрямую, а «нашлось на
    // одном сервисе» раньше читалось зелёным. Зелёный — только «наш порт на ВСЕХ активных
    // сервисах» (primary из -listnetworkserviceorder входит в этот список по построению).
    for (final svc in _macServices) {
      final r = await Process.run('/usr/sbin/networksetup', ['-getsocksfirewallproxy', svc]);
      final out = (r.stdout ?? '').toString();
      if (!(out.contains('Enabled: Yes') && out.contains('$socksPort'))) return false;
    }
    return true;
  }

  static Future<bool> _winApplied(int httpPort) async {
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    final r = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
    return (r.stdout ?? '').toString().contains('127.0.0.1:$httpPort');
  }

  static Future<bool> _linuxApplied(int socksPort) async {
    final mode = await Process.run('gsettings', ['get', 'org.gnome.system.proxy', 'mode']);
    if (!(mode.stdout ?? '').toString().contains('manual')) return false;
    final port = await Process.run('gsettings', ['get', 'org.gnome.system.proxy.socks', 'port']);
    return (port.stdout ?? '').toString().trim() == '$socksPort';
  }

  /// Остался ли в системе НАШ прокси (указывает на localhost) — вызывается на старте
  /// приложения, чтобы прибрать за прошлым упавшим запуском.
  static Future<bool> looksOurs() async {
    try {
      if (Platform.isWindows) {
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        final en = await Process.run('reg', ['query', key, '/v', 'ProxyEnable']);
        if (!(en.stdout ?? '').toString().contains('0x1')) return false;
        final srv = await Process.run('reg', ['query', key, '/v', 'ProxyServer']);
        return (srv.stdout ?? '').toString().contains('127.0.0.1');
      }
      if (Platform.isMacOS) {
        for (final svc in await _macNetworkServices()) {
          final r = await Process.run('/usr/sbin/networksetup', ['-getsocksfirewallproxy', svc]);
          final out = (r.stdout ?? '').toString();
          if (out.contains('Enabled: Yes') && out.contains('127.0.0.1')) {
            _macServices = [svc];
            return true;
          }
        }
        return false;
      }
      if (Platform.isLinux) {
        final mode = await Process.run('gsettings', ['get', 'org.gnome.system.proxy', 'mode']);
        if (!(mode.stdout ?? '').toString().contains('manual')) return false;
        final host = await Process.run('gsettings', ['get', 'org.gnome.system.proxy.socks', 'host']);
        return (host.stdout ?? '').toString().contains('127.0.0.1');
      }
    } catch (_) {/* не смогли прочитать — считаем, что чужого не трогаем */}
    return false;
  }

  /// Прибраться на старте приложения: если в системе висит наш прокси от прошлой сессии
  /// (падение/убийство процесса), снимаем его — иначе у пользователя «нет интернета».
  static Future<void> cleanupStale() async {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    if (await looksOurs()) await disable();
  }

  /// Сетевые сервисы macOS (Wi-Fi, Ethernet…), кроме отключённых (строки со «*»).
  static Future<List<String>> _macNetworkServices() async {
    final r = await Process.run('/usr/sbin/networksetup', ['-listallnetworkservices']);
    final out = (r.stdout ?? '').toString().split('\n');
    return [
      for (var line in out.skip(1))
        if (line.trim().isNotEmpty && !line.startsWith('*')) line.trim(),
    ];
  }
}
