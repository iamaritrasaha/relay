// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'http.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsHttpClientError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsHttpClientError()';
}


}

/// @nodoc
class $RsHttpClientErrorCopyWith<$Res>  {
$RsHttpClientErrorCopyWith(RsHttpClientError _, $Res Function(RsHttpClientError) __);
}


/// Adds pattern-matching-related methods to [RsHttpClientError].
extension RsHttpClientErrorPatterns on RsHttpClientError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsHttpClientError_StatusCode value)?  statusCode,TResult Function( RsHttpClientError_Reqwest value)?  reqwest,TResult Function( RsHttpClientError_Json value)?  json,TResult Function( RsHttpClientError_Io value)?  io,TResult Function( RsHttpClientError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsHttpClientError_StatusCode value)  statusCode,required TResult Function( RsHttpClientError_Reqwest value)  reqwest,required TResult Function( RsHttpClientError_Json value)  json,required TResult Function( RsHttpClientError_Io value)  io,required TResult Function( RsHttpClientError_Other value)  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that);case RsHttpClientError_Reqwest():
return reqwest(_that);case RsHttpClientError_Json():
return json(_that);case RsHttpClientError_Io():
return io(_that);case RsHttpClientError_Other():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsHttpClientError_StatusCode value)?  statusCode,TResult? Function( RsHttpClientError_Reqwest value)?  reqwest,TResult? Function( RsHttpClientError_Json value)?  json,TResult? Function( RsHttpClientError_Io value)?  io,TResult? Function( RsHttpClientError_Other value)?  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int status,  String? message)?  statusCode,TResult Function( String field0)?  reqwest,TResult Function( String field0)?  json,TResult Function( String field0)?  io,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int status,  String? message)  statusCode,required TResult Function( String field0)  reqwest,required TResult Function( String field0)  json,required TResult Function( String field0)  io,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest():
return reqwest(_that.field0);case RsHttpClientError_Json():
return json(_that.field0);case RsHttpClientError_Io():
return io(_that.field0);case RsHttpClientError_Other():
return other(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int status,  String? message)?  statusCode,TResult? Function( String field0)?  reqwest,TResult? Function( String field0)?  json,TResult? Function( String field0)?  io,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RsHttpClientError_StatusCode extends RsHttpClientError {
  const RsHttpClientError_StatusCode({required this.status, this.message}): super._();
  

 final  int status;
 final  String? message;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_StatusCodeCopyWith<RsHttpClientError_StatusCode> get copyWith => _$RsHttpClientError_StatusCodeCopyWithImpl<RsHttpClientError_StatusCode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_StatusCode&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,status,message);

@override
String toString() {
  return 'RsHttpClientError.statusCode(status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_StatusCodeCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_StatusCodeCopyWith(RsHttpClientError_StatusCode value, $Res Function(RsHttpClientError_StatusCode) _then) = _$RsHttpClientError_StatusCodeCopyWithImpl;
@useResult
$Res call({
 int status, String? message
});




}
/// @nodoc
class _$RsHttpClientError_StatusCodeCopyWithImpl<$Res>
    implements $RsHttpClientError_StatusCodeCopyWith<$Res> {
  _$RsHttpClientError_StatusCodeCopyWithImpl(this._self, this._then);

  final RsHttpClientError_StatusCode _self;
  final $Res Function(RsHttpClientError_StatusCode) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = freezed,}) {
  return _then(RsHttpClientError_StatusCode(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsHttpClientError_Reqwest extends RsHttpClientError {
  const RsHttpClientError_Reqwest(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_ReqwestCopyWith<RsHttpClientError_Reqwest> get copyWith => _$RsHttpClientError_ReqwestCopyWithImpl<RsHttpClientError_Reqwest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Reqwest&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.reqwest(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_ReqwestCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_ReqwestCopyWith(RsHttpClientError_Reqwest value, $Res Function(RsHttpClientError_Reqwest) _then) = _$RsHttpClientError_ReqwestCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_ReqwestCopyWithImpl<$Res>
    implements $RsHttpClientError_ReqwestCopyWith<$Res> {
  _$RsHttpClientError_ReqwestCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Reqwest _self;
  final $Res Function(RsHttpClientError_Reqwest) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Reqwest(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Json extends RsHttpClientError {
  const RsHttpClientError_Json(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_JsonCopyWith<RsHttpClientError_Json> get copyWith => _$RsHttpClientError_JsonCopyWithImpl<RsHttpClientError_Json>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Json&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.json(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_JsonCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_JsonCopyWith(RsHttpClientError_Json value, $Res Function(RsHttpClientError_Json) _then) = _$RsHttpClientError_JsonCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_JsonCopyWithImpl<$Res>
    implements $RsHttpClientError_JsonCopyWith<$Res> {
  _$RsHttpClientError_JsonCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Json _self;
  final $Res Function(RsHttpClientError_Json) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Json(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Io extends RsHttpClientError {
  const RsHttpClientError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_IoCopyWith<RsHttpClientError_Io> get copyWith => _$RsHttpClientError_IoCopyWithImpl<RsHttpClientError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_IoCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_IoCopyWith(RsHttpClientError_Io value, $Res Function(RsHttpClientError_Io) _then) = _$RsHttpClientError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_IoCopyWithImpl<$Res>
    implements $RsHttpClientError_IoCopyWith<$Res> {
  _$RsHttpClientError_IoCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Io _self;
  final $Res Function(RsHttpClientError_Io) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Other extends RsHttpClientError {
  const RsHttpClientError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_OtherCopyWith<RsHttpClientError_Other> get copyWith => _$RsHttpClientError_OtherCopyWithImpl<RsHttpClientError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_OtherCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_OtherCopyWith(RsHttpClientError_Other value, $Res Function(RsHttpClientError_Other) _then) = _$RsHttpClientError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_OtherCopyWithImpl<$Res>
    implements $RsHttpClientError_OtherCopyWith<$Res> {
  _$RsHttpClientError_OtherCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Other _self;
  final $Res Function(RsHttpClientError_Other) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsRelayLanPairingEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent()';
}


}

/// @nodoc
class $RsRelayLanPairingEventCopyWith<$Res>  {
$RsRelayLanPairingEventCopyWith(RsRelayLanPairingEvent _, $Res Function(RsRelayLanPairingEvent) __);
}


/// Adds pattern-matching-related methods to [RsRelayLanPairingEvent].
extension RsRelayLanPairingEventPatterns on RsRelayLanPairingEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRelayLanPairingEvent_VerificationCode value)?  verificationCode,TResult Function( RsRelayLanPairingEvent_Paired value)?  paired,TResult Function( RsRelayLanPairingEvent_Declined value)?  declined,TResult Function( RsRelayLanPairingEvent_Unsupported value)?  unsupported,TResult Function( RsRelayLanPairingEvent_Busy value)?  busy,TResult Function( RsRelayLanPairingEvent_AuthenticationFailed value)?  authenticationFailed,TResult Function( RsRelayLanPairingEvent_TransportFailed value)?  transportFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode() when verificationCode != null:
return verificationCode(_that);case RsRelayLanPairingEvent_Paired() when paired != null:
return paired(_that);case RsRelayLanPairingEvent_Declined() when declined != null:
return declined(_that);case RsRelayLanPairingEvent_Unsupported() when unsupported != null:
return unsupported(_that);case RsRelayLanPairingEvent_Busy() when busy != null:
return busy(_that);case RsRelayLanPairingEvent_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed(_that);case RsRelayLanPairingEvent_TransportFailed() when transportFailed != null:
return transportFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRelayLanPairingEvent_VerificationCode value)  verificationCode,required TResult Function( RsRelayLanPairingEvent_Paired value)  paired,required TResult Function( RsRelayLanPairingEvent_Declined value)  declined,required TResult Function( RsRelayLanPairingEvent_Unsupported value)  unsupported,required TResult Function( RsRelayLanPairingEvent_Busy value)  busy,required TResult Function( RsRelayLanPairingEvent_AuthenticationFailed value)  authenticationFailed,required TResult Function( RsRelayLanPairingEvent_TransportFailed value)  transportFailed,}){
final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode():
return verificationCode(_that);case RsRelayLanPairingEvent_Paired():
return paired(_that);case RsRelayLanPairingEvent_Declined():
return declined(_that);case RsRelayLanPairingEvent_Unsupported():
return unsupported(_that);case RsRelayLanPairingEvent_Busy():
return busy(_that);case RsRelayLanPairingEvent_AuthenticationFailed():
return authenticationFailed(_that);case RsRelayLanPairingEvent_TransportFailed():
return transportFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRelayLanPairingEvent_VerificationCode value)?  verificationCode,TResult? Function( RsRelayLanPairingEvent_Paired value)?  paired,TResult? Function( RsRelayLanPairingEvent_Declined value)?  declined,TResult? Function( RsRelayLanPairingEvent_Unsupported value)?  unsupported,TResult? Function( RsRelayLanPairingEvent_Busy value)?  busy,TResult? Function( RsRelayLanPairingEvent_AuthenticationFailed value)?  authenticationFailed,TResult? Function( RsRelayLanPairingEvent_TransportFailed value)?  transportFailed,}){
final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode() when verificationCode != null:
return verificationCode(_that);case RsRelayLanPairingEvent_Paired() when paired != null:
return paired(_that);case RsRelayLanPairingEvent_Declined() when declined != null:
return declined(_that);case RsRelayLanPairingEvent_Unsupported() when unsupported != null:
return unsupported(_that);case RsRelayLanPairingEvent_Busy() when busy != null:
return busy(_that);case RsRelayLanPairingEvent_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed(_that);case RsRelayLanPairingEvent_TransportFailed() when transportFailed != null:
return transportFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String code,  String remoteRelayId)?  verificationCode,TResult Function( String remoteRelayId,  String remoteAlias,  String verificationCode)?  paired,TResult Function()?  declined,TResult Function()?  unsupported,TResult Function()?  busy,TResult Function()?  authenticationFailed,TResult Function()?  transportFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode() when verificationCode != null:
return verificationCode(_that.code,_that.remoteRelayId);case RsRelayLanPairingEvent_Paired() when paired != null:
return paired(_that.remoteRelayId,_that.remoteAlias,_that.verificationCode);case RsRelayLanPairingEvent_Declined() when declined != null:
return declined();case RsRelayLanPairingEvent_Unsupported() when unsupported != null:
return unsupported();case RsRelayLanPairingEvent_Busy() when busy != null:
return busy();case RsRelayLanPairingEvent_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed();case RsRelayLanPairingEvent_TransportFailed() when transportFailed != null:
return transportFailed();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String code,  String remoteRelayId)  verificationCode,required TResult Function( String remoteRelayId,  String remoteAlias,  String verificationCode)  paired,required TResult Function()  declined,required TResult Function()  unsupported,required TResult Function()  busy,required TResult Function()  authenticationFailed,required TResult Function()  transportFailed,}) {final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode():
return verificationCode(_that.code,_that.remoteRelayId);case RsRelayLanPairingEvent_Paired():
return paired(_that.remoteRelayId,_that.remoteAlias,_that.verificationCode);case RsRelayLanPairingEvent_Declined():
return declined();case RsRelayLanPairingEvent_Unsupported():
return unsupported();case RsRelayLanPairingEvent_Busy():
return busy();case RsRelayLanPairingEvent_AuthenticationFailed():
return authenticationFailed();case RsRelayLanPairingEvent_TransportFailed():
return transportFailed();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String code,  String remoteRelayId)?  verificationCode,TResult? Function( String remoteRelayId,  String remoteAlias,  String verificationCode)?  paired,TResult? Function()?  declined,TResult? Function()?  unsupported,TResult? Function()?  busy,TResult? Function()?  authenticationFailed,TResult? Function()?  transportFailed,}) {final _that = this;
switch (_that) {
case RsRelayLanPairingEvent_VerificationCode() when verificationCode != null:
return verificationCode(_that.code,_that.remoteRelayId);case RsRelayLanPairingEvent_Paired() when paired != null:
return paired(_that.remoteRelayId,_that.remoteAlias,_that.verificationCode);case RsRelayLanPairingEvent_Declined() when declined != null:
return declined();case RsRelayLanPairingEvent_Unsupported() when unsupported != null:
return unsupported();case RsRelayLanPairingEvent_Busy() when busy != null:
return busy();case RsRelayLanPairingEvent_AuthenticationFailed() when authenticationFailed != null:
return authenticationFailed();case RsRelayLanPairingEvent_TransportFailed() when transportFailed != null:
return transportFailed();case _:
  return null;

}
}

}

/// @nodoc


class RsRelayLanPairingEvent_VerificationCode extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_VerificationCode({required this.code, required this.remoteRelayId}): super._();
  

 final  String code;
 final  String remoteRelayId;

/// Create a copy of RsRelayLanPairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayLanPairingEvent_VerificationCodeCopyWith<RsRelayLanPairingEvent_VerificationCode> get copyWith => _$RsRelayLanPairingEvent_VerificationCodeCopyWithImpl<RsRelayLanPairingEvent_VerificationCode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_VerificationCode&&(identical(other.code, code) || other.code == code)&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId));
}


@override
int get hashCode => Object.hash(runtimeType,code,remoteRelayId);

@override
String toString() {
  return 'RsRelayLanPairingEvent.verificationCode(code: $code, remoteRelayId: $remoteRelayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayLanPairingEvent_VerificationCodeCopyWith<$Res> implements $RsRelayLanPairingEventCopyWith<$Res> {
  factory $RsRelayLanPairingEvent_VerificationCodeCopyWith(RsRelayLanPairingEvent_VerificationCode value, $Res Function(RsRelayLanPairingEvent_VerificationCode) _then) = _$RsRelayLanPairingEvent_VerificationCodeCopyWithImpl;
@useResult
$Res call({
 String code, String remoteRelayId
});




}
/// @nodoc
class _$RsRelayLanPairingEvent_VerificationCodeCopyWithImpl<$Res>
    implements $RsRelayLanPairingEvent_VerificationCodeCopyWith<$Res> {
  _$RsRelayLanPairingEvent_VerificationCodeCopyWithImpl(this._self, this._then);

  final RsRelayLanPairingEvent_VerificationCode _self;
  final $Res Function(RsRelayLanPairingEvent_VerificationCode) _then;

/// Create a copy of RsRelayLanPairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? remoteRelayId = null,}) {
  return _then(RsRelayLanPairingEvent_VerificationCode(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayLanPairingEvent_Paired extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_Paired({required this.remoteRelayId, required this.remoteAlias, required this.verificationCode}): super._();
  

 final  String remoteRelayId;
 final  String remoteAlias;
 final  String verificationCode;

/// Create a copy of RsRelayLanPairingEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayLanPairingEvent_PairedCopyWith<RsRelayLanPairingEvent_Paired> get copyWith => _$RsRelayLanPairingEvent_PairedCopyWithImpl<RsRelayLanPairingEvent_Paired>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_Paired&&(identical(other.remoteRelayId, remoteRelayId) || other.remoteRelayId == remoteRelayId)&&(identical(other.remoteAlias, remoteAlias) || other.remoteAlias == remoteAlias)&&(identical(other.verificationCode, verificationCode) || other.verificationCode == verificationCode));
}


@override
int get hashCode => Object.hash(runtimeType,remoteRelayId,remoteAlias,verificationCode);

@override
String toString() {
  return 'RsRelayLanPairingEvent.paired(remoteRelayId: $remoteRelayId, remoteAlias: $remoteAlias, verificationCode: $verificationCode)';
}


}

/// @nodoc
abstract mixin class $RsRelayLanPairingEvent_PairedCopyWith<$Res> implements $RsRelayLanPairingEventCopyWith<$Res> {
  factory $RsRelayLanPairingEvent_PairedCopyWith(RsRelayLanPairingEvent_Paired value, $Res Function(RsRelayLanPairingEvent_Paired) _then) = _$RsRelayLanPairingEvent_PairedCopyWithImpl;
@useResult
$Res call({
 String remoteRelayId, String remoteAlias, String verificationCode
});




}
/// @nodoc
class _$RsRelayLanPairingEvent_PairedCopyWithImpl<$Res>
    implements $RsRelayLanPairingEvent_PairedCopyWith<$Res> {
  _$RsRelayLanPairingEvent_PairedCopyWithImpl(this._self, this._then);

  final RsRelayLanPairingEvent_Paired _self;
  final $Res Function(RsRelayLanPairingEvent_Paired) _then;

/// Create a copy of RsRelayLanPairingEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? remoteRelayId = null,Object? remoteAlias = null,Object? verificationCode = null,}) {
  return _then(RsRelayLanPairingEvent_Paired(
remoteRelayId: null == remoteRelayId ? _self.remoteRelayId : remoteRelayId // ignore: cast_nullable_to_non_nullable
as String,remoteAlias: null == remoteAlias ? _self.remoteAlias : remoteAlias // ignore: cast_nullable_to_non_nullable
as String,verificationCode: null == verificationCode ? _self.verificationCode : verificationCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsRelayLanPairingEvent_Declined extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_Declined(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_Declined);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent.declined()';
}


}




/// @nodoc


class RsRelayLanPairingEvent_Unsupported extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_Unsupported(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent.unsupported()';
}


}




/// @nodoc


class RsRelayLanPairingEvent_Busy extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_Busy(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_Busy);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent.busy()';
}


}




/// @nodoc


class RsRelayLanPairingEvent_AuthenticationFailed extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_AuthenticationFailed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_AuthenticationFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent.authenticationFailed()';
}


}




/// @nodoc


class RsRelayLanPairingEvent_TransportFailed extends RsRelayLanPairingEvent {
  const RsRelayLanPairingEvent_TransportFailed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayLanPairingEvent_TransportFailed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayLanPairingEvent.transportFailed()';
}


}




/// @nodoc
mixin _$RsRelayPeerAuth {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth()';
}


}

/// @nodoc
class $RsRelayPeerAuthCopyWith<$Res>  {
$RsRelayPeerAuthCopyWith(RsRelayPeerAuth _, $Res Function(RsRelayPeerAuth) __);
}


/// Adds pattern-matching-related methods to [RsRelayPeerAuth].
extension RsRelayPeerAuthPatterns on RsRelayPeerAuth {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsRelayPeerAuth_NotAttempted value)?  notAttempted,TResult Function( RsRelayPeerAuth_Unsupported value)?  unsupported,TResult Function( RsRelayPeerAuth_TransportUnauthenticated value)?  transportUnauthenticated,TResult Function( RsRelayPeerAuth_SignerUnavailable value)?  signerUnavailable,TResult Function( RsRelayPeerAuth_Malformed value)?  malformed,TResult Function( RsRelayPeerAuth_RoleMismatch value)?  roleMismatch,TResult Function( RsRelayPeerAuth_ChallengeMismatch value)?  challengeMismatch,TResult Function( RsRelayPeerAuth_CryptoInvalid value)?  cryptoInvalid,TResult Function( RsRelayPeerAuth_Authenticated value)?  authenticated,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted() when notAttempted != null:
return notAttempted(_that);case RsRelayPeerAuth_Unsupported() when unsupported != null:
return unsupported(_that);case RsRelayPeerAuth_TransportUnauthenticated() when transportUnauthenticated != null:
return transportUnauthenticated(_that);case RsRelayPeerAuth_SignerUnavailable() when signerUnavailable != null:
return signerUnavailable(_that);case RsRelayPeerAuth_Malformed() when malformed != null:
return malformed(_that);case RsRelayPeerAuth_RoleMismatch() when roleMismatch != null:
return roleMismatch(_that);case RsRelayPeerAuth_ChallengeMismatch() when challengeMismatch != null:
return challengeMismatch(_that);case RsRelayPeerAuth_CryptoInvalid() when cryptoInvalid != null:
return cryptoInvalid(_that);case RsRelayPeerAuth_Authenticated() when authenticated != null:
return authenticated(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsRelayPeerAuth_NotAttempted value)  notAttempted,required TResult Function( RsRelayPeerAuth_Unsupported value)  unsupported,required TResult Function( RsRelayPeerAuth_TransportUnauthenticated value)  transportUnauthenticated,required TResult Function( RsRelayPeerAuth_SignerUnavailable value)  signerUnavailable,required TResult Function( RsRelayPeerAuth_Malformed value)  malformed,required TResult Function( RsRelayPeerAuth_RoleMismatch value)  roleMismatch,required TResult Function( RsRelayPeerAuth_ChallengeMismatch value)  challengeMismatch,required TResult Function( RsRelayPeerAuth_CryptoInvalid value)  cryptoInvalid,required TResult Function( RsRelayPeerAuth_Authenticated value)  authenticated,}){
final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted():
return notAttempted(_that);case RsRelayPeerAuth_Unsupported():
return unsupported(_that);case RsRelayPeerAuth_TransportUnauthenticated():
return transportUnauthenticated(_that);case RsRelayPeerAuth_SignerUnavailable():
return signerUnavailable(_that);case RsRelayPeerAuth_Malformed():
return malformed(_that);case RsRelayPeerAuth_RoleMismatch():
return roleMismatch(_that);case RsRelayPeerAuth_ChallengeMismatch():
return challengeMismatch(_that);case RsRelayPeerAuth_CryptoInvalid():
return cryptoInvalid(_that);case RsRelayPeerAuth_Authenticated():
return authenticated(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsRelayPeerAuth_NotAttempted value)?  notAttempted,TResult? Function( RsRelayPeerAuth_Unsupported value)?  unsupported,TResult? Function( RsRelayPeerAuth_TransportUnauthenticated value)?  transportUnauthenticated,TResult? Function( RsRelayPeerAuth_SignerUnavailable value)?  signerUnavailable,TResult? Function( RsRelayPeerAuth_Malformed value)?  malformed,TResult? Function( RsRelayPeerAuth_RoleMismatch value)?  roleMismatch,TResult? Function( RsRelayPeerAuth_ChallengeMismatch value)?  challengeMismatch,TResult? Function( RsRelayPeerAuth_CryptoInvalid value)?  cryptoInvalid,TResult? Function( RsRelayPeerAuth_Authenticated value)?  authenticated,}){
final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted() when notAttempted != null:
return notAttempted(_that);case RsRelayPeerAuth_Unsupported() when unsupported != null:
return unsupported(_that);case RsRelayPeerAuth_TransportUnauthenticated() when transportUnauthenticated != null:
return transportUnauthenticated(_that);case RsRelayPeerAuth_SignerUnavailable() when signerUnavailable != null:
return signerUnavailable(_that);case RsRelayPeerAuth_Malformed() when malformed != null:
return malformed(_that);case RsRelayPeerAuth_RoleMismatch() when roleMismatch != null:
return roleMismatch(_that);case RsRelayPeerAuth_ChallengeMismatch() when challengeMismatch != null:
return challengeMismatch(_that);case RsRelayPeerAuth_CryptoInvalid() when cryptoInvalid != null:
return cryptoInvalid(_that);case RsRelayPeerAuth_Authenticated() when authenticated != null:
return authenticated(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notAttempted,TResult Function()?  unsupported,TResult Function()?  transportUnauthenticated,TResult Function()?  signerUnavailable,TResult Function()?  malformed,TResult Function()?  roleMismatch,TResult Function()?  challengeMismatch,TResult Function()?  cryptoInvalid,TResult Function( String relayId)?  authenticated,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted() when notAttempted != null:
return notAttempted();case RsRelayPeerAuth_Unsupported() when unsupported != null:
return unsupported();case RsRelayPeerAuth_TransportUnauthenticated() when transportUnauthenticated != null:
return transportUnauthenticated();case RsRelayPeerAuth_SignerUnavailable() when signerUnavailable != null:
return signerUnavailable();case RsRelayPeerAuth_Malformed() when malformed != null:
return malformed();case RsRelayPeerAuth_RoleMismatch() when roleMismatch != null:
return roleMismatch();case RsRelayPeerAuth_ChallengeMismatch() when challengeMismatch != null:
return challengeMismatch();case RsRelayPeerAuth_CryptoInvalid() when cryptoInvalid != null:
return cryptoInvalid();case RsRelayPeerAuth_Authenticated() when authenticated != null:
return authenticated(_that.relayId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notAttempted,required TResult Function()  unsupported,required TResult Function()  transportUnauthenticated,required TResult Function()  signerUnavailable,required TResult Function()  malformed,required TResult Function()  roleMismatch,required TResult Function()  challengeMismatch,required TResult Function()  cryptoInvalid,required TResult Function( String relayId)  authenticated,}) {final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted():
return notAttempted();case RsRelayPeerAuth_Unsupported():
return unsupported();case RsRelayPeerAuth_TransportUnauthenticated():
return transportUnauthenticated();case RsRelayPeerAuth_SignerUnavailable():
return signerUnavailable();case RsRelayPeerAuth_Malformed():
return malformed();case RsRelayPeerAuth_RoleMismatch():
return roleMismatch();case RsRelayPeerAuth_ChallengeMismatch():
return challengeMismatch();case RsRelayPeerAuth_CryptoInvalid():
return cryptoInvalid();case RsRelayPeerAuth_Authenticated():
return authenticated(_that.relayId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notAttempted,TResult? Function()?  unsupported,TResult? Function()?  transportUnauthenticated,TResult? Function()?  signerUnavailable,TResult? Function()?  malformed,TResult? Function()?  roleMismatch,TResult? Function()?  challengeMismatch,TResult? Function()?  cryptoInvalid,TResult? Function( String relayId)?  authenticated,}) {final _that = this;
switch (_that) {
case RsRelayPeerAuth_NotAttempted() when notAttempted != null:
return notAttempted();case RsRelayPeerAuth_Unsupported() when unsupported != null:
return unsupported();case RsRelayPeerAuth_TransportUnauthenticated() when transportUnauthenticated != null:
return transportUnauthenticated();case RsRelayPeerAuth_SignerUnavailable() when signerUnavailable != null:
return signerUnavailable();case RsRelayPeerAuth_Malformed() when malformed != null:
return malformed();case RsRelayPeerAuth_RoleMismatch() when roleMismatch != null:
return roleMismatch();case RsRelayPeerAuth_ChallengeMismatch() when challengeMismatch != null:
return challengeMismatch();case RsRelayPeerAuth_CryptoInvalid() when cryptoInvalid != null:
return cryptoInvalid();case RsRelayPeerAuth_Authenticated() when authenticated != null:
return authenticated(_that.relayId);case _:
  return null;

}
}

}

/// @nodoc


class RsRelayPeerAuth_NotAttempted extends RsRelayPeerAuth {
  const RsRelayPeerAuth_NotAttempted(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_NotAttempted);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.notAttempted()';
}


}




/// @nodoc


class RsRelayPeerAuth_Unsupported extends RsRelayPeerAuth {
  const RsRelayPeerAuth_Unsupported(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_Unsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.unsupported()';
}


}




/// @nodoc


class RsRelayPeerAuth_TransportUnauthenticated extends RsRelayPeerAuth {
  const RsRelayPeerAuth_TransportUnauthenticated(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_TransportUnauthenticated);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.transportUnauthenticated()';
}


}




/// @nodoc


class RsRelayPeerAuth_SignerUnavailable extends RsRelayPeerAuth {
  const RsRelayPeerAuth_SignerUnavailable(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_SignerUnavailable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.signerUnavailable()';
}


}




/// @nodoc


class RsRelayPeerAuth_Malformed extends RsRelayPeerAuth {
  const RsRelayPeerAuth_Malformed(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_Malformed);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.malformed()';
}


}




/// @nodoc


class RsRelayPeerAuth_RoleMismatch extends RsRelayPeerAuth {
  const RsRelayPeerAuth_RoleMismatch(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_RoleMismatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.roleMismatch()';
}


}




/// @nodoc


class RsRelayPeerAuth_ChallengeMismatch extends RsRelayPeerAuth {
  const RsRelayPeerAuth_ChallengeMismatch(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_ChallengeMismatch);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.challengeMismatch()';
}


}




/// @nodoc


class RsRelayPeerAuth_CryptoInvalid extends RsRelayPeerAuth {
  const RsRelayPeerAuth_CryptoInvalid(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_CryptoInvalid);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsRelayPeerAuth.cryptoInvalid()';
}


}




/// @nodoc


class RsRelayPeerAuth_Authenticated extends RsRelayPeerAuth {
  const RsRelayPeerAuth_Authenticated({required this.relayId}): super._();
  

 final  String relayId;

/// Create a copy of RsRelayPeerAuth
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsRelayPeerAuth_AuthenticatedCopyWith<RsRelayPeerAuth_Authenticated> get copyWith => _$RsRelayPeerAuth_AuthenticatedCopyWithImpl<RsRelayPeerAuth_Authenticated>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsRelayPeerAuth_Authenticated&&(identical(other.relayId, relayId) || other.relayId == relayId));
}


@override
int get hashCode => Object.hash(runtimeType,relayId);

@override
String toString() {
  return 'RsRelayPeerAuth.authenticated(relayId: $relayId)';
}


}

/// @nodoc
abstract mixin class $RsRelayPeerAuth_AuthenticatedCopyWith<$Res> implements $RsRelayPeerAuthCopyWith<$Res> {
  factory $RsRelayPeerAuth_AuthenticatedCopyWith(RsRelayPeerAuth_Authenticated value, $Res Function(RsRelayPeerAuth_Authenticated) _then) = _$RsRelayPeerAuth_AuthenticatedCopyWithImpl;
@useResult
$Res call({
 String relayId
});




}
/// @nodoc
class _$RsRelayPeerAuth_AuthenticatedCopyWithImpl<$Res>
    implements $RsRelayPeerAuth_AuthenticatedCopyWith<$Res> {
  _$RsRelayPeerAuth_AuthenticatedCopyWithImpl(this._self, this._then);

  final RsRelayPeerAuth_Authenticated _self;
  final $Res Function(RsRelayPeerAuth_Authenticated) _then;

/// Create a copy of RsRelayPeerAuth
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? relayId = null,}) {
  return _then(RsRelayPeerAuth_Authenticated(
relayId: null == relayId ? _self.relayId : relayId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsUploadEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsUploadEvent()';
}


}

/// @nodoc
class $RsUploadEventCopyWith<$Res>  {
$RsUploadEventCopyWith(RsUploadEvent _, $Res Function(RsUploadEvent) __);
}


/// Adds pattern-matching-related methods to [RsUploadEvent].
extension RsUploadEventPatterns on RsUploadEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsUploadEvent_Progress value)?  progress,TResult Function( RsUploadEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsUploadEvent_Progress value)  progress,required TResult Function( RsUploadEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that);case RsUploadEvent_Failed():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsUploadEvent_Progress value)?  progress,TResult? Function( RsUploadEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( double progress)?  progress,TResult Function( RsHttpClientError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( double progress)  progress,required TResult Function( RsHttpClientError error)  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that.progress);case RsUploadEvent_Failed():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( double progress)?  progress,TResult? Function( RsHttpClientError error)?  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsUploadEvent_Progress extends RsUploadEvent {
  const RsUploadEvent_Progress({required this.progress}): super._();
  

 final  double progress;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_ProgressCopyWith<RsUploadEvent_Progress> get copyWith => _$RsUploadEvent_ProgressCopyWithImpl<RsUploadEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'RsUploadEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_ProgressCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_ProgressCopyWith(RsUploadEvent_Progress value, $Res Function(RsUploadEvent_Progress) _then) = _$RsUploadEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 double progress
});




}
/// @nodoc
class _$RsUploadEvent_ProgressCopyWithImpl<$Res>
    implements $RsUploadEvent_ProgressCopyWith<$Res> {
  _$RsUploadEvent_ProgressCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Progress _self;
  final $Res Function(RsUploadEvent_Progress) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(RsUploadEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RsUploadEvent_Failed extends RsUploadEvent {
  const RsUploadEvent_Failed({required this.error}): super._();
  

 final  RsHttpClientError error;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_FailedCopyWith<RsUploadEvent_Failed> get copyWith => _$RsUploadEvent_FailedCopyWithImpl<RsUploadEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RsUploadEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_FailedCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_FailedCopyWith(RsUploadEvent_Failed value, $Res Function(RsUploadEvent_Failed) _then) = _$RsUploadEvent_FailedCopyWithImpl;
@useResult
$Res call({
 RsHttpClientError error
});


$RsHttpClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$RsUploadEvent_FailedCopyWithImpl<$Res>
    implements $RsUploadEvent_FailedCopyWith<$Res> {
  _$RsUploadEvent_FailedCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Failed _self;
  final $Res Function(RsUploadEvent_Failed) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RsUploadEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as RsHttpClientError,
  ));
}

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RsHttpClientErrorCopyWith<$Res> get error {
  
  return $RsHttpClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
