// Автоперебор кандидатов (режим «лучший сервер»): правило «пробуем следующего или стоп».
//
// Зачем именно этот тест. Сам перебор через публичный API контроллера без живого движка не
// воспроизвести (connect/verify делает только TunnelEngine — та же причина, что в
// killswitch_test и reconnect_test), поэтому тест фиксирует решающее правило
// ConnectionController.roamContinues, которым цикл в toggle() выбирает между следующим
// кандидатом и честной остановкой:
//   • режим «лучший сервер»: кандидаты 1..4 мимо → пробуем следующего (до kMaxTryAttempts
//     за одно нажатие — человек больше не жмёт «подключиться» по пять раз вручную);
//   • пятый мимо → стоп: бесконечный перебор при лежащей сети долбил бы узлы вечно;
//   • ручной выбор сервера → стоп сразу (поведение прежнее: причина + мягкая подсказка
//     «выбери другой или включи "лучший сервер"»).
import 'package:flutter_test/flutter_test.dart';
import 'package:bitaps_vpn/main.dart';

void main() {
  test('автоперебор: в режиме «лучший сервер» — до 5 кандидатов за нажатие, дальше стоп', () {
    for (var attempt = 1; attempt < ConnectionController.kMaxTryAttempts; attempt++) {
      expect(ConnectionController.roamContinues(true, attempt), isTrue,
          reason: 'кандидат $attempt мимо — пробуем следующего тем же нажатием');
    }
    expect(ConnectionController.roamContinues(true, ConnectionController.kMaxTryAttempts), isFalse,
        reason: 'все ${ConnectionController.kMaxTryAttempts} мимо — честная остановка');
    expect(ConnectionController.kMaxTryAttempts, 5, reason: 'лимит из ТЗ: 5 кандидатов за нажатие');
  });

  test('автоперебор: ручной выбор сервера перебор НЕ запускает', () {
    for (var attempt = 1; attempt <= ConnectionController.kMaxTryAttempts; attempt++) {
      expect(ConnectionController.roamContinues(false, attempt), isFalse,
          reason: 'ручной выбор — одна попытка и подсказка, как раньше');
    }
  });
}
