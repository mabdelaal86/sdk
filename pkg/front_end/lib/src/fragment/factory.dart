// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'fragment.dart';

class FactoryFragment implements Fragment, FunctionFragment {
  final ConstructorName constructorName;

  final Uri fileUri;
  final int startOffset;
  final int formalsOffset;
  final int endOffset;
  final Modifiers modifiers;
  final List<MetadataBuilder>? metadata;
  final NominalParameterNameSpace typeParameterNameSpace;
  final LookupScope typeParameterScope;
  final List<FormalParameterBuilder>? formals;
  final AsyncMarker asyncModifier;
  final String? nativeMethodName;
  final ConstructorReferenceBuilder? redirectionTarget;

  SourceFactoryBuilder? _builder;

  FactoryFragment(
      {required this.constructorName,
      required this.fileUri,
      required this.startOffset,
      required this.formalsOffset,
      required this.endOffset,
      required this.modifiers,
      required this.metadata,
      required this.typeParameterNameSpace,
      required this.typeParameterScope,
      required this.formals,
      required this.asyncModifier,
      required this.nativeMethodName,
      required this.redirectionTarget});

  @override
  String get name => constructorName.name;

  int get fullNameOffset => constructorName.fullNameOffset;

  @override
  SourceFactoryBuilder get builder {
    assert(_builder != null, "Builder has not been computed for $this.");
    return _builder!;
  }

  void set builder(SourceFactoryBuilder value) {
    assert(_builder == null, "Builder has already been computed for $this.");
    _builder = value;
  }

  @override
  FunctionBodyBuildingContext createFunctionBodyBuildingContext() {
    return new _FactoryBodyBuildingContext(this);
  }

  @override
  String toString() => '$runtimeType($name,$fileUri,$fullNameOffset)';
}

class _FactoryBodyBuildingContext implements FunctionBodyBuildingContext {
  FactoryFragment _fragment;

  _FactoryBodyBuildingContext(this._fragment);

  @override
  // Coverage-ignore(suite): Not run.
  MemberKind get memberKind => MemberKind.Factory;

  @override
  bool get shouldBuild => true;

  @override
  LocalScope computeFormalParameterScope(LookupScope typeParameterScope) {
    return _fragment.builder.computeFormalParameterScope(typeParameterScope);
  }

  @override
  LookupScope get typeParameterScope {
    return _fragment.typeParameterScope;
  }

  @override
  BodyBuilderContext createBodyBuilderContext() {
    return _fragment.builder.createBodyBuilderContext();
  }

  @override
  InferenceDataForTesting? get inferenceDataForTesting => _fragment
      .builder
      .dataForTesting
      // Coverage-ignore(suite): Not run.
      ?.inferenceData;

  @override
  List<TypeParameter>? get thisTypeParameters =>
      _fragment.builder.thisTypeParameters;

  @override
  VariableDeclaration? get thisVariable => _fragment.builder.thisVariable;
}
