// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: analyzer_use_new_elements

import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:pub_semver/pub_semver.dart';

class SinceSdkVersionComputer {
  static final RegExp _asLanguageVersion = RegExp(r'^\d+\.\d+$');

  /// The [element] is a `dart:xyz` library, so it can have `@Since` annotations.
  /// Evaluates its annotations and returns the version.
  Version? compute(ElementImpl element) {
    // Must be in a `dart:` library.
    var librarySource = element.librarySource;
    if (librarySource == null || !librarySource.uri.isScheme('dart')) {
      return null;
    }

    // Fields cannot be referenced outside.
    if (element is FieldElementImpl && element.isSynthetic) {
      return null;
    }

    // We cannot add required parameters.
    if (element is ParameterElementImpl && element.isRequired) {
      return null;
    }

    var specified = _specifiedVersion(element);
    if (element.enclosingElement3 case var enclosingElement?) {
      var enclosing = enclosingElement.sinceSdkVersion;
      return specified.maxWith(enclosing);
    } else if (element.library case var libraryElement?) {
      var enclosing = libraryElement.sinceSdkVersion;
      return specified.maxWith(enclosing);
    } else {
      return specified;
    }
  }

  /// The [element] is a `dart:xyz` library, so it can have `@Since` annotations.
  /// Evaluates its annotations and returns the version.
  Version? compute2(Element2 element) {
    // Must be in a `dart:` library.
    var libraryUri = element.library2?.uri;
    if (libraryUri == null || !libraryUri.isScheme('dart')) {
      return null;
    }

    // Fields cannot be referenced outside.
    if (element is FieldElement2 && element.isSynthetic) {
      return null;
    }

    // We cannot add required parameters.
    if (element is FormalParameterElement && element.isRequired) {
      return null;
    }

    Version? specified;
    if (element is Annotatable) {
      specified = _specifiedVersion2(element as Annotatable);
    }
    if (element.enclosingElement2 case Annotatable enclosingElement?) {
      var enclosing = enclosingElement.metadata2.sinceSdkVersion;
      return specified.maxWith(enclosing);
    } else if (element.library2 case var libraryElement?) {
      var enclosing = libraryElement.metadata2.sinceSdkVersion;
      return specified.maxWith(enclosing);
    } else {
      return specified;
    }
  }

  /// Returns the parsed [Version], or `null` if wrong format.
  static Version? _parseVersion(String versionStr) {
    // 2.15
    if (_asLanguageVersion.hasMatch(versionStr)) {
      return Version.parse('$versionStr.0');
    }

    // 2.19.3 or 3.0.0-dev.4
    try {
      return Version.parse(versionStr);
    } on FormatException {
      return null;
    }
  }

  /// Returns the maximal specified `@Since()` version, `null` if none.
  static Version? _specifiedVersion(ElementImpl element) {
    Version? result;
    for (var annotation in element.metadata) {
      if (annotation.isDartInternalSince) {
        var arguments = annotation.annotationAst.arguments?.arguments;
        var versionNode = arguments?.singleOrNull;
        if (versionNode is SimpleStringLiteralImpl) {
          var versionStr = versionNode.value;
          var version = _parseVersion(versionStr);
          if (version != null) {
            result = result.maxWith(version);
          }
        }
      }
    }
    return result;
  }

  /// Returns the maximal specified `@Since()` version, `null` if none.
  static Version? _specifiedVersion2(Annotatable element) {
    var annotations =
        element.metadata2.annotations.cast<ElementAnnotationImpl>();
    Version? result;
    for (var annotation in annotations) {
      if (annotation.isDartInternalSince) {
        var arguments = annotation.annotationAst.arguments?.arguments;
        var versionNode = arguments?.singleOrNull;
        if (versionNode is SimpleStringLiteralImpl) {
          var versionStr = versionNode.value;
          var version = _parseVersion(versionStr);
          if (version != null) {
            result = result.maxWith(version);
          }
        }
      }
    }
    return result;
  }
}

extension on Version? {
  Version? maxWith(Version? other) {
    var self = this;
    if (self == null) {
      return other;
    } else if (other == null) {
      return self;
    } else if (self >= other) {
      return self;
    } else {
      return other;
    }
  }
}
