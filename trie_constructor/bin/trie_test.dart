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

import 'dart:io';
import 'dart:math';

import 'package:trie_constructor/word_info.dart';
import 'package:trie_constructor/suffix_trie.dart';

const defaultNumPredictions = 40;
const defaultTestSize = 5000;

// If set via its command line argument, the quality of this language model's
// predictions on its training data is measured using keyboard coverage, entropy
// and perplexity.
void runAllTests(List<WordInfo> sourceWords, File testOutput) {
  var testWords = <WordInfo>[];
  var trainingWords = <WordInfo>[];
  var testSize = defaultTestSize;
  // If the input data is too small for the test data to be 5000 lines long,
  // the size is set to be a tenth of the input data set's size.
  if (testSize > sourceWords.length / 10) {
    testSize = (sourceWords.length / 10).round();
  }
  // Every tenth word in the data set is added to the test set.
  for (var i = 0; i < testSize * 10; i++) {
    if (i % 10 == 0) {
      testWords.add(sourceWords[i]);
    } else {
      trainingWords.add((sourceWords[i]));
    }
  }
  // Any remaining words are added to the training set.
  trainingWords.addAll(sourceWords.sublist(testSize * 10));

  var trie = SuffixTrie.fromWords(trainingWords, testOutput);
  var frequencyModelAccuracy =
      calculateKeyboardAccuracy(trie, testWords, false);
  print('Frequency model keyboard coverage: $frequencyModelAccuracy');
  var probabilisticModelAccuracy =
      calculateKeyboardAccuracy(trie, testWords, true);
  print('Probabilistic model keyboard coverage: $probabilisticModelAccuracy');

  var entropy = calculateEntropy(trie, testWords);
  print('Entropy on test data: $entropy');
  var perplexity = calculatePerplexity(entropy);
  print('Perplexity on test data: $perplexity');
}

// Calculates the entropy of the language model. This can be seen as a measure
// of the model's uncertaintly which means the lower it is the better.
double calculateEntropy(SuffixTrie trie, List<WordInfo> words) {
  var log2Prob = 0.0;
  var numAksarasTested = 0;
  for (var word in words) {
    var context = [''];
    for (var aksara in word.aksaras) {
      var probs = trie.getProbabilities(context);
      var p = probs[aksara];
      p ??= probs[trie.unseenAksara];
      log2Prob += log(p) / ln2;
      context.add(aksara);
    }
    numAksarasTested += word.aksaras.length;
  }
  var entropy = -log2Prob / numAksarasTested;
  return entropy;
}

// Calculates the perplexity of the language model, which is 2^(entropy).
double calculatePerplexity(double entropy) {
  var perplexity = pow(2, entropy);
  return perplexity;
}

// Calculates the accuracy/coverage of single-aksara keyboard predictions.
// This test returns how likely it is that the aksara a user wants to type next
// is displayed on the keyboard. The percentage returned is weighted according
// to the frequency of the test words.
double calculateKeyboardAccuracy(
    SuffixTrie trie, List<WordInfo> words, bool isProbabilisticModel) {
  var modelScore = 0;
  var maxScore = 0;
  for (var word in words) {
    var context = ['@'];
    for (var aksara in word.aksaras) {
      if (aksara != WordInfo.wordStartingSymbol) {
        maxScore += word.frequency;
        var predictions = <List<String>>[];
        if (isProbabilisticModel) {
          predictions =
              trie.getModelPredictions(context, defaultNumPredictions);
        } else {
          predictions =
              trie.findPredictedPatterns(context, defaultNumPredictions, 1);
        }
        for (var prediction in predictions) {
          if (prediction.join() == aksara) {
            modelScore += word.frequency;
            break;
          }
        }
        context.add(aksara);
      }
    }
  }
  return modelScore / maxScore;
}
