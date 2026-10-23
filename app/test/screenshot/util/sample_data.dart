import '../../support/fake_repository.dart';
import '../../support/fake_user.dart';

const sampleUserId = '0199a8d4-6d5e-7c3a-9b1f-2a4c6e8d0f12';
const sampleUserName = 'alex';

const sampleProviderId = '0199a8d4-6d5e-7c3a-9b1f-100000000001';
const sampleModelId = '0199a8d4-6d5e-7c3a-9b1f-100000000002';

const documentsId = '0199a8d4-6d5e-7c3a-9b1f-200000000001';
const notesId = '0199a8d4-6d5e-7c3a-9b1f-200000000002';

const taxChatId = '0199a8d4-6d5e-7c3a-9b1f-300000000001';
const passportChatId = '0199a8d4-6d5e-7c3a-9b1f-300000000002';

final sampleUser = fakeUser(id: sampleUserId, userName: sampleUserName, email: 'alex@example.com', role: 'ADMIN', defaultModelId: sampleModelId);

final documents = fakeRepository(
  id: documentsId,
  ownerId: sampleUserId,
  name: 'documents',
  description: 'Taxes, insurance, payslips and everything else that comes on paper.',
  url: 'https://git.example.com/alex/documents.git',
  hasToken: true,
  tokenHint: '7f3a',
  gitSize: 4820000,
  lfsSize: 31400000,
);

final notes = fakeRepository(
  id: notesId,
  ownerId: sampleUserId,
  name: 'notes',
  description: 'Things worth remembering.',
  local: true,
);

/// What every page of a logged-in user may load: the user, the instance, the models and the repositories.
Map<String, Object?> baseRoutes() => {
  '/api/v1/me': sampleUser,
  '/api/v1/instance': {'name': 'Acme'},
  '/api/v1/models': [
    fakeModel(id: sampleModelId, displayName: ' Mistral 4 119B', providerId: sampleProviderId, providerName: 'OpenRouter', isDefault: true),
  ],
  '/api/v1/repositories': [documents, notes],
  '/api/v1/chats': {
    'items': [chat(passportChatId, 'Passport renewal', notesId), chat(taxChatId, 'Tax ID', documentsId)],
    'next_cursor': null,
  },
};

Map<String, dynamic> chat(String id, String title, String repositoryId) => {
  'id': id,
  'title': title,
  'all_repositories': false,
  'repository_ids': [repositoryId],
  'model_id': sampleModelId,
  'temporary': false,
  'created_at': '2026-10-21T09:12:00+00:00',
  'updated_at': '2026-10-21T09:13:00+00:00',
};

/// A question of a chat and its answer, which the model found with [toolCalls] (name and input).
typedef Exchange = ({String question, List<(String, Map<String, dynamic>)> toolCalls, String answer});

/// A chat with its messages, like `GET /api/v1/chats/{id}` returns it: the [exchanges] in the repository
/// [repositoryId]. The ids of the messages and tool calls are [id] with another end.
Map<String, dynamic> chatDetail({
  required String id,
  required String title,
  required String repositoryId,
  required List<Exchange> exchanges,
}) {
  var n = 0;
  String nextId() => '${id.substring(0, 30)}${(++n).toString().padLeft(6, '0')}';
  return {
    ...chat(id, title, repositoryId),
    'messages': [
      for (final exchange in exchanges) ...[
        _message(id: nextId(), role: 'USER', content: exchange.question),
        _message(
          id: nextId(),
          role: 'ASSISTANT',
          content: exchange.answer,
          toolCalls: [
            for (final (name, input) in exchange.toolCalls)
              {
                'id': nextId(),
                'name': name,
                'input': input,
                'repository_id': repositoryId,
                'commit_sha': '0123456789abcdef0123456789abcdef01234567',
                'status': 'COMPLETED',
                'created_at': '2026-10-21T09:12:10+00:00',
              },
          ],
        ),
      ],
    ],
  };
}

Map<String, dynamic> _message({
  required String id,
  required String role,
  required String content,
  List<Map<String, dynamic>> toolCalls = const [],
}) {
  final answer = role == 'ASSISTANT';
  return {
    'id': id,
    'role': role,
    'content': content,
    'status': 'COMPLETED',
    'error': null,
    'model_id': answer ? sampleModelId : null,
    'tool_calls': toolCalls,
    'created_at': '2026-10-21T09:12:00+00:00',
    'finished_at': answer ? '2026-10-21T09:12:42+00:00' : null,
    'usage': answer ? {'input_tokens': 18240, 'output_tokens': 412, 'cache_read_tokens': 12800, 'cache_write_tokens': 0} : null,
    'cost': answer ? {'amount': '0.0072', 'currency': 'USD'} : null,
    'attachment': null,
  };
}
