// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'relay_anywhere.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsRelayAnywhereEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent()';
}


}

/// @nodoc
class $RsRelayAnywhereEventCopyWith<$Res>  {
$RsRelayAnywhereEventCopyWith(RsRelayAnywhereEvent _, $Res Function(RsRelayAnywhereEvent) __);
}


/// Adds pattern-matching-related methods to [RsRelayAnywhereEvent].
extension RsRelayAnywhereEventPatterns on RsRelayAnywhereEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRelayAnywhereEvent_Starting value)?  starting,TResult Function( RsRelayAnywhereEvent_AddressReady value)?  addressReady,TResult Function( RsRelayAnywhereEvent_WaitingForPeer value)?  waitingForPeer,TResult Function( RsRelayAnywhereEvent_Connecting value)?  connecting,TResult Function( RsRelayAnywhereEvent_PeerConnected value)?  peerConnected,TResult Function( RsRelayAnywhereEvent_TlsEstablished value)?  tlsEstablished,TResult Function( RsRelayAnywhereEvent_PeerAuthenticated value)?  peerAuthenticated,TResult Function( RsRelayAnywhereEvent_IncomingBatch value)?  incomingBatch,TResult Function( RsRelayAnywhereEvent_Transferring value)?  transferring,TResult Function( RsRelayAnywhereEvent_Completed value)?  completed,TResult Function( RsRelayAnywhereEvent_Failed value)?  failed,TResult Function( RsRelayAnywhereEvent_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting() when starting != null:
return starting(_that);case RsRelayAnywhereEvent_AddressReady() when addressReady != null:
return addressReady(_that);case RsRelayAnywhereEvent_WaitingForPeer() when waitingForPeer != null:
return waitingForPeer(_that);case RsRelayAnywhereEvent_Connecting() when connecting != null:
return connecting(_that);case RsRelayAnywhereEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case RsRelayAnywhereEvent_TlsEstablished() when tlsEstablished != null:
return tlsEstablished(_that);case RsRelayAnywhereEvent_PeerAuthenticated() when peerAuthenticated != null:
return peerAuthenticated(_that);case RsRelayAnywhereEvent_IncomingBatch() when incomingBatch != null:
return incomingBatch(_that);case RsRelayAnywhereEvent_Transferring() when transferring != null:
return transferring(_that);case RsRelayAnywhereEvent_Completed() when completed != null:
return completed(_that);case RsRelayAnywhereEvent_Failed() when failed != null:
return failed(_that);case RsRelayAnywhereEvent_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRelayAnywhereEvent_Starting value)  starting,required TResult Function( RsRelayAnywhereEvent_AddressReady value)  addressReady,required TResult Function( RsRelayAnywhereEvent_WaitingForPeer value)  waitingForPeer,required TResult Function( RsRelayAnywhereEvent_Connecting value)  connecting,required TResult Function( RsRelayAnywhereEvent_PeerConnected value)  peerConnected,required TResult Function( RsRelayAnywhereEvent_TlsEstablished value)  tlsEstablished,required TResult Function( RsRelayAnywhereEvent_PeerAuthenticated value)  peerAuthenticated,required TResult Function( RsRelayAnywhereEvent_IncomingBatch value)  incomingBatch,required TResult Function( RsRelayAnywhereEvent_Transferring value)  transferring,required TResult Function( RsRelayAnywhereEvent_Completed value)  completed,required TResult Function( RsRelayAnywhereEvent_Failed value)  failed,required TResult Function( RsRelayAnywhereEvent_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting():
return starting(_that);case RsRelayAnywhereEvent_AddressReady():
return addressReady(_that);case RsRelayAnywhereEvent_WaitingForPeer():
return waitingForPeer(_that);case RsRelayAnywhereEvent_Connecting():
return connecting(_that);case RsRelayAnywhereEvent_PeerConnected():
return peerConnected(_that);case RsRelayAnywhereEvent_TlsEstablished():
return tlsEstablished(_that);case RsRelayAnywhereEvent_PeerAuthenticated():
return peerAuthenticated(_that);case RsRelayAnywhereEvent_IncomingBatch():
return incomingBatch(_that);case RsRelayAnywhereEvent_Transferring():
return transferring(_that);case RsRelayAnywhereEvent_Completed():
return completed(_that);case RsRelayAnywhereEvent_Failed():
return failed(_that);case RsRelayAnywhereEvent_Cancelled():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRelayAnywhereEvent_Starting value)?  starting,TResult? Function( RsRelayAnywhereEvent_AddressReady value)?  addressReady,TResult? Function( RsRelayAnywhereEvent_WaitingForPeer value)?  waitingForPeer,TResult? Function( RsRelayAnywhereEvent_Connecting value)?  connecting,TResult? Function( RsRelayAnywhereEvent_PeerConnected value)?  peerConnected,TResult? Function( RsRelayAnywhereEvent_TlsEstablished value)?  tlsEstablished,TResult? Function( RsRelayAnywhereEvent_PeerAuthenticated value)?  peerAuthenticated,TResult? Function( RsRelayAnywhereEvent_IncomingBatch value)?  incomingBatch,TResult? Function( RsRelayAnywhereEvent_Transferring value)?  transferring,TResult? Function( RsRelayAnywhereEvent_Completed value)?  completed,TResult? Function( RsRelayAnywhereEvent_Failed value)?  failed,TResult? Function( RsRelayAnywhereEvent_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting() when starting != null:
return starting(_that);case RsRelayAnywhereEvent_AddressReady() when addressReady != null:
return addressReady(_that);case RsRelayAnywhereEvent_WaitingForPeer() when waitingForPeer != null:
return waitingForPeer(_that);case RsRelayAnywhereEvent_Connecting() when connecting != null:
return connecting(_that);case RsRelayAnywhereEvent_PeerConnected() when peerConnected != null:
return peerConnected(_that);case RsRelayAnywhereEvent_TlsEstablished() when tlsEstablished != null:
return tlsEstablished(_that);case RsRelayAnywhereEvent_PeerAuthenticated() when peerAuthenticated != null:
return peerAuthenticated(_that);case RsRelayAnywhereEvent_IncomingBatch() when incomingBatch != null:
return incomingBatch(_that);case RsRelayAnywhereEvent_Transferring() when transferring != null:
return transferring(_that);case RsRelayAnywhereEvent_Completed() when completed != null:
return completed(_that);case RsRelayAnywhereEvent_Failed() when failed != null:
return failed(_that);case RsRelayAnywhereEvent_Cancelled() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  starting,TResult Function( String address,  String localRelayId)?  addressReady,TResult Function()?  waitingForPeer,TResult Function()?  connecting,TResult Function()?  peerConnected,TResult Function()?  tlsEstablished,TResult Function( String remoteRelayId)?  peerAuthenticated,TResult Function( BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)?  incomingBatch,TResult Function( BigInt bytes,  BigInt total)?  transferring,TResult Function( String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)?  completed,TResult Function( String message,  String category,  String? stage)?  failed,TResult Function()?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting() when starting != null:
return starting();case RsRelayAnywhereEvent_AddressReady() when addressReady != null:
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereEvent_WaitingForPeer() when waitingForPeer != null:
return waitingForPeer();case RsRelayAnywhereEvent_Connecting() when connecting != null:
return connecting();case RsRelayAnywhereEvent_PeerConnected() when peerConnected != null:
return peerConnected();case RsRelayAnywhereEvent_TlsEstablished() when tlsEstablished != null:
return tlsEstablished();case RsRelayAnywhereEvent_PeerAuthenticated() when peerAuthenticated != null:
return peerAuthenticated(_that.remoteRelayId);case RsRelayAnywhereEvent_IncomingBatch() when incomingBatch != null:
return incomingBatch(_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereEvent_Transferring() when transferring != null:
return transferring(_that.bytes,_that.total);case RsRelayAnywhereEvent_Completed() when completed != null:
return completed(_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereEvent_Failed() when failed != null:
return failed(_that.message,_that.category,_that.stage);case RsRelayAnywhereEvent_Cancelled() when cancelled != null:
return cancelled();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  starting,required TResult Function( String address,  String localRelayId)  addressReady,required TResult Function()  waitingForPeer,required TResult Function()  connecting,required TResult Function()  peerConnected,required TResult Function()  tlsEstablished,required TResult Function( String remoteRelayId)  peerAuthenticated,required TResult Function( BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)  incomingBatch,required TResult Function( BigInt bytes,  BigInt total)  transferring,required TResult Function( String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)  completed,required TResult Function( String message,  String category,  String? stage)  failed,required TResult Function()  cancelled,}) {final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting():
return starting();case RsRelayAnywhereEvent_AddressReady():
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereEvent_WaitingForPeer():
return waitingForPeer();case RsRelayAnywhereEvent_Connecting():
return connecting();case RsRelayAnywhereEvent_PeerConnected():
return peerConnected();case RsRelayAnywhereEvent_TlsEstablished():
return tlsEstablished();case RsRelayAnywhereEvent_PeerAuthenticated():
return peerAuthenticated(_that.remoteRelayId);case RsRelayAnywhereEvent_IncomingBatch():
return incomingBatch(_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereEvent_Transferring():
return transferring(_that.bytes,_that.total);case RsRelayAnywhereEvent_Completed():
return completed(_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereEvent_Failed():
return failed(_that.message,_that.category,_that.stage);case RsRelayAnywhereEvent_Cancelled():
return cancelled();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  starting,TResult? Function( String address,  String localRelayId)?  addressReady,TResult? Function()?  waitingForPeer,TResult? Function()?  connecting,TResult? Function()?  peerConnected,TResult? Function()?  tlsEstablished,TResult? Function( String remoteRelayId)?  peerAuthenticated,TResult? Function( BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)?  incomingBatch,TResult? Function( BigInt bytes,  BigInt total)?  transferring,TResult? Function( String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)?  completed,TResult? Function( String message,  String category,  String? stage)?  failed,TResult? Function()?  cancelled,}) {final _that = this;
switch (_that) {
case RsRelayAnywhereEvent_Starting() when starting != null:
return starting();case RsRelayAnywhereEvent_AddressReady() when addressReady != null:
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereEvent_WaitingForPeer() when waitingForPeer != null:
return waitingForPeer();case RsRelayAnywhereEvent_Connecting() when connecting != null:
return connecting();case RsRelayAnywhereEvent_PeerConnected() when peerConnected != null:
return peerConnected();case RsRelayAnywhereEvent_TlsEstablished() when tlsEstablished != null:
return tlsEstablished();case RsRelayAnywhereEvent_PeerAuthenticated() when peerAuthenticated != null:
return peerAuthenticated(_that.remoteRelayId);case RsRelayAnywhereEvent_IncomingBatch() when incomingBatch != null:
return incomingBatch(_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereEvent_Transferring() when transferring != null:
return transferring(_that.bytes,_that.total);case RsRelayAnywhereEvent_Completed() when completed != null:
return completed(_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereEvent_Failed() when failed != null:
return failed(_that.message,_that.category,_that.stage);case RsRelayAnywhereEvent_Cancelled() when cancelled != null:
return cancelled();case _:
  return null;

}
}

}

/// @nodoc


class RsRelayAnywhereEvent_Starting extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Starting(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Starting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.starting()';
}


}




/// @nodoc


class RsRelayAnywhereEvent_AddressReady extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_AddressReady({required this.address, required this.localRelayId}): super._();


 final  String address;
 final  String localRelayId;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_AddressReadyCopyWith<RsRelayAnywhereEvent_AddressReady> get copyWith => _$RsRelayAnywhereEvent_AddressReadyCopyWithImpl<RsRelayAnywhereEvent_AddressReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_AddressReady&&(identical(other.address, address) || other.address == address)&&(identical(other.localRelayId, localRelayId) || other.localRelayId == localRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,address,localRelayId);

@override
String toString() {
  return 'RsRelayAnywhereEvent.addressReady(address: $address, localRelayId: $localRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_AddressReadyCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_AddressReadyCopyWith(RsRelayAnywhereEvent_AddressReady value, $Res Function(RsRelayAnywhereEvent_AddressReady) _then) = _$RsRelayAnywhereEvent_AddressReadyCopyWithImpl;
@useResult
$Res call({
 String address, String localRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_AddressReadyCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_AddressReadyCopyWith<$Res> {
  _$RsRelayAnywhereEvent_AddressReadyCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_AddressReady _self;
  final $Res Function(RsRelayAnywhereEvent_AddressReady) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? address = null,Object? localRelayId = null,}) {
  return _then(RsRelayAnywhereEvent_AddressReady(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,localRelayId: null == localRelayId ? _self.localRelayId : localRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_WaitingForPeer extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_WaitingForPeer(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_WaitingForPeer);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.waitingForPeer()';
}


}




/// @nodoc


class RsRelayAnywhereEvent_Connecting extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Connecting(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.connecting()';
}


}




/// @nodoc


class RsRelayAnywhereEvent_PeerConnected extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_PeerConnected(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_PeerConnected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.peerConnected()';
}


}




/// @nodoc


class RsRelayAnywhereEvent_TlsEstablished extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_TlsEstablished(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_TlsEstablished);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.tlsEstablished()';
}


}




/// @nodoc


class RsRelayAnywhereEvent_PeerAuthenticated extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_PeerAuthenticated({required this.remoteRelayId}): super._();


 final  String remoteRelayId;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_PeerAuthenticatedCopyWith<RsRelayAnywhereEvent_PeerAuthenticated> get copyWith => _$RsRelayAnywhereEvent_PeerAuthenticatedCopyWithImpl<RsRelayAnywhereEvent_PeerAuthenticated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_PeerAuthenticated&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId);

@override
String toString() {
  return 'RsRelayAnywhereEvent.peerAuthenticated(remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_PeerAuthenticatedCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_PeerAuthenticatedCopyWith(RsRelayAnywhereEvent_PeerAuthenticated value, $Res Function(RsRelayAnywhereEvent_PeerAuthenticated) _then) = _$RsRelayAnywhereEvent_PeerAuthenticatedCopyWithImpl;
@useResult
$Res call({
 String remoteRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_PeerAuthenticatedCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_PeerAuthenticatedCopyWith<$Res> {
  _$RsRelayAnywhereEvent_PeerAuthenticatedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_PeerAuthenticated _self;
  final $Res Function(RsRelayAnywhereEvent_PeerAuthenticated) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,}) {
  return _then(RsRelayAnywhereEvent_PeerAuthenticated(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_IncomingBatch extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_IncomingBatch({required this.transferId, required final  List<RsRelayIncomingFile> files, required this.remoteRelayId}): _files = files,super._();


 final  BigInt transferId;
 final  List<RsRelayIncomingFile> _files;
 List<RsRelayIncomingFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

 final  String remoteRelayId;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_IncomingBatchCopyWith<RsRelayAnywhereEvent_IncomingBatch> get copyWith => _$RsRelayAnywhereEvent_IncomingBatchCopyWithImpl<RsRelayAnywhereEvent_IncomingBatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_IncomingBatch&&(identical(other.transferId, transferId) || other.transferId == transferId)&&const DeepCollectionEquality().equals(other._files, _files)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,const DeepCollectionEquality().hash(_files),remoteRelayId);

@override
String toString() {
  return 'RsRelayAnywhereEvent.incomingBatch(transferId: $transferId, files: $files, remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_IncomingBatchCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_IncomingBatchCopyWith(RsRelayAnywhereEvent_IncomingBatch value, $Res Function(RsRelayAnywhereEvent_IncomingBatch) _then) = _$RsRelayAnywhereEvent_IncomingBatchCopyWithImpl;
@useResult
$Res call({
 BigInt transferId, List<RsRelayIncomingFile> files, String remoteRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_IncomingBatchCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_IncomingBatchCopyWith<$Res> {
  _$RsRelayAnywhereEvent_IncomingBatchCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_IncomingBatch _self;
  final $Res Function(RsRelayAnywhereEvent_IncomingBatch) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? files = null,Object? remoteRelayId = null,}) {
  return _then(RsRelayAnywhereEvent_IncomingBatch(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as BigInt,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<RsRelayIncomingFile>,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_Transferring extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Transferring({required this.bytes, required this.total}): super._();


 final  BigInt bytes;
 final  BigInt total;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_TransferringCopyWith<RsRelayAnywhereEvent_Transferring> get copyWith => _$RsRelayAnywhereEvent_TransferringCopyWithImpl<RsRelayAnywhereEvent_Transferring>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Transferring&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode => Object.hash(runtimeType,bytes,total);

@override
String toString() {
  return 'RsRelayAnywhereEvent.transferring(bytes: $bytes, total: $total)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_TransferringCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_TransferringCopyWith(RsRelayAnywhereEvent_Transferring value, $Res Function(RsRelayAnywhereEvent_Transferring) _then) = _$RsRelayAnywhereEvent_TransferringCopyWithImpl;
@useResult
$Res call({
 BigInt bytes, BigInt total
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_TransferringCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_TransferringCopyWith<$Res> {
  _$RsRelayAnywhereEvent_TransferringCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_Transferring _self;
  final $Res Function(RsRelayAnywhereEvent_Transferring) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,Object? total = null,}) {
  return _then(RsRelayAnywhereEvent_Transferring(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_Completed extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Completed({required this.path, required this.bytes, required this.localRelayId, required this.remoteRelayId, required this.durationMs}): super._();


 final  String path;
 final  BigInt bytes;
 final  String localRelayId;
 final  String remoteRelayId;
 final  BigInt durationMs;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_CompletedCopyWith<RsRelayAnywhereEvent_Completed> get copyWith => _$RsRelayAnywhereEvent_CompletedCopyWithImpl<RsRelayAnywhereEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Completed&&(identical(other.path, path) || other.path == path)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.localRelayId, localRelayId) || other.localRelayId == localRelayId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode => Object.hash(runtimeType,path,bytes,localRelayId,remoteRelayId,durationMs);

@override
String toString() {
  return 'RsRelayAnywhereEvent.completed(path: $path, bytes: $bytes, localRelayId: $localRelayId, remoteRelayId: $remoteRelayId, durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_CompletedCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_CompletedCopyWith(RsRelayAnywhereEvent_Completed value, $Res Function(RsRelayAnywhereEvent_Completed) _then) = _$RsRelayAnywhereEvent_CompletedCopyWithImpl;
@useResult
$Res call({
 String path, BigInt bytes, String localRelayId, String remoteRelayId, BigInt durationMs
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_CompletedCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_CompletedCopyWith<$Res> {
  _$RsRelayAnywhereEvent_CompletedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_Completed _self;
  final $Res Function(RsRelayAnywhereEvent_Completed) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,Object? bytes = null,Object? localRelayId = null,Object? remoteRelayId = null,Object? durationMs = null,}) {
  return _then(RsRelayAnywhereEvent_Completed(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,localRelayId: null == localRelayId ? _self.localRelayId : localRelayId // ignore: cast_nullable_to_non_nullable
as String,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_Failed extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Failed({required this.message, required this.category, this.stage}): super._();


 final  String message;
 final  String category;
 final  String? stage;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereEvent_FailedCopyWith<RsRelayAnywhereEvent_Failed> get copyWith => _$RsRelayAnywhereEvent_FailedCopyWithImpl<RsRelayAnywhereEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Failed&&(identical(other.message, message) || other.message == message)&&(identical(other.category, category) || other.category == category)&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode => Object.hash(runtimeType,message,category,stage);

@override
String toString() {
  return 'RsRelayAnywhereEvent.failed(message: $message, category: $category, stage: $stage)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereEvent_FailedCopyWith<$Res> implements $RsRelayAnywhereEventCopyWith<$Res> {
  factory $RsRelayAnywhereEvent_FailedCopyWith(RsRelayAnywhereEvent_Failed value, $Res Function(RsRelayAnywhereEvent_Failed) _then) = _$RsRelayAnywhereEvent_FailedCopyWithImpl;
@useResult
$Res call({
 String message, String category, String? stage
});




}
/// @nodoc
class _$RsRelayAnywhereEvent_FailedCopyWithImpl<$Res>
    implements $RsRelayAnywhereEvent_FailedCopyWith<$Res> {
  _$RsRelayAnywhereEvent_FailedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereEvent_Failed _self;
  final $Res Function(RsRelayAnywhereEvent_Failed) _then;

/// Create a copy of RsRelayAnywhereEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,Object? category = null,Object? stage = freezed,}) {
  return _then(RsRelayAnywhereEvent_Failed(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsRelayAnywhereEvent_Cancelled extends RsRelayAnywhereEvent {
  const RsRelayAnywhereEvent_Cancelled(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereEvent_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereEvent.cancelled()';
}


}




// dart format on
