// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'continuity.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsCapabilityState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsCapabilityState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsCapabilityState()';
}


}

/// @nodoc
class $RsCapabilityStateCopyWith<$Res>  {
$RsCapabilityStateCopyWith(RsCapabilityState _, $Res Function(RsCapabilityState) __);
}


/// Adds pattern-matching-related methods to [RsCapabilityState].
extension RsCapabilityStatePatterns on RsCapabilityState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsCapabilityState_Available value)?  available,TResult Function( RsCapabilityState_PermissionRequired value)?  permissionRequired,TResult Function( RsCapabilityState_Limited value)?  limited,TResult Function( RsCapabilityState_Unavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsCapabilityState_Available() when available != null:
return available(_that);case RsCapabilityState_PermissionRequired() when permissionRequired != null:
return permissionRequired(_that);case RsCapabilityState_Limited() when limited != null:
return limited(_that);case RsCapabilityState_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsCapabilityState_Available value)  available,required TResult Function( RsCapabilityState_PermissionRequired value)  permissionRequired,required TResult Function( RsCapabilityState_Limited value)  limited,required TResult Function( RsCapabilityState_Unavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case RsCapabilityState_Available():
return available(_that);case RsCapabilityState_PermissionRequired():
return permissionRequired(_that);case RsCapabilityState_Limited():
return limited(_that);case RsCapabilityState_Unavailable():
return unavailable(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsCapabilityState_Available value)?  available,TResult? Function( RsCapabilityState_PermissionRequired value)?  permissionRequired,TResult? Function( RsCapabilityState_Limited value)?  limited,TResult? Function( RsCapabilityState_Unavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case RsCapabilityState_Available() when available != null:
return available(_that);case RsCapabilityState_PermissionRequired() when permissionRequired != null:
return permissionRequired(_that);case RsCapabilityState_Limited() when limited != null:
return limited(_that);case RsCapabilityState_Unavailable() when unavailable != null:
return unavailable(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  available,TResult Function( String reason)?  permissionRequired,TResult Function( String reason)?  limited,TResult Function( String reason)?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsCapabilityState_Available() when available != null:
return available();case RsCapabilityState_PermissionRequired() when permissionRequired != null:
return permissionRequired(_that.reason);case RsCapabilityState_Limited() when limited != null:
return limited(_that.reason);case RsCapabilityState_Unavailable() when unavailable != null:
return unavailable(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  available,required TResult Function( String reason)  permissionRequired,required TResult Function( String reason)  limited,required TResult Function( String reason)  unavailable,}) {final _that = this;
switch (_that) {
case RsCapabilityState_Available():
return available();case RsCapabilityState_PermissionRequired():
return permissionRequired(_that.reason);case RsCapabilityState_Limited():
return limited(_that.reason);case RsCapabilityState_Unavailable():
return unavailable(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  available,TResult? Function( String reason)?  permissionRequired,TResult? Function( String reason)?  limited,TResult? Function( String reason)?  unavailable,}) {final _that = this;
switch (_that) {
case RsCapabilityState_Available() when available != null:
return available();case RsCapabilityState_PermissionRequired() when permissionRequired != null:
return permissionRequired(_that.reason);case RsCapabilityState_Limited() when limited != null:
return limited(_that.reason);case RsCapabilityState_Unavailable() when unavailable != null:
return unavailable(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RsCapabilityState_Available extends RsCapabilityState {
  const RsCapabilityState_Available(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsCapabilityState_Available);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsCapabilityState.available()';
}


}




/// @nodoc


class RsCapabilityState_PermissionRequired extends RsCapabilityState {
  const RsCapabilityState_PermissionRequired({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsCapabilityState_PermissionRequiredCopyWith<RsCapabilityState_PermissionRequired> get copyWith => _$RsCapabilityState_PermissionRequiredCopyWithImpl<RsCapabilityState_PermissionRequired>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsCapabilityState_PermissionRequired&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RsCapabilityState.permissionRequired(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsCapabilityState_PermissionRequiredCopyWith<$Res> implements $RsCapabilityStateCopyWith<$Res> {
  factory $RsCapabilityState_PermissionRequiredCopyWith(RsCapabilityState_PermissionRequired value, $Res Function(RsCapabilityState_PermissionRequired) _then) = _$RsCapabilityState_PermissionRequiredCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RsCapabilityState_PermissionRequiredCopyWithImpl<$Res>
    implements $RsCapabilityState_PermissionRequiredCopyWith<$Res> {
  _$RsCapabilityState_PermissionRequiredCopyWithImpl(this._self, this._then);

  final RsCapabilityState_PermissionRequired _self;
  final $Res Function(RsCapabilityState_PermissionRequired) _then;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RsCapabilityState_PermissionRequired(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsCapabilityState_Limited extends RsCapabilityState {
  const RsCapabilityState_Limited({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsCapabilityState_LimitedCopyWith<RsCapabilityState_Limited> get copyWith => _$RsCapabilityState_LimitedCopyWithImpl<RsCapabilityState_Limited>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsCapabilityState_Limited&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RsCapabilityState.limited(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsCapabilityState_LimitedCopyWith<$Res> implements $RsCapabilityStateCopyWith<$Res> {
  factory $RsCapabilityState_LimitedCopyWith(RsCapabilityState_Limited value, $Res Function(RsCapabilityState_Limited) _then) = _$RsCapabilityState_LimitedCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RsCapabilityState_LimitedCopyWithImpl<$Res>
    implements $RsCapabilityState_LimitedCopyWith<$Res> {
  _$RsCapabilityState_LimitedCopyWithImpl(this._self, this._then);

  final RsCapabilityState_Limited _self;
  final $Res Function(RsCapabilityState_Limited) _then;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RsCapabilityState_Limited(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsCapabilityState_Unavailable extends RsCapabilityState {
  const RsCapabilityState_Unavailable({required this.reason}): super._();
  

 final  String reason;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsCapabilityState_UnavailableCopyWith<RsCapabilityState_Unavailable> get copyWith => _$RsCapabilityState_UnavailableCopyWithImpl<RsCapabilityState_Unavailable>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsCapabilityState_Unavailable&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,reason);

@override
String toString() {
  return 'RsCapabilityState.unavailable(reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsCapabilityState_UnavailableCopyWith<$Res> implements $RsCapabilityStateCopyWith<$Res> {
  factory $RsCapabilityState_UnavailableCopyWith(RsCapabilityState_Unavailable value, $Res Function(RsCapabilityState_Unavailable) _then) = _$RsCapabilityState_UnavailableCopyWithImpl;
@useResult
$Res call({
 String reason
});




}
/// @nodoc
class _$RsCapabilityState_UnavailableCopyWithImpl<$Res>
    implements $RsCapabilityState_UnavailableCopyWith<$Res> {
  _$RsCapabilityState_UnavailableCopyWithImpl(this._self, this._then);

  final RsCapabilityState_Unavailable _self;
  final $Res Function(RsCapabilityState_Unavailable) _then;

/// Create a copy of RsCapabilityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(RsCapabilityState_Unavailable(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsContinuityEvent {

 String get remoteRelayId;
/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEventCopyWith<RsContinuityEvent> get copyWith => _$RsContinuityEventCopyWithImpl<RsContinuityEvent>(this as RsContinuityEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId);

@override
String toString() {
  return 'RsContinuityEvent(remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEventCopyWith<$Res>  {
  factory $RsContinuityEventCopyWith(RsContinuityEvent value, $Res Function(RsContinuityEvent) _then) = _$RsContinuityEventCopyWithImpl;
@useResult
$Res call({
 String remoteRelayId
});




}
/// @nodoc
class _$RsContinuityEventCopyWithImpl<$Res>
    implements $RsContinuityEventCopyWith<$Res> {
  _$RsContinuityEventCopyWithImpl(this._self, this._then);

  final RsContinuityEvent _self;
  final $Res Function(RsContinuityEvent) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? remoteRelayId = null,}) {
  return _then(_self.copyWith(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RsContinuityEvent].
extension RsContinuityEventPatterns on RsContinuityEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsContinuityEvent_SessionEstablished value)?  sessionEstablished,TResult Function( RsContinuityEvent_SessionEnded value)?  sessionEnded,TResult Function( RsContinuityEvent_ManifestReceived value)?  manifestReceived,TResult Function( RsContinuityEvent_BatteryChanged value)?  batteryChanged,TResult Function( RsContinuityEvent_ClipboardOffered value)?  clipboardOffered,TResult Function( RsContinuityEvent_NotificationPosted value)?  notificationPosted,TResult Function( RsContinuityEvent_NotificationRemoved value)?  notificationRemoved,TResult Function( RsContinuityEvent_ConversationsPage value)?  conversationsPage,TResult Function( RsContinuityEvent_MessagesPage value)?  messagesPage,TResult Function( RsContinuityEvent_MessageReceived value)?  messageReceived,TResult Function( RsContinuityEvent_SmsSendCompleted value)?  smsSendCompleted,TResult Function( RsContinuityEvent_CallStateChanged value)?  callStateChanged,TResult Function( RsContinuityEvent_CallActionCompleted value)?  callActionCompleted,TResult Function( RsContinuityEvent_PeerError value)?  peerError,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished() when sessionEstablished != null:
return sessionEstablished(_that);case RsContinuityEvent_SessionEnded() when sessionEnded != null:
return sessionEnded(_that);case RsContinuityEvent_ManifestReceived() when manifestReceived != null:
return manifestReceived(_that);case RsContinuityEvent_BatteryChanged() when batteryChanged != null:
return batteryChanged(_that);case RsContinuityEvent_ClipboardOffered() when clipboardOffered != null:
return clipboardOffered(_that);case RsContinuityEvent_NotificationPosted() when notificationPosted != null:
return notificationPosted(_that);case RsContinuityEvent_NotificationRemoved() when notificationRemoved != null:
return notificationRemoved(_that);case RsContinuityEvent_ConversationsPage() when conversationsPage != null:
return conversationsPage(_that);case RsContinuityEvent_MessagesPage() when messagesPage != null:
return messagesPage(_that);case RsContinuityEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case RsContinuityEvent_SmsSendCompleted() when smsSendCompleted != null:
return smsSendCompleted(_that);case RsContinuityEvent_CallStateChanged() when callStateChanged != null:
return callStateChanged(_that);case RsContinuityEvent_CallActionCompleted() when callActionCompleted != null:
return callActionCompleted(_that);case RsContinuityEvent_PeerError() when peerError != null:
return peerError(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsContinuityEvent_SessionEstablished value)  sessionEstablished,required TResult Function( RsContinuityEvent_SessionEnded value)  sessionEnded,required TResult Function( RsContinuityEvent_ManifestReceived value)  manifestReceived,required TResult Function( RsContinuityEvent_BatteryChanged value)  batteryChanged,required TResult Function( RsContinuityEvent_ClipboardOffered value)  clipboardOffered,required TResult Function( RsContinuityEvent_NotificationPosted value)  notificationPosted,required TResult Function( RsContinuityEvent_NotificationRemoved value)  notificationRemoved,required TResult Function( RsContinuityEvent_ConversationsPage value)  conversationsPage,required TResult Function( RsContinuityEvent_MessagesPage value)  messagesPage,required TResult Function( RsContinuityEvent_MessageReceived value)  messageReceived,required TResult Function( RsContinuityEvent_SmsSendCompleted value)  smsSendCompleted,required TResult Function( RsContinuityEvent_CallStateChanged value)  callStateChanged,required TResult Function( RsContinuityEvent_CallActionCompleted value)  callActionCompleted,required TResult Function( RsContinuityEvent_PeerError value)  peerError,}){
final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished():
return sessionEstablished(_that);case RsContinuityEvent_SessionEnded():
return sessionEnded(_that);case RsContinuityEvent_ManifestReceived():
return manifestReceived(_that);case RsContinuityEvent_BatteryChanged():
return batteryChanged(_that);case RsContinuityEvent_ClipboardOffered():
return clipboardOffered(_that);case RsContinuityEvent_NotificationPosted():
return notificationPosted(_that);case RsContinuityEvent_NotificationRemoved():
return notificationRemoved(_that);case RsContinuityEvent_ConversationsPage():
return conversationsPage(_that);case RsContinuityEvent_MessagesPage():
return messagesPage(_that);case RsContinuityEvent_MessageReceived():
return messageReceived(_that);case RsContinuityEvent_SmsSendCompleted():
return smsSendCompleted(_that);case RsContinuityEvent_CallStateChanged():
return callStateChanged(_that);case RsContinuityEvent_CallActionCompleted():
return callActionCompleted(_that);case RsContinuityEvent_PeerError():
return peerError(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsContinuityEvent_SessionEstablished value)?  sessionEstablished,TResult? Function( RsContinuityEvent_SessionEnded value)?  sessionEnded,TResult? Function( RsContinuityEvent_ManifestReceived value)?  manifestReceived,TResult? Function( RsContinuityEvent_BatteryChanged value)?  batteryChanged,TResult? Function( RsContinuityEvent_ClipboardOffered value)?  clipboardOffered,TResult? Function( RsContinuityEvent_NotificationPosted value)?  notificationPosted,TResult? Function( RsContinuityEvent_NotificationRemoved value)?  notificationRemoved,TResult? Function( RsContinuityEvent_ConversationsPage value)?  conversationsPage,TResult? Function( RsContinuityEvent_MessagesPage value)?  messagesPage,TResult? Function( RsContinuityEvent_MessageReceived value)?  messageReceived,TResult? Function( RsContinuityEvent_SmsSendCompleted value)?  smsSendCompleted,TResult? Function( RsContinuityEvent_CallStateChanged value)?  callStateChanged,TResult? Function( RsContinuityEvent_CallActionCompleted value)?  callActionCompleted,TResult? Function( RsContinuityEvent_PeerError value)?  peerError,}){
final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished() when sessionEstablished != null:
return sessionEstablished(_that);case RsContinuityEvent_SessionEnded() when sessionEnded != null:
return sessionEnded(_that);case RsContinuityEvent_ManifestReceived() when manifestReceived != null:
return manifestReceived(_that);case RsContinuityEvent_BatteryChanged() when batteryChanged != null:
return batteryChanged(_that);case RsContinuityEvent_ClipboardOffered() when clipboardOffered != null:
return clipboardOffered(_that);case RsContinuityEvent_NotificationPosted() when notificationPosted != null:
return notificationPosted(_that);case RsContinuityEvent_NotificationRemoved() when notificationRemoved != null:
return notificationRemoved(_that);case RsContinuityEvent_ConversationsPage() when conversationsPage != null:
return conversationsPage(_that);case RsContinuityEvent_MessagesPage() when messagesPage != null:
return messagesPage(_that);case RsContinuityEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that);case RsContinuityEvent_SmsSendCompleted() when smsSendCompleted != null:
return smsSendCompleted(_that);case RsContinuityEvent_CallStateChanged() when callStateChanged != null:
return callStateChanged(_that);case RsContinuityEvent_CallActionCompleted() when callActionCompleted != null:
return callActionCompleted(_that);case RsContinuityEvent_PeerError() when peerError != null:
return peerError(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String remoteRelayId,  bool directPath,  bool localPath)?  sessionEstablished,TResult Function( String remoteRelayId,  String reason)?  sessionEnded,TResult Function( String remoteRelayId,  RsCapabilityManifest manifest)?  manifestReceived,TResult Function( String remoteRelayId,  int? percentage,  RsChargingState charging)?  batteryChanged,TResult Function( String remoteRelayId,  String text,  bool explicit)?  clipboardOffered,TResult Function( String remoteRelayId,  String key,  String appLabel,  String? title,  String? body,  BigInt postedAtMs,  bool clearable)?  notificationPosted,TResult Function( String remoteRelayId,  String key)?  notificationRemoved,TResult Function( String remoteRelayId,  List<RsSmsConversation> conversations,  bool hasMore)?  conversationsPage,TResult Function( String remoteRelayId,  String conversationId,  List<RsSmsMessage> messages,  bool hasMore)?  messagesPage,TResult Function( String remoteRelayId,  RsSmsMessage message)?  messageReceived,TResult Function( String remoteRelayId,  String requestId,  bool sent,  String? detail)?  smsSendCompleted,TResult Function( String remoteRelayId,  RsCallState state)?  callStateChanged,TResult Function( String remoteRelayId,  String requestId,  bool accepted,  String? detail)?  callActionCompleted,TResult Function( String remoteRelayId,  String code,  String detail)?  peerError,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished() when sessionEstablished != null:
return sessionEstablished(_that.remoteRelayId,_that.directPath,_that.localPath);case RsContinuityEvent_SessionEnded() when sessionEnded != null:
return sessionEnded(_that.remoteRelayId,_that.reason);case RsContinuityEvent_ManifestReceived() when manifestReceived != null:
return manifestReceived(_that.remoteRelayId,_that.manifest);case RsContinuityEvent_BatteryChanged() when batteryChanged != null:
return batteryChanged(_that.remoteRelayId,_that.percentage,_that.charging);case RsContinuityEvent_ClipboardOffered() when clipboardOffered != null:
return clipboardOffered(_that.remoteRelayId,_that.text,_that.explicit);case RsContinuityEvent_NotificationPosted() when notificationPosted != null:
return notificationPosted(_that.remoteRelayId,_that.key,_that.appLabel,_that.title,_that.body,_that.postedAtMs,_that.clearable);case RsContinuityEvent_NotificationRemoved() when notificationRemoved != null:
return notificationRemoved(_that.remoteRelayId,_that.key);case RsContinuityEvent_ConversationsPage() when conversationsPage != null:
return conversationsPage(_that.remoteRelayId,_that.conversations,_that.hasMore);case RsContinuityEvent_MessagesPage() when messagesPage != null:
return messagesPage(_that.remoteRelayId,_that.conversationId,_that.messages,_that.hasMore);case RsContinuityEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.remoteRelayId,_that.message);case RsContinuityEvent_SmsSendCompleted() when smsSendCompleted != null:
return smsSendCompleted(_that.remoteRelayId,_that.requestId,_that.sent,_that.detail);case RsContinuityEvent_CallStateChanged() when callStateChanged != null:
return callStateChanged(_that.remoteRelayId,_that.state);case RsContinuityEvent_CallActionCompleted() when callActionCompleted != null:
return callActionCompleted(_that.remoteRelayId,_that.requestId,_that.accepted,_that.detail);case RsContinuityEvent_PeerError() when peerError != null:
return peerError(_that.remoteRelayId,_that.code,_that.detail);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String remoteRelayId,  bool directPath,  bool localPath)  sessionEstablished,required TResult Function( String remoteRelayId,  String reason)  sessionEnded,required TResult Function( String remoteRelayId,  RsCapabilityManifest manifest)  manifestReceived,required TResult Function( String remoteRelayId,  int? percentage,  RsChargingState charging)  batteryChanged,required TResult Function( String remoteRelayId,  String text,  bool explicit)  clipboardOffered,required TResult Function( String remoteRelayId,  String key,  String appLabel,  String? title,  String? body,  BigInt postedAtMs,  bool clearable)  notificationPosted,required TResult Function( String remoteRelayId,  String key)  notificationRemoved,required TResult Function( String remoteRelayId,  List<RsSmsConversation> conversations,  bool hasMore)  conversationsPage,required TResult Function( String remoteRelayId,  String conversationId,  List<RsSmsMessage> messages,  bool hasMore)  messagesPage,required TResult Function( String remoteRelayId,  RsSmsMessage message)  messageReceived,required TResult Function( String remoteRelayId,  String requestId,  bool sent,  String? detail)  smsSendCompleted,required TResult Function( String remoteRelayId,  RsCallState state)  callStateChanged,required TResult Function( String remoteRelayId,  String requestId,  bool accepted,  String? detail)  callActionCompleted,required TResult Function( String remoteRelayId,  String code,  String detail)  peerError,}) {final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished():
return sessionEstablished(_that.remoteRelayId,_that.directPath,_that.localPath);case RsContinuityEvent_SessionEnded():
return sessionEnded(_that.remoteRelayId,_that.reason);case RsContinuityEvent_ManifestReceived():
return manifestReceived(_that.remoteRelayId,_that.manifest);case RsContinuityEvent_BatteryChanged():
return batteryChanged(_that.remoteRelayId,_that.percentage,_that.charging);case RsContinuityEvent_ClipboardOffered():
return clipboardOffered(_that.remoteRelayId,_that.text,_that.explicit);case RsContinuityEvent_NotificationPosted():
return notificationPosted(_that.remoteRelayId,_that.key,_that.appLabel,_that.title,_that.body,_that.postedAtMs,_that.clearable);case RsContinuityEvent_NotificationRemoved():
return notificationRemoved(_that.remoteRelayId,_that.key);case RsContinuityEvent_ConversationsPage():
return conversationsPage(_that.remoteRelayId,_that.conversations,_that.hasMore);case RsContinuityEvent_MessagesPage():
return messagesPage(_that.remoteRelayId,_that.conversationId,_that.messages,_that.hasMore);case RsContinuityEvent_MessageReceived():
return messageReceived(_that.remoteRelayId,_that.message);case RsContinuityEvent_SmsSendCompleted():
return smsSendCompleted(_that.remoteRelayId,_that.requestId,_that.sent,_that.detail);case RsContinuityEvent_CallStateChanged():
return callStateChanged(_that.remoteRelayId,_that.state);case RsContinuityEvent_CallActionCompleted():
return callActionCompleted(_that.remoteRelayId,_that.requestId,_that.accepted,_that.detail);case RsContinuityEvent_PeerError():
return peerError(_that.remoteRelayId,_that.code,_that.detail);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String remoteRelayId,  bool directPath,  bool localPath)?  sessionEstablished,TResult? Function( String remoteRelayId,  String reason)?  sessionEnded,TResult? Function( String remoteRelayId,  RsCapabilityManifest manifest)?  manifestReceived,TResult? Function( String remoteRelayId,  int? percentage,  RsChargingState charging)?  batteryChanged,TResult? Function( String remoteRelayId,  String text,  bool explicit)?  clipboardOffered,TResult? Function( String remoteRelayId,  String key,  String appLabel,  String? title,  String? body,  BigInt postedAtMs,  bool clearable)?  notificationPosted,TResult? Function( String remoteRelayId,  String key)?  notificationRemoved,TResult? Function( String remoteRelayId,  List<RsSmsConversation> conversations,  bool hasMore)?  conversationsPage,TResult? Function( String remoteRelayId,  String conversationId,  List<RsSmsMessage> messages,  bool hasMore)?  messagesPage,TResult? Function( String remoteRelayId,  RsSmsMessage message)?  messageReceived,TResult? Function( String remoteRelayId,  String requestId,  bool sent,  String? detail)?  smsSendCompleted,TResult? Function( String remoteRelayId,  RsCallState state)?  callStateChanged,TResult? Function( String remoteRelayId,  String requestId,  bool accepted,  String? detail)?  callActionCompleted,TResult? Function( String remoteRelayId,  String code,  String detail)?  peerError,}) {final _that = this;
switch (_that) {
case RsContinuityEvent_SessionEstablished() when sessionEstablished != null:
return sessionEstablished(_that.remoteRelayId,_that.directPath,_that.localPath);case RsContinuityEvent_SessionEnded() when sessionEnded != null:
return sessionEnded(_that.remoteRelayId,_that.reason);case RsContinuityEvent_ManifestReceived() when manifestReceived != null:
return manifestReceived(_that.remoteRelayId,_that.manifest);case RsContinuityEvent_BatteryChanged() when batteryChanged != null:
return batteryChanged(_that.remoteRelayId,_that.percentage,_that.charging);case RsContinuityEvent_ClipboardOffered() when clipboardOffered != null:
return clipboardOffered(_that.remoteRelayId,_that.text,_that.explicit);case RsContinuityEvent_NotificationPosted() when notificationPosted != null:
return notificationPosted(_that.remoteRelayId,_that.key,_that.appLabel,_that.title,_that.body,_that.postedAtMs,_that.clearable);case RsContinuityEvent_NotificationRemoved() when notificationRemoved != null:
return notificationRemoved(_that.remoteRelayId,_that.key);case RsContinuityEvent_ConversationsPage() when conversationsPage != null:
return conversationsPage(_that.remoteRelayId,_that.conversations,_that.hasMore);case RsContinuityEvent_MessagesPage() when messagesPage != null:
return messagesPage(_that.remoteRelayId,_that.conversationId,_that.messages,_that.hasMore);case RsContinuityEvent_MessageReceived() when messageReceived != null:
return messageReceived(_that.remoteRelayId,_that.message);case RsContinuityEvent_SmsSendCompleted() when smsSendCompleted != null:
return smsSendCompleted(_that.remoteRelayId,_that.requestId,_that.sent,_that.detail);case RsContinuityEvent_CallStateChanged() when callStateChanged != null:
return callStateChanged(_that.remoteRelayId,_that.state);case RsContinuityEvent_CallActionCompleted() when callActionCompleted != null:
return callActionCompleted(_that.remoteRelayId,_that.requestId,_that.accepted,_that.detail);case RsContinuityEvent_PeerError() when peerError != null:
return peerError(_that.remoteRelayId,_that.code,_that.detail);case _:
  return null;

}
}

}

/// @nodoc


class RsContinuityEvent_SessionEstablished extends RsContinuityEvent {
  const RsContinuityEvent_SessionEstablished({required this.remoteRelayId, required this.directPath, required this.localPath}): super._();
  

@override final  String remoteRelayId;
 final  bool directPath;
/// Whether this session runs over the local network. Read from the path
/// the transport established, never claimed by the peer.
 final  bool localPath;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_SessionEstablishedCopyWith<RsContinuityEvent_SessionEstablished> get copyWith => _$RsContinuityEvent_SessionEstablishedCopyWithImpl<RsContinuityEvent_SessionEstablished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_SessionEstablished&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.directPath, directPath) || other.directPath == directPath)&&(identical(other.localPath, localPath) || other.localPath == localPath));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,directPath,localPath);

@override
String toString() {
  return 'RsContinuityEvent.sessionEstablished(remoteRelayId: $remoteRelayId, directPath: $directPath, localPath: $localPath)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_SessionEstablishedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_SessionEstablishedCopyWith(RsContinuityEvent_SessionEstablished value, $Res Function(RsContinuityEvent_SessionEstablished) _then) = _$RsContinuityEvent_SessionEstablishedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, bool directPath, bool localPath
});




}
/// @nodoc
class _$RsContinuityEvent_SessionEstablishedCopyWithImpl<$Res>
    implements $RsContinuityEvent_SessionEstablishedCopyWith<$Res> {
  _$RsContinuityEvent_SessionEstablishedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_SessionEstablished _self;
  final $Res Function(RsContinuityEvent_SessionEstablished) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? directPath = null,Object? localPath = null,}) {
  return _then(RsContinuityEvent_SessionEstablished(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,directPath: null == directPath ? _self.directPath : directPath // ignore: cast_nullable_to_non_nullable
as bool,localPath: null == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsContinuityEvent_SessionEnded extends RsContinuityEvent {
  const RsContinuityEvent_SessionEnded({required this.remoteRelayId, required this.reason}): super._();
  

@override final  String remoteRelayId;
 final  String reason;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_SessionEndedCopyWith<RsContinuityEvent_SessionEnded> get copyWith => _$RsContinuityEvent_SessionEndedCopyWithImpl<RsContinuityEvent_SessionEnded>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_SessionEnded&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,reason);

@override
String toString() {
  return 'RsContinuityEvent.sessionEnded(remoteRelayId: $remoteRelayId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_SessionEndedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_SessionEndedCopyWith(RsContinuityEvent_SessionEnded value, $Res Function(RsContinuityEvent_SessionEnded) _then) = _$RsContinuityEvent_SessionEndedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String reason
});




}
/// @nodoc
class _$RsContinuityEvent_SessionEndedCopyWithImpl<$Res>
    implements $RsContinuityEvent_SessionEndedCopyWith<$Res> {
  _$RsContinuityEvent_SessionEndedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_SessionEnded _self;
  final $Res Function(RsContinuityEvent_SessionEnded) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? reason = null,}) {
  return _then(RsContinuityEvent_SessionEnded(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsContinuityEvent_ManifestReceived extends RsContinuityEvent {
  const RsContinuityEvent_ManifestReceived({required this.remoteRelayId, required this.manifest}): super._();
  

@override final  String remoteRelayId;
 final  RsCapabilityManifest manifest;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_ManifestReceivedCopyWith<RsContinuityEvent_ManifestReceived> get copyWith => _$RsContinuityEvent_ManifestReceivedCopyWithImpl<RsContinuityEvent_ManifestReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_ManifestReceived&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.manifest, manifest) || other.manifest == manifest));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,manifest);

@override
String toString() {
  return 'RsContinuityEvent.manifestReceived(remoteRelayId: $remoteRelayId, manifest: $manifest)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_ManifestReceivedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_ManifestReceivedCopyWith(RsContinuityEvent_ManifestReceived value, $Res Function(RsContinuityEvent_ManifestReceived) _then) = _$RsContinuityEvent_ManifestReceivedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, RsCapabilityManifest manifest
});




}
/// @nodoc
class _$RsContinuityEvent_ManifestReceivedCopyWithImpl<$Res>
    implements $RsContinuityEvent_ManifestReceivedCopyWith<$Res> {
  _$RsContinuityEvent_ManifestReceivedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_ManifestReceived _self;
  final $Res Function(RsContinuityEvent_ManifestReceived) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? manifest = null,}) {
  return _then(RsContinuityEvent_ManifestReceived(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,manifest: null == manifest ? _self.manifest : manifest // ignore: cast_nullable_to_non_nullable
as RsCapabilityManifest,
  ));
}


}

/// @nodoc


class RsContinuityEvent_BatteryChanged extends RsContinuityEvent {
  const RsContinuityEvent_BatteryChanged({required this.remoteRelayId, this.percentage, required this.charging}): super._();
  

@override final  String remoteRelayId;
 final  int? percentage;
 final  RsChargingState charging;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_BatteryChangedCopyWith<RsContinuityEvent_BatteryChanged> get copyWith => _$RsContinuityEvent_BatteryChangedCopyWithImpl<RsContinuityEvent_BatteryChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_BatteryChanged&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.percentage, percentage) || other.percentage == percentage)&&(identical(other.charging, charging) || other.charging == charging));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,percentage,charging);

@override
String toString() {
  return 'RsContinuityEvent.batteryChanged(remoteRelayId: $remoteRelayId, percentage: $percentage, charging: $charging)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_BatteryChangedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_BatteryChangedCopyWith(RsContinuityEvent_BatteryChanged value, $Res Function(RsContinuityEvent_BatteryChanged) _then) = _$RsContinuityEvent_BatteryChangedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, int? percentage, RsChargingState charging
});




}
/// @nodoc
class _$RsContinuityEvent_BatteryChangedCopyWithImpl<$Res>
    implements $RsContinuityEvent_BatteryChangedCopyWith<$Res> {
  _$RsContinuityEvent_BatteryChangedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_BatteryChanged _self;
  final $Res Function(RsContinuityEvent_BatteryChanged) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? percentage = freezed,Object? charging = null,}) {
  return _then(RsContinuityEvent_BatteryChanged(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as int?,charging: null == charging ? _self.charging : charging // ignore: cast_nullable_to_non_nullable
as RsChargingState,
  ));
}


}

/// @nodoc


class RsContinuityEvent_ClipboardOffered extends RsContinuityEvent {
  const RsContinuityEvent_ClipboardOffered({required this.remoteRelayId, required this.text, required this.explicit}): super._();
  

@override final  String remoteRelayId;
 final  String text;
 final  bool explicit;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_ClipboardOfferedCopyWith<RsContinuityEvent_ClipboardOffered> get copyWith => _$RsContinuityEvent_ClipboardOfferedCopyWithImpl<RsContinuityEvent_ClipboardOffered>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_ClipboardOffered&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.text, text) || other.text == text)&&(identical(other.explicit, explicit) || other.explicit == explicit));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,text,explicit);

@override
String toString() {
  return 'RsContinuityEvent.clipboardOffered(remoteRelayId: $remoteRelayId, text: $text, explicit: $explicit)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_ClipboardOfferedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_ClipboardOfferedCopyWith(RsContinuityEvent_ClipboardOffered value, $Res Function(RsContinuityEvent_ClipboardOffered) _then) = _$RsContinuityEvent_ClipboardOfferedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String text, bool explicit
});




}
/// @nodoc
class _$RsContinuityEvent_ClipboardOfferedCopyWithImpl<$Res>
    implements $RsContinuityEvent_ClipboardOfferedCopyWith<$Res> {
  _$RsContinuityEvent_ClipboardOfferedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_ClipboardOffered _self;
  final $Res Function(RsContinuityEvent_ClipboardOffered) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? text = null,Object? explicit = null,}) {
  return _then(RsContinuityEvent_ClipboardOffered(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,explicit: null == explicit ? _self.explicit : explicit // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsContinuityEvent_NotificationPosted extends RsContinuityEvent {
  const RsContinuityEvent_NotificationPosted({required this.remoteRelayId, required this.key, required this.appLabel, this.title, this.body, required this.postedAtMs, required this.clearable}): super._();
  

@override final  String remoteRelayId;
 final  String key;
 final  String appLabel;
 final  String? title;
 final  String? body;
 final  BigInt postedAtMs;
 final  bool clearable;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_NotificationPostedCopyWith<RsContinuityEvent_NotificationPosted> get copyWith => _$RsContinuityEvent_NotificationPostedCopyWithImpl<RsContinuityEvent_NotificationPosted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_NotificationPosted&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.key, key) || other.key == key)&&(identical(other.appLabel, appLabel) || other.appLabel == appLabel)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.postedAtMs, postedAtMs) || other.postedAtMs == postedAtMs)&&(identical(other.clearable, clearable) || other.clearable == clearable));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,key,appLabel,title,body,postedAtMs,clearable);

@override
String toString() {
  return 'RsContinuityEvent.notificationPosted(remoteRelayId: $remoteRelayId, key: $key, appLabel: $appLabel, title: $title, body: $body, postedAtMs: $postedAtMs, clearable: $clearable)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_NotificationPostedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_NotificationPostedCopyWith(RsContinuityEvent_NotificationPosted value, $Res Function(RsContinuityEvent_NotificationPosted) _then) = _$RsContinuityEvent_NotificationPostedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String key, String appLabel, String? title, String? body, BigInt postedAtMs, bool clearable
});




}
/// @nodoc
class _$RsContinuityEvent_NotificationPostedCopyWithImpl<$Res>
    implements $RsContinuityEvent_NotificationPostedCopyWith<$Res> {
  _$RsContinuityEvent_NotificationPostedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_NotificationPosted _self;
  final $Res Function(RsContinuityEvent_NotificationPosted) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? key = null,Object? appLabel = null,Object? title = freezed,Object? body = freezed,Object? postedAtMs = null,Object? clearable = null,}) {
  return _then(RsContinuityEvent_NotificationPosted(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,appLabel: null == appLabel ? _self.appLabel : appLabel // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,body: freezed == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String?,postedAtMs: null == postedAtMs ? _self.postedAtMs : postedAtMs // ignore: cast_nullable_to_non_nullable
as BigInt,clearable: null == clearable ? _self.clearable : clearable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsContinuityEvent_NotificationRemoved extends RsContinuityEvent {
  const RsContinuityEvent_NotificationRemoved({required this.remoteRelayId, required this.key}): super._();
  

@override final  String remoteRelayId;
 final  String key;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_NotificationRemovedCopyWith<RsContinuityEvent_NotificationRemoved> get copyWith => _$RsContinuityEvent_NotificationRemovedCopyWithImpl<RsContinuityEvent_NotificationRemoved>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_NotificationRemoved&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,key);

@override
String toString() {
  return 'RsContinuityEvent.notificationRemoved(remoteRelayId: $remoteRelayId, key: $key)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_NotificationRemovedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_NotificationRemovedCopyWith(RsContinuityEvent_NotificationRemoved value, $Res Function(RsContinuityEvent_NotificationRemoved) _then) = _$RsContinuityEvent_NotificationRemovedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String key
});




}
/// @nodoc
class _$RsContinuityEvent_NotificationRemovedCopyWithImpl<$Res>
    implements $RsContinuityEvent_NotificationRemovedCopyWith<$Res> {
  _$RsContinuityEvent_NotificationRemovedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_NotificationRemoved _self;
  final $Res Function(RsContinuityEvent_NotificationRemoved) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? key = null,}) {
  return _then(RsContinuityEvent_NotificationRemoved(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsContinuityEvent_ConversationsPage extends RsContinuityEvent {
  const RsContinuityEvent_ConversationsPage({required this.remoteRelayId, required final  List<RsSmsConversation> conversations, required this.hasMore}): _conversations = conversations,super._();
  

@override final  String remoteRelayId;
 final  List<RsSmsConversation> _conversations;
 List<RsSmsConversation> get conversations {
  if (_conversations is EqualUnmodifiableListView) return _conversations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_conversations);
}

 final  bool hasMore;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_ConversationsPageCopyWith<RsContinuityEvent_ConversationsPage> get copyWith => _$RsContinuityEvent_ConversationsPageCopyWithImpl<RsContinuityEvent_ConversationsPage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_ConversationsPage&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&const DeepCollectionEquality().equals(other._conversations, _conversations)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,const DeepCollectionEquality().hash(_conversations),hasMore);

@override
String toString() {
  return 'RsContinuityEvent.conversationsPage(remoteRelayId: $remoteRelayId, conversations: $conversations, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_ConversationsPageCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_ConversationsPageCopyWith(RsContinuityEvent_ConversationsPage value, $Res Function(RsContinuityEvent_ConversationsPage) _then) = _$RsContinuityEvent_ConversationsPageCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, List<RsSmsConversation> conversations, bool hasMore
});




}
/// @nodoc
class _$RsContinuityEvent_ConversationsPageCopyWithImpl<$Res>
    implements $RsContinuityEvent_ConversationsPageCopyWith<$Res> {
  _$RsContinuityEvent_ConversationsPageCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_ConversationsPage _self;
  final $Res Function(RsContinuityEvent_ConversationsPage) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? conversations = null,Object? hasMore = null,}) {
  return _then(RsContinuityEvent_ConversationsPage(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,conversations: null == conversations ? _self._conversations : conversations // ignore: cast_nullable_to_non_nullable
as List<RsSmsConversation>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsContinuityEvent_MessagesPage extends RsContinuityEvent {
  const RsContinuityEvent_MessagesPage({required this.remoteRelayId, required this.conversationId, required final  List<RsSmsMessage> messages, required this.hasMore}): _messages = messages,super._();
  

@override final  String remoteRelayId;
 final  String conversationId;
 final  List<RsSmsMessage> _messages;
 List<RsSmsMessage> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}

 final  bool hasMore;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_MessagesPageCopyWith<RsContinuityEvent_MessagesPage> get copyWith => _$RsContinuityEvent_MessagesPageCopyWithImpl<RsContinuityEvent_MessagesPage>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_MessagesPage&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other._messages, _messages)&&(identical(other.hasMore, hasMore) || other.hasMore == hasMore));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,conversationId,const DeepCollectionEquality().hash(_messages),hasMore);

@override
String toString() {
  return 'RsContinuityEvent.messagesPage(remoteRelayId: $remoteRelayId, conversationId: $conversationId, messages: $messages, hasMore: $hasMore)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_MessagesPageCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_MessagesPageCopyWith(RsContinuityEvent_MessagesPage value, $Res Function(RsContinuityEvent_MessagesPage) _then) = _$RsContinuityEvent_MessagesPageCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String conversationId, List<RsSmsMessage> messages, bool hasMore
});




}
/// @nodoc
class _$RsContinuityEvent_MessagesPageCopyWithImpl<$Res>
    implements $RsContinuityEvent_MessagesPageCopyWith<$Res> {
  _$RsContinuityEvent_MessagesPageCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_MessagesPage _self;
  final $Res Function(RsContinuityEvent_MessagesPage) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? conversationId = null,Object? messages = null,Object? hasMore = null,}) {
  return _then(RsContinuityEvent_MessagesPage(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<RsSmsMessage>,hasMore: null == hasMore ? _self.hasMore : hasMore // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RsContinuityEvent_MessageReceived extends RsContinuityEvent {
  const RsContinuityEvent_MessageReceived({required this.remoteRelayId, required this.message}): super._();
  

@override final  String remoteRelayId;
 final  RsSmsMessage message;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_MessageReceivedCopyWith<RsContinuityEvent_MessageReceived> get copyWith => _$RsContinuityEvent_MessageReceivedCopyWithImpl<RsContinuityEvent_MessageReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_MessageReceived&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,message);

@override
String toString() {
  return 'RsContinuityEvent.messageReceived(remoteRelayId: $remoteRelayId, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_MessageReceivedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_MessageReceivedCopyWith(RsContinuityEvent_MessageReceived value, $Res Function(RsContinuityEvent_MessageReceived) _then) = _$RsContinuityEvent_MessageReceivedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, RsSmsMessage message
});




}
/// @nodoc
class _$RsContinuityEvent_MessageReceivedCopyWithImpl<$Res>
    implements $RsContinuityEvent_MessageReceivedCopyWith<$Res> {
  _$RsContinuityEvent_MessageReceivedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_MessageReceived _self;
  final $Res Function(RsContinuityEvent_MessageReceived) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? message = null,}) {
  return _then(RsContinuityEvent_MessageReceived(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as RsSmsMessage,
  ));
}


}

/// @nodoc


class RsContinuityEvent_SmsSendCompleted extends RsContinuityEvent {
  const RsContinuityEvent_SmsSendCompleted({required this.remoteRelayId, required this.requestId, required this.sent, this.detail}): super._();
  

@override final  String remoteRelayId;
 final  String requestId;
 final  bool sent;
 final  String? detail;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_SmsSendCompletedCopyWith<RsContinuityEvent_SmsSendCompleted> get copyWith => _$RsContinuityEvent_SmsSendCompletedCopyWithImpl<RsContinuityEvent_SmsSendCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_SmsSendCompleted&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.sent, sent) || other.sent == sent)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,requestId,sent,detail);

@override
String toString() {
  return 'RsContinuityEvent.smsSendCompleted(remoteRelayId: $remoteRelayId, requestId: $requestId, sent: $sent, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_SmsSendCompletedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_SmsSendCompletedCopyWith(RsContinuityEvent_SmsSendCompleted value, $Res Function(RsContinuityEvent_SmsSendCompleted) _then) = _$RsContinuityEvent_SmsSendCompletedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String requestId, bool sent, String? detail
});




}
/// @nodoc
class _$RsContinuityEvent_SmsSendCompletedCopyWithImpl<$Res>
    implements $RsContinuityEvent_SmsSendCompletedCopyWith<$Res> {
  _$RsContinuityEvent_SmsSendCompletedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_SmsSendCompleted _self;
  final $Res Function(RsContinuityEvent_SmsSendCompleted) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? requestId = null,Object? sent = null,Object? detail = freezed,}) {
  return _then(RsContinuityEvent_SmsSendCompleted(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,sent: null == sent ? _self.sent : sent // ignore: cast_nullable_to_non_nullable
as bool,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsContinuityEvent_CallStateChanged extends RsContinuityEvent {
  const RsContinuityEvent_CallStateChanged({required this.remoteRelayId, required this.state}): super._();
  

@override final  String remoteRelayId;
 final  RsCallState state;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_CallStateChangedCopyWith<RsContinuityEvent_CallStateChanged> get copyWith => _$RsContinuityEvent_CallStateChangedCopyWithImpl<RsContinuityEvent_CallStateChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_CallStateChanged&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,state);

@override
String toString() {
  return 'RsContinuityEvent.callStateChanged(remoteRelayId: $remoteRelayId, state: $state)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_CallStateChangedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_CallStateChangedCopyWith(RsContinuityEvent_CallStateChanged value, $Res Function(RsContinuityEvent_CallStateChanged) _then) = _$RsContinuityEvent_CallStateChangedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, RsCallState state
});




}
/// @nodoc
class _$RsContinuityEvent_CallStateChangedCopyWithImpl<$Res>
    implements $RsContinuityEvent_CallStateChangedCopyWith<$Res> {
  _$RsContinuityEvent_CallStateChangedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_CallStateChanged _self;
  final $Res Function(RsContinuityEvent_CallStateChanged) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? state = null,}) {
  return _then(RsContinuityEvent_CallStateChanged(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as RsCallState,
  ));
}


}

/// @nodoc


class RsContinuityEvent_CallActionCompleted extends RsContinuityEvent {
  const RsContinuityEvent_CallActionCompleted({required this.remoteRelayId, required this.requestId, required this.accepted, this.detail}): super._();
  

@override final  String remoteRelayId;
 final  String requestId;
 final  bool accepted;
 final  String? detail;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_CallActionCompletedCopyWith<RsContinuityEvent_CallActionCompleted> get copyWith => _$RsContinuityEvent_CallActionCompletedCopyWithImpl<RsContinuityEvent_CallActionCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_CallActionCompleted&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.accepted, accepted) || other.accepted == accepted)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,requestId,accepted,detail);

@override
String toString() {
  return 'RsContinuityEvent.callActionCompleted(remoteRelayId: $remoteRelayId, requestId: $requestId, accepted: $accepted, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_CallActionCompletedCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_CallActionCompletedCopyWith(RsContinuityEvent_CallActionCompleted value, $Res Function(RsContinuityEvent_CallActionCompleted) _then) = _$RsContinuityEvent_CallActionCompletedCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String requestId, bool accepted, String? detail
});




}
/// @nodoc
class _$RsContinuityEvent_CallActionCompletedCopyWithImpl<$Res>
    implements $RsContinuityEvent_CallActionCompletedCopyWith<$Res> {
  _$RsContinuityEvent_CallActionCompletedCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_CallActionCompleted _self;
  final $Res Function(RsContinuityEvent_CallActionCompleted) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? requestId = null,Object? accepted = null,Object? detail = freezed,}) {
  return _then(RsContinuityEvent_CallActionCompleted(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,accepted: null == accepted ? _self.accepted : accepted // ignore: cast_nullable_to_non_nullable
as bool,detail: freezed == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsContinuityEvent_PeerError extends RsContinuityEvent {
  const RsContinuityEvent_PeerError({required this.remoteRelayId, required this.code, required this.detail}): super._();
  

@override final  String remoteRelayId;
 final  String code;
 final  String detail;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityEvent_PeerErrorCopyWith<RsContinuityEvent_PeerError> get copyWith => _$RsContinuityEvent_PeerErrorCopyWithImpl<RsContinuityEvent_PeerError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityEvent_PeerError&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.code, code) || other.code == code)&&(identical(other.detail, detail) || other.detail == detail));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,code,detail);

@override
String toString() {
  return 'RsContinuityEvent.peerError(remoteRelayId: $remoteRelayId, code: $code, detail: $detail)';
}


}

/// @nodoc
abstract mixin class $RsContinuityEvent_PeerErrorCopyWith<$Res> implements $RsContinuityEventCopyWith<$Res> {
  factory $RsContinuityEvent_PeerErrorCopyWith(RsContinuityEvent_PeerError value, $Res Function(RsContinuityEvent_PeerError) _then) = _$RsContinuityEvent_PeerErrorCopyWithImpl;
@override @useResult
$Res call({
 String remoteRelayId, String code, String detail
});




}
/// @nodoc
class _$RsContinuityEvent_PeerErrorCopyWithImpl<$Res>
    implements $RsContinuityEvent_PeerErrorCopyWith<$Res> {
  _$RsContinuityEvent_PeerErrorCopyWithImpl(this._self, this._then);

  final RsContinuityEvent_PeerError _self;
  final $Res Function(RsContinuityEvent_PeerError) _then;

/// Create a copy of RsContinuityEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? code = null,Object? detail = null,}) {
  return _then(RsContinuityEvent_PeerError(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,detail: null == detail ? _self.detail : detail // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsContinuityHostRequest {

 BigInt get requestId; String get remoteRelayId;
/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequestCopyWith<RsContinuityHostRequest> get copyWith => _$RsContinuityHostRequestCopyWithImpl<RsContinuityHostRequest>(this as RsContinuityHostRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId);

@override
String toString() {
  return 'RsContinuityHostRequest(requestId: $requestId, remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequestCopyWith<$Res>  {
  factory $RsContinuityHostRequestCopyWith(RsContinuityHostRequest value, $Res Function(RsContinuityHostRequest) _then) = _$RsContinuityHostRequestCopyWithImpl;
@useResult
$Res call({
 BigInt requestId, String remoteRelayId
});




}
/// @nodoc
class _$RsContinuityHostRequestCopyWithImpl<$Res>
    implements $RsContinuityHostRequestCopyWith<$Res> {
  _$RsContinuityHostRequestCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest _self;
  final $Res Function(RsContinuityHostRequest) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requestId = null,Object? remoteRelayId = null,}) {
  return _then(_self.copyWith(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RsContinuityHostRequest].
extension RsContinuityHostRequestPatterns on RsContinuityHostRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsContinuityHostRequest_ApplyClipboard value)?  applyClipboard,TResult Function( RsContinuityHostRequest_DismissNotification value)?  dismissNotification,TResult Function( RsContinuityHostRequest_ListConversations value)?  listConversations,TResult Function( RsContinuityHostRequest_ListMessages value)?  listMessages,TResult Function( RsContinuityHostRequest_SendSms value)?  sendSms,TResult Function( RsContinuityHostRequest_CallAction value)?  callAction,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard() when applyClipboard != null:
return applyClipboard(_that);case RsContinuityHostRequest_DismissNotification() when dismissNotification != null:
return dismissNotification(_that);case RsContinuityHostRequest_ListConversations() when listConversations != null:
return listConversations(_that);case RsContinuityHostRequest_ListMessages() when listMessages != null:
return listMessages(_that);case RsContinuityHostRequest_SendSms() when sendSms != null:
return sendSms(_that);case RsContinuityHostRequest_CallAction() when callAction != null:
return callAction(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsContinuityHostRequest_ApplyClipboard value)  applyClipboard,required TResult Function( RsContinuityHostRequest_DismissNotification value)  dismissNotification,required TResult Function( RsContinuityHostRequest_ListConversations value)  listConversations,required TResult Function( RsContinuityHostRequest_ListMessages value)  listMessages,required TResult Function( RsContinuityHostRequest_SendSms value)  sendSms,required TResult Function( RsContinuityHostRequest_CallAction value)  callAction,}){
final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard():
return applyClipboard(_that);case RsContinuityHostRequest_DismissNotification():
return dismissNotification(_that);case RsContinuityHostRequest_ListConversations():
return listConversations(_that);case RsContinuityHostRequest_ListMessages():
return listMessages(_that);case RsContinuityHostRequest_SendSms():
return sendSms(_that);case RsContinuityHostRequest_CallAction():
return callAction(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsContinuityHostRequest_ApplyClipboard value)?  applyClipboard,TResult? Function( RsContinuityHostRequest_DismissNotification value)?  dismissNotification,TResult? Function( RsContinuityHostRequest_ListConversations value)?  listConversations,TResult? Function( RsContinuityHostRequest_ListMessages value)?  listMessages,TResult? Function( RsContinuityHostRequest_SendSms value)?  sendSms,TResult? Function( RsContinuityHostRequest_CallAction value)?  callAction,}){
final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard() when applyClipboard != null:
return applyClipboard(_that);case RsContinuityHostRequest_DismissNotification() when dismissNotification != null:
return dismissNotification(_that);case RsContinuityHostRequest_ListConversations() when listConversations != null:
return listConversations(_that);case RsContinuityHostRequest_ListMessages() when listMessages != null:
return listMessages(_that);case RsContinuityHostRequest_SendSms() when sendSms != null:
return sendSms(_that);case RsContinuityHostRequest_CallAction() when callAction != null:
return callAction(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt requestId,  String remoteRelayId,  String text)?  applyClipboard,TResult Function( BigInt requestId,  String remoteRelayId,  String key)?  dismissNotification,TResult Function( BigInt requestId,  String remoteRelayId,  int limit,  BigInt? beforeMs)?  listConversations,TResult Function( BigInt requestId,  String remoteRelayId,  String conversationId,  int limit,  BigInt? beforeMs)?  listMessages,TResult Function( BigInt requestId,  String remoteRelayId,  String? conversationId,  List<String> recipients,  String body)?  sendSms,TResult Function( BigInt requestId,  String remoteRelayId,  RsCallAction action,  String? address)?  callAction,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard() when applyClipboard != null:
return applyClipboard(_that.requestId,_that.remoteRelayId,_that.text);case RsContinuityHostRequest_DismissNotification() when dismissNotification != null:
return dismissNotification(_that.requestId,_that.remoteRelayId,_that.key);case RsContinuityHostRequest_ListConversations() when listConversations != null:
return listConversations(_that.requestId,_that.remoteRelayId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_ListMessages() when listMessages != null:
return listMessages(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_SendSms() when sendSms != null:
return sendSms(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.recipients,_that.body);case RsContinuityHostRequest_CallAction() when callAction != null:
return callAction(_that.requestId,_that.remoteRelayId,_that.action,_that.address);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt requestId,  String remoteRelayId,  String text)  applyClipboard,required TResult Function( BigInt requestId,  String remoteRelayId,  String key)  dismissNotification,required TResult Function( BigInt requestId,  String remoteRelayId,  int limit,  BigInt? beforeMs)  listConversations,required TResult Function( BigInt requestId,  String remoteRelayId,  String conversationId,  int limit,  BigInt? beforeMs)  listMessages,required TResult Function( BigInt requestId,  String remoteRelayId,  String? conversationId,  List<String> recipients,  String body)  sendSms,required TResult Function( BigInt requestId,  String remoteRelayId,  RsCallAction action,  String? address)  callAction,}) {final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard():
return applyClipboard(_that.requestId,_that.remoteRelayId,_that.text);case RsContinuityHostRequest_DismissNotification():
return dismissNotification(_that.requestId,_that.remoteRelayId,_that.key);case RsContinuityHostRequest_ListConversations():
return listConversations(_that.requestId,_that.remoteRelayId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_ListMessages():
return listMessages(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_SendSms():
return sendSms(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.recipients,_that.body);case RsContinuityHostRequest_CallAction():
return callAction(_that.requestId,_that.remoteRelayId,_that.action,_that.address);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt requestId,  String remoteRelayId,  String text)?  applyClipboard,TResult? Function( BigInt requestId,  String remoteRelayId,  String key)?  dismissNotification,TResult? Function( BigInt requestId,  String remoteRelayId,  int limit,  BigInt? beforeMs)?  listConversations,TResult? Function( BigInt requestId,  String remoteRelayId,  String conversationId,  int limit,  BigInt? beforeMs)?  listMessages,TResult? Function( BigInt requestId,  String remoteRelayId,  String? conversationId,  List<String> recipients,  String body)?  sendSms,TResult? Function( BigInt requestId,  String remoteRelayId,  RsCallAction action,  String? address)?  callAction,}) {final _that = this;
switch (_that) {
case RsContinuityHostRequest_ApplyClipboard() when applyClipboard != null:
return applyClipboard(_that.requestId,_that.remoteRelayId,_that.text);case RsContinuityHostRequest_DismissNotification() when dismissNotification != null:
return dismissNotification(_that.requestId,_that.remoteRelayId,_that.key);case RsContinuityHostRequest_ListConversations() when listConversations != null:
return listConversations(_that.requestId,_that.remoteRelayId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_ListMessages() when listMessages != null:
return listMessages(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.limit,_that.beforeMs);case RsContinuityHostRequest_SendSms() when sendSms != null:
return sendSms(_that.requestId,_that.remoteRelayId,_that.conversationId,_that.recipients,_that.body);case RsContinuityHostRequest_CallAction() when callAction != null:
return callAction(_that.requestId,_that.remoteRelayId,_that.action,_that.address);case _:
  return null;

}
}

}

/// @nodoc


class RsContinuityHostRequest_ApplyClipboard extends RsContinuityHostRequest {
  const RsContinuityHostRequest_ApplyClipboard({required this.requestId, required this.remoteRelayId, required this.text}): super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  String text;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_ApplyClipboardCopyWith<RsContinuityHostRequest_ApplyClipboard> get copyWith => _$RsContinuityHostRequest_ApplyClipboardCopyWithImpl<RsContinuityHostRequest_ApplyClipboard>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_ApplyClipboard&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,text);

@override
String toString() {
  return 'RsContinuityHostRequest.applyClipboard(requestId: $requestId, remoteRelayId: $remoteRelayId, text: $text)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_ApplyClipboardCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_ApplyClipboardCopyWith(RsContinuityHostRequest_ApplyClipboard value, $Res Function(RsContinuityHostRequest_ApplyClipboard) _then) = _$RsContinuityHostRequest_ApplyClipboardCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, String text
});




}
/// @nodoc
class _$RsContinuityHostRequest_ApplyClipboardCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_ApplyClipboardCopyWith<$Res> {
  _$RsContinuityHostRequest_ApplyClipboardCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_ApplyClipboard _self;
  final $Res Function(RsContinuityHostRequest_ApplyClipboard) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? text = null,}) {
  return _then(RsContinuityHostRequest_ApplyClipboard(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsContinuityHostRequest_DismissNotification extends RsContinuityHostRequest {
  const RsContinuityHostRequest_DismissNotification({required this.requestId, required this.remoteRelayId, required this.key}): super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  String key;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_DismissNotificationCopyWith<RsContinuityHostRequest_DismissNotification> get copyWith => _$RsContinuityHostRequest_DismissNotificationCopyWithImpl<RsContinuityHostRequest_DismissNotification>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_DismissNotification&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.key, key) || other.key == key));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,key);

@override
String toString() {
  return 'RsContinuityHostRequest.dismissNotification(requestId: $requestId, remoteRelayId: $remoteRelayId, key: $key)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_DismissNotificationCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_DismissNotificationCopyWith(RsContinuityHostRequest_DismissNotification value, $Res Function(RsContinuityHostRequest_DismissNotification) _then) = _$RsContinuityHostRequest_DismissNotificationCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, String key
});




}
/// @nodoc
class _$RsContinuityHostRequest_DismissNotificationCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_DismissNotificationCopyWith<$Res> {
  _$RsContinuityHostRequest_DismissNotificationCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_DismissNotification _self;
  final $Res Function(RsContinuityHostRequest_DismissNotification) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? key = null,}) {
  return _then(RsContinuityHostRequest_DismissNotification(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsContinuityHostRequest_ListConversations extends RsContinuityHostRequest {
  const RsContinuityHostRequest_ListConversations({required this.requestId, required this.remoteRelayId, required this.limit, this.beforeMs}): super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  int limit;
 final  BigInt? beforeMs;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_ListConversationsCopyWith<RsContinuityHostRequest_ListConversations> get copyWith => _$RsContinuityHostRequest_ListConversationsCopyWithImpl<RsContinuityHostRequest_ListConversations>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_ListConversations&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.beforeMs, beforeMs) || other.beforeMs == beforeMs));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,limit,beforeMs);

@override
String toString() {
  return 'RsContinuityHostRequest.listConversations(requestId: $requestId, remoteRelayId: $remoteRelayId, limit: $limit, beforeMs: $beforeMs)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_ListConversationsCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_ListConversationsCopyWith(RsContinuityHostRequest_ListConversations value, $Res Function(RsContinuityHostRequest_ListConversations) _then) = _$RsContinuityHostRequest_ListConversationsCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, int limit, BigInt? beforeMs
});




}
/// @nodoc
class _$RsContinuityHostRequest_ListConversationsCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_ListConversationsCopyWith<$Res> {
  _$RsContinuityHostRequest_ListConversationsCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_ListConversations _self;
  final $Res Function(RsContinuityHostRequest_ListConversations) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? limit = null,Object? beforeMs = freezed,}) {
  return _then(RsContinuityHostRequest_ListConversations(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,beforeMs: freezed == beforeMs ? _self.beforeMs : beforeMs // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class RsContinuityHostRequest_ListMessages extends RsContinuityHostRequest {
  const RsContinuityHostRequest_ListMessages({required this.requestId, required this.remoteRelayId, required this.conversationId, required this.limit, this.beforeMs}): super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  String conversationId;
 final  int limit;
 final  BigInt? beforeMs;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_ListMessagesCopyWith<RsContinuityHostRequest_ListMessages> get copyWith => _$RsContinuityHostRequest_ListMessagesCopyWithImpl<RsContinuityHostRequest_ListMessages>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_ListMessages&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&(identical(other.limit, limit) || other.limit == limit)&&(identical(other.beforeMs, beforeMs) || other.beforeMs == beforeMs));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,conversationId,limit,beforeMs);

@override
String toString() {
  return 'RsContinuityHostRequest.listMessages(requestId: $requestId, remoteRelayId: $remoteRelayId, conversationId: $conversationId, limit: $limit, beforeMs: $beforeMs)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_ListMessagesCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_ListMessagesCopyWith(RsContinuityHostRequest_ListMessages value, $Res Function(RsContinuityHostRequest_ListMessages) _then) = _$RsContinuityHostRequest_ListMessagesCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, String conversationId, int limit, BigInt? beforeMs
});




}
/// @nodoc
class _$RsContinuityHostRequest_ListMessagesCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_ListMessagesCopyWith<$Res> {
  _$RsContinuityHostRequest_ListMessagesCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_ListMessages _self;
  final $Res Function(RsContinuityHostRequest_ListMessages) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? conversationId = null,Object? limit = null,Object? beforeMs = freezed,}) {
  return _then(RsContinuityHostRequest_ListMessages(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,conversationId: null == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,beforeMs: freezed == beforeMs ? _self.beforeMs : beforeMs // ignore: cast_nullable_to_non_nullable
as BigInt?,
  ));
}


}

/// @nodoc


class RsContinuityHostRequest_SendSms extends RsContinuityHostRequest {
  const RsContinuityHostRequest_SendSms({required this.requestId, required this.remoteRelayId, this.conversationId, required final  List<String> recipients, required this.body}): _recipients = recipients,super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  String? conversationId;
 final  List<String> _recipients;
 List<String> get recipients {
  if (_recipients is EqualUnmodifiableListView) return _recipients;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recipients);
}

 final  String body;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_SendSmsCopyWith<RsContinuityHostRequest_SendSms> get copyWith => _$RsContinuityHostRequest_SendSmsCopyWithImpl<RsContinuityHostRequest_SendSms>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_SendSms&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.conversationId, conversationId) || other.conversationId == conversationId)&&const DeepCollectionEquality().equals(other._recipients, _recipients)&&(identical(other.body, body) || other.body == body));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,conversationId,const DeepCollectionEquality().hash(_recipients),body);

@override
String toString() {
  return 'RsContinuityHostRequest.sendSms(requestId: $requestId, remoteRelayId: $remoteRelayId, conversationId: $conversationId, recipients: $recipients, body: $body)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_SendSmsCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_SendSmsCopyWith(RsContinuityHostRequest_SendSms value, $Res Function(RsContinuityHostRequest_SendSms) _then) = _$RsContinuityHostRequest_SendSmsCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, String? conversationId, List<String> recipients, String body
});




}
/// @nodoc
class _$RsContinuityHostRequest_SendSmsCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_SendSmsCopyWith<$Res> {
  _$RsContinuityHostRequest_SendSmsCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_SendSms _self;
  final $Res Function(RsContinuityHostRequest_SendSms) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? conversationId = freezed,Object? recipients = null,Object? body = null,}) {
  return _then(RsContinuityHostRequest_SendSms(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,conversationId: freezed == conversationId ? _self.conversationId : conversationId // ignore: cast_nullable_to_non_nullable
as String?,recipients: null == recipients ? _self._recipients : recipients // ignore: cast_nullable_to_non_nullable
as List<String>,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsContinuityHostRequest_CallAction extends RsContinuityHostRequest {
  const RsContinuityHostRequest_CallAction({required this.requestId, required this.remoteRelayId, required this.action, this.address}): super._();
  

@override final  BigInt requestId;
@override final  String remoteRelayId;
 final  RsCallAction action;
 final  String? address;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsContinuityHostRequest_CallActionCopyWith<RsContinuityHostRequest_CallAction> get copyWith => _$RsContinuityHostRequest_CallActionCopyWithImpl<RsContinuityHostRequest_CallAction>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsContinuityHostRequest_CallAction&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.action, action) || other.action == action)&&(identical(other.address, address) || other.address == address));
}


@override
int get hashCode => Object.hash(runtimeType,requestId,remoteRelayId,action,address);

@override
String toString() {
  return 'RsContinuityHostRequest.callAction(requestId: $requestId, remoteRelayId: $remoteRelayId, action: $action, address: $address)';
}


}

/// @nodoc
abstract mixin class $RsContinuityHostRequest_CallActionCopyWith<$Res> implements $RsContinuityHostRequestCopyWith<$Res> {
  factory $RsContinuityHostRequest_CallActionCopyWith(RsContinuityHostRequest_CallAction value, $Res Function(RsContinuityHostRequest_CallAction) _then) = _$RsContinuityHostRequest_CallActionCopyWithImpl;
@override @useResult
$Res call({
 BigInt requestId, String remoteRelayId, RsCallAction action, String? address
});




}
/// @nodoc
class _$RsContinuityHostRequest_CallActionCopyWithImpl<$Res>
    implements $RsContinuityHostRequest_CallActionCopyWith<$Res> {
  _$RsContinuityHostRequest_CallActionCopyWithImpl(this._self, this._then);

  final RsContinuityHostRequest_CallAction _self;
  final $Res Function(RsContinuityHostRequest_CallAction) _then;

/// Create a copy of RsContinuityHostRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? remoteRelayId = null,Object? action = null,Object? address = freezed,}) {
  return _then(RsContinuityHostRequest_CallAction(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as RsCallAction,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
