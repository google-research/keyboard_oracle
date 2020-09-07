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

import 'dart:collection';

// A helper class for Keyboard Oracle which is used to store aksaras in a list.
class Aksaras<String> extends ListBase<String> {
  List<String> innerList = <String>[];

  Aksaras(this.innerList);

  @override
  int get length => innerList.length;

  @override
  set length(int length) {
    innerList.length = length;
  }

  @override
  void operator []=(int index, String value) {
    innerList[index] = value;
  }

  @override
  String operator [](int index) => innerList[index];

  @override
  void add(String value) => innerList.add(value);

  @override
  void addAll(Iterable<String> all) => innerList.addAll(all);

  @override
  bool operator ==(o) {
    return (o is Aksaras) && (innerList.join() == o.innerList.join());
  }

  @override
  int get hashCode => innerList.join().hashCode;
}
