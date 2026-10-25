import 'package:app/gen/strings.g.dart';
import 'package:app/service/account_service.dart';
import 'package:app/service/api_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:app/widget/admin/mistral_key_sheet.dart';
import 'package:app/widget/admin/override_sheet.dart';
import 'package:app/widget/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The configuration of the server, for admins: every environment variable with its value and its override, and
/// overriding the runtime settings (those that apply without a restart) by tapping them. The advice on overrides versus
/// environment variables is left out for the local instance, whose environment the user can't set, and so are the
/// settings the user can't change there: only the runtime settings and the Mistral OCR key, which is set in the app
/// instead (see [MistralKeySheet]), are listed.
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> with Refena {
  /// `null` until they are loaded.
  List<ConfigEntryDto>? _entries;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // ignore: discarded_futures
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final entries = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiGetConfigAction());
      if (mounted) {
        setState(() {
          _entries = entries;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.config.page.loadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// Sets the Mistral OCR key of the local instance, which starts it again, and loads the settings again.
  Future<void> _setMistralKey(ConfigEntryDto entry) async {
    if (await MistralKeySheet.show(context, isSet: entry.env != null) && mounted) {
      await _load();
    }
  }

  Future<void> _override(ConfigEntryDto entry) async {
    final entries = _entries;
    if (entries == null) {
      return;
    }
    final updated = await OverrideSheet.show(context, entry: entry, entries: entries);
    if (updated != null && mounted) {
      setState(() {
        _entries = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final t = context.t;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final recommendEnv = t.base.admin.config.page.recommendEnv(envVars: '\u0000').split('\u0000');
    final local = context.watch(accountProvider.select((state) => state.active?.isLocal ?? false));
    final shown = local ? entries?.where((e) => e.runtime || e.key == ocrApiKeyMistral).toList() : entries;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.admin.config.title)),
      body: shown == null
          ? _loading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('config.retry'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(t.base.common.retry),
                    ),
                  )
          : ListView(
              key: const ValueKey('config.list'),
              padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
              children: [
                if (!local) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(t.base.admin.config.page.stored, style: muted),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: recommendEnv.first),
                          TextSpan(
                            text: t.base.admin.config.page.envVars,
                            style: muted?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(text: recommendEnv.last),
                        ],
                      ),
                      style: muted,
                    ),
                  ),
                ],
                Padding(
                  padding: EdgeInsets.fromLTRB(16, local ? 16 : 0, 16, 8),
                  child: Text(t.base.admin.config.page.ocrHint, style: muted),
                ),
                if (!local)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      t.flutter.admin.config.page.runtimeOnly,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(t.base.admin.config.page.noConfig, style: muted),
                  ),
                for (final entry in shown)
                  _EntryTile(
                    entry: entry,
                    onTap: entry.runtime
                        ? () => _override(entry)
                        : local && entry.key == ocrApiKeyMistral
                        ? () => _setMistralKey(entry)
                        : null,
                  ),
              ],
            ),
    );
  }
}

/// A setting: its key, its environment value (struck through while an override is in effect), its override, and
/// whether it is a runtime setting (tapping it opens the override sheet).
class _EntryTile extends StatelessWidget {
  final ConfigEntryDto entry;
  final VoidCallback? onTap;

  const _EntryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final theme = Theme.of(context);
    final env = entry.env;
    final override = entry.overrideValue;
    final envLabel = t.base.admin.config.overrideDialog.env(value: '\u0000').split('\u0000');
    final overrideLabel = t.flutter.admin.config.page.overrideValue(value: '\u0000').split('\u0000');
    final mono = theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', fontFamilyFallback: const ['Menlo', 'Courier']);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListTile(
      key: ValueKey('config.entry.${entry.key}'),
      title: Text(entry.key, style: mono),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: envLabel.first),
                if (env == null)
                  TextSpan(
                    text: t.base.admin.config.page.notSet,
                    style: muted?.copyWith(fontStyle: FontStyle.italic),
                  )
                else
                  TextSpan(
                    text: env,
                    style: override != null ? muted?.copyWith(decoration: TextDecoration.lineThrough) : null,
                  ),
                TextSpan(text: envLabel.last),
              ],
            ),
            style: muted,
          ),
          if (override != null)
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: overrideLabel.first),
                  TextSpan(
                    text: override,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: overrideLabel.last),
                ],
              ),
              style: muted,
            ),
        ],
      ),
      isThreeLine: override != null,
      trailing: entry.runtime
          ? StatusChip(label: t.flutter.admin.config.page.runtime, color: theme.colorScheme.primary, icon: Icons.bolt)
          : null,
      onTap: onTap,
    );
  }
}
