// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'call_session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$CallSession {

 CallStatus get status; String get channelId; String get role;// 'Citizen', 'Rescuer', 'Dispatcher'
 bool get isVideoEnabled; bool get isAudioEnabled; bool get isSpeakerEnabled; bool get isFrontCamera; int? get localUid; int? get remoteUid; String? get errorMessage;
/// Create a copy of CallSession
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CallSessionCopyWith<CallSession> get copyWith => _$CallSessionCopyWithImpl<CallSession>(this as CallSession, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CallSession&&(identical(other.status, status) || other.status == status)&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.role, role) || other.role == role)&&(identical(other.isVideoEnabled, isVideoEnabled) || other.isVideoEnabled == isVideoEnabled)&&(identical(other.isAudioEnabled, isAudioEnabled) || other.isAudioEnabled == isAudioEnabled)&&(identical(other.isSpeakerEnabled, isSpeakerEnabled) || other.isSpeakerEnabled == isSpeakerEnabled)&&(identical(other.isFrontCamera, isFrontCamera) || other.isFrontCamera == isFrontCamera)&&(identical(other.localUid, localUid) || other.localUid == localUid)&&(identical(other.remoteUid, remoteUid) || other.remoteUid == remoteUid)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,status,channelId,role,isVideoEnabled,isAudioEnabled,isSpeakerEnabled,isFrontCamera,localUid,remoteUid,errorMessage);

@override
String toString() {
  return 'CallSession(status: $status, channelId: $channelId, role: $role, isVideoEnabled: $isVideoEnabled, isAudioEnabled: $isAudioEnabled, isSpeakerEnabled: $isSpeakerEnabled, isFrontCamera: $isFrontCamera, localUid: $localUid, remoteUid: $remoteUid, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class $CallSessionCopyWith<$Res>  {
  factory $CallSessionCopyWith(CallSession value, $Res Function(CallSession) _then) = _$CallSessionCopyWithImpl;
@useResult
$Res call({
 CallStatus status, String channelId, String role, bool isVideoEnabled, bool isAudioEnabled, bool isSpeakerEnabled, bool isFrontCamera, int? localUid, int? remoteUid, String? errorMessage
});




}
/// @nodoc
class _$CallSessionCopyWithImpl<$Res>
    implements $CallSessionCopyWith<$Res> {
  _$CallSessionCopyWithImpl(this._self, this._then);

  final CallSession _self;
  final $Res Function(CallSession) _then;

/// Create a copy of CallSession
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? status = null,Object? channelId = null,Object? role = null,Object? isVideoEnabled = null,Object? isAudioEnabled = null,Object? isSpeakerEnabled = null,Object? isFrontCamera = null,Object? localUid = freezed,Object? remoteUid = freezed,Object? errorMessage = freezed,}) {
  return _then(_self.copyWith(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as CallStatus,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,isVideoEnabled: null == isVideoEnabled ? _self.isVideoEnabled : isVideoEnabled // ignore: cast_nullable_to_non_nullable
as bool,isAudioEnabled: null == isAudioEnabled ? _self.isAudioEnabled : isAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,isSpeakerEnabled: null == isSpeakerEnabled ? _self.isSpeakerEnabled : isSpeakerEnabled // ignore: cast_nullable_to_non_nullable
as bool,isFrontCamera: null == isFrontCamera ? _self.isFrontCamera : isFrontCamera // ignore: cast_nullable_to_non_nullable
as bool,localUid: freezed == localUid ? _self.localUid : localUid // ignore: cast_nullable_to_non_nullable
as int?,remoteUid: freezed == remoteUid ? _self.remoteUid : remoteUid // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CallSession].
extension CallSessionPatterns on CallSession {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CallSession value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CallSession() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CallSession value)  $default,){
final _that = this;
switch (_that) {
case _CallSession():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CallSession value)?  $default,){
final _that = this;
switch (_that) {
case _CallSession() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CallStatus status,  String channelId,  String role,  bool isVideoEnabled,  bool isAudioEnabled,  bool isSpeakerEnabled,  bool isFrontCamera,  int? localUid,  int? remoteUid,  String? errorMessage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CallSession() when $default != null:
return $default(_that.status,_that.channelId,_that.role,_that.isVideoEnabled,_that.isAudioEnabled,_that.isSpeakerEnabled,_that.isFrontCamera,_that.localUid,_that.remoteUid,_that.errorMessage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CallStatus status,  String channelId,  String role,  bool isVideoEnabled,  bool isAudioEnabled,  bool isSpeakerEnabled,  bool isFrontCamera,  int? localUid,  int? remoteUid,  String? errorMessage)  $default,) {final _that = this;
switch (_that) {
case _CallSession():
return $default(_that.status,_that.channelId,_that.role,_that.isVideoEnabled,_that.isAudioEnabled,_that.isSpeakerEnabled,_that.isFrontCamera,_that.localUid,_that.remoteUid,_that.errorMessage);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CallStatus status,  String channelId,  String role,  bool isVideoEnabled,  bool isAudioEnabled,  bool isSpeakerEnabled,  bool isFrontCamera,  int? localUid,  int? remoteUid,  String? errorMessage)?  $default,) {final _that = this;
switch (_that) {
case _CallSession() when $default != null:
return $default(_that.status,_that.channelId,_that.role,_that.isVideoEnabled,_that.isAudioEnabled,_that.isSpeakerEnabled,_that.isFrontCamera,_that.localUid,_that.remoteUid,_that.errorMessage);case _:
  return null;

}
}

}

/// @nodoc


class _CallSession extends CallSession {
  const _CallSession({required this.status, required this.channelId, required this.role, required this.isVideoEnabled, required this.isAudioEnabled, required this.isSpeakerEnabled, required this.isFrontCamera, this.localUid, this.remoteUid, this.errorMessage}): super._();
  

@override final  CallStatus status;
@override final  String channelId;
@override final  String role;
// 'Citizen', 'Rescuer', 'Dispatcher'
@override final  bool isVideoEnabled;
@override final  bool isAudioEnabled;
@override final  bool isSpeakerEnabled;
@override final  bool isFrontCamera;
@override final  int? localUid;
@override final  int? remoteUid;
@override final  String? errorMessage;

/// Create a copy of CallSession
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CallSessionCopyWith<_CallSession> get copyWith => __$CallSessionCopyWithImpl<_CallSession>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CallSession&&(identical(other.status, status) || other.status == status)&&(identical(other.channelId, channelId) || other.channelId == channelId)&&(identical(other.role, role) || other.role == role)&&(identical(other.isVideoEnabled, isVideoEnabled) || other.isVideoEnabled == isVideoEnabled)&&(identical(other.isAudioEnabled, isAudioEnabled) || other.isAudioEnabled == isAudioEnabled)&&(identical(other.isSpeakerEnabled, isSpeakerEnabled) || other.isSpeakerEnabled == isSpeakerEnabled)&&(identical(other.isFrontCamera, isFrontCamera) || other.isFrontCamera == isFrontCamera)&&(identical(other.localUid, localUid) || other.localUid == localUid)&&(identical(other.remoteUid, remoteUid) || other.remoteUid == remoteUid)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage));
}


@override
int get hashCode => Object.hash(runtimeType,status,channelId,role,isVideoEnabled,isAudioEnabled,isSpeakerEnabled,isFrontCamera,localUid,remoteUid,errorMessage);

@override
String toString() {
  return 'CallSession(status: $status, channelId: $channelId, role: $role, isVideoEnabled: $isVideoEnabled, isAudioEnabled: $isAudioEnabled, isSpeakerEnabled: $isSpeakerEnabled, isFrontCamera: $isFrontCamera, localUid: $localUid, remoteUid: $remoteUid, errorMessage: $errorMessage)';
}


}

/// @nodoc
abstract mixin class _$CallSessionCopyWith<$Res> implements $CallSessionCopyWith<$Res> {
  factory _$CallSessionCopyWith(_CallSession value, $Res Function(_CallSession) _then) = __$CallSessionCopyWithImpl;
@override @useResult
$Res call({
 CallStatus status, String channelId, String role, bool isVideoEnabled, bool isAudioEnabled, bool isSpeakerEnabled, bool isFrontCamera, int? localUid, int? remoteUid, String? errorMessage
});




}
/// @nodoc
class __$CallSessionCopyWithImpl<$Res>
    implements _$CallSessionCopyWith<$Res> {
  __$CallSessionCopyWithImpl(this._self, this._then);

  final _CallSession _self;
  final $Res Function(_CallSession) _then;

/// Create a copy of CallSession
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? status = null,Object? channelId = null,Object? role = null,Object? isVideoEnabled = null,Object? isAudioEnabled = null,Object? isSpeakerEnabled = null,Object? isFrontCamera = null,Object? localUid = freezed,Object? remoteUid = freezed,Object? errorMessage = freezed,}) {
  return _then(_CallSession(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as CallStatus,channelId: null == channelId ? _self.channelId : channelId // ignore: cast_nullable_to_non_nullable
as String,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,isVideoEnabled: null == isVideoEnabled ? _self.isVideoEnabled : isVideoEnabled // ignore: cast_nullable_to_non_nullable
as bool,isAudioEnabled: null == isAudioEnabled ? _self.isAudioEnabled : isAudioEnabled // ignore: cast_nullable_to_non_nullable
as bool,isSpeakerEnabled: null == isSpeakerEnabled ? _self.isSpeakerEnabled : isSpeakerEnabled // ignore: cast_nullable_to_non_nullable
as bool,isFrontCamera: null == isFrontCamera ? _self.isFrontCamera : isFrontCamera // ignore: cast_nullable_to_non_nullable
as bool,localUid: freezed == localUid ? _self.localUid : localUid // ignore: cast_nullable_to_non_nullable
as int?,remoteUid: freezed == remoteUid ? _self.remoteUid : remoteUid // ignore: cast_nullable_to_non_nullable
as int?,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
