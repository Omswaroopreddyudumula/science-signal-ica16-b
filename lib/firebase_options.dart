import 'package:firebase_core/firebase_core.dart';

/// Android configuration from the registered Firebase application.
/// Client config is supplied at build time; passwords and tokens are never here.
class DefaultFirebaseOptions {
  static const currentPlatform = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
    appId: String.fromEnvironment('FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID'),
  );
}
