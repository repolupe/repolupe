import 'dart:convert';

import 'package:app/src/rust/api/mirror.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';

const _indented = JsonEncoder.withIndent('  ');

/// [text], the text of a JSON value (a tool's schema, the arguments of a call), as it is shown: indented, or as the
/// model sent it if it is a string (arguments that were not a JSON object) or no JSON at all.
String formatJsonText(String text) {
  final Object? value;
  try {
    value = jsonDecode(text);
  } on FormatException {
    return text;
  }
  return value is String ? value : _indented.convert(value);
}

/// The JSON value [text] is the text of, or the text itself if it is none.
Object? _jsonValue(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

extension RawAnswerJson on RawAnswerDto {
  /// The tool of each call by the call's id, since a result only has the id.
  Map<String, String> get toolNames => {
    for (final message in messages)
      for (final block in message.content)
        if (block case RawBlockDto_ToolUse(:final id, :final name)) id: name,
  };

  /// The answer as indented JSON, as the API sends it.
  String toJsonText() => _indented.convert({
    'system': system,
    'tools': [
      for (final tool in tools) {'name': tool.name, 'description': tool.description, 'input_schema': _jsonValue(tool.inputSchema)},
    ],
    'messages': [
      for (final message in messages)
        {
          'role': switch (message.role) {
            MessageRole.user => 'USER',
            MessageRole.assistant => 'ASSISTANT',
          },
          'content': [for (final block in message.content) block._toJson()],
        },
    ],
  });
}

extension RawMessageContent on RawMessageDto {
  /// Whether it only has tool results, which are sent as user messages, but don't come from the user.
  bool get onlyToolResults => content.isNotEmpty && content.every((block) => block is RawBlockDto_ToolResult);
}

extension on RawBlockDto {
  Map<String, Object?> _toJson() => switch (this) {
    RawBlockDto_Text(:final text) => {'type': 'TEXT', 'text': text},
    RawBlockDto_Reasoning(:final text, :final redacted) => {'type': 'REASONING', 'text': text, 'redacted': redacted},
    RawBlockDto_ToolUse(:final id, :final name, :final input) => {'type': 'TOOL_USE', 'id': id, 'name': name, 'input': _jsonValue(input)},
    RawBlockDto_ToolResult(:final toolUseId, :final content, :final isError) => {
      'type': 'TOOL_RESULT',
      'tool_use_id': toolUseId,
      'content': content,
      'is_error': isError,
    },
    RawBlockDto_Unknown() => {'type': 'UNKNOWN'},
  };
}
