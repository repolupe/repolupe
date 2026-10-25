import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/me_service.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:app/util/locales.dart';
import 'package:app/widget/settings/default_model_sheet.dart';
import 'package:app/widget/settings/locale_sheet.dart';
import 'package:flutter/material.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// The preferences of the active account: its model, its language, and whether proposed changes are applied
/// automatically (only for users who may manage repositories).
class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> with Refena {
  /// The models the user can choose, `null` until they are loaded.
  List<ModelDto>? _models;
  bool _loadingModels = false;
  bool _savingModel = false;
  bool _savingLocale = false;
  bool _savingAutoCommit = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) {
      // Current when the page opens, e.g. after it was edited on another device.
      // ignore: discarded_futures
      ref.redux(meProvider).dispatchAsync(RefreshMeAction());
      // ignore: discarded_futures
      _loadModels();
    });
  }

  Future<void> _loadModels() async {
    setState(() {
      _loadingModels = true;
    });
    try {
      final models = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiListModelsAction());
      if (mounted) {
        setState(() {
          _models = models;
        });
      }
    } on ClientError catch (e) {
      ref.global.dispatch(ShowSnackBarAction(message: t.base.settings.preferences.page.modelsLoadFailed(error: e.userMessage)));
    } finally {
      if (mounted) {
        setState(() {
          _loadingModels = false;
        });
      }
    }
  }

  /// The user's model, else the default one, or that there is none.
  String _modelLabel(Translations t, UserDto user) {
    final models = _models;
    if (models == null) {
      return t.base.common.loading;
    }
    if (models.isEmpty) {
      return t.base.settings.preferences.page.noModels;
    }
    final chosen = models.where((m) => m.id == user.defaultModelId).firstOrNull;
    if (chosen != null) {
      return '${chosen.displayName} (${chosen.providerName})';
    }
    final defaultModel = models.where((m) => m.isDefault).firstOrNull;
    return defaultModel != null ? t.base.settings.preferences.defaultModel(name: defaultModel.displayName) : t.base.settings.preferences.defaultNone;
  }

  Future<void> _chooseModel(UserDto user) async {
    final models = _models;
    if (models == null) {
      return;
    }
    if (models.isEmpty) {
      ref.global.dispatch(ShowSnackBarAction(message: context.t.base.settings.preferences.page.noModelsAskAdmin));
      return;
    }
    final choice = await DefaultModelSheet.show(context, models: models, chosenModelId: user.defaultModelId);
    if (choice == null || !mounted) {
      return;
    }
    setState(() {
      _savingModel = true;
    });
    try {
      final result = await ref.global.dispatchAsync(SetDefaultModelAction(choice.modelId));
      if (result == SetDefaultModelResult.unknownModel && mounted) {
        // Deleted in the meantime.
        await _loadModels();
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingModel = false;
        });
      }
    }
  }

  Future<void> _chooseLocale(UserDto user) async {
    final choice = await LocaleSheet.show(context, chosen: user.locale);
    if (choice == null || !mounted) {
      return;
    }
    setState(() {
      _savingLocale = true;
    });
    try {
      await ref.global.dispatchAsync(SetLocaleAction(choice.locale));
    } finally {
      if (mounted) {
        setState(() {
          _savingLocale = false;
        });
      }
    }
  }

  Future<void> _setAutoCommit(bool autoCommit) async {
    setState(() {
      _savingAutoCommit = true;
    });
    try {
      await ref.global.dispatchAsync(SetAutoCommitAction(autoCommit));
    } finally {
      if (mounted) {
        setState(() {
          _savingAutoCommit = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final user = context.watch(meProvider);
    final modelBusy = _loadingModels || _savingModel;
    return Scaffold(
      appBar: AppBar(title: Text(t.base.settings.preferences.title)),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.paddingOf(context).bottom),
              children: [
                ListTile(
                  key: const ValueKey('preferences.model'),
                  leading: const Icon(Icons.smart_toy),
                  title: Text(t.base.common.model),
                  subtitle: Text(_modelLabel(t, user)),
                  trailing: modelBusy ? const _Progress() : const Icon(Icons.edit),
                  onTap: modelBusy ? null : () => _chooseModel(user),
                ),
                ListTile(
                  key: const ValueKey('preferences.locale'),
                  leading: const Icon(Icons.language),
                  title: Text(t.base.settings.preferences.language),
                  subtitle: Text(user.locale ?? t.flutter.settings.preferences.deviceDefaultWithLocale(locale: deviceLocaleTag())),
                  trailing: _savingLocale ? const _Progress() : const Icon(Icons.edit),
                  onTap: _savingLocale ? null : () => _chooseLocale(user),
                ),
                if (user.canManageRepositories)
                  SwitchListTile(
                    key: const ValueKey('preferences.autoCommit'),
                    secondary: _savingAutoCommit ? const _Progress() : const Icon(Icons.publish),
                    title: Text(t.base.settings.preferences.page.autoCommit),
                    subtitle: Text(t.base.settings.preferences.page.autoCommitHint),
                    value: user.autoCommit,
                    onChanged: _savingAutoCommit ? null : _setAutoCommit,
                  ),
              ],
            ),
    );
  }
}

/// Shown in a row while its request runs.
class _Progress extends StatelessWidget {
  const _Progress();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
  }
}
