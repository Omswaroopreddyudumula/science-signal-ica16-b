import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

const labTests = bool.fromEnvironment('LAB_TESTS');

enum Fault {
  none,
  deniedVerification,
  unavailable,
  quota,
  delayedAcknowledgement,
}

const fixedFields = [
  'schemaVersion',
  'variant',
  'categoryId',
  'questionCount',
  'correctCount',
];

class AttemptRecord {
  AttemptRecord(this.id, this.fields, this.timestamp);
  final String id;
  final Map<String, dynamic> fields;
  final Timestamp timestamp;
}

class AttemptStore {
  AttemptStore(this.uid, {FirebaseFirestore? db})
    : db = db ?? FirebaseFirestore.instance;
  final String uid;
  final FirebaseFirestore db;
  Fault fault = Fault.none;
  bool _denyNextRead = false;
  CollectionReference<Map<String, dynamic>> get attempts =>
      db.collection('users/$uid/attempts');
  String newId() => attempts.doc().id;
  void checkIdentity() {
    if (FirebaseAuth.instance.currentUser?.uid != uid) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unauthenticated',
        message: 'The initiating account changed.',
      );
    }
  }

  static Map<String, dynamic> fields(int score) => {
    'schemaVersion': 1,
    'variant': 'B',
    'categoryId': 17,
    'questionCount': 5,
    'correctCount': score,
  };
  static bool same(Map<String, dynamic> a, Map<String, dynamic> b) =>
      fixedFields.every(
        (k) => a[k] == b[k] && a[k].runtimeType == b[k].runtimeType,
      );
  static void validate(Map<String, dynamic> data) {
    if (data.length != 6 ||
        !data.keys.toSet().containsAll([...fixedFields, 'submittedAt']) ||
        data['schemaVersion'] is! int ||
        data['schemaVersion'] != 1 ||
        data['variant'] != 'B' ||
        data['categoryId'] is! int ||
        data['categoryId'] != 17 ||
        data['questionCount'] is! int ||
        data['questionCount'] != 5 ||
        data['correctCount'] is! int ||
        (data['correctCount'] as int) < 0 ||
        (data['correctCount'] as int) > 5 ||
        data['submittedAt'] is! Timestamp) {
      throw const FormatException(
        'Server record does not match the Class B schema.',
      );
    }
  }

  Future<void> commit(String id, Map<String, dynamic> frozen) async {
    checkIdentity();
    if (labTests && (fault == Fault.unavailable || fault == Fault.quota)) {
      final code = fault == Fault.quota ? 'resource-exhausted' : 'unavailable';
      fault = Fault.none;
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: code,
        message: 'Labeled development injection before commit.',
      );
    }
    final ref = attempts.doc(id);
    await db.runTransaction(
      (tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) {
          if (!same(existing.data()!, frozen)) {
            throw StateError(
              'Collision: this round ID already contains a different score. It will not be overwritten.',
            );
          }
        } else {
          tx.set(ref, frozen);
        }
      },
      timeout: const Duration(seconds: 8),
      maxAttempts: 2,
    );
    if (labTests && fault == Fault.deniedVerification) {
      _denyNextRead = true;
      fault = Fault.none;
    }
    if (labTests && fault == Fault.delayedAcknowledgement) {
      fault = Fault.none;
      await Future<void>.delayed(const Duration(seconds: 12));
    }
  }

  Future<AttemptRecord?> read(
    String id, {
    Map<String, dynamic>? expected,
  }) async {
    checkIdentity();
    if (labTests && _denyNextRead) {
      _denyNextRead = false;
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message:
            'Development injection: first verification after a real commit.',
      );
    }
    final snap = await attempts
        .doc(id)
        .get(const GetOptions(source: Source.server));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) {
      throw StateError('Server confirmation is not available.');
    }
    if (!snap.exists) return null;
    final data = snap.data()!;
    validate(data);
    if (expected != null && !same(data, expected)) {
      throw StateError(
        'Collision: server fields differ from this completed round.',
      );
    }
    return AttemptRecord(id, data, data['submittedAt'] as Timestamp);
  }

  Future<String?> latestId() async {
    checkIdentity();
    final snap = await attempts
        .orderBy('submittedAt', descending: true)
        .limit(1)
        .get(const GetOptions(source: Source.server));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites) {
      throw StateError('Server confirmation is not available.');
    }
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }
}
