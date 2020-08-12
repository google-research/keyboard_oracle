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
library keyboard_oracle;

import 'dart:typed_data';

import 'package:trie_constructor/suffix_trie.dart';

class DynamicKeyboard {
  DynamicKeyboard(Uint8List protoBytes, this._numOfPredictions) {
    _trie = SuffixTrie(protoBytes);
    mapCharNeighbours();
    fillKeyboard();
  }

  // Initialises keyboard values to their base values and fills the keys
  // in dynamically.
  void fillKeyboard() {
    var contextAsString = contextWord.join();
    // If keys have already been created for this context
    if (_cachedKeys.containsKey(contextAsString)) {
      keys = _cachedKeys[contextAsString];
    }
    // Otherwise dynamically create keys and cache them.
    else {
      dynamicallyChangeButtons();
      _cachedKeys[contextAsString] = keys;
    }
  }

  static const String wordStartingSymbol = '@';

  // The text displayed on the screen currently.
  List<String> displayedText = [];

  // A map that, for each character, gives a list
  // of what immediately succeeds it.
  Map<String, List<String>> _charNeighbours = {};

  // Keys created from previous entered contexts.
  Map<String, List<List<String>>> _cachedKeys = {};

  // The context used to determine what keys to display dynamically.
  List<String> contextWord = [wordStartingSymbol];

  // A list of length-1 single characters displayed at bottom of keyboard.
  List<String> charPredictions = [];

  // If the user has clicked one of the character buttons rather than a
  // pattern or grapheme cluster, it needs to be handled differently.
  bool _inputIsCharacter = false;

  // Inputs that should be treated differently to regular letters/characters.
  final List<String> _specialSymbols = [' ', '⏎', '←'];

  // The language model used to predict what should be displayed on the
  // keyboard.
  SuffixTrie _trie;

  // The number of predictions generated for the keyboard.
  int _numOfPredictions;

  // The keys, as grapheme clusters, displayed on the buttons in the grid.
  List<List<String>> keys = [];

  void setNumOfPredictions(int newNumOfPredictions) {
    if (_numOfPredictions != newNumOfPredictions) {
      _numOfPredictions = newNumOfPredictions;
      _cachedKeys.clear();
    }
  }

  // Maps each existing character to a list of characters that can
  // come after it.
  void mapCharNeighbours() {
    var _sourceWords = _trie.constructAllWords();
    //for each word
    for (var word in _sourceWords) {
      // for each grapheme cluster in word
      for (var i = 0; i < word.length; i++) {
        // for each character in the grapheme cluster
        for (var j = 0; j < word[i].length; j++) {
          var currentChar = word[i][j];
          var nextChar = '';
          if (j != word[i].length - 1) {
            nextChar = word[i][j + 1];
          } else if (i != word.length - 1) {
            // If it is the last character in a grapheme cluster, the next
            // character will be the first character in the next
            // grapheme cluster.
            nextChar = word[i + 1][0];
          }
          // If the character is not in the map yet, it is added.
          if (!_charNeighbours.containsKey(currentChar)) {
            if (nextChar.isNotEmpty) {
              _charNeighbours[currentChar] = [nextChar];
            } else {
              _charNeighbours[currentChar] = [];
            }
          }
          // Only add the next character if it is not in the
          // current list already.
          else if (nextChar.isNotEmpty &&
              !_charNeighbours[currentChar].contains(nextChar)) {
            _charNeighbours[currentChar].add(nextChar);
          }
        }
      }
    }
  }

  // Changes the list of keyboard buttons according to the
  // context/context-change.
  void dynamicallyChangeButtons() {
    keys = <List<String>>[];
    var patterns = <List<String>>[];
    // 10 predictions of lengths 4, 3, and 2 are always generated.
    var groups = {4: 10, 3: 10, 2: 10};
    // If the user has requested more than the minimum number of predictions,
    // single aksara predictions are also generated.
    if (_numOfPredictions > 30) {
      groups[1] = _numOfPredictions - 30;
    }
    // For each group (sequences of length 1-4), find most likely patterns.
    for (var group in groups.keys) {
      patterns = _trie.findPredictedPatterns(contextWord, groups[group], group);
      fillKeysWithPatterns(patterns, groups[group]);
    }
    setCharPredictions();
  }

  // Given the context, get the possible single 1-length characters that
  // could come immediately afterwards.
  void setCharPredictions() {
    var lastChar = contextWord.last[contextWord.last.length - 1];
    if (_inputIsCharacter) {
      lastChar = contextWord.last.substring(0, contextWord.last.length - 2);
    }
    charPredictions = _charNeighbours[lastChar];
    if (charPredictions != null) {
      charPredictions.sort();
    }
  }

  // Sets the keyboard keys (list) to be the grapheme clusters from
  // the found patterns.
  void fillKeysWithPatterns(List<List<String>> patterns, int numPatsNeeded) {
    // Do for each pattern.
    for (var row = 0; row < numPatsNeeded; row++) {
      List<String> pattern;
      if (patterns.length > row) {
        pattern = patterns[row];
        keys.add(pattern);
      } else {
        keys.add([]);
      }
    }
  }

  // The text value displayed on the screen and the current context are changed
  // depending on what the input is.
  void processNewInput(List<String> input) {
    // If the input is not a letter (i.e. if it is a symbol or number).
    if (input.length == 1 && _specialSymbols.contains(input.first)) {
      var curr = input.first;
      if (curr == '←') {
        processBackSpace();
      } else {
        // Resets context.
        contextWord = [wordStartingSymbol];
        if (curr == '⏎') {
          displayedText.add('\n');
        } else {
          displayedText.add(curr);
        }
      }
    } else {
      // If the most recent input before this input was a character, we check
      // if it can be combined with the beginning of this input. Otherwise, it
      // is a grapheme cluster of its own.
      if (_inputIsCharacter) {
        var canBeCombined = false;
        var lastAksara = contextWord.last[0];
        var combination = lastAksara + input.first;
        for (var aksara in _trie.allAksaras) {
          if (combination == aksara) {
            canBeCombined = true;
            break;
          }
        }
        if (canBeCombined) {
          contextWord.last = combination;
          displayedText.last = combination;
          input = input.sublist(1);
        } else {
          contextWord.last = lastAksara;
        }
      }
      if (input.isNotEmpty) {
        contextWord += input;
        displayedText += input;
      }
    }
    _inputIsCharacter = false;
  }

  // Updates the current context/text & removes the most recent
  // grapheme cluster.
  void processBackSpace() {
    if (displayedText.length > 0) {
      // Remove most recent grapheme cluster from text.
      displayedText = displayedText.sublist(0, displayedText.length - 1);
      if (contextWord.length > 1) {
        contextWord = contextWord.sublist(0, contextWord.length - 1);
      }
      // If context contains no letters but current text is not empty.
      else if (displayedText.isNotEmpty) {
        var lastChar = displayedText.last;
        // If currentText contains more than one word, set context to be the
        // most recent word.
        if (lastChar != ' ' && lastChar != '⏎' && displayedText.contains(' ')) {
          var lastWordPos = displayedText.lastIndexOf(' ') + 1;
          contextWord =
              [wordStartingSymbol] + displayedText.sublist(lastWordPos);
        } else {
          contextWord = [wordStartingSymbol] + displayedText;
        }
      } else {
        contextWord = [wordStartingSymbol];
      }
    }
  }

  // Checks if a given character can be combined with the end of the context to
  // form a grapheme cluster. If so, they are combined. Otherwise, the character
  // is added as a separate grapheme cluster.
  void combineCharWithContext(String char) {
    if (_inputIsCharacter) {
      contextWord.last = contextWord.last[0];
      _inputIsCharacter = false;
    }
    var canBeCombined = false;
    var combination = contextWord.last + char;
    for (var aksara in _trie.allAksaras) {
      if (combination == aksara) {
        canBeCombined = true;
        break;
      }
    }
    if (canBeCombined) {
      contextWord.last = combination;
      displayedText.last = combination;
    } else {
      _inputIsCharacter = true;
      var charInput = char + '.*';
      contextWord.add(charInput);
      displayedText.add(char);
    }
  }
}
