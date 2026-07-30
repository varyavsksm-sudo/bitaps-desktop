part of '../main.dart';

// ============================ GOOGLE PLAY BILLING ============================
// Покупка подписки ИЗ ПРИЛОЖЕНИЯ (Play-политика: цифровые подписки только через Play Billing).
// Модель — РАЗОВЫЕ managed-продукты, как наши предоплаченные тарифы (без авто-продления).
// Цепочка доверия: покупка в Google → purchaseToken → серверная верификация (edge
// `google-play-verify` ходит в Google Play Developer API, сверяет, выдаёт доступ и гасит
// продукт consume'ом). Локальному «окно оплаты» не доверяем — грант только по вердикту сервера.
// Состояние биллинга живёт в top-level синглтоне: extension не может держать
// instance-поля (ограничение Dart), а сессия приложения у нас одна.
class _BillingStore {
  final InAppPurchase iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? sub;
  final Set<String> pendingTokens = {};
  bool ready = false;
  final Map<String, String> playPrices = {}; // productId → локализованная цена
}

final _billing = _BillingStore();

extension ShellBilling on ShellState {
  static const Map<String, String> _planToProduct = {
    'mo': 'sub_mo',
    'q': 'sub_q',
    'h': 'sub_h',
    'yr': 'sub_yr',
  };

  bool get billingAvailable => _billing.ready && Platform.isAndroid;

  Future<void> _initBilling() async {
    if (!Platform.isAndroid) return;
    try {
      final ok = await _billing.iap.isAvailable();
      if (!ok) return;
      _billing.sub ??= _billing.iap.purchaseStream.listen(_onPurchases,
          onError: (_) {}, onDone: () {});
      // Плагин переотдаёт непогашенные покупки (оплатил, но приложение умерло до верификации)
      // в purchaseStream ТОЛЬКО после restorePurchases() — без вызова такие деньги «зависали».
      await _billing.iap.restorePurchases();
      final resp =
          await _billing.iap.queryProductDetails(_planToProduct.values.toSet());
      for (final p in resp.productDetails) {
        _billing.playPrices[p.id] = p.price;
      }
      // Готовность — только при непустой витрине: если продукты ещё не созданы в Play Console,
      // ready=true включал бы billingAvailable и отрезал Android-пользователям фолбэк на бота.
      _billing.ready = resp.productDetails.isNotEmpty;
    } catch (_) {
      _billing.ready = false;
    }
  }

  String? playPriceOf(String planCode) =>
      _billing.playPrices[_planToProduct[planCode]];

  Future<void> _buyPlan(String planCode) async {
    final id = _planToProduct[planCode];
    if (id == null) { _toast(tr('Тариф не найден')); return; }
    if (!_billing.ready) { _toast(tr('Магазин недоступен — попробуй позже')); return; }
    final resp = await _billing.iap.queryProductDetails({id});
    if (resp.productDetails.isEmpty) {
      _toast(tr('Продукт ещё не создан в Play Console (sub_mo/sub_q/sub_h/sub_yr)'));
      return;
    }
    _toast(tr('Открываю оплату…'));
    // applicationUserName → obfuscatedExternalAccountId у Google: сервер сверяет его с
    // sha256(tgId), поэтому чужой/перехваченный purchaseToken не зачислится на наш аккаунт.
    final ok = await _billing.iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: resp.productDetails.first,
        applicationUserName:
            tgId == null ? null : sha256.convert(utf8.encode('$tgId')).toString(),
      ),
    );
    // false = окно оплаты даже не открылось (сбой Play/нет сервисов) — показываем, не молчим.
    if (!ok) _toast(tr('Оплата не открылась — попробуй ещё раз'));
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        await _verifyPurchase(p);
      } else if (p.status == PurchaseStatus.error) {
        // Ошибку оплаты показываем пользователю — иначе тап по «Оплатить» выглядел «мёртвым».
        _toast(tr('Оплата не прошла — попробуй ещё раз'));
      }
    }
  }

  /// Серверная верификация. Признание покупки (completePurchase) — только после ok сервера,
  /// иначе Google вернёт деньги покупателю, а доступ уже выдан.
  Future<void> _verifyPurchase(PurchaseDetails p) async {
    final token = p.verificationData.serverVerificationData;
    if (token.isEmpty || _billing.pendingTokens.contains(token)) return;
    if (tgId == null || appToken == null) return;
    _billing.pendingTokens.add(token);
    _toast(tr('Проверяю покупку…'));
    try {
      final r = await http
          .post(Uri.parse('${kFnBase}google-play-verify'),
              headers: {'content-type': 'application/json', 'apikey': kApiKey},
              body: jsonEncode({
                'product_id': p.productID,
                'purchase_token': token,
                'telegram_id': tgId,
                'token': appToken,
              }))
          .timeout(const Duration(seconds: 20));
      final ok = r.statusCode == 200 &&
          (jsonDecode(r.body) is Map && (jsonDecode(r.body)['ok'] == true));
      if (ok) {
        if (p.pendingCompletePurchase) await _billing.iap.completePurchase(p);
        _toast(tr('Подписка активна 🙌'));
        await _refreshSub(silent: true);
      } else {
        _toast(tr('Покупка не подтверждена — напиши в поддержку'));
      }
    } catch (_) {
      _toast(_netErr); // токен остаётся в _billing.pendingTokens — повтор при следующей покупке
    } finally {
      _billing.pendingTokens.remove(token);
    }
  }
}
