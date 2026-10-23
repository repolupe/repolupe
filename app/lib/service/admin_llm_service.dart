import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/util/validation.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

// What admins do to the LLM providers and their models (`/api/v1/llm-providers`, `/api/v1/models`,
// `/api/v1/default-model`): each action checks the input, calls the API, shows a snack bar in any case, and returns
// the result (`null` or `false` if it failed).

/// Creates an LLM provider after checking the name and currency (empty for none; the base URL and API key are
/// optional too). Returns the provider, `null` if that failed.
class CreateLlmProviderAction extends AsyncGlobalActionWithResult<LlmProviderDto?> {
  final String name;
  final LlmApiFormat apiFormat;
  final String baseUrl;
  final String apiKey;
  final String currency;

  CreateLlmProviderAction({
    required this.name,
    required this.apiFormat,
    required this.baseUrl,
    required this.apiKey,
    required this.currency,
  });

  @override
  Future<LlmProviderDto?> reduce() async {
    final name = this.name.trim();
    final currency = this.currency.trim().toUpperCase();
    final error = llmProviderError(name: name, currency: currency);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return null;
    }

    final LlmProviderDto provider;
    try {
      provider = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiCreateLlmProviderAction(
              request: CreateLlmProviderRequest(
                name: name,
                apiFormat: apiFormat,
                baseUrl: trimmedOrNull(baseUrl),
                apiKey: trimmedOrNull(apiKey),
                currency: trimmedOrNull(currency),
              ),
            ),
          );
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.createProviderFailed(error: e.userMessage)));
      return null;
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.providerCreated));
    return provider;
  }

  /// Without the API key, which the debug observers would print otherwise.
  @override
  String toString() => 'CreateLlmProviderAction(name: $name, apiFormat: $apiFormat, baseUrl: $baseUrl, currency: $currency)';
}

/// Replaces the settings of the LLM provider [id] after checking the name and currency (empty for none). The key is
/// kept, removed or replaced by [apiKey] (a new key must not be empty). Returns the provider, `null` if that failed.
class UpdateLlmProviderAction extends AsyncGlobalActionWithResult<LlmProviderDto?> {
  final UuidValue id;
  final String name;
  final LlmApiFormat apiFormat;
  final String baseUrl;
  final ApiKeyChange apiKey;
  final String currency;

  UpdateLlmProviderAction({
    required this.id,
    required this.name,
    required this.apiFormat,
    required this.baseUrl,
    required this.apiKey,
    required this.currency,
  });

  @override
  Future<LlmProviderDto?> reduce() async {
    final name = this.name.trim();
    final currency = this.currency.trim().toUpperCase();
    final error = llmProviderError(name: name, currency: currency);
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return null;
    }
    final apiKey = switch (this.apiKey) {
      ApiKeyChange_Set(:final value) => ApiKeyChange.set_(value: value.trim()),
      final change => change,
    };
    if (apiKey case ApiKeyChange_Set(:final value) when value.isEmpty) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.providerDialog.missingApiKey));
      return null;
    }

    final LlmProviderDto provider;
    try {
      provider = await ref
          .redux(apiProvider)
          .dispatchAsyncTakeResult(
            ApiUpdateLlmProviderAction(
              id: id,
              request: UpdateLlmProviderRequest(
                name: name,
                apiFormat: apiFormat,
                baseUrl: trimmedOrNull(baseUrl),
                apiKey: apiKey,
                currency: trimmedOrNull(currency),
              ),
            ),
          );
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.saveProviderFailed(error: e.userMessage)));
      return null;
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.providerUpdated));
    return provider;
  }

  /// Without the API key, which the debug observers would print otherwise.
  @override
  String toString() => 'UpdateLlmProviderAction(id: $id, name: $name, apiFormat: $apiFormat, baseUrl: $baseUrl, currency: $currency)';
}

/// Deletes the LLM provider [id] with its models. Returns why that failed, `null` if it was deleted (with a snack
/// bar then).
class DeleteLlmProviderAction extends AsyncGlobalActionWithResult<String?> {
  final UuidValue id;

  DeleteLlmProviderAction(this.id);

  @override
  Future<String?> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiDeleteLlmProviderAction(id: id));
    } on ClientError catch (e) {
      return t.base.admin.llm.page.deleteProviderFailed(error: e.userMessage);
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.providerDeleted));
    return null;
  }

  @override
  String toString() => 'DeleteLlmProviderAction($id)';
}

/// Adds a model to the provider [providerId], or replaces the model [modelId] if given, after checking the fields as
/// entered (empty for none; the prices only count if the provider has a currency, [hasCurrency]). Returns the model,
/// `null` if that failed.
class SaveLlmModelAction extends AsyncGlobalActionWithResult<LlmModelDto?> {
  final UuidValue providerId;

  /// The model being replaced, `null` to add one.
  final UuidValue? modelId;
  final bool hasCurrency;
  final String apiName;
  final String displayName;
  final String maxOutputTokens;
  final String inputPrice;
  final String outputPrice;
  final String cacheReadPrice;
  final String cacheWritePrice;

  SaveLlmModelAction({
    required this.providerId,
    required this.modelId,
    required this.hasCurrency,
    required this.apiName,
    required this.displayName,
    required this.maxOutputTokens,
    required this.inputPrice,
    required this.outputPrice,
    required this.cacheReadPrice,
    required this.cacheWritePrice,
  });

  @override
  Future<LlmModelDto?> reduce() async {
    final apiName = this.apiName.trim();
    final displayName = this.displayName.trim();
    final error = llmModelError(
      apiName: apiName,
      displayName: displayName,
      maxOutputTokens: maxOutputTokens,
      hasCurrency: hasCurrency,
      inputPrice: inputPrice,
      outputPrice: outputPrice,
      cacheReadPrice: cacheReadPrice,
      cacheWritePrice: cacheWritePrice,
    );
    if (error != null) {
      ref.global.dispatch(ShowSnackBarAction(message: error));
      return null;
    }
    final tokens = trimmedOrNull(maxOutputTokens);
    final request = LlmModelRequest(
      apiName: apiName,
      displayName: trimmedOrNull(displayName),
      maxOutputTokens: tokens == null ? null : int.parse(tokens),
      inputPrice: hasCurrency ? normalizePrice(inputPrice) : null,
      outputPrice: hasCurrency ? normalizePrice(outputPrice) : null,
      cacheReadPrice: hasCurrency ? normalizePrice(cacheReadPrice) : null,
      cacheWritePrice: hasCurrency ? normalizePrice(cacheWritePrice) : null,
    );

    final modelId = this.modelId;
    final LlmModelDto model;
    try {
      model = modelId == null
          ? await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiCreateLlmModelAction(providerId: providerId, request: request))
          : await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiUpdateLlmModelAction(id: modelId, request: request));
    } on ClientError catch (e) {
      final page = t.base.admin.llm.page;
      ref.global.dispatch(
        ShowSnackBarAction(
          message: modelId == null ? page.addModelFailed(error: e.userMessage) : page.saveModelFailed(error: e.userMessage),
        ),
      );
      return null;
    }

    ref.global.dispatch(
      ShowSnackBarAction(message: modelId == null ? t.base.admin.llm.page.modelsAdded(count: 1) : t.base.admin.llm.page.modelUpdated),
    );
    return model;
  }

  @override
  String toString() => 'SaveLlmModelAction(providerId: $providerId, modelId: $modelId, apiName: $apiName)';
}

/// What [AddRemoteModelsAction] did: the API names of the models it added, and if some failed, how many were added
/// and the first error (shown in the sheet, which stays open).
typedef AddRemoteModelsResult = ({List<String> added, String? error});

/// Adds the [models] a server listed to the provider [providerId], one after the other (so the first becomes the
/// default if there is none), with the server's display name if the API accepts it. Failures don't stop the others.
/// Shows a snack bar if all were added.
class AddRemoteModelsAction extends AsyncGlobalActionWithResult<AddRemoteModelsResult> {
  final UuidValue providerId;
  final List<RemoteModelDto> models;

  AddRemoteModelsAction({required this.providerId, required this.models});

  @override
  Future<AddRemoteModelsResult> reduce() async {
    final added = <String>[];
    final failed = <String>[];
    for (final model in models) {
      final displayName = model.displayName?.trim() ?? '';
      try {
        await ref
            .redux(apiProvider)
            .dispatchAsyncTakeResult(
              ApiCreateLlmModelAction(
                providerId: providerId,
                request: LlmModelRequest(
                  apiName: model.apiName,
                  // Shows the API name instead of a name the API would reject.
                  displayName: displayName.runes.length <= maxModelDisplayNameLength ? trimmedOrNull(displayName) : null,
                ),
              ),
            );
        added.add(model.apiName);
      } on ClientError catch (e) {
        failed.add('${model.displayName ?? model.apiName}: ${e.userMessage}');
      }
    }

    if (failed.isEmpty) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.modelsAdded(count: added.length)));
      return (added: added, error: null);
    }
    final more = failed.length - 1;
    final page = t.base.admin.llm.page;
    return (
      added: added,
      error: more > 0
          ? page.partlyAddedMore(added: added.length, total: models.length, error: failed.first, more: more)
          : page.partlyAdded(added: added.length, total: models.length, error: failed.first),
    );
  }

  @override
  String toString() => 'AddRemoteModelsAction(providerId: $providerId, models: ${models.map((m) => m.apiName).toList()})';
}

/// Deletes the model [id]; users who chose it fall back to the default model. Returns why that failed, `null` if it
/// was deleted (with a snack bar then).
class DeleteLlmModelAction extends AsyncGlobalActionWithResult<String?> {
  final UuidValue id;

  DeleteLlmModelAction(this.id);

  @override
  Future<String?> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiDeleteLlmModelAction(id: id));
    } on ClientError catch (e) {
      return t.base.admin.llm.page.deleteModelFailed(error: e.userMessage);
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.modelDeleted));
    return null;
  }

  @override
  String toString() => 'DeleteLlmModelAction($id)';
}

/// Makes the model [modelId] the default model. Returns whether it is (the page reloads the providers either way,
/// e.g. after `UNKNOWN_MODEL` when another admin deleted the model).
class SetDefaultLlmModelAction extends AsyncGlobalActionWithResult<bool> {
  final UuidValue modelId;

  SetDefaultLlmModelAction(this.modelId);

  @override
  Future<bool> reduce() async {
    try {
      await ref.redux(apiProvider).dispatchAsync(ApiSetDefaultModelAction(modelId: modelId));
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.setDefaultFailed(error: e.userMessage)));
      return false;
    }

    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.llm.page.defaultChanged));
    return true;
  }

  @override
  String toString() => 'SetDefaultLlmModelAction($modelId)';
}
