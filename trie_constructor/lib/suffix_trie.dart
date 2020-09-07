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

import 'src/cached_pair.dart';
import 'src/suffix_trie_node.dart';
import 'suffix_trie.pb.dart' as pb;
import 'src/word_info.dart';
import 'aksaras.dart';

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
  SuffixTrie.fromWords(List<WordInfo> sourceWords) {
    addWords(sourceWords);
  }

  SuffixTrie.serialiseTrie(List<WordInfo> sourceWords, File trieFile) {
    addWords(sourceWords);
    serialiseSuffixTrie(trieFile);
  }

  SuffixTrie.emptyTrie();

  // Each word in the trie starts with this symbol.
  static const String wordStartingSymbol = '@';

  // A constant used to modify the prediction frequency based on the length
  // of the context that it follows.
  double contextFactor = 16;

  // A constant used to modify the prediction frequency based on the number of
  // aksaras in the prediction.
  double predictionFactor = -5;

  static const numPredictionLengths = 4;

  static const maxNumPredictions = 160;

  // The string used to denote a previously unseen aksara.
  static const unseenAksara = 'OOV';

  // A list of every existing aksara in the trie.
  Aksaras allAksaras;

  // This is an empty node symbolising the top/beginning of the trie.
  TrieNode rootNode = TrieNode.emptyNode();

  Map<CachedPair, List<WordInfo>> cachedPredictions = {};

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
  // For example, if adding the word @ABCD (@ is the word starting symbol), the
  // suffixes we would add are @ABCD, BCD, CD, D (Reasons for omitting ABCD are
  // outlined below). This would result in a trie with a root which has @, B,
  // C, D as its children.
  void addWords(List<WordInfo> words) {
    if (words != null && words.isNotEmpty) {
      for (var word in words) {
        for (var i = 0; i < word.aksaras.length; i++) {
          // We do not add the suffix starting with the word's first aksara
          // (i=0 is the wordStartingSymbol) as we want to differentiate
          // between aksaras that appear at the beginning and middle of a word.
          // Aksaras that appear at the beginning are often particular to that
          // context and having them exist in the suffix trie in non-beginning
          // contexts could be inaccurate.
          if (i != 1) {
            rootNode.addText(
                WordInfo(Aksaras(word.aksaras.sublist(i)), word.frequency));
          }
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
  bool contains(Aksaras context) {
    return (rootNode.contains(context) != null);
  }

  void printContextTrie(Aksaras context) {
    var contextNode = rootNode.contains(context);
    if (contextNode != null) {
      contextNode.printNode();
    } else {
      print('This context does not exist in the trie.');
    }
  }

  // Given a context, returns how probable it is for each existing aksara to
  // follow the context. Adapted from the JavaScript implementation here
  // https://git.io/JJaGl . More information on the method itself can be
  // found in Sections 3 and 4 of this paper:
  // https://www.repository.cam.ac.uk/handle/1810/254106
  Map<String, double> getProbabilities(Aksaras context) {
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
      currentNode = rootNode.contains(Aksaras(currentCtx));
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
        currentNode = rootNode.contains(Aksaras(currentCtx));
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
  List<Aksaras> getModelPredictions(Aksaras context, int numPredictions) {
    var probs = getProbabilities(context);
    var sortedProbs = probs.keys.toList()
      ..sort((k1, k2) => probs[k2].compareTo(probs[k1]));
    var predictions = <Aksaras>[];
    for (var i = 0;
        predictions.length < numPredictions && i < sortedProbs.length;
        i++) {
      if (sortedProbs[i] != WordInfo.wordStartingSymbol) {
        predictions.add(Aksaras([sortedProbs[i]]));
      }
    }
    return predictions;
  }

  // Gets every grapheme cluster in existence in the trie.
  Aksaras findAllAksaras() {
    var allAksaras = Aksaras([]);
    var possibleAksaras =
        rootNode.children + rootNode.contains(Aksaras(['@'])).children;
    for (var node in possibleAksaras) {
      if (!allAksaras.contains(node.text)) {
        allAksaras.add(node.text);
      }
    }
    // This represents an aksara that has not been seen before.
    allAksaras.add(unseenAksara);
    return allAksaras;
  }

  List<Aksaras> getMostLikelyPredictions(Aksaras context, int numAksaras) {
    var contexts = <Aksaras>[];
    // The context is reduced each iteration so that more possible predictions
    // can be found. If the original context was @ABCD, the contexts we would
    // try are @ABCD, ABCD, BCD, CD, D, [] (@ is the word starting symbol).
    if (context.length == 1) {
      contexts.add(context);
    } else {
      for (var i = 0; i <= context.length; i++) {
        contexts.add(Aksaras(context.sublist(i)));
      }
    }
    var results = <WordInfo>[];
    // Get predictions for each prediction length and context.
    for (var i = 1; i <= numPredictionLengths; i++) {
      var tempResults = <WordInfo>[];
      for (var currCtx in contexts) {
        tempResults.addAll(findPredictions(currCtx, i));
      }
      // Remove duplicates from the temp results (results of the same length
      // from multiple different contexts.
      results.addAll(removeDuplicates(tempResults));
    }
    // Get the top predictions in terms of frequency.
    results.sort((a, b) => b.frequency.compareTo(a.frequency));
    var predictionWords = <Aksaras>[];
    var aksarasUsed = 0;
    var hasSpace = true;
    for (var j = 0; hasSpace; j++) {
      if (aksarasUsed + results[j].aksaras.length + 1 <= numAksaras) {
        predictionWords.add(results[j].aksaras);
        aksarasUsed += results[j].aksaras.length + 1;
      } else {
        hasSpace = false;
      }
    }
    return predictionWords;
  }

  // For a given group (length of sequence of buttons), gets the top n most
  // frequent predictions for that group.
  List<WordInfo> findPredictions(Aksaras context, int predictionLength) {
    if (cachedPredictions[CachedPair(predictionLength, context.join())] !=
        null) {
      return cachedPredictions[CachedPair(predictionLength, context.join())];
    }
    var predictions = <WordInfo>[];
    var contextNode = rootNode.contains(context);
    // If the context node has any children.
    if (contextNode != null && !contextNode.isLeaf) {
      var results = <WordInfo>[];
      // Add every possible predictionLength prediction that follows the context
      // node to our results.
      findAllPredictions(results, contextNode, Aksaras([]), predictionLength);
      // Only the top [maxNumPredictions] results are needed.
      if (results.length > maxNumPredictions) {
        results.sort((a, b) => b.frequency.compareTo(a.frequency));
        results = results.sublist(0, maxNumPredictions);
      }
      // Modify each result with its updated frequency based on context length
      // and prediction length.
      for (var result in results) {
        predictions.add(
            getModifiedPrediction(result, context.length, predictionLength));
      }
    }
    cachedPredictions[CachedPair(predictionLength, context.join())] =
        predictions;
    return predictions;
  }

// Only returns the unique WordInfo objects in the original list.
  List<WordInfo> removeDuplicates(List<WordInfo> predictions) {
    var uniquePredictions = <WordInfo>[];
    for (var prediction in predictions) {
      var curr = prediction.aksaras.join();
      var isDuplicate = false;
      for (var j = 0; j < uniquePredictions.length && !isDuplicate; j++) {
        if (curr == uniquePredictions[j].aksaras.join()) {
          isDuplicate = true;
        }
      }
      if (!isDuplicate) {
        uniquePredictions.add(prediction);
      }
    }
    return uniquePredictions;
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
      Aksaras currPrediction, int predictionLength) {
    for (var child in contextNode.children) {
      if (child.text != wordStartingSymbol) {
        if (currPrediction.length == (predictionLength - 1)) {
          results.add(WordInfo(
              Aksaras(currPrediction + [child.text]), child.frequency));
        } else {
          findAllPredictions(results, child,
              Aksaras(currPrediction + [child.text]), predictionLength);
        }
      }
    }
  }

  List<Aksaras> constructAllWords() {
    var allWords = <Aksaras>[];
    var startingNode = rootNode.children.first;
    startingNode.getWords(allWords, [startingNode.text]);
    return allWords;
  }

  void printTrie() {
    return rootNode.printNode();
  }
}
