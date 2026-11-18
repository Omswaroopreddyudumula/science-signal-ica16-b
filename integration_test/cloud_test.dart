import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:science_signal_16/main.dart';
import 'package:science_signal_16/attempt_store.dart';
import 'package:science_signal_16/firebase_options.dart';
import 'package:science_signal_16/quiz.dart';
import 'package:science_signal_16/round_controller.dart';

class SwitchingClient extends http.BaseClient {
  final real = http.Client();
  String? fixture;
  String? lastBody;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (fixture != null) {
      return http.StreamedResponse(Stream.value(utf8.encode(fixture!)), 200);
    }
    final response = await real.send(request);
    final bytes = await response.stream.toBytes();
    lastBody = utf8.decode(bytes);
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
    );
  }

  @override
  void close() => real.close();
}

Map<String, dynamic> fixture() => {
  'response_code': 0,
  'results': List.generate(
    5,
    (i) => {
      'category': 'Science%20%26%20Nature',
      'difficulty': 'medium',
      'type': 'boolean',
      'question': 'Test%20science%20question',
      'correct_answer': 'True',
      'incorrect_answers': ['False'],
    },
  ),
};
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('T01-T06 and T08-T12 against deployed Firebase', (tester) async {
    await initializeCloud();
    await FirebaseAuth.instance.signOut();
    RoundController? current;
    late SwitchingClient client;
    runApp(
      ScienceApp(
        controllerFactory: (uid) {
          client = SwitchingClient();
          return RoundController(uid, api: QuizApi(client: client));
        },
        onController: (c) => current = c,
      ),
    );
    Future<void> until(bool Function() predicate, {int seconds = 30}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (!predicate()) {
        if (DateTime.now().isAfter(end)) {
          fail('Timed out: ${current?.phase.name}; ${current?.message}');
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
      }
      await tester.pump();
    }

    Future<void> top() async {
      final f = find.byType(Scrollable).first;
      if (f.evaluate().isNotEmpty) {
        tester.state<ScrollableState>(f).position.jumpTo(0);
        await tester.pump();
      }
    }

    Future<void> tap(String key) async {
      await top();
      final f = find.byKey(Key(key));
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          f,
          400,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
      }
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
    }

    Future<void> shot(String name) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await top();
      await tester.pump(const Duration(milliseconds: 300));
      // Raster capture runs outside the widget test clock.
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('capture-root')),
        );
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        binding.reportData ??= <String, dynamic>{};
        (binding.reportData!['screenshots'] ??= <dynamic>[]).add({
          'screenshotName': name,
          'bytes': bytes.toList(),
        });
        image.dispose();
      });
      // ignore: avoid_print
      print('Captured $name');
    }

    final records = <Map<String, dynamic>>[];
    void record(
      String id,
      String pre,
      String action,
      String expected,
      String actual,
      String evidence,
    ) {
      final c = current;
      records.add({
        'id': id,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'precondition': pre,
        'action': action,
        'expected': expected,
        'actual': actual,
        'result': 'PASS',
        'evidence': evidence,
        'roundSuffix': c?.roundId == null
            ? null
            : c!.roundId!.substring(c.roundId!.length - 6),
      });
      // No credentials or tokens in console output.
      // ignore: avoid_print
      print('$id PASS: $actual');
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!.addAll({
        'stage': 'cloud',
        'records': records,
        'trace': c?.trace ?? [],
      });
    }

    await until(() => find.byKey(const Key('sign-in')).evaluate().isNotEmpty);
    await tester.enterText(
      find.byKey(const Key('email')),
      const String.fromEnvironment('TEST_A_EMAIL'),
    );
    await tester.enterText(
      find.byKey(const Key('password')),
      'DeliberatelyWrongPassword123!',
    );
    await tap('sign-in');
    await until(
      () => find.byKey(const Key('auth-error')).evaluate().isNotEmpty,
    );
    await shot('T01-invalid-sign-in');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    // Replace text through the controller after Android IME dismissal settles.
    tester
        .widget<TextField>(find.byKey(const Key('password')))
        .controller!
        .text = const String.fromEnvironment(
      'TEST_A_PASSWORD',
    );
    await tester.pump();
    expect(
      tester
              .widget<TextField>(find.byKey(const Key('password')))
              .controller!
              .text ==
          const String.fromEnvironment('TEST_A_PASSWORD'),
      true,
      reason: 'The test must enter the configured password without logging it.',
    );
    // ignore: avoid_print
    print('Configured sign-in input verified without exposing credentials');
    await tap('sign-in');
    await until(() => current != null);
    expect(
      FirebaseAuth.instance.currentUser!.uid,
      const String.fromEnvironment('TEST_A_UID'),
    );
    record(
      'T01',
      'Signed out; two dedicated cloud test accounts exist',
      'Invalid password, then valid user A sign-in',
      'Visible error, then intended authenticated UID',
      'Invalid credential error shown; authorized user A authenticated',
      'T01-invalid-sign-in.png',
    );
    final c = current!;
    await tap('start');
    await until(() => c.phase != Phase.loading, seconds: 20);
    expect(c.phase, Phase.playing, reason: c.message);
    expect(c.questions.length, 5);
    await shot('T02-live-question');
    final pair = {
      'encoded': c.questions.first.encoded,
      'decoded': c.questions.first.text,
    };
    record(
      'T02',
      'User A online',
      'GET exact Class B endpoint',
      'Five validated medium category-17 boolean questions',
      'Five live questions accepted; percent-encoded strings decoded',
      'T02-live-question.png',
    );
    for (var i = 0; i < 5; i++) {
      final correct = c.questions[i].correct;
      await tap(
        'answer-${i < 2
            ? correct
            : correct == 'True'
            ? 'False'
            : 'True'}',
      );
      final score = c.score;
      c.choose(correct == 'True' ? 'False' : 'True');
      expect(c.score, score);
      if (i == 0) await shot('T04-correct');
      if (i == 2) await shot('T04-incorrect');
      await tap('continue');
    }
    expect(c.phase, Phase.readyToSubmit);
    expect(c.score, 2);
    expect(c.answers.where((a) => a != null).length, 5);
    for (var i = 0; i < 5; i++) {
      await top();
      final f = find.byKey(Key('review-$i'));
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          f,
          350,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
      }
      expect(f, findsOneWidget);
    }
    record(
      'T04',
      'Five live questions loaded',
      'Choose two correct and three incorrect answers; attempt repeated selection',
      '2/5, locked choices, text plus color feedback',
      'Final score 2/5; repeated answer calls did not change score',
      'T04-correct.png; T04-incorrect.png',
    );
    final firstId = c.roundId!;
    final before = await c.store.attempts.get(
      const GetOptions(source: Source.server),
    );
    await tap('submit');
    unawaited(c.submit());
    await until(() => !c.inFlight, seconds: 35);
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    expect(c.verified!.fields['correctCount'], 2);
    final original = c.verified!;
    final after = await c.store.attempts.get(
      const GetOptions(source: Source.server),
    );
    expect(after.size, before.size + 1);
    await shot('T06-cloud-verified');
    record(
      'T06',
      'Completed 2/5 round; user A online',
      'Submit and immediately repeat submission',
      'One immutable attempt, server timestamp, exact server read',
      'One additional cloud document; correctCount 2; resolved timestamp; server metadata checked',
      'T06-cloud-verified.png',
    );
    await tester.runAsync(
      () => Future<void>.delayed(Duration(seconds: c.api.cooldown + 1)),
    );
    await tap('replay');
    await until(() => c.phase != Phase.loading);
    expect(c.phase, Phase.playing, reason: c.message);
    expect(c.roundId, isNot(firstId));
    expect(c.score, 0);
    expect(c.answers.every((a) => a == null), true);
    record(
      'T05',
      'First round reviewed and cloud verified',
      'Review all five entries and Replay',
      'Five review entries; new ID and clean state',
      'All review entries found; new ID; score 0 and no inherited answers',
      'T06-cloud-verified.png; round trace',
    );
    Future<void> finishRound() async {
      if (c.phase != Phase.playing) {
        await tester.runAsync(
          () => Future<void>.delayed(Duration(seconds: c.api.cooldown + 1)),
        );
        await c.start();
      }
      expect(c.phase, Phase.playing, reason: c.message);
      for (var i = 0; i < 5; i++) {
        c.choose('True');
        c.next();
      }
      await tester.pump();
      expect(c.phase, Phase.readyToSubmit);
    }

    await finishRound();
    final offlineId = c.roundId!;
    await FirebaseFirestore.instance.disableNetwork();
    final offlineFuture = c.submit();
    await until(() => c.phase == Phase.saveUnknown || !c.inFlight, seconds: 25);
    await tester.pump();
    await shot('T08-offline');
    expect(c.phase, isNot(Phase.cloudVerified));
    expect(c.roundId, offlineId);
    await FirebaseFirestore.instance.enableNetwork();
    await offlineFuture;
    if (c.phase != Phase.cloudVerified) {
      await c.reconcile();
      if (c.phase == Phase.readyToSubmit) await c.submit();
    }
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    expect(c.roundId, offlineId);
    await shot('T08-recovered');
    record(
      'T08',
      'Completed unsaved round',
      'Disable actual Firestore networking, submit, reconnect and reconcile original ID',
      'No false success or new ID; bounded recovery',
      'Offline did not report verified; reconnect/reconcile recovered the same ID',
      'T08-offline.png; T08-recovered.png',
    );
    await finishRound();
    c.store.fault = Fault.deniedVerification;
    final deniedId = c.roundId!;
    await c.submit();
    expect(c.acknowledged, true);
    expect(c.phase, Phase.permissionDenied);
    expect(c.roundId, deniedId);
    expect(c.message, contains('Write acknowledged; verification unavailable'));
    await tester.pump();
    await shot('T09-write-acknowledged-read-denied');
    final committed = await c.store.attempts
        .doc(deniedId)
        .get(const GetOptions(source: Source.server));
    expect(committed.exists, true);
    final countBefore = (await c.store.attempts.get(
      const GetOptions(source: Source.server),
    )).size;
    await c.reconcile();
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    expect(c.roundId, deniedId);
    expect(
      (await c.store.attempts.get(const GetOptions(source: Source.server)))
          .size,
      countBefore,
    );
    expect(c.verified!.timestamp, committed.data()!['submittedAt']);
    await tester.pump();
    await shot('T09-same-record-verified');
    record(
      'T09',
      'Completed round; labeled first-read fault enabled',
      'Real transaction, inject first verification denial, retry only server read',
      'Acknowledged write preserved; same server record verified; no duplicate',
      'Real committed document exists; retry kept ID, count and original timestamp unchanged',
      'T09-write-acknowledged-read-denied.png; T09-same-record-verified.png',
    );
    final appB = await Firebase.initializeApp(
      name: 'class-b-negative-tests',
      options: DefaultFirebaseOptions.currentPlatform,
    );
    final authB = FirebaseAuth.instanceFor(app: appB);
    await authB.signInWithEmailAndPassword(
      email: const String.fromEnvironment('TEST_B_EMAIL'),
      password: const String.fromEnvironment('TEST_B_PASSWORD'),
    );
    final dbB = FirebaseFirestore.instanceFor(app: appB);
    dbB.settings = const Settings(persistenceEnabled: false);
    final aPath = 'users/${c.uid}/attempts/$firstId';
    Future<void> denied(Future<Object?> Function() operation) async {
      try {
        await operation();
        fail('Expected deployed rules to deny operation');
      } on FirebaseException catch (e) {
        expect(e.code, 'permission-denied');
      }
    }

    await denied(
      () => dbB.doc(aPath).get(const GetOptions(source: Source.server)),
    );
    await denied(
      () => dbB.collection('users/${c.uid}/attempts').doc().set({
        ...AttemptStore.fields(2),
        'submittedAt': FieldValue.serverTimestamp(),
      }),
    );
    record(
      'T10',
      'Separate Firebase client authenticated as B',
      'Read and create under user A attempt path',
      'Both rejected by deployed owner rules',
      'Cross-user server read and write returned permission-denied',
      'cloud test trace; deployed firestore.rules',
    );
    await denied(
      () => c.store.attempts.doc().set({
        ...AttemptStore.fields(6),
        'submittedAt': FieldValue.serverTimestamp(),
      }),
    );
    await denied(
      () => c.store.attempts.doc().set({
        ...AttemptStore.fields(2),
        'submittedAt': FieldValue.serverTimestamp(),
        'extra': true,
      }),
    );
    await denied(
      () => c.store.attempts.doc(firstId).update({'correctCount': 5}),
    );
    final preserved = await c.store.read(firstId);
    expect(preserved!.fields['correctCount'], 2);
    expect(preserved.timestamp, original.timestamp);
    record(
      'T11',
      'Valid original cloud attempt exists',
      'Attempt score 6, extra field and update',
      'All denied; original unchanged',
      'Three permission-denied results; original score 2 and timestamp unchanged',
      'cloud test trace; deployed firestore.rules',
    );
    // Collision is checked without writing a different payload under the original ID.
    try {
      await c.store.commit(firstId, {
        ...AttemptStore.fields(5),
        'submittedAt': FieldValue.serverTimestamp(),
      });
      fail('Expected collision');
    } on StateError catch (e) {
      expect(e.message, contains('Collision'));
    }
    await finishRound();
    final failureId = c.roundId!;
    for (final fault in [Fault.unavailable, Fault.quota]) {
      c.store.fault = fault;
      await c.submit();
      expect(c.phase, Phase.saveUnknown);
      expect(c.roundId, failureId);
      expect(
        c.message,
        contains(
          fault == Fault.quota ? 'quota exhausted' : 'Service unavailable',
        ),
      );
      await tester.pump();
      await shot(
        fault == Fault.quota
            ? 'T12-quota-injection'
            : 'T12-unavailable-injection',
      );
      await c.reconcile();
      expect(c.phase, Phase.readyToSubmit, reason: c.message);
    }
    await c.submit();
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    record(
      'T12',
      'Completed round; labeled error hooks enabled',
      'Inject unavailable, then resource-exhausted; reconcile between bounded attempts',
      'Distinct errors, no false success, same ID',
      'Both errors visible; server absence checked before retry; real final write/read succeeded',
      'T12-unavailable-injection.png; T12-quota-injection.png',
    );
    await finishRound();
    c.store.fault = Fault.delayedAcknowledgement;
    final delayedId = c.roundId!;
    final delayed = c.submit();
    await until(() => c.phase == Phase.saveUnknown && c.inFlight, seconds: 20);
    expect(c.roundId, delayedId);
    await c.submit();
    expect(c.roundId, delayedId);
    await shot('timeout-acknowledgement-unknown');
    await delayed;
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    // Invalid API fixtures exercise the same controller/UI path; no live calls are made here.
    for (final bad in ['encoding', 'code', 'four']) {
      await tester.runAsync(
        () => Future<void>.delayed(Duration(seconds: c.api.cooldown + 1)),
      );
      final data = fixture();
      if (bad == 'encoding') data['results'][0]['question'] = 'Bad%ZZ';
      if (bad == 'code') data['response_code'] = 1;
      if (bad == 'four') (data['results'] as List).removeLast();
      client.fixture = jsonEncode(data);
      await c.start();
      expect(c.phase, Phase.requestError);
      expect(c.questions, isEmpty);
      final previous = c.message;
      await c.load();
      expect(c.phase, Phase.requestError);
      expect(c.message, contains('Wait'));
      expect(previous, isNotEmpty);
      await tester.pump();
      if (bad == 'four') await shot('T03-invalid-data-rate-limited');
    }
    client.fixture = null;
    record(
      'T03',
      'Development-only invalid response fixtures',
      'Inject malformed percent encoding, nonzero code and four results; retry immediately',
      'Play blocked for every case; retry rate-limited',
      'All three fixtures rejected; immediate retry says Wait; no invalid round became playable',
      'T03-invalid-data-rate-limited.png; quiz unit tests',
    );
    // Restore the original real record without starting or saving another round.
    await c.retrieve(firstId);
    expect(c.phase, Phase.cloudVerified, reason: c.message);
    binding.reportData ??= <String, dynamic>{};
    binding.reportData!.addAll({
      'stage': 'cloud',
      'records': records,
      'encodedPair': pair,
      'trace': c.trace,
      'restoreId': firstId,
      'firstRoundSuffix': firstId.substring(firstId.length - 6),
      't09RoundSuffix': deniedId.substring(deniedId.length - 6),
      'serverRecord': {
        ...original.fields,
        'submittedAt': original.timestamp.toDate().toUtc().toIso8601String(),
      },
      'collisionCheck':
          'Changed-score same-ID commit rejected; original unchanged',
    });
    await authB.signOut();
    await appB.delete();
  }, timeout: const Timeout(Duration(minutes: 12)));
}
