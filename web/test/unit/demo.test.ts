import {afterEach, beforeEach, describe, expect, it, vi} from 'vitest';
import {
    type AttachmentDto,
    type ChatDetailDto,
    type ChatPageDto,
    DiffFileKind,
    DiffLineKind,
    ErrorCode,
    type ProposedCommitDto,
    type FileDiffDto,
    ProposedCommitStatus,
    type MessageDto,
    type MessageStreamEvent,
    MessageStatus,
    type ModelDto,
    ToolCallStatus,
} from '~/utils/model';

let demo: typeof import('~/utils/demo');

beforeEach(async () => {
    vi.useFakeTimers();
    // a fresh module per test, so no chats or attachments carry over
    vi.resetModules();
    demo = await import('~/utils/demo');
});

afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
});

/** A request to the demo API, waiting out its latency. */
async function fetchDemo(method: 'GET' | 'POST', route: string, body?: object): Promise<Response> {
    const response = demo.demoFetch(method, route, body, undefined);
    await vi.advanceTimersByTimeAsync(100);
    return await response;
}

/** Like `makeRequest`: the JSON of a successful response. */
async function request<T>(method: 'GET' | 'POST', route: string, body?: object): Promise<T> {
    const response = await fetchDemo(method, route, body);
    expect(response.status).toBe(200);
    const text = await response.text();
    return (text ? JSON.parse(text) : null) as T;
}

async function expectError(response: Response, status: number, code: ErrorCode) {
    expect(response.status).toBe(status);
    expect((await response.json()).code).toBe(code);
}

async function upload(file: File): Promise<AttachmentDto> {
    const attachment = demo.demoUploadAttachment(file);
    await vi.advanceTimersByTimeAsync(300);
    return await attachment;
}

async function createChat(content: string, {repositories = true, attachmentId = null as string | null,
    modelId = null as string | null} = {}): Promise<ChatDetailDto> {
    return await request('POST', 'chats', {
        content,
        attachment_id: attachmentId,
        all_repositories: repositories,
        repository_ids: [],
        model_id: modelId,
    });
}

async function sendMessage(chatId: string, content: string, attachmentId: string | null = null) {
    return await request<[MessageDto, MessageDto]>('POST', `chats/${chatId}/messages`,
        {content, attachment_id: attachmentId});
}

/** The answer once it is finished. */
async function finished(chatId: string, messageId: string): Promise<MessageDto> {
    await vi.runAllTimersAsync();
    const chat = await request<ChatDetailDto>('GET', `chats/${chatId}`);
    return chat.messages.find(m => m.id === messageId)!;
}

describe('demo API', () => {
    it('shows the sample scan in the answer to the first message, streaming it', async () => {
        const chat = await createChat('Where is the invoice?');
        const answer = chat.messages[1]!;
        expect(answer.status).toBe(MessageStatus.GENERATING);

        const events: MessageStreamEvent[] = [];
        demo.demoStreamMessage(chat.id, answer.id, e => events.push(e));
        await vi.runAllTimersAsync();

        expect(events[0]!.type).toBe('snapshot');
        expect(events.filter(e => e.type.startsWith('tool_call_')).map(e => e.type))
            .toEqual(['tool_call_started', 'tool_call_finished']);
        const done = events.at(-1)!;
        expect(done.type).toBe('done');
        const message = done.data as MessageDto;
        expect(message.status).toBe(MessageStatus.COMPLETED);
        expect(message.content).toBe(events.map(e => e.type === 'content_delta' ? e.data.text : '').join(''));
        expect(message.content).toContain('scans/sample_scan.pdf');
        expect(message.tool_calls).toMatchObject([{
            name: 'present_file_to_user',
            input: {path: 'scans/sample_scan.pdf'},
            status: ToolCallStatus.COMPLETED,
        }]);
        expect(message.usage).not.toBeNull();
        expect(message.cost).toBeNull();
    });

    it('serves the presented file', async () => {
        vi.stubGlobal('fetch', vi.fn(async () => new Response('%PDF-1.4')));
        const chat = await createChat('Where is the invoice?');
        const answer = await finished(chat.id, chat.messages[1]!.id);

        const response = await fetchDemo('GET', `chats/${chat.id}/tool-calls/${answer.tool_calls[0]!.id}/file`);
        expect(response.headers.get('Content-Type')).toBe('application/pdf');
        expect(await response.text()).toBe('%PDF-1.4');
    });

    it('greets in chats without repositories', async () => {
        const chat = await createChat('Hi', {repositories: false});
        const answer = await finished(chat.id, chat.messages[1]!.id);

        expect(answer.content).toContain('How can I help you today?');
        expect(answer.tool_calls).toEqual([]);
    });

    it('proposes to store the attachment of the first message, and commits it', async () => {
        const attachment = await upload(new File(['hello\nworld\n'], 'notes.txt', {type: 'text/plain'}));
        const chat = await createChat('', {attachmentId: attachment.id});
        expect(chat.title).toBe('notes.txt');
        const answer = await finished(chat.id, chat.messages[1]!.id);

        expect(answer.content).toContain('`legal/notes.txt`');
        expect(answer.tool_calls).toMatchObject([{
            name: 'save_attachment',
            input: {attachment: 1, path: 'legal/notes.txt'},
            status: ToolCallStatus.COMPLETED,
        }]);
        const changeRoute = `chats/${chat.id}/tool-calls/${answer.tool_calls[0]!.id}`;
        const change = await request<ProposedCommitDto>('GET', `${changeRoute}/proposed-commit`);
        expect(change).toMatchObject({path: 'legal/notes.txt', status: ProposedCommitStatus.PROPOSED});

        const patch = await (await fetchDemo('GET', `${changeRoute}/patch`)).text();
        expect(patch).toContain('2 insertions(+)');
        expect(patch).toContain('+++ b/legal/notes.txt\n@@ -0,0 +1,2 @@\n+hello\n+world\n');
        expect(await request<FileDiffDto>('GET', `${changeRoute}/diff`)).toEqual({
            kind: DiffFileKind.ADDED,
            hunks: [{
                skipped: false,
                lines: [
                    {kind: DiffLineKind.ADDED, parts: [{text: 'hello', changed: false}]},
                    {kind: DiffLineKind.ADDED, parts: [{text: 'world', changed: false}]},
                ],
            }],
            moves: null,
        });
        expect(await (await fetchDemo('GET', `${changeRoute}/proposed-commit/file`)).text()).toBe('hello\nworld\n');

        const committed = await request<ProposedCommitDto>('POST', `${changeRoute}/commit`);
        expect(committed).toMatchObject({
            status: ProposedCommitStatus.COMMITTED,
            pushed_commit: change.proposed_commit,
            pushed_branch: 'main',
        });
        // a committed change stays committed
        expect(await request<ProposedCommitDto>('POST', `${changeRoute}/commit`)).toEqual(committed);
    });

    it('answers every later message with the troll answer', async () => {
        const chat = await createChat('Where is the invoice?');
        await finished(chat.id, chat.messages[1]!.id);

        const [, second] = await sendMessage(chat.id, 'And the receipt?');
        expect(await finished(chat.id, second.id)).toMatchObject({content: demo.TROLL_ANSWER, tool_calls: []});

        const attachment = await upload(new File(['hello'], 'notes.txt', {type: 'text/plain'}));
        const [question, third] = await sendMessage(chat.id, 'Store this', attachment.id);
        expect(question.attachment?.number).toBe(1);
        expect(await finished(chat.id, third.id)).toMatchObject({content: demo.TROLL_ANSWER, tool_calls: []});
    });

    it('rejects a message while an answer is generated', async () => {
        const chat = await createChat('Where is the invoice?');

        await expectError(await fetchDemo('POST', `chats/${chat.id}/messages`, {content: 'Hello?'}),
            409, ErrorCode.GENERATION_IN_PROGRESS);
    });

    it('cancels an answer while its tool runs', async () => {
        const chat = await createChat('Where is the invoice?');
        // past the start of the tool call, before its end
        await vi.advanceTimersByTimeAsync(1_000);
        const answerId = chat.messages[1]!.id;
        await request('POST', `chats/${chat.id}/messages/${answerId}/cancel`);

        expect(await finished(chat.id, answerId)).toMatchObject({
            status: MessageStatus.CANCELLED,
            content: '',
            tool_calls: [{name: 'present_file_to_user', status: ToolCallStatus.FAILED}],
        });
    });

    it('retries the answer to the first message like the first', async () => {
        const chat = await createChat('Where is the invoice?');
        const cancelled = chat.messages[1]!.id;
        await request('POST', `chats/${chat.id}/messages/${cancelled}/cancel`);

        const retried = await request<MessageDto>('POST', `chats/${chat.id}/messages/${cancelled}/retry`);
        const answer = await finished(chat.id, retried.id);
        expect(answer.status).toBe(MessageStatus.COMPLETED);
        expect(answer.content).toContain('scans/sample_scan.pdf');
        const messages = (await request<ChatDetailDto>('GET', `chats/${chat.id}`)).messages;
        expect(messages.map(m => m.id)).toEqual([chat.messages[0]!.id, retried.id]);
    });

    it('prices only the answers of the hosted model', async () => {
        const models = await request<ModelDto[]>('GET', 'models');
        const hosted = models.find(m => !m.is_default)!;
        const chat = await createChat('Where is the invoice?', {modelId: hosted.id});
        const answer = await finished(chat.id, chat.messages[1]!.id);

        expect(answer.model_id).toBe(hosted.id);
        expect(answer.cost?.currency).toBe('USD');
        expect(Number(answer.cost?.amount)).toBeGreaterThan(0);
    });

    it('does not list temporary chats', async () => {
        const listed = await createChat('Where is the invoice?');
        const temporary = await request<ChatDetailDto>('POST', 'chats',
            {content: 'Hi', all_repositories: true, repository_ids: [], temporary: true});
        expect(listed.temporary).toBe(false);
        expect(temporary.temporary).toBe(true);

        const page = await request<ChatPageDto>('GET', 'chats');
        expect(page.items.map(c => c.id)).toEqual([listed.id]);
        expect((await request<ChatDetailDto>('GET', `chats/${temporary.id}`)).temporary).toBe(true);
    });

    it('forbids what the demo does not serve', async () => {
        await expectError(await fetchDemo('GET', 'users'), 403, ErrorCode.FORBIDDEN);
    });
});
