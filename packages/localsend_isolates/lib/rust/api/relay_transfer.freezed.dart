// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'relay_transfer.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsRelayTransferEvent {

 String get transferId;
/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEventCopyWith<RsRelayTransferEvent> get copyWith => _$RsRelayTransferEventCopyWithImpl<RsRelayTransferEvent>(this as RsRelayTransferEvent, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent&&(identical(other.transferId, transferId) || other.transferId == transferId));
}


@override
int get hashCode => Object.hash(runtimeType,transferId);

@override
String toString() {
  return 'RsRelayTransferEvent(transferId: $transferId)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEventCopyWith<$Res>  {
  factory $RsRelayTransferEventCopyWith(RsRelayTransferEvent value, $Res Function(RsRelayTransferEvent) _then) = _$RsRelayTransferEventCopyWithImpl;
@useResult
$Res call({
 String transferId
});




}
/// @nodoc
class _$RsRelayTransferEventCopyWithImpl<$Res>
    implements $RsRelayTransferEventCopyWith<$Res> {
  _$RsRelayTransferEventCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent _self;
  final $Res Function(RsRelayTransferEvent) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? transferId = null,}) {
  return _then(_self.copyWith(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RsRelayTransferEvent].
extension RsRelayTransferEventPatterns on RsRelayTransferEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRelayTransferEvent_OutgoingStarted value)?  outgoingStarted,TResult Function( RsRelayTransferEvent_Accepted value)?  accepted,TResult Function( RsRelayTransferEvent_Declined value)?  declined,TResult Function( RsRelayTransferEvent_FileStarted value)?  fileStarted,TResult Function( RsRelayTransferEvent_FileProgress value)?  fileProgress,TResult Function( RsRelayTransferEvent_OverallProgress value)?  overallProgress,TResult Function( RsRelayTransferEvent_Completed value)?  completed,TResult Function( RsRelayTransferEvent_Failed value)?  failed,TResult Function( RsRelayTransferEvent_Cancelled value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted() when outgoingStarted != null:
return outgoingStarted(_that);case RsRelayTransferEvent_Accepted() when accepted != null:
return accepted(_that);case RsRelayTransferEvent_Declined() when declined != null:
return declined(_that);case RsRelayTransferEvent_FileStarted() when fileStarted != null:
return fileStarted(_that);case RsRelayTransferEvent_FileProgress() when fileProgress != null:
return fileProgress(_that);case RsRelayTransferEvent_OverallProgress() when overallProgress != null:
return overallProgress(_that);case RsRelayTransferEvent_Completed() when completed != null:
return completed(_that);case RsRelayTransferEvent_Failed() when failed != null:
return failed(_that);case RsRelayTransferEvent_Cancelled() when cancelled != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRelayTransferEvent_OutgoingStarted value)  outgoingStarted,required TResult Function( RsRelayTransferEvent_Accepted value)  accepted,required TResult Function( RsRelayTransferEvent_Declined value)  declined,required TResult Function( RsRelayTransferEvent_FileStarted value)  fileStarted,required TResult Function( RsRelayTransferEvent_FileProgress value)  fileProgress,required TResult Function( RsRelayTransferEvent_OverallProgress value)  overallProgress,required TResult Function( RsRelayTransferEvent_Completed value)  completed,required TResult Function( RsRelayTransferEvent_Failed value)  failed,required TResult Function( RsRelayTransferEvent_Cancelled value)  cancelled,}){
final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted():
return outgoingStarted(_that);case RsRelayTransferEvent_Accepted():
return accepted(_that);case RsRelayTransferEvent_Declined():
return declined(_that);case RsRelayTransferEvent_FileStarted():
return fileStarted(_that);case RsRelayTransferEvent_FileProgress():
return fileProgress(_that);case RsRelayTransferEvent_OverallProgress():
return overallProgress(_that);case RsRelayTransferEvent_Completed():
return completed(_that);case RsRelayTransferEvent_Failed():
return failed(_that);case RsRelayTransferEvent_Cancelled():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRelayTransferEvent_OutgoingStarted value)?  outgoingStarted,TResult? Function( RsRelayTransferEvent_Accepted value)?  accepted,TResult? Function( RsRelayTransferEvent_Declined value)?  declined,TResult? Function( RsRelayTransferEvent_FileStarted value)?  fileStarted,TResult? Function( RsRelayTransferEvent_FileProgress value)?  fileProgress,TResult? Function( RsRelayTransferEvent_OverallProgress value)?  overallProgress,TResult? Function( RsRelayTransferEvent_Completed value)?  completed,TResult? Function( RsRelayTransferEvent_Failed value)?  failed,TResult? Function( RsRelayTransferEvent_Cancelled value)?  cancelled,}){
final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted() when outgoingStarted != null:
return outgoingStarted(_that);case RsRelayTransferEvent_Accepted() when accepted != null:
return accepted(_that);case RsRelayTransferEvent_Declined() when declined != null:
return declined(_that);case RsRelayTransferEvent_FileStarted() when fileStarted != null:
return fileStarted(_that);case RsRelayTransferEvent_FileProgress() when fileProgress != null:
return fileProgress(_that);case RsRelayTransferEvent_OverallProgress() when overallProgress != null:
return overallProgress(_that);case RsRelayTransferEvent_Completed() when completed != null:
return completed(_that);case RsRelayTransferEvent_Failed() when failed != null:
return failed(_that);case RsRelayTransferEvent_Cancelled() when cancelled != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String transferId,  BigInt totalBytes,  String origin)?  outgoingStarted,TResult Function( String transferId,  String sessionId,  List<String> acceptedFileIds,  BigInt totalBytes,  String origin)?  accepted,TResult Function( String transferId,  String? fileId,  String origin)?  declined,TResult Function( String transferId,  String sessionId,  String fileId,  String fileName,  int fileIndex,  int fileCount,  BigInt totalBytes,  String origin)?  fileStarted,TResult Function( String transferId,  String sessionId,  String fileId,  BigInt bytes,  BigInt totalBytes,  String origin)?  fileProgress,TResult Function( String transferId,  String sessionId,  BigInt bytes,  BigInt totalBytes,  String origin)?  overallProgress,TResult Function( String transferId,  String? sessionId,  BigInt bytes,  String origin)?  completed,TResult Function( String transferId,  String category)?  failed,TResult Function( String transferId)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted() when outgoingStarted != null:
return outgoingStarted(_that.transferId,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Accepted() when accepted != null:
return accepted(_that.transferId,_that.sessionId,_that.acceptedFileIds,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Declined() when declined != null:
return declined(_that.transferId,_that.fileId,_that.origin);case RsRelayTransferEvent_FileStarted() when fileStarted != null:
return fileStarted(_that.transferId,_that.sessionId,_that.fileId,_that.fileName,_that.fileIndex,_that.fileCount,_that.totalBytes,_that.origin);case RsRelayTransferEvent_FileProgress() when fileProgress != null:
return fileProgress(_that.transferId,_that.sessionId,_that.fileId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_OverallProgress() when overallProgress != null:
return overallProgress(_that.transferId,_that.sessionId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Completed() when completed != null:
return completed(_that.transferId,_that.sessionId,_that.bytes,_that.origin);case RsRelayTransferEvent_Failed() when failed != null:
return failed(_that.transferId,_that.category);case RsRelayTransferEvent_Cancelled() when cancelled != null:
return cancelled(_that.transferId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String transferId,  BigInt totalBytes,  String origin)  outgoingStarted,required TResult Function( String transferId,  String sessionId,  List<String> acceptedFileIds,  BigInt totalBytes,  String origin)  accepted,required TResult Function( String transferId,  String? fileId,  String origin)  declined,required TResult Function( String transferId,  String sessionId,  String fileId,  String fileName,  int fileIndex,  int fileCount,  BigInt totalBytes,  String origin)  fileStarted,required TResult Function( String transferId,  String sessionId,  String fileId,  BigInt bytes,  BigInt totalBytes,  String origin)  fileProgress,required TResult Function( String transferId,  String sessionId,  BigInt bytes,  BigInt totalBytes,  String origin)  overallProgress,required TResult Function( String transferId,  String? sessionId,  BigInt bytes,  String origin)  completed,required TResult Function( String transferId,  String category)  failed,required TResult Function( String transferId)  cancelled,}) {final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted():
return outgoingStarted(_that.transferId,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Accepted():
return accepted(_that.transferId,_that.sessionId,_that.acceptedFileIds,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Declined():
return declined(_that.transferId,_that.fileId,_that.origin);case RsRelayTransferEvent_FileStarted():
return fileStarted(_that.transferId,_that.sessionId,_that.fileId,_that.fileName,_that.fileIndex,_that.fileCount,_that.totalBytes,_that.origin);case RsRelayTransferEvent_FileProgress():
return fileProgress(_that.transferId,_that.sessionId,_that.fileId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_OverallProgress():
return overallProgress(_that.transferId,_that.sessionId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Completed():
return completed(_that.transferId,_that.sessionId,_that.bytes,_that.origin);case RsRelayTransferEvent_Failed():
return failed(_that.transferId,_that.category);case RsRelayTransferEvent_Cancelled():
return cancelled(_that.transferId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String transferId,  BigInt totalBytes,  String origin)?  outgoingStarted,TResult? Function( String transferId,  String sessionId,  List<String> acceptedFileIds,  BigInt totalBytes,  String origin)?  accepted,TResult? Function( String transferId,  String? fileId,  String origin)?  declined,TResult? Function( String transferId,  String sessionId,  String fileId,  String fileName,  int fileIndex,  int fileCount,  BigInt totalBytes,  String origin)?  fileStarted,TResult? Function( String transferId,  String sessionId,  String fileId,  BigInt bytes,  BigInt totalBytes,  String origin)?  fileProgress,TResult? Function( String transferId,  String sessionId,  BigInt bytes,  BigInt totalBytes,  String origin)?  overallProgress,TResult? Function( String transferId,  String? sessionId,  BigInt bytes,  String origin)?  completed,TResult? Function( String transferId,  String category)?  failed,TResult? Function( String transferId)?  cancelled,}) {final _that = this;
switch (_that) {
case RsRelayTransferEvent_OutgoingStarted() when outgoingStarted != null:
return outgoingStarted(_that.transferId,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Accepted() when accepted != null:
return accepted(_that.transferId,_that.sessionId,_that.acceptedFileIds,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Declined() when declined != null:
return declined(_that.transferId,_that.fileId,_that.origin);case RsRelayTransferEvent_FileStarted() when fileStarted != null:
return fileStarted(_that.transferId,_that.sessionId,_that.fileId,_that.fileName,_that.fileIndex,_that.fileCount,_that.totalBytes,_that.origin);case RsRelayTransferEvent_FileProgress() when fileProgress != null:
return fileProgress(_that.transferId,_that.sessionId,_that.fileId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_OverallProgress() when overallProgress != null:
return overallProgress(_that.transferId,_that.sessionId,_that.bytes,_that.totalBytes,_that.origin);case RsRelayTransferEvent_Completed() when completed != null:
return completed(_that.transferId,_that.sessionId,_that.bytes,_that.origin);case RsRelayTransferEvent_Failed() when failed != null:
return failed(_that.transferId,_that.category);case RsRelayTransferEvent_Cancelled() when cancelled != null:
return cancelled(_that.transferId);case _:
  return null;

}
}

}

/// @nodoc


class RsRelayTransferEvent_OutgoingStarted extends RsRelayTransferEvent {
  const RsRelayTransferEvent_OutgoingStarted({required this.transferId, required this.totalBytes, required this.origin}): super._();


@override final  String transferId;
 final  BigInt totalBytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_OutgoingStartedCopyWith<RsRelayTransferEvent_OutgoingStarted> get copyWith => _$RsRelayTransferEvent_OutgoingStartedCopyWithImpl<RsRelayTransferEvent_OutgoingStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_OutgoingStarted&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,totalBytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.outgoingStarted(transferId: $transferId, totalBytes: $totalBytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_OutgoingStartedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_OutgoingStartedCopyWith(RsRelayTransferEvent_OutgoingStarted value, $Res Function(RsRelayTransferEvent_OutgoingStarted) _then) = _$RsRelayTransferEvent_OutgoingStartedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, BigInt totalBytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_OutgoingStartedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_OutgoingStartedCopyWith<$Res> {
  _$RsRelayTransferEvent_OutgoingStartedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_OutgoingStarted _self;
  final $Res Function(RsRelayTransferEvent_OutgoingStarted) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? totalBytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_OutgoingStarted(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_Accepted extends RsRelayTransferEvent {
  const RsRelayTransferEvent_Accepted({required this.transferId, required this.sessionId, required final  List<String> acceptedFileIds, required this.totalBytes, required this.origin}): _acceptedFileIds = acceptedFileIds,super._();


@override final  String transferId;
 final  String sessionId;
 final  List<String> _acceptedFileIds;
 List<String> get acceptedFileIds {
  if (_acceptedFileIds is EqualUnmodifiableListView) return _acceptedFileIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_acceptedFileIds);
}

 final  BigInt totalBytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_AcceptedCopyWith<RsRelayTransferEvent_Accepted> get copyWith => _$RsRelayTransferEvent_AcceptedCopyWithImpl<RsRelayTransferEvent_Accepted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_Accepted&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&const DeepCollectionEquality().equals(other._acceptedFileIds, _acceptedFileIds)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,sessionId,const DeepCollectionEquality().hash(_acceptedFileIds),totalBytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.accepted(transferId: $transferId, sessionId: $sessionId, acceptedFileIds: $acceptedFileIds, totalBytes: $totalBytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_AcceptedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_AcceptedCopyWith(RsRelayTransferEvent_Accepted value, $Res Function(RsRelayTransferEvent_Accepted) _then) = _$RsRelayTransferEvent_AcceptedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String sessionId, List<String> acceptedFileIds, BigInt totalBytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_AcceptedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_AcceptedCopyWith<$Res> {
  _$RsRelayTransferEvent_AcceptedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_Accepted _self;
  final $Res Function(RsRelayTransferEvent_Accepted) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? sessionId = null,Object? acceptedFileIds = null,Object? totalBytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_Accepted(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,acceptedFileIds: null == acceptedFileIds ? _self._acceptedFileIds : acceptedFileIds // ignore: cast_nullable_to_non_nullable
as List<String>,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_Declined extends RsRelayTransferEvent {
  const RsRelayTransferEvent_Declined({required this.transferId, this.fileId, required this.origin}): super._();


@override final  String transferId;
 final  String? fileId;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_DeclinedCopyWith<RsRelayTransferEvent_Declined> get copyWith => _$RsRelayTransferEvent_DeclinedCopyWithImpl<RsRelayTransferEvent_Declined>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_Declined&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.fileId, fileId) || other.fileId == fileId)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,fileId,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.declined(transferId: $transferId, fileId: $fileId, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_DeclinedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_DeclinedCopyWith(RsRelayTransferEvent_Declined value, $Res Function(RsRelayTransferEvent_Declined) _then) = _$RsRelayTransferEvent_DeclinedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String? fileId, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_DeclinedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_DeclinedCopyWith<$Res> {
  _$RsRelayTransferEvent_DeclinedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_Declined _self;
  final $Res Function(RsRelayTransferEvent_Declined) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? fileId = freezed,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_Declined(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,fileId: freezed == fileId ? _self.fileId : fileId // ignore: cast_nullable_to_non_nullable
as String?,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_FileStarted extends RsRelayTransferEvent {
  const RsRelayTransferEvent_FileStarted({required this.transferId, required this.sessionId, required this.fileId, required this.fileName, required this.fileIndex, required this.fileCount, required this.totalBytes, required this.origin}): super._();


@override final  String transferId;
 final  String sessionId;
 final  String fileId;
 final  String fileName;
 final  int fileIndex;
 final  int fileCount;
 final  BigInt totalBytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_FileStartedCopyWith<RsRelayTransferEvent_FileStarted> get copyWith => _$RsRelayTransferEvent_FileStartedCopyWithImpl<RsRelayTransferEvent_FileStarted>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_FileStarted&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.fileId, fileId) || other.fileId == fileId)&&(identical(other.fileName, fileName) || other.fileName == fileName)&&(identical(other.fileIndex, fileIndex) || other.fileIndex == fileIndex)&&(identical(other.fileCount, fileCount) || other.fileCount == fileCount)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,sessionId,fileId,fileName,fileIndex,fileCount,totalBytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.fileStarted(transferId: $transferId, sessionId: $sessionId, fileId: $fileId, fileName: $fileName, fileIndex: $fileIndex, fileCount: $fileCount, totalBytes: $totalBytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_FileStartedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_FileStartedCopyWith(RsRelayTransferEvent_FileStarted value, $Res Function(RsRelayTransferEvent_FileStarted) _then) = _$RsRelayTransferEvent_FileStartedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String sessionId, String fileId, String fileName, int fileIndex, int fileCount, BigInt totalBytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_FileStartedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_FileStartedCopyWith<$Res> {
  _$RsRelayTransferEvent_FileStartedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_FileStarted _self;
  final $Res Function(RsRelayTransferEvent_FileStarted) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? sessionId = null,Object? fileId = null,Object? fileName = null,Object? fileIndex = null,Object? fileCount = null,Object? totalBytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_FileStarted(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,fileId: null == fileId ? _self.fileId : fileId // ignore: cast_nullable_to_non_nullable
as String,fileName: null == fileName ? _self.fileName : fileName // ignore: cast_nullable_to_non_nullable
as String,fileIndex: null == fileIndex ? _self.fileIndex : fileIndex // ignore: cast_nullable_to_non_nullable
as int,fileCount: null == fileCount ? _self.fileCount : fileCount // ignore: cast_nullable_to_non_nullable
as int,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_FileProgress extends RsRelayTransferEvent {
  const RsRelayTransferEvent_FileProgress({required this.transferId, required this.sessionId, required this.fileId, required this.bytes, required this.totalBytes, required this.origin}): super._();


@override final  String transferId;
 final  String sessionId;
 final  String fileId;
 final  BigInt bytes;
 final  BigInt totalBytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_FileProgressCopyWith<RsRelayTransferEvent_FileProgress> get copyWith => _$RsRelayTransferEvent_FileProgressCopyWithImpl<RsRelayTransferEvent_FileProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_FileProgress&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.fileId, fileId) || other.fileId == fileId)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,sessionId,fileId,bytes,totalBytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.fileProgress(transferId: $transferId, sessionId: $sessionId, fileId: $fileId, bytes: $bytes, totalBytes: $totalBytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_FileProgressCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_FileProgressCopyWith(RsRelayTransferEvent_FileProgress value, $Res Function(RsRelayTransferEvent_FileProgress) _then) = _$RsRelayTransferEvent_FileProgressCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String sessionId, String fileId, BigInt bytes, BigInt totalBytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_FileProgressCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_FileProgressCopyWith<$Res> {
  _$RsRelayTransferEvent_FileProgressCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_FileProgress _self;
  final $Res Function(RsRelayTransferEvent_FileProgress) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? sessionId = null,Object? fileId = null,Object? bytes = null,Object? totalBytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_FileProgress(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,fileId: null == fileId ? _self.fileId : fileId // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_OverallProgress extends RsRelayTransferEvent {
  const RsRelayTransferEvent_OverallProgress({required this.transferId, required this.sessionId, required this.bytes, required this.totalBytes, required this.origin}): super._();


@override final  String transferId;
 final  String sessionId;
 final  BigInt bytes;
 final  BigInt totalBytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_OverallProgressCopyWith<RsRelayTransferEvent_OverallProgress> get copyWith => _$RsRelayTransferEvent_OverallProgressCopyWithImpl<RsRelayTransferEvent_OverallProgress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_OverallProgress&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,sessionId,bytes,totalBytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.overallProgress(transferId: $transferId, sessionId: $sessionId, bytes: $bytes, totalBytes: $totalBytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_OverallProgressCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_OverallProgressCopyWith(RsRelayTransferEvent_OverallProgress value, $Res Function(RsRelayTransferEvent_OverallProgress) _then) = _$RsRelayTransferEvent_OverallProgressCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String sessionId, BigInt bytes, BigInt totalBytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_OverallProgressCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_OverallProgressCopyWith<$Res> {
  _$RsRelayTransferEvent_OverallProgressCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_OverallProgress _self;
  final $Res Function(RsRelayTransferEvent_OverallProgress) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? sessionId = null,Object? bytes = null,Object? totalBytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_OverallProgress(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,sessionId: null == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,totalBytes: null == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_Completed extends RsRelayTransferEvent {
  const RsRelayTransferEvent_Completed({required this.transferId, this.sessionId, required this.bytes, required this.origin}): super._();


@override final  String transferId;
 final  String? sessionId;
 final  BigInt bytes;
 final  String origin;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_CompletedCopyWith<RsRelayTransferEvent_Completed> get copyWith => _$RsRelayTransferEvent_CompletedCopyWithImpl<RsRelayTransferEvent_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_Completed&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.sessionId, sessionId) || other.sessionId == sessionId)&&(identical(other.bytes, bytes) || other.bytes == bytes)&&(identical(other.origin, origin) || other.origin == origin));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,sessionId,bytes,origin);

@override
String toString() {
  return 'RsRelayTransferEvent.completed(transferId: $transferId, sessionId: $sessionId, bytes: $bytes, origin: $origin)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_CompletedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_CompletedCopyWith(RsRelayTransferEvent_Completed value, $Res Function(RsRelayTransferEvent_Completed) _then) = _$RsRelayTransferEvent_CompletedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String? sessionId, BigInt bytes, String origin
});




}
/// @nodoc
class _$RsRelayTransferEvent_CompletedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_CompletedCopyWith<$Res> {
  _$RsRelayTransferEvent_CompletedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_Completed _self;
  final $Res Function(RsRelayTransferEvent_Completed) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? sessionId = freezed,Object? bytes = null,Object? origin = null,}) {
  return _then(RsRelayTransferEvent_Completed(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,sessionId: freezed == sessionId ? _self.sessionId : sessionId // ignore: cast_nullable_to_non_nullable
as String?,bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as BigInt,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_Failed extends RsRelayTransferEvent {
  const RsRelayTransferEvent_Failed({required this.transferId, required this.category}): super._();


@override final  String transferId;
 final  String category;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_FailedCopyWith<RsRelayTransferEvent_Failed> get copyWith => _$RsRelayTransferEvent_FailedCopyWithImpl<RsRelayTransferEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_Failed&&(identical(other.transferId, transferId) || other.transferId == transferId)&&(identical(other.category, category) || other.category == category));
}


@override
int get hashCode => Object.hash(runtimeType,transferId,category);

@override
String toString() {
  return 'RsRelayTransferEvent.failed(transferId: $transferId, category: $category)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_FailedCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_FailedCopyWith(RsRelayTransferEvent_Failed value, $Res Function(RsRelayTransferEvent_Failed) _then) = _$RsRelayTransferEvent_FailedCopyWithImpl;
@override @useResult
$Res call({
 String transferId, String category
});




}
/// @nodoc
class _$RsRelayTransferEvent_FailedCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_FailedCopyWith<$Res> {
  _$RsRelayTransferEvent_FailedCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_Failed _self;
  final $Res Function(RsRelayTransferEvent_Failed) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,Object? category = null,}) {
  return _then(RsRelayTransferEvent_Failed(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayTransferEvent_Cancelled extends RsRelayTransferEvent {
  const RsRelayTransferEvent_Cancelled({required this.transferId}): super._();


@override final  String transferId;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayTransferEvent_CancelledCopyWith<RsRelayTransferEvent_Cancelled> get copyWith => _$RsRelayTransferEvent_CancelledCopyWithImpl<RsRelayTransferEvent_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayTransferEvent_Cancelled&&(identical(other.transferId, transferId) || other.transferId == transferId));
}


@override
int get hashCode => Object.hash(runtimeType,transferId);

@override
String toString() {
  return 'RsRelayTransferEvent.cancelled(transferId: $transferId)';
}


}

/// @nodoc
abstract mixin class $RsRelayTransferEvent_CancelledCopyWith<$Res> implements $RsRelayTransferEventCopyWith<$Res> {
  factory $RsRelayTransferEvent_CancelledCopyWith(RsRelayTransferEvent_Cancelled value, $Res Function(RsRelayTransferEvent_Cancelled) _then) = _$RsRelayTransferEvent_CancelledCopyWithImpl;
@override @useResult
$Res call({
 String transferId
});




}
/// @nodoc
class _$RsRelayTransferEvent_CancelledCopyWithImpl<$Res>
    implements $RsRelayTransferEvent_CancelledCopyWith<$Res> {
  _$RsRelayTransferEvent_CancelledCopyWithImpl(this._self, this._then);

  final RsRelayTransferEvent_Cancelled _self;
  final $Res Function(RsRelayTransferEvent_Cancelled) _then;

/// Create a copy of RsRelayTransferEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? transferId = null,}) {
  return _then(RsRelayTransferEvent_Cancelled(
transferId: null == transferId ? _self.transferId : transferId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
