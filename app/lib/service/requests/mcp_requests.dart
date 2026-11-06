part of '../api_service.dart';

/// Lists the MCP servers the user owns or that are shared with them. They are added, changed and shared in the web
/// app; the app only turns them and their tools on or off.
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

/// Replaces the settings of the user's own MCP server [id] (whether they use it, which tools are off) and returns it.
/// Needs the permission to manage MCP servers.
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
