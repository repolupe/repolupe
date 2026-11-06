import 'package:app/src/rust/third_party/repolupe/dto/mcp.dart';
import 'package:uuid/uuid.dart';

/// A `McpServerDto`, like `GET /api/v1/mcp-servers` lists it: owned by [ownerId], or shared with the user by
/// `bob` if [shared] is set (whether they turned it on), with [tools] (by name) of which [disabledTools] are off.
McpServerDto fakeMcpServer({
  required String id,
  required String ownerId,
  String name = 'search',
  bool enabled = true,
  bool? shared,
  McpServerStatus status = McpServerStatus.ready,
  String? lastError,
  List<String> tools = const ['search'],
  List<String> disabledTools = const [],
}) => McpServerDto(
  id: UuidValue.fromString(id),
  ownerId: UuidValue.fromString(ownerId),
  shared: shared == null ? null : McpServerShareDto(ownerName: 'bob', enabled: shared, createdAt: DateTime.utc(2026, 10, 20, 12)),
  name: name,
  url: shared == null ? 'https://mcp.example.com/mcp' : 'https://mcp.example.com',
  enabled: enabled,
  auth: McpServerAuth.none,
  status: status,
  lastError: lastError,
  tools: [for (final tool in tools) McpToolDto(name: tool, description: 'Runs $tool')],
  disabledTools: disabledTools,
  checkedAt: DateTime.utc(2026, 10, 21, 12),
  createdAt: DateTime.utc(2026, 10, 20, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 12),
);
