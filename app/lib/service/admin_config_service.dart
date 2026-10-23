import 'dart:async';

import 'package:app/gen/strings.g.dart';
import 'package:app/service/api_service.dart';
import 'package:app/service/instance_name_provider.dart';
import 'package:app/src/rust/api/error.dart';
import 'package:app/src/rust/third_party/repolupe/dto/config.dart';
import 'package:refena_flutter/addons.dart';
import 'package:refena_flutter/refena_flutter.dart';

// What admins do to the server's configuration (`/api/v1/config`).

/// What [SetConfigOverrideAction] did: the settings as the API lists them afterwards, or why it rejected the value
/// (shown in the dialog, which stays open).
typedef SetConfigResult = ({List<ConfigEntryDto>? entries, String? error});

/// Sets the override of [key] to [value], or removes it if [value] is `null` (or blank). The API replaces all
/// overrides, so the ones of the other [entries] are sent along unchanged. Shows a snack bar if it succeeded.
class SetConfigOverrideAction extends AsyncGlobalActionWithResult<SetConfigResult> {
  final List<ConfigEntryDto> entries;
  final String key;
  final String? value;

  SetConfigOverrideAction({required this.entries, required this.key, required this.value});

  /// The overrides to send: those of the other entries, plus [value] for [key] if it is set.
  Map<String, String> get overrides {
    final overrides = <String, String>{
      for (final entry in entries)
        if (entry.key != key && entry.overrideValue != null) entry.key: entry.overrideValue!,
    };
    final value = this.value?.trim();
    if (value != null && value.isNotEmpty) {
      overrides[key] = value;
    }
    return overrides;
  }

  @override
  Future<SetConfigResult> reduce() async {
    final List<ConfigEntryDto> updated;
    try {
      updated = await ref.redux(apiProvider).dispatchAsyncTakeResult(ApiSetConfigAction(overrides: overrides));
    } on ClientError catch (e) {
      return (entries: null, error: e.userMessage);
    }

    // The instance name may have changed, which the start page of a chat shows.
    unawaited(ref.rebuild(instanceNameProvider));
    ref.global.dispatch(ShowSnackBarAction(message: t.base.admin.config.page.updated));
    return (entries: updated, error: null);
  }

  @override
  String toString() => 'SetConfigOverrideAction(key: $key, value: $value)';
}
