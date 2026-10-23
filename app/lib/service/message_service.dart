import 'dart:async';
import 'dart:math';

import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/api/stream.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart' hide MessageEvent;
import 'package:uuid/uuid.dart';

final _logger = Logger('MessageService');

/// How long to wait before subscribing to an answer again after its stream broke off, doubled up to [_maxRetryDelay].
const _minRetryDelay = Duration(seconds: 1);
const _maxRetryDelay = Duration(seconds: 30);

final messageProvider = ReduxProvider<MessageService, MessageDto?>((ref) {
  return MessageService(api: ref.notifier(apiProvider));
});

/// The answer being generated, updated with every event of its stream, `null` if none is followed.
/// Kept apart from the chat so that the events rebuild only the answer; once it is finished, the chat has it.
class MessageService extends ReduxNotifier<MessageDto?> {
  final ApiService _api;

  /// Cancels the stream of the answer being followed.
  CancellationToken? _streamCancel;

  MessageService({required this._api});

  @override
  MessageDto? init() => null;

  void _stopStream() {
    _streamCancel?.cancel();
    _streamCancel = null;
  }
}

/// Applies the events of [message] (an answer being generated in [chatId]) until it is finished,
/// subscribing again whenever the stream breaks off.
/// Returns the finished answer, or `null` if it was stopped by [StopFollowMessageAction] or by following another one.
class FollowMessageAction extends AsyncReduxActionWithResult<MessageService, MessageDto?, MessageDto?> {
  final UuidValue chatId;
  final MessageDto message;

  FollowMessageAction({
    required this.chatId,
    required this.message,
  });

  @override
  Future<(MessageDto?, MessageDto?)> reduce() async {
    final messageId = message.id;
    notifier._stopStream();
    final cancel = CancellationToken();
    notifier._streamCancel = cancel;
    dispatch(_SetMessageAction(message));

    var delay = _minRetryDelay;
    while (!cancel.isCancelled()) {
      try {
        final events = await external(
          notifier._api,
        ).dispatchAsyncTakeResult(ApiStreamMessageAction(chatId: chatId, messageId: messageId, cancel: cancel));
        await for (final event in events) {
          if (cancel.isCancelled()) {
            break;
          }
          if (event case MessageEvent_Error(:final error)) {
            _logger.warning('The stream of $messageId broke off: $error');
          } else {
            delay = _minRetryDelay;
            dispatch(_ApplyEventAction(messageId, event));
          }
        }
      } on ClientError_Api catch (e) {
        // E.g. the chat was deleted elsewhere, so subscribing again would not help either.
        if (!cancel.isCancelled()) {
          dispatch(_FailMessageAction(messageId, e.userMessage));
        }
        break;
      } on ClientError catch (e) {
        _logger.warning('Cannot follow $messageId: $e');
      }

      if (cancel.isCancelled() || state?.status != MessageStatus.generating) {
        break;
      }
      await Future<void>.delayed(delay);
      delay = Duration(milliseconds: min(delay.inMilliseconds * 2, _maxRetryDelay.inMilliseconds));
    }

    if (cancel.isCancelled()) {
      // The state belongs to whoever stopped it.
      return (state, null);
    }
    notifier._streamCancel = null;
    return (null, state);
  }

  @override
  String toString() => 'FollowMessageAction(${message.id})';
}

/// Stops following the answer, e.g. for a new chat.
class StopFollowMessageAction extends ReduxAction<MessageService, MessageDto?> {
  @override
  MessageDto? reduce() {
    notifier._stopStream();
    return null;
  }
}

class _SetMessageAction extends ReduxAction<MessageService, MessageDto?> {
  final MessageDto message;

  _SetMessageAction(this.message);

  @override
  MessageDto? reduce() => message;

  @override
  String toString() => '_SetMessageAction(${message.id})';
}

class _ApplyEventAction extends ReduxAction<MessageService, MessageDto?> {
  final UuidValue messageId;
  final MessageEvent event;

  _ApplyEventAction(this.messageId, this.event);

  @override
  MessageDto? reduce() {
    final current = state;
    if (current == null || current.id != messageId) {
      return state;
    }
    return switch (event) {
      MessageEvent_Snapshot(:final message) || MessageEvent_Done(:final message) => message,
      MessageEvent_ContentDelta(:final delta) => _copyMessage(current, content: current.content + delta.text),
      MessageEvent_ToolCallStarted(:final toolCall) => _copyMessage(current, toolCalls: [...current.toolCalls, toolCall]),
      MessageEvent_ToolCallFinished(:final toolCall) => _copyMessage(
        current,
        toolCalls: [for (final t in current.toolCalls) t.id == toolCall.id ? _copyToolCall(t, status: toolCall.status) : t],
      ),
      MessageEvent_Error() => current,
    };
  }

  /// Without the event, which would print the whole message.
  @override
  String toString() => '_ApplyEventAction($messageId, ${event.runtimeType})';
}

/// Shows the answer [messageId] as failed with [error], when it can no longer be followed.
class _FailMessageAction extends ReduxAction<MessageService, MessageDto?> {
  final UuidValue messageId;
  final String error;

  _FailMessageAction(this.messageId, this.error);

  @override
  MessageDto? reduce() {
    final message = state;
    if (message == null || message.id != messageId) {
      return state;
    }
    return _copyMessage(message, status: MessageStatus.failed, error: error);
  }
}

MessageDto _copyMessage(
  MessageDto m, {
  String? content,
  MessageStatus? status,
  String? error,
  List<ToolCallSummaryDto>? toolCalls,
}) {
  return MessageDto(
    id: m.id,
    role: m.role,
    content: content ?? m.content,
    status: status ?? m.status,
    error: error ?? m.error,
    modelId: m.modelId,
    toolCalls: toolCalls ?? m.toolCalls,
    createdAt: m.createdAt,
    finishedAt: m.finishedAt,
    usage: m.usage,
    cost: m.cost,
    attachment: m.attachment,
  );
}

ToolCallSummaryDto _copyToolCall(ToolCallSummaryDto t, {required ToolCallStatus status}) {
  return ToolCallSummaryDto(
    id: t.id,
    name: t.name,
    input: t.input,
    repositoryId: t.repositoryId,
    commitSha: t.commitSha,
    status: status,
    createdAt: t.createdAt,
  );
}
