// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ClientError {

 String get message;
/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientErrorCopyWith<ClientError> get copyWith => _$ClientErrorCopyWithImpl<ClientError>(this as ClientError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ClientError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientError&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ClientError;
  return Object.hash(runtimeType,_this.message);
}

@override
String toString() {
  final _this = this as ClientError;
  return 'ClientError(message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $ClientErrorCopyWith<$Res>  {
  factory $ClientErrorCopyWith(ClientError value, $Res Function(ClientError) _then) = _$ClientErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ClientErrorCopyWithImpl<$Res>
    implements $ClientErrorCopyWith<$Res> {
  _$ClientErrorCopyWithImpl(this._self, this._then);

  final ClientError _self;
  final $Res Function(ClientError) _then;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ClientError].
extension ClientErrorPatterns on ClientError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ClientError_Api value)?  api,TResult Function( ClientError_InvalidResponse value)?  invalidResponse,TResult Function( ClientError_Transport value)?  transport,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ClientError_Api() when api != null:
return api(_that);case ClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that);case ClientError_Transport() when transport != null:
return transport(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ClientError_Api value)  api,required TResult Function( ClientError_InvalidResponse value)  invalidResponse,required TResult Function( ClientError_Transport value)  transport,}){
final _that = this;
switch (_that) {
case ClientError_Api():
return api(_that);case ClientError_InvalidResponse():
return invalidResponse(_that);case ClientError_Transport():
return transport(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ClientError_Api value)?  api,TResult? Function( ClientError_InvalidResponse value)?  invalidResponse,TResult? Function( ClientError_Transport value)?  transport,}){
final _that = this;
switch (_that) {
case ClientError_Api() when api != null:
return api(_that);case ClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that);case ClientError_Transport() when transport != null:
return transport(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int status,  ErrorCode code,  String message)?  api,TResult Function( int status,  String message)?  invalidResponse,TResult Function( String message)?  transport,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ClientError_Api() when api != null:
return api(_that.status,_that.code,_that.message);case ClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that.status,_that.message);case ClientError_Transport() when transport != null:
return transport(_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int status,  ErrorCode code,  String message)  api,required TResult Function( int status,  String message)  invalidResponse,required TResult Function( String message)  transport,}) {final _that = this;
switch (_that) {
case ClientError_Api():
return api(_that.status,_that.code,_that.message);case ClientError_InvalidResponse():
return invalidResponse(_that.status,_that.message);case ClientError_Transport():
return transport(_that.message);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int status,  ErrorCode code,  String message)?  api,TResult? Function( int status,  String message)?  invalidResponse,TResult? Function( String message)?  transport,}) {final _that = this;
switch (_that) {
case ClientError_Api() when api != null:
return api(_that.status,_that.code,_that.message);case ClientError_InvalidResponse() when invalidResponse != null:
return invalidResponse(_that.status,_that.message);case ClientError_Transport() when transport != null:
return transport(_that.message);case _:
  return null;

}
}

}

/// @nodoc


class ClientError_Api extends ClientError {
  const ClientError_Api({required this.status, required this.code, required this.message}): super._();
  

 final  int status;
 final  ErrorCode code;
@override final  String message;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientError_ApiCopyWith<ClientError_Api> get copyWith => _$ClientError_ApiCopyWithImpl<ClientError_Api>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientError_Api&&(identical(other.status, status) || other.status == status)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,code,message);
}

@override
String toString() {
    return 'ClientError.api(status: $status, code: $code, message: $message)';
}


}

/// @nodoc
abstract mixin class $ClientError_ApiCopyWith<$Res> implements $ClientErrorCopyWith<$Res> {
  factory $ClientError_ApiCopyWith(ClientError_Api value, $Res Function(ClientError_Api) _then) = _$ClientError_ApiCopyWithImpl;
@override @useResult
$Res call({
 int status, ErrorCode code, String message
});




}
/// @nodoc
class _$ClientError_ApiCopyWithImpl<$Res>
    implements $ClientError_ApiCopyWith<$Res> {
  _$ClientError_ApiCopyWithImpl(this._self, this._then);

  final ClientError_Api _self;
  final $Res Function(ClientError_Api) _then;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? code = null,Object? message = null,}) {
  return _then(ClientError_Api(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ErrorCode,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ClientError_InvalidResponse extends ClientError {
  const ClientError_InvalidResponse({required this.status, required this.message}): super._();
  

 final  int status;
@override final  String message;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientError_InvalidResponseCopyWith<ClientError_InvalidResponse> get copyWith => _$ClientError_InvalidResponseCopyWithImpl<ClientError_InvalidResponse>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientError_InvalidResponse&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status,message);
}

@override
String toString() {
    return 'ClientError.invalidResponse(status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $ClientError_InvalidResponseCopyWith<$Res> implements $ClientErrorCopyWith<$Res> {
  factory $ClientError_InvalidResponseCopyWith(ClientError_InvalidResponse value, $Res Function(ClientError_InvalidResponse) _then) = _$ClientError_InvalidResponseCopyWithImpl;
@override @useResult
$Res call({
 int status, String message
});




}
/// @nodoc
class _$ClientError_InvalidResponseCopyWithImpl<$Res>
    implements $ClientError_InvalidResponseCopyWith<$Res> {
  _$ClientError_InvalidResponseCopyWithImpl(this._self, this._then);

  final ClientError_InvalidResponse _self;
  final $Res Function(ClientError_InvalidResponse) _then;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = null,}) {
  return _then(ClientError_InvalidResponse(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class ClientError_Transport extends ClientError {
  const ClientError_Transport({required this.message}): super._();
  

@override final  String message;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClientError_TransportCopyWith<ClientError_Transport> get copyWith => _$ClientError_TransportCopyWithImpl<ClientError_Transport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClientError_Transport&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'ClientError.transport(message: $message)';
}


}

/// @nodoc
abstract mixin class $ClientError_TransportCopyWith<$Res> implements $ClientErrorCopyWith<$Res> {
  factory $ClientError_TransportCopyWith(ClientError_Transport value, $Res Function(ClientError_Transport) _then) = _$ClientError_TransportCopyWithImpl;
@override @useResult
$Res call({
 String message
});




}
/// @nodoc
class _$ClientError_TransportCopyWithImpl<$Res>
    implements $ClientError_TransportCopyWith<$Res> {
  _$ClientError_TransportCopyWithImpl(this._self, this._then);

  final ClientError_Transport _self;
  final $Res Function(ClientError_Transport) _then;

/// Create a copy of ClientError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(ClientError_Transport(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
