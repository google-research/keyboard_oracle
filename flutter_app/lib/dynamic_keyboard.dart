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
    var patterns =
        _trie.getMostLikelyPredictions(contextWord, _numOfPredictions);
    // Sets the keyboard keys to be the most likely predictions found.
    for (var i = 0; i < _numOfPredictions; i++) {
      if (patterns.length > i) {
        keys.add(patterns[i]);
      } else {
        keys.add([]);
      }
    }
    setCharPredictions();
  }

  // Given the context, get the possible single 1-length characters that
  // could come immediately afterwards.
  void setCharPredictions() {
    var lastChar = contextWord.last[contextWord.last.length - 1];
    charPredictions = _charNeighbours[lastChar];
    if (charPredictions != null) {
      charPredictions.sort();
    }
  }

  // The text value displayed on the screen is modified according to the input.
  void processNewInput(List<String> input, int endOfList) {
    // If the input is not a letter (i.e. if it is a symbol or number).
    if (input.length == 1 && input.first == '←') {
      processBackSpace(endOfList);
    } else {
      // If the most recent input before this input was a character, we check
      // if it can be combined with the the first aksara of this input.
      // Otherwise, it is a grapheme cluster of its own.
      if (_inputIsCharacter) {
        var selectedText = displayedText.sublist(0, endOfList);
        if (selectedText.isNotEmpty) {
          var combination = selectedText.last + input.first;
          var canBeCombined = isValidAksara(combination);
          if (canBeCombined) {
            displayedText = selectedText.sublist(0, selectedText.length - 1) +
                [combination] +
                displayedText.sublist(endOfList);
            input = input.sublist(1);
          }
        }
      }
      if (input.isNotEmpty) {
        var newPart = displayedText.sublist(0, endOfList) + input;
        displayedText = newPart + displayedText.sublist(endOfList);
      }
    }
    _inputIsCharacter = false;
    setContextWord();
  }

  // Updates the current displayed text & removes the most recent
  // grapheme cluster.
  void processBackSpace(int endOfList) {
    var selectedText = displayedText.sublist(0, endOfList);
    if (selectedText.length > 0) {
      // Remove most recent grapheme cluster from selected text.
      var tempDisplayedText = selectedText.sublist(0, selectedText.length - 1);
      // Add the rest of the displayed text that follows, if it exists.
      if (displayedText.length > endOfList) {
        tempDisplayedText.addAll(displayedText.sublist(endOfList));
      }
      displayedText = tempDisplayedText;
    }
    setContextWord();
  }

  // Checks if a given character can be combined with the end of the text to
  // form a grapheme cluster. If so, they are combined. Otherwise, the character
  // is added as a separate grapheme cluster.
  void combineCharWithContext(String char, int endOfList) {
    _inputIsCharacter = false;
    var selectedText = displayedText.sublist(0, endOfList);
    if (selectedText.isNotEmpty) {
      // Combining the last aksara in the text with the new character.
      var combination = selectedText.last + char;
      var canBeCombined = isValidAksara(combination);
      // If the combination is a valid aksara, the last aksara in the selected
      // text is set to be this combination (i.e. the character is added to the
      // last aksara).
      if (canBeCombined) {
        displayedText = selectedText.sublist(0, selectedText.length - 1) +
            [combination] +
            displayedText.sublist(endOfList);
      } else {
        _inputIsCharacter = true;
        var newPart = selectedText + [char];
        displayedText = newPart + displayedText.sublist(endOfList);
      }
    } else {
      var isAksara = isValidAksara(char);
      if (!isAksara) {
        _inputIsCharacter = true;
      }
      displayedText = [char] + displayedText.sublist(endOfList);
    }
    setContextWord();
  }

  bool isValidAksara(String combination) {
    var isValid = false;
    // Checking if this combination matches any existing aksara.
    for (var aksara in _trie.allAksaras) {
      if (combination == aksara) {
        isValid = true;
        break;
      }
    }
    return isValid;
  }

// The context word is set to be the  last word/segment in the displayed text.
  void setContextWord() {
    contextWord = [wordStartingSymbol];
    if (displayedText.isNotEmpty) {
      var enterIndex = displayedText.lastIndexOf('\n');
      var spaceIndex = displayedText.lastIndexOf(' ');
      var lastWhitespaceIndex =
          enterIndex > spaceIndex ? enterIndex : spaceIndex;
      if (lastWhitespaceIndex >= 0) {
        contextWord += displayedText.sublist(lastWhitespaceIndex + 1);
      } else {
        contextWord += displayedText;
      }
    }
  }
}
