part of '../api_service.dart';

/// Lists the MCP servers the user owns or that are shared with them. They are managed in the web app.
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
