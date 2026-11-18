import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:science_signal_16/main.dart';
import 'package:science_signal_16/round_controller.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('T08 actual Wi-Fi and mobile-data outage', (tester) async {
    await initializeCloud();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: const String.fromEnvironment('TEST_A_EMAIL'),
      password: const String.fromEnvironment('TEST_A_PASSWORD'),
    );
    RoundController? c;
    runApp(ScienceApp(onController: (v) => c = v));
    Future<void> until(bool Function() predicate, {int seconds = 35}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!predicate()) {
        if (DateTime.now().isAfter(end)) {
          fail('Offline test timeout: ${c?.phase.name}');
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
    }

    Future<void> shot(String name) async {
      await tester.pump(const Duration(milliseconds: 300));
      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture-root')),
        );
        final image = await b.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        binding.reportData ??= {};
        (binding.reportData!['screenshots'] ??= <dynamic>[]).add({
          'screenshotName': name,
          'bytes': bytes.toList(),
        });
        image.dispose();
      });
    }

    await until(() => c != null);
    await tester.runAsync(() => c!.start());
    expect(c!.phase, Phase.playing, reason: c!.message);
    for (var i = 0; i < 5; i++) {
      c!.choose('True');
      c!.next();
    }
    await tester.pump();
    final id = c!.roundId!;
    const dir = '/data/user/0/com.campusdesk.science_signal_16/cache';
    File('$dir/ica16-off-request').writeAsStringSync('request');
    await until(() => File('$dir/ica16-off-confirmed').existsSync());
    final operation = c!.submit();
    await until(
      () => c!.phase == Phase.saveUnknown || !c!.inFlight,
      seconds: 25,
    );
    expect(c!.phase, isNot(Phase.cloudVerified));
    expect(
      c!.acknowledged,
      false,
      reason: 'A transaction must not be acknowledged while the device has no network.',
    );
    expect(c!.roundId, id);
    await shot('T08-offline');
    File('$dir/ica16-on-request').writeAsStringSync('request');
    await until(() => File('$dir/ica16-on-confirmed').existsSync());
    await operation;
    await tester.runAsync(() => c!.reconcile());
    if (c!.phase == Phase.readyToSubmit) {
      await tester.runAsync(() => c!.submit());
    }
    expect(c!.phase, Phase.cloudVerified, reason: c!.message);
    expect(c!.roundId, id);
    await tester.pump();
    await shot('T08-recovered');
    binding.reportData!.addAll({
      'stage': 'physical-offline',
      'records': [
        {
          'id': 'T08',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'precondition': 'Completed unsaved live quiz; actual Wi-Fi and mobile data disabled by external device test controller; no active default network',
          'action': 'Submit with device disconnected; restore both network connections; reconcile and retry the original ID',
          'expected': 'No acknowledgement or cloud verification while offline; one recovered original-ID record after reconnect',
          'actual': 'Offline attempt remained unacknowledged and unresolved; reconnect plus original-ID reconciliation and retry produced a real server-verified document',
          'result': 'PASS',
          'roundSuffix': id.substring(id.length - 6),
          'evidence': 'T08-offline.png; T08-recovered.png; T08-device-network-control.json',
        },
      ],
      'trace': c!.trace,
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
