import 'dart:convert';

import 'package:app/src/rust/third_party/repolupe/dto/chat.dart';
import 'package:app/src/rust/third_party/repolupe/dto/extraction.dart';
import 'package:app/src/rust/third_party/repolupe/dto/instance.dart';
import 'package:app/src/rust/third_party/repolupe/dto/llm.dart';
import 'package:app/src/rust/third_party/repolupe/dto/repository.dart';
import 'package:app/src/rust/third_party/repolupe/dto/user.dart';
import 'package:uuid/uuid.dart';

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

final sampleUser = fakeUser(
  id: sampleUserId,
  userName: sampleUserName,
  email: 'alex@example.com',
  role: UserRole.admin,
  defaultModelId: sampleModelId,
);

/// The names and descriptions of the sample data in one language.
typedef SampleTexts = ({
  String documents,
  String documentsDescription,
  String notes,
  String notesDescription,
  String taxChat,
  String passportChat,
});

const englishTexts = (
  documents: 'documents',
  documentsDescription: 'Taxes, insurance, payslips and everything else that comes on paper.',
  notes: 'notes',
  notesDescription: 'Things worth remembering.',
  taxChat: 'Tax ID',
  passportChat: 'Passport renewal',
);

const germanTexts = (
  documents: 'dokumente',
  documentsDescription: 'Steuern, Versicherungen, Gehaltsabrechnungen und alles andere, was auf Papier kommt.',
  notes: 'notizen',
  notesDescription: 'Was ich mir merken möchte.',
  taxChat: 'Steuer-ID',
  passportChat: 'Reisepass verlängern',
);

RepositoryDto documents(SampleTexts texts) => fakeRepository(
  id: documentsId,
  ownerId: sampleUserId,
  name: texts.documents,
  description: texts.documentsDescription,
  url: 'https://git.example.com/alex/${texts.documents}.git',
  hasToken: true,
  tokenHint: '7f3a',
  gitSize: 4820000,
  lfsSize: 31400000,
);

RepositoryDto notes(SampleTexts texts) => fakeRepository(
  id: notesId,
  ownerId: sampleUserId,
  name: texts.notes,
  description: texts.notesDescription,
  local: true,
);

/// What the API answers in a screenshot (see `screenshotGroup`): what every page of a logged-in user may load, and
/// the chats, documents and users of a repository that only some pages load, by their id. Anything else fails with
/// `NOT_FOUND`.
class SampleApi {
  final UserDto me;
  final InstanceDto instance;
  final List<ModelDto> models;
  final List<RepositoryDto> repositories;
  final List<ChatDto> chats;
  final Map<UuidValue, ChatDetailDto> chatDetails;
  final Map<UuidValue, RepositoryDocumentsDto> repositoryDocuments;
  final Map<UuidValue, List<RepositoryUserDto>> repositoryUsers;

  const SampleApi({
    required this.me,
    required this.instance,
    required this.models,
    required this.repositories,
    required this.chats,
    this.chatDetails = const {},
    this.repositoryDocuments = const {},
    this.repositoryUsers = const {},
  });
}

/// The [SampleApi] with the user, the instance, the model, the repositories and the chats, named with [texts], and
/// the [chatDetails], and the [repositoryDocuments] and [repositoryUsers] by the id of their repository.
SampleApi sampleApi(
  SampleTexts texts, {
  List<ChatDetailDto> chatDetails = const [],
  Map<String, List<RepositoryDocumentDto>> repositoryDocuments = const {},
  Map<String, List<RepositoryUserDto>> repositoryUsers = const {},
}) => SampleApi(
  me: sampleUser,
  instance: const InstanceDto(name: 'Acme'),
  models: [
    fakeModel(id: sampleModelId, displayName: ' Mistral 4 119B', providerId: sampleProviderId, providerName: 'OpenRouter', isDefault: true),
  ],
  repositories: [documents(texts), notes(texts)],
  chats: [chat(passportChatId, texts.passportChat, notesId), chat(taxChatId, texts.taxChat, documentsId)],
  chatDetails: {for (final detail in chatDetails) detail.chat.id: detail},
  repositoryDocuments: {
    for (final MapEntry(:key, :value) in repositoryDocuments.entries) UuidValue.fromString(key): RepositoryDocumentsDto(documents: value),
  },
  repositoryUsers: {for (final MapEntry(:key, :value) in repositoryUsers.entries) UuidValue.fromString(key): value},
);

ChatDto chat(String id, String title, String repositoryId) => ChatDto(
  id: UuidValue.fromString(id),
  title: title,
  allRepositories: false,
  repositoryIds: [UuidValue.fromString(repositoryId)],
  modelId: UuidValue.fromString(sampleModelId),
  temporary: false,
  createdAt: DateTime.utc(2026, 10, 21, 9, 12),
  updatedAt: DateTime.utc(2026, 10, 21, 9, 13),
);

/// A question of a chat and its answer, which the model found with [toolCalls] (name and input).
typedef Exchange = ({String question, List<(String, Map<String, dynamic>)> toolCalls, String answer});

/// A chat with its messages, like `GET /api/v1/chats/{id}` returns it: the [exchanges] in the repository
/// [repositoryId]. The ids of the messages and tool calls are [id] with another end.
ChatDetailDto chatDetail({
  required String id,
  required String title,
  required String repositoryId,
  required List<Exchange> exchanges,
}) {
  var n = 0;
  UuidValue nextId() => UuidValue.fromString('${id.substring(0, 30)}${(++n).toString().padLeft(6, '0')}');
  return ChatDetailDto(
    chat: chat(id, title, repositoryId),
    messages: [
      for (final exchange in exchanges) ...[
        _message(id: nextId(), role: MessageRole.user, content: exchange.question),
        _message(
          id: nextId(),
          role: MessageRole.assistant,
          content: exchange.answer,
          toolCalls: [
            for (final (name, input) in exchange.toolCalls)
              ToolCallSummaryDto(
                id: nextId(),
                name: name,
                input: jsonEncode(input),
                repositoryId: UuidValue.fromString(repositoryId),
                commitSha: '0123456789abcdef0123456789abcdef01234567',
                status: ToolCallStatus.completed,
                createdAt: DateTime.utc(2026, 10, 21, 9, 12, 10),
              ),
          ],
        ),
      ],
    ],
  );
}

MessageDto _message({
  required UuidValue id,
  required MessageRole role,
  required String content,
  List<ToolCallSummaryDto> toolCalls = const [],
}) {
  final answer = role == MessageRole.assistant;
  return MessageDto(
    id: id,
    role: role,
    content: content,
    status: MessageStatus.completed,
    modelId: answer ? UuidValue.fromString(sampleModelId) : null,
    toolCalls: toolCalls,
    createdAt: DateTime.utc(2026, 10, 21, 9, 12),
    finishedAt: answer ? DateTime.utc(2026, 10, 21, 9, 12, 42) : null,
    usage: answer ? const UsageDto(inputTokens: 18240, outputTokens: 412, cacheReadTokens: 12800, cacheWriteTokens: 0) : null,
    cost: answer ? const CostDto(amount: '0.0072', currency: 'USD') : null,
  );
}
