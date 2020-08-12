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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:bubble/bubble.dart';

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

  String language = 'deva';

  String keyboardType = 'aksara';

  // Used to check if the processing of the data file has been completed.
  bool doneLoading = false;

  // The size of the text displayed and the text on the buttons.
  double fontSize = 16.0;

  Widget staticKeys;

  static const maxFontSize = 18.0;

  static const minNumOfPredictions = 30;

  int maxNumOfPredictions = 140;

  // The number of predictions displayed when the app starts up.
  int numOfPredictions = 60;

  final _predictionController = TextEditingController(text: '60');

  final _fontController = TextEditingController(text: '16.0');

  // Used to check if the keyboard is currently expanded and visible.
  bool keyboardIsExpanded = true;

  // Stores previously loaded keyboards to avoid loading times.
  Map<String, DynamicKeyboard> storedKeyboards = {};

  // This initialises the keyboard with 60 predictions.
  @override
  void initState() {
    super.initState();
    addGoogleLicense();
    initialiseKeyboard();
  }

  // If the current language's keyboard has already been created, it
  // is loaded from the map to be used. Otherwise, a new keyboard is created
  // using the binary proto files in /assets.
  void initialiseKeyboard() async {
    // Depending on the language, the max number of predictions is different
    // due to the scripts taking up different amounts of room on the screen.
    if (language == 'mlym') {
      maxNumOfPredictions = 100;
    } else {
      maxNumOfPredictions = 140;
    }
    if (numOfPredictions > maxNumOfPredictions) {
      numOfPredictions = maxNumOfPredictions;
    }
    if (storedKeyboards[language] != null) {
      setState(() {
        keyboard = storedKeyboards[language];
        keyboard.setNumOfPredictions(numOfPredictions);
        keyboard.fillKeyboard();
        _predictionController.text = numOfPredictions.toString();
        staticKeys = loadStaticKeys();
        doneLoading = true;
      });
    } else {
      await rootBundle.load('assets/${language}_trie.bin').then((data) {
        setState(() {
          var protoBytes = data.buffer.asUint8List();
          keyboard = DynamicKeyboard(protoBytes, numOfPredictions);
          _predictionController.text = numOfPredictions.toString();
          staticKeys = loadStaticKeys();
          doneLoading = true;
          storedKeyboards[language] = keyboard;
        });
      });
    }
  }

  @override
  void dispose() {
    _predictionController.dispose();
    _fontController.dispose();
    super.dispose();
  }

  // This method is rerun every time setState is called.
  @override
  Widget build(BuildContext context) {
    if (!doneLoading) {
      return Center(child: CircularProgressIndicator());
    }
    // Position on screen at beginning of scroll/swipe gesture.
    var startPosition;

    // Position on screen at end of scroll/swipe gesture.
    var endPosition;

    return Scaffold(
        resizeToAvoidBottomPadding: false,
        appBar: AppBar(
          title: Text(widget.title),
          actions: <Widget>[
            Center(
              child: Text(
                '# Predictions',
                style: TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
                // Option to choose the number of predictions displayed.
                child: Padding(
                    padding: EdgeInsets.all(5),
                    child: TextField(
                      keyboardType: TextInputType.number,
                      controller: _predictionController,
                      onEditingComplete: () {
                        numOfPredictions =
                            int.parse(_predictionController.text);
                        if (numOfPredictions > maxNumOfPredictions) {
                          numOfPredictions = maxNumOfPredictions;
                        } else if (numOfPredictions < minNumOfPredictions) {
                          numOfPredictions = minNumOfPredictions;
                        }
                        setState(() {
                          _predictionController.text =
                              numOfPredictions.toString();
                          FocusScope.of(context).unfocus();
                          keyboard.setNumOfPredictions(numOfPredictions);
                          keyboard.fillKeyboard();
                        });
                      },
                    ))),
            Center(
              child: Text(
                'Font:',
                style: TextStyle(fontSize: 14),
              ),
            ),
            Expanded(
                // Option to choose the font size.
                child: Padding(
                    padding: EdgeInsets.all(5),
                    child: TextField(
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
                        });
                      },
                    ))),
            Padding(
                padding: EdgeInsets.all(5),
                // Dropdown menu to choose the language/script.
                child: ButtonTheme(
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
                        }
                      });
                    },
                    items: <String>['deva', 'mlym']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                )),
            Expanded(
              child: RaisedButton(
                  color: Colors.blue,
                  child: Icon(Icons.info),
                  onPressed: () {
                    showAboutDialog(
                        context: context,
                        applicationName: 'Keyboard Oracle',
                        applicationLegalese:
                            'This is not an officially supported Google product.');
                  }),
            )
          ],
        ),
        body: Column(children: <Widget>[
          Expanded(
              // The text displayed using the users input.
              child: Stack(
            children: <Widget>[
              SingleChildScrollView(
                child: Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                        height: 100,
                        child: Text(keyboard.displayedText.join(),
                            style: TextStyle(
                                fontSize: fontSize,
                                backgroundColor: Colors.white)))),
              ),
              Align(
                alignment: Alignment.bottomRight,
                // Allows the user to expand/collapse the keyboard.
                child: RaisedButton(
                  color: Colors.transparent,
                  shape: CircleBorder(),
                  onPressed: () {
                    setState(() {
                      keyboardIsExpanded = !keyboardIsExpanded;
                    });
                  },
                  child: Icon(Icons.keyboard),
                ),
              ),
            ],
          )),
          // The keyboard, displays the most likely predictions of lengths 1-4.
          keyboardIsExpanded
              ? Column(
                  key: GlobalKey(),
                  children: <Widget>[
                    GestureDetector(
                        onVerticalDragStart: (details) {
                          startPosition = details.globalPosition;
                        },
                        onVerticalDragUpdate: (details) {
                          endPosition = details.globalPosition;
                        },
                        onVerticalDragEnd: (details) {
                          if (endPosition != null) {
                            setState(() {
                              if (startPosition.dy > endPosition.dy + 5) {
                                keyboardType = 'characters';
                              } else if (startPosition.dy <
                                  endPosition.dy - 5) {
                                keyboardType = 'aksara';
                              }
                            });
                          }
                        },
                        child: Container(
                            color: Colors.grey[200],
                            child: Column(
                              children: <Widget>[
                                keyboardType == 'aksara'
                                    ? loadPredictions()
                                    : loadCharacters(),
                              ],
                            ))),
                    Container(
                        height: 40,
                        padding: const EdgeInsets.only(
                            left: 4, right: 4, top: 2, bottom: 2),
                        color: Colors.grey[200],
                        child: staticKeys)
                  ],
                )
              : SizedBox.shrink(),
        ]));
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
              right: keys[i].length == 1 ? 3 : 2,
              left: keys[i].length == 1 ? 3 : 2),
          child: GestureDetector(
              onTap: () {
                setState(() {
                  keyboard.processNewInput(keys[i]);
                  keyboard.fillKeyboard();
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

  // Displays possible single characters given the context.
  Widget loadCharacters() {
    var bubbles = <Bubble>[];
    var characters = keyboard.charPredictions;
    for (var i = 0; i < characters.length; i++) {
      bubbles.add(
        Bubble(
          color: Colors.grey[400],
          padding: BubbleEdges.only(top: 1, bottom: 1, right: 3, left: 3),
          child: GestureDetector(
              onTap: () {
                setState(() {
                  keyboard.combineCharWithContext(characters[i]);
                  keyboard.fillKeyboard();
                  keyboardType = 'aksara';
                });
              },
              child: Text(characters[i],
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
                setState(() {
                  keyboardType = 'characters';
                });
              },
              child: Icon(
                Icons.arrow_downward,
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
                  keyboardType = 'aksara';
                });
              },
              child: Icon(
                Icons.arrow_upward,
                size: 16,
              ),
            )),
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {},
              child: Icon(
                Icons.format_quote,
                size: 16,
              ),
            )),
        Expanded(
            flex: 1,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {},
              child: Icon(
                Icons.insert_emoticon,
                size: 16,
              ),
            )),
        Expanded(
            flex: 5,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffd9d9d9),
              onPressed: () {
                setState(() {
                  keyboard.processNewInput([' ']);
                  keyboard.fillKeyboard();
                });
              },
              child: Text(
                ' ',
                textAlign: TextAlign.center,
              ),
            )),
        Expanded(
            flex: 2,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                setState(() {
                  keyboard.processNewInput(['←']);
                  keyboard.fillKeyboard();
                });
              },
              child: Icon(
                Icons.backspace,
                size: 16,
              ),
            )),
        Expanded(
            flex: 2,
            child: RaisedButton(
              padding: const EdgeInsets.all(1),
              color: const Color(0xffb7b7b7),
              onPressed: () {
                keyboard.processNewInput(['⏎']);
                keyboard.fillKeyboard();
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
