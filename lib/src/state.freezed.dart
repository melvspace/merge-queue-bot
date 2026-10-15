// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Rejection {


/// Create a copy of Rejection
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RejectionCopyWith<Rejection> get copyWith => _$RejectionCopyWithImpl<Rejection>(this as Rejection, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Rejection;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Rejection&&(identical(other.member, _this.member) || other.member == _this.member)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.marker, _this.marker) || other.marker == _this.marker)&&const DeepCollectionEquality().equals(other.previousAssignees, _this.previousAssignees)&&(identical(other.deliveredUpdate, _this.deliveredUpdate) || other.deliveredUpdate == _this.deliveredUpdate));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Rejection;
  return Object.hash(runtimeType,_this.member,_this.reason,_this.marker,const DeepCollectionEquality().hash(_this.previousAssignees),_this.deliveredUpdate);
}

@override
String toString() {
  final _this = this as Rejection;
  return 'Rejection(member: ${_this.member}, reason: ${_this.reason}, marker: ${_this.marker}, previousAssignees: ${_this.previousAssignees}, deliveredUpdate: ${_this.deliveredUpdate})';
}


}

/// @nodoc
abstract mixin class $RejectionCopyWith<$Res>  {
  factory $RejectionCopyWith(Rejection value, $Res Function(Rejection) _then) = _$RejectionCopyWithImpl;
@useResult
$Res call({
 MergeRequest member, String reason, String marker, List<int> previousAssignees, bool deliveredUpdate
});


$MergeRequestCopyWith<$Res> get member;

}
/// @nodoc
class _$RejectionCopyWithImpl<$Res>
    implements $RejectionCopyWith<$Res> {
  _$RejectionCopyWithImpl(this._self, this._then);

  final Rejection _self;
  final $Res Function(Rejection) _then;

/// Create a copy of Rejection
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? member = null,Object? reason = null,Object? marker = null,Object? previousAssignees = null,Object? deliveredUpdate = null,}) {
  return _then(Rejection(
null == member ? _self.member : member // ignore: cast_nullable_to_non_nullable
as MergeRequest,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,null == marker ? _self.marker : marker // ignore: cast_nullable_to_non_nullable
as String,null == previousAssignees ? _self.previousAssignees : previousAssignees // ignore: cast_nullable_to_non_nullable
as List<int>,deliveredUpdate: null == deliveredUpdate ? _self.deliveredUpdate : deliveredUpdate // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of Rejection
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MergeRequestCopyWith<$Res> get member {
  
  return $MergeRequestCopyWith<$Res>(_self.member, (value) {
    return _then(_self.copyWith(member: value));
  });
}
}


/// Adds pattern-matching-related methods to [Rejection].
extension RejectionPatterns on Rejection {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

// dart format on
