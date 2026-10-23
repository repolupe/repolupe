import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:flutter/material.dart';

/// The tools that propose commits, shown with the `ProposedCommitPage`.
const changeTools = {'change_file', 'move_files', 'save_attachment'};

/// The last segment of a path, e.g. `guide.md` for `docs/guide.md`.
String fileName(String path) {
  final segments = path.split('/').where((s) => s.isNotEmpty);
  return segments.isEmpty ? path : segments.last;
}

/// A path without empty and `.` segments.
String _normalizePath(String path) => path.split('/').where((s) => s.isNotEmpty && s != '.').join('/');

extension ToolCallInput on ToolCallSummaryDto {
  /// The object the model called the tool with, empty if it is not one.
  Map<String, dynamic> get inputMap {
    try {
      final value = jsonDecode(input);
      return value is Map<String, dynamic> ? value : const {};
    } on FormatException {
      return const {};
    }
  }

  /// The `path` input without empty and `.` segments, `null` if it has none.
  String? get path => switch (inputMap['path']) {
    final String path => _normalizePath(path),
    _ => null,
  };

  /// The `moves` input of a `move_files` call with their paths like [path], empty for other calls.
  List<FileMoveDto> get moves {
    final moves = inputMap['moves'];
    if (name != 'move_files' || moves is! List) {
      return const [];
    }
    String normalize(Object? path) => path is String ? _normalizePath(path) : '';
    return [
      for (final m in moves) FileMoveDto(from: normalize(m is Map ? m['from'] : null), to: normalize(m is Map ? m['to'] : null)),
    ];
  }

  /// The repository the model named, for calls whose repository was deleted.
  String? get repositoryName => switch (inputMap['repository']) {
    final String name => name,
    _ => null,
  };

  IconData get icon => switch (name) {
    'list_files' => Icons.folder_outlined,
    'read_file' => Icons.description_outlined,
    'grep' => Icons.manage_search,
    'outline' => Icons.format_list_bulleted,
    'present_file_to_user' => Icons.preview_outlined,
    'change_file' => Icons.edit_outlined,
    'move_files' => Icons.drive_file_move_outline,
    'save_attachment' => Icons.upload_file_outlined,
    'read_attachment' => Icons.attach_file,
    _ => Icons.build_outlined,
  };

  /// The most telling part of the input, e.g. the path that was read or the pattern that was searched.
  String get detail {
    final input = inputMap;
    String? str(Object? value) => switch (value) {
      final String s when s.isNotEmpty => s,
      final num n => '$n',
      _ => null,
    };
    final path = str(input['path']);
    final glob = str(input['glob']);
    switch (name) {
      case 'list_files':
        return [path ?? '/', ?glob].join(' ');
      case 'read_file' || 'outline' || 'present_file_to_user' || 'change_file':
        return path ?? '';
      case 'move_files':
        final moves = this.moves;
        return moves.length == 1 ? '${moves.first.from} → ${moves.first.to}' : t.base.chat.moveCount(count: moves.length);
      case 'read_attachment':
        final attachment = str(input['attachment']);
        return attachment == null ? '' : '#$attachment';
      case 'save_attachment':
        final attachment = str(input['attachment']);
        return [if (attachment != null) '#$attachment', if (path != null) '→ $path'].join(' ');
      case 'grep':
        final pattern = str(input['pattern']);
        final where = [?path, ?glob].join(' ');
        if (pattern != null && where.isNotEmpty) {
          return t.base.chat.toolCallLabel.grepPatternIn(pattern: pattern, where: where);
        }
        return pattern != null ? '"$pattern"' : (where.isEmpty ? '' : t.base.chat.toolCallLabel.grepIn(where: where));
      default:
        return input.isEmpty ? '' : jsonEncode(input);
    }
  }
}

/// A file the model showed with `present_file_to_user`, or a change it proposed, with the path it refers to.
typedef ToolCallFile = ({ToolCallSummaryDto toolCall, String path});

/// The files the model showed in [message] with `present_file_to_user`, each once.
List<ToolCallFile> presentedFiles(MessageDto message) {
  final files = <String, ToolCallFile>{};
  for (final toolCall in message.toolCalls) {
    final path = toolCall.path;
    if (toolCall.name != 'present_file_to_user' || toolCall.status != ToolCallStatus.completed || path == null) {
      continue;
    }
    files.putIfAbsent('${toolCall.repositoryId}:$path', () => (toolCall: toolCall, path: path));
  }
  return files.values.toList();
}

/// The changes the model proposed in [message] with `change_file`, the moves it proposed with `move_files` (`path` is
/// where the first one moves to), and the attachments it proposed to store with `save_attachment`. A later call for
/// the same file, the same attachment, or moves in the same repository, replaces an earlier one.
List<ToolCallFile> proposedChanges(MessageDto message) {
  final changes = <String, ToolCallFile>{};
  for (final toolCall in message.toolCalls) {
    final path = toolCall.name == 'move_files' ? toolCall.moves.firstOrNull?.to : toolCall.path;
    if (!changeTools.contains(toolCall.name) || toolCall.status != ToolCallStatus.completed || path == null) {
      continue;
    }
    final key = switch (toolCall.name) {
      'save_attachment' => 'attachment:${toolCall.inputMap['attachment']}',
      'move_files' => '${toolCall.repositoryId}:moves',
      _ => '${toolCall.repositoryId}:$path',
    };
    // Removed first, so the later one also takes the earlier one's place at the end.
    changes.remove(key);
    changes[key] = (toolCall: toolCall, path: path);
  }
  return changes.values.toList();
}
