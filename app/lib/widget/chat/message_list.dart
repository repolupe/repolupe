import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/assistant_message.dart';
import 'package:app/widget/chat/user_message.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The space to the left and right of the messages. Answers put it inside them, so that their wide tables scroll
/// through it to the screen's edges.
const _horizontalPadding = 16.0;

/// The messages of a chat, newest at the bottom. They scroll on behind the message input, whose height is the bottom
/// padding (the Scaffold's body, which extends behind it), and fade into the background there.
class MessageList extends StatelessWidget {
  final UuidValue chatId;
  final List<MessageDto> messages;

  /// The name of the model with the id, if it is still offered.
  final String? Function(UuidValue? modelId) modelName;

  const MessageList({super.key, required this.chatId, required this.messages, required this.modelName});

  @override
  Widget build(BuildContext context) {
    // The message input's height, with the space below it.
    final input = MediaQuery.paddingOf(context).bottom;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return ShaderMask(
      // The messages fade into the background from the top of the message input to the bottom of the screen, or the
      // keyboard's top.
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black, Colors.transparent],
      ).createShader(Rect.fromLTRB(0, bounds.bottom - input, bounds.right, bounds.bottom - keyboard)),
      child: ListView.separated(
        key: const ValueKey('chat.messages'),
        // Starts at the bottom and stays there while the answer grows.
        reverse: true,
        padding: EdgeInsets.only(top: 16, bottom: 24 + input),
        itemCount: messages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 24),
        itemBuilder: (context, index) {
          final message = messages[messages.length - 1 - index];
          // The list's padding already makes room for the message input, so the messages don't see it. Otherwise the
          // scrollbar of a wide table or code block would be drawn that far above its bottom edge.
          return MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: switch (message.role) {
              MessageRole.user => Padding(
                padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
                child: UserMessage(key: ValueKey(message.id), message: message),
              ),
              MessageRole.assistant => _Answer(
                key: ValueKey(message.id),
                chatId: chatId,
                message: message,
                modelName: modelName(message.modelId),
              ),
            },
          );
        },
      ),
    );
  }
}

/// An answer, while it is generated as the [MessageService] follows it, so that its events rebuild only this answer.
/// The same widget before and after it finishes, so that the [AssistantMessage] keeps its state (the text it reveals).
class _Answer extends StatelessWidget {
  final UuidValue chatId;

  /// The answer as the chat has it, shown until the [MessageService] follows it, and once it is finished.
  final MessageDto message;
  final String? modelName;

  const _Answer({super.key, required this.chatId, required this.message, required this.modelName});

  @override
  Widget build(BuildContext context) {
    final running = context.watch(messageProvider.select((m) => m != null && m.id == message.id ? m : null));
    return AssistantMessage(
      chatId: chatId,
      message: running != null && message.status == MessageStatus.generating ? running : message,
      modelName: modelName,
      horizontalPadding: _horizontalPadding,
    );
  }
}
