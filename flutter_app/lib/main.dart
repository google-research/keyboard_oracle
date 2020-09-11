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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bubble/bubble.dart';
import 'package:trie_constructor/aksaras.dart';

import 'dynamic_keyboard.dart';

void main() {
  runApp(KeyboardApp());
}

class KeyboardApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dynamic Keyboard',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MyHomePage(title: ''),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  DynamicKeyboard keyboard;

  String language = 'hi';

  // The static buttons at the bottom of the keyboard, e.g. spacebar.
  Widget staticKeys;

  // Used to check if the processing of the data file has been completed.
  bool doneLoading = false;

  // The size of the text displayed on the buttons.
  double fontSize = 20.0;

  static const maxFontSize = 24.0;

  // The approximate number of lines of predictions displayed on the screen.
  int numOfLines = 10;

  int maxNumOfLines = 15;

  // The approximate number of aksaras that appear on each line of the screen.
  int aksarasPerLine = 16;

  // Used to check if the sub-aksara keyboard is currently expanded and visible.
  bool keyboardIsExpanded = true;

  // Stores previously loaded keyboards to avoid long loading times.
  Map<String, DynamicKeyboard> storedKeyboards = {};

  // Checks if the most recent input to the text field was from the aksara
  // keyboard or some external source (gboard, pasted text, etc.).
  bool isAksaraKeyboardInput = false;

  // Keeps a record of what the current text displayed on the screen is.
  String currentText = '';

  // Controls how long the key predictions are.
  double pWeight = -5;

  double cWeight = 16;

  final _linesController = TextEditingController(text: '10');

  final _textDisplayController = TextEditingController(text: '');

  final _fontController = TextEditingController(text: '20.0');

  final _pWeightController = TextEditingController(text: '-5');

  final _cWeightController = TextEditingController(text: '16');

  // This initialises the keyboard with 60 predictions.
  @override
  void initState() {
    super.initState();
    addGoogleLicense();
    initialiseKeyboard();
    _textDisplayController.addListener(() {
      handleNewInput();
    });
  }

  // A keyboard is created using the binary proto files in /assets. If the
  // keyboard for the current language has already been created, it is reloaded
  // from a map rather than created again.
  void initialiseKeyboard() async {
    // Depending on the language and font size, the max number of predictions
    // will be different.
    setMaxPredictions();
    if (storedKeyboards[language] != null) {
      keyboard = storedKeyboards[language];
      keyboard.reset(aksarasPerLine * numOfLines);
      staticKeys = loadStaticKeys();
      updateTextController(0);
      doneLoading = true;
    } else {
      await rootBundle.load('assets/${language}_trie.bin').then((data) {
        setState(() {
          setMaxPredictions();
          var protoBytes = data.buffer.asUint8List();
          keyboard = DynamicKeyboard(protoBytes, aksarasPerLine * numOfLines);
          storedKeyboards[language] = keyboard;
          staticKeys = loadStaticKeys();
          updateTextController(0);
          doneLoading = true;
        });
      });
    }
  }

  void setMaxPredictions() {
    // The approx. number of aksaras able to fit on a line when the font size
    // is at its maximum value. These maximum values are taken from experiments
    // using the Google Pixel.
    if (language == 'hi') {
      aksarasPerLine = 15;
      maxNumOfLines = 13;
    } else if (language == 'ml') {
      aksarasPerLine = 11;
      maxNumOfLines = 12;
    } else {
      aksarasPerLine = 14;
      maxNumOfLines = 12;
    }
    var fontSizeDiff = maxFontSize - fontSize;
    setState(() {
      // For each decrement by 1 of the font size, there is room for approx.
      // 0.25 more aksaras to be displayed on a line.
      aksarasPerLine += (fontSizeDiff / 4).round();
      // For each decrement by 1 of the font size, there is room for approx.
      // 0.5 more lines to be displayed on the screen.
      maxNumOfLines += (fontSizeDiff / 2).round();
      numOfLines = maxNumOfLines;
      _linesController.text = numOfLines.toString();
    });
  }

  // Manually updates the position of the text field's cursor.
  void updateTextController(int offset) {
    _textDisplayController.value = TextEditingValue(
      text: keyboard.displayedText.join(),
      selection: TextSelection(baseOffset: offset, extentOffset: offset),
    );
    currentText = keyboard.displayedText.join();
    isAksaraKeyboardInput = true;
  }

  // Retrieves the index of the last aksara that appears before the cursor.
  // In other words, returns how many aksaras come before the cursor.
  int getLastAksaraIndex({int cursorIndex}) {
    if (cursorIndex == null) {
      cursorIndex = _textDisplayController.selection.baseOffset;
    }
    if (cursorIndex <= 0) {
      return 0;
    } else {
      var text = keyboard.displayedText;
      var currentLength = 0;
      for (var i = 0; i < text.length; i++) {
        currentLength += text[i].length;
        if (cursorIndex <= currentLength) {
          return i + 1;
        }
      }
      return text.length;
    }
  }

  // We update the aksara keyboard's text and context if the input has come
  // from an external source (pasted text, etc.) and either (1) The keyboard
  // has been switched from non-aksaras to aksaras or (2) the cursor has been
  // manually moved.
  dynamic handleNewInput() {
    var shownText = _textDisplayController.text;
    // If shownText is equal to currentText this means that no changes have
    // been made but the cursor has been moved.
    if (!isAksaraKeyboardInput &&
        (keyboardIsExpanded || (shownText == currentText))) {
      var keyboardText = keyboard.displayedText.join();
      // If any changes have been made.
      if (shownText != keyboardText) {
        int index = 0;
        // Finds where the keyboard's text and the text currently shown differ.
        while (index < keyboardText.length &&
            index < shownText.length &&
            shownText[index] == keyboardText[index]) {
          index++;
        }
        // Finds all of the aksaras the keyboard and shown text both begin with.
        var cursorIndex = getLastAksaraIndex(cursorIndex: index);
        int diff = shownText.length - keyboardText.length;
        var unchangedText = keyboard.displayedText.sublist(0, cursorIndex);
        if (diff >= 0) {
          var newText = shownText.substring(index);
          keyboard.displayedText = Aksaras(unchangedText);
          setState(() {
            var offset = keyboard.addNewText(newText, cursorIndex);
            updateTextController(offset - 1);
          });
        } else {
          // If the diff is negative this means aksaras/letters have been cut
          // from the text.
          var afterCut = (cursorIndex - diff) <= keyboard.displayedText.length
              ? keyboard.displayedText.sublist(cursorIndex - diff)
              : [];
          setState(() {
            keyboard.displayedText = Aksaras(unchangedText + afterCut);
          });
        }
      }
    } else {
      isAksaraKeyboardInput = false;
    }
    currentText = shownText;
  }

  @override
  void dispose() {
    _linesController.dispose();
    _textDisplayController.dispose();
    _fontController.dispose();
    _pWeightController.dispose();
    super.dispose();
  }

  // This method is run each time setState is called.
  @override
  Widget build(BuildContext context) {
    if (keyboardIsExpanded) {
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    } else {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
    if (!doneLoading) {
      return Center(
          child: Text(
        'Loading...',
        style: TextStyle(color: Colors.white),
      ));
    }
    // This decides whether the phone's in-build keyboard is displayed or not.
    return Scaffold(
      // This makes sure there is no overflow when an in-built keyboard is
      // displayed, i.e. the keyboard appears on top of the already existing
      // widgets, rather than pushing them upwards on the screen.
      resizeToAvoidBottomInset: false,
      body: Column(children: <Widget>[
        Expanded(
            child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.topLeft,
              child: SafeArea(
                child: SingleChildScrollView(
                  // The text displaying what the user has input.
                  child: TextField(
                      onTap: () {
                        // Makes sure that, when the focus is put on the
                        // TextField, the in-build keyboard is only displayed
                        // when it is supposed to be.
                        if (keyboardIsExpanded) {
                          SystemChannels.textInput
                              .invokeMethod('TextInput.hide');
                        } else {
                          SystemChannels.textInput
                              .invokeMethod('TextInput.show');
                        }
                      },
                      decoration: null,
                      autofocus: true,
                      keyboardType: TextInputType.multiline,
                      maxLines: (maxNumOfLines - numOfLines) + 3,
                      showCursor: true,
                      controller: _textDisplayController,
                      style: TextStyle(
                          fontSize: 26, backgroundColor: Colors.white)),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom),
                child: keyboardIsExpanded
                    ? SizedBox.shrink()
                    : RaisedButton(
                        color: Colors.transparent,
                        shape: CircleBorder(),
                        // Allows the user to switch between the aksara keyboard and
                        // the phone's in-built keyboard.
                        onPressed: () {
                          setState(() {
                            keyboardIsExpanded = !keyboardIsExpanded;
                            if (keyboardIsExpanded) {
                              handleNewInput();
                            }
                          });
                        },
                        // Displays the app settings in a popup.
                        onLongPress: () {
                          setState(() {
                            keyboardIsExpanded = false;
                            showSettingsMenu();
                          });
                        },
                        child: Icon(Icons.keyboard),
                      ),
              ),
            ),
          ],
        )),
        // The keyboard, displays the most likely predictions of lengths 1-4.
        keyboardIsExpanded
            ? Column(
                key: GlobalKey(),
                children: <Widget>[
                  Container(
                    color: Colors.grey[200],
                    child: loadPredictions(),
                  ),
                  Container(
                      height: 40,
                      padding: const EdgeInsets.only(
                          left: 4, right: 4, top: 2, bottom: 2),
                      color: Colors.grey[200],
                      child: staticKeys)
                ],
              )
            : SizedBox.shrink(),
      ]),
    );
  }

// A popup dialog containing app info and settings for font size, language, etc.
  Future<dynamic> showSettingsMenu() {
    return showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  right: -45.0,
                  top: -45.0,
                  child: InkResponse(
                    onTap: () {
                      Navigator.of(context).pop();
                      keyboardIsExpanded = true;
                    },
                    child: CircleAvatar(
                      child: Icon(Icons.close),
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ),
                SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      Center(
                        child: Text(
                          'Language:',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      ButtonTheme(
                        alignedDropdown: true,
                        child: DropdownButton<String>(
                          value: language,
                          icon: Icon(Icons.arrow_downward),
                          iconSize: 14,
                          style: TextStyle(fontSize: 14, color: Colors.black),
                          underline: Container(
                            height: 2,
                            color: Colors.black,
                          ),
                          onChanged: (String newValue) {
                            setState(() {
                              if (newValue != language) {
                                language = newValue;
                                doneLoading = false;
                                initialiseKeyboard();
                                Navigator.of(context).pop();
                              }
                            });
                          },
                          items: <String>['hi', 'ml', 'bn', 'te']
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                      ),
                      Center(
                        child: Text(
                          '# Lines',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),

                      // Option to choose the number of lines of predictions
                      // that are displayed.
                      TextField(
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        controller: _linesController,
                        onEditingComplete: () {
                          numOfLines = int.parse(_linesController.text);
                          if (numOfLines > maxNumOfLines) {
                            numOfLines = maxNumOfLines;
                          } else if (numOfLines < 1) {
                            numOfLines = 1;
                          }
                          setState(() {
                            _linesController.text = numOfLines.toString();
                            FocusScope.of(context).unfocus();
                            keyboard
                                .setNumOfAksaras(aksarasPerLine * numOfLines);
                            keyboard.fillKeyboard();
                            Navigator.of(context).pop();
                          });
                        },
                      ),
                      Center(
                        child: Text(
                          'Font:',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      TextField(
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        controller: _fontController,
                        onEditingComplete: () {
                          var sizeInput = double.parse(_fontController.text);
                          if (sizeInput > maxFontSize) {
                            sizeInput = maxFontSize;
                          } else if (sizeInput < 1) {
                            sizeInput = 1;
                          }
                          setState(() {
                            _fontController.text = sizeInput.toString();
                            FocusScope.of(context).unfocus();
                            fontSize = sizeInput;
                            setMaxPredictions();
                            keyboard
                                .setNumOfAksaras(aksarasPerLine * numOfLines);
                            keyboard.fillKeyboard();
                            Navigator.of(context).pop();
                          });
                        },
                      ),
                      Center(
                        child: Text(
                          'Prediction Length Weight',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      // Option to choose the predictionWeight value (how long
                      // key predictions are in general)
                      TextField(
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        controller: _pWeightController,
                        onEditingComplete: () {
                          pWeight = double.parse(_pWeightController.text);
                          setState(() {
                            FocusScope.of(context).unfocus();
                            _pWeightController.text = pWeight.toString();
                            keyboard.setPredictionWeight(pWeight);
                            keyboard.fillKeyboard();
                            Navigator.of(context).pop();
                          });
                        },
                      ),
                      Center(
                        child: Text(
                          'Context Weight',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      // Option to choose the contextWeight value (how important
                      // the context is for predictions)
                      TextField(
                        autofocus: false,
                        keyboardType: TextInputType.number,
                        controller: _cWeightController,
                        onEditingComplete: () {
                          cWeight = double.parse(_cWeightController.text);
                          setState(() {
                            FocusScope.of(context).unfocus();
                            _cWeightController.text = cWeight.toString();
                            keyboard.setContextWeight(cWeight);
                            keyboard.fillKeyboard();
                            Navigator.of(context).pop();
                          });
                        },
                      ),
                      RaisedButton(
                          color: Colors.blue,
                          child: Icon(Icons.info),
                          onPressed: () {
                            showAboutDialog(
                                context: context,
                                applicationName: 'Keyboard Oracle',
                                applicationLegalese:
                                    'This is not an officially supported Google product.');
                          }),
                    ],
                  ),
                ),
              ],
            ),
          );
        });
  }

// The main part of the keyboard, displays predictions.
  Widget loadPredictions() {
    var bubbles = <Bubble>[];
    var keys = keyboard.keys;
    keys.sort((a, b) => a.join().compareTo(b.join()));
    for (var i = 0; i < keys.length; i++) {
      bubbles.add(
        Bubble(
          color: Colors.grey[400],
          padding: BubbleEdges.only(
              top: 1,
              bottom: 1,
              right: keys[i].length == 1 ? 7 : 1,
              left: keys[i].length == 1 ? 7 : 1),
          child: InkResponse(
              onTap: () {
                setState(() {
                  var end = getLastAksaraIndex();
                  keyboard.processNewInput(keys[i], end);
                  updateTextController(keyboard.displayedText
                      .sublist(0, end + keys[i].length)
                      .join()
                      .length);
                });
              },
              child: Text(keys[i].join(),
                  style: TextStyle(fontSize: fontSize, color: Colors.black))),
        ),
      );
    }
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 0,
      runSpacing: 2,
      children: bubbles,
    );
  }

  // Displays static keys such as enter, backspace, etc.
  Widget loadStaticKeys() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                Clipboard.setData(
                    new ClipboardData(text: keyboard.displayedText.join()));
              },
              child: Icon(
                Icons.content_copy,
                size: 16,
              ),
            )),
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                setState(() {
                  keyboardIsExpanded = !keyboardIsExpanded;
                  if (keyboardIsExpanded) {
                    handleNewInput();
                  }
                });
              },
              onLongPress: () {
                setState(() {
                  keyboardIsExpanded = false;
                  showSettingsMenu();
                });
              },
              child: Icon(Icons.keyboard),
            )),
        Expanded(
            flex: 3,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffd9d9d9),
              onPressed: () {
                setState(() {
                  var end = getLastAksaraIndex();
                  keyboard.processNewInput(Aksaras([' ']), end);
                  updateTextController(
                      keyboard.displayedText.sublist(0, end + 1).join().length);
                });
              },
              child: Text(
                ' ',
                textAlign: TextAlign.center,
              ),
            )),
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                setState(() {
                  var end = getLastAksaraIndex();
                  keyboard.processNewInput(Aksaras(['←']), end);
                  var newEnd = end <= 1
                      ? end - 1
                      : keyboard.displayedText
                          .sublist(0, end - 1)
                          .join()
                          .length;
                  updateTextController(newEnd);
                });
              },
              child: Icon(
                Icons.backspace,
                size: 16,
              ),
            )),
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                setState(() {
                  var end = getLastAksaraIndex();
                  keyboard.processNewInput(Aksaras(['\n']), end);
                  updateTextController(
                      keyboard.displayedText.sublist(0, end + 1).join().length);
                });
              },
              child: Icon(
                Icons.keyboard_return,
                size: 18,
              ),
            )),
      ],
    );
  }

  void addGoogleLicense() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(['Keyboard Oracle'], '''
Copyright 2020 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.''');
    });
  }
}
