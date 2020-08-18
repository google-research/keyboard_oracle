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

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:trie_constructor/word_info.dart';
import 'package:trie_constructor/suffix_trie.dart';

import 'trie_test.dart';

void main(List<String> args) {
  var parser = ArgParser();

  // If needed, the user can choose their own input and output files.
  parser.addOption('inputFile', defaultsTo: 'deva_examples.txt');
  parser.addOption('outputFile', defaultsTo: 'deva_trie.bin');
  // If set, the trie is loaded from a binary file rather than constructed when
  // tests are run. An input text file is still needed in order to load the
  // set of test words.
  parser.addOption('trieFile', defaultsTo: null);
  // If set, tests are run on the generated trie.
  parser.addFlag('isTest', defaultsTo: false);
  // If set, the more time-consuming 'number of clicks per aksara' test is run.
  parser.addFlag('testClicks', defaultsTo: false);
  var results = parser.parse(args);

  var file = File(results['inputFile']);
  var content = file.readAsStringSync();
  var ls = LineSplitter();
  var lines = ls.convert(content);
  var sourceWords = <WordInfo>[];
  // For each line in the text file, a WordInfo object is constructed.
  for (var i = 0; i < lines.length; i++) {
    var curr = WordInfo.fromString(lines[i]);
    sourceWords.add(curr);
  }

  var newFile = File(results['outputFile']);

  // If the isTest command line flag is test, language model tests are run.
  if (results['isTest']) {
    runAllTests(
        sourceWords, newFile, results['testClicks'], results['trieFile']);
  } else {
    // A suffix trie is created using the source words and stored in a new file.
    SuffixTrie.fromWords(sourceWords, newFile);
  }
}
