import 'dart:convert';
import 'dart:typed_data';

import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/api/client.dart';
import 'package:app/widget/chat/code_block.dart';
import 'package:app/widget/chat/markdown_content.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// A downloaded file as it is shown: Markdown rendered, PDFs in a viewer, other text as it is.
sealed class LoadedFile {
  const LoadedFile();

  /// By the file's `Content-Type`.
  factory LoadedFile.of(FileDownload file) {
    final type = (file.contentType ?? '').split(';').first.trim().toLowerCase();
    return switch (type) {
      'application/pdf' => PdfFile(file.content),
      'text/markdown' => MarkdownFile(utf8.decode(file.content, allowMalformed: true)),
      _ when type.startsWith('text/') => TextFile(utf8.decode(file.content, allowMalformed: true)),
      _ => const OtherFile(),
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

/// Fills the rest of the page and scrolls itself.
class PdfFile extends LoadedFile {
  final Uint8List content;

  const PdfFile(this.content);
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
    final theme = Theme.of(context);
    return switch (file) {
      MarkdownFile(:final text) => MarkdownContent(content: text),
      TextFile(:final text) => CodeBlock(text: text),
      PdfFile(:final content) => PdfViewer.data(content, sourceName: sourceName),
      OtherFile() => Text(
        context.t.flutter.chat.fileContent.cannotShow,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    };
  }
}

/// The page of a file: [title], [header] above the content, and [child] once it is loaded.
class FileScaffold extends StatelessWidget {
  final String title;
  final Widget? header;
  final bool loading;
  final String? error;
  final Widget? child;

  /// Below the page, e.g. an action that stays visible while the content scrolls.
  final Widget? footer;

  /// Whether [child] fills the rest of the page and scrolls itself (e.g. a PDF viewer), instead of scrolling with the page.
  final bool fill;

  const FileScaffold({
    super.key,
    required this.title,
    this.header,
    required this.loading,
    required this.error,
    required this.child,
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
