/*
Copyright 2020 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'dart:math';

import 'package:trie_constructor/aksaras.dart';
import 'package:trie_constructor/src/word_info.dart';
import 'package:trie_constructor/suffix_trie.dart';

import 'package:test/test.dart';

// The main suffix trie methods used by Keyboard Oracle are tested here.
void main() {
  var trieWords = [
    WordInfo(Aksaras(['@', 'e', 'f']), 4),
    WordInfo(Aksaras(['@', 'a', 'b', 'c', 'd']), 1),
    WordInfo(Aksaras(['@', 'a', 'f', 'd']), 2)
  ];
  var trie = SuffixTrie.fromWords(trieWords);
  // Setting the factor that changes frequencies/predictions based on prediction
  // length to 0 so that it has no effect on the predictions, which results in
  // more predictable results for the test.
  trie.predictionWeight = 0;
  getMostLikelyPredictionsTest(trie);
  findPredictionsTest(trie);
  findAllPredictionsTest(trie);
}

// Gets the most likely n predictions according to the trie's frequency-based
// algorithm.
void getMostLikelyPredictionsTest(SuffixTrie trie) {
  group('Testing most likely predictions for context =', () {
    test('"@"', () {
      var results = trie.getMostLikelyPredictions(Aksaras(['@']), 11);
      var expected = 'e';
      expect(results[0].join(), equals(expected));
      expected = 'ef';
      expect(results[1].join(), equals(expected));
      expected = 'a';
      expect(results[2].join(), equals(expected));
      expected = 'af';
      expect(results[3].join(), equals(expected));
    });

    test('"@a"', () {
      var results = trie.getMostLikelyPredictions(Aksaras(['@', 'a']), 7);
      var expected = 'f';
      expect(results[0].join(), equals(expected));
      expected = 'fd';
      expect(results[1].join(), equals(expected));
      expected = 'b';
      expect(results[2].join(), equals(expected));
    });

    test('[empty]', () {
      var results = trie.getMostLikelyPredictions(Aksaras([]), 4);
      var expected = 'f';
      expect(results[0].join(), equals(expected));
      expected = 'd';
      expect(results[1].join(), equals(expected));
    });
  });
}

// Returns all (up to maxNumPredictions) predictions of a certain length that
// follow a given context in the trie, with each predictions's frequency
// modified based on the trie's frequency-based algorithm.
void findPredictionsTest(SuffixTrie trie) {
  var results = trie.findPredictions(Aksaras(['@']), 1);
  test(
      'Testing findPredictions results for context = ["@"] and prediction'
      'length = 1', () {
    var expected =
        (3 * pow(2, trie.contextWeight) * pow(1, trie.predictionWeight))
            .round();
    var result = results.firstWhere((element) => element.aksaras.join() == 'a');
    expect(result.frequency, equals(expected));
    expected = (4 * pow(2, trie.contextWeight) * pow(1, trie.predictionWeight))
        .round();
    result = results.firstWhere((element) => element.aksaras.join() == 'e');
    expect(result.frequency, equals(expected));
  });
}

// Returns every prediction of a certain length that follows a given context.
void findAllPredictionsTest(SuffixTrie trie) {
  var contextNode = trie.rootNode.contains(Aksaras(['@']));
  group('Testing find all predictions results for context = ["@"]', () {
    test('with prediction length = 1', () {
      var results = <WordInfo>[];
      trie.findAllPredictions(results, contextNode, Aksaras([]), 1);
      expect(2, equals(results.length));
    });
    test('with prediction length = 2', () {
      var results = <WordInfo>[];
      trie.findAllPredictions(results, contextNode, Aksaras([]), 2);
      expect(3, equals(results.length));
    });
    test('with prediction length = 3', () {
      var results = <WordInfo>[];
      trie.findAllPredictions(results, contextNode, Aksaras([]), 3);
      expect(2, equals(results.length));
    });
  });
}
