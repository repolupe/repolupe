import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/util/currencies.dart';
import 'package:app/widget/flag_emoji.dart';
import 'package:flutter/material.dart';

/// The name of a new provider: one of the common providers, which fills in the rest of the form, or a name of the
/// admin's own (`suggestion` `null`).
typedef LlmProviderNameChoice = ({String name, LlmProviderSuggestionDto? suggestion});

/// Picks the name of a new LLM provider from the common ones, filtered by the search field, which also takes a name
/// of its own. Pops with an [LlmProviderNameChoice].
class LlmProviderNamePickerPage extends StatefulWidget {
  /// The name chosen so far, which the search starts with.
  final String name;

  const LlmProviderNamePickerPage({super.key, required this.name});

  @override
  State<LlmProviderNamePickerPage> createState() => _LlmProviderNamePickerPageState();
}

class _LlmProviderNamePickerPageState extends State<LlmProviderNamePickerPage> {
  late String _query = widget.name;
  late final _queryController = TextEditingController(text: widget.name);
  final Future<List<LlmProviderSuggestionDto>> _suggestions = llmProviderSuggestions();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// The suggestions whose name contains the query, ignoring case. All of them while it is empty or one of them
  /// exactly (e.g. the one chosen before).
  List<LlmProviderSuggestionDto> _filtered(List<LlmProviderSuggestionDto> suggestions) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty || suggestions.any((s) => s.name.toLowerCase() == query)) {
      return suggestions;
    }
    return suggestions.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  void _choose(LlmProviderNameChoice choice) {
    Navigator.pop(context, choice);
  }

  /// Takes the query as the name, unless it is blank.
  void _chooseOwnName() {
    final name = _query.trim();
    if (name.isNotEmpty) {
      _choose((name: name, suggestion: null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final picker = t.flutter.admin.llm.namePicker;
    final name = _query.trim();
    return Scaffold(
      appBar: AppBar(title: Text(picker.title)),
      body: SafeArea(
        child: FutureBuilder(
          future: _suggestions,
          builder: (context, snapshot) {
            final suggestions = snapshot.data ?? const [];
            final filtered = _filtered(suggestions);
            final isSuggestion = suggestions.any((s) => s.name.toLowerCase() == name.toLowerCase());
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    key: const ValueKey('providerNamePicker.search'),
                    controller: _queryController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: picker.searchHint,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.done,
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    onSubmitted: (_) => _chooseOwnName(),
                  ),
                ),
                if (name.isNotEmpty && !isSuggestion)
                  ListTile(
                    key: const ValueKey('providerNamePicker.custom'),
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(picker.useName(name: name)),
                    onTap: _chooseOwnName,
                  ),
                for (final suggestion in filtered)
                  ListTile(
                    key: ValueKey('providerNamePicker.${suggestion.name}'),
                    leading: FlagEmoji(countryFlag(suggestion.countryCode)),
                    title: Text(suggestion.name),
                    subtitle: _subtitle(context, suggestion),
                    onTap: () => _choose((name: suggestion.name, suggestion: suggestion)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The brand of the provider's own models, or for routers that requests may run anywhere; hosts have none.
Widget? _subtitle(BuildContext context, LlmProviderSuggestionDto suggestion) {
  if (suggestion.modelBrand case final brand?) {
    return Text(brand);
  }
  if (suggestion.runsInference) {
    return null;
  }
  return Row(
    children: [
      const Icon(Icons.call_split, size: 12),
      const SizedBox(width: 4),
      Text(context.t.base.admin.llm.providerDialog.thirdParty),
    ],
  );
}
