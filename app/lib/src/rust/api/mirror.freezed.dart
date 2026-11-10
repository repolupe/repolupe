// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'mirror.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApiKeyChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiKeyChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiKeyChange()';
}


}

/// @nodoc
class $ApiKeyChangeCopyWith<$Res>  {
$ApiKeyChangeCopyWith(ApiKeyChange _, $Res Function(ApiKeyChange) __);
}


/// Adds pattern-matching-related methods to [ApiKeyChange].
extension ApiKeyChangePatterns on ApiKeyChange {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ApiKeyChange_Keep value)?  keep,TResult Function( ApiKeyChange_Remove value)?  remove,TResult Function( ApiKeyChange_Set value)?  set_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ApiKeyChange_Keep() when keep != null:
return keep(_that);case ApiKeyChange_Remove() when remove != null:
return remove(_that);case ApiKeyChange_Set() when set_ != null:
return set_(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ApiKeyChange_Keep value)  keep,required TResult Function( ApiKeyChange_Remove value)  remove,required TResult Function( ApiKeyChange_Set value)  set_,}){
final _that = this;
switch (_that) {
case ApiKeyChange_Keep():
return keep(_that);case ApiKeyChange_Remove():
return remove(_that);case ApiKeyChange_Set():
return set_(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ApiKeyChange_Keep value)?  keep,TResult? Function( ApiKeyChange_Remove value)?  remove,TResult? Function( ApiKeyChange_Set value)?  set_,}){
final _that = this;
switch (_that) {
case ApiKeyChange_Keep() when keep != null:
return keep(_that);case ApiKeyChange_Remove() when remove != null:
return remove(_that);case ApiKeyChange_Set() when set_ != null:
return set_(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function()?  remove,TResult Function( String value)?  set_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ApiKeyChange_Keep() when keep != null:
return keep();case ApiKeyChange_Remove() when remove != null:
return remove();case ApiKeyChange_Set() when set_ != null:
return set_(_that.value);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function()  remove,required TResult Function( String value)  set_,}) {final _that = this;
switch (_that) {
case ApiKeyChange_Keep():
return keep();case ApiKeyChange_Remove():
return remove();case ApiKeyChange_Set():
return set_(_that.value);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function()?  remove,TResult? Function( String value)?  set_,}) {final _that = this;
switch (_that) {
case ApiKeyChange_Keep() when keep != null:
return keep();case ApiKeyChange_Remove() when remove != null:
return remove();case ApiKeyChange_Set() when set_ != null:
return set_(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ApiKeyChange_Keep extends ApiKeyChange {
  const ApiKeyChange_Keep(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiKeyChange_Keep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiKeyChange.keep()';
}


}




/// @nodoc


class ApiKeyChange_Remove extends ApiKeyChange {
  const ApiKeyChange_Remove(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiKeyChange_Remove);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'ApiKeyChange.remove()';
}


}




/// @nodoc


class ApiKeyChange_Set extends ApiKeyChange {
  const ApiKeyChange_Set({required this.value}): super._();
  

 final  String value;

/// Create a copy of ApiKeyChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApiKeyChange_SetCopyWith<ApiKeyChange_Set> get copyWith => _$ApiKeyChange_SetCopyWithImpl<ApiKeyChange_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApiKeyChange_Set&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'ApiKeyChange.set_(value: $value)';
}


}

/// @nodoc
abstract mixin class $ApiKeyChange_SetCopyWith<$Res> implements $ApiKeyChangeCopyWith<$Res> {
  factory $ApiKeyChange_SetCopyWith(ApiKeyChange_Set value, $Res Function(ApiKeyChange_Set) _then) = _$ApiKeyChange_SetCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$ApiKeyChange_SetCopyWithImpl<$Res>
    implements $ApiKeyChange_SetCopyWith<$Res> {
  _$ApiKeyChange_SetCopyWithImpl(this._self, this._then);

  final ApiKeyChange_Set _self;
  final $Res Function(ApiKeyChange_Set) _then;

/// Create a copy of ApiKeyChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(ApiKeyChange_Set(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RawBlockDto {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RawBlockDto()';
}


}

/// @nodoc
class $RawBlockDtoCopyWith<$Res>  {
$RawBlockDtoCopyWith(RawBlockDto _, $Res Function(RawBlockDto) __);
}


/// Adds pattern-matching-related methods to [RawBlockDto].
extension RawBlockDtoPatterns on RawBlockDto {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RawBlockDto_Text value)?  text,TResult Function( RawBlockDto_Reasoning value)?  reasoning,TResult Function( RawBlockDto_ToolUse value)?  toolUse,TResult Function( RawBlockDto_ToolResult value)?  toolResult,TResult Function( RawBlockDto_Unknown value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RawBlockDto_Text() when text != null:
return text(_that);case RawBlockDto_Reasoning() when reasoning != null:
return reasoning(_that);case RawBlockDto_ToolUse() when toolUse != null:
return toolUse(_that);case RawBlockDto_ToolResult() when toolResult != null:
return toolResult(_that);case RawBlockDto_Unknown() when unknown != null:
return unknown(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RawBlockDto_Text value)  text,required TResult Function( RawBlockDto_Reasoning value)  reasoning,required TResult Function( RawBlockDto_ToolUse value)  toolUse,required TResult Function( RawBlockDto_ToolResult value)  toolResult,required TResult Function( RawBlockDto_Unknown value)  unknown,}){
final _that = this;
switch (_that) {
case RawBlockDto_Text():
return text(_that);case RawBlockDto_Reasoning():
return reasoning(_that);case RawBlockDto_ToolUse():
return toolUse(_that);case RawBlockDto_ToolResult():
return toolResult(_that);case RawBlockDto_Unknown():
return unknown(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RawBlockDto_Text value)?  text,TResult? Function( RawBlockDto_Reasoning value)?  reasoning,TResult? Function( RawBlockDto_ToolUse value)?  toolUse,TResult? Function( RawBlockDto_ToolResult value)?  toolResult,TResult? Function( RawBlockDto_Unknown value)?  unknown,}){
final _that = this;
switch (_that) {
case RawBlockDto_Text() when text != null:
return text(_that);case RawBlockDto_Reasoning() when reasoning != null:
return reasoning(_that);case RawBlockDto_ToolUse() when toolUse != null:
return toolUse(_that);case RawBlockDto_ToolResult() when toolResult != null:
return toolResult(_that);case RawBlockDto_Unknown() when unknown != null:
return unknown(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  text,TResult Function( String text,  bool redacted)?  reasoning,TResult Function( String id,  String name,  String input)?  toolUse,TResult Function( String toolUseId,  String content,  bool isError)?  toolResult,TResult Function()?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RawBlockDto_Text() when text != null:
return text(_that.text);case RawBlockDto_Reasoning() when reasoning != null:
return reasoning(_that.text,_that.redacted);case RawBlockDto_ToolUse() when toolUse != null:
return toolUse(_that.id,_that.name,_that.input);case RawBlockDto_ToolResult() when toolResult != null:
return toolResult(_that.toolUseId,_that.content,_that.isError);case RawBlockDto_Unknown() when unknown != null:
return unknown();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  text,required TResult Function( String text,  bool redacted)  reasoning,required TResult Function( String id,  String name,  String input)  toolUse,required TResult Function( String toolUseId,  String content,  bool isError)  toolResult,required TResult Function()  unknown,}) {final _that = this;
switch (_that) {
case RawBlockDto_Text():
return text(_that.text);case RawBlockDto_Reasoning():
return reasoning(_that.text,_that.redacted);case RawBlockDto_ToolUse():
return toolUse(_that.id,_that.name,_that.input);case RawBlockDto_ToolResult():
return toolResult(_that.toolUseId,_that.content,_that.isError);case RawBlockDto_Unknown():
return unknown();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  text,TResult? Function( String text,  bool redacted)?  reasoning,TResult? Function( String id,  String name,  String input)?  toolUse,TResult? Function( String toolUseId,  String content,  bool isError)?  toolResult,TResult? Function()?  unknown,}) {final _that = this;
switch (_that) {
case RawBlockDto_Text() when text != null:
return text(_that.text);case RawBlockDto_Reasoning() when reasoning != null:
return reasoning(_that.text,_that.redacted);case RawBlockDto_ToolUse() when toolUse != null:
return toolUse(_that.id,_that.name,_that.input);case RawBlockDto_ToolResult() when toolResult != null:
return toolResult(_that.toolUseId,_that.content,_that.isError);case RawBlockDto_Unknown() when unknown != null:
return unknown();case _:
  return null;

}
}

}

/// @nodoc


class RawBlockDto_Text extends RawBlockDto {
  const RawBlockDto_Text({required this.text}): super._();
  

 final  String text;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawBlockDto_TextCopyWith<RawBlockDto_Text> get copyWith => _$RawBlockDto_TextCopyWithImpl<RawBlockDto_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto_Text&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'RawBlockDto.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $RawBlockDto_TextCopyWith<$Res> implements $RawBlockDtoCopyWith<$Res> {
  factory $RawBlockDto_TextCopyWith(RawBlockDto_Text value, $Res Function(RawBlockDto_Text) _then) = _$RawBlockDto_TextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$RawBlockDto_TextCopyWithImpl<$Res>
    implements $RawBlockDto_TextCopyWith<$Res> {
  _$RawBlockDto_TextCopyWithImpl(this._self, this._then);

  final RawBlockDto_Text _self;
  final $Res Function(RawBlockDto_Text) _then;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(RawBlockDto_Text(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RawBlockDto_Reasoning extends RawBlockDto {
  const RawBlockDto_Reasoning({required this.text, required this.redacted}): super._();
  

 final  String text;
 final  bool redacted;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawBlockDto_ReasoningCopyWith<RawBlockDto_Reasoning> get copyWith => _$RawBlockDto_ReasoningCopyWithImpl<RawBlockDto_Reasoning>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto_Reasoning&&(identical(other.text, text) || other.text == text)&&(identical(other.redacted, redacted) || other.redacted == redacted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,redacted);
}

@override
String toString() {
    return 'RawBlockDto.reasoning(text: $text, redacted: $redacted)';
}


}

/// @nodoc
abstract mixin class $RawBlockDto_ReasoningCopyWith<$Res> implements $RawBlockDtoCopyWith<$Res> {
  factory $RawBlockDto_ReasoningCopyWith(RawBlockDto_Reasoning value, $Res Function(RawBlockDto_Reasoning) _then) = _$RawBlockDto_ReasoningCopyWithImpl;
@useResult
$Res call({
 String text, bool redacted
});




}
/// @nodoc
class _$RawBlockDto_ReasoningCopyWithImpl<$Res>
    implements $RawBlockDto_ReasoningCopyWith<$Res> {
  _$RawBlockDto_ReasoningCopyWithImpl(this._self, this._then);

  final RawBlockDto_Reasoning _self;
  final $Res Function(RawBlockDto_Reasoning) _then;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,Object? redacted = null,}) {
  return _then(RawBlockDto_Reasoning(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,redacted: null == redacted ? _self.redacted : redacted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RawBlockDto_ToolUse extends RawBlockDto {
  const RawBlockDto_ToolUse({required this.id, required this.name, required this.input}): super._();
  

 final  String id;
 final  String name;
 final  String input;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawBlockDto_ToolUseCopyWith<RawBlockDto_ToolUse> get copyWith => _$RawBlockDto_ToolUseCopyWithImpl<RawBlockDto_ToolUse>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto_ToolUse&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.input, input) || other.input == input));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,input);
}

@override
String toString() {
    return 'RawBlockDto.toolUse(id: $id, name: $name, input: $input)';
}


}

/// @nodoc
abstract mixin class $RawBlockDto_ToolUseCopyWith<$Res> implements $RawBlockDtoCopyWith<$Res> {
  factory $RawBlockDto_ToolUseCopyWith(RawBlockDto_ToolUse value, $Res Function(RawBlockDto_ToolUse) _then) = _$RawBlockDto_ToolUseCopyWithImpl;
@useResult
$Res call({
 String id, String name, String input
});




}
/// @nodoc
class _$RawBlockDto_ToolUseCopyWithImpl<$Res>
    implements $RawBlockDto_ToolUseCopyWith<$Res> {
  _$RawBlockDto_ToolUseCopyWithImpl(this._self, this._then);

  final RawBlockDto_ToolUse _self;
  final $Res Function(RawBlockDto_ToolUse) _then;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? input = null,}) {
  return _then(RawBlockDto_ToolUse(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RawBlockDto_ToolResult extends RawBlockDto {
  const RawBlockDto_ToolResult({required this.toolUseId, required this.content, required this.isError}): super._();
  

 final  String toolUseId;
 final  String content;
 final  bool isError;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawBlockDto_ToolResultCopyWith<RawBlockDto_ToolResult> get copyWith => _$RawBlockDto_ToolResultCopyWithImpl<RawBlockDto_ToolResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto_ToolResult&&(identical(other.toolUseId, toolUseId) || other.toolUseId == toolUseId)&&(identical(other.content, content) || other.content == content)&&(identical(other.isError, isError) || other.isError == isError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toolUseId,content,isError);
}

@override
String toString() {
    return 'RawBlockDto.toolResult(toolUseId: $toolUseId, content: $content, isError: $isError)';
}


}

/// @nodoc
abstract mixin class $RawBlockDto_ToolResultCopyWith<$Res> implements $RawBlockDtoCopyWith<$Res> {
  factory $RawBlockDto_ToolResultCopyWith(RawBlockDto_ToolResult value, $Res Function(RawBlockDto_ToolResult) _then) = _$RawBlockDto_ToolResultCopyWithImpl;
@useResult
$Res call({
 String toolUseId, String content, bool isError
});




}
/// @nodoc
class _$RawBlockDto_ToolResultCopyWithImpl<$Res>
    implements $RawBlockDto_ToolResultCopyWith<$Res> {
  _$RawBlockDto_ToolResultCopyWithImpl(this._self, this._then);

  final RawBlockDto_ToolResult _self;
  final $Res Function(RawBlockDto_ToolResult) _then;

/// Create a copy of RawBlockDto
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? toolUseId = null,Object? content = null,Object? isError = null,}) {
  return _then(RawBlockDto_ToolResult(
toolUseId: null == toolUseId ? _self.toolUseId : toolUseId // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,isError: null == isError ? _self.isError : isError // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RawBlockDto_Unknown extends RawBlockDto {
  const RawBlockDto_Unknown(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RawBlockDto_Unknown);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'RawBlockDto.unknown()';
}


}




/// @nodoc
mixin _$TokenChange {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TokenChange);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TokenChange()';
}


}

/// @nodoc
class $TokenChangeCopyWith<$Res>  {
$TokenChangeCopyWith(TokenChange _, $Res Function(TokenChange) __);
}


/// Adds pattern-matching-related methods to [TokenChange].
extension TokenChangePatterns on TokenChange {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TokenChange_Keep value)?  keep,TResult Function( TokenChange_Remove value)?  remove,TResult Function( TokenChange_Set value)?  set_,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TokenChange_Keep() when keep != null:
return keep(_that);case TokenChange_Remove() when remove != null:
return remove(_that);case TokenChange_Set() when set_ != null:
return set_(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TokenChange_Keep value)  keep,required TResult Function( TokenChange_Remove value)  remove,required TResult Function( TokenChange_Set value)  set_,}){
final _that = this;
switch (_that) {
case TokenChange_Keep():
return keep(_that);case TokenChange_Remove():
return remove(_that);case TokenChange_Set():
return set_(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TokenChange_Keep value)?  keep,TResult? Function( TokenChange_Remove value)?  remove,TResult? Function( TokenChange_Set value)?  set_,}){
final _that = this;
switch (_that) {
case TokenChange_Keep() when keep != null:
return keep(_that);case TokenChange_Remove() when remove != null:
return remove(_that);case TokenChange_Set() when set_ != null:
return set_(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  keep,TResult Function()?  remove,TResult Function( String value)?  set_,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TokenChange_Keep() when keep != null:
return keep();case TokenChange_Remove() when remove != null:
return remove();case TokenChange_Set() when set_ != null:
return set_(_that.value);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  keep,required TResult Function()  remove,required TResult Function( String value)  set_,}) {final _that = this;
switch (_that) {
case TokenChange_Keep():
return keep();case TokenChange_Remove():
return remove();case TokenChange_Set():
return set_(_that.value);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  keep,TResult? Function()?  remove,TResult? Function( String value)?  set_,}) {final _that = this;
switch (_that) {
case TokenChange_Keep() when keep != null:
return keep();case TokenChange_Remove() when remove != null:
return remove();case TokenChange_Set() when set_ != null:
return set_(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class TokenChange_Keep extends TokenChange {
  const TokenChange_Keep(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TokenChange_Keep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TokenChange.keep()';
}


}




/// @nodoc


class TokenChange_Remove extends TokenChange {
  const TokenChange_Remove(): super._();
  






@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TokenChange_Remove);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'TokenChange.remove()';
}


}




/// @nodoc


class TokenChange_Set extends TokenChange {
  const TokenChange_Set({required this.value}): super._();
  

 final  String value;

/// Create a copy of TokenChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TokenChange_SetCopyWith<TokenChange_Set> get copyWith => _$TokenChange_SetCopyWithImpl<TokenChange_Set>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is TokenChange_Set&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'TokenChange.set_(value: $value)';
}


}

/// @nodoc
abstract mixin class $TokenChange_SetCopyWith<$Res> implements $TokenChangeCopyWith<$Res> {
  factory $TokenChange_SetCopyWith(TokenChange_Set value, $Res Function(TokenChange_Set) _then) = _$TokenChange_SetCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$TokenChange_SetCopyWithImpl<$Res>
    implements $TokenChange_SetCopyWith<$Res> {
  _$TokenChange_SetCopyWithImpl(this._self, this._then);

  final TokenChange_Set _self;
  final $Res Function(TokenChange_Set) _then;

/// Create a copy of TokenChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(TokenChange_Set(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
