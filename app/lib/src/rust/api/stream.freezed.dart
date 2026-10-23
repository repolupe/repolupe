// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'stream.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MessageEvent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'MessageEvent()';
}


}

/// @nodoc
class $MessageEventCopyWith<$Res>  {
$MessageEventCopyWith(MessageEvent _, $Res Function(MessageEvent) __);
}


/// Adds pattern-matching-related methods to [MessageEvent].
extension MessageEventPatterns on MessageEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( MessageEvent_Snapshot value)?  snapshot,TResult Function( MessageEvent_ContentDelta value)?  contentDelta,TResult Function( MessageEvent_ToolCallStarted value)?  toolCallStarted,TResult Function( MessageEvent_ToolCallFinished value)?  toolCallFinished,TResult Function( MessageEvent_Done value)?  done,TResult Function( MessageEvent_Error value)?  error,required TResult orElse(),}){
final _that = this;
switch (_that) {
case MessageEvent_Snapshot() when snapshot != null:
return snapshot(_that);case MessageEvent_ContentDelta() when contentDelta != null:
return contentDelta(_that);case MessageEvent_ToolCallStarted() when toolCallStarted != null:
return toolCallStarted(_that);case MessageEvent_ToolCallFinished() when toolCallFinished != null:
return toolCallFinished(_that);case MessageEvent_Done() when done != null:
return done(_that);case MessageEvent_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( MessageEvent_Snapshot value)  snapshot,required TResult Function( MessageEvent_ContentDelta value)  contentDelta,required TResult Function( MessageEvent_ToolCallStarted value)  toolCallStarted,required TResult Function( MessageEvent_ToolCallFinished value)  toolCallFinished,required TResult Function( MessageEvent_Done value)  done,required TResult Function( MessageEvent_Error value)  error,}){
final _that = this;
switch (_that) {
case MessageEvent_Snapshot():
return snapshot(_that);case MessageEvent_ContentDelta():
return contentDelta(_that);case MessageEvent_ToolCallStarted():
return toolCallStarted(_that);case MessageEvent_ToolCallFinished():
return toolCallFinished(_that);case MessageEvent_Done():
return done(_that);case MessageEvent_Error():
return error(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( MessageEvent_Snapshot value)?  snapshot,TResult? Function( MessageEvent_ContentDelta value)?  contentDelta,TResult? Function( MessageEvent_ToolCallStarted value)?  toolCallStarted,TResult? Function( MessageEvent_ToolCallFinished value)?  toolCallFinished,TResult? Function( MessageEvent_Done value)?  done,TResult? Function( MessageEvent_Error value)?  error,}){
final _that = this;
switch (_that) {
case MessageEvent_Snapshot() when snapshot != null:
return snapshot(_that);case MessageEvent_ContentDelta() when contentDelta != null:
return contentDelta(_that);case MessageEvent_ToolCallStarted() when toolCallStarted != null:
return toolCallStarted(_that);case MessageEvent_ToolCallFinished() when toolCallFinished != null:
return toolCallFinished(_that);case MessageEvent_Done() when done != null:
return done(_that);case MessageEvent_Error() when error != null:
return error(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( MessageDto message)?  snapshot,TResult Function( ContentDeltaDto delta)?  contentDelta,TResult Function( ToolCallSummaryDto toolCall)?  toolCallStarted,TResult Function( ToolCallFinishedDto toolCall)?  toolCallFinished,TResult Function( MessageDto message)?  done,TResult Function( ClientError error)?  error,required TResult orElse(),}) {final _that = this;
switch (_that) {
case MessageEvent_Snapshot() when snapshot != null:
return snapshot(_that.message);case MessageEvent_ContentDelta() when contentDelta != null:
return contentDelta(_that.delta);case MessageEvent_ToolCallStarted() when toolCallStarted != null:
return toolCallStarted(_that.toolCall);case MessageEvent_ToolCallFinished() when toolCallFinished != null:
return toolCallFinished(_that.toolCall);case MessageEvent_Done() when done != null:
return done(_that.message);case MessageEvent_Error() when error != null:
return error(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( MessageDto message)  snapshot,required TResult Function( ContentDeltaDto delta)  contentDelta,required TResult Function( ToolCallSummaryDto toolCall)  toolCallStarted,required TResult Function( ToolCallFinishedDto toolCall)  toolCallFinished,required TResult Function( MessageDto message)  done,required TResult Function( ClientError error)  error,}) {final _that = this;
switch (_that) {
case MessageEvent_Snapshot():
return snapshot(_that.message);case MessageEvent_ContentDelta():
return contentDelta(_that.delta);case MessageEvent_ToolCallStarted():
return toolCallStarted(_that.toolCall);case MessageEvent_ToolCallFinished():
return toolCallFinished(_that.toolCall);case MessageEvent_Done():
return done(_that.message);case MessageEvent_Error():
return error(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( MessageDto message)?  snapshot,TResult? Function( ContentDeltaDto delta)?  contentDelta,TResult? Function( ToolCallSummaryDto toolCall)?  toolCallStarted,TResult? Function( ToolCallFinishedDto toolCall)?  toolCallFinished,TResult? Function( MessageDto message)?  done,TResult? Function( ClientError error)?  error,}) {final _that = this;
switch (_that) {
case MessageEvent_Snapshot() when snapshot != null:
return snapshot(_that.message);case MessageEvent_ContentDelta() when contentDelta != null:
return contentDelta(_that.delta);case MessageEvent_ToolCallStarted() when toolCallStarted != null:
return toolCallStarted(_that.toolCall);case MessageEvent_ToolCallFinished() when toolCallFinished != null:
return toolCallFinished(_that.toolCall);case MessageEvent_Done() when done != null:
return done(_that.message);case MessageEvent_Error() when error != null:
return error(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class MessageEvent_Snapshot extends MessageEvent {
  const MessageEvent_Snapshot({required this.message}): super._();
  

 final  MessageDto message;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_SnapshotCopyWith<MessageEvent_Snapshot> get copyWith => _$MessageEvent_SnapshotCopyWithImpl<MessageEvent_Snapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_Snapshot&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'MessageEvent.snapshot(message: $message)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_SnapshotCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_SnapshotCopyWith(MessageEvent_Snapshot value, $Res Function(MessageEvent_Snapshot) _then) = _$MessageEvent_SnapshotCopyWithImpl;
@useResult
$Res call({
 MessageDto message
});




}
/// @nodoc
class _$MessageEvent_SnapshotCopyWithImpl<$Res>
    implements $MessageEvent_SnapshotCopyWith<$Res> {
  _$MessageEvent_SnapshotCopyWithImpl(this._self, this._then);

  final MessageEvent_Snapshot _self;
  final $Res Function(MessageEvent_Snapshot) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MessageEvent_Snapshot(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as MessageDto,
  ));
}


}

/// @nodoc


class MessageEvent_ContentDelta extends MessageEvent {
  const MessageEvent_ContentDelta({required this.delta}): super._();
  

 final  ContentDeltaDto delta;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_ContentDeltaCopyWith<MessageEvent_ContentDelta> get copyWith => _$MessageEvent_ContentDeltaCopyWithImpl<MessageEvent_ContentDelta>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_ContentDelta&&(identical(other.delta, delta) || other.delta == delta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,delta);
}

@override
String toString() {
    return 'MessageEvent.contentDelta(delta: $delta)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_ContentDeltaCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_ContentDeltaCopyWith(MessageEvent_ContentDelta value, $Res Function(MessageEvent_ContentDelta) _then) = _$MessageEvent_ContentDeltaCopyWithImpl;
@useResult
$Res call({
 ContentDeltaDto delta
});




}
/// @nodoc
class _$MessageEvent_ContentDeltaCopyWithImpl<$Res>
    implements $MessageEvent_ContentDeltaCopyWith<$Res> {
  _$MessageEvent_ContentDeltaCopyWithImpl(this._self, this._then);

  final MessageEvent_ContentDelta _self;
  final $Res Function(MessageEvent_ContentDelta) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? delta = null,}) {
  return _then(MessageEvent_ContentDelta(
delta: null == delta ? _self.delta : delta // ignore: cast_nullable_to_non_nullable
as ContentDeltaDto,
  ));
}


}

/// @nodoc


class MessageEvent_ToolCallStarted extends MessageEvent {
  const MessageEvent_ToolCallStarted({required this.toolCall}): super._();
  

 final  ToolCallSummaryDto toolCall;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_ToolCallStartedCopyWith<MessageEvent_ToolCallStarted> get copyWith => _$MessageEvent_ToolCallStartedCopyWithImpl<MessageEvent_ToolCallStarted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_ToolCallStarted&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toolCall);
}

@override
String toString() {
    return 'MessageEvent.toolCallStarted(toolCall: $toolCall)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_ToolCallStartedCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_ToolCallStartedCopyWith(MessageEvent_ToolCallStarted value, $Res Function(MessageEvent_ToolCallStarted) _then) = _$MessageEvent_ToolCallStartedCopyWithImpl;
@useResult
$Res call({
 ToolCallSummaryDto toolCall
});




}
/// @nodoc
class _$MessageEvent_ToolCallStartedCopyWithImpl<$Res>
    implements $MessageEvent_ToolCallStartedCopyWith<$Res> {
  _$MessageEvent_ToolCallStartedCopyWithImpl(this._self, this._then);

  final MessageEvent_ToolCallStarted _self;
  final $Res Function(MessageEvent_ToolCallStarted) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? toolCall = null,}) {
  return _then(MessageEvent_ToolCallStarted(
toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallSummaryDto,
  ));
}


}

/// @nodoc


class MessageEvent_ToolCallFinished extends MessageEvent {
  const MessageEvent_ToolCallFinished({required this.toolCall}): super._();
  

 final  ToolCallFinishedDto toolCall;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_ToolCallFinishedCopyWith<MessageEvent_ToolCallFinished> get copyWith => _$MessageEvent_ToolCallFinishedCopyWithImpl<MessageEvent_ToolCallFinished>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_ToolCallFinished&&(identical(other.toolCall, toolCall) || other.toolCall == toolCall));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toolCall);
}

@override
String toString() {
    return 'MessageEvent.toolCallFinished(toolCall: $toolCall)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_ToolCallFinishedCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_ToolCallFinishedCopyWith(MessageEvent_ToolCallFinished value, $Res Function(MessageEvent_ToolCallFinished) _then) = _$MessageEvent_ToolCallFinishedCopyWithImpl;
@useResult
$Res call({
 ToolCallFinishedDto toolCall
});




}
/// @nodoc
class _$MessageEvent_ToolCallFinishedCopyWithImpl<$Res>
    implements $MessageEvent_ToolCallFinishedCopyWith<$Res> {
  _$MessageEvent_ToolCallFinishedCopyWithImpl(this._self, this._then);

  final MessageEvent_ToolCallFinished _self;
  final $Res Function(MessageEvent_ToolCallFinished) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? toolCall = null,}) {
  return _then(MessageEvent_ToolCallFinished(
toolCall: null == toolCall ? _self.toolCall : toolCall // ignore: cast_nullable_to_non_nullable
as ToolCallFinishedDto,
  ));
}


}

/// @nodoc


class MessageEvent_Done extends MessageEvent {
  const MessageEvent_Done({required this.message}): super._();
  

 final  MessageDto message;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_DoneCopyWith<MessageEvent_Done> get copyWith => _$MessageEvent_DoneCopyWithImpl<MessageEvent_Done>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_Done&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'MessageEvent.done(message: $message)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_DoneCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_DoneCopyWith(MessageEvent_Done value, $Res Function(MessageEvent_Done) _then) = _$MessageEvent_DoneCopyWithImpl;
@useResult
$Res call({
 MessageDto message
});




}
/// @nodoc
class _$MessageEvent_DoneCopyWithImpl<$Res>
    implements $MessageEvent_DoneCopyWith<$Res> {
  _$MessageEvent_DoneCopyWithImpl(this._self, this._then);

  final MessageEvent_Done _self;
  final $Res Function(MessageEvent_Done) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(MessageEvent_Done(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as MessageDto,
  ));
}


}

/// @nodoc


class MessageEvent_Error extends MessageEvent {
  const MessageEvent_Error({required this.error}): super._();
  

 final  ClientError error;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MessageEvent_ErrorCopyWith<MessageEvent_Error> get copyWith => _$MessageEvent_ErrorCopyWithImpl<MessageEvent_Error>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MessageEvent_Error&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'MessageEvent.error(error: $error)';
}


}

/// @nodoc
abstract mixin class $MessageEvent_ErrorCopyWith<$Res> implements $MessageEventCopyWith<$Res> {
  factory $MessageEvent_ErrorCopyWith(MessageEvent_Error value, $Res Function(MessageEvent_Error) _then) = _$MessageEvent_ErrorCopyWithImpl;
@useResult
$Res call({
 ClientError error
});


$ClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$MessageEvent_ErrorCopyWithImpl<$Res>
    implements $MessageEvent_ErrorCopyWith<$Res> {
  _$MessageEvent_ErrorCopyWithImpl(this._self, this._then);

  final MessageEvent_Error _self;
  final $Res Function(MessageEvent_Error) _then;

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(MessageEvent_Error(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as ClientError,
  ));
}

/// Create a copy of MessageEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ClientErrorCopyWith<$Res> get error {
  
  return $ClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
