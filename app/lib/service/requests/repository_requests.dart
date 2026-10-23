part of '../api_service.dart';

/// Lists the repositories the user owns or that are shared with them.
class ApiListRepositoriesAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<RepositoryDto>> {
  ApiListRepositoriesAction();

  @override
  Future<(AccountClient?, List<RepositoryDto>)> reduce() async {
    final repositories = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listRepositories(),
      ),
    );
    return (state, repositories);
  }
}

/// Loads the repository [id], which the user owns or that is shared with them.
class ApiGetRepositoryAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, RepositoryDto> {
  final UuidValue id;

  ApiGetRepositoryAction({required this.id});

  @override
  Future<(AccountClient?, RepositoryDto)> reduce() async {
    final repository = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getRepository(id: id),
      ),
    );
    return (state, repository);
  }

  @override
  String toString() => 'ApiGetRepositoryAction(id: $id)';
}

/// Creates a repository and returns it. With a remote, the server checks it first, which can take seconds.
class ApiCreateRepositoryAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, RepositoryDto> {
  final CreateRepositoryRequest request;

  ApiCreateRepositoryAction({required this.request});

  @override
  Future<(AccountClient?, RepositoryDto)> reduce() async {
    final repository = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.createRepository(request: request),
      ),
    );
    return (state, repository);
  }

  /// Without the token, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiCreateRepositoryAction(name: ${request.name}, remote: ${request.remote?.url})';
}

/// Replaces the settings of the repository [id] (owner only) and returns it.
class ApiUpdateRepositoryAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, RepositoryDto> {
  final UuidValue id;
  final UpdateRepositoryRequest request;

  ApiUpdateRepositoryAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, RepositoryDto)> reduce() async {
    final repository = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateRepository(id: id, request: request),
      ),
    );
    return (state, repository);
  }

  /// Without the token, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiUpdateRepositoryAction(id: $id, name: ${request.name})';
}

/// Deletes the repository [id] (owner only).
class ApiDeleteRepositoryAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiDeleteRepositoryAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.deleteRepository(id: id),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiDeleteRepositoryAction(id: $id)';
}

/// Syncs the repository [id] as soon as possible (owner only).
class ApiSyncRepositoryAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiSyncRepositoryAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.syncRepository(id: id),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiSyncRepositoryAction(id: $id)';
}

/// Stops sharing the repository [id] with the user [userId]: by the owner, or by the user themselves to leave it.
class ApiRemoveRepositoryUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final UuidValue userId;

  ApiRemoveRepositoryUserAction({required this.id, required this.userId});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.removeRepositoryUser(id: id, userId: userId),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiRemoveRepositoryUserAction(id: $id, userId: $userId)';
}

/// Lists the documents of the head commit of the repository [id] with their conversion status.
class ApiListRepositoryDocumentsAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, RepositoryDocumentsDto> {
  final UuidValue id;

  ApiListRepositoryDocumentsAction({required this.id});

  @override
  Future<(AccountClient?, RepositoryDocumentsDto)> reduce() async {
    final documents = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listRepositoryDocuments(id: id),
      ),
    );
    return (state, documents);
  }

  @override
  String toString() => 'ApiListRepositoryDocumentsAction(id: $id)';
}

/// Lists the users the repository [id] is shared with (owner or admin only).
class ApiListRepositoryUsersAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<RepositoryUserDto>> {
  final UuidValue id;

  ApiListRepositoryUsersAction({required this.id});

  @override
  Future<(AccountClient?, List<RepositoryUserDto>)> reduce() async {
    final users = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listRepositoryUsers(id: id),
      ),
    );
    return (state, users);
  }

  @override
  String toString() => 'ApiListRepositoryUsersAction(id: $id)';
}

/// Shares the repository [id] with the user of a user name or email (owner or admin only). Fails with
/// `UNKNOWN_USER` if there is no such user.
class ApiAddRepositoryUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final AddRepositoryUserRequest request;

  ApiAddRepositoryUserAction({required this.id, required this.request});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.addRepositoryUser(id: id, request: request),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiAddRepositoryUserAction(id: $id, user: ${request.userNameOrEmail})';
}

/// Sets whether the user [userId] the repository [id] is shared with may commit the changes proposed to them
/// (owner or admin only).
class ApiUpdateRepositoryUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final UuidValue userId;
  final UpdateRepositoryUserRequest request;

  ApiUpdateRepositoryUserAction({required this.id, required this.userId, required this.request});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.updateRepositoryUser(id: id, userId: userId, request: request),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiUpdateRepositoryUserAction(id: $id, userId: $userId, canCommit: ${request.canCommit})';
}
