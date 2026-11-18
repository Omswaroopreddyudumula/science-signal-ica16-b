import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'attempt_store.dart';
import 'firebase_options.dart';
import 'round_controller.dart';

Future<void> initializeCloud() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: false,
  );
}

Future<void> main() async {
  await initializeCloud();
  runApp(const ScienceApp());
}

class ScienceApp extends StatelessWidget {
  const ScienceApp({super.key, this.onController, this.controllerFactory});
  final void Function(RoundController)? onController;
  final RoundController Function(String)? controllerFactory;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const Key('capture-root'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Science Signal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff146b75)),
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return s.data == null
              ? const SignIn()
              : QuizScreen(
                  key: ValueKey(s.data!.uid),
                  user: s.data!,
                  onController: onController,
                  controllerFactory: controllerFactory,
                );
        },
      ),
    ),
  );
}

class SignIn extends StatefulWidget {
  const SignIn({super.key});
  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: email.text.trim(),
            password: password.text,
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FirebaseAuthException
              ? 'Sign-in failed (${e.code}). Check your account and connection.'
              : 'Sign-in timed out. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Science Signal')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Trust the evidence',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Class B • Five medium science questions\nSign in to save and verify your cloud attempt.',
              ),
              const SizedBox(height: 24),
              TextField(
                key: const Key('email'),
                controller: email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('password'),
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              if (error != null)
                Text(
                  error!,
                  key: const Key('auth-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                key: const Key('sign-in'),
                onPressed: busy ? null : login,
                child: Text(busy ? 'Signing in…' : 'Sign in'),
              ),
              const Text(
                'Use an authorized test account. Credentials are never included in score records.',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.user,
    this.onController,
    this.controllerFactory,
  });
  final User user;
  final void Function(RoundController)? onController;
  final RoundController Function(String)? controllerFactory;
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final RoundController c;
  final retrieveId = TextEditingController();
  bool offline = false;
  @override
  void initState() {
    super.initState();
    c =
        widget.controllerFactory?.call(widget.user.uid) ??
        RoundController(widget.user.uid);
    widget.onController?.call(c);
    c.addListener(refresh);
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(refresh);
    c.dispose();
    retrieveId.dispose();
    super.dispose();
  }

  Future<void> network(bool value) async {
    if (value) {
      await FirebaseFirestore.instance.disableNetwork();
    } else {
      await FirebaseFirestore.instance.enableNetwork();
    }
    if (mounted) setState(() => offline = value);
  }

  @override
  Widget build(BuildContext context) {
    final reviewing =
        {
          Phase.readyToSubmit,
          Phase.submitting,
          Phase.verifying,
          Phase.cloudVerified,
          Phase.saveUnknown,
          Phase.permissionDenied,
          Phase.verificationUnavailable,
          Phase.collision,
        }.contains(c.phase) &&
        c.questions.length == 5;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Science Signal'),
        actions: [
          TextButton(
            key: const Key('sign-out'),
            onPressed: c.unresolved
                ? null
                : () => FirebaseAuth.instance.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              key: const Key('page-scroll'),
              padding: const EdgeInsets.all(20),
              children: [
                Text('Class B • ${widget.user.email}'),
                const SizedBox(height: 8),
                if (c.roundId != null)
                  SelectableText(
                    'Round ID suffix: …${c.roundId!.substring(c.roundId!.length - 6)}',
                    key: const Key('round-id'),
                  ),
                const SizedBox(height: 12),
                Container(
                  key: const Key('cloud-status'),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.phase == Phase.cloudVerified
                        ? Colors.green.shade100
                        : c.acknowledged
                        ? Colors.amber.shade100
                        : Colors.blueGrey.shade50,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            c.phase == Phase.cloudVerified
                                ? Icons.verified_outlined
                                : c.acknowledged
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_outlined,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              c.phase.name,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(c.message),
                      if (c.verified != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Server score: ${c.verified!.fields['correctCount']} / 5',
                        ),
                        Text(
                          'Server timestamp: ${c.verified!.timestamp.toDate().toUtc().toIso8601String()}',
                        ),
                        const Text('Source: server • Pending writes: false'),
                      ],
                    ],
                  ),
                ),
                if (c.phase == Phase.loading || c.inFlight)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: LinearProgressIndicator(),
                  ),
                if (c.phase == Phase.idle)
                  FilledButton(
                    key: const Key('start'),
                    onPressed: c.start,
                    child: const Text('Start science round'),
                  ),
                if (c.phase == Phase.requestError)
                  FilledButton(
                    key: const Key('retry-questions'),
                    onPressed: c.load,
                    child: const Text('Retry questions after five seconds'),
                  ),
                if (c.phase == Phase.playing) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Question ${c.index + 1} of 5',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  LinearProgressIndicator(value: (c.index + 1) / 5),
                  const SizedBox(height: 12),
                  Text(
                    c.questions[c.index].text,
                    key: const Key('question'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: ['True', 'False']
                        .map(
                          (answer) => Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: FilledButton(
                                key: Key('answer-$answer'),
                                onPressed: c.answers[c.index] == null
                                    ? () => c.choose(answer)
                                    : null,
                                child: Text(answer),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (c.answers[c.index] != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        c.answers[c.index] == c.questions[c.index].correct
                            ? 'Correct! One point recorded.'
                            : 'Incorrect. Correct answer: ${c.questions[c.index].correct}.',
                        key: const Key('feedback'),
                        style: TextStyle(
                          color:
                              c.answers[c.index] == c.questions[c.index].correct
                              ? Colors.green.shade800
                              : Colors.red.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Text('Score: ${c.score} / 5'),
                  FilledButton(
                    key: const Key('continue'),
                    onPressed: c.answers[c.index] == null ? null : c.next,
                    child: Text(
                      c.index == 4 ? 'Review all answers' : 'Continue',
                    ),
                  ),
                ],
                if (reviewing) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Round complete • ${c.score} / 5',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (var i = 0; i < 5; i++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${i + 1}. ${c.questions[i].text}\nYour answer: ${c.answers[i]} • Correct answer: ${c.questions[i].correct}',
                          key: Key('review-$i'),
                        ),
                      ),
                    ),
                  if (c.phase == Phase.readyToSubmit)
                    FilledButton(
                      key: const Key('submit'),
                      onPressed: c.inFlight ? null : c.submit,
                      child: const Text('Submit completed attempt'),
                    ),
                ],
                if (c.unresolved && !c.inFlight)
                  FilledButton(
                    key: const Key('reconcile'),
                    onPressed: c.reconcile,
                    child: Text(
                      c.acknowledged
                          ? 'Retry server verification'
                          : 'Reconcile original round ID',
                    ),
                  ),
                if (c.phase == Phase.cloudVerified)
                  OutlinedButton(
                    key: const Key('replay'),
                    onPressed: c.start,
                    child: const Text('Replay with a new round ID'),
                  ),
                const Divider(height: 32),
                TextField(
                  key: const Key('retrieve-id'),
                  controller: retrieveId,
                  enabled: !c.unresolved,
                  decoration: const InputDecoration(
                    labelText: 'Retrieve an existing round ID',
                    border: OutlineInputBorder(),
                  ),
                ),
                OutlinedButton(
                  key: const Key('retrieve'),
                  onPressed: c.unresolved
                      ? null
                      : () => c.retrieve(retrieveId.text),
                  child: const Text('Read this ID from server'),
                ),
                TextButton(
                  key: const Key('latest'),
                  onPressed: c.unresolved ? null : c.retrieveLatest,
                  child: const Text('Retrieve latest server attempt'),
                ),
                if (labTests) ...[
                  const Divider(height: 32),
                  const Text(
                    'DEVELOPMENT TEST HOOKS • injections are labeled; cloud rules stay intact.',
                  ),
                  DropdownButton<Fault>(
                    key: const Key('fault'),
                    isExpanded: true,
                    value: c.store.fault,
                    items: Fault.values
                        .map(
                          (f) =>
                              DropdownMenuItem(value: f, child: Text(f.name)),
                        )
                        .toList(),
                    onChanged: c.unresolved
                        ? null
                        : (f) => setState(() => c.store.fault = f!),
                  ),
                  SwitchListTile(
                    key: const Key('offline'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Development: disable Firestore network'),
                    value: offline,
                    onChanged: c.inFlight && !offline ? null : network,
                  ),
                  const Text(
                    'deniedVerification injects only the first read after a real commit. unavailable and quota inject before commit. delayedAcknowledgement delays observation of a real commit.',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
