// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";

class A {
  get foo => cyclicStatic;
}

var a = new A();
dynamic cyclicStatic = (() => a.foo + 1)();

cyclicInitialization() {
  return cyclicStatic;
}

// Helper method to detect whether [errorType] is an overflow error.
//
// TODO(41308): Use `is StackOverflowError` once DDC converts overflow errors
// from JavaScript.
bool isOverflowError(Type errorType) {
  void detectOverflowError() => detectOverflowError();
  try {
    detectOverflowError();
  } catch (e) {
    return errorType == e.runtimeType;
  }
  return false;
}

main() {
  bool hasThrown = false;
  try {
    cyclicStatic + 1;
  } catch (e2) {
    var e = e2;
    hasThrown = true;
    Expect.isTrue(
      isOverflowError(e.runtimeType),
      "Got '$e' instead of StackOverflowError",
    );
  }
  Expect.isTrue(hasThrown);
}
