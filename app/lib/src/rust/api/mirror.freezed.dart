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
