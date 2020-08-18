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
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';

import 'suffix_trie_node.dart';
import 'suffix_trie.pb.dart' as pb;
import 'word_info.dart';

// A trie constructed using input words and all of their suffixes.
// Each node represents an aksara (grapheme cluster) and has a frequency which
// describes how often this aksara comes after its parent.
// The purpose of this suffix trie is to predict what aksaras come next after
// a given context.
class SuffixTrie {
  // Loads a previously constructed trie from its proto bytes.
  SuffixTrie(Uint8List protoBytes) {
    var storedTrie = pb.SuffixTrie.fromBuffer(protoBytes);
    rootNode = deserializeNode(storedTrie.rootNode);
    deserializeNodeChildren(rootNode, storedTrie.rootNode);
    allAksaras = findAllAksaras();
  }

  // Creates and stores a new trie created using the input words.
  SuffixTrie.fromWords(List<WordInfo> sourceWords, File trieFile) {
    addWords(sourceWords);
    serialiseSuffixTrie(trieFile);
  }

  SuffixTrie.emptyTrie();

  // Each word in the trie starts with this symbol.
  static const String wordStartingSymbol = '@';

  // A constant used to modify the prediction frequency based on the length
  // of the context that it follows.
  static const contextFactor = 16;

  // A constant used to modify the prediction frequency based on the number of
  // aksaras in the prediction.
  static const predictionFactor = -1.5;

  // A list of every existing aksara in the trie.
  List<String> allAksaras;

  // The string used to denote a previously unseen aksara.
  String unseenAksara = 'OOV';

  // This is an empty node symbolising the top/beginning of the trie.
  TrieNode rootNode = TrieNode.emptyNode();

  // The objects data is stored in a new file using a protocol buffer
  void serialiseSuffixTrie(File trieFile) async {
    // Creating suffix trie proto.
    var pbTrie = pb.SuffixTrie();
    // Constructing root node proto.
    var root = serializeNode(rootNode);
    // Adding root node's children to root node proto.
    serializeNodeChildren(root, rootNode);
    // Setting root of suffix trie proto to root node proto.
    pbTrie.rootNode = root;
    // Storing the suffix trie as bytes.
    trieFile.writeAsBytesSync(pbTrie.writeToBuffer());
  }

  void serializeNodeChildren(pb.SuffixTrie_TrieNode pbNode, TrieNode node) {
    if (node.children.isNotEmpty) {
      for (var child in node.children) {
        // Create a new proto node for each child.
        var pbChild = serializeNode(child);
        // Add the child's children to the new proto node.
        serializeNodeChildren(pbChild, child);
        // Add the new proto node to current proto node's list of children.
        pbNode.children.add(pbChild);
      }
    }
  }

  pb.SuffixTrie_TrieNode serializeNode(TrieNode current) {
    var node = pb.SuffixTrie_TrieNode();
    node.text = current.text;
    // The int is parsed as an Int64 as frequency numbers can be high.
    node.frequency = Int64(current.frequency);
    node.isLeaf = current.isLeaf;
    return node;
  }

  void deserializeNodeChildren(TrieNode node, pb.SuffixTrie_TrieNode pbNode) {
    if (pbNode.children.isNotEmpty) {
      for (var pbChild in pbNode.children) {
        // Create a new node for each proto child.
        var child = deserializeNode(pbChild);
        // Add the child's children to the new node.
        deserializeNodeChildren(child, pbChild);
        // Add the new node to the current node's list of children.
        node.children.add(child);
      }
    }
  }

  TrieNode deserializeNode(pb.SuffixTrie_TrieNode current) {
    var node = TrieNode.emptyNode();
    node.text = current.text;
    node.frequency = current.frequency.toInt();
    node.isLeaf = current.isLeaf;
    return node;
  }

  // For each WordInfo object (containing a word and a frequency), each suffix
  // of the word is added to the trie along with the word's frequency.
  void addWords(List<WordInfo> words) {
    if (words != null && words.isNotEmpty) {
      for (var word in words) {
        for (var i = 0; i < word.aksaras.length; i++) {
          rootNode.addText(WordInfo(word.aksaras.sublist(i), word.frequency));
        }
      }
    }
    allAksaras = findAllAksaras();
  }

  // Returns the frequency of the node / all of its children.
  int getTotalFrequency(TrieNode node) {
    var frequency = node.frequency;
    if (node == rootNode) {
      for (var child in rootNode.children) {
        frequency += child.frequency;
      }
    }
    return frequency;
  }

  // Checks whether the given context exists in the trie.
  bool contains(List<String> context) {
    return (rootNode.contains(context) != null);
  }

  // Given a context, returns how probable it is for each existing aksara to
  // follow the context. Adapted from the JavaScript implementation here
  // https://git.io/JJaGl . More information on the method itself can be
  // found in Sections 3 and 4 of this paper:
  // https://www.repository.cam.ac.uk/handle/1810/254106
  Map<String, double> getProbabilities(List<String> context) {
    // Kneser-Ney-esque smoothing parameters copied from Dasher.
    const knAlpha = 0.49;
    const knBeta = 0.77;

    // Initialise the probability estimates to 0.0.
    var probs = <String, double>{};
    for (var aksara in allAksaras) {
      probs[aksara] = 0.0;
    }

    // This runs through all of the symbols that follow the context and/or
    // suffixes of the context, and assigns them a probability.
    var totalMass = 1.0;
    var gamma = totalMass;
    var currentNode;
    var currentCtx = List<String>.from(context);
    // Finding the longest context that exists in the trie to use as context.
    while (currentNode == null) {
      currentNode = rootNode.contains(currentCtx);
      if (currentCtx.isNotEmpty) {
        currentCtx = currentCtx.sublist(1);
      } else {
        break;
      }
    }

    var hasProcessedRoot = false;
    // Iterates until we have backed up to the root of the trie.
    while (!hasProcessedRoot) {
      var totalFrequency = getTotalFrequency(currentNode);
      if (currentNode.children.isNotEmpty) {
        for (var child in currentNode.children) {
          var aksara = child.text;
          var p =
              gamma * (child.frequency - knBeta) / (totalFrequency + knAlpha);
          probs[aksara] += p;
          totalMass -= p;
        }
      }

      // Backing off to a shorter context unless already at trie root, in
      // which case the context is already empty.
      if (currentNode == rootNode || currentCtx.isEmpty) {
        hasProcessedRoot = true;
      } else {
        currentCtx = currentCtx.sublist(1);
        currentNode = rootNode.contains(currentCtx);
      }
      gamma = totalMass;
    }

    // Divide the remaining probability mass between all of the aksaras.
    var remainingMass = totalMass;
    var numAksaras = allAksaras.length;
    for (var aksara in allAksaras) {
      var p = remainingMass / numAksaras;
      probs[aksara] += p;
      totalMass -= p;
    }

    // Making sure that there is no probability mass remaining and the
    // probabilities of all of the aksaras add up to approximately 1.
    for (var aksara in allAksaras) {
      var p = totalMass / numAksaras;
      probs[aksara] += p;
      totalMass -= p;
      numAksaras--;
    }
    return probs;
  }

// Returns the most likely n aksaras to come after the context, according
// to the probabilistic language model.
  List<List<String>> getModelPredictions(
      List<String> context, int numPredictions) {
    var probs = getProbabilities(context);
    var sortedProbs = probs.keys.toList()
      ..sort((k1, k2) => probs[k2].compareTo(probs[k1]));
    var predictions = <List<String>>[];
    for (var i = 0;
        predictions.length < numPredictions && i < sortedProbs.length;
        i++) {
      if (sortedProbs[i] != WordInfo.wordStartingSymbol) {
        predictions.add([sortedProbs[i]]);
      }
    }
    return predictions;
  }

  // Gets every grapheme cluster in existence in the trie.
  List<String> findAllAksaras() {
    var allAksaras = <String>[];
    for (var child in rootNode.children) {
      if (!allAksaras.contains(child.text)) {
        allAksaras.add(child.text);
      }
    }
    // This represents an aksara that has not been seen before.
    allAksaras.add(unseenAksara);
    return allAksaras;
  }

  List<List<String>> getMostLikelyPredictions(
      List<String> context, int numPredictions) {
    var results = <WordInfo>[];
    for (var i = 1; i <= 4; i++) {
      results.addAll(findPredictions(context, numPredictions, i));
    }

    results.sort((a, b) => b.frequency.compareTo(a.frequency));
    var predictionWords = <List<String>>[];
    for (var j = 0; j < numPredictions; j++) {
      predictionWords.add(results[j].aksaras);
    }
    return predictionWords;
  }

  // For a given group (length of sequence of buttons), gets the top n most
  // frequent predictions for that group.
  List<WordInfo> findPredictions(
      List<String> context, int numPredictions, int predictionLength) {
    var predictions = <WordInfo>[];
    TrieNode contextNode;
    while (predictions.length < numPredictions) {
      contextNode = rootNode.contains(context);
      if (contextNode != null && !contextNode.isLeaf) {
        var results = <WordInfo>[];
        findAllPredictions(results, contextNode, [], predictionLength);
        results.sort((a, b) => b.frequency.compareTo(a.frequency));
        // Only keep the results that have not already been added to predictions
        for (var i = 0;
            i < results.length && predictions.length < numPredictions;
            i++) {
          var curr = results[i].aksaras.join();
          var isUsed = false;
          for (var j = 0; j < predictions.length && !isUsed; j++) {
            if (curr == predictions[j].aksaras.join()) {
              isUsed = true;
            }
          }
          if (!isUsed) {
            var modifiedPrediction = getModifiedPrediction(
                results[i], context.length, predictionLength);
            predictions.add(modifiedPrediction);
          }
        }
      }
      // If not enough predictions have been found (< rows), reduce the
      // context so that more possible predictions can be found.
      if (context.isNotEmpty) {
        context = context.sublist(1);
      } else {
        break;
      }
    }
    return predictions;
  }

  WordInfo getModifiedPrediction(
      WordInfo prediction, int contextLength, int predictionLength) {
    var newFrequency = (prediction.frequency *
            pow(contextLength + 1, contextFactor) *
            pow(predictionLength, predictionFactor))
        .round();
    return WordInfo(prediction.aksaras, newFrequency);
  }

  // Gets all possible predictions of length [group] that follow the context node.
  void findAllPredictions(List<WordInfo> results, TrieNode contextNode,
      List<String> currPrediction, int predictionLength) {
    for (var child in contextNode.children) {
      if (child.text != wordStartingSymbol) {
        if (currPrediction.length == (predictionLength - 1)) {
          results.add(WordInfo(currPrediction + [child.text], child.frequency));
        } else {
          findAllPredictions(
              results, child, currPrediction + [child.text], predictionLength);
        }
      }
    }
  }

  List<List<String>> constructAllWords() {
    var allWords = <List<String>>[];
    var startingNode = rootNode.children.first;
    startingNode.getWords(allWords, [startingNode.text]);
    return allWords;
  }
}
