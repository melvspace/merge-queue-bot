// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotUser {


/// Create a copy of BotUser
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotUserCopyWith<BotUser> get copyWith => _$BotUserCopyWithImpl<BotUser>(this as BotUser, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotUser;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotUser&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.email, _this.email) || other.email == _this.email));
}


@override
int get hashCode {
  final _this = this as BotUser;
  return Object.hash(runtimeType,_this.id,_this.name,_this.email);
}

@override
String toString() {
  final _this = this as BotUser;
  return 'BotUser(id: ${_this.id}, name: ${_this.name}, email: ${_this.email})';
}


}

/// @nodoc
abstract mixin class $BotUserCopyWith<$Res>  {
  factory $BotUserCopyWith(BotUser value, $Res Function(BotUser) _then) = _$BotUserCopyWithImpl;
@useResult
$Res call({
 int id, String name, String email
});




}
/// @nodoc
class _$BotUserCopyWithImpl<$Res>
    implements $BotUserCopyWith<$Res> {
  _$BotUserCopyWithImpl(this._self, this._then);

  final BotUser _self;
  final $Res Function(BotUser) _then;

/// Create a copy of BotUser
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? email = null,}) {
  return _then(BotUser(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc
mixin _$Project {


/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectCopyWith<Project> get copyWith => _$ProjectCopyWithImpl<Project>(this as Project, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Project;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Project&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.cloneUrl, _this.cloneUrl) || other.cloneUrl == _this.cloneUrl)&&(identical(other.mergeMethod, _this.mergeMethod) || other.mergeMethod == _this.mergeMethod)&&(identical(other.squashOption, _this.squashOption) || other.squashOption == _this.squashOption)&&(identical(other.automaticRebase, _this.automaticRebase) || other.automaticRebase == _this.automaticRebase)&&(identical(other.mergedResultsPipelines, _this.mergedResultsPipelines) || other.mergedResultsPipelines == _this.mergedResultsPipelines));
}


@override
int get hashCode {
  final _this = this as Project;
  return Object.hash(runtimeType,_this.id,_this.path,_this.cloneUrl,_this.mergeMethod,_this.squashOption,_this.automaticRebase,_this.mergedResultsPipelines);
}

@override
String toString() {
  final _this = this as Project;
  return 'Project(id: ${_this.id}, path: ${_this.path}, cloneUrl: ${_this.cloneUrl}, mergeMethod: ${_this.mergeMethod}, squashOption: ${_this.squashOption}, automaticRebase: ${_this.automaticRebase}, mergedResultsPipelines: ${_this.mergedResultsPipelines})';
}


}

/// @nodoc
abstract mixin class $ProjectCopyWith<$Res>  {
  factory $ProjectCopyWith(Project value, $Res Function(Project) _then) = _$ProjectCopyWithImpl;
@useResult
$Res call({
 int id, String path, String cloneUrl, String mergeMethod, String squashOption, bool automaticRebase, bool mergedResultsPipelines
});




}
/// @nodoc
class _$ProjectCopyWithImpl<$Res>
    implements $ProjectCopyWith<$Res> {
  _$ProjectCopyWithImpl(this._self, this._then);

  final Project _self;
  final $Res Function(Project) _then;

/// Create a copy of Project
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? path = null,Object? cloneUrl = null,Object? mergeMethod = null,Object? squashOption = null,Object? automaticRebase = null,Object? mergedResultsPipelines = null,}) {
  return _then(Project(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,cloneUrl: null == cloneUrl ? _self.cloneUrl : cloneUrl // ignore: cast_nullable_to_non_nullable
as String,mergeMethod: null == mergeMethod ? _self.mergeMethod : mergeMethod // ignore: cast_nullable_to_non_nullable
as String,squashOption: null == squashOption ? _self.squashOption : squashOption // ignore: cast_nullable_to_non_nullable
as String,automaticRebase: null == automaticRebase ? _self.automaticRebase : automaticRebase // ignore: cast_nullable_to_non_nullable
as bool,mergedResultsPipelines: null == mergedResultsPipelines ? _self.mergedResultsPipelines : mergedResultsPipelines // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}




/// @nodoc
mixin _$MergeRequest {


/// Create a copy of MergeRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MergeRequestCopyWith<MergeRequest> get copyWith => _$MergeRequestCopyWithImpl<MergeRequest>(this as MergeRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as MergeRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MergeRequest&&(identical(other.iid, _this.iid) || other.iid == _this.iid)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.sha, _this.sha) || other.sha == _this.sha)&&(identical(other.targetBranch, _this.targetBranch) || other.targetBranch == _this.targetBranch)&&(identical(other.sourceBranch, _this.sourceBranch) || other.sourceBranch == _this.sourceBranch)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&const DeepCollectionEquality().equals(other.assignees, _this.assignees)&&(identical(other.authorName, _this.authorName) || other.authorName == _this.authorName)&&(identical(other.authorEmail, _this.authorEmail) || other.authorEmail == _this.authorEmail)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.mergeCommitSha, _this.mergeCommitSha) || other.mergeCommitSha == _this.mergeCommitSha)&&(identical(other.sourceProjectId, _this.sourceProjectId) || other.sourceProjectId == _this.sourceProjectId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as MergeRequest;
  return Object.hash(runtimeType,_this.iid,_this.title,_this.url,_this.sha,_this.targetBranch,_this.sourceBranch,_this.state,_this.draft,const DeepCollectionEquality().hash(_this.assignees),_this.authorName,_this.authorEmail,_this.createdAt,_this.mergeCommitSha,_this.sourceProjectId);
}

@override
String toString() {
  final _this = this as MergeRequest;
  return 'MergeRequest(iid: ${_this.iid}, title: ${_this.title}, url: ${_this.url}, sha: ${_this.sha}, targetBranch: ${_this.targetBranch}, sourceBranch: ${_this.sourceBranch}, state: ${_this.state}, draft: ${_this.draft}, assignees: ${_this.assignees}, authorName: ${_this.authorName}, authorEmail: ${_this.authorEmail}, createdAt: ${_this.createdAt}, mergeCommitSha: ${_this.mergeCommitSha}, sourceProjectId: ${_this.sourceProjectId})';
}


}

/// @nodoc
abstract mixin class $MergeRequestCopyWith<$Res>  {
  factory $MergeRequestCopyWith(MergeRequest value, $Res Function(MergeRequest) _then) = _$MergeRequestCopyWithImpl;
@useResult
$Res call({
 int iid, String title, String url, String sha,@JsonKey(name: 'target') String targetBranch,@JsonKey(name: 'source') String sourceBranch, String state, bool draft, List<int> assignees, String authorName, String authorEmail, DateTime createdAt, String? mergeCommitSha, int? sourceProjectId
});




}
/// @nodoc
class _$MergeRequestCopyWithImpl<$Res>
    implements $MergeRequestCopyWith<$Res> {
  _$MergeRequestCopyWithImpl(this._self, this._then);

  final MergeRequest _self;
  final $Res Function(MergeRequest) _then;

/// Create a copy of MergeRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? iid = null,Object? title = null,Object? url = null,Object? sha = null,Object? targetBranch = null,Object? sourceBranch = null,Object? state = null,Object? draft = null,Object? assignees = null,Object? authorName = null,Object? authorEmail = null,Object? createdAt = null,Object? mergeCommitSha = freezed,Object? sourceProjectId = freezed,}) {
  return _then(MergeRequest(
iid: null == iid ? _self.iid : iid // ignore: cast_nullable_to_non_nullable
as int,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,sha: null == sha ? _self.sha : sha // ignore: cast_nullable_to_non_nullable
as String,targetBranch: null == targetBranch ? _self.targetBranch : targetBranch // ignore: cast_nullable_to_non_nullable
as String,sourceBranch: null == sourceBranch ? _self.sourceBranch : sourceBranch // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as bool,assignees: null == assignees ? _self.assignees : assignees // ignore: cast_nullable_to_non_nullable
as List<int>,authorName: null == authorName ? _self.authorName : authorName // ignore: cast_nullable_to_non_nullable
as String,authorEmail: null == authorEmail ? _self.authorEmail : authorEmail // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,mergeCommitSha: freezed == mergeCommitSha ? _self.mergeCommitSha : mergeCommitSha // ignore: cast_nullable_to_non_nullable
as String?,sourceProjectId: freezed == sourceProjectId ? _self.sourceProjectId : sourceProjectId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [MergeRequest].
extension MergeRequestPatterns on MergeRequest {
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

/// @nodoc
mixin _$Pipeline {


/// Create a copy of Pipeline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PipelineCopyWith<Pipeline> get copyWith => _$PipelineCopyWithImpl<Pipeline>(this as Pipeline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Pipeline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Pipeline&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.sha, _this.sha) || other.sha == _this.sha)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as Pipeline;
  return Object.hash(runtimeType,_this.id,_this.sha,_this.status);
}

@override
String toString() {
  final _this = this as Pipeline;
  return 'Pipeline(id: ${_this.id}, sha: ${_this.sha}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $PipelineCopyWith<$Res>  {
  factory $PipelineCopyWith(Pipeline value, $Res Function(Pipeline) _then) = _$PipelineCopyWithImpl;
@useResult
$Res call({
 int id, String sha, String status
});




}
/// @nodoc
class _$PipelineCopyWithImpl<$Res>
    implements $PipelineCopyWith<$Res> {
  _$PipelineCopyWithImpl(this._self, this._then);

  final Pipeline _self;
  final $Res Function(Pipeline) _then;

/// Create a copy of Pipeline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? sha = null,Object? status = null,}) {
  return _then(Pipeline(
null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,null == sha ? _self.sha : sha // ignore: cast_nullable_to_non_nullable
as String,null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}



/// @nodoc
mixin _$BatchRef {


/// Create a copy of BatchRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BatchRefCopyWith<BatchRef> get copyWith => _$BatchRefCopyWithImpl<BatchRef>(this as BatchRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BatchRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BatchRef&&(identical(other.iid, _this.iid) || other.iid == _this.iid)&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.sha, _this.sha) || other.sha == _this.sha)&&(identical(other.mergeCommitSha, _this.mergeCommitSha) || other.mergeCommitSha == _this.mergeCommitSha)&&(identical(other.sourceBranch, _this.sourceBranch) || other.sourceBranch == _this.sourceBranch)&&(identical(other.targetBranch, _this.targetBranch) || other.targetBranch == _this.targetBranch)&&(identical(other.detailedMergeStatus, _this.detailedMergeStatus) || other.detailedMergeStatus == _this.detailedMergeStatus));
}


@override
int get hashCode {
  final _this = this as BatchRef;
  return Object.hash(runtimeType,_this.iid,_this.url,_this.state,_this.sha,_this.mergeCommitSha,_this.sourceBranch,_this.targetBranch,_this.detailedMergeStatus);
}

@override
String toString() {
  final _this = this as BatchRef;
  return 'BatchRef(iid: ${_this.iid}, url: ${_this.url}, state: ${_this.state}, sha: ${_this.sha}, mergeCommitSha: ${_this.mergeCommitSha}, sourceBranch: ${_this.sourceBranch}, targetBranch: ${_this.targetBranch}, detailedMergeStatus: ${_this.detailedMergeStatus})';
}


}

/// @nodoc
abstract mixin class $BatchRefCopyWith<$Res>  {
  factory $BatchRefCopyWith(BatchRef value, $Res Function(BatchRef) _then) = _$BatchRefCopyWithImpl;
@useResult
$Res call({
 int iid, String url, String state, String sha, String? mergeCommitSha, String? sourceBranch, String? targetBranch, String? detailedMergeStatus
});




}
/// @nodoc
class _$BatchRefCopyWithImpl<$Res>
    implements $BatchRefCopyWith<$Res> {
  _$BatchRefCopyWithImpl(this._self, this._then);

  final BatchRef _self;
  final $Res Function(BatchRef) _then;

/// Create a copy of BatchRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? iid = null,Object? url = null,Object? state = null,Object? sha = null,Object? mergeCommitSha = freezed,Object? sourceBranch = freezed,Object? targetBranch = freezed,Object? detailedMergeStatus = freezed,}) {
  return _then(BatchRef(
null == iid ? _self.iid : iid // ignore: cast_nullable_to_non_nullable
as int,null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as String,null == sha ? _self.sha : sha // ignore: cast_nullable_to_non_nullable
as String,mergeCommitSha: freezed == mergeCommitSha ? _self.mergeCommitSha : mergeCommitSha // ignore: cast_nullable_to_non_nullable
as String?,sourceBranch: freezed == sourceBranch ? _self.sourceBranch : sourceBranch // ignore: cast_nullable_to_non_nullable
as String?,targetBranch: freezed == targetBranch ? _self.targetBranch : targetBranch // ignore: cast_nullable_to_non_nullable
as String?,detailedMergeStatus: freezed == detailedMergeStatus ? _self.detailedMergeStatus : detailedMergeStatus // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}



// dart format on
