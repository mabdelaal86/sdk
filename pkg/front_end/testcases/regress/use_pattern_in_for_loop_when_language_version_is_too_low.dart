// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart=2.12

void foo() {
  var repoPaths = [(user: "a", repo: "b")];
  for (var (:user, :repo) in repoPaths)  {
    print(user);
    print(repo);
  }
}
