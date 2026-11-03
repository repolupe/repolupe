import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// An item to choose in [scopeChoices], e.g. a repository.
typedef ScopeItem = ({UuidValue id, String title, String? subtitle});

/// Checkboxes for all [items] (titled [allTitle]) and each one; picking one while all are chosen chooses only that one.
/// [ids] are the chosen items unless [all].
List<Widget> scopeChoices({
  required String allTitle,
  required bool all,
  required List<UuidValue> ids,
  required List<ScopeItem> items,
  required void Function(bool all, List<UuidValue> ids) onChanged,
}) => [
  CheckboxListTile(
    title: Text(allTitle),
    value: all,
    onChanged: (value) => onChanged(value ?? false, const []),
  ),
  const Divider(),
  for (final item in items)
    CheckboxListTile(
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.subtitle == null ? null : Text(item.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      value: !all && ids.contains(item.id),
      onChanged: (selected) => onChanged(false, [
        if (!all) ...ids.where((id) => id != item.id),
        if (selected ?? false) item.id,
      ]),
    ),
];
