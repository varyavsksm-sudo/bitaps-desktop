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
  XrayProcess._(this._proc, this._configFile, this.socksPort);

  final Process _proc;
  final File _configFile;
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
    final dir = await Directory.systemTemp.createTemp('bitaps_engine_');
    final cfg = File('${dir.path}${Platform.pathSeparator}config.json');
    await cfg.writeAsString(configJson);
    Process proc;
    try {
      proc = await Process.start(bin, ['run', '-c', cfg.path], runInShell: false);
    } catch (e) {
      await dir.delete(recursive: true).catchError((_) => dir);
      throw EngineUnavailable('не удалось запустить движок: $e');
    }
    final p = XrayProcess._(proc, cfg, socksPort);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(p._onLog);
    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(p._onLog);
    // Готовность = локальный socks реально принимает соединения. Пока порт не слушает,
    // включать системный прокси нельзя — иначе весь трафик уедет в закрытый порт.
    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await p._socksReady()) return p;
      if (p._exited) {
        await p._cleanup();
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
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _exited = true;
    try {
      final dir = _configFile.parent;
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {/* временный каталог — не критично */}
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

  static bool get enabled => _enabled;

  static Future<bool> enable(int port) async {
    try {
      if (Platform.isMacOS) {
        _macServices = await _macNetworkServices();
        for (final s in _macServices) {
          await Process.run('/usr/sbin/networksetup', ['-setsocksfirewallproxy', s, '127.0.0.1', '$port']);
          await Process.run('/usr/sbin/networksetup', ['-setsocksfirewallproxystate', s, 'on']);
        }
        _enabled = _macServices.isNotEmpty;
        return _enabled;
      }
      if (Platform.isWindows) {
        // WinINet: включаем socks-прокси в реестре пользователя (прав администратора не нужно)
        const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
        await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', 'socks=127.0.0.1:$port', '/f']);
        await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
        _enabled = true;
        return true;
      }
      if (Platform.isLinux) {
        // GNOME/GTK-окружения читают gsettings; на прочих DE пользователь настраивает сам.
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy', 'mode', 'manual']);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'host', '127.0.0.1']);
        await Process.run('gsettings', ['set', 'org.gnome.system.proxy.socks', 'port', '$port']);
        _enabled = true;
        return true;
      }
    } catch (_) {/* ниже вернём false — вызывающий честно скажет, что прокси не встал */}
    return false;
  }

  static Future<void> disable() async {
    if (!_enabled) return;
    _enabled = false;
    try {
      if (Platform.isMacOS) {
        for (final s in _macServices) {
          await Process.run('/usr/sbin/networksetup', ['-setsocksfirewallproxystate', s, 'off']);
        }
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
