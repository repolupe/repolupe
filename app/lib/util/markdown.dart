import 'package:markdown/markdown.dart' as md;

/// Whether [content] has a table anywhere, also in a list or quote. Parsed as answers are rendered (GitHub flavored),
/// so that a table in a code block, or rows without a delimiter row, don't count.
bool containsTable(String content) {
  final nodes = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored).parse(content);
  return _containsTable(nodes);
}

bool _containsTable(List<md.Node> nodes) {
  return nodes.any((node) => node is md.Element && (node.tag == 'table' || _containsTable(node.children ?? const [])));
}
