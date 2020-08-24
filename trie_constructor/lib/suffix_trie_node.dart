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

import 'aksaras.dart';
import 'word_info.dart';

// The nodes that make up the suffix trie. Each one contains an aksara,
// the frequency of that aksara after its parent, its children,
// and whether it is at the bottom of the trie or not.
class TrieNode {
  String text = '';
  int frequency = 0;
  List<TrieNode> children = [];
  bool isLeaf = false;

  TrieNode.emptyNode();

  TrieNode(this.text, int freq) {
    frequency += freq;
  }

  // This goes through each aksara in the input word and adds it to the trie if
  // it does not already exist at the current part of the trie.
  // If the aksara already exists, the current words frequency is added to
  // the TrieNode containing the already-existing aksara.
  void addText(WordInfo input) {
    // If there are no remaining aksara to add, the current node is a leaf.
    if (input.aksaras.isEmpty) {
      if (children.isEmpty) {
        isLeaf = true;
      }
      return;
    } else {
      isLeaf = false;
    }
    var firstChar = input.aksaras[0];
    var remainingAksaras = input.aksaras.sublist(1);
    TrieNode newNode;
    if (contains(Aksaras([firstChar])) == null) {
      newNode = TrieNode(firstChar, input.frequency);
      children.add(newNode);
    } else {
      newNode = children.firstWhere((child) => child.text == firstChar);
      newNode.frequency += input.frequency;
    }
    newNode.addText(WordInfo(Aksaras(remainingAksaras), input.frequency));
    // A nodes children are sorted in order of how likely they are
    // to come directly after the current node.
    children.sort((a, b) => b.frequency.compareTo(a.frequency));
  }

  // Checks whether a given word is contained in the trie.
  TrieNode contains(Aksaras word) {
    TrieNode finalNode;
    if (word.isNotEmpty && children.isNotEmpty) {
      var firstAksara = word[0];
      var nextNode = children.firstWhere((child) => child.text == firstAksara,
          orElse: () => null);
      if (nextNode != null) {
        var remainingAksaras = Aksaras(word.sublist(1));
        if (remainingAksaras.isEmpty) {
          finalNode = nextNode;
        } else {
          finalNode = nextNode.contains(remainingAksaras);
        }
      }
    } else if (text.isEmpty && word.isEmpty) {
      finalNode = this;
    }
    return finalNode;
  }

  void getWords(List<Aksaras> words, List<String> word) {
    for (var child in children) {
      var tempWord = Aksaras(word + [child.text]);
      if (child.children.isEmpty) {
        words.add(tempWord);
      } else {
        child.getWords(words, tempWord);
      }
    }
  }

  // This prints the trie from the current node in a readable way. For example,
  // if the trie contained 'afd' with frequency 2, 'ef' with frequency 4 and
  //'abcd' with frequency 1, printing the root node would display:
  //(0) ->
  //         @(7) ->
  //                 e(4) ->
  //                         f(4)
  //                 a(3) ->
  //                         f(2) ->
  //                                 d(2)
  //                         b(1) ->
  //                                 c(1) ->
  //                                         d(1)
  //         f(6) ->
  //                 d(2)
  //         d(3)
  //         b(1) ->
  //                 c(1) ->
  //                         d(1)
  //         c(1) ->
  //                 d(1)

  void printNode({int offset = 0}) {
    var tabs = '\t' * offset;
    print('$tabs ${text}($frequency) ${children.isNotEmpty ? '->' : ''}');
    for (var child in children) {
      child.printNode(offset: offset + 1);
    }
  }
}
