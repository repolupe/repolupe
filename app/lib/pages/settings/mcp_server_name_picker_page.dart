import 'package:app/gen/strings.g.dart';
import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:app/util/currencies.dart';
import 'package:app/widget/flag_emoji.dart';
import 'package:app/widget/page_list_view.dart';
import 'package:flutter/material.dart';

/// The name of a new MCP server: one of the common servers, which fills in its URL, or a name of the user's own
/// (`suggestion` `null`).
typedef McpServerNameChoice = ({String name, McpServerSuggestionDto? suggestion});

/// What a server is for, e.g. "Search", shown below a suggestion. `null` for kinds of a newer server.
String? mcpServerKindLabel(Translations t, McpServerKind kind) {
  final kinds = t.base.mcpServers.kind;
  return switch (kind) {
    McpServerKind.search => kinds.search,
    McpServerKind.webScraping => kinds.webScraping,
    McpServerKind.documentation => kinds.documentation,
    McpServerKind.devTools => kinds.devTools,
    McpServerKind.cloud => kinds.cloud,
    McpServerKind.database => kinds.database,
    McpServerKind.observability => kinds.observability,
    McpServerKind.projectManagement => kinds.projectManagement,
    McpServerKind.productivity => kinds.productivity,
    McpServerKind.crm => kinds.crm,
    McpServerKind.payments => kinds.payments,
    McpServerKind.finance => kinds.finance,
    McpServerKind.design => kinds.design,
    McpServerKind.automation => kinds.automation,
    McpServerKind.knowledge => kinds.knowledge,
    McpServerKind.maps => kinds.maps,
    McpServerKind.travel => kinds.travel,
    McpServerKind.unknown => null,
  };
}

/// Picks the name of a new MCP server from the common ones (from the Rust crate), filtered by the search field, which
/// also takes a name of its own. Pops with an [McpServerNameChoice].
class McpServerNamePickerPage extends StatefulWidget {
  /// The name chosen so far, which the search starts with.
  final String name;

  const McpServerNamePickerPage({super.key, required this.name});

  @override
  State<McpServerNamePickerPage> createState() => _McpServerNamePickerPageState();
}

class _McpServerNamePickerPageState extends State<McpServerNamePickerPage> {
  late String _query = widget.name;
  late final _queryController = TextEditingController(text: widget.name);
  final Future<List<McpServerSuggestionDto>> _suggestions = mcpServerSuggestions();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  /// The suggestions whose name contains the query, ignoring case. All of them while it is empty or one of them
  /// exactly (e.g. the one chosen before).
  List<McpServerSuggestionDto> _filtered(List<McpServerSuggestionDto> suggestions) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty || suggestions.any((s) => s.name.toLowerCase() == query)) {
      return suggestions;
    }
    return suggestions.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  void _choose(McpServerNameChoice choice) {
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
    final picker = t.flutter.mcpServers.namePicker;
    final name = _query.trim();
    return Scaffold(
      appBar: AppBar(title: Text(picker.title)),
      body: SafeArea(
        child: FutureBuilder(
          future: _suggestions,
          builder: (context, snapshot) {
            final suggestions = snapshot.data ?? const [];
            final isSuggestion = suggestions.any((s) => s.name.toLowerCase() == name.toLowerCase());
            return PageListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    key: const ValueKey('mcpServerNamePicker.search'),
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
                    key: const ValueKey('mcpServerNamePicker.custom'),
                    leading: const Icon(Icons.edit_outlined),
                    title: Text(picker.useName(name: name)),
                    onTap: _chooseOwnName,
                  ),
                for (final suggestion in _filtered(suggestions))
                  ListTile(
                    key: ValueKey('mcpServerNamePicker.${suggestion.name}'),
                    leading: FlagEmoji(countryFlag(suggestion.countryCode)),
                    title: Text(suggestion.name),
                    subtitle: switch (mcpServerKindLabel(t, suggestion.kind)) {
                      final kind? => Text(kind),
                      null => null,
                    },
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
