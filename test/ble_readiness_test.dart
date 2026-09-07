import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:pine_gomoku/services/ble_link.dart';

void main() {
  test(
    'waits for peripheral initialization instead of advertising too early',
    () async {
      var calls = 0;
      await waitForPeripheralReady(
        () async => ++calls < 3
            ? PeripheralReadinessState.unknown
            : PeripheralReadinessState.ready,
      );
      expect(calls, 3);
    },
  );
  test('unsupported peripheral reports an actionable error', () async {
    await expectLater(
      waitForPeripheralReady(() async => PeripheralReadinessState.unsupported),
      throwsStateError,
    );
  });
}
