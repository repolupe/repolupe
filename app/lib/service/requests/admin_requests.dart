part of '../api_service.dart';

// Users (admins only).

/// Lists every user.
class ApiListUsersAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<UserDto>> {
  ApiListUsersAction();

  @override
  Future<(AccountClient?, List<UserDto>)> reduce() async {
    final users = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listUsers(),
      ),
    );
    return (state, users);
  }
}

/// Creates a user and returns it.
class ApiRegisterUserAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, UserDto> {
  final RegisterRequest request;

  ApiRegisterUserAction({required this.request});

  @override
  Future<(AccountClient?, UserDto)> reduce() async {
    final user = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.registerUser(request: request),
      ),
    );
    return (state, user);
  }

  /// Without the password, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiRegisterUserAction(userName: ${request.userName}, email: ${request.email})';
}

/// Replaces the user name, email and permissions of the user [id] and returns the user.
class ApiUpdateUserAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, UserDto> {
  final UuidValue id;
  final UpdateUserRequest request;

  ApiUpdateUserAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, UserDto)> reduce() async {
    final user = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateUser(id: id, request: request),
      ),
    );
    return (state, user);
  }

  @override
  String toString() => 'ApiUpdateUserAction(id: $id, userName: ${request.userName})';
}

/// Sets the password of the user [id], which signs them out everywhere, and returns the user.
class ApiResetPasswordAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, UserDto> {
  final UuidValue id;
  final ResetPasswordRequest request;

  ApiResetPasswordAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, UserDto)> reduce() async {
    final user = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.resetPassword(id: id, request: request),
      ),
    );
    return (state, user);
  }

  /// Without the password, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiResetPasswordAction(id: $id, mustChangePassword: ${request.mustChangePassword})';
}

/// Deletes the user [id] with their sessions, chats and repositories.
class ApiDeleteUserAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiDeleteUserAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.deleteUser(request: DeleteUserRequest(userId: id)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiDeleteUserAction(id: $id)';
}

// LLM providers and models (admins only).

/// Lists every LLM provider with its models.
class ApiListLlmProvidersAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<LlmProviderDto>> {
  ApiListLlmProvidersAction();

  @override
  Future<(AccountClient?, List<LlmProviderDto>)> reduce() async {
    final providers = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listLlmProviders(),
      ),
    );
    return (state, providers);
  }
}

/// Creates an LLM provider and returns it (without models).
class ApiCreateLlmProviderAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, LlmProviderDto> {
  final CreateLlmProviderRequest request;

  ApiCreateLlmProviderAction({required this.request});

  @override
  Future<(AccountClient?, LlmProviderDto)> reduce() async {
    final provider = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.createLlmProvider(request: request),
      ),
    );
    return (state, provider);
  }

  /// Without the API key, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiCreateLlmProviderAction(name: ${request.name}, apiFormat: ${request.apiFormat}, baseUrl: ${request.baseUrl})';
}

/// Replaces the settings of the LLM provider [id] and returns it with its models.
class ApiUpdateLlmProviderAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, LlmProviderDto> {
  final UuidValue id;
  final UpdateLlmProviderRequest request;

  ApiUpdateLlmProviderAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, LlmProviderDto)> reduce() async {
    final provider = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateLlmProvider(id: id, request: request),
      ),
    );
    return (state, provider);
  }

  /// Without the API key, which the debug observers would print otherwise.
  @override
  String toString() => 'ApiUpdateLlmProviderAction(id: $id, name: ${request.name}, apiFormat: ${request.apiFormat}, baseUrl: ${request.baseUrl})';
}

/// Deletes the LLM provider [id] with its models.
class ApiDeleteLlmProviderAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiDeleteLlmProviderAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.deleteLlmProvider(id: id),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiDeleteLlmProviderAction(id: $id)';
}

/// Asks the server of the LLM provider [providerId] for the models it offers.
class ApiListRemoteModelsAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<RemoteModelDto>> {
  final UuidValue providerId;

  ApiListRemoteModelsAction({required this.providerId});

  @override
  Future<(AccountClient?, List<RemoteModelDto>)> reduce() async {
    final models = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listRemoteModels(providerId: providerId),
      ),
    );
    return (state, models);
  }

  @override
  String toString() => 'ApiListRemoteModelsAction(providerId: $providerId)';
}

/// Adds a model to the LLM provider [providerId] and returns it.
class ApiCreateLlmModelAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, LlmModelDto> {
  final UuidValue providerId;
  final LlmModelRequest request;

  ApiCreateLlmModelAction({required this.providerId, required this.request});

  @override
  Future<(AccountClient?, LlmModelDto)> reduce() async {
    final model = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.createLlmModel(providerId: providerId, request: request),
      ),
    );
    return (state, model);
  }

  @override
  String toString() => 'ApiCreateLlmModelAction(providerId: $providerId, apiName: ${request.apiName})';
}

/// Replaces the settings of the model [id] and returns it.
class ApiUpdateLlmModelAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, LlmModelDto> {
  final UuidValue id;
  final LlmModelRequest request;

  ApiUpdateLlmModelAction({required this.id, required this.request});

  @override
  Future<(AccountClient?, LlmModelDto)> reduce() async {
    final model = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.updateLlmModel(id: id, request: request),
      ),
    );
    return (state, model);
  }

  @override
  String toString() => 'ApiUpdateLlmModelAction(id: $id, apiName: ${request.apiName})';
}

/// Deletes the model [id]; users who chose it fall back to the default model.
class ApiDeleteLlmModelAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue id;

  ApiDeleteLlmModelAction({required this.id});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.deleteLlmModel(id: id),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiDeleteLlmModelAction(id: $id)';
}

/// Makes the model [modelId] the default model, the one of users who did not choose a model.
class ApiSetDefaultModelAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final UuidValue modelId;

  ApiSetDefaultModelAction({required this.modelId});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.setDefaultModel(request: SetDefaultModelRequest(modelId: modelId)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiSetDefaultModelAction(modelId: $modelId)';
}

// Document extraction (admins only).

/// What the document conversion is doing across all repositories, with its totals.
class ApiGetExtractionOverviewAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ExtractionOverviewDto> {
  ApiGetExtractionOverviewAction();

  @override
  Future<(AccountClient?, ExtractionOverviewDto)> reduce() async {
    final overview = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getExtractionOverview(),
      ),
    );
    return (state, overview);
  }
}

/// A page of the documents of all repositories, [limit] of them from [offset], those matching [filter].
class ApiListExtractionDocumentsAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, ExtractionDocumentPageDto> {
  final DocumentFilter filter;
  final int offset;
  final int limit;

  ApiListExtractionDocumentsAction({required this.filter, required this.offset, required this.limit});

  @override
  Future<(AccountClient?, ExtractionDocumentPageDto)> reduce() async {
    final page = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.listExtractionDocuments(filter: filter, offset: offset, limit: limit),
      ),
    );
    return (state, page);
  }

  @override
  String toString() => 'ApiListExtractionDocumentsAction(filter: $filter, offset: $offset, limit: $limit)';
}

/// Converts the document with the content [blobOid] again (deletes its failed extraction, clears its skip).
class ApiRetryDocumentExtractionAction extends AsyncReduxAction<ApiService, AccountClient?> {
  final String blobOid;

  ApiRetryDocumentExtractionAction({required this.blobOid});

  @override
  Future<AccountClient?> reduce() async {
    await dispatchAsyncTakeResult(
      _ApiCallAction<void>(
        call: (client) => client.retryDocumentExtraction(request: RetryDocumentRequest(blobOid: blobOid)),
      ),
    );
    return state;
  }

  @override
  String toString() => 'ApiRetryDocumentExtractionAction(blobOid: $blobOid)';
}

// Configuration (admins only).

/// Every setting of the server, sorted by key: its environment value, its override and whether it can be
/// overridden at runtime.
class ApiGetConfigAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<ConfigEntryDto>> {
  ApiGetConfigAction();

  @override
  Future<(AccountClient?, List<ConfigEntryDto>)> reduce() async {
    final entries = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.getConfig(),
      ),
    );
    return (state, entries);
  }
}

/// Replaces all overrides (keys left out fall back to the environment) and returns the settings.
class ApiSetConfigAction extends AsyncReduxActionWithResult<ApiService, AccountClient?, List<ConfigEntryDto>> {
  final Map<String, String> overrides;

  ApiSetConfigAction({required this.overrides});

  @override
  Future<(AccountClient?, List<ConfigEntryDto>)> reduce() async {
    final entries = await dispatchAsyncTakeResult(
      _ApiCallAction(
        call: (client) => client.setConfig(overrides: overrides),
      ),
    );
    return (state, entries);
  }

  @override
  String toString() => 'ApiSetConfigAction(keys: ${overrides.keys.toList()})';
}
