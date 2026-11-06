part of '../api_service.dart';

/// Lists the MCP servers the user owns or that are shared with them. The app can't sign in to them (OAuth) yet.
class ApiListMcpServersAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<McpServerDto>> {
  ApiListMcpServersAction();

  @override
  Future<(AccountClient?, List<McpServerDto>)> reduce() async {
    final servers = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listMcpServers(),
      ),
    );
    return (state, servers);
  }
}

/// Adds an MCP server and returns it. The server connects to it first, which can take seconds, and fails with
/// `REMOTE_UNREACHABLE` or `AUTH_FAILED` (see [ClientErrorMessage.userDetail]). One that asks to sign in without a
/// token is added as `AUTHORIZATION_REQUIRED`. Needs the permission to manage MCP servers.
class ApiCreateMcpServerAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, McpServerDto> {
  final CreateMcpServerRequest request;

  ApiCreateMcpServerAction({required this.request});

  @override
  Future<(AccountClient?, McpServerDto)> reduce() async {
    final server = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.createMcpServer(request: request),
      ),
    );
    return (state, server);
  }

  /// Without the URL and the token, which the debug observers would print otherwise (the URL may hold a key too).
  @override
  String toString() => 'ApiCreateMcpServerAction(name: ${request.name})';
}

/// Replaces the settings of the user's own MCP server [id] (its name, whether they use it, which tools are off) and
/// returns it. Needs the permission to manage MCP servers.
class ApiUpdateMcpServerAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, McpServerDto> {
  final UuidValue id;
  final UpdateMcpServerRequest request;

  ApiUpdateMcpServerAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, McpServerDto)> reduce() async {
    final server = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateMcpServer(id: id, request: request),
      ),
    );
    return (state, server);
  }

  @override
  String toString() => 'ApiUpdateMcpServerAction(id: $id, enabled: ${request.enabled}, disabledTools: ${request.disabledTools})';
}

/// Turns the MCP server [id], shared with the user [userId] (the user themselves), on or off for their chats.
class ApiUpdateMcpServerUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final UuidValue userId;
  final bool enabled;

  ApiUpdateMcpServerUserAction({required this.id, required this.userId, required this.enabled});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.updateMcpServerUser(
          id: id,
          userId: userId,
          request: UpdateMcpServerUserRequest(enabled: enabled),
        ),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiUpdateMcpServerUserAction(id: $id, userId: $userId, enabled: $enabled)';
}

/// Deletes the user's own MCP server [id]. Needs the permission to manage MCP servers.
class ApiDeleteMcpServerAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiDeleteMcpServerAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.deleteMcpServer(id: id),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiDeleteMcpServerAction(id: $id)';
}

/// Connects to the user's own MCP server [id] again to list its tools, and returns it. A failed connection is
/// returned in its status, not thrown. Needs the permission to manage MCP servers.
class ApiRefreshMcpServerAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, McpServerDto> {
  final UuidValue id;

  ApiRefreshMcpServerAction({required this.id});

  @override
  Future<(AccountClient?, McpServerDto)> reduce() async {
    final server = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.refreshMcpServer(id: id),
      ),
    );
    return (state, server);
  }

  @override
  String toString() => 'ApiRefreshMcpServerAction(id: $id)';
}

/// Lists the users the user's own MCP server [id] is shared with. Needs the permission to manage MCP servers.
class ApiListMcpServerUsersAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<McpServerUserDto>> {
  final UuidValue id;

  ApiListMcpServerUsersAction({required this.id});

  @override
  Future<(AccountClient?, List<McpServerUserDto>)> reduce() async {
    final users = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listMcpServerUsers(id: id),
      ),
    );
    return (state, users);
  }

  @override
  String toString() => 'ApiListMcpServerUsersAction(id: $id)';
}

/// Shares the user's own MCP server [id] with the user of a user name or email, who can then turn it on. Fails with
/// `UNKNOWN_USER` if there is no such user. Needs the permission to manage MCP servers.
class ApiAddMcpServerUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final AddMcpServerUserRequest request;

  ApiAddMcpServerUserAction({required this.id, required this.request});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.addMcpServerUser(id: id, request: request),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiAddMcpServerUserAction(id: $id, user: ${request.userNameOrEmail})';
}

/// Stops sharing the MCP server [id] with the user [userId]: by the owner, or by the user themselves to leave it
/// (also without the permission to manage MCP servers).
class ApiRemoveMcpServerUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;
  final UuidValue userId;

  ApiRemoveMcpServerUserAction({required this.id, required this.userId});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.removeMcpServerUser(id: id, userId: userId),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiRemoveMcpServerUserAction(id: $id, userId: $userId)';
}
