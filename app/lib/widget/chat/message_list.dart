import 'dart:math';

import 'package:app/service/message_service.dart';
import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/widget/chat/assistant_message.dart';
import 'package:app/widget/chat/user_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

/// The least space to the left and right of the messages. Answers put it inside them, so that their wide tables scroll
/// through it to the screen's edges.
const _minHorizontalPadding = 16.0;

/// The messages of a chat, newest at the bottom. They scroll on behind the message input, whose height is the bottom
/// padding (the Scaffold's body, which extends behind it), and fade into the background there.
class MessageList extends StatefulWidget {
  final UuidValue chatId;
  final List<MessageDto> messages;

  /// The name of the model with the id, if it is still offered.
  final String? Function(UuidValue? modelId) modelName;

  /// The width of the messages, with their padding. The list itself spans the whole width and centers them, so that the
  /// wide tables of answers scroll through the space beside them to the screen's edges.
  final double maxWidth;

  const MessageList({
    super.key,
    required this.chatId,
    required this.messages,
    required this.modelName,
    this.maxWidth = double.infinity,
  });

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _resize = _UserResize();

  @override
  Widget build(BuildContext context) {
    final messages = widget.messages;
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = _minHorizontalPadding + max(0.0, (constraints.maxWidth - widget.maxWidth) / 2);
          return ListView.separated(
            key: const ValueKey('chat.messages'),
            // Starts at the bottom and stays there while the answer grows.
            reverse: true,
            // An answer the user resizes keeps its top in place instead.
            physics: _KeepTopPhysics(_resize, parent: const AlwaysScrollableScrollPhysics()),
            padding: EdgeInsets.only(top: 16, bottom: 24 + input),
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: (context, index) {
              final message = messages[messages.length - 1 - index];
              // The list's padding already makes room for the message input, so the messages don't see it. Otherwise
              // the scrollbar of a wide table or code block would be drawn that far above its bottom edge.
              return MediaQuery.removePadding(
                context: context,
                removeBottom: true,
                child: switch (message.role) {
                  MessageRole.user => Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: UserMessage(key: ValueKey(message.id), message: message),
                  ),
                  MessageRole.assistant => _Answer(
                    key: ValueKey(message.id),
                    chatId: widget.chatId,
                    message: message,
                    modelName: widget.modelName(message.modelId),
                    horizontalPadding: horizontalPadding,
                    resize: _resize,
                  ),
                },
              );
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
  final double horizontalPadding;
  final _UserResize resize;

  const _Answer({
    super.key,
    required this.chatId,
    required this.message,
    required this.modelName,
    required this.horizontalPadding,
    required this.resize,
  });

  @override
  Widget build(BuildContext context) {
    final running = context.watch(messageProvider.select((m) => m != null && m.id == message.id ? m : null));
    return _HeightObserver(
      onChanged: (delta) => resize.changed(message.id, delta),
      child: AssistantMessage(
        chatId: chatId,
        message: running != null && message.status == MessageStatus.generating ? running : message,
        modelName: modelName,
        horizontalPadding: horizontalPadding,
        onResize: () => resize.start(message.id),
      ),
    );
  }
}

/// How much the height of an answer changed on the user's request (e.g. fitting its tables to the width), for
/// [_KeepTopPhysics] to scroll by.
class _UserResize {
  /// The answer the user is resizing, until the end of the frame.
  UuidValue? _messageId;
  double _delta = 0;

  /// Called right before the answer with [messageId] changes its height on the user's request.
  void start(UuidValue messageId) {
    _messageId = messageId;
    // Dropped if the list could not scroll by it (e.g. it isn't longer than the screen).
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _messageId = null;
      _delta = 0;
    });
  }

  /// Called during layout, when the height of the answer with [messageId] changed by [delta].
  void changed(UuidValue messageId, double delta) {
    if (messageId == _messageId) {
      _delta += delta;
    }
  }

  /// The change that the list has not scrolled by yet.
  double take() {
    final delta = _delta;
    _delta = 0;
    return delta;
  }
}

/// Keeps the top of an answer the user resizes in place (with the button they tapped), rather than its bottom, at which
/// the reversed list is anchored. It scrolls by the change in the same layout, so that the answer doesn't jump for a
/// frame, as it would with a jump after it.
class _KeepTopPhysics extends ScrollPhysics {
  final _UserResize resize;

  const _KeepTopPhysics(this.resize, {super.parent});

  @override
  _KeepTopPhysics applyTo(ScrollPhysics? ancestor) => _KeepTopPhysics(resize, parent: buildParent(ancestor));

  /// Called during layout when the extent of the list changed, as it does when an answer changes its height.
  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    final delta = resize.take();
    if (delta == 0) {
      return super.adjustPositionForNewDimensions(
        oldPosition: oldPosition,
        newPosition: newPosition,
        isScrolling: isScrolling,
        velocity: velocity,
      );
    }
    // Instead of the parents' adjustment, which would e.g. keep the position at the end of a shrinking list and so move
    // it by the change twice.
    return (newPosition.pixels + delta).clamp(newPosition.minScrollExtent, newPosition.maxScrollExtent);
  }
}

/// Reports how much the height of its child changed, while it is laid out.
class _HeightObserver extends SingleChildRenderObjectWidget {
  final ValueChanged<double> onChanged;

  const _HeightObserver({required this.onChanged, required super.child});

  @override
  _RenderHeightObserver createRenderObject(BuildContext context) => _RenderHeightObserver(onChanged);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightObserver renderObject) {
    renderObject.onChanged = onChanged;
  }
}

class _RenderHeightObserver extends RenderProxyBox {
  ValueChanged<double> onChanged;

  _RenderHeightObserver(this.onChanged);

  @override
  void performLayout() {
    final oldHeight = hasSize ? size.height : null;
    super.performLayout();
    if (oldHeight != null && size.height != oldHeight) {
      onChanged(size.height - oldHeight);
    }
  }
}
