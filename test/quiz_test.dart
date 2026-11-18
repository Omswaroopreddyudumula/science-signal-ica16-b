import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:science_signal_16/quiz.dart';

Map<String, dynamic> valid() => {
  'response_code': 0,
  'results': List.generate(
    5,
    (i) => {
      'category': 'Science%20%26%20Nature',
      'difficulty': 'medium',
      'type': 'boolean',
      'question': 'Earth%20orbits%20the%20Sun.',
      'correct_answer': 'True',
      'incorrect_answers': ['False'],
    },
  ),
};
void main() {
  test('strict endpoint decoding and invalid cases', () {
    final data = valid();
    expect(
      parseQuestions(jsonEncode(data)).first.text,
      'Earth orbits the Sun.',
    );
    for (final mutate in <void Function(Map<String, dynamic>)>[
      (d) => d['response_code'] = 1,
      (d) => (d['results'] as List).removeLast(),
      (d) => d['results'][0]['question'] = 'bad%ZZ',
      (d) => d['results'][0]['correct_answer'] = 'Maybe',
      (d) => d['results'][0]['category'] = 'History',
      (d) => d['results'][0]['difficulty'] = 'easy',
      (d) => d['results'][0]['type'] = 'multiple',
      (d) => d['results'][0]['incorrect_answers'] = ['True'],
    ]) {
      final sample = valid();
      mutate(sample);
      expect(() => parseQuestions(jsonEncode(sample)), throwsFormatException);
    }
  });
}
