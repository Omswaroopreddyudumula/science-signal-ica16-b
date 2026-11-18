import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

String decodeComponentStrict(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    throw const FormatException('Invalid percent encoding in question data.');
  }
}

class Question {
  const Question(this.encoded, this.text, this.correct);
  final String encoded, text, correct;
  factory Question.parse(Object? raw) {
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('Invalid question.');
    }
    String decode(String key) {
      final value = raw[key];
      if (value is! String) throw FormatException('Missing $key.');
      return decodeComponentStrict(value);
    }

    final category = decode('category'),
        text = decode('question'),
        correct = decode('correct_answer');
    final wrong = raw['incorrect_answers'];
    if (category != 'Science & Nature' ||
        raw['difficulty'] != 'medium' ||
        raw['type'] != 'boolean' ||
        text.trim().isEmpty ||
        wrong is! List ||
        wrong.length != 1 ||
        wrong.single is! String) {
      throw const FormatException(
        'Expected five medium Science & Nature true/false questions.',
      );
    }
    final incorrect = decodeComponentStrict(wrong.single as String);
    if ({correct, incorrect}.length != 2 ||
        !{'True', 'False'}.containsAll({correct, incorrect})) {
      throw const FormatException('Invalid answer values.');
    }
    return Question(raw['question'] as String, text, correct);
  }
}

List<Question> parseQuestions(String body) {
  final data = jsonDecode(body);
  if (data is! Map ||
      data['response_code'] != 0 ||
      data['results'] is! List ||
      (data['results'] as List).length != 5) {
    throw const FormatException(
      'The API did not return exactly five valid questions.',
    );
  }
  return (data['results'] as List).map(Question.parse).toList(growable: false);
}

class QuizApi {
  QuizApi({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;
  DateTime? lastRequest;
  static final uri = Uri.parse(
    'https://opentdb.com/api.php?amount=5&category=17&difficulty=medium&type=boolean&encode=url3986',
  );
  int get cooldown {
    final last = lastRequest;
    if (last == null) return 0;
    final ms = 5000 - DateTime.now().difference(last).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  Future<List<Question>> fetch() async {
    if (cooldown > 0) {
      throw StateError('Wait $cooldown seconds before retrying.');
    }
    lastRequest = DateTime.now();
    final response = await client.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw StateError(
        'Question service returned HTTP ${response.statusCode}. Retry after five seconds.',
      );
    }
    return parseQuestions(response.body);
  }

  void close() => client.close();
}
