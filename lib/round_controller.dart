import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'attempt_store.dart';
import 'quiz.dart';

enum Phase {
  idle,
  loading,
  playing,
  readyToSubmit,
  submitting,
  verifying,
  cloudVerified,
  requestError,
  saveUnknown,
  permissionDenied,
  verificationUnavailable,
  collision,
}

class RoundController extends ChangeNotifier {
  RoundController(this.uid, {QuizApi? api, AttemptStore? store})
    : api = api ?? QuizApi(),
      store = store ?? AttemptStore(uid);
  final String uid;
  final QuizApi api;
  final AttemptStore store;
  Phase phase = Phase.idle;
  List<Question> questions = [];
  List<String?> answers = [];
  int index = 0, generation = 0;
  String? roundId;
  String message =
      'Start a science round or retrieve an existing cloud attempt.';
  Map<String, dynamic>? frozen;
  AttemptRecord? verified;
  bool acknowledged = false, inFlight = false, disposed = false;
  final List<Map<String, dynamic>> trace = [];
  int get score => List.generate(
    questions.length,
    (i) => i,
  ).where((i) => answers[i] == questions[i].correct).length;
  bool get unresolved =>
      inFlight ||
      {
        Phase.submitting,
        Phase.verifying,
        Phase.saveUnknown,
        Phase.permissionDenied,
        Phase.verificationUnavailable,
        Phase.collision,
      }.contains(phase);
  bool get identityMatches =>
      !disposed && FirebaseAuth.instance.currentUser?.uid == uid;
  bool active(int g, String? id) =>
      identityMatches && g == generation && id == roundId;
  void emit(String event) {
    if (disposed) return;
    trace.add({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event,
      'phase': phase.name,
      'roundSuffix': roundId?.substring(roundId!.length - 6),
      'acknowledged': acknowledged,
      'inFlight': inFlight,
    });
    notifyListeners();
  }

  Future<void> start() async {
    if (unresolved || !identityMatches) return;
    roundId = store.newId();
    generation++;
    frozen = null;
    verified = null;
    acknowledged = false;
    questions = [];
    answers = [];
    index = 0;
    await load();
  }

  Future<void> load() async {
    if (unresolved || !identityMatches) return;
    final g = generation, id = roundId;
    phase = Phase.loading;
    message = 'Loading five science questions…';
    emit('GET started');
    try {
      final fetched = await api.fetch();
      if (!active(g, id)) return;
      questions = fetched;
      answers = List.filled(5, null);
      index = 0;
      phase = Phase.playing;
      message = 'Choose True or False once.';
      emit('GET validated');
    } catch (e) {
      if (active(g, id)) {
        phase = Phase.requestError;
        message = e is FormatException ? e.message.toString() : e.toString();
        emit('GET rejected');
      }
    }
  }

  void choose(String answer) {
    if (phase != Phase.playing ||
        answers[index] != null ||
        !{'True', 'False'}.contains(answer)) {
      return;
    }
    answers[index] = answer;
    emit('answer locked');
  }

  void next() {
    if (phase != Phase.playing || answers[index] == null) return;
    if (index < 4) {
      index++;
    } else {
      phase = Phase.readyToSubmit;
      message = 'Review all five answers, then submit the completed score.';
    }
    emit('continue');
  }

  String describe(Object e) {
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' =>
          'Permission denied. The rules rejected this operation.',
        'unavailable' => 'Service unavailable. Check the connection and retry.',
        'resource-exhausted' =>
          'Service quota exhausted. Wait before a bounded retry.',
        'unauthenticated' =>
          'Authentication expired or changed. Restore the initiating account.',
        _ => '${e.code}: ${e.message ?? 'Cloud operation failed.'}',
      };
    }
    return e.toString();
  }

  void error(Object e, {required bool afterCommit}) {
    if (e is StateError && e.message.toString().contains('Collision')) {
      phase = Phase.collision;
    } else if (e is FirebaseException && e.code == 'permission-denied') {
      phase = Phase.permissionDenied;
    } else {
      phase = afterCommit ? Phase.verificationUnavailable : Phase.saveUnknown;
    }
    message = afterCommit
        ? 'Write acknowledged; verification unavailable. ${describe(e)} Retry only the server read of this ID.'
        : 'Save outcome unresolved. ${describe(e)} Reconcile this ID from the server before another save.';
    if (e is FirebaseException &&
        (e.message?.toLowerCase().contains('injection') ?? false)) {
      message += ' [DEVELOPMENT INJECTION]';
    }
    emit('cloud error');
  }

  // A UI timeout never cancels native work or unlocks a second operation.
  Future<T> observeRead<T>(Future<T> operation, int g, String? id) async {
    final timer = Timer(const Duration(seconds: 10), () {
      if (active(g, id) && inFlight) {
        phase = acknowledged
            ? Phase.verificationUnavailable
            : Phase.saveUnknown;
        message = acknowledged
            ? 'Write acknowledged; verification unavailable. Server read is still running; no overlapping retry is allowed.'
            : 'Server read timed out. Keep the original ID while the pending operation settles.';
        emit('server read UI timeout');
      }
    });
    try {
      return await operation;
    } finally {
      timer.cancel();
    }
  }

  Future<void> submit() async {
    if (phase != Phase.readyToSubmit ||
        inFlight ||
        roundId == null ||
        questions.length != 5 ||
        answers.any((a) => a == null) ||
        !identityMatches) {
      return;
    }
    frozen ??= Map.unmodifiable({
      ...AttemptStore.fields(score),
      'submittedAt': FieldValue.serverTimestamp(),
    });
    final g = generation, id = roundId!;
    inFlight = true;
    phase = Phase.submitting;
    message = 'Submitting this round once…';
    emit('transaction started');
    final timer = Timer(const Duration(seconds: 10), () {
      if (active(g, id) && inFlight && phase == Phase.submitting) {
        phase = Phase.saveUnknown;
        message = 'Save acknowledgement timed out. The operation may still finish. Keep this ID; retry is blocked while it is running.';
        emit('10 second UI timeout');
      }
    });
    try {
      await store.commit(id, frozen!);
      if (!active(g, id)) return;
      acknowledged = true;
      phase = Phase.verifying;
      message = 'Write acknowledged. Retrieving the exact server document…';
      emit('commit acknowledged');
      final record = await observeRead(store.read(id, expected: frozen), g, id);
      if (!active(g, id)) return;
      if (record == null) {
        throw StateError(
          'Acknowledged document is not visible from the server.',
        );
      }
      verified = record;
      phase = Phase.cloudVerified;
      message = 'Cloud verified. Exact server fields and timestamp match; no pending writes.';
      emit('server verified');
    } catch (e) {
      if (active(g, id)) error(e, afterCommit: acknowledged);
    } finally {
      timer.cancel();
      if (active(g, id)) {
        inFlight = false;
        emit('operation settled');
      }
    }
  }

  Future<void> reconcile() async {
    if (inFlight || roundId == null || !identityMatches) return;
    final g = generation, id = roundId!;
    inFlight = true;
    phase = Phase.verifying;
    message = acknowledged
        ? 'Write acknowledged. Retrying only the server read…'
        : 'Reconciling the original ID from the server…';
    emit('reconcile started');
    try {
      final record = await observeRead(store.read(id, expected: frozen), g, id);
      if (!active(g, id)) return;
      if (record == null) {
        if (acknowledged) {
          throw StateError(
            'Acknowledged document is not visible from the server.',
          );
        }
        phase = questions.length == 5 ? Phase.readyToSubmit : Phase.idle;
        message = 'Server confirms this ID is absent. You may retry the same frozen round. No new ID was generated.';
        emit('server absence confirmed');
      } else {
        verified = record;
        acknowledged = true;
        phase = Phase.cloudVerified;
        message =
            'Cloud verified. Same original server document; no duplicate save.';
        emit('reconcile verified');
      }
    } catch (e) {
      if (active(g, id)) error(e, afterCommit: acknowledged);
    } finally {
      if (active(g, id)) {
        inFlight = false;
        emit('reconcile settled');
      }
    }
  }

  Future<void> retrieve(String id) async {
    if (unresolved ||
        !identityMatches ||
        id.trim().isEmpty ||
        id.contains('/')) {
      return;
    }
    generation++;
    roundId = id.trim();
    frozen = null;
    verified = null;
    questions = [];
    answers = [];
    acknowledged = false;
    await reconcile();
  }

  Future<void> retrieveLatest() async {
    if (unresolved || !identityMatches) return;
    final g = ++generation;
    inFlight = true;
    phase = Phase.verifying;
    message = 'Finding the latest server attempt…';
    emit('latest server query');
    try {
      final id = await observeRead(store.latestId(), g, roundId);
      if (!identityMatches || generation != g) return;
      inFlight = false;
      if (id == null) {
        phase = Phase.idle;
        message = 'No cloud attempts exist for this account.';
        emit('no prior attempts');
        return;
      }
      // retrieve checks unresolved; reset the settled query state first.
      phase = Phase.idle;
      await retrieve(id);
    } catch (e) {
      if (identityMatches && generation == g) {
        inFlight = false;
        phase = Phase.idle;
        message = describe(e);
        emit('latest query failed');
      }
    }
  }

  @override
  void dispose() {
    disposed = true;
    generation++;
    api.close();
    super.dispose();
  }
}
