# Science Signal ICA16 Class B

Om Swaroop Reddy Udumula · Undergraduate pathway

A Flutter Android quiz using live OpenTDB questions, Firebase Email/Password authentication, and deployed Cloud Firestore. A create-once transaction and a separate server-only read distinguish a committed attempt from a verified attempt. This is a real cloud implementation, not the earlier local score simulation.

## Setup and platform

Test target: Pixel 8 emulator running Android 17. Flutter 3.47.2 / Dart 3.13.2. The Android package is `com.campusdesk.science_signal_16`. Firebase project: `campus-supply-desk-om-261104`; Cloud Firestore Standard edition, Native mode; Email/Password authentication enabled. A dedicated Android application and dedicated test users were created for this activity. Existing unrelated project rules were preserved; their earlier expiration was not extended.

1. Install Flutter, Android SDK, Firebase CLI and FlutterFire CLI. Run `flutter pub get`.
2. Use a Firebase project you control. Enable Email/Password authentication and create two authorized test users. No passwords, tokens or service-account keys belong in this repository.
3. Register the Android package, then run `flutterfire configure --project YOUR_PROJECT_ID --platforms android --android-package-name com.campusdesk.science_signal_16`.
4. For the checked-in generated options, the client API key is supplied at build time. Put `{"FIREBASE_API_KEY":"your Firebase Android client API key","LAB_TESTS":"true"}` in an ignored local build-defines JSON. Match the generated options to your own project. This client configuration is not an Admin credential or an authorization boundary.
5. Review `firestore.rules`, select the intended project, and deploy with `firebase deploy --only firestore:rules --project YOUR_PROJECT_ID`. If using a new project, remove the unrelated legacy `campus_products` rule block; the `users/{uid}/attempts/{roundId}` contract is the Activity 16 rule.
6. Run `flutter run -d emulator-5554 --dart-define-from-file=/absolute/path/to/build-defines.json`.

The delivered release APK is already configured for the activity project. Sign in using authorized test access obtained privately from the project owner. The app intentionally has no public self-registration screen. Instructor access must be shared only through an approved private course channel; it is not embedded in the APK or public source.

## Class B contract

Path: `users/{FirebaseAuth.currentUser.uid}/attempts/{roundId}`. The ID is generated once at round start using `attempts.doc().id`; no write occurs merely by allocating it.

Exactly six fields are stored:

| Field | Value |
| --- | --- |
| schemaVersion | integer 1 |
| variant | string B |
| categoryId | integer 17 |
| questionCount | integer 5 |
| correctCount | integer 0–5 |
| submittedAt | server timestamp |

No question text, names, student IDs, passwords, or tokens are stored in an attempt. Rules permit owner reads and validated creates; all updates and deletes are denied. These rules do not prove an owner earned an in-range score. A trusted scoring backend would be required for that stronger claim.

The transaction reads the exact document first. If absent it creates the frozen payload. If the five non-timestamp fields match, it reuses the existing record. Different fields produce a collision instead of overwriting. IDs, UI changes, external calls, and notification effects never occur inside the transaction callback.

Verification uses `GetOptions(source: Source.server)`. It requires existence, exactly matching fixed fields, a resolved timestamp, `isFromCache == false`, and `hasPendingWrites == false`. Only that path produces Cloud verified. Firestore disk persistence is disabled. Firebase Auth session restoration is not treated as cloud score verification.

## Quiz validation

GET `https://opentdb.com/api.php?amount=5&category=17&difficulty=medium&type=boolean&encode=url3986` with a 10-second timeout. Require HTTP 200, response code zero, exactly five records, nonempty decoded prompts, decoded Science & Nature category, medium difficulty, boolean type and exactly opposing True/False answers. Percent decoding uses `Uri.decodeComponent`; malformed encoding is normalized to a readable validation error. Requests are user-triggered and at least five seconds apart, including failed responses. No automatic retry loop is implemented.

Selections are locked once per question. True/False order stays fixed; Continue requires an answer. Feedback includes text and color. The results page reviews all five selections and correct answers. Replay creates a new ID and clears prior answers only when cloud outcome is resolved.

## Recovery and development hooks

Build with `LAB_TESTS=true` to show the explicitly labeled test panel. The classroom release includes these hooks. Default builds without that define hide them.

- `deniedVerification`: performs the real cloud transaction, then injects permission-denied on the first verification read only. Rules remain intact. Retry performs only a real server read of the same ID.
- `unavailable` / `quota`: inject pre-commit errors without exhausting a real project. The original ID remains; a server reconciliation is required before retrying the frozen save.
- `delayedAcknowledgement`: delays observation of an actual committed write by 12 seconds. The 10-second UI timer shows saveUnknown while `inFlight` continues blocking overlap. A UI timeout never cancels the underlying operation.
- Network switch: actually disables/enables Firestore networking; it does not simulate a saved record. Transactions fail offline.

Sign-out and replay are blocked while unresolved. Callbacks are bound to UID, round ID and generation; a changed authentication session cannot attach the old result to the next user. `acknowledged` stays true after a successful transaction even if verification is denied. The amber cloud icon and message say Write acknowledged; verification unavailable. No result is deleted or duplicated to make that message disappear.

## Reproduce restart retrieval

Submit and server-verify a completed round under authorized test user A. Record its ID privately, stop the app, and reopen while online as the same user. Choose Retrieve latest server attempt, or enter the original full ID in the retrieval field. The app makes a server-only read without replaying the quiz. Screenshots and public traces display only the last six ID characters. Full IDs and account access are kept outside the public evidence package.

## Tests

```sh
flutter test test/quiz_test.dart
flutter analyze
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/cloud_test.dart -d emulator-5554 --dart-define-from-file=/private/path/test-defines.json
# Stop the app process, then run the independent restart test with RESTORE_ID and RESTORE_TIMESTAMP:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/restore_test.dart -d emulator-5554 --dart-define-from-file=/private/path/test-defines.json
flutter build apk --release --dart-define-from-file=/private/path/build-defines.json
```

The private test-defines file also supplies TEST_A_EMAIL, TEST_A_PASSWORD, TEST_A_UID, TEST_B_EMAIL, TEST_B_PASSWORD and TEST_B_UID. These are test-run inputs, not application constants or committed credentials. The driver keeps the exact retrieval ID in a private run file and writes only redacted public records. Captures are raster images of the actual Flutter interface running on the Android emulator.

T08 is additionally verified with actual device connectivity disabled by tools/network_test.py, not merely the Firestore SDK network toggle. Start that controller in a separate terminal, then run integration_test/offline_test.dart using the same driver and private test-defines. It restores Wi-Fi and mobile data in a finally block and imposes an offline safety limit. The corrected record is in physical-offline-results.json.

T01–T12 records, state traces, actual encoded/decoded pair, deployed-rule evidence, and server records are in `evidence/`. The evidence document contains all six 120–180 word responses and the instructor-candidate critique. Graduate extensions are not claimed.

## Build and delivery

`flutter build apk --release --dart-define-from-file=/private/path/build-defines.json` produces `build/app/outputs/flutter-apk/app-release.apk`. The delivered file is named `ICA16_B_OmSwaroopReddyUdumula.apk`. It is a release-mode classroom APK using development signing, not an app-store publication. Build/platform/commit evidence is recorded with the submission document. Obtain the final repository hash with `git rev-parse HEAD`.

## Assistance and critique

OpenAI Codex assisted with implementation, test automation, troubleshooting and report drafting on November 18, 2026. Actual observations come from the recorded runs. The critique uses the instructor-provided flawed candidate; it was not executed and no production rules were weakened. Review the code and evidence before an instructor walkthrough.

## References

- [Course Activity 16 Class B guide](https://codd.cs.gsu.edu/~lhenry23/mad/ica/act16/V1/index2b.html)
- [Firestore transactions](https://firebase.google.com/docs/firestore/manage-data/transactions)
- [Firestore field validation rules](https://firebase.google.com/docs/firestore/security/rules-fields)
- [Firestore offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline)
