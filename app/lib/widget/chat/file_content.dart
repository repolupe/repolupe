import 'dart:convert';

import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/src/rust/third_party/repolupe/dto/attachment.dart';
import 'package:app/widget/chat/code_block.dart';
import 'package:app/widget/chat/markdown_content.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// How the app shows a file, the same files the web shows next to the chat.
enum FileKind {
  pdf,
  image,
  markdown,
  text;

  /// By the file's `Content-Type`, and for Markdown by its name too, since not every browser reports a type for the
  /// Markdown files it attaches. `null` if the app cannot show the file.
  static FileKind? of({required String? contentType, String? fileName}) {
    final type = (contentType ?? '').split(';').first.trim().toLowerCase();
    final name = (fileName ?? '').toLowerCase();
    return switch (type) {
      'application/pdf' => pdf,
      'image/png' || 'image/jpeg' || 'image/gif' || 'image/webp' => image,
      'text/markdown' => markdown,
      _ when name.endsWith('.md') || name.endsWith('.markdown') => markdown,
      _ when type.startsWith('text/') => text,
      _ => null,
    };
  }
}

/// Larger text attachments are saved instead of shown, like on the web.
const _maxAttachmentTextBytes = 1024 * 1024;

extension AttachmentKind on AttachmentDto {
  /// Whether a tap shows the attachment in the app. Other files, and large text files, are saved instead, like the web
  /// downloads them.
  bool get canShow => switch (FileKind.of(contentType: contentType, fileName: fileName)) {
    FileKind.pdf || FileKind.image => true,
    FileKind.markdown || FileKind.text => size <= _maxAttachmentTextBytes,
    null => false,
  };
}

/// A downloaded file as it is shown: Markdown rendered, PDFs in a viewer, images zoomable, other text as it is.
sealed class LoadedFile {
  const LoadedFile();

  /// Whether the content fills the rest of the page and scrolls itself, instead of scrolling with the page.
  bool get fillsPage => false;

  /// By its [FileKind].
  factory LoadedFile.of(FileDownload file) {
    return switch (FileKind.of(contentType: file.contentType, fileName: file.fileName)) {
      FileKind.pdf => PdfFile(file.content),
      FileKind.image => ImageFile(file.content),
      FileKind.markdown => MarkdownFile(utf8.decode(file.content, allowMalformed: true)),
      FileKind.text => TextFile(utf8.decode(file.content, allowMalformed: true)),
      null => const OtherFile(),
    };
  }
}

class MarkdownFile extends LoadedFile {
  final String text;

  const MarkdownFile(this.text);
}

class TextFile extends LoadedFile {
  final String text;

  const TextFile(this.text);
}

class PdfFile extends LoadedFile {
  final Uint8List content;

  const PdfFile(this.content);

  @override
  bool get fillsPage => true;
}

/// A PNG, JPEG, GIF or WebP image.
class ImageFile extends LoadedFile {
  final Uint8List content;

  const ImageFile(this.content);

  @override
  bool get fillsPage => true;
}

/// A file of another type, which the app cannot show.
class OtherFile extends LoadedFile {
  const OtherFile();
}

/// The content of [file]. [sourceName] identifies a PDF in the viewer's cache.
class FileContent extends StatelessWidget {
  final LoadedFile file;
  final String sourceName;

  const FileContent({super.key, required this.file, required this.sourceName});

  @override
  Widget build(BuildContext context) {
    return switch (file) {
      MarkdownFile(:final text) => MarkdownContent(content: text),
      TextFile(:final text) => CodeBlock(text: text),
      PdfFile(:final content) => PdfViewer.data(content, sourceName: sourceName),
      ImageFile(:final content) => InteractiveViewer(
        maxScale: 8,
        child: SizedBox.expand(
          child: Image.memory(
            content,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Center(child: _CannotShow()),
          ),
        ),
      ),
      OtherFile() => const _CannotShow(),
    };
  }
}

/// Says that the app cannot show the file.
class _CannotShow extends StatelessWidget {
  const _CannotShow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      context.t.flutter.chat.fileContent.cannotShow,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

/// Saves [file] as [fileName] with [saveDownload].
class DownloadButton extends StatelessWidget {
  final FileDownload file;
  final String fileName;

  const DownloadButton({super.key, required this.file, required this.fileName});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    return IconButton(
      icon: const Icon(Icons.download),
      tooltip: context.t.base.common.download,
      onPressed: () => saveDownload(ref, file, fileName),
    );
  }
}

/// Saves [file] as [fileName] where the user chooses, or shows a snack bar if it cannot.
Future<void> saveDownload(Ref ref, FileDownload file, String fileName) async {
  // Without parameters like the charset, which Android's save dialog does not take.
  final type = (file.contentType ?? '').split(';').first.trim();
  try {
    await FilePicker.saveFile(
      fileName: fileName,
      bytes: file.content,
      mimeType: type.isEmpty ? 'application/octet-stream' : type,
    );
  } on PlatformException {
    ref.global.dispatch(ShowSnackBarAction(message: t.flutter.chat.fileContent.saveFailed));
  }
}

/// The page of a file: [title], [header] above the content, and [child] once it is loaded.
class FileScaffold extends StatelessWidget {
  final String title;
  final Widget? header;
  final bool loading;
  final String? error;
  final Widget? child;

  /// In the app bar, e.g. a download button.
  final List<Widget>? actions;

  /// Below the page, e.g. an action that stays visible while the content scrolls.
  final Widget? footer;

  /// Whether [child] fills the rest of the page and scrolls itself (see [LoadedFile.fillsPage]), instead of scrolling with the page.
  final bool fill;

  const FileScaffold({
    super.key,
    required this.title,
    this.header,
    required this.loading,
    required this.error,
    required this.child,
    this.actions,
    this.footer,
    this.fill = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = this.header;
    return Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: actions,
        bottom: loading ? const PreferredSize(preferredSize: Size.fromHeight(4), child: LinearProgressIndicator()) : null,
      ),
      bottomNavigationBar: footer,
      body: SafeArea(
        child: switch ((fill, error, child)) {
          (true, null, final child?) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (header != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: header,
                ),
              Expanded(child: child),
            ],
          ),
          _ => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (header != null) ...[
                header,
                const SizedBox(height: 16),
              ],
              if (error case final error?)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(error, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onErrorContainer)),
                )
              else
                ?child,
            ],
          ),
        },
      ),
    );
  }
}
