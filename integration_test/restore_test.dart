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
  testWidgets('T07 real process restart and exact server retrieval', (
    tester,
  ) async {
    await initializeCloud();
    final restored = await FirebaseAuth.instance.authStateChanges().first;
    if (restored == null) {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: const String.fromEnvironment('TEST_A_EMAIL'),
        password: const String.fromEnvironment('TEST_A_PASSWORD'),
      );
    }
    expect(
      FirebaseAuth.instance.currentUser!.uid ==
          const String.fromEnvironment('TEST_A_UID'),
      true,
    );
    RoundController? c;
    runApp(ScienceApp(onController: (v) => c = v));
    for (var i = 0; c == null && i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(c, isNotNull);
    expect(c!.questions, isEmpty);
    await tester.runAsync(
      () => c!.retrieve(const String.fromEnvironment('RESTORE_ID')),
    );
    expect(c!.phase, Phase.cloudVerified, reason: c!.message);
    expect(c!.questions, isEmpty);
    expect(c!.verified!.fields['correctCount'], 2);
    expect(
      c!.verified!.timestamp.toDate().toUtc().toIso8601String(),
      const String.fromEnvironment('RESTORE_TIMESTAMP'),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('capture-root')),
      );
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
      binding.reportData = {
        'stage': 'restore',
        'screenshots': [
          {
            'screenshotName': 'T07-restart-server-retrieval',
            'bytes': bytes.toList(),
          },
        ],
        'records': [
          {
            'id': 'T07',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'precondition': 'App process stopped after the initial cloud test; network online; original ID retained only by external test harness',
            'action': 'Launch a fresh app process, restore user A authentication, retrieve the exact original ID without playing',
            'expected': 'Same original server record, score 2 and original timestamp; no replay or new save',
            'actual': 'Server-only retrieval returned original score 2 and exactly matching timestamp after process restart; no questions loaded',
            'result': 'PASS',
            'roundSuffix': c!.roundId!.substring(c!.roundId!.length - 6),
            'evidence': 'T07-restart-server-retrieval.png',
          },
        ],
        'serverRecord': {
          ...c!.verified!.fields,
          'submittedAt': c!.verified!.timestamp
              .toDate()
              .toUtc()
              .toIso8601String(),
        },
        'trace': c!.trace,
      };
      image.dispose();
    });
  });
}
