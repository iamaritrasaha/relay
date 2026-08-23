// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'kdeconnect.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsKdeConnectEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsKdeConnectEvent()';
}


}

/// @nodoc
class $RsKdeConnectEventCopyWith<$Res>  {
$RsKdeConnectEventCopyWith(RsKdeConnectEvent _, $Res Function(RsKdeConnectEvent) __);
}


/// Adds pattern-matching-related methods to [RsKdeConnectEvent].
extension RsKdeConnectEventPatterns on RsKdeConnectEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsKdeConnectEvent_DevicesChanged value)?  devicesChanged,TResult Function( RsKdeConnectEvent_IncomingPair value)?  incomingPair,TResult Function( RsKdeConnectEvent_PairingFailed value)?  pairingFailed,TResult Function( RsKdeConnectEvent_TrustChanged value)?  trustChanged,TResult Function( RsKdeConnectEvent_PingReceived value)?  pingReceived,TResult Function( RsKdeConnectEvent_ClipboardReceived value)?  clipboardReceived,TResult Function( RsKdeConnectEvent_NotificationsChanged value)?  notificationsChanged,TResult Function( RsKdeConnectEvent_SmsChanged value)?  smsChanged,TResult Function( RsKdeConnectEvent_TelephonyReceived value)?  telephonyReceived,TResult Function( RsKdeConnectEvent_TransferChanged value)?  transferChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that);case RsKdeConnectEvent_PingReceived() when pingReceived != null:
return pingReceived(_that);case RsKdeConnectEvent_ClipboardReceived() when clipboardReceived != null:
return clipboardReceived(_that);case RsKdeConnectEvent_NotificationsChanged() when notificationsChanged != null:
return notificationsChanged(_that);case RsKdeConnectEvent_SmsChanged() when smsChanged != null:
return smsChanged(_that);case RsKdeConnectEvent_TelephonyReceived() when telephonyReceived != null:
return telephonyReceived(_that);case RsKdeConnectEvent_TransferChanged() when transferChanged != null:
return transferChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsKdeConnectEvent_DevicesChanged value)  devicesChanged,required TResult Function( RsKdeConnectEvent_IncomingPair value)  incomingPair,required TResult Function( RsKdeConnectEvent_PairingFailed value)  pairingFailed,required TResult Function( RsKdeConnectEvent_TrustChanged value)  trustChanged,required TResult Function( RsKdeConnectEvent_PingReceived value)  pingReceived,required TResult Function( RsKdeConnectEvent_ClipboardReceived value)  clipboardReceived,required TResult Function( RsKdeConnectEvent_NotificationsChanged value)  notificationsChanged,required TResult Function( RsKdeConnectEvent_SmsChanged value)  smsChanged,required TResult Function( RsKdeConnectEvent_TelephonyReceived value)  telephonyReceived,required TResult Function( RsKdeConnectEvent_TransferChanged value)  transferChanged,}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged():
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair():
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed():
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged():
return trustChanged(_that);case RsKdeConnectEvent_PingReceived():
return pingReceived(_that);case RsKdeConnectEvent_ClipboardReceived():
return clipboardReceived(_that);case RsKdeConnectEvent_NotificationsChanged():
return notificationsChanged(_that);case RsKdeConnectEvent_SmsChanged():
return smsChanged(_that);case RsKdeConnectEvent_TelephonyReceived():
return telephonyReceived(_that);case RsKdeConnectEvent_TransferChanged():
return transferChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsKdeConnectEvent_DevicesChanged value)?  devicesChanged,TResult? Function( RsKdeConnectEvent_IncomingPair value)?  incomingPair,TResult? Function( RsKdeConnectEvent_PairingFailed value)?  pairingFailed,TResult? Function( RsKdeConnectEvent_TrustChanged value)?  trustChanged,TResult? Function( RsKdeConnectEvent_PingReceived value)?  pingReceived,TResult? Function( RsKdeConnectEvent_ClipboardReceived value)?  clipboardReceived,TResult? Function( RsKdeConnectEvent_NotificationsChanged value)?  notificationsChanged,TResult? Function( RsKdeConnectEvent_SmsChanged value)?  smsChanged,TResult? Function( RsKdeConnectEvent_TelephonyReceived value)?  telephonyReceived,TResult? Function( RsKdeConnectEvent_TransferChanged value)?  transferChanged,}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that);case RsKdeConnectEvent_PingReceived() when pingReceived != null:
return pingReceived(_that);case RsKdeConnectEvent_ClipboardReceived() when clipboardReceived != null:
return clipboardReceived(_that);case RsKdeConnectEvent_NotificationsChanged() when notificationsChanged != null:
return notificationsChanged(_that);case RsKdeConnectEvent_SmsChanged() when smsChanged != null:
return smsChanged(_that);case RsKdeConnectEvent_TelephonyReceived() when telephonyReceived != null:
return telephonyReceived(_that);case RsKdeConnectEvent_TransferChanged() when transferChanged != null:
return transferChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<RsKdeConnectDevice> devices)?  devicesChanged,TResult Function( String deviceId,  String name)?  incomingPair,TResult Function( String deviceId,  String reason)?  pairingFailed,TResult Function( List<RsKdeConnectTrustedDevice> devices)?  trustChanged,TResult Function( String deviceId,  String? message)?  pingReceived,TResult Function( String deviceId,  String content,  PlatformInt64 timestampMs)?  clipboardReceived,TResult Function( String deviceId,  List<RsKdeNotification> notifications)?  notificationsChanged,TResult Function( String deviceId,  List<RsKdeSmsConversation> conversations,  List<RsKdeSmsMessage> messages)?  smsChanged,TResult Function( String deviceId,  RsKdeTelephonyEvent event)?  telephonyReceived,TResult Function( RsTransfer transfer)?  transferChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that.devices);case RsKdeConnectEvent_PingReceived() when pingReceived != null:
return pingReceived(_that.deviceId,_that.message);case RsKdeConnectEvent_ClipboardReceived() when clipboardReceived != null:
return clipboardReceived(_that.deviceId,_that.content,_that.timestampMs);case RsKdeConnectEvent_NotificationsChanged() when notificationsChanged != null:
return notificationsChanged(_that.deviceId,_that.notifications);case RsKdeConnectEvent_SmsChanged() when smsChanged != null:
return smsChanged(_that.deviceId,_that.conversations,_that.messages);case RsKdeConnectEvent_TelephonyReceived() when telephonyReceived != null:
return telephonyReceived(_that.deviceId,_that.event);case RsKdeConnectEvent_TransferChanged() when transferChanged != null:
return transferChanged(_that.transfer);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<RsKdeConnectDevice> devices)  devicesChanged,required TResult Function( String deviceId,  String name)  incomingPair,required TResult Function( String deviceId,  String reason)  pairingFailed,required TResult Function( List<RsKdeConnectTrustedDevice> devices)  trustChanged,required TResult Function( String deviceId,  String? message)  pingReceived,required TResult Function( String deviceId,  String content,  PlatformInt64 timestampMs)  clipboardReceived,required TResult Function( String deviceId,  List<RsKdeNotification> notifications)  notificationsChanged,required TResult Function( String deviceId,  List<RsKdeSmsConversation> conversations,  List<RsKdeSmsMessage> messages)  smsChanged,required TResult Function( String deviceId,  RsKdeTelephonyEvent event)  telephonyReceived,required TResult Function( RsTransfer transfer)  transferChanged,}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged():
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair():
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed():
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged():
return trustChanged(_that.devices);case RsKdeConnectEvent_PingReceived():
return pingReceived(_that.deviceId,_that.message);case RsKdeConnectEvent_ClipboardReceived():
return clipboardReceived(_that.deviceId,_that.content,_that.timestampMs);case RsKdeConnectEvent_NotificationsChanged():
return notificationsChanged(_that.deviceId,_that.notifications);case RsKdeConnectEvent_SmsChanged():
return smsChanged(_that.deviceId,_that.conversations,_that.messages);case RsKdeConnectEvent_TelephonyReceived():
return telephonyReceived(_that.deviceId,_that.event);case RsKdeConnectEvent_TransferChanged():
return transferChanged(_that.transfer);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<RsKdeConnectDevice> devices)?  devicesChanged,TResult? Function( String deviceId,  String name)?  incomingPair,TResult? Function( String deviceId,  String reason)?  pairingFailed,TResult? Function( List<RsKdeConnectTrustedDevice> devices)?  trustChanged,TResult? Function( String deviceId,  String? message)?  pingReceived,TResult? Function( String deviceId,  String content,  PlatformInt64 timestampMs)?  clipboardReceived,TResult? Function( String deviceId,  List<RsKdeNotification> notifications)?  notificationsChanged,TResult? Function( String deviceId,  List<RsKdeSmsConversation> conversations,  List<RsKdeSmsMessage> messages)?  smsChanged,TResult? Function( String deviceId,  RsKdeTelephonyEvent event)?  telephonyReceived,TResult? Function( RsTransfer transfer)?  transferChanged,}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that.devices);case RsKdeConnectEvent_PingReceived() when pingReceived != null:
return pingReceived(_that.deviceId,_that.message);case RsKdeConnectEvent_ClipboardReceived() when clipboardReceived != null:
return clipboardReceived(_that.deviceId,_that.content,_that.timestampMs);case RsKdeConnectEvent_NotificationsChanged() when notificationsChanged != null:
return notificationsChanged(_that.deviceId,_that.notifications);case RsKdeConnectEvent_SmsChanged() when smsChanged != null:
return smsChanged(_that.deviceId,_that.conversations,_that.messages);case RsKdeConnectEvent_TelephonyReceived() when telephonyReceived != null:
return telephonyReceived(_that.deviceId,_that.event);case RsKdeConnectEvent_TransferChanged() when transferChanged != null:
return transferChanged(_that.transfer);case _:
  return null;

}
}

}

/// @nodoc


class RsKdeConnectEvent_DevicesChanged extends RsKdeConnectEvent {
  const RsKdeConnectEvent_DevicesChanged({required final  List<RsKdeConnectDevice> devices}): _devices = devices,super._();
  

 final  List<RsKdeConnectDevice> _devices;
 List<RsKdeConnectDevice> get devices {
  if (_devices is EqualUnmodifiableListView) return _devices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_devices);
}


/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_DevicesChangedCopyWith<RsKdeConnectEvent_DevicesChanged> get copyWith => _$RsKdeConnectEvent_DevicesChangedCopyWithImpl<RsKdeConnectEvent_DevicesChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_DevicesChanged&&const DeepCollectionEquality().equals(other._devices, _devices));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_devices));

@override
String toString() {
  return 'RsKdeConnectEvent.devicesChanged(devices: $devices)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_DevicesChangedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_DevicesChangedCopyWith(RsKdeConnectEvent_DevicesChanged value, $Res Function(RsKdeConnectEvent_DevicesChanged) _then) = _$RsKdeConnectEvent_DevicesChangedCopyWithImpl;
@useResult
$Res call({
 List<RsKdeConnectDevice> devices
});




}
/// @nodoc
class _$RsKdeConnectEvent_DevicesChangedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_DevicesChangedCopyWith<$Res> {
  _$RsKdeConnectEvent_DevicesChangedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_DevicesChanged _self;
  final $Res Function(RsKdeConnectEvent_DevicesChanged) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? devices = null,}) {
  return _then(RsKdeConnectEvent_DevicesChanged(
devices: null == devices ? _self._devices : devices // ignore: cast_nullable_to_non_nullable
as List<RsKdeConnectDevice>,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_IncomingPair extends RsKdeConnectEvent {
  const RsKdeConnectEvent_IncomingPair({required this.deviceId, required this.name}): super._();
  

 final  String deviceId;
 final  String name;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_IncomingPairCopyWith<RsKdeConnectEvent_IncomingPair> get copyWith => _$RsKdeConnectEvent_IncomingPairCopyWithImpl<RsKdeConnectEvent_IncomingPair>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_IncomingPair&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,name);

@override
String toString() {
  return 'RsKdeConnectEvent.incomingPair(deviceId: $deviceId, name: $name)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_IncomingPairCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_IncomingPairCopyWith(RsKdeConnectEvent_IncomingPair value, $Res Function(RsKdeConnectEvent_IncomingPair) _then) = _$RsKdeConnectEvent_IncomingPairCopyWithImpl;
@useResult
$Res call({
 String deviceId, String name
});




}
/// @nodoc
class _$RsKdeConnectEvent_IncomingPairCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_IncomingPairCopyWith<$Res> {
  _$RsKdeConnectEvent_IncomingPairCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_IncomingPair _self;
  final $Res Function(RsKdeConnectEvent_IncomingPair) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? name = null,}) {
  return _then(RsKdeConnectEvent_IncomingPair(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_PairingFailed extends RsKdeConnectEvent {
  const RsKdeConnectEvent_PairingFailed({required this.deviceId, required this.reason}): super._();
  

 final  String deviceId;
 final  String reason;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_PairingFailedCopyWith<RsKdeConnectEvent_PairingFailed> get copyWith => _$RsKdeConnectEvent_PairingFailedCopyWithImpl<RsKdeConnectEvent_PairingFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_PairingFailed&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,reason);

@override
String toString() {
  return 'RsKdeConnectEvent.pairingFailed(deviceId: $deviceId, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_PairingFailedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_PairingFailedCopyWith(RsKdeConnectEvent_PairingFailed value, $Res Function(RsKdeConnectEvent_PairingFailed) _then) = _$RsKdeConnectEvent_PairingFailedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String reason
});




}
/// @nodoc
class _$RsKdeConnectEvent_PairingFailedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_PairingFailedCopyWith<$Res> {
  _$RsKdeConnectEvent_PairingFailedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_PairingFailed _self;
  final $Res Function(RsKdeConnectEvent_PairingFailed) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? reason = null,}) {
  return _then(RsKdeConnectEvent_PairingFailed(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_TrustChanged extends RsKdeConnectEvent {
  const RsKdeConnectEvent_TrustChanged({required final  List<RsKdeConnectTrustedDevice> devices}): _devices = devices,super._();
  

 final  List<RsKdeConnectTrustedDevice> _devices;
 List<RsKdeConnectTrustedDevice> get devices {
  if (_devices is EqualUnmodifiableListView) return _devices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_devices);
}


/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_TrustChangedCopyWith<RsKdeConnectEvent_TrustChanged> get copyWith => _$RsKdeConnectEvent_TrustChangedCopyWithImpl<RsKdeConnectEvent_TrustChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_TrustChanged&&const DeepCollectionEquality().equals(other._devices, _devices));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_devices));

@override
String toString() {
  return 'RsKdeConnectEvent.trustChanged(devices: $devices)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_TrustChangedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_TrustChangedCopyWith(RsKdeConnectEvent_TrustChanged value, $Res Function(RsKdeConnectEvent_TrustChanged) _then) = _$RsKdeConnectEvent_TrustChangedCopyWithImpl;
@useResult
$Res call({
 List<RsKdeConnectTrustedDevice> devices
});




}
/// @nodoc
class _$RsKdeConnectEvent_TrustChangedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_TrustChangedCopyWith<$Res> {
  _$RsKdeConnectEvent_TrustChangedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_TrustChanged _self;
  final $Res Function(RsKdeConnectEvent_TrustChanged) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? devices = null,}) {
  return _then(RsKdeConnectEvent_TrustChanged(
devices: null == devices ? _self._devices : devices // ignore: cast_nullable_to_non_nullable
as List<RsKdeConnectTrustedDevice>,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_PingReceived extends RsKdeConnectEvent {
  const RsKdeConnectEvent_PingReceived({required this.deviceId, this.message}): super._();
  

 final  String deviceId;
 final  String? message;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_PingReceivedCopyWith<RsKdeConnectEvent_PingReceived> get copyWith => _$RsKdeConnectEvent_PingReceivedCopyWithImpl<RsKdeConnectEvent_PingReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_PingReceived&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,message);

@override
String toString() {
  return 'RsKdeConnectEvent.pingReceived(deviceId: $deviceId, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_PingReceivedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_PingReceivedCopyWith(RsKdeConnectEvent_PingReceived value, $Res Function(RsKdeConnectEvent_PingReceived) _then) = _$RsKdeConnectEvent_PingReceivedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String? message
});




}
/// @nodoc
class _$RsKdeConnectEvent_PingReceivedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_PingReceivedCopyWith<$Res> {
  _$RsKdeConnectEvent_PingReceivedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_PingReceived _self;
  final $Res Function(RsKdeConnectEvent_PingReceived) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? message = freezed,}) {
  return _then(RsKdeConnectEvent_PingReceived(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_ClipboardReceived extends RsKdeConnectEvent {
  const RsKdeConnectEvent_ClipboardReceived({required this.deviceId, required this.content, required this.timestampMs}): super._();
  

 final  String deviceId;
 final  String content;
 final  PlatformInt64 timestampMs;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_ClipboardReceivedCopyWith<RsKdeConnectEvent_ClipboardReceived> get copyWith => _$RsKdeConnectEvent_ClipboardReceivedCopyWithImpl<RsKdeConnectEvent_ClipboardReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_ClipboardReceived&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.content, content) || other.content == content)&&(identical(other.timestampMs, timestampMs) || other.timestampMs == timestampMs));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,content,timestampMs);

@override
String toString() {
  return 'RsKdeConnectEvent.clipboardReceived(deviceId: $deviceId, content: $content, timestampMs: $timestampMs)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_ClipboardReceivedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_ClipboardReceivedCopyWith(RsKdeConnectEvent_ClipboardReceived value, $Res Function(RsKdeConnectEvent_ClipboardReceived) _then) = _$RsKdeConnectEvent_ClipboardReceivedCopyWithImpl;
@useResult
$Res call({
 String deviceId, String content, PlatformInt64 timestampMs
});




}
/// @nodoc
class _$RsKdeConnectEvent_ClipboardReceivedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_ClipboardReceivedCopyWith<$Res> {
  _$RsKdeConnectEvent_ClipboardReceivedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_ClipboardReceived _self;
  final $Res Function(RsKdeConnectEvent_ClipboardReceived) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? content = null,Object? timestampMs = null,}) {
  return _then(RsKdeConnectEvent_ClipboardReceived(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,timestampMs: null == timestampMs ? _self.timestampMs : timestampMs // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_NotificationsChanged extends RsKdeConnectEvent {
  const RsKdeConnectEvent_NotificationsChanged({required this.deviceId, required final  List<RsKdeNotification> notifications}): _notifications = notifications,super._();
  

 final  String deviceId;
 final  List<RsKdeNotification> _notifications;
 List<RsKdeNotification> get notifications {
  if (_notifications is EqualUnmodifiableListView) return _notifications;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_notifications);
}


/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_NotificationsChangedCopyWith<RsKdeConnectEvent_NotificationsChanged> get copyWith => _$RsKdeConnectEvent_NotificationsChangedCopyWithImpl<RsKdeConnectEvent_NotificationsChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_NotificationsChanged&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&const DeepCollectionEquality().equals(other._notifications, _notifications));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,const DeepCollectionEquality().hash(_notifications));

@override
String toString() {
  return 'RsKdeConnectEvent.notificationsChanged(deviceId: $deviceId, notifications: $notifications)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_NotificationsChangedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_NotificationsChangedCopyWith(RsKdeConnectEvent_NotificationsChanged value, $Res Function(RsKdeConnectEvent_NotificationsChanged) _then) = _$RsKdeConnectEvent_NotificationsChangedCopyWithImpl;
@useResult
$Res call({
 String deviceId, List<RsKdeNotification> notifications
});




}
/// @nodoc
class _$RsKdeConnectEvent_NotificationsChangedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_NotificationsChangedCopyWith<$Res> {
  _$RsKdeConnectEvent_NotificationsChangedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_NotificationsChanged _self;
  final $Res Function(RsKdeConnectEvent_NotificationsChanged) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? notifications = null,}) {
  return _then(RsKdeConnectEvent_NotificationsChanged(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,notifications: null == notifications ? _self._notifications : notifications // ignore: cast_nullable_to_non_nullable
as List<RsKdeNotification>,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_SmsChanged extends RsKdeConnectEvent {
  const RsKdeConnectEvent_SmsChanged({required this.deviceId, required final  List<RsKdeSmsConversation> conversations, required final  List<RsKdeSmsMessage> messages}): _conversations = conversations,_messages = messages,super._();
  

 final  String deviceId;
 final  List<RsKdeSmsConversation> _conversations;
 List<RsKdeSmsConversation> get conversations {
  if (_conversations is EqualUnmodifiableListView) return _conversations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_conversations);
}

 final  List<RsKdeSmsMessage> _messages;
 List<RsKdeSmsMessage> get messages {
  if (_messages is EqualUnmodifiableListView) return _messages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_messages);
}


/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_SmsChangedCopyWith<RsKdeConnectEvent_SmsChanged> get copyWith => _$RsKdeConnectEvent_SmsChangedCopyWithImpl<RsKdeConnectEvent_SmsChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_SmsChanged&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&const DeepCollectionEquality().equals(other._conversations, _conversations)&&const DeepCollectionEquality().equals(other._messages, _messages));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,const DeepCollectionEquality().hash(_conversations),const DeepCollectionEquality().hash(_messages));

@override
String toString() {
  return 'RsKdeConnectEvent.smsChanged(deviceId: $deviceId, conversations: $conversations, messages: $messages)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_SmsChangedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_SmsChangedCopyWith(RsKdeConnectEvent_SmsChanged value, $Res Function(RsKdeConnectEvent_SmsChanged) _then) = _$RsKdeConnectEvent_SmsChangedCopyWithImpl;
@useResult
$Res call({
 String deviceId, List<RsKdeSmsConversation> conversations, List<RsKdeSmsMessage> messages
});




}
/// @nodoc
class _$RsKdeConnectEvent_SmsChangedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_SmsChangedCopyWith<$Res> {
  _$RsKdeConnectEvent_SmsChangedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_SmsChanged _self;
  final $Res Function(RsKdeConnectEvent_SmsChanged) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? conversations = null,Object? messages = null,}) {
  return _then(RsKdeConnectEvent_SmsChanged(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,conversations: null == conversations ? _self._conversations : conversations // ignore: cast_nullable_to_non_nullable
as List<RsKdeSmsConversation>,messages: null == messages ? _self._messages : messages // ignore: cast_nullable_to_non_nullable
as List<RsKdeSmsMessage>,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_TelephonyReceived extends RsKdeConnectEvent {
  const RsKdeConnectEvent_TelephonyReceived({required this.deviceId, required this.event}): super._();
  

 final  String deviceId;
 final  RsKdeTelephonyEvent event;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_TelephonyReceivedCopyWith<RsKdeConnectEvent_TelephonyReceived> get copyWith => _$RsKdeConnectEvent_TelephonyReceivedCopyWithImpl<RsKdeConnectEvent_TelephonyReceived>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_TelephonyReceived&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode => Object.hash(runtimeType,deviceId,event);

@override
String toString() {
  return 'RsKdeConnectEvent.telephonyReceived(deviceId: $deviceId, event: $event)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_TelephonyReceivedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_TelephonyReceivedCopyWith(RsKdeConnectEvent_TelephonyReceived value, $Res Function(RsKdeConnectEvent_TelephonyReceived) _then) = _$RsKdeConnectEvent_TelephonyReceivedCopyWithImpl;
@useResult
$Res call({
 String deviceId, RsKdeTelephonyEvent event
});




}
/// @nodoc
class _$RsKdeConnectEvent_TelephonyReceivedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_TelephonyReceivedCopyWith<$Res> {
  _$RsKdeConnectEvent_TelephonyReceivedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_TelephonyReceived _self;
  final $Res Function(RsKdeConnectEvent_TelephonyReceived) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deviceId = null,Object? event = null,}) {
  return _then(RsKdeConnectEvent_TelephonyReceived(
deviceId: null == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as RsKdeTelephonyEvent,
  ));
}


}

/// @nodoc


class RsKdeConnectEvent_TransferChanged extends RsKdeConnectEvent {
  const RsKdeConnectEvent_TransferChanged({required this.transfer}): super._();
  

 final  RsTransfer transfer;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsKdeConnectEvent_TransferChangedCopyWith<RsKdeConnectEvent_TransferChanged> get copyWith => _$RsKdeConnectEvent_TransferChangedCopyWithImpl<RsKdeConnectEvent_TransferChanged>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsKdeConnectEvent_TransferChanged&&(identical(other.transfer, transfer) || other.transfer == transfer));
}


@override
int get hashCode => Object.hash(runtimeType,transfer);

@override
String toString() {
  return 'RsKdeConnectEvent.transferChanged(transfer: $transfer)';
}


}

/// @nodoc
abstract mixin class $RsKdeConnectEvent_TransferChangedCopyWith<$Res> implements $RsKdeConnectEventCopyWith<$Res> {
  factory $RsKdeConnectEvent_TransferChangedCopyWith(RsKdeConnectEvent_TransferChanged value, $Res Function(RsKdeConnectEvent_TransferChanged) _then) = _$RsKdeConnectEvent_TransferChangedCopyWithImpl;
@useResult
$Res call({
 RsTransfer transfer
});




}
/// @nodoc
class _$RsKdeConnectEvent_TransferChangedCopyWithImpl<$Res>
    implements $RsKdeConnectEvent_TransferChangedCopyWith<$Res> {
  _$RsKdeConnectEvent_TransferChangedCopyWithImpl(this._self, this._then);

  final RsKdeConnectEvent_TransferChanged _self;
  final $Res Function(RsKdeConnectEvent_TransferChanged) _then;

/// Create a copy of RsKdeConnectEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? transfer = null,}) {
  return _then(RsKdeConnectEvent_TransferChanged(
transfer: null == transfer ? _self.transfer : transfer // ignore: cast_nullable_to_non_nullable
as RsTransfer,
  ));
}


}

// dart format on
