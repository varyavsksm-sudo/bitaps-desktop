// Килл-свитч: при НЕОЖИДАННОМ обрыве VPN системный прокси держится (fail-closed) только
// там, где приложение реально может его удержать, — на десктопе с xray.
//
// Зачем именно этот тест. Семантика «обрыв ≠ отключение по кнопке» — ядро фичи: перепутай
// ветку — и либо трафик утечёт мимо туннеля (fail-open), либо интернет останется заблокирован
// после осознанного отключения человека. Сам обрыв через публичный API контроллера без живого
// движка не воспроизвести (события шлёт только TunnelEngine), поэтому тест фиксирует решающее
// правило ConnectionController.holdProxyOnDrop, которым _dropped выбирает между
// failClosed() (прокси НЕ снимаем) и обычным disconnect():
//   • тумблер ВКЛ + десктоп → держим прокси: порт мёртв, трафик умирает, а не идёт напрямую;
//   • тумблер ВЫКЛ → не держим никогда (прежнее поведение: прокси снимается, интернет прямой);
//   • Android/iOS → не держим даже при включённом тумблере: маршруты после смерти
//     VpnService/NetworkExtension удерживает только система («Постоянный VPN» + «Блокировать
//     соединения без VPN» / includeAllNetworks), и объявлять там «трафик заблокирован» было бы
//     ложью — поэтому blocked-состояние (карточка «Снять блокировку») там не возникает.
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/engine.dart';
import 'package:bitaps_vpn/main.dart';

void main() {
  test('килл-свитч: прокси при обрыве держим только на десктопе и только при включённом тумблере', () {
    expect(ConnectionController.holdProxyOnDrop(true, EngineKind.desktopXray), isTrue,
        reason: 'десктоп + тумблер ВКЛ = fail-closed: прокси НЕ снимаем');
    expect(ConnectionController.holdProxyOnDrop(false, EngineKind.desktopXray), isFalse,
        reason: 'тумблер ВЫКЛ — прежнее поведение, прокси снимаем');
    for (final kind in EngineKind.values) {
      if (kind == EngineKind.desktopXray) continue;
      expect(ConnectionController.holdProxyOnDrop(true, kind), isFalse,
          reason: '$kind: приложению удерживать нечего — блокировку не выдумываем');
      expect(ConnectionController.holdProxyOnDrop(false, kind), isFalse);
    }
  });
}
