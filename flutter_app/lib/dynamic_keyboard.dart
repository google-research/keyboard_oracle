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

import 'package:flutter_emoji/flutter_emoji.dart';
import 'package:trie_constructor/aksaras.dart';
import 'package:trie_constructor/suffix_trie.dart';

class DynamicKeyboard {
  DynamicKeyboard(Uint8List protoBytes, this._numOfAksaras) {
    _trie = SuffixTrie(protoBytes);
    fillKeyboard();
  }

  static const String wordStartingSymbol = '@';

  // The text displayed on the screen currently.
  Aksaras displayedText = Aksaras([]);

  // Keys created from previous entered contexts.
  Map<String, List<Aksaras>> _cachedKeys = {};

  // The context used to determine what keys to display dynamically.
  Aksaras contextWord = Aksaras([wordStartingSymbol]);

  // A list of length-1 single characters displayed at bottom of keyboard.
  List<String> charPredictions = [];

  // The language model used to predict what should be displayed on the
  // keyboard.
  SuffixTrie _trie;

  // The number of aksara predictions generated for the keyboard.
  int _numOfAksaras;

  // The keys, as grapheme clusters, displayed on the buttons in the grid.
  List<Aksaras> keys = [];

  void setNumOfAksaras(int newNumOfAksaras) {
    if (_numOfAksaras != newNumOfAksaras) {
      _numOfAksaras = newNumOfAksaras;
      _cachedKeys.clear();
    }
  }

  void setPValue(double pValue) {
    if (_trie.predictionFactor != pValue) {
      _trie.predictionFactor = pValue;
      _trie.cachedPredictions.clear();
      _cachedKeys.clear();
    }
  }

  void setCValue(double cValue) {
    if (_trie.contextFactor != cValue) {
      _trie.contextFactor = cValue;
      _trie.cachedPredictions.clear();
      _cachedKeys.clear();
    }
  }

  void reset(int numOfAksaras) {
    setNumOfAksaras(numOfAksaras);
    displayedText.clear();
    setContextWord();
  }

  // Initialises keyboard values to their base values and fills the keys
  // in dynamically.
  void fillKeyboard() {
    var contextAsString = contextWord.join();
    // If keys have already been created for this context
    if (_cachedKeys.containsKey(contextAsString)) {
      keys = _cachedKeys[contextAsString];
    } else {
      // Sets the keyboard keys to be the most likely predictions found according
      // to the context.
      keys = _trie.getMostLikelyPredictions(contextWord, _numOfAksaras);
      _cachedKeys[contextAsString] = keys;
    }
  }

  // The text value displayed on the screen is modified according to the input.
  void processNewInput(Aksaras input, int endOfList) {
    // If the input is not a letter (i.e. if it is a symbol or number).
    if (input.length == 1 && input.first == '←') {
      processBackSpace(endOfList);
    } else if (input.isNotEmpty) {
      var newPart = displayedText.sublist(0, endOfList) + input;
      displayedText = Aksaras(newPart + displayedText.sublist(endOfList));
    }
    setContextWord();
  }

  // Updates the current displayed text & removes the most recent
  // grapheme cluster.
  void processBackSpace(int endOfList) {
    var selectedText = displayedText.sublist(0, endOfList);
    if (selectedText.length > 0) {
      // Remove most recent grapheme cluster from selected text.
      var tempDisplayedText =
          Aksaras(selectedText.sublist(0, selectedText.length - 1));
      // Add the rest of the displayed text that follows, if it exists.
      if (displayedText.length > endOfList) {
        tempDisplayedText.addAll(displayedText.sublist(endOfList));
      }
      displayedText = tempDisplayedText;
    }
  }

// The context word is set to be the  last word/segment in the displayed text.
  void setContextWord() {
    contextWord = Aksaras([wordStartingSymbol]);
    if (displayedText.isNotEmpty) {
      var startOfContext = -1;
      for (var i = displayedText.length - 1; i >= 0; i--) {
        if (!_trie.allAksaras.contains(displayedText[i]) ||
            displayedText[i] == '\n' ||
            displayedText[i] == ' ') {
          startOfContext = i;
          break;
        }
      }
      if (startOfContext >= 0) {
        contextWord.addAll(displayedText.sublist(startOfContext + 1));
      } else {
        contextWord.addAll(displayedText);
      }
    }
    fillKeyboard();
  }

  // Takes new text input and separates it into aksaras/emojis/non-aksaras in
  // order to appropriately add it to the context and text.
  int addNewText(String text, int cursorIndex) {
    var parser = EmojiParser();
    var newAksaras = <String>[];
    var start = 0;
    var end = text.length;
    if (cursorIndex > 0) {
      // Adding the last aksara before the cursor in case it can be combined
      // with the beginning of the new text to form an aksara.
      text = displayedText[cursorIndex - 1] + text;
    }
    // Continues until every character in the string has been processed.
    while (start < text.length) {
      // Tests possible combinations of aksaras, starting from the longest
      // possible combination and reducing each time until a match is found.
      while (end > start) {
        // If there is only one character in the combination, the combination
        // forms an aksaras, or the combination forms an emoji.
        if (end - start == 1 ||
            _trie.allAksaras.contains(text.substring(start, end)) ||
            parser.getEmoji(text.substring(start, end)) != Emoji.None) {
          var aksara = text.substring(start, end);
          newAksaras.add(aksara);
          start += aksara.length;
        } else {
          end--;
        }
      }
      end = text.length;
    }
    // The new 'aksaras' are added to where the cursor previously was before
    // the new changes.
    displayedText = Aksaras(
        displayedText.sublist(0, cursorIndex - (cursorIndex > 0 ? 1 : 0)) +
            newAksaras +
            displayedText.sublist(cursorIndex));
    cursorIndex = displayedText.sublist(0, cursorIndex).join().length +
        newAksaras.join().length;
    // The context is updated using the new displayed text.
    setContextWord();
    return cursorIndex;
  }
}
