import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sports_scope_companion/ble/relay/relay_gate.dart';
import 'package:sports_scope_companion/ble/relay/relay_store.dart';
import 'package:sports_scope_companion/ble/sensor_profile.dart';

void main() {
  test('relayKindOf reconnaît les trois mesures, forme courte ou longue', () {
    expect(relayKindOf('2a37'), SensorKind.heartRate);
    expect(relayKindOf('00002a63-0000-1000-8000-00805f9b34fb'), SensorKind.power);
    expect(relayKindOf('2a5b'), SensorKind.speedCadence);
    expect(relayKindOf('2a19'), isNull); // batterie : pas relayée
    expect(relayKindOf('2a66'), isNull); // point de contrôle : jamais relayé
  });

  test('RelayGate : la première source garde la main, la relève après silence', () {
    final gate = RelayGate();
    final t = DateTime(2026, 1, 1, 12);
    expect(gate.accept(SensorKind.heartRate, 'A', t), isTrue);
    expect(gate.accept(SensorKind.heartRate, 'B', t.add(const Duration(seconds: 1))), isFalse);
    expect(gate.accept(SensorKind.heartRate, 'A', t.add(const Duration(seconds: 2))), isTrue);
    expect(gate.accept(SensorKind.heartRate, 'B', t.add(const Duration(seconds: 9))), isTrue);
    // Une autre mesure a sa propre source.
    expect(gate.accept(SensorKind.power, 'B', t), isTrue);
  });

  test('RelayStore : éteint par défaut, tout relayé, et ça persiste', () async {
    final dir = await Directory.systemTemp.createTemp('relay');
    final file = File('${dir.path}/relay.json');
    final store = RelayStore(file);
    await store.load();
    expect(store.enabled, isFalse);
    expect(store.kinds, relayableKinds.toSet());

    await store.setEnabled(true);
    await store.setKind(SensorKind.heartRate, false);

    final again = RelayStore(file);
    await again.load();
    expect(again.enabled, isTrue);
    expect(again.allows(SensorKind.heartRate), isFalse);
    expect(again.allows(SensorKind.power), isTrue);
    await dir.delete(recursive: true);
  });
}
