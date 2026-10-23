import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:uuid/uuid.dart';

/// The `LlmProviderDto` JSON of a fake server, like `GET /api/v1/llm-providers` lists them. [hasKey] with its
/// [keyHint] for a key; [currency] `null` if its models have no prices.
Map<String, dynamic> fakeLlmProvider({
  required String id,
  String name = 'Anthropic',
  String apiFormat = 'ANTHROPIC',
  String baseUrl = 'https://api.anthropic.com',
  bool hasKey = true,
  String? keyHint,
  String? currency = 'USD',
  List<Map<String, dynamic>> models = const [],
}) => {
  'id': id,
  'name': name,
  'api_format': apiFormat,
  'base_url': baseUrl,
  'api_key': hasKey ? {'hint': keyHint} : null,
  'currency': currency,
  'models': models,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
};

/// The `LlmModelDto` JSON of a fake server, as a provider lists its models.
Map<String, dynamic> fakeLlmModel({
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
}) => {
  'id': id,
  'provider_id': providerId,
  'api_name': apiName,
  'display_name': displayName,
  'max_output_tokens': maxOutputTokens,
  'input_price': inputPrice,
  'output_price': outputPrice,
  'cache_read_price': cacheReadPrice,
  'cache_write_price': cacheWritePrice,
  'is_default': isDefault,
  'created_at': '2026-10-20T12:00:00+00:00',
  'updated_at': '2026-10-20T12:00:00+00:00',
};

/// The `RemoteModelDto` JSON of a fake server, like `GET /api/v1/llm-providers/{id}/remote-models` lists them.
Map<String, dynamic> fakeRemoteModel({required String apiName, String? displayName}) => {'api_name': apiName, 'display_name': displayName};

/// The `LlmProviderDto` of the fake JSON, as the LLM page passes it to the form and the sheet.
LlmProviderDto llmProviderOf(Map<String, dynamic> json) => LlmProviderDto(
  id: UuidValue.fromString(json['id'] as String),
  name: json['name'] as String,
  apiFormat: json['api_format'] == 'ANTHROPIC' ? LlmApiFormat.anthropic : LlmApiFormat.openAi,
  baseUrl: json['base_url'] as String,
  apiKey: json['api_key'] == null ? null : ApiKeyDto(hint: (json['api_key'] as Map<String, dynamic>)['hint'] as String?),
  currency: json['currency'] as String?,
  models: [for (final model in json['models'] as List<Map<String, dynamic>>) llmModelOf(model)],
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);

/// The `LlmModelDto` of the fake JSON.
LlmModelDto llmModelOf(Map<String, dynamic> json) => LlmModelDto(
  id: UuidValue.fromString(json['id'] as String),
  providerId: UuidValue.fromString(json['provider_id'] as String),
  apiName: json['api_name'] as String,
  displayName: json['display_name'] as String?,
  maxOutputTokens: json['max_output_tokens'] as int?,
  inputPrice: json['input_price'] as String?,
  outputPrice: json['output_price'] as String?,
  cacheReadPrice: json['cache_read_price'] as String?,
  cacheWritePrice: json['cache_write_price'] as String?,
  isDefault: json['is_default'] as bool,
  createdAt: DateTime.parse(json['created_at'] as String),
  updatedAt: DateTime.parse(json['updated_at'] as String),
);
