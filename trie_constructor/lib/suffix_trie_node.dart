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

// The nodes that make up the suffix trie. Each one contains an aksara,
// the frequency of that aksara after its parent, its children,
// and whether it is at the bottom of the trie or not.
import 'word_info.dart';

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
    var remainingAksara = input.aksaras.sublist(1);
    TrieNode newNode;
    if (contains([firstChar]) == null) {
      newNode = TrieNode(firstChar, input.frequency);
      children.add(newNode);
    } else {
      newNode = children.firstWhere((child) => child.text == firstChar);
      newNode.frequency += input.frequency;
    }
    newNode.addText(WordInfo(remainingAksara, input.frequency));
    // A nodes children are sorted in order of how likely they are
    // to come directly after the current node.
    children.sort((a, b) => b.frequency.compareTo(a.frequency));
  }

  // Checks whether a given word is contained in the trie.
  TrieNode contains(List<String> word) {
    TrieNode finalNode;
    if (word.isNotEmpty && children.isNotEmpty) {
      var firstAksara = word[0];
      var nextNode = children.firstWhere((child) => child.text == firstAksara,
          orElse: () => null);
      if (nextNode != null) {
        var remainingAksara = word.sublist(1);
        if (remainingAksara.isEmpty) {
          finalNode = nextNode;
        } else {
          finalNode = nextNode.contains(remainingAksara);
        }
      }
    } else if (text.isEmpty && word.isEmpty) {
      finalNode = this;
    }
    return finalNode;
  }

  void getWords(List<List<String>> words, List<String> word) {
    for (var child in children) {
      var tempWord = word + [child.text];
      if (child.children.isEmpty) {
        words.add(tempWord);
      } else {
        child.getWords(words, tempWord);
      }
    }
  }

  @override
  String toString() {
    var leafMarker = isLeaf ? '#' : '';
    var nodeChildren = children.isNotEmpty ? children.toString() : '';
    var result = '$text$leafMarker :  $frequency $nodeChildren';
    return result;
  }
}
