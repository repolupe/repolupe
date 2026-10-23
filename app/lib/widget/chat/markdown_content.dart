import 'package:app/gen/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('MarkdownContent');

/// The link schemes that open when tapped, others (e.g. app-specific ones) are ignored, since answers are written by the model.
const _linkSchemes = {'http', 'https', 'mailto', 'tel'};

/// The Markdown of an answer (GitHub flavored, like the web's), selectable. Links open outside the app.
class MarkdownContent extends StatelessWidget {
  final String content;

  const MarkdownContent({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Courier'],
      backgroundColor: Colors.transparent,
    );
    final codeBackground = BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    );
    final ref = context.ref;
    return MarkdownBody(
      data: content,
      selectable: true,
      onTapLink: (_, href, _) async {
        if (href != null) {
          await _openLink(ref, href);
        }
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyLarge,
        a: TextStyle(color: theme.colorScheme.primary, decoration: TextDecoration.underline),
        listBullet: theme.textTheme.bodyLarge,
        code: code,
        codeblockDecoration: codeBackground,
        codeblockPadding: const EdgeInsets.all(12),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant, width: 4)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12),
      ),
    );
  }
}

/// Opens [href] in the app that handles it (e.g. the browser), or shows a snack bar if it cannot.
Future<void> _openLink(Ref ref, String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null || !_linkSchemes.contains(uri.scheme.toLowerCase())) {
    _logger.info('Ignoring the link $href');
    return;
  }

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException catch (e) {
    _logger.warning('Cannot open $uri: $e');
  }
  if (!opened) {
    ref.global.dispatch(ShowSnackBarAction(message: t.flutter.chat.markdownContent.openLinkFailed(link: href)));
  }
}
