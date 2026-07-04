part of 'main.dart';

// ============================ NETWORK / EDGE-FUNCTIONS ============================
// Все сетевые вызовы к Supabase edge-функциям (app-login / app-sub / app-pair / rotate-secret /
// notify) + сетевые инструменты (спид-тест, проверка утечек) + авто-проверка обновлений.
extension ShellApi on ShellState {
  // Авто-проверка обновлений: сравниваем номер вшитой сборки с номером последнего релиза.
  // Тихо: любой сбой/таймаут/дев-сборка (kBuildNumber==0) — просто не показываем баннер.
  Future<void> _checkUpdate() async {
    if (kBuildNumber == 0) return;
    try {
      final r = await http.get(Uri.parse(kBuildNumberUrl)).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final latest = int.tryParse(r.body.trim()) ?? 0;
      if (latest > kBuildNumber && mounted) rebuild(() => _updateAvail = true);
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
                    Text(tr('Минутку…'), style: mono(13, c: C.muted)),
                  ])
                : Text(
                    snap.hasError
                        ? (appLang == 'en' ? "Couldn't run this.\n${snap.error}" : 'Не удалось выполнить.\n${snap.error}')
                        : (snap.data ?? ''),
                    style: mono(13, c: C.text)),
            actions: done
                ? [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Ок'), style: mono(13, c: C.accent)))]
                : null,
          );
        },
      ),
    );
  }

  // 2xx, но тело — не JSON-объект (пустое/HTML/массив). Это НЕ обрыв сети: возвращаем null, чтобы
  // вызывающий показал «непонятный ответ сервера», а не вводящее в заблуждение «нет интернета».
  Map<String, dynamic>? _asObj(String body) {
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) return d;
      if (d is Map) return d.cast<String, dynamic>();
    } catch (_) {/* не JSON */}
    return null;
  }

  String get _badRespErr => appLang == 'en'
      ? 'Unexpected server response. Try again later.'
      : 'Непонятный ответ сервера. Попробуй позже.';

  // ----- вход по ключу / реальная подписка / устройства -----
  void _applySub(Map<String, dynamic> d, {bool fresh = false}) {
    // явный вход в аккаунт (fresh) сбрасывает ранее импортированный чужой ключ — ключ аккаунта
    // должен применяться; авто-рефреш (fresh=false) НЕ перетирает вручную импортированный ключ
    if (fresh) { importedHost = null; customCfg = null; }
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
    if (tgId == null || appToken == null) { _toast(tr('Сначала войди')); return; }
    _toast(tr('Меняю код…'));
    try {
      final r = await http
          .post(Uri.parse(kRotateSecret),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'telegram_id': tgId, 'token': appToken}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode == 401 || r.statusCode == 403) { _doLogout(); _toast(tr('Сессия истекла — войди снова')); return; }
      if (r.statusCode >= 500) { _toast(_srvErr(r.statusCode)); return; } // 5xx → «сервер недоступен», а не «нет интернета»
      final d = _asObj(r.body);
      if (d == null) { _toast(_badRespErr); return; }
      if (d['ok'] == true && d['login_secret'] is String) {
        rebuild(() => loginSecret = d['login_secret'] as String);
        _save();
        _toast(tr('Код входа обновлён ✓'));
      } else {
        _toast(tr('Не удалось сменить код'));
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
      _toast(tr('Вставь Код входа из бота или письма'));
      return;
    }
    // Вход по vpn_key (vless://… / https://…) отключён на сервере (app-login → 403): принимаем
    // ТОЛЬКО «Код входа» (UUID login_secret, уходит как {secret}). Так вызов согласован с бэкендом,
    // а юзер не бьётся о вечный 403, вставляя VPN-ключ. _pairLogin тоже передаёт сюда UUID.
    if (key.startsWith('vless://') || key.startsWith('http://') || key.startsWith('https://')) {
      _loginError(tr('Вход по VPN-ключу отключён. Вставь «Код входа» (UUID) из бота или письма.'));
      return;
    }
    if (key.contains(RegExp(r'\s'))) {
      _toast(tr('Вставь «Код входа» (UUID) — без пробелов'));
      return;
    }
    _toast(tr('Вхожу…'));
    try {
      final r = await http
          .post(Uri.parse(kAppLogin),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({'secret': key}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode >= 500) {
        _toast(_srvErr(r.statusCode));
        return;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        _loginError(tr('Этот ключ не подошёл. Возьми актуальный ключ в боте.'));
        return;
      }
      if (r.statusCode == 429) {
        _loginError(tr('Слишком много попыток. Подожди минуту и попробуй снова.'));
        return;
      }
      final d = _asObj(r.body);
      if (d == null) { _toast(_badRespErr); return; }
      if (d['ok'] == true && d['telegram_id'] is num && d['app_token'] is String) {
        rebuild(() {
          tgId = (d['telegram_id'] as num).toInt();
          appToken = d['app_token'] as String;
          _applySub(d, fresh: true);
          _loginCtrl.clear();
        });
        _save();
        _toast(tr('Вход выполнен ✓'));
      } else {
        _loginError(tr('Ключ не найден. Возьми актуальный ключ в боте.'));
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
      if (r.statusCode >= 500) { _toast(_srvErr(r.statusCode)); return; } // 5xx → «сервер недоступен», а не «нет интернета»
      final d = _asObj(r.body);
      if (d == null) { _toast(_badRespErr); return; }
      if (d['ok'] != true || d['url'] == null || d['token'] is! String) {
        _toast(tr('Не удалось начать вход, попробуй ещё раз'));
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
          Text(tr('Подтверди вход в Telegram'), style: disp(15, w: FontWeight.w700, c: C.text)),
          const SizedBox(height: 6),
          Text(tr('Открылся бот — нажми «Запустить», затем «✅ Да, это я». Войду сам, как подтвердишь.'),
              textAlign: TextAlign.center, style: mono(12, c: C.muted)),
        ]),
        actions: [
          TextButton(onPressed: () { cancelled = true; Navigator.pop(dctx); }, child: Text(tr('Отмена'), style: mono(13, c: C.muted))),
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
        final cd = _asObj(cr.body);
        if (cd == null) continue; // непонятный ответ — не рушим опрос, ждём следующей итерации
        // cd['key'] несёт login_secret (UUID) — вход по vpn_key закрыт на сервере (app-login → 403).
        // _login сам определит UUID как «Код входа» и залогинится по secret, а не по key.
        if (cd['key'] != null) { key = cd['key'] as String; break; }
        if (cd['pending'] != true && cd['ok'] != true) break; // истёк/ошибка
      } catch (_) {/* сеть моргнула — продолжаем опрос */}
    }
    if (cancelled) return; // окно уже закрыто «Отменой»
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    if (key != null) {
      await _login(key);
    } else if (mounted) {
      _toast(tr('Не дождался подтверждения. Открой бота и нажми «Запустить».'));
    }
  }

  void _loginError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: C.bg2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: C.line)),
        title: Text(tr('Не удалось войти'), style: disp(18, w: FontWeight.w700)),
        content: Text(msg, style: mono(13, c: C.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Закрыть'), style: mono(13, c: C.muted))),
          TextButton(onPressed: () { Navigator.pop(context); _open(kBot); }, child: Text(tr('Открыть бота'), style: mono(13, c: C.accent))),
        ],
      ),
    );
  }

  Future<void> _refreshSub({String? del, bool silent = false}) async {
    if (!loggedIn) {
      if (!silent) _toast(tr('Сначала войди по ключу'));
      return;
    }
    if (!silent) _toast(del != null ? tr('Удаляю устройство…') : tr('Обновляю…'));
    if (mounted) rebuild(() => _subLoading = true);
    try {
      final r = await http
          .post(Uri.parse(kAppSub),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              // удаление устройства подтверждаем «Кодом входа» (login_secret) — сервер требует
              // сильный credential, а не только сессионный token (см. app-sub).
              body: jsonEncode({'telegram_id': tgId, 'token': appToken,
                if (del != null) 'del': del,
                if (del != null && loginSecret != null) 'secret': loginSecret}))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      // 403 при удалении — не протухшая сессия, а требование «Кода входа»: не разлогиниваем.
      if (r.statusCode == 403 && del != null) {
        if (!silent) {
          _toast(loginSecret == null
              ? tr('Удаление требует «Код входа». Открой его в боте (/start → Код входа) и войди по нему.')
              : tr('Не удалось подтвердить «Код входа» для удаления.'));
        }
        return;
      }
      if (r.statusCode == 401 || r.statusCode == 403) {
        if (!silent) _toast(tr('Сессия истекла — войди заново'));
        _doLogout(silent: true);
        return;
      }
      if (r.statusCode >= 500) {
        if (!silent) _toast(_srvErr(r.statusCode));
        return;
      }
      final d = _asObj(r.body);
      if (d == null) { if (!silent) _toast(_badRespErr); return; }
      if (d['ok'] == true) {
        rebuild(() => _applySub(d));
        _save();
        if (!silent) _toast(del != null ? tr('Устройство удалено ✓') : tr('Обновлено ✓'));
      } else if (!silent) {
        _toast(tr('Не удалось обновить'));
      }
    } on TimeoutException catch (e) {
      debugPrint('_refreshSub timeout: $e');
      if (!silent) _toast(_netErr);
    } catch (e) {
      debugPrint('_refreshSub error: $e');
      if (!silent) _toast(_netErr);
    } finally {
      if (mounted) rebuild(() => _subLoading = false);
    }
  }

  Future<void> _sendSupport() async {
    final msg = _support.text.trim();
    if (msg.isEmpty) {
      _toast(tr('Сначала напиши сообщение'));
      return;
    }
    _toast(tr('Отправляю…'));
    try {
      final r = await http.post(Uri.parse(kNotify),
          headers: {'content-type': 'application/json', 'apikey': kApiKey},
          body: jsonEncode({
            'type': 'support',
            'name': loggedIn
                ? (subName != null && subName!.isNotEmpty
                    ? subName!
                    : (appLang == 'en' ? 'Account #$tgId' : 'Аккаунт #$tgId'))
                : tr('Пользователь приложения'),
            'email': '',
            'message': msg,
            'source': 'десктоп-приложение'
          }))
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (r.statusCode >= 200 && r.statusCode < 300) {
        _support.clear();
        rebuild(() {});
        _toast(tr('Отправлено в поддержку ✓'));
      } else {
        _toast(r.statusCode >= 500
            ? _srvErr(r.statusCode)
            : (appLang == 'en' ? 'Send error (${r.statusCode})' : 'Ошибка отправки (${r.statusCode})'));
      }
    } catch (e) {
      debugPrint('_sendSupport error: $e');
      _toast(_netErr);
    }
  }

  Future<void> _leakCheck() => _runTool(tr('Проверка утечек'), () async {
        final r = await http.get(Uri.parse('https://api.ipify.org?format=json')).timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) {
          throw Exception(appLang == 'en' ? 'server returned ${r.statusCode}' : 'сервер вернул ${r.statusCode}');
        }
        final ip = (jsonDecode(r.body) as Map)['ip'];
        if (ip == null) throw Exception(tr('IP не получен'));
        return appLang == 'en'
            ? 'Your current external IP:\n\n$ip\n\nWith the VPN on it changes to the server address — that shows traffic goes through the tunnel.'
            : 'Твой текущий внешний IP:\n\n$ip\n\nС включённым VPN он сменится на адрес сервера — так видно, что трафик идёт через туннель.';
      });

  Future<void> _speedTest() => _runTool(tr('Спид-тест'), () async {
        final sw = Stopwatch()..start();
        final r = await http.get(Uri.parse('https://speed.cloudflare.com/__down?bytes=4000000')).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) {
          throw Exception(appLang == 'en' ? 'server returned ${r.statusCode}' : 'сервер вернул ${r.statusCode}');
        }
        sw.stop();
        final secs = (sw.elapsedMilliseconds / 1000.0).clamp(0.001, double.infinity);
        final mbps = r.bodyBytes.length * 8 / secs / 1e6;
        final mb = r.bodyBytes.length / 1048576;
        return appLang == 'en'
            ? 'Download speed: ${mbps.toStringAsFixed(1)} Mbps\n\nGot ${mb.toStringAsFixed(1)} MB in ${sw.elapsedMilliseconds} ms\n(real measurement via Cloudflare)'
            : 'Скорость загрузки: ${mbps.toStringAsFixed(1)} Mbps\n\nПолучено ${mb.toStringAsFixed(1)} MB за ${sw.elapsedMilliseconds} мс\n(реальный замер через Cloudflare)';
      });
}
