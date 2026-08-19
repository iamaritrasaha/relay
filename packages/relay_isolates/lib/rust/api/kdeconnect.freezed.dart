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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsKdeConnectEvent_DevicesChanged value)?  devicesChanged,TResult Function( RsKdeConnectEvent_IncomingPair value)?  incomingPair,TResult Function( RsKdeConnectEvent_PairingFailed value)?  pairingFailed,TResult Function( RsKdeConnectEvent_TrustChanged value)?  trustChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsKdeConnectEvent_DevicesChanged value)  devicesChanged,required TResult Function( RsKdeConnectEvent_IncomingPair value)  incomingPair,required TResult Function( RsKdeConnectEvent_PairingFailed value)  pairingFailed,required TResult Function( RsKdeConnectEvent_TrustChanged value)  trustChanged,}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged():
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair():
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed():
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged():
return trustChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsKdeConnectEvent_DevicesChanged value)?  devicesChanged,TResult? Function( RsKdeConnectEvent_IncomingPair value)?  incomingPair,TResult? Function( RsKdeConnectEvent_PairingFailed value)?  pairingFailed,TResult? Function( RsKdeConnectEvent_TrustChanged value)?  trustChanged,}){
final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<RsKdeConnectDevice> devices)?  devicesChanged,TResult Function( String deviceId,  String name)?  incomingPair,TResult Function( String deviceId,  String reason)?  pairingFailed,TResult Function( List<RsKdeConnectTrustedDevice> devices)?  trustChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that.devices);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<RsKdeConnectDevice> devices)  devicesChanged,required TResult Function( String deviceId,  String name)  incomingPair,required TResult Function( String deviceId,  String reason)  pairingFailed,required TResult Function( List<RsKdeConnectTrustedDevice> devices)  trustChanged,}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged():
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair():
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed():
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged():
return trustChanged(_that.devices);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<RsKdeConnectDevice> devices)?  devicesChanged,TResult? Function( String deviceId,  String name)?  incomingPair,TResult? Function( String deviceId,  String reason)?  pairingFailed,TResult? Function( List<RsKdeConnectTrustedDevice> devices)?  trustChanged,}) {final _that = this;
switch (_that) {
case RsKdeConnectEvent_DevicesChanged() when devicesChanged != null:
return devicesChanged(_that.devices);case RsKdeConnectEvent_IncomingPair() when incomingPair != null:
return incomingPair(_that.deviceId,_that.name);case RsKdeConnectEvent_PairingFailed() when pairingFailed != null:
return pairingFailed(_that.deviceId,_that.reason);case RsKdeConnectEvent_TrustChanged() when trustChanged != null:
return trustChanged(_that.devices);case _:
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

// dart format on
