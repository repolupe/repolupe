// The demo mode (`VITE_DEMO=true` at build time, e.g. `VITE_DEMO=true npm run generate`):
// an in-memory stand-in for the API, so the frontend runs without one.

import samplePdfUrl from '~/assets/demo/sample_scan.pdf?url';
import {
    type AttachmentDto,
    type ChatDetailDto,
    DiffFileKind,
    DiffLineKind,
    ErrorCode,
    type ProposedCommitDto,
    ProposedCommitStatus,
    type FileDiffDto,
    type MessageDto,
    MessageRole,
    MessageStatus,
    type MessageStreamEvent,
    type ModelDto,
    type RepositoryDto,
    RepositorySyncStatus,
    ToolCallStatus,
    type ToolCallSummaryDto,
    type UserDto,
    UserRole,
} from "~/utils/model";

export const DEMO: boolean = import.meta.env.VITE_DEMO === 'true';

const DEMO_FILE_PATH = 'scans/sample_scan.pdf';

const ANSWER = `I found the file \`${DEMO_FILE_PATH}\` in the repository **Documents**. It is a scanned invoice:\n\n`
    + `- **Invoice number:** 7731\n`
    + `- **Total due:** 125 USD\n\n`
    + `I opened it next to the chat for you to read.`;

/** Where an answer to a message with an attachment proposes to store it. */
const ATTACHMENT_DIR = 'legal';

const ATTACHMENT_ANSWER = (fileName: string, path: string) =>
    `\`${fileName}\` looks like a legal document (like any other file), so I propose to store it in the folder \`${ATTACHMENT_DIR}/\` `
    + `of the repository **Documents**, as \`${path}\`.\n\n`
    + `Nothing is committed yet: review the change next to the chat and apply it to commit it.`;

/** The answer in chats without repositories, where there is no file to show. */
const GREETING = `Hello! How can I help you today? Whether you have a question, need help with a task, `
    + `or just want to chat, I'm here to help.`;

/** The answer to every message after the first of a chat. */
export const TROLL_ANSWER = '67';

const CREATED_AT = new Date().toISOString();

const USER: UserDto = {
    id: '0199f000-0000-7000-8000-000000000001',
    role: UserRole.USER,
    user_name: 'demo',
    email: null,
    can_login: true,
    can_manage_repositories: true,
    can_change_identity: true,
    must_change_password: false,
    default_model_id: null,
    locale: null,
    auto_commit: false,
    full_name: null,
    first_name: 'Demo',
    about: null,
    created_at: CREATED_AT,
};

const HOSTED_MODEL_ID = '0199f000-0000-7000-8000-000000000005';

const MODELS: ModelDto[] = [{
    id: '0199f000-0000-7000-8000-000000000002',
    display_name: 'Repolupe Super Small 1.0 69B',
    provider_id: '0199f000-0000-7000-8000-000000000003',
    provider_name: 'Demo',
    is_default: true,
}, {
    id: HOSTED_MODEL_ID,
    display_name: 'Repolupe Giga Large 1.0 420B',
    provider_id: '0199f000-0000-7000-8000-000000000003',
    provider_name: 'Demo',
    is_default: false,
}];

/**
 * Of the hosted demo model, in USD per million tokens, so an answer costs a fraction of a cent. The local one has no
 * prices, so its answers show no cost.
 */
const PRICES = {input: 1, output: 5, cache_read: 0.1, cache_write: 1.25};

const HEAD_SHA = '3f786850e387550fdab836ed7e6dc881de23001b';

const REPOSITORIES: RepositoryDto[] = [{
    id: '0199f000-0000-7000-8000-000000000004',
    owner_id: USER.id,
    name: 'Documents',
    description: null,
    remote: {
        url: 'https://git.example.com/demo/documents.git',
        branch: 'main',
        poll_interval_seconds: 3600,
        token: null,
    },
    allow_commits: true,
    can_commit: true,
    sync_status: RepositorySyncStatus.READY,
    sync_started_at: CREATED_AT,
    head_commit_sha: HEAD_SHA,
    last_synced_at: CREATED_AT,
    git_size: 24_576,
    lfs_size: 0,
    last_error: null,
    next_sync_at: CREATED_AT,
    created_at: CREATED_AT,
    updated_at: CREATED_AT,
}];

/** A generating answer, with the streams that follow it. */
interface Generation {
    cancelled: boolean;
    listeners: Set<(event: MessageStreamEvent) => void>;
}

/** What the API would store, kept in memory until a reload. */
const state = {
    chats: [] as ChatDetailDto[],
    attachments: new Map<string, { dto: AttachmentDto, file: File, url: string | null }>(),
    toolCallOutputs: new Map<string, string>(),
    /** The changes proposed by `save_attachment` calls, by their ids. */
    proposedCommits: new Map<string, { dto: ProposedCommitDto, attachment: AttachmentDto, message: string }>(),
    /** The live generations, by the ids of their messages. */
    generations: new Map<string, Generation>(),
};

class DemoError extends Error {
    constructor(readonly status: number, readonly code: ErrorCode, message: string) {
        super(message);
    }
}

const notFound = () => new DemoError(404, ErrorCode.NOT_FOUND, 'Not found.');

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

const copy = <T>(value: T): T => structuredClone(value);

/** A random commit sha. */
const randomSha = () => Array.from(crypto.getRandomValues(new Uint8Array(20)), b => b.toString(16).padStart(2, '0')).join('');

function findChat(id: string): ChatDetailDto {
    const chat = state.chats.find(c => c.id === id);
    if (!chat) {
        throw notFound();
    }
    return chat;
}

function findMessage(chatId: string, messageId: string): MessageDto {
    const message = findChat(chatId).messages.find(m => m.id === messageId);
    if (!message) {
        throw notFound();
    }
    return message;
}

function findToolCall(chatId: string, toolCallId: string): ToolCallSummaryDto {
    for (const message of findChat(chatId).messages) {
        const toolCall = message.tool_calls.find(t => t.id === toolCallId);
        if (toolCall) {
            return toolCall;
        }
    }
    throw notFound();
}

function chatSummary({messages: _, ...chat}: ChatDetailDto) {
    return copy(chat);
}

function userMessage(chat: ChatDetailDto, content: string, attachmentId: string | null): MessageDto {
    let attachment: AttachmentDto | null = null;
    if (attachmentId) {
        const stored = state.attachments.get(attachmentId);
        if (!stored || stored.dto.number !== null) {
            throw new DemoError(400, ErrorCode.UNKNOWN_ATTACHMENT, 'Unknown attachment.');
        }
        stored.dto.number = chat.messages.filter(m => m.attachment).length + 1;
        attachment = copy(stored.dto);
    }
    if (!content.trim() && !attachment) {
        throw new DemoError(400, ErrorCode.VALIDATION_ERROR, 'The message is empty.');
    }
    return newMessage(MessageRole.USER, content.trim(), attachment);
}

function newMessage(role: MessageRole, content: string, attachment: AttachmentDto | null = null,
                    modelId: string | null = null): MessageDto {
    return {
        id: crypto.randomUUID(),
        role,
        content,
        status: role === MessageRole.USER ? MessageStatus.COMPLETED : MessageStatus.GENERATING,
        error: null,
        model_id: modelId,
        tool_calls: [],
        created_at: new Date().toISOString(),
        finished_at: null,
        usage: null,
        cost: null,
        attachment,
    };
}

function findProposedCommit(chatId: string, toolCallId: string) {
    const change = state.proposedCommits.get(findToolCall(chatId, toolCallId).id);
    if (!change) {
        throw notFound();
    }
    return change;
}

/**
 * Adds an answer to the chat and generates it: to a later question than the first, streams {@link TROLL_ANSWER}; with
 * repositories, proposes to store the attachment of the question and streams {@link ATTACHMENT_ANSWER}, or without one
 * shows the sample scan and streams {@link ANSWER}; otherwise streams {@link GREETING}.
 */
function startAnswer(chat: ChatDetailDto): MessageDto {
    // like `llm_config.rs`: the chat's model, else the default (the demo user has none of its own)
    const modelId = MODELS.find(m => m.id === chat.model_id)?.id ?? MODELS.find(m => m.is_default)!.id;
    // the question is the last message, also when an answer is retried
    const attachment = chat.messages.at(-1)?.attachment ?? null;
    const firstQuestion = chat.messages.filter(m => m.role === MessageRole.USER).length === 1;
    const message = newMessage(MessageRole.ASSISTANT, '', null, modelId);
    chat.messages.push(message);
    chat.updated_at = message.created_at;
    const generation: Generation = {cancelled: false, listeners: new Set()};
    state.generations.set(message.id, generation);
    const emit = (event: MessageStreamEvent) => generation.listeners.forEach(l => l(copy(event)));
    const hasRepositories = chat.all_repositories || chat.repository_ids.length > 0;

    (async () => {
        await sleep(600);
        if (generation.cancelled) {
            return;
        }
        let text = GREETING;
        if (!firstQuestion) {
            text = TROLL_ANSWER;
        } else if (hasRepositories && attachment) {
            const path = `${ATTACHMENT_DIR}/${attachment.file_name}`;
            if (!await saveAttachment(message, generation, emit, attachment, path)) {
                return;
            }
            text = ATTACHMENT_ANSWER(attachment.file_name, path);
        } else if (hasRepositories) {
            if (!await presentSampleScan(message, generation, emit)) {
                return;
            }
            text = ANSWER;
        }
        for (const word of text.match(/\S+\s*/g) ?? []) {
            await sleep(40);
            if (generation.cancelled) {
                return;
            }
            message.content += word;
            emit({type: 'content_delta', data: {text: word}});
        }
        finishAnswer(message, MessageStatus.COMPLETED);
    })();

    return message;
}

/** Calls `present_file_to_user` with the sample scan, false if the answer was cancelled meanwhile. */
async function presentSampleScan(message: MessageDto, generation: Generation,
                                 emit: (event: MessageStreamEvent) => void): Promise<boolean> {
    const toolCall = await callTool(message, generation, emit, 'present_file_to_user',
        {repository: REPOSITORIES[0]!.name, path: DEMO_FILE_PATH},
        `\`${DEMO_FILE_PATH}\` is shown to the user as a button below your answer that opens the file.`);
    return !!toolCall;
}

/** Calls `save_attachment` to store the attachment at `path`, false if the answer was cancelled meanwhile. */
async function saveAttachment(message: MessageDto, generation: Generation,
                              emit: (event: MessageStreamEvent) => void, attachment: AttachmentDto,
                              path: string): Promise<boolean> {
    const commitMessage = `Add ${attachment.file_name} to the legal documents`;
    const toolCall = await callTool(message, generation, emit, 'save_attachment',
        {repository: REPOSITORIES[0]!.name, attachment: attachment.number, path, message: commitMessage},
        `Proposed a commit that creates \`${path}\` with attachment ${attachment.number} (\`${attachment.file_name}\`). `
        + `It is not committed yet: the user sees it below your answer and decides whether to commit it. To store it `
        + `elsewhere, call save_attachment for attachment ${attachment.number} again.`);
    if (!toolCall) {
        return false;
    }
    state.proposedCommits.set(toolCall.id, {
        dto: {
            path,
            moves: null,
            proposed_commit: randomSha(),
            status: ProposedCommitStatus.PROPOSED,
            pushed_commit: null,
            pushed_branch: null,
            error: null,
            committed_at: null,
            can_commit: true,
        },
        attachment,
        message: commitMessage,
    });
    return true;
}

/** Runs a tool call of the answer, `null` if the answer was cancelled meanwhile. */
async function callTool(message: MessageDto, generation: Generation, emit: (event: MessageStreamEvent) => void,
                        name: string, input: Record<string, unknown>,
                        output: string): Promise<ToolCallSummaryDto | null> {
    const toolCall: ToolCallSummaryDto = {
        id: crypto.randomUUID(),
        name,
        input,
        repository_id: REPOSITORIES[0]!.id,
        commit_sha: HEAD_SHA,
        status: ToolCallStatus.RUNNING,
        created_at: new Date().toISOString(),
    };
    message.tool_calls.push(toolCall);
    emit({type: 'tool_call_started', data: toolCall});

    await sleep(800);
    if (generation.cancelled) {
        return null;
    }
    toolCall.status = ToolCallStatus.COMPLETED;
    state.toolCallOutputs.set(toolCall.id, output);
    emit({type: 'tool_call_finished', data: {id: toolCall.id, status: toolCall.status}});
    return toolCall;
}

/** Like `generation::finish`: only the first call has an effect. */
function finishAnswer(message: MessageDto, status: MessageStatus) {
    const generation = state.generations.get(message.id);
    if (!generation) {
        return;
    }
    state.generations.delete(message.id);
    generation.cancelled = true;
    for (const toolCall of message.tool_calls) {
        if (toolCall.status === ToolCallStatus.RUNNING) {
            toolCall.status = ToolCallStatus.FAILED;
        }
    }
    message.status = status;
    message.finished_at = new Date().toISOString();
    const usage = {
        input_tokens: 1_200,
        output_tokens: message.content.length / 4 | 0,
        cache_read_tokens: 3_400,
        cache_write_tokens: 0,
    };
    message.usage = usage;
    if (message.model_id === HOSTED_MODEL_ID) {
        const amount = (usage.input_tokens * PRICES.input + usage.output_tokens * PRICES.output
            + usage.cache_read_tokens * PRICES.cache_read + usage.cache_write_tokens * PRICES.cache_write) / 1_000_000;
        message.cost = {amount: amount.toFixed(8).replace(/\.?0+$/, ''), currency: 'USD'};
    }
    generation.listeners.forEach(l => l({type: 'done', data: copy(message)}));
}

function createChat(body: Record<string, any>): ChatDetailDto {
    const now = new Date().toISOString();
    const chat: ChatDetailDto = {
        id: crypto.randomUUID(),
        title: '',
        all_repositories: !!body.all_repositories,
        repository_ids: body.all_repositories ? [] : body.repository_ids ?? [],
        model_id: body.model_id ?? null,
        temporary: !!body.temporary,
        created_at: now,
        updated_at: now,
        messages: [],
    };
    const message = userMessage(chat, body.content ?? '', body.attachment_id ?? null);
    const firstLine = message.content.split('\n')[0]!.trim();
    chat.title = body.title?.trim() || (firstLine.length > 60 ? firstLine.slice(0, 60) + '…' : firstLine)
        || message.attachment?.file_name || 'New chat';
    chat.messages.push(message);
    state.chats.push(chat);
    startAnswer(chat);
    return copy(chat);
}

function sendMessage(chatId: string, body: Record<string, any>): [MessageDto, MessageDto] {
    const chat = findChat(chatId);
    if (chat.messages.some(m => m.status === MessageStatus.GENERATING)) {
        throw new DemoError(409, ErrorCode.GENERATION_IN_PROGRESS, 'An answer is still being generated.');
    }
    const message = userMessage(chat, body.content ?? '', body.attachment_id ?? null);
    chat.messages.push(message);
    return [copy(message), copy(startAnswer(chat))];
}

function retryMessage(chatId: string, messageId: string): MessageDto {
    const chat = findChat(chatId);
    const last = chat.messages.at(-1);
    if (!last || last.id !== messageId || last.role !== MessageRole.ASSISTANT
        || (last.status !== MessageStatus.FAILED && last.status !== MessageStatus.CANCELLED)) {
        throw new DemoError(409, ErrorCode.NOT_RETRYABLE, 'Only a failed or cancelled last answer can be retried.');
    }
    chat.messages.pop();
    return copy(startAnswer(chat));
}

function getChats(params: Record<string, unknown>) {
    const offset = Number(params.cursor ?? 0);
    const limit = Number(params.limit ?? 10);
    // like the API, temporary chats are not listed
    const sorted = state.chats.filter(c => !c.temporary).sort((a, b) => b.updated_at.localeCompare(a.updated_at));
    const next = offset + limit;
    return {
        items: sorted.slice(offset, next).map(chatSummary),
        next_cursor: next < sorted.length ? String(next) : null,
    };
}

async function presentedFile(chatId: string, toolCallId: string): Promise<Response> {
    const toolCall = findToolCall(chatId, toolCallId);
    if (toolCall.name !== 'present_file_to_user' || toolCall.status !== ToolCallStatus.COMPLETED) {
        throw notFound();
    }
    // bundled with the frontend, no API involved
    const blob = await (await fetch(samplePdfUrl)).blob();
    return new Response(blob, {headers: {'Content-Type': 'application/pdf'}});
}

/**
 * The commit a `save_attachment` call proposed, like `git format-patch`: text files as a diff, other files like git
 * shows binary files (without one).
 */
async function proposedCommitPatch(chatId: string, toolCallId: string): Promise<Response> {
    const {dto, attachment, message} = findProposedCommit(chatId, toolCallId);
    const path = dto.path!;
    const bytes = new Uint8Array(await state.attachments.get(attachment.id)!.file.arrayBuffer());
    // like git: a NUL byte in the first 8000 bytes makes it binary
    const binary = bytes.subarray(0, 8000).includes(0);
    let stat = `Bin 0 -> ${bytes.length} bytes`;
    let summary = ' 1 file changed';
    let diff = `Binary files /dev/null and b/${path} differ\n`;
    if (!binary) {
        const text = new TextDecoder().decode(bytes);
        const lines = text.split('\n');
        if (text.endsWith('\n')) {
            lines.pop();
        }
        stat = `${lines.length} ${'+'.repeat(Math.min(lines.length, 50))}`;
        summary += `, ${lines.length} insertion${lines.length === 1 ? '' : 's'}(+)`;
        diff = lines.length === 0 ? '' : `--- /dev/null\n+++ b/${path}\n@@ -0,0 +1,${lines.length} @@\n`
            + lines.map(l => `+${l}\n`).join('')
            + (text.endsWith('\n') ? '' : '\\ No newline at end of file\n');
    }
    const date = new Date(findToolCall(chatId, toolCallId).created_at).toUTCString().replace('GMT', '+0000');
    const patch = `From ${dto.proposed_commit} Mon Sep 17 00:00:00 2001\n`
        + `From: Repolupe+demo <noreply@repolupe.com>\n`
        + `Date: ${date}\n`
        + `Subject: [PATCH] ${message}\n\n`
        + `---\n`
        + ` ${path} | ${stat}\n`
        + `${summary}\n`
        + ` create mode 100644 ${path}\n\n`
        + `diff --git a/${path} b/${path}\n`
        + `new file mode 100644\n`
        + `index 0000000..${dto.proposed_commit.slice(-7)}\n`
        + diff
        + `--\n2.47.0\n`;
    return new Response(patch, {headers: {'Content-Type': 'text/x-patch'}});
}

/**
 * The commit a `save_attachment` call proposed as the API shows it: a new file, its lines all added, or no lines if
 * it is binary (with a NUL byte in the first 8000 bytes, or not UTF-8, like the API decides it).
 */
async function proposedCommitDiff(chatId: string, toolCallId: string): Promise<FileDiffDto> {
    const {attachment} = findProposedCommit(chatId, toolCallId);
    const bytes = new Uint8Array(await state.attachments.get(attachment.id)!.file.arrayBuffer());
    let text: string | null = null;
    if (!bytes.subarray(0, 8000).includes(0)) {
        try {
            text = new TextDecoder('utf-8', {fatal: true}).decode(bytes);
        } catch {
            // binary
        }
    }
    const lines = text?.split('\n') ?? [];
    if (text?.endsWith('\n')) {
        lines.pop();
    }
    return {
        kind: DiffFileKind.ADDED,
        hunks: lines.length === 0 ? [] : [{
            skipped: false,
            lines: lines.map(line => ({
                kind: DiffLineKind.ADDED,
                parts: [{text: line.endsWith('\r') ? line.slice(0, -1) : line, changed: false}],
            })),
        }],
        moves: null,
    };
}

/** The file a `save_attachment` call proposed: the attachment. */
function proposedCommitFile(chatId: string, toolCallId: string): Response {
    const {attachment} = findProposedCommit(chatId, toolCallId);
    return new Response(state.attachments.get(attachment.id)!.file,
        {headers: {'Content-Type': attachment.content_type}});
}

/** Commits the change of a `save_attachment` call, which always succeeds; a committed change stays committed. */
function commitProposedCommit(chatId: string, toolCallId: string): ProposedCommitDto {
    const {dto} = findProposedCommit(chatId, toolCallId);
    if (dto.status !== ProposedCommitStatus.COMMITTED) {
        dto.status = ProposedCommitStatus.COMMITTED;
        dto.pushed_commit = dto.proposed_commit;
        dto.pushed_branch = REPOSITORIES[0]!.remote!.branch;
        dto.committed_at = new Date().toISOString();
    }
    return copy(dto);
}

/** Answers a request like the API, without a network request to it. */
async function route(method: 'GET' | 'POST', route: string, body: Record<string, any>,
                     params: Record<string, unknown>): Promise<unknown> {
    const parts = route.split('/');
    const match = (pattern: string) => {
        const expected = pattern.split('/');
        return expected.length === parts.length && expected.every((p, i) => p === '*' || p === parts[i]);
    };

    if (method === 'GET') {
        if (route === 'instance') return {name: 'Repolupe'};
        // always logged in: the logout is in the settings, which the demo doesn't have
        if (route === 'me') return USER;
        if (route === 'models') return MODELS;
        if (route === 'repositories') return REPOSITORIES;
        if (match('repositories/*')) {
            const repository = REPOSITORIES.find(r => r.id === parts[1]);
            if (!repository) {
                throw notFound();
            }
            return repository;
        }
        if (route === 'chats') return getChats(params);
        if (match('chats/*')) return copy(findChat(parts[1]!));
        if (match('chats/*/tool-calls/*')) {
            const toolCall = findToolCall(parts[1]!, parts[3]!);
            return {...copy(toolCall), output: state.toolCallOutputs.get(toolCall.id) ?? null};
        }
        if (match('chats/*/tool-calls/*/file')) return await presentedFile(parts[1]!, parts[3]!);
        if (match('chats/*/tool-calls/*/patch')) return await proposedCommitPatch(parts[1]!, parts[3]!);
        if (match('chats/*/tool-calls/*/diff')) return await proposedCommitDiff(parts[1]!, parts[3]!);
        if (match('chats/*/tool-calls/*/proposed-commit')) return copy(findProposedCommit(parts[1]!, parts[3]!).dto);
        if (match('chats/*/tool-calls/*/proposed-commit/file')) return proposedCommitFile(parts[1]!, parts[3]!);
    } else {
        if (route === 'chats') return createChat(body);
        if (match('chats/*/update')) {
            const chat = findChat(parts[1]!);
            chat.title = String(body.title ?? chat.title).trim() || chat.title;
            chat.model_id = body.model_id ?? null;
            chat.updated_at = new Date().toISOString();
            return chatSummary(chat);
        }
        if (match('chats/*/delete')) {
            const chat = findChat(parts[1]!);
            chat.messages.forEach(m => finishAnswer(m, MessageStatus.CANCELLED));
            state.chats.splice(state.chats.indexOf(chat), 1);
            return null;
        }
        if (match('chats/*/messages')) return sendMessage(parts[1]!, body);
        if (match('chats/*/messages/*/cancel')) {
            finishAnswer(findMessage(parts[1]!, parts[3]!), MessageStatus.CANCELLED);
            return null;
        }
        if (match('chats/*/messages/*/retry')) return retryMessage(parts[1]!, parts[3]!);
        if (match('chats/*/tool-calls/*/commit')) return commitProposedCommit(parts[1]!, parts[3]!);
    }
    throw new DemoError(403, ErrorCode.FORBIDDEN, 'This is not available in the demo.');
}

/** The response the API would send, `fetch` in demo mode. */
export async function demoFetch(method: 'GET' | 'POST', path: string, body: object | undefined,
                                params: Record<string, unknown> | undefined): Promise<Response> {
    // a little latency, so loading states show like they do with the API
    await sleep(100);
    try {
        // through JSON like a request to the API, which also turns reactive proxies (e.g. a page's `repository_ids`)
        // into plain values that `structuredClone` can copy
        const json = JSON.parse(JSON.stringify(body ?? {})) as Record<string, any>;
        const result = await route(method, path, json, params ?? {});
        if (result instanceof Response) {
            return result;
        }
        return new Response(result === null ? '' : JSON.stringify(result), {
            headers: {'Content-Type': 'application/json'},
        });
    } catch (e) {
        if (!(e instanceof DemoError)) {
            throw e;
        }
        return new Response(JSON.stringify({code: e.code, message: e.message}), {
            status: e.status,
            headers: {'Content-Type': 'application/json'},
        });
    }
}

export async function demoUploadAttachment(file: File): Promise<AttachmentDto> {
    await sleep(300);
    const dto: AttachmentDto = {
        id: crypto.randomUUID(),
        number: null,
        file_name: file.name,
        content_type: file.type || 'application/octet-stream',
        size: file.size,
        created_at: new Date().toISOString(),
    };
    state.attachments.set(dto.id, {dto, file, url: null});
    return copy(dto);
}

/** An object URL of the uploaded file, empty if it is not known (e.g. after a reload). */
export function demoAttachmentUrl(id: string): string {
    const stored = state.attachments.get(id);
    if (!stored) {
        return '';
    }
    stored.url ??= URL.createObjectURL(stored.file);
    return stored.url;
}

/** Like `streamMessage`, delivering the events of the generation asynchronously like an `EventSource`. */
export function demoStreamMessage(
    chatId: string,
    messageId: string,
    onEvent: (event: MessageStreamEvent) => void,
    onError?: () => void,
): () => void {
    let closed = false;
    const listener = (event: MessageStreamEvent) => {
        if (!closed) {
            onEvent(event);
        }
    };
    setTimeout(() => {
        if (closed) {
            return;
        }
        let message: MessageDto;
        try {
            message = findMessage(chatId, messageId);
        } catch {
            onError?.();
            return;
        }
        onEvent({type: 'snapshot', data: copy(message)});
        const generation = state.generations.get(messageId);
        if (generation) {
            generation.listeners.add(listener);
        } else {
            onEvent({type: 'done', data: copy(message)});
        }
    }, 0);
    return () => {
        closed = true;
        state.generations.get(messageId)?.listeners.delete(listener);
    };
}
