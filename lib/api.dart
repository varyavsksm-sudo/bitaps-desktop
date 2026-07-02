part of 'main.dart';

// ============================ NETWORK / EDGE-FUNCTIONS ============================
// Все сетевые вызовы к Supabase edge-функциям (app-login / app-sub / app-pair / rotate-secret /
// notify) + сетевые инструменты (спид-тест, проверка утечек) + авто-проверка обновлений.
extension ShellApi on _ShellState {
  // Авто-проверка обновлений: сравниваем номер вшитой сборки с номером последнего релиза.
  // Тихо: любой сбой/таймаут/дев-сборка (kBuildNumber==0) — просто не показываем баннер.
  Future<void> _checkUpdate() async {
    if (kBuildNumber == 0) return;
    try {
      final r = await http.get(Uri.parse(kBuildNumberUrl)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final latest = int.tryParse(r.body.trim()) ?? 0;
      if (latest > kBuildNumber && mounted) setState(() => _updateAvail = true);
    } catch (_) {/* тихо */}
  }

  // Инструмент с сетью: окно с крутилкой → результат прямо в окне (видно всегда)
  Future<void> _runTool(String title, Future<String> Function() work) async {
    final fut = work();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<String>(
        future: fut,
        builder: (c, snap) {
          final done = snap.connectionState == ConnectionState.done;
          return AlertDialog(
            backgroundColor: C.bg2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
            title: Text(title, style: disp(18, w: FontWeight.w700)),
            content: !done
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
                    const SizedBox(width: 14),
                    Text('Минутку…', style: mono(13, c: C.muted)),
                  ])
                : Text(snap.hasError ? 'Не удалось выполнить.\n${snap.error}' : (snap.data ?? ''), style: mono(13, c: C.text)),
            actions: done
                ? [TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Ок', style: mono(13, c: C.accent)))]
                : null,
          );
        },
      ),
    );
  }

  // ----- вход по ключу / реальная подписка / устройства -----
  void _applySub(Map<String, dynamic> d) {
    subName = d['name']?.toString();
    subPlan = d['plan']?.toString();
    subExpires = d['expires_at']?.toString();
    subLimit = (d['device_limit'] is num) ? (d['device_limit'] as num).toInt() : null;
    subActive = d['active'] == true;
    // не перетираем вручную импортированный ключ (чужой хост) авто-рефрешем подписки
    if (d['vpn_key'] is String && importedHost == null) keyStr = d['vpn_key'] as String;
    if (d['login_secret'] is String) loginSecret = d['login_secret'] as String;
    final dl = d['devices'];
    devices = (dl is List) ? dl.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : [];
  }

  // Ротация кода входа: старый код перестаёт работать, показываем новый.
  Future<void> _rotateSecret() async {
    if (tgId == null || appToken == null) { _toast('Сначала войди'); return; }
    _toast('Меняю код…');
    try {
      final r = await http
          .post(Uri.parse(kRotateSecret),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'telegram_id': tgId, 'token': appToken}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode == 401 || r.statusCode == 403) { _doLogout(); _toast('Сессия истекла — войди снова'); return; }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['login_secret'] is String) {
        setState(() => loginSecret = d['login_secret'] as String);
        _save();
        _toast('Код входа обновлён ✓');
      } else {
        _toast('Не удалось сменить код');
      }
    } catch (e) {
      debugPrint('_rotateSecret error: $e');
      if (mounted) _toast(_netErr);
    }
  }

  Future<void> _login([String? presetKey]) async {
    if (!mounted) return; // _pairLogin может звать после закрытия экрана
    final key = (presetKey ?? _loginCtrl.text).trim();
    if (key.length < 12) {
      _toast('Вставь ключ из бота или Код входа');
      return;
    }
    // vless://… / https://… → VPN-ключ (шлём как key); иначе (UUID) — «Код входа»/login_secret (как secret).
    // Готовит вход по login_secret на будущее, когда вход по vpn_key отключат. keyStr берётся из ответа, не отсюда.
    final isKey = key.startsWith('vless://') || key.startsWith('http://') || key.startsWith('https://');
    if (!isKey && key.contains(RegExp(r'\s'))) {
      _toast('Вставь ключ (vless://…) или Код входа');
      return;
    }
    _toast('Вхожу…');
    try {
      final r = await http
          .post(Uri.parse(kAppLogin),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode(isKey ? {'key': key} : {'secret': key}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode >= 500) {
        _toast(_srvErr(r.statusCode));
        return;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        _loginError('Этот ключ не подошёл. Возьми актуальный ключ в боте.');
        return;
      }
      if (r.statusCode == 429) {
        _loginError('Слишком много попыток. Подожди минуту и попробуй снова.');
        return;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && d['telegram_id'] is num && d['app_token'] is String) {
        setState(() {
          tgId = (d['telegram_id'] as num).toInt();
          appToken = d['app_token'] as String;
          _applySub(d);
          _loginCtrl.clear();
        });
        _save();
        _toast('Вход выполнен ✓');
      } else {
        _loginError('Ключ не найден. Возьми актуальный ключ в боте.');
      }
    } on TimeoutException catch (e) {
      debugPrint('_login timeout: $e');
      _toast(_netErr);
    } catch (e) {
      debugPrint('_login error: $e');
      _toast(_netErr);
    }
  }

  // Авто-вход через бота: старт привязки → открыть бота → опрашивать, пока не подтвердит → войти.
  Future<void> _pairLogin() async {
    String token = '';
    try {
      final r = await http
          .post(Uri.parse(kAppPair),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'action': 'start'}))
          .timeout(const Duration(seconds: 15));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || d['url'] == null || d['token'] is! String) {
        _toast('Не удалось начать вход, попробуй ещё раз');
        return;
      }
      token = d['token'] as String;
      await _open(d['url'] as String);
    } on TimeoutException {
      _toast(_netErr);
      return;
    } catch (e) {
      debugPrint('_pairLogin start: $e');
      _toast(_netErr);
      return;
    }
    if (!mounted) return;
    bool cancelled = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 6),
          SizedBox(width: 34, height: 34, child: CircularProgressIndicator(color: C.accent, strokeWidth: 3)),
          const SizedBox(height: 16),
          Text('Подтверди вход в Telegram', style: disp(15, w: FontWeight.w700, c: C.text)),
          const SizedBox(height: 6),
          Text('Открылся бот — нажми «Запустить», затем «✅ Да, это я». Войду сам, как подтвердишь.',
              textAlign: TextAlign.center, style: mono(12, c: C.muted)),
        ]),
        actions: [
          TextButton(onPressed: () { cancelled = true; Navigator.pop(dctx); }, child: Text('Отмена', style: mono(13, c: C.muted))),
        ],
      ),
    );
    String? key;
    // опрашиваем до серверного TTL привязки (~15 мин), чтобы позднее подтверждение не терялось
    for (int i = 0; i < 180 && !cancelled; i++) {
      await Future.delayed(const Duration(seconds: 5));
      if (cancelled || !mounted) break;
      try {
        final cr = await http
            .post(Uri.parse(kAppPair),
                headers: {'content-type': 'application/json', 'apikey': kApiKey},
                body: jsonEncode({'action': 'check', 'token': token}))
            .timeout(const Duration(seconds: 10));
        final cd = jsonDecode(cr.body) as Map<String, dynamic>;
        if (cd['key'] != null) { key = cd['key'] as String; break; }
        if (cd['pending'] != true && cd['ok'] != true) break; // истёк/ошибка
      } catch (_) {/* сеть моргнула — продолжаем опрос */}
    }
    if (cancelled) return; // окно уже закрыто «Отменой»
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    if (key != null) {
      await _login(key);
    } else if (mounted) {
      _toast('Не дождался подтверждения. Открой бота и нажми «Запустить».');
    }
  }

  void _loginError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text('Не удалось войти', style: disp(18, w: FontWeight.w700)),
        content: Text(msg, style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Закрыть', style: mono(13, c: C.muted))),
          TextButton(onPressed: () { Navigator.pop(context); _open(kBot); }, child: Text('Открыть бота', style: mono(13, c: C.accent))),
        ],
      ),
    );
  }

  Future<void> _refreshSub({String? del, bool silent = false}) async {
    if (!loggedIn) {
      if (!silent) _toast('Сначала войди по ключу');
      return;
    }
    if (!silent) _toast(del != null ? 'Удаляю устройство…' : 'Обновляю…');
    if (mounted) setState(() => _subLoading = true);
    try {
      final r = await http
          .post(Uri.parse(kAppSub),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'telegram_id': tgId, 'token': appToken, if (del != null) 'del': del}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode == 401 || r.statusCode == 403) {
        if (!silent) _toast('Сессия истекла — войди заново');
        _doLogout(silent: true);
        return;
      }
      if (r.statusCode >= 500) {
        if (!silent) _toast(_srvErr(r.statusCode));
        return;
      }
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true) {
        setState(() => _applySub(d));
        _save();
        if (!silent) _toast(del != null ? 'Устройство удалено ✓' : 'Обновлено ✓');
      } else if (!silent) {
        _toast('Не удалось обновить');
      }
    } on TimeoutException catch (e) {
      debugPrint('_refreshSub timeout: $e');
      if (!silent) _toast(_netErr);
    } catch (e) {
      debugPrint('_refreshSub error: $e');
      if (!silent) _toast(_netErr);
    } finally {
      if (mounted) setState(() => _subLoading = false);
    }
  }

  Future<void> _sendSupport() async {
    final msg = _support.text.trim();
    if (msg.isEmpty) {
      _toast('Сначала напиши сообщение');
      return;
    }
    _toast('Отправляю…');
    try {
      final r = await http.post(Uri.parse(kNotify),
          headers: {'content-type': 'application/json', 'apikey': kApiKey},
          body: jsonEncode({
            'type': 'support',
            'name': loggedIn ? (subName != null && subName!.isNotEmpty ? subName! : 'Аккаунт #$tgId') : 'Пользователь приложения',
            'email': '',
            'message': msg,
            'source': 'десктоп-приложение'
          }))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _support.clear();
        setState(() {});
        _toast('Отправлено в поддержку ✓');
      } else {
        _toast(r.statusCode >= 500 ? _srvErr(r.statusCode) : 'Ошибка отправки (${r.statusCode})');
      }
    } catch (e) {
      debugPrint('_sendSupport error: $e');
      _toast(_netErr);
    }
  }

  Future<void> _leakCheck() => _runTool('Проверка утечек', () async {
        final r = await http.get(Uri.parse('https://api.ipify.org?format=json')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) throw Exception('сервер вернул ${r.statusCode}');
        final ip = (jsonDecode(r.body) as Map)['ip'];
        if (ip == null) throw Exception('IP не получен');
        return 'Твой текущий внешний IP:\n\n$ip\n\nС включённым VPN он сменится на адрес сервера — так видно, что трафик идёт через туннель.';
      });

  Future<void> _speedTest() => _runTool('Спид-тест', () async {
        final sw = Stopwatch()..start();
        final r = await http.get(Uri.parse('https://speed.cloudflare.com/__down?bytes=4000000')).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) throw Exception('сервер вернул ${r.statusCode}');
        sw.stop();
        final secs = (sw.elapsedMilliseconds / 1000.0).clamp(0.001, double.infinity);
        final mbps = r.bodyBytes.length * 8 / secs / 1e6;
        final mb = r.bodyBytes.length / 1048576;
        return 'Скорость загрузки: ${mbps.toStringAsFixed(1)} Mbps\n\nПолучено ${mb.toStringAsFixed(1)} MB за ${sw.elapsedMilliseconds} мс\n(реальный замер через Cloudflare)';
      });
}
