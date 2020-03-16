import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:build/build.dart';
import 'package:settings_manager/settings_manager.dart';
import 'package:settings_manager/src/api/annotations.dart'
    show BoolSetting, SettingsConfig;
import 'package:source_gen/source_gen.dart';

import 'errors.dart';
import 'template/bool_setting.dart';
import 'template/store.dart';
import 'template/string_setting.dart';
import 'template/util.dart';
import 'type_names.dart';

class StoreClassVisitor extends SimpleElementVisitor {
  StoreClassVisitor(
    String publicTypeName,
    ClassElement userClass,
    StoreTemplate template,
    this.typeNameFinder,
  ) : _errors = StoreClassCodegenErrors(publicTypeName) {
    _storeTemplate = template
      ..typeParams.templates.addAll(userClass.typeParameters
          .map((type) => typeParamTemplate(type, typeNameFinder)))
      ..typeArgs.templates.addAll(userClass.typeParameters.map((t) => t.name))
      ..parentTypeName = userClass.name
      ..publicTypeName = publicTypeName;
  }

  final _boolSettingChecker = const TypeChecker.fromRuntime(BoolSetting);
  final _stringSettingChecker = const TypeChecker.fromRuntime(StringSetting);

  StoreTemplate _storeTemplate;

  LibraryScopedNameFinder typeNameFinder;

  final StoreClassCodegenErrors _errors;

  String get source {
    if (_errors.hasErrors) {
      log.severe(_errors.message);
      return '';
    }
    return _storeTemplate.toString();
  }

  @override
  void visitClassElement(ClassElement element) {
    if (isMixinStoreClass(element)) {
      _errors.nonAbstractStoreMixinDeclarations
          .addIf(!element.isAbstract, element.name);
    }
    // if the class is annotated to generate toString() method we add the information to the _storeTemplate
    _storeTemplate.generateToString = hasGeneratedToString(element);
  }

  @override
  void visitFieldElement(FieldElement element) {
    if (_fieldIsNotValid(element)) {
      return;
    }

    if (_boolSettingChecker.hasAnnotationOfExact(element)) {
      final annotation = _boolSettingChecker.firstAnnotationOfExact(element);
      final template = BoolSettingTemplate()
        ..defaultValue = annotation.getField('defaultValue').toBoolValue()
        ..addStream = annotation.getField('addStream').toBoolValue()
        ..addValueNotifer = annotation.getField('addValueNotifer').toBoolValue()
        ..isPrivate = element.isPrivate
        ..name = element.name;
      _storeTemplate.boolSettings.add(template);
    }

    if (_stringSettingChecker.hasAnnotationOfExact(element)) {
      final annotation = _stringSettingChecker.firstAnnotationOfExact(element);
      final template = StringSettingTemplate()
        ..defaultValue = annotation.getField('defaultValue').toStringValue()
        ..isPrivate = element.isPrivate
        ..name = element.name;
      _storeTemplate.stringSettings.add(template);
    }

    return;
  }

  bool _fieldIsNotValid(FieldElement element) => _any([
        _errors.staticObservables.addIf(element.isStatic, element.name),
        _errors.finalObservables.addIf(element.isFinal, element.name)
      ]);
}

const _storeMixinChecker = TypeChecker.fromRuntime(SettingsStore);
const _toStringAnnotationChecker = TypeChecker.fromRuntime(SettingsConfig);

bool isMixinStoreClass(ClassElement classElement) =>
    classElement.mixins.any(_storeMixinChecker.isExactlyType);

// Checks if the class as a toString annotation
bool isStoreConfigAnnotatedStoreClass(ClassElement classElement) =>
    _toStringAnnotationChecker.hasAnnotationOfExact(classElement);

bool hasGeneratedToString(ClassElement classElement) {
  if (isStoreConfigAnnotatedStoreClass(classElement)) {
    final annotation =
        _toStringAnnotationChecker.firstAnnotationOfExact(classElement);
    return annotation.getField('hasToString').toBoolValue();
  }
  return true;
}

bool _any(List<bool> list) => list.any(_identity);

T _identity<T>(T value) => value;
