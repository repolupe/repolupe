import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:uuid/uuid.dart';

/// An `LlmProviderDto`, like `GET /api/v1/llm-providers` lists them. [hasKey] with its [keyHint] for a key;
/// [currency] `null` if its models have no prices.
LlmProviderDto fakeLlmProvider({
  required String id,
  String name = 'Anthropic',
  LlmApiFormat apiFormat = LlmApiFormat.anthropic,
  String baseUrl = 'https://api.anthropic.com',
  bool hasKey = true,
  String? keyHint,
  String? currency = 'USD',
  List<LlmModelDto> models = const [],
}) => LlmProviderDto(
  id: UuidValue.fromString(id),
  name: name,
  apiFormat: apiFormat,
  baseUrl: baseUrl,
  apiKey: hasKey ? ApiKeyDto(hint: keyHint) : null,
  currency: currency,
  models: models,
  createdAt: DateTime.utc(2026, 10, 20, 12),
  updatedAt: DateTime.utc(2026, 10, 20, 12),
);

/// An `LlmModelDto`, as a provider lists its models.
LlmModelDto fakeLlmModel({
  required String id,
  required String providerId,
  required String apiName,
  String? displayName,
  int? maxOutputTokens,
  String? inputPrice,
  String? outputPrice,
  String? cacheReadPrice,
  String? cacheWritePrice,
  bool isDefault = false,
}) => LlmModelDto(
  id: UuidValue.fromString(id),
  providerId: UuidValue.fromString(providerId),
  apiName: apiName,
  displayName: displayName,
  maxOutputTokens: maxOutputTokens,
  inputPrice: inputPrice,
  outputPrice: outputPrice,
  cacheReadPrice: cacheReadPrice,
  cacheWritePrice: cacheWritePrice,
  isDefault: isDefault,
  createdAt: DateTime.utc(2026, 10, 20, 12),
  updatedAt: DateTime.utc(2026, 10, 20, 12),
);

/// A `RemoteModelDto`, like `GET /api/v1/llm-providers/{id}/remote-models` lists them.
RemoteModelDto fakeRemoteModel({required String apiName, String? displayName}) => RemoteModelDto(apiName: apiName, displayName: displayName);
