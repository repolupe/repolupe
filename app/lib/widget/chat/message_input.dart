import 'dart:math';
import 'dart:ui' as ui;

import 'package:app/gen/strings.g.dart';
import 'package:app/service/chat_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/widget/chat/attachment_label.dart';
import 'package:app/widget/chat/input_options_sheet.dart';
import 'package:app/widget/chat/mcp_server_sheet.dart';
import 'package:app/widget/chat/model_sheet.dart';
import 'package:app/widget/chat/repository_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Photos taken with the camera are scaled down to this longer edge before they are uploaded, since the model looks at
/// them at 1568 px anyway. A little more keeps small writing legible if the photo is stored in a repository.
const _maxPhotoEdge = 2048.0;

/// Of the WebP the scaled photo is encoded as.
const _photoQuality = 85;

final _logger = Logger('MessageInput');

/// The text field and below it the actions, in one box: a plus button with the options (taking a photo, attaching a
/// file, and what a new chat reads), the model, and the button that sends the message, or stops the answer being
/// generated. The attached file is above the text field, the repositories and MCP servers of the new chat (unless all)
/// above the plus button.
class MessageInput extends StatefulWidget {
  const MessageInput({super.key});

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> with Refena {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    // Unfocusing the field, not the page's scope, which would keep it as the scope's focused child,
    // so that the scope focusing again (e.g. when the drawer opens) would show the keyboard again.
    FocusManager.instance.primaryFocus?.unfocus();
    final sent = await ref.redux(chatProvider).dispatchAsyncTakeResult(SendMessageAction(_controller.text));
    if (sent && mounted) {
      _controller.clear();
    }
  }

  Future<void> _attach() async {
    final file = await FilePicker.pickFile();
    if (file == null || !mounted) {
      return;
    }
    // Without a length, reading the file fails too, which the action reports.
    final size = file.lengthSync() ?? await file.length() ?? 0;
    await ref.redux(chatProvider).dispatchAsync(AttachFileAction(fileName: file.name, size: size, read: file.readAsBytes));
  }

  /// Attaches a photo taken with the camera, like a file, but scaled down and as a WebP: unlike a file the user picks,
  /// it has no original to keep, and at full resolution it takes megabytes to upload and store.
  Future<void> _takePhoto() async {
    final XFile? photo;
    try {
      // Not scaled by the picker, which would encode it as a JPEG once more, but only when it is encoded as a WebP.
      photo = await ImagePicker().pickImage(source: ImageSource.camera);
    } on PlatformException catch (e) {
      final messages = t.flutter.chat.messageInput;
      ref.global.dispatch(ShowSnackBarAction(message: e.code == 'camera_access_denied' ? messages.cameraDenied : messages.cameraFailed));
      return;
    }
    if (photo == null || !mounted) {
      return;
    }
    final webp = await _toWebp(photo);
    if (!mounted) {
      return;
    }
    // The picker names it with a random id, so it is named after the time instead.
    final time = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    if (webp != null) {
      await ref.redux(chatProvider).dispatchAsync(AttachFileAction(fileName: 'IMG_$time.webp', size: webp.length, read: () async => webp));
      return;
    }
    // Without the WebP, the photo as taken, keeping its extension.
    final dot = photo.name.lastIndexOf('.');
    final extension = dot < 0 ? '.jpg' : photo.name.substring(dot);
    final size = await photo.length();
    await ref.redux(chatProvider).dispatchAsync(AttachFileAction(fileName: 'IMG_$time$extension', size: size, read: photo.readAsBytes));
  }

  /// The [photo] as a WebP, scaled down to [_maxPhotoEdge], or null if it can't be read or encoded.
  static Future<Uint8List?> _toWebp(XFile photo) async {
    try {
      // The compressor scales the shorter edge down to its size, so that is the shorter edge the photo has once its
      // longer one is at most the maximum. Being the same for both, it doesn't matter which edge is the width after
      // the compressor turns the photo upright.
      final (:width, :height) = await _size(photo);
      final shortEdge = (min(width, height) * min(1.0, _maxPhotoEdge / max(width, height))).round();
      return await FlutterImageCompress.compressWithFile(
        photo.path,
        minWidth: shortEdge,
        minHeight: shortEdge,
        quality: _photoQuality,
        format: CompressFormat.webp,
      );
    } catch (e, st) {
      _logger.warning('Encoding the photo as a WebP failed', e, st);
      return null;
    }
  }

  /// The width and height of the [photo] as stored (not turned upright), read from its header.
  static Future<({int width, int height})> _size(XFile photo) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(await photo.readAsBytes());
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final size = (width: descriptor.width, height: descriptor.height);
    descriptor.dispose();
    buffer.dispose();
    return size;
  }

  Future<void> _showOptions() async {
    final option = await InputOptionsSheet.show(context);
    if (!mounted) {
      return;
    }
    switch (option) {
      case InputOption.camera:
        await _takePhoto();
      case InputOption.attach:
        await _attach();
      case InputOption.repositories:
        await RepositorySheet.show(context);
      case InputOption.mcpServers:
        await McpServerSheet.show(context);
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch(chatProvider);
    final answering = state.answer != null;
    final canSend = state.canSend(_controller.text);
    final attachment = state.attachment;
    // Only the scopes that are not all items, so the default takes no space.
    final newChat = state.chat == null && state.loaded;
    final chips = [
      if (newChat && state.repositories.isNotEmpty && !state.allRepositories)
        _ScopeChip(
          key: const ValueKey('chat.repositories'),
          icon: RepositorySheet.icon(state),
          label: RepositorySheet.summary(context, state),
          tooltip: context.t.base.repositories.title,
          enabled: !state.busy,
          onPressed: () async => RepositorySheet.show(context),
          onDeleted: () => ref.redux(chatProvider).dispatch(SetRepositoryScopeAction(all: true, ids: const [])),
        ),
      if (newChat && state.mcpServers.isNotEmpty && !state.allMcpServers)
        _ScopeChip(
          key: const ValueKey('chat.mcpServers'),
          icon: McpServerSheet.icon(state),
          label: McpServerSheet.summary(context, state),
          tooltip: context.t.base.mcpServers.title,
          enabled: !state.busy,
          onPressed: () async => McpServerSheet.show(context),
          onDeleted: () => ref.redux(chatProvider).dispatch(SetMcpServerScopeAction(all: true, ids: const [])),
        ),
    ];
    final colors = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: AnimatedContainer(
        // Fades with the page's background.
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        decoration: BoxDecoration(
          // A shade darker than the page's background,
          // but white on the light temporary background, which is about as dark.
          color: state.isTemporary && colors.brightness == Brightness.light ? colors.surfaceContainerLowest : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (attachment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: _AttachmentChip(attachment: attachment, enabled: !state.sending),
              ),
            TextField(
              key: const ValueKey('chat.input'),
              controller: _controller,
              focusNode: _focusNode,
              minLines: 1,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: context.t.base.chat.placeholder,
                border: InputBorder.none,
                // Lines up with the icon of the button below.
                contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              ),
            ),
            // Above the plus button, so the model has the rest of the row below.
            if (chips.isNotEmpty)
              GestureDetector(
                // Taps on the free space focus the text field, as if the box were the field.
                behavior: HitTestBehavior.opaque,
                onTap: _focusNode.requestFocus,
                child: Padding(
                  // As far from the edge as the buttons below.
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 8, children: chips),
                  ),
                ),
              ),
            // The buttons are as far from the edges as from the bottom.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  IconButton(
                    key: const ValueKey('chat.options'),
                    icon: const Icon(Icons.add),
                    tooltip: context.t.base.chat.messageInput.options,
                    // A new chat has more options once they are loaded.
                    onPressed: !state.busy && (state.chat != null || state.loaded) ? _showOptions : null,
                  ),
                  Expanded(
                    // Taps on the free space focus the text field, as if the box were the field.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _focusNode.requestFocus,
                      // The model next to the send button, as wide as its name, up to all of the space.
                      child: SizedBox(
                        height: 48,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: state.models.isEmpty ? null : _ModelButton(state: state, enabled: !state.busy),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Stopping keeps the keyboard open, sending closes it.
                  if (answering)
                    IconButton.filledTonal(
                      key: const ValueKey('chat.stop'),
                      icon: const Icon(Icons.stop),
                      tooltip: context.t.base.chat.messageInput.stop,
                      onPressed: () async {
                        await ref.redux(chatProvider).dispatchAsync(CancelAnswerAction());
                      },
                    )
                  else
                    IconButton(
                      key: const ValueKey('chat.send'),
                      icon: state.sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      tooltip: context.t.base.chat.messageInput.send,
                      onPressed: canSend ? _send : null,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The file attached to the next message, with a spinner while it is uploaded, and a button that removes it.
class _AttachmentChip extends StatelessWidget {
  final PendingAttachment attachment;
  final bool enabled;

  const _AttachmentChip({required this.attachment, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return InputChip(
      key: const ValueKey('chat.attachment'),
      isEnabled: enabled,
      avatar: attachment.uploaded == null
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.attach_file),
      label: AttachmentLabel(
        fileName: attachment.fileName,
        size: attachment.size,
        sizeColor: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onDeleted: () => context.redux(chatProvider).dispatch(RemoveAttachmentAction()),
    );
  }
}

/// A scope of the new chat while it is not all items, opening the sheet to choose them. Removing it chooses all again.
class _ScopeChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// What the items are, e.g. "Repositories".
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final VoidCallback onDeleted;

  const _ScopeChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      isEnabled: enabled,
      avatar: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      tooltip: tooltip,
      onPressed: onPressed,
      onDeleted: onDeleted,
    );
  }
}

/// The model that answers in the chat, as quiet text next to the send button, opening a sheet to choose another.
class _ModelButton extends StatelessWidget {
  final ChatState state;
  final bool enabled;

  const _ModelButton({required this.state, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final defaultModelId = context.watch(meProvider.select((user) => user?.defaultModelId));
    return TextButton(
      key: const ValueKey('chat.model'),
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: enabled ? () async => ModelSheet.show(context) : null,
      child: Text(
        state.answeringModel(defaultModelId)?.displayName ?? context.t.base.common.kDefault,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
