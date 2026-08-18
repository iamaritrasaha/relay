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




/// @nodoc
mixin _$RsRelayAnywhereListenerEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent()';
}


}

/// @nodoc
class $RsRelayAnywhereListenerEventCopyWith<$Res>  {
$RsRelayAnywhereListenerEventCopyWith(RsRelayAnywhereListenerEvent _, $Res Function(RsRelayAnywhereListenerEvent) __);
}


/// Adds pattern-matching-related methods to [RsRelayAnywhereListenerEvent].
extension RsRelayAnywhereListenerEventPatterns on RsRelayAnywhereListenerEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRelayAnywhereListenerEvent_AddressReady value)?  addressReady,TResult Function( RsRelayAnywhereListenerEvent_SessionStarting value)?  sessionStarting,TResult Function( RsRelayAnywhereListenerEvent_SessionWaitingForPeer value)?  sessionWaitingForPeer,TResult Function( RsRelayAnywhereListenerEvent_SessionPeerConnected value)?  sessionPeerConnected,TResult Function( RsRelayAnywhereListenerEvent_SessionTlsEstablished value)?  sessionTlsEstablished,TResult Function( RsRelayAnywhereListenerEvent_SessionPeerAuthenticated value)?  sessionPeerAuthenticated,TResult Function( RsRelayAnywhereListenerEvent_SessionIncomingBatch value)?  sessionIncomingBatch,TResult Function( RsRelayAnywhereListenerEvent_SessionTransferring value)?  sessionTransferring,TResult Function( RsRelayAnywhereListenerEvent_SessionCompleted value)?  sessionCompleted,TResult Function( RsRelayAnywhereListenerEvent_SessionCancelled value)?  sessionCancelled,TResult Function( RsRelayAnywhereListenerEvent_SessionFailed value)?  sessionFailed,TResult Function( RsRelayAnywhereListenerEvent_Stopped value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady() when addressReady != null:
return addressReady(_that);case RsRelayAnywhereListenerEvent_SessionStarting() when sessionStarting != null:
return sessionStarting(_that);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer() when sessionWaitingForPeer != null:
return sessionWaitingForPeer(_that);case RsRelayAnywhereListenerEvent_SessionPeerConnected() when sessionPeerConnected != null:
return sessionPeerConnected(_that);case RsRelayAnywhereListenerEvent_SessionTlsEstablished() when sessionTlsEstablished != null:
return sessionTlsEstablished(_that);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated() when sessionPeerAuthenticated != null:
return sessionPeerAuthenticated(_that);case RsRelayAnywhereListenerEvent_SessionIncomingBatch() when sessionIncomingBatch != null:
return sessionIncomingBatch(_that);case RsRelayAnywhereListenerEvent_SessionTransferring() when sessionTransferring != null:
return sessionTransferring(_that);case RsRelayAnywhereListenerEvent_SessionCompleted() when sessionCompleted != null:
return sessionCompleted(_that);case RsRelayAnywhereListenerEvent_SessionCancelled() when sessionCancelled != null:
return sessionCancelled(_that);case RsRelayAnywhereListenerEvent_SessionFailed() when sessionFailed != null:
return sessionFailed(_that);case RsRelayAnywhereListenerEvent_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRelayAnywhereListenerEvent_AddressReady value)  addressReady,required TResult Function( RsRelayAnywhereListenerEvent_SessionStarting value)  sessionStarting,required TResult Function( RsRelayAnywhereListenerEvent_SessionWaitingForPeer value)  sessionWaitingForPeer,required TResult Function( RsRelayAnywhereListenerEvent_SessionPeerConnected value)  sessionPeerConnected,required TResult Function( RsRelayAnywhereListenerEvent_SessionTlsEstablished value)  sessionTlsEstablished,required TResult Function( RsRelayAnywhereListenerEvent_SessionPeerAuthenticated value)  sessionPeerAuthenticated,required TResult Function( RsRelayAnywhereListenerEvent_SessionIncomingBatch value)  sessionIncomingBatch,required TResult Function( RsRelayAnywhereListenerEvent_SessionTransferring value)  sessionTransferring,required TResult Function( RsRelayAnywhereListenerEvent_SessionCompleted value)  sessionCompleted,required TResult Function( RsRelayAnywhereListenerEvent_SessionCancelled value)  sessionCancelled,required TResult Function( RsRelayAnywhereListenerEvent_SessionFailed value)  sessionFailed,required TResult Function( RsRelayAnywhereListenerEvent_Stopped value)  stopped,}){
final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady():
return addressReady(_that);case RsRelayAnywhereListenerEvent_SessionStarting():
return sessionStarting(_that);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer():
return sessionWaitingForPeer(_that);case RsRelayAnywhereListenerEvent_SessionPeerConnected():
return sessionPeerConnected(_that);case RsRelayAnywhereListenerEvent_SessionTlsEstablished():
return sessionTlsEstablished(_that);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated():
return sessionPeerAuthenticated(_that);case RsRelayAnywhereListenerEvent_SessionIncomingBatch():
return sessionIncomingBatch(_that);case RsRelayAnywhereListenerEvent_SessionTransferring():
return sessionTransferring(_that);case RsRelayAnywhereListenerEvent_SessionCompleted():
return sessionCompleted(_that);case RsRelayAnywhereListenerEvent_SessionCancelled():
return sessionCancelled(_that);case RsRelayAnywhereListenerEvent_SessionFailed():
return sessionFailed(_that);case RsRelayAnywhereListenerEvent_Stopped():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRelayAnywhereListenerEvent_AddressReady value)?  addressReady,TResult? Function( RsRelayAnywhereListenerEvent_SessionStarting value)?  sessionStarting,TResult? Function( RsRelayAnywhereListenerEvent_SessionWaitingForPeer value)?  sessionWaitingForPeer,TResult? Function( RsRelayAnywhereListenerEvent_SessionPeerConnected value)?  sessionPeerConnected,TResult? Function( RsRelayAnywhereListenerEvent_SessionTlsEstablished value)?  sessionTlsEstablished,TResult? Function( RsRelayAnywhereListenerEvent_SessionPeerAuthenticated value)?  sessionPeerAuthenticated,TResult? Function( RsRelayAnywhereListenerEvent_SessionIncomingBatch value)?  sessionIncomingBatch,TResult? Function( RsRelayAnywhereListenerEvent_SessionTransferring value)?  sessionTransferring,TResult? Function( RsRelayAnywhereListenerEvent_SessionCompleted value)?  sessionCompleted,TResult? Function( RsRelayAnywhereListenerEvent_SessionCancelled value)?  sessionCancelled,TResult? Function( RsRelayAnywhereListenerEvent_SessionFailed value)?  sessionFailed,TResult? Function( RsRelayAnywhereListenerEvent_Stopped value)?  stopped,}){
final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady() when addressReady != null:
return addressReady(_that);case RsRelayAnywhereListenerEvent_SessionStarting() when sessionStarting != null:
return sessionStarting(_that);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer() when sessionWaitingForPeer != null:
return sessionWaitingForPeer(_that);case RsRelayAnywhereListenerEvent_SessionPeerConnected() when sessionPeerConnected != null:
return sessionPeerConnected(_that);case RsRelayAnywhereListenerEvent_SessionTlsEstablished() when sessionTlsEstablished != null:
return sessionTlsEstablished(_that);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated() when sessionPeerAuthenticated != null:
return sessionPeerAuthenticated(_that);case RsRelayAnywhereListenerEvent_SessionIncomingBatch() when sessionIncomingBatch != null:
return sessionIncomingBatch(_that);case RsRelayAnywhereListenerEvent_SessionTransferring() when sessionTransferring != null:
return sessionTransferring(_that);case RsRelayAnywhereListenerEvent_SessionCompleted() when sessionCompleted != null:
return sessionCompleted(_that);case RsRelayAnywhereListenerEvent_SessionCancelled() when sessionCancelled != null:
return sessionCancelled(_that);case RsRelayAnywhereListenerEvent_SessionFailed() when sessionFailed != null:
return sessionFailed(_that);case RsRelayAnywhereListenerEvent_Stopped() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String address,  String localRelayId)?  addressReady,TResult Function( BigInt sessionId)?  sessionStarting,TResult Function( BigInt sessionId)?  sessionWaitingForPeer,TResult Function( BigInt sessionId)?  sessionPeerConnected,TResult Function( BigInt sessionId)?  sessionTlsEstablished,TResult Function( BigInt sessionId,  String remoteRelayId)?  sessionPeerAuthenticated,TResult Function( BigInt sessionId,  BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)?  sessionIncomingBatch,TResult Function( BigInt sessionId,  BigInt bytes,  BigInt total)?  sessionTransferring,TResult Function( BigInt sessionId,  String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)?  sessionCompleted,TResult Function( BigInt sessionId)?  sessionCancelled,TResult Function( BigInt sessionId,  String message,  String category,  String? stage)?  sessionFailed,TResult Function()?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady() when addressReady != null:
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereListenerEvent_SessionStarting() when sessionStarting != null:
return sessionStarting(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer() when sessionWaitingForPeer != null:
return sessionWaitingForPeer(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerConnected() when sessionPeerConnected != null:
return sessionPeerConnected(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionTlsEstablished() when sessionTlsEstablished != null:
return sessionTlsEstablished(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated() when sessionPeerAuthenticated != null:
return sessionPeerAuthenticated(_that.sessionId,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionIncomingBatch() when sessionIncomingBatch != null:
return sessionIncomingBatch(_that.sessionId,_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionTransferring() when sessionTransferring != null:
return sessionTransferring(_that.sessionId,_that.bytes,_that.total);case RsRelayAnywhereListenerEvent_SessionCompleted() when sessionCompleted != null:
return sessionCompleted(_that.sessionId,_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereListenerEvent_SessionCancelled() when sessionCancelled != null:
return sessionCancelled(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionFailed() when sessionFailed != null:
return sessionFailed(_that.sessionId,_that.message,_that.category,_that.stage);case RsRelayAnywhereListenerEvent_Stopped() when stopped != null:
return stopped();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String address,  String localRelayId)  addressReady,required TResult Function( BigInt sessionId)  sessionStarting,required TResult Function( BigInt sessionId)  sessionWaitingForPeer,required TResult Function( BigInt sessionId)  sessionPeerConnected,required TResult Function( BigInt sessionId)  sessionTlsEstablished,required TResult Function( BigInt sessionId,  String remoteRelayId)  sessionPeerAuthenticated,required TResult Function( BigInt sessionId,  BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)  sessionIncomingBatch,required TResult Function( BigInt sessionId,  BigInt bytes,  BigInt total)  sessionTransferring,required TResult Function( BigInt sessionId,  String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)  sessionCompleted,required TResult Function( BigInt sessionId)  sessionCancelled,required TResult Function( BigInt sessionId,  String message,  String category,  String? stage)  sessionFailed,required TResult Function()  stopped,}) {final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady():
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereListenerEvent_SessionStarting():
return sessionStarting(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer():
return sessionWaitingForPeer(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerConnected():
return sessionPeerConnected(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionTlsEstablished():
return sessionTlsEstablished(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated():
return sessionPeerAuthenticated(_that.sessionId,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionIncomingBatch():
return sessionIncomingBatch(_that.sessionId,_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionTransferring():
return sessionTransferring(_that.sessionId,_that.bytes,_that.total);case RsRelayAnywhereListenerEvent_SessionCompleted():
return sessionCompleted(_that.sessionId,_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereListenerEvent_SessionCancelled():
return sessionCancelled(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionFailed():
return sessionFailed(_that.sessionId,_that.message,_that.category,_that.stage);case RsRelayAnywhereListenerEvent_Stopped():
return stopped();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String address,  String localRelayId)?  addressReady,TResult? Function( BigInt sessionId)?  sessionStarting,TResult? Function( BigInt sessionId)?  sessionWaitingForPeer,TResult? Function( BigInt sessionId)?  sessionPeerConnected,TResult? Function( BigInt sessionId)?  sessionTlsEstablished,TResult? Function( BigInt sessionId,  String remoteRelayId)?  sessionPeerAuthenticated,TResult? Function( BigInt sessionId,  BigInt transferId,  List<RsRelayIncomingFile> files,  String remoteRelayId)?  sessionIncomingBatch,TResult? Function( BigInt sessionId,  BigInt bytes,  BigInt total)?  sessionTransferring,TResult? Function( BigInt sessionId,  String path,  BigInt bytes,  String localRelayId,  String remoteRelayId,  BigInt durationMs)?  sessionCompleted,TResult? Function( BigInt sessionId)?  sessionCancelled,TResult? Function( BigInt sessionId,  String message,  String category,  String? stage)?  sessionFailed,TResult? Function()?  stopped,}) {final _that = this;
switch (_that) {
case RsRelayAnywhereListenerEvent_AddressReady() when addressReady != null:
return addressReady(_that.address,_that.localRelayId);case RsRelayAnywhereListenerEvent_SessionStarting() when sessionStarting != null:
return sessionStarting(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionWaitingForPeer() when sessionWaitingForPeer != null:
return sessionWaitingForPeer(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerConnected() when sessionPeerConnected != null:
return sessionPeerConnected(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionTlsEstablished() when sessionTlsEstablished != null:
return sessionTlsEstablished(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionPeerAuthenticated() when sessionPeerAuthenticated != null:
return sessionPeerAuthenticated(_that.sessionId,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionIncomingBatch() when sessionIncomingBatch != null:
return sessionIncomingBatch(_that.sessionId,_that.transferId,_that.files,_that.remoteRelayId);case RsRelayAnywhereListenerEvent_SessionTransferring() when sessionTransferring != null:
return sessionTransferring(_that.sessionId,_that.bytes,_that.total);case RsRelayAnywhereListenerEvent_SessionCompleted() when sessionCompleted != null:
return sessionCompleted(_that.sessionId,_that.path,_that.bytes,_that.localRelayId,_that.remoteRelayId,_that.durationMs);case RsRelayAnywhereListenerEvent_SessionCancelled() when sessionCancelled != null:
return sessionCancelled(_that.sessionId);case RsRelayAnywhereListenerEvent_SessionFailed() when sessionFailed != null:
return sessionFailed(_that.sessionId,_that.message,_that.category,_that.stage);case RsRelayAnywhereListenerEvent_Stopped() when stopped != null:
return stopped();case _:
  return null;

}
}

}

/// @nodoc


class RsRelayAnywhereListenerEvent_AddressReady extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_AddressReady({required this.address, required this.localRelayId}): super._();


 final  String address;
 final  String localRelayId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_AddressReadyCopyWith<RsRelayAnywhereListenerEvent_AddressReady> get copyWith => _$RsRelayAnywhereListenerEvent_AddressReadyCopyWithImpl<RsRelayAnywhereListenerEvent_AddressReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_AddressReady&&(identical(other.address, address) || other.address == address)&&(identical(other.localRelayId, localRelayId) || other.localRelayId == localRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,address,localRelayId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.addressReady(address: $address, localRelayId: $localRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_AddressReadyCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_AddressReadyCopyWith(RsRelayAnywhereListenerEvent_AddressReady value, $Res Function(RsRelayAnywhereListenerEvent_AddressReady) _then) = _$RsRelayAnywhereListenerEvent_AddressReadyCopyWithImpl;
@useResult
$Res call({
 String address, String localRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_AddressReadyCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_AddressReadyCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_AddressReadyCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_AddressReady _self;
  final $Res Function(RsRelayAnywhereListenerEvent_AddressReady) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? address = null,Object? localRelayId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_AddressReady(
address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,localRelayId: null == localRelayId ? _self.localRelayId : localRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionStarting extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionStarting({required this.sessionId}): super._();


 final  BigInt sessionId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionStartingCopyWith<RsRelayAnywhereListenerEvent_SessionStarting> get copyWith => _$RsRelayAnywhereListenerEvent_SessionStartingCopyWithImpl<RsRelayAnywhereListenerEvent_SessionStarting>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionStarting&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionStarting(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionStartingCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionStartingCopyWith(RsRelayAnywhereListenerEvent_SessionStarting value, $Res Function(RsRelayAnywhereListenerEvent_SessionStarting) _then) = _$RsRelayAnywhereListenerEvent_SessionStartingCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionStartingCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionStartingCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionStartingCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionStarting _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionStarting) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionStarting(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionWaitingForPeer extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionWaitingForPeer({required this.sessionId}): super._();


 final  BigInt sessionId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWith<RsRelayAnywhereListenerEvent_SessionWaitingForPeer> get copyWith => _$RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWithImpl<RsRelayAnywhereListenerEvent_SessionWaitingForPeer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionWaitingForPeer&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionWaitingForPeer(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWith(RsRelayAnywhereListenerEvent_SessionWaitingForPeer value, $Res Function(RsRelayAnywhereListenerEvent_SessionWaitingForPeer) _then) = _$RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionWaitingForPeerCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionWaitingForPeer _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionWaitingForPeer) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionWaitingForPeer(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionPeerConnected extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionPeerConnected({required this.sessionId}): super._();


 final  BigInt sessionId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWith<RsRelayAnywhereListenerEvent_SessionPeerConnected> get copyWith => _$RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWithImpl<RsRelayAnywhereListenerEvent_SessionPeerConnected>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionPeerConnected&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionPeerConnected(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWith(RsRelayAnywhereListenerEvent_SessionPeerConnected value, $Res Function(RsRelayAnywhereListenerEvent_SessionPeerConnected) _then) = _$RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionPeerConnectedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionPeerConnected _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionPeerConnected) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionPeerConnected(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionTlsEstablished extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionTlsEstablished({required this.sessionId}): super._();


 final  BigInt sessionId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWith<RsRelayAnywhereListenerEvent_SessionTlsEstablished> get copyWith => _$RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWithImpl<RsRelayAnywhereListenerEvent_SessionTlsEstablished>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionTlsEstablished&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionTlsEstablished(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWith(RsRelayAnywhereListenerEvent_SessionTlsEstablished value, $Res Function(RsRelayAnywhereListenerEvent_SessionTlsEstablished) _then) = _$RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionTlsEstablishedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionTlsEstablished _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionTlsEstablished) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionTlsEstablished(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionPeerAuthenticated extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionPeerAuthenticated({required this.sessionId, required this.remoteRelayId}): super._();


 final  BigInt sessionId;
 final  String remoteRelayId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWith<RsRelayAnywhereListenerEvent_SessionPeerAuthenticated> get copyWith => _$RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWithImpl<RsRelayAnywhereListenerEvent_SessionPeerAuthenticated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionPeerAuthenticated&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,remoteRelayId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionPeerAuthenticated(sessionId: $sessionId, remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWith(RsRelayAnywhereListenerEvent_SessionPeerAuthenticated value, $Res Function(RsRelayAnywhereListenerEvent_SessionPeerAuthenticated) _then) = _$RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId, String remoteRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionPeerAuthenticatedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionPeerAuthenticated _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionPeerAuthenticated) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? remoteRelayId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionPeerAuthenticated(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionIncomingBatch extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionIncomingBatch({required this.sessionId, required this.transferId, required final  List<RsRelayIncomingFile> files, required this.remoteRelayId}): _files = files,super._();


 final  BigInt sessionId;
 final  BigInt transferId;
 final  List<RsRelayIncomingFile> _files;
 List<RsRelayIncomingFile> get files {
  if (_files is EqualUnmodifiableListView) return _files;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_files);
}

 final  String remoteRelayId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWith<RsRelayAnywhereListenerEvent_SessionIncomingBatch> get copyWith => _$RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWithImpl<RsRelayAnywhereListenerEvent_SessionIncomingBatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionIncomingBatch&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.transferId, transferId) || other.transferId == transferId)&&const DeepCollectionEquality().equals(other._files, _files)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,transferId,const DeepCollectionEquality().hash(_files),remoteRelayId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionIncomingBatch(sessionId: $sessionId, transferId: $transferId, files: $files, remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWith(RsRelayAnywhereListenerEvent_SessionIncomingBatch value, $Res Function(RsRelayAnywhereListenerEvent_SessionIncomingBatch) _then) = _$RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId, BigInt transferId, List<RsRelayIncomingFile> files, String remoteRelayId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionIncomingBatchCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionIncomingBatch _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionIncomingBatch) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? transferId = null,Object? files = null,Object? remoteRelayId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionIncomingBatch(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as BigInt,files: null == files ? _self._files : files // ignore: cast_nullable_to_non_nullable
as List<RsRelayIncomingFile>,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionTransferring extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionTransferring({required this.sessionId, required this.bytes, required this.total}): super._();


 final  BigInt sessionId;
 final  BigInt bytes;
 final  BigInt total;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionTransferringCopyWith<RsRelayAnywhereListenerEvent_SessionTransferring> get copyWith => _$RsRelayAnywhereListenerEvent_SessionTransferringCopyWithImpl<RsRelayAnywhereListenerEvent_SessionTransferring>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionTransferring&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,bytes,total);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionTransferring(sessionId: $sessionId, bytes: $bytes, total: $total)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionTransferringCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionTransferringCopyWith(RsRelayAnywhereListenerEvent_SessionTransferring value, $Res Function(RsRelayAnywhereListenerEvent_SessionTransferring) _then) = _$RsRelayAnywhereListenerEvent_SessionTransferringCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId, BigInt bytes, BigInt total
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionTransferringCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionTransferringCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionTransferringCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionTransferring _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionTransferring) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? bytes = null,Object? total = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionTransferring(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionCompleted extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionCompleted({required this.sessionId, required this.path, required this.bytes, required this.localRelayId, required this.remoteRelayId, required this.durationMs}): super._();


 final  BigInt sessionId;
 final  String path;
 final  BigInt bytes;
 final  String localRelayId;
 final  String remoteRelayId;
 final  BigInt durationMs;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionCompletedCopyWith<RsRelayAnywhereListenerEvent_SessionCompleted> get copyWith => _$RsRelayAnywhereListenerEvent_SessionCompletedCopyWithImpl<RsRelayAnywhereListenerEvent_SessionCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionCompleted&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.path, path) || other.path == path)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.localRelayId, localRelayId) || other.localRelayId == localRelayId)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,path,bytes,localRelayId,remoteRelayId,durationMs);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionCompleted(sessionId: $sessionId, path: $path, bytes: $bytes, localRelayId: $localRelayId, remoteRelayId: $remoteRelayId, durationMs: $durationMs)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionCompletedCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionCompletedCopyWith(RsRelayAnywhereListenerEvent_SessionCompleted value, $Res Function(RsRelayAnywhereListenerEvent_SessionCompleted) _then) = _$RsRelayAnywhereListenerEvent_SessionCompletedCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId, String path, BigInt bytes, String localRelayId, String remoteRelayId, BigInt durationMs
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionCompletedCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionCompletedCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionCompletedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionCompleted _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionCompleted) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? path = null,Object? bytes = null,Object? localRelayId = null,Object? remoteRelayId = null,Object? durationMs = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionCompleted(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,localRelayId: null == localRelayId ? _self.localRelayId : localRelayId // ignore: cast_nullable_to_non_nullable
as String,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionCancelled extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionCancelled({required this.sessionId}): super._();


 final  BigInt sessionId;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionCancelledCopyWith<RsRelayAnywhereListenerEvent_SessionCancelled> get copyWith => _$RsRelayAnywhereListenerEvent_SessionCancelledCopyWithImpl<RsRelayAnywhereListenerEvent_SessionCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionCancelled&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionCancelled(sessionId: $sessionId)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionCancelledCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionCancelledCopyWith(RsRelayAnywhereListenerEvent_SessionCancelled value, $Res Function(RsRelayAnywhereListenerEvent_SessionCancelled) _then) = _$RsRelayAnywhereListenerEvent_SessionCancelledCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionCancelledCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionCancelledCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionCancelledCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionCancelled _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionCancelled) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionCancelled(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_SessionFailed extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_SessionFailed({required this.sessionId, required this.message, required this.category, this.stage}): super._();


 final  BigInt sessionId;
 final  String message;
 final  String category;
 final  String? stage;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayAnywhereListenerEvent_SessionFailedCopyWith<RsRelayAnywhereListenerEvent_SessionFailed> get copyWith => _$RsRelayAnywhereListenerEvent_SessionFailedCopyWithImpl<RsRelayAnywhereListenerEvent_SessionFailed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_SessionFailed&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.message, message) || other.message == message)&&(identical(other.category, category) || other.category == category)&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode => Object.hash(runtimeType,sessionId,message,category,stage);

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.sessionFailed(sessionId: $sessionId, message: $message, category: $category, stage: $stage)';
}


}

/// @nodoc
abstract mixin class $RsRelayAnywhereListenerEvent_SessionFailedCopyWith<$Res> implements $RsRelayAnywhereListenerEventCopyWith<$Res> {
  factory $RsRelayAnywhereListenerEvent_SessionFailedCopyWith(RsRelayAnywhereListenerEvent_SessionFailed value, $Res Function(RsRelayAnywhereListenerEvent_SessionFailed) _then) = _$RsRelayAnywhereListenerEvent_SessionFailedCopyWithImpl;
@useResult
$Res call({
 BigInt sessionId, String message, String category, String? stage
});




}
/// @nodoc
class _$RsRelayAnywhereListenerEvent_SessionFailedCopyWithImpl<$Res>
    implements $RsRelayAnywhereListenerEvent_SessionFailedCopyWith<$Res> {
  _$RsRelayAnywhereListenerEvent_SessionFailedCopyWithImpl(this._self, this._then);

  final RsRelayAnywhereListenerEvent_SessionFailed _self;
  final $Res Function(RsRelayAnywhereListenerEvent_SessionFailed) _then;

/// Create a copy of RsRelayAnywhereListenerEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sessionId = null,Object? message = null,Object? category = null,Object? stage = freezed,}) {
  return _then(RsRelayAnywhereListenerEvent_SessionFailed(
sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as BigInt,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,stage: freezed == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsRelayAnywhereListenerEvent_Stopped extends RsRelayAnywhereListenerEvent {
  const RsRelayAnywhereListenerEvent_Stopped(): super._();







@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayAnywhereListenerEvent_Stopped);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayAnywhereListenerEvent.stopped()';
}


}




// dart format on
