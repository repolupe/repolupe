import {
    ErrorCode,
    type AttachmentDto,
    type ChatDetailDto,
    type InstanceDto,
    type ChatDto,
    type ChatPageDto,
    type ConfigEntryDto,
    type DocumentFilter,
    type ExtractionDocumentPageDto,
    type ExtractionOverviewDto,
    type ProposedCommitDto,
    type FileDiffDto,
    type LlmApiFormat,
    type LlmModelDto,
    type LlmProviderDto,
    type RemoteModelDto,
    type MessageDto,
    type MessageStreamEvent,
    type ModelDto,
    type RepositoryDocumentsDto,
    type RepositoryDto,
    type RepositoryUserDto,
    type ToolCallDto,
    type UserDto,
} from "~/utils/model";
import {t} from "~/utils/i18n";
import {DEMO, demoAttachmentUrl, demoFetch, demoStreamMessage, demoUploadAttachment} from "~/utils/demo";

// Same origin: in dev, nuxt.config.ts proxies /api/v1 to the API. Browsers authenticate with the
// HttpOnly `session` cookie set by the login, so no token is kept here.
const API_URL = "/api/v1";

let handle401: (() => void) | null = null;
let handlePasswordChangeRequired: (() => void) | null = null;

/** Thrown for every response with status >= 400. Show it with {@link errorMessage}. */
export class ApiError extends Error {
    constructor(
        public readonly status: number,
        /** `null` if the response is not from the API, e.g. the error page of a proxy. */
        public readonly code: ErrorCode | null,
        /** The API's text in English, only shown for codes this version does not know. */
        message: string,
    ) {
        super(message);
    }
}

/** Thrown if a request does not reach the server, e.g. while offline. */
export class UnreachableError extends Error {
    constructor(cause: unknown) {
        super('The server is unreachable', {cause});
    }
}

/** The texts of the error codes, in the language of the UI instead of the API's English. */
const ERROR_TEXTS: Record<ErrorCode, string> = {
    [ErrorCode.INTERNAL_ERROR]: 'errors.internalError',
    [ErrorCode.VALIDATION_ERROR]: 'errors.validationError',
    [ErrorCode.UNSUPPORTED_MEDIA_TYPE]: 'errors.unsupportedMediaType',
    [ErrorCode.UNAUTHORIZED]: 'errors.unauthorized',
    [ErrorCode.FORBIDDEN]: 'errors.forbidden',
    [ErrorCode.NOT_FOUND]: 'errors.notFound',
    [ErrorCode.CONFLICT]: 'errors.conflict',
    [ErrorCode.RATE_LIMITED]: 'errors.rateLimited',
    [ErrorCode.USER_NAME_TAKEN]: 'errors.userNameTaken',
    [ErrorCode.EMAIL_TAKEN]: 'errors.emailTaken',
    [ErrorCode.NAME_TAKEN]: 'errors.nameTaken',
    [ErrorCode.REPO_NOT_FOUND]: 'errors.repoNotFound',
    [ErrorCode.BRANCH_NOT_FOUND]: 'errors.branchNotFound',
    [ErrorCode.AUTH_FAILED]: 'errors.authFailed',
    [ErrorCode.TOKEN_REQUIRED]: 'errors.tokenRequired',
    [ErrorCode.REMOTE_UNREACHABLE]: 'errors.remoteUnreachable',
    [ErrorCode.UNKNOWN_REPOSITORY]: 'errors.unknownRepository',
    [ErrorCode.UNKNOWN_USER]: 'errors.unknownUser',
    [ErrorCode.GENERATION_IN_PROGRESS]: 'errors.generationInProgress',
    [ErrorCode.NOT_RETRYABLE]: 'errors.notRetryable',
    [ErrorCode.WRONG_PASSWORD]: 'errors.wrongPassword',
    [ErrorCode.SAME_PASSWORD]: 'errors.samePassword',
    [ErrorCode.PASSWORD_CHANGE_REQUIRED]: 'errors.passwordChangeRequired',
    [ErrorCode.UNKNOWN_MODEL]: 'errors.unknownModel',
    [ErrorCode.NO_MODEL_CONFIGURED]: 'errors.noModelConfigured',
    [ErrorCode.UNAVAILABLE]: 'errors.unavailable',
    [ErrorCode.FILE_UNAVAILABLE]: 'errors.fileUnavailable',
    [ErrorCode.UNKNOWN_ATTACHMENT]: 'errors.unknownAttachment',
};

/** The text to show for an error thrown by one of the functions below. */
export function errorMessage(e: unknown): string {
    if (e instanceof UnreachableError) {
        return t('errors.unreachable');
    }
    if (e instanceof ApiError) {
        if (e.code === null) {
            return t('errors.invalidResponse', {status: e.status});
        }
        // undefined for a code of a newer server
        const key = ERROR_TEXTS[e.code] as string | undefined;
        return key ? t(key) : e.message;
    }
    return t('common.error');
}

interface RequestParameter {
    method: 'GET' | 'POST';
    route: string;
    body?: object;
    params?: { [key: string]: string | number | null | undefined };
    /** For requests where 401 does not mean the session expired, like the login. */
    no401Callback?: boolean;
}

async function makeRequest<T>(parameter: RequestParameter): Promise<T> {
    const response = await fetchResponse(parameter);
    const text = await response.text();
    return (text ? JSON.parse(text) : null) as T;
}

/** For responses that are not JSON. Throws {@link ApiError} like {@link makeRequest}. */
async function fetchResponse({method, route, body, params, no401Callback}: RequestParameter): Promise<Response> {
    if (DEMO) {
        const response = await demoFetch(method, route, body, params);
        await throwIfFailed(response, no401Callback ?? false);
        return response;
    }

    const url = new URL(API_URL + '/' + route, document.location.href);

    if (params) {
        for (const [key, value] of Object.entries(params)) {
            if (value !== null && value !== undefined) {
                url.searchParams.set(key, String(value));
            }
        }
    }

    // Every authenticated POST must be JSON (the CSRF protection of the cookie auth), even without a body.
    const response = await send(url, {
        method,
        body: method === 'POST' ? JSON.stringify(body ?? {}) : undefined,
        headers: method === 'POST' ? {"Content-Type": "application/json"} : {},
    });
    await throwIfFailed(response, no401Callback ?? false);
    return response;
}

/** `fetch`, throwing {@link UnreachableError} if the request does not reach the server. */
async function send(url: URL, init: RequestInit): Promise<Response> {
    try {
        return await fetch(url.toString(), init);
    } catch (e) {
        throw new UnreachableError(e);
    }
}

/** Throws {@link ApiError} for every status >= 400. */
async function throwIfFailed(response: Response, no401Callback: boolean): Promise<void> {
    if (response.status >= 400) {
        if (!no401Callback && response.status === 401 && handle401) {
            handle401();
        }
        let code: ErrorCode | null = null;
        let message = '';
        try {
            const json = await response.json();
            code = json.code ?? null;
            message = json.message ?? '';
        } catch {
            // not JSON, e.g. a proxy error page
        }
        if (code === ErrorCode.PASSWORD_CHANGE_REQUIRED && handlePasswordChangeRequired) {
            handlePasswordChangeRequired();
        }
        throw new ApiError(response.status, code, message);
    }
}

/**
 * `h401` is called whenever a request fails because the session is gone, `hPasswordChange` when it fails because an
 * admin requires the user to change their password first.
 */
export function initAPI(h401: () => void, hPasswordChange: () => void) {
    handle401 = h401;
    handlePasswordChangeRequired = hPasswordChange;
}

// --- Instance ---

export async function getInstance(): Promise<InstanceDto> {
    return await makeRequest({route: 'instance', method: 'GET'});
}

// --- Auth & current user ---

export interface LoginPayload {
    user_name_or_email: string;
    password: string;
}

export async function login(payload: LoginPayload): Promise<UserDto> {
    const response = await makeRequest<{ token: string, user: UserDto }>({
        route: 'login',
        method: 'POST',
        body: payload,
        no401Callback: true,
    });
    return response.user;
}

export async function logout(): Promise<void> {
    await makeRequest({route: 'logout', method: 'POST', no401Callback: true});
}

/** Restores the session from the cookie, throws an {@link ApiError} with status 401 if there is none. */
export async function getMe(): Promise<UserDto> {
    return await makeRequest({route: 'me', method: 'GET', no401Callback: true});
}

export interface ChangePasswordPayload {
    current_password: string;
    new_password: string;
}

/** Signs out every other session and ends a required change. Fails with `WRONG_PASSWORD` or `SAME_PASSWORD`. */
export async function changePassword(payload: ChangePasswordPayload): Promise<void> {
    await makeRequest({route: 'change-password', method: 'POST', body: payload});
}

export interface UpdateIdentityPayload {
    user_name: string;
    /** `null` removes it. */
    email: string | null;
}

/**
 * Sets the own user name and email, the sessions stay valid. Fails with `USER_NAME_TAKEN` or `EMAIL_TAKEN`, and with
 * `FORBIDDEN` without `can_change_identity`.
 */
export async function updateMyIdentity(payload: UpdateIdentityPayload): Promise<UserDto> {
    return await makeRequest({route: 'me/identity', method: 'POST', body: payload});
}

/** `null` uses the default model. */
export async function setMyDefaultModel(modelId: string | null): Promise<void> {
    await makeRequest({route: 'me/default-model', method: 'POST', body: {model_id: modelId}});
}

/** Whether the changes the model proposes are committed once its answer is complete. */
export async function setMyAutoCommit(autoCommit: boolean): Promise<void> {
    await makeRequest({route: 'me/auto-commit', method: 'POST', body: {auto_commit: autoCommit}});
}

/** BCP 47 tag such as `de-DE`, `null` lets the client decide. */
export async function setMyLocale(locale: string | null): Promise<void> {
    await makeRequest({route: 'me/locale', method: 'POST', body: {locale}});
}

export interface UpdateProfilePayload {
    full_name: string | null;
    first_name: string | null;
    about: string | null;
}

/** Replaces all fields, `null` or empty clears one. */
export async function updateMyProfile(payload: UpdateProfilePayload): Promise<void> {
    await makeRequest({route: 'me/profile', method: 'POST', body: payload});
}

/** The models users can choose from. */
export async function getModels(): Promise<ModelDto[]> {
    return await makeRequest({route: 'models', method: 'GET'});
}

// --- Repositories ---

export async function getRepositories(): Promise<RepositoryDto[]> {
    return await makeRequest({route: 'repositories', method: 'GET'});
}

export async function getRepository(id: string): Promise<RepositoryDto> {
    return await makeRequest({route: `repositories/${id}`, method: 'GET'});
}

export interface CreateRepositoryPayload {
    name: string;
    description: string | null;
    /** `null` creates a local repository, which starts with an empty commit on its branch `main`. */
    remote: RemoteSettings | null;
    /** With a remote, checks that the token may push. */
    allow_commits: boolean;
}

export interface RemoteSettings {
    url: string;
    branch: string;
    /** At least 60. */
    poll_interval_seconds: number;
    /** `null` for public repositories. */
    token: string | null;
}

/**
 * With a remote, contacts it first, so it can fail with `REPO_NOT_FOUND`, `BRANCH_NOT_FOUND`, `AUTH_FAILED`,
 * `TOKEN_REQUIRED` or `REMOTE_UNREACHABLE`.
 */
export async function createRepository(payload: CreateRepositoryPayload): Promise<RepositoryDto> {
    return await makeRequest({route: 'repositories', method: 'POST', body: payload});
}

/** `KEEP` is rejected when the `url` moves to another host. */
export type TokenChange =
    | { action: 'KEEP' }
    | { action: 'REMOVE' }
    | { action: 'SET', value: string };

export interface UpdateRepositoryPayload {
    name: string;
    description: string | null;
    /** `null` for a local repository, which stays local. A repository with a remote keeps one. */
    remote: RemoteSettingsChange | null;
    allow_commits: boolean;
}

export interface RemoteSettingsChange {
    url: string;
    branch: string;
    poll_interval_seconds: number;
    token: TokenChange;
}

/** Owner only (others get `FORBIDDEN`). Replaces all fields. */
export async function updateRepository(id: string, payload: UpdateRepositoryPayload): Promise<RepositoryDto> {
    return await makeRequest({route: `repositories/${id}/update`, method: 'POST', body: payload});
}

export async function deleteRepository(id: string): Promise<void> {
    await makeRequest({route: `repositories/${id}/delete`, method: 'POST'});
}

/** Schedules a sync as soon as possible. Fails with `RATE_LIMITED` if requested too often. */
export async function requestSync(id: string): Promise<void> {
    await makeRequest({route: `repositories/${id}/sync`, method: 'POST'});
}

/** The documents in the synced commit, and how far their conversion to Markdown is. */
export async function getRepositoryDocuments(id: string): Promise<RepositoryDocumentsDto> {
    return await makeRequest({route: `repositories/${id}/documents`, method: 'GET'});
}

/** The users the repository is shared with. Owner and admins only. */
export async function getRepositoryUsers(id: string): Promise<RepositoryUserDto[]> {
    return await makeRequest({route: `repositories/${id}/users`, method: 'GET'});
}

/** Shares the repository. Fails with `UNKNOWN_USER`, sharing it again does nothing. */
export async function addRepositoryUser(id: string, userNameOrEmail: string): Promise<void> {
    await makeRequest({
        route: `repositories/${id}/users`,
        method: 'POST',
        body: {user_name_or_email: userNameOrEmail},
    });
}

/** Lets the user the repository is shared with commit, if it allows commits. Owner and admins only. */
export async function updateRepositoryUser(id: string, userId: string, canCommit: boolean): Promise<void> {
    await makeRequest({
        route: `repositories/${id}/users/${userId}/update`,
        method: 'POST',
        body: {can_commit: canCommit},
    });
}

export async function removeRepositoryUser(id: string, userId: string): Promise<void> {
    await makeRequest({route: `repositories/${id}/users/${userId}/delete`, method: 'POST'});
}

// --- Chats ---

/** Newest first. Pass the returned `next_cursor` to get the next page. */
export async function getChats(cursor: string | null = null, limit: number = 10): Promise<ChatPageDto> {
    return await makeRequest({route: 'chats', method: 'GET', params: {cursor, limit}});
}

export async function getChat(id: string): Promise<ChatDetailDto> {
    return await makeRequest({route: `chats/${id}`, method: 'GET'});
}

export interface CreateChatPayload {
    /** The first message, may be blank with an attachment. */
    content: string;
    /** Uploaded with {@link uploadAttachment}, sent with the message. */
    attachment_id?: string | null;
    all_repositories: boolean;
    /** Ignored if `all_repositories`. */
    repository_ids: string[];
    /** Derived from `content` if absent or blank. */
    title?: string | null;
    /** Absent or `null` uses the user's model. */
    model_id?: string | null;
    /** Not listed, and deleted a day after its last message. Cannot be changed later. */
    temporary?: boolean;
}

/**
 * Creates the chat with its first message and starts generating the answer, which is the
 * last message (status `GENERATING`). Fails with `NO_MODEL_CONFIGURED`, `UNKNOWN_MODEL`,
 * `UNKNOWN_REPOSITORY` or `UNKNOWN_ATTACHMENT`.
 */
export async function createChat(payload: CreateChatPayload): Promise<ChatDetailDto> {
    return await makeRequest({route: 'chats', method: 'POST', body: payload});
}

/** The repositories of a chat cannot be changed. */
export interface UpdateChatPayload {
    title: string;
    /** `null` uses the user's model. */
    model_id: string | null;
}

/** Replaces all fields. Fails with `UNKNOWN_MODEL`. */
export async function updateChat(id: string, payload: UpdateChatPayload): Promise<ChatDto> {
    return await makeRequest({route: `chats/${id}/update`, method: 'POST', body: payload});
}

export async function deleteChat(id: string): Promise<void> {
    await makeRequest({route: `chats/${id}/delete`, method: 'POST'});
}

/**
 * Returns the user's message and the `GENERATING` answer. Fails with `GENERATION_IN_PROGRESS`,
 * `RATE_LIMITED` (too many generations of this user) or `NO_MODEL_CONFIGURED`.
 */
/** `content` may be blank with an attachment. Fails with `UNKNOWN_ATTACHMENT`. */
export async function sendMessage(chatId: string, content: string, attachmentId: string | null = null): Promise<[MessageDto, MessageDto]> {
    return await makeRequest({
        route: `chats/${chatId}/messages`,
        method: 'POST',
        body: {content, attachment_id: attachmentId},
    });
}

/** Larger files are rejected, same as the API's limit. */
export const MAX_ATTACHMENT_BYTES = 50 * 1024 * 1024;

/**
 * Uploads a file to send with the next message (`attachment_id`). Sent as raw bytes, since
 * `application/octet-stream`, unlike a form, cannot be posted cross-site without a CORS preflight.
 */
export async function uploadAttachment(file: File): Promise<AttachmentDto> {
    if (DEMO) {
        return await demoUploadAttachment(file);
    }
    const url = new URL(`${API_URL}/attachments`, document.location.href);
    url.searchParams.set('file_name', file.name);
    if (file.type) {
        url.searchParams.set('content_type', file.type);
    }
    const response = await send(url, {
        method: 'POST',
        body: file,
        headers: {"Content-Type": "application/octet-stream"},
    });
    await throwIfFailed(response, false);
    return await response.json() as AttachmentDto;
}

/** Downloads the file of an attachment, e.g. as the `href` of a link. */
export function attachmentUrl(id: string): string {
    if (DEMO) {
        return demoAttachmentUrl(id);
    }
    return `${API_URL}/attachments/${id}`;
}

export async function cancelMessage(chatId: string, messageId: string): Promise<void> {
    await makeRequest({route: `chats/${chatId}/messages/${messageId}/cancel`, method: 'POST'});
}

/**
 * Replaces the failed or cancelled last answer with a new one (new id, status `GENERATING`), which is
 * returned. Fails with `NOT_RETRYABLE`.
 */
export async function retryMessage(chatId: string, messageId: string): Promise<MessageDto> {
    return await makeRequest({route: `chats/${chatId}/messages/${messageId}/retry`, method: 'POST'});
}

/** A tool call with its output. */
export async function getToolCall(chatId: string, toolCallId: string): Promise<ToolCallDto> {
    return await makeRequest({route: `chats/${chatId}/tool-calls/${toolCallId}`, method: 'GET'});
}

/** A file as it is in the repository, with its `Content-Type`. */
export interface FileContent {
    contentType: string;
    blob: Blob;
}

/**
 * The file of a `present_file_to_user` call as it is in the repository (PDFs are the original
 * files), at the commit the answer read. The content type is `application/pdf`, `text/markdown` or
 * `text/plain`. `FILE_UNAVAILABLE` if it can no longer be read, `NOT_FOUND` if the repository is
 * gone or no longer shared with the user.
 */
export async function getPresentedFile(chatId: string, toolCallId: string): Promise<FileContent> {
    const response = await fetchResponse({route: `chats/${chatId}/tool-calls/${toolCallId}/file`, method: 'GET'});
    return {contentType: response.headers.get('Content-Type') ?? '', blob: await response.blob()};
}

/**
 * The commit a `change_file` call proposed, as a patch that `git am` applies. `FILE_UNAVAILABLE`
 * if it can no longer be read, `NOT_FOUND` if the call failed, or the repository is gone or no
 * longer shared with the user.
 */
export async function getProposedCommitPatch(chatId: string, toolCallId: string): Promise<string> {
    const response = await fetchResponse({route: `chats/${chatId}/tool-calls/${toolCallId}/patch`, method: 'GET'});
    return await response.text();
}

/**
 * The commit a `change_file`, `save_attachment` or `move_files` call proposed, as it is shown: the diff
 * of the file with the changed words marked, or the moves. Fails like {@link getProposedCommitPatch}.
 */
export async function getProposedCommitDiff(chatId: string, toolCallId: string): Promise<FileDiffDto> {
    return await makeRequest({route: `chats/${chatId}/tool-calls/${toolCallId}/diff`, method: 'GET'});
}

/**
 * The file a `change_file` or `save_attachment` call proposed, as it is in the proposed commit,
 * with the content types of {@link getPresentedFile}. `FILE_UNAVAILABLE` if it can't be shown,
 * e.g. since the change deletes it, `NOT_FOUND` like {@link getProposedCommitPatch}.
 */
export async function getProposedCommitFile(chatId: string, toolCallId: string): Promise<FileContent> {
    const response = await fetchResponse({route: `chats/${chatId}/tool-calls/${toolCallId}/proposed-commit/file`, method: 'GET'});
    return {contentType: response.headers.get('Content-Type') ?? '', blob: await response.blob()};
}

/** The change a `change_file` call proposed, and whether it was committed. `NOT_FOUND` like {@link getProposedCommitPatch}. */
export async function getProposedCommit(chatId: string, toolCallId: string): Promise<ProposedCommitDto> {
    return await makeRequest({route: `chats/${chatId}/tool-calls/${toolCallId}/proposed-commit`, method: 'GET'});
}

/**
 * Pushes the change a `change_file` call proposed to the branch of its repository. Returns how it went
 * (`COMMITTED`, `CONFLICT` or `FAILED`, with its `error`). `FORBIDDEN` unless the user may commit it,
 * `FILE_UNAVAILABLE` if the change can no longer be read.
 */
export async function commitProposedCommit(chatId: string, toolCallId: string): Promise<ProposedCommitDto> {
    return await makeRequest({route: `chats/${chatId}/tool-calls/${toolCallId}/commit`, method: 'POST'});
}

const STREAM_EVENTS = ['snapshot', 'content_delta', 'tool_call_started', 'tool_call_finished', 'done'] as const;

/**
 * Follows a `GENERATING` answer. `onEvent` gets a `snapshot` first (again after each reconnect, so
 * apply it by replacing the message) and finally `done`, after which the stream is closed.
 * `onError` is called if the stream cannot be (re)opened, e.g. the message is gone.
 * Returns a function that closes the stream.
 */
export function streamMessage(
    chatId: string,
    messageId: string,
    onEvent: (event: MessageStreamEvent) => void,
    onError?: () => void,
): () => void {
    if (DEMO) {
        return demoStreamMessage(chatId, messageId, onEvent, onError);
    }
    const source = new EventSource(`${API_URL}/chats/${chatId}/messages/${messageId}/stream`);

    for (const type of STREAM_EVENTS) {
        source.addEventListener(type, (e: MessageEvent) => {
            onEvent({type, data: JSON.parse(e.data)} as MessageStreamEvent);
            if (type === 'done') {
                source.close();
            }
        });
    }

    // EventSource reconnects by itself after network errors, CLOSED means it gave up (e.g. a 404).
    source.onerror = () => {
        if (source.readyState === EventSource.CLOSED) {
            onError?.();
        }
    };

    return () => source.close();
}

// --- Admin: users ---

export async function getUsers(): Promise<UserDto[]> {
    return await makeRequest({route: 'users', method: 'GET'});
}

export interface RegisterUserPayload {
    /** 1 to 64 letters, digits, `.`, `_` or `-`. */
    user_name: string;
    /** `null` registers the user without one. */
    email: string | null;
    /** 8 to 128 characters. */
    password: string;
    /** The user must change the password after logging in. */
    must_change_password: boolean;
}

/** Fails with `USER_NAME_TAKEN` or `EMAIL_TAKEN`. */
export async function registerUser(payload: RegisterUserPayload): Promise<UserDto> {
    return await makeRequest({route: 'register', method: 'POST', body: payload});
}

export interface UpdateUserPayload {
    user_name: string;
    /** `null` removes it. */
    email: string | null;
    can_login: boolean;
    can_manage_repositories: boolean;
    can_change_identity: boolean;
    /** The user can do nothing but change their password until they do. */
    must_change_password: boolean;
}

/**
 * Fails with `USER_NAME_TAKEN` or `EMAIL_TAKEN`. Disabling the login signs the user out everywhere. Admins can be
 * renamed but not restricted (`FORBIDDEN`).
 */
export async function updateUser(userId: string, payload: UpdateUserPayload): Promise<UserDto> {
    return await makeRequest({route: `users/${userId}/update`, method: 'POST', body: payload});
}

export interface ResetPasswordPayload {
    /** 8 to 128 characters. */
    password: string;
    /** The user must change the password after logging in. */
    must_change_password: boolean;
}

/** Sets the password of another user and signs them out everywhere. Admins change their own with `changePassword`. */
export async function resetUserPassword(userId: string, payload: ResetPasswordPayload): Promise<UserDto> {
    return await makeRequest({route: `users/${userId}/password`, method: 'POST', body: payload});
}

/** Admins cannot delete themselves. */
export async function deleteUser(userId: string): Promise<void> {
    await makeRequest({route: 'delete-user', method: 'POST', body: {user_id: userId}});
}

// --- Admin: config ---

/** Every key the server was started with (without secrets), sorted by key. */
export async function getConfig(): Promise<ConfigEntryDto[]> {
    return await makeRequest({route: 'config', method: 'GET'});
}

/**
 * Replaces all overrides, so keys missing from `overrides` fall back to their `env` value. Applied immediately.
 * Fails with `VALIDATION_ERROR` for unknown keys and invalid values.
 */
export async function setConfigOverrides(overrides: Record<string, string>): Promise<ConfigEntryDto[]> {
    return await makeRequest({route: 'config', method: 'POST', body: overrides});
}

// --- Admin: Document extraction ---

export async function getExtractionOverview(): Promise<ExtractionOverviewDto> {
    return await makeRequest({route: 'document-extraction', method: 'GET'});
}

/** The documents of all repositories, by repository name and path. */
export async function getExtractionDocuments(
    filter: DocumentFilter,
    offset: number,
    limit: number,
): Promise<ExtractionDocumentPageDto> {
    return await makeRequest({
        route: 'document-extraction/documents',
        method: 'GET',
        params: {filter, offset, limit},
    });
}

/** Converts the document again if it failed or was not available, else does nothing. */
export async function retryDocument(blobOid: string): Promise<void> {
    await makeRequest({route: 'document-extraction/retry', method: 'POST', body: {blob_oid: blobOid}});
}

// --- Admin: LLM providers and models ---

export async function getLlmProviders(): Promise<LlmProviderDto[]> {
    return await makeRequest({route: 'llm-providers', method: 'GET'});
}

export interface CreateLlmProviderPayload {
    name: string;
    api_format: LlmApiFormat;
    /** `null` or blank uses the official API of `api_format`. */
    base_url: string | null;
    /** `null` or blank for servers without authentication. */
    api_key: string | null;
    /** ISO 4217 code of the model prices, e.g. `USD`. `null` if its models have no prices. */
    currency: string | null;
}

/** Fails with `NAME_TAKEN`. */
export async function createLlmProvider(payload: CreateLlmProviderPayload): Promise<LlmProviderDto> {
    return await makeRequest({route: 'llm-providers', method: 'POST', body: payload});
}

/** `KEEP` is rejected when `base_url` moves to another host. */
export type ApiKeyChange =
    | { action: 'KEEP' }
    | { action: 'REMOVE' }
    | { action: 'SET', value: string };

export interface UpdateLlmProviderPayload {
    name: string;
    api_format: LlmApiFormat;
    base_url: string | null;
    api_key: ApiKeyChange;
    /** `null` is rejected while models of the provider have prices. */
    currency: string | null;
}

export async function updateLlmProvider(id: string, payload: UpdateLlmProviderPayload): Promise<LlmProviderDto> {
    return await makeRequest({route: `llm-providers/${id}/update`, method: 'POST', body: payload});
}

/** Also deletes its models. */
export async function deleteLlmProvider(id: string): Promise<void> {
    await makeRequest({route: `llm-providers/${id}/delete`, method: 'POST'});
}

export interface LlmModelPayload {
    /** The model id sent to the API, e.g. `claude-opus-5-5`. */
    api_name: string;
    /** Shown to users, e.g. `Claude Opus 5.5`. `null`, blank or the same as `api_name` shows `api_name` (and is stored as `null`). The name shown is unique among all models, ignoring case. */
    display_name: string | null;
    /** `null` uses the default of the API format. */
    max_output_tokens: number | null;
    /** Per million tokens in the provider's currency, as decimal strings. Set together, `null` if unknown. Only if the provider has a currency. */
    input_price: string | null;
    output_price: string | null;
    /** `null` charges `input_price`. Only with `input_price`. */
    cache_read_price: string | null;
    /** `null` charges `input_price`. Only with `input_price`. */
    cache_write_price: string | null;
}

/** The first model becomes the default. Fails with `NAME_TAKEN`. */
export async function createLlmModel(providerId: string, payload: LlmModelPayload): Promise<LlmModelDto> {
    return await makeRequest({route: `llm-providers/${providerId}/models`, method: 'POST', body: payload});
}

/**
 * The models the provider's server offers, newest first as far as it says. Fails with `AUTH_FAILED` if the server
 * rejects the key, and `REMOTE_UNREACHABLE` if it cannot be reached or does not list its models.
 */
export async function getRemoteLlmModels(providerId: string): Promise<RemoteModelDto[]> {
    return await makeRequest({route: `llm-providers/${providerId}/remote-models`, method: 'GET'});
}

export async function updateLlmModel(id: string, payload: LlmModelPayload): Promise<LlmModelDto> {
    return await makeRequest({route: `models/${id}/update`, method: 'POST', body: payload});
}

export async function deleteLlmModel(id: string): Promise<void> {
    await makeRequest({route: `models/${id}/delete`, method: 'POST'});
}

/** The model of users who did not choose one, replacing the previous default. Fails with `UNKNOWN_MODEL`. */
export async function setDefaultModel(modelId: string): Promise<void> {
    await makeRequest({route: 'default-model', method: 'POST', body: {model_id: modelId}});
}
