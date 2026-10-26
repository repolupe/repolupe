// Mirrors the DTOs in api/src/controller/mod.rs. Ids are UUIDs, timestamps ISO 8601 strings.

export enum UserRole {
    USER = "USER",
    ADMIN = "ADMIN",
}

export interface InstanceDto {
    name: string;
}

/** The server as admins see it. */
export interface ServerDto {
    version: string;
}

/** A row of `GET /api/v1/config`, values in the text form of the environment variables. */
export interface ConfigEntryDto {
    key: string;
    /** What the server was started with: the environment variable, or built in. `null` if unset, `******` for secrets. */
    env: string | null;
    /** Set by an admin, in effect instead of `env`. */
    override: string | null;
    /** Whether it can be overridden. Everything else needs a restart. */
    runtime: boolean;
}

export interface UserDto {
    id: string;
    role: UserRole;
    /** Unique ignoring case. Letters, digits, `.`, `_` and `-`. */
    user_name: string;
    /** Unique ignoring case. */
    email: string | null;
    /** `false` rejects logins. Always `true` for admins. */
    can_login: boolean;
    /** `false` only lets the user read repositories shared with them. Always `true` for admins. */
    can_manage_repositories: boolean;
    /** `false` keeps the user from changing their own user name and email. Always `true` for admins. */
    can_change_identity: boolean;
    /**
     * Set by an admin: every request but `GET /me` and changing the password fails with `PASSWORD_CHANGE_REQUIRED`
     * until the user changes it.
     */
    must_change_password: boolean;
    /** `null` uses the default model. */
    default_model_id: string | null;
    /** BCP 47 language tag such as `de-DE`, `null` lets the client decide. */
    locale: string | null;
    /** Commits the changes the model proposes once its answer is complete, instead of leaving them to the user. */
    auto_commit: boolean;
    /** As it appears in documents, tells the LLM who "I" is in questions. */
    full_name: string | null;
    first_name: string | null;
    /** What the user tells the LLM about themselves. */
    about: string | null;
    created_at: string;
}

export enum RepositorySyncStatus {
    PENDING = "PENDING",
    SYNCING = "SYNCING",
    READY = "READY",
    FAILED = "FAILED",
}

export interface RepositoryDto {
    id: string;
    /** Only the owner manages the repository, others it is shared with can only read it. */
    owner_id: string;
    name: string;
    description: string | null;
    /** `null` for a local repository, which only exists on the server and changes only by committing the model's proposals. */
    remote: RemoteSettingsDto | null;
    /** Whether the model proposes commits to the owner (`change_file`, `move_files`), who reviews them, and to the users it is shared with who may commit. */
    allow_commits: boolean;
    /** Whether the viewer commits the changes proposed to them: commits are allowed, and they own it or the owner lets them commit. */
    can_commit: boolean;
    sync_status: RepositorySyncStatus;
    sync_started_at: string | null;
    head_commit_sha: string | null;
    last_synced_at: string | null;
    /** Bytes of the git objects of the branch (other branches and tags are not fetched), `null` until the first sync. */
    git_size: number | null;
    /** Bytes of the LFS objects in the head commit, `null` until the first sync. */
    lfs_size: number | null;
    last_error: string | null;
    /** `null` while no sync is scheduled, e.g. of a local repository after its last sync. */
    next_sync_at: string | null;
    created_at: string;
    updated_at: string;
}

/** The remote a repository is synced from. */
export interface RemoteSettingsDto {
    url: string;
    /** The branch that is synced. */
    branch: string;
    poll_interval_seconds: number;
    /** `null` for public remotes. The hint is only returned to the owner. */
    token: { hint: string | null } | null;
}

export interface RepositoryUserDto {
    user_id: string;
    user_name: string;
    email: string | null;
    /** Whether they commit the changes proposed to them, like the owner, if the repository allows commits. */
    can_commit: boolean;
    /** When the repository was shared with the user. */
    created_at: string;
}

export interface RepositoryDocumentsDto {
    /** By path. */
    documents: RepositoryDocumentDto[];
    /** Set while the conversions wait for the OCR service, which is unavailable. */
    paused_until: string | null;
}

export interface RepositoryDocumentDto {
    path: string;
    /** What the model reads, `null` until the document is converted for the first time. */
    extraction: DocumentExtractionDto | null;
    /**
     * `null` once the document is converted with the current settings. Until then, the model
     * reads `extraction`, if any, which was made with earlier settings.
     */
    conversion: DocumentConversionDto | null;
}

export enum DocumentExtractionStatus {
    COMPLETED = "COMPLETED",
    FAILED = "FAILED",
}

export interface DocumentExtractionDto {
    status: DocumentExtractionStatus;
    /** Whether pages were recognized with OCR, so the text may contain errors. For `COMPLETED`. */
    ocr: boolean | null;
    /** Why the document could not be converted, as the model sees it. For `FAILED`. */
    error: string | null;
    extracted_at: string;
}

export enum DocumentConversionStatus {
    WAITING = "WAITING",
    CONVERTING = "CONVERTING",
    /** Left out for a while, see `skip_reason`. */
    SKIPPED = "SKIPPED",
}

export enum DocumentSkipReason {
    /** The file is stored with Git LFS, and its object was not downloaded by the sync. */
    LFS_OBJECT_MISSING = "LFS_OBJECT_MISSING",
    /** The file could not be read, or the result not stored. */
    ERROR = "ERROR",
}

/** What the document conversion is doing across all repositories. Admins only. */
export interface ExtractionOverviewDto {
    /** Identifies the current settings. Documents converted with others are converted again. */
    extractor: string;
    converting: ConvertingDocumentDto | null;
    paused: ExtractionPauseDto | null;
    totals: ExtractionTotalsDto;
}

export interface ConvertingDocumentDto {
    /** `null` for an attachment, or if the repository was deleted meanwhile. */
    repository: RepositoryLabelDto | null;
    /** For an attachment, its file name. */
    path: string;
    /** Whether it is a file attached to a chat, not one in a repository. */
    attachment: boolean;
    started_at: string;
}

export interface ExtractionPauseDto {
    until: string;
    /** The error of the OCR service. */
    reason: string;
}

/** A blob counts once for each repository and path containing it. */
export interface ExtractionTotalsDto {
    documents: number;
    /** The counts below add up to `documents`. With the current settings. */
    converted: number;
    /** With the current settings. */
    failed: number;
    /** Waiting to be converted with the current settings, or being converted. */
    waiting: number;
    /** Left out for a while, e.g. since the LFS object was not downloaded. */
    skipped: number;
}

/** A repository of any user, in admin views. */
export interface RepositoryLabelDto {
    id: string;
    name: string;
    owner_name: string;
    /** Whether the admin owns the repository or it is shared with them, so they can open it. */
    readable: boolean;
}

/** Which documents to list, by their extraction with the current settings. */
export enum DocumentFilter {
    ALL = "ALL",
    CONVERTED = "CONVERTED",
    FAILED = "FAILED",
    /** Not converted with the current settings yet. */
    PENDING = "PENDING",
}

export interface ExtractionDocumentPageDto {
    items: ExtractionDocumentDto[];
    /** Of all pages. */
    total: number;
}

/** A document of any repository, for admins. */
export interface ExtractionDocumentDto extends RepositoryDocumentDto {
    repository: RepositoryLabelDto;
    /** Identifies the content, see `retryDocument`. */
    blob_oid: string;
}

export interface DocumentConversionDto {
    status: DocumentConversionStatus;
    /** For `CONVERTING`. */
    started_at: string | null;
    /** For `SKIPPED`. */
    skip_reason: DocumentSkipReason | null;
    /** When a `SKIPPED` document is tried again. */
    retry_at: string | null;
}

export enum LlmApiFormat {
    ANTHROPIC = "ANTHROPIC",
    /** Any OpenAI-compatible server (OpenRouter, Ollama, vLLM, LM Studio, ...). */
    OPENAI = "OPENAI",
}

export interface LlmProviderDto {
    id: string;
    name: string;
    api_format: LlmApiFormat;
    base_url: string;
    /** `null` for servers without authentication. The key itself is never returned. */
    api_key: { hint: string | null } | null;
    /** ISO 4217 code of the model prices, e.g. `USD`. `null` if its models have no prices. */
    currency: string | null;
    models: LlmModelDto[];
    created_at: string;
    updated_at: string;
}

/** A model as admins see it, see {@link ModelDto} for users. */
export interface LlmModelDto {
    id: string;
    provider_id: string;
    /** Sent to the API, e.g. `claude-opus-5-5`. */
    api_name: string;
    /** Shown to users, e.g. `Claude Opus 5.5`. `null` shows `api_name`. */
    display_name: string | null;
    /** `null` uses the default of the API format. */
    max_output_tokens: number | null;
    /** Per million tokens in the provider's currency, as decimal strings. `null` if unknown. */
    input_price: string | null;
    output_price: string | null;
    /** `null` charges `input_price`. */
    cache_read_price: string | null;
    /** `null` charges `input_price`. */
    cache_write_price: string | null;
    is_default: boolean;
    created_at: string;
    updated_at: string;
}

/** A common LLM provider, offered when creating one, see {@link getLlmProviderSuggestions}. */
export interface LlmProviderSuggestionDto {
    name: string;
    api_format: LlmApiFormat;
    base_url: string;
    /** ISO 4217 code the provider prices its models in, `null` for local servers. */
    currency: string | null;
    /** ISO 3166-1 alpha-2 code of the provider's country, shown as its flag. `null` for local servers. */
    country_code: string | null;
    /** Whether the provider serves the models itself, `false` for routers that forward requests to other providers. */
    runs_inference: boolean;
    /** Brand of the models the provider develops (e.g. Claude), shown as its subtitle. `null` for hosts and routers of other companies' models. */
    model_brand: string | null;
}

/** A model the provider's server offers, see {@link getRemoteLlmModels}. */
export interface RemoteModelDto {
    /** Sent to the API, e.g. `claude-opus-5-5`. */
    api_name: string;
    /** `null` if the server only has the id, or a name that is the same. */
    display_name: string | null;
}

/** A model as users see it. */
export interface ModelDto {
    id: string;
    /** Falls back to the API name. */
    display_name: string;
    provider_id: string;
    provider_name: string;
    /** Used by users who did not choose a model. */
    is_default: boolean;
}

export interface ChatDto {
    id: string;
    title: string;
    all_repositories: boolean;
    /** Empty if `all_repositories` is true. */
    repository_ids: string[];
    /** `null` uses the user's model. */
    model_id: string | null;
    /** Not listed in `GET /api/v1/chats`, and deleted a day after its last message. */
    temporary: boolean;
    created_at: string;
    updated_at: string;
}

/** Which repositories a chat reads, as sent to the API. */
export interface RepositoryScope {
    all_repositories: boolean;
    /** Ignored if `all_repositories`. */
    repository_ids: string[];
}

export interface ChatPageDto {
    items: ChatDto[];
    /** Pass as `cursor` to get the next page, `null` on the last page. */
    next_cursor: string | null;
}

export interface ChatDetailDto extends ChatDto {
    messages: MessageDto[];
}

export enum MessageRole {
    USER = "USER",
    ASSISTANT = "ASSISTANT",
}

export enum MessageStatus {
    GENERATING = "GENERATING",
    COMPLETED = "COMPLETED",
    FAILED = "FAILED",
    CANCELLED = "CANCELLED",
}

export interface MessageDto {
    id: string;
    role: MessageRole;
    /** Partial while `GENERATING`, and after `FAILED` or `CANCELLED`. */
    content: string;
    status: MessageStatus;
    error: string | null;
    /** The model that wrote the answer, `null` for user messages or if the model was deleted. */
    model_id: string | null;
    tool_calls: ToolCallSummaryDto[];
    created_at: string;
    /** When the answer reached its final status, `null` for user messages, while `GENERATING`, or if it was interrupted by a restart. */
    finished_at: string | null;
    /** Tokens used for the answer, `null` for user messages, while `GENERATING`, or if unknown. */
    usage: UsageDto | null;
    /** At the prices when the answer finished, `null` if the model had no prices or the usage is unknown. */
    cost: CostDto | null;
    /** The file sent with a user message, `null` if none. */
    attachment: AttachmentDto | null;
}

/** A file the user attached to a chat, downloaded from `attachmentUrl`. */
export interface AttachmentDto {
    id: string;
    /** How the model refers to it, counting from 1 per chat, `null` until sent. */
    number: number | null;
    file_name: string;
    content_type: string;
    size: number;
    created_at: string;
}

export interface UsageDto {
    /** Not read from or written to the cache. */
    input_tokens: number;
    output_tokens: number;
    cache_read_tokens: number;
    cache_write_tokens: number;
}

export interface CostDto {
    /** A decimal string, unrounded. */
    amount: string;
    /** ISO 4217 code, e.g. `USD`. */
    currency: string;
}

export enum ToolCallStatus {
    RUNNING = "RUNNING",
    COMPLETED = "COMPLETED",
    FAILED = "FAILED",
}

/** A tool call without its output, see {@link ToolCallDto}. */
export interface ToolCallSummaryDto {
    id: string;
    /** `list_files`, `read_file`, `grep`, `outline`, `present_file_to_user`, `change_file`, `move_files`, `save_attachment` or `read_attachment`. */
    name: string;
    input: Record<string, unknown>;
    /** `null` for tools not bound to one repository, or if the repository was deleted. */
    repository_id: string | null;
    commit_sha: string | null;
    status: ToolCallStatus;
    created_at: string;
}

export interface ToolCallDto extends ToolCallSummaryDto {
    /** `null` while running. */
    output: string | null;
}

/** How far a change proposed with `change_file`, `move_files` or `save_attachment` got. */
export enum ProposedCommitStatus {
    PROPOSED = "PROPOSED",
    /** Pushed to the branch. */
    COMMITTED = "COMMITTED",
    /** The paths it changes changed on the branch since the commit the change was based on. */
    CONFLICT = "CONFLICT",
    /** The push failed, e.g. the remote refused it. */
    FAILED = "FAILED",
}

/** A file or folder moved by `move_files`. */
export interface FileMoveDto {
    from: string;
    /** The new path of the file or folder itself. */
    to: string;
}

/** The change a successful `change_file`, `move_files` or `save_attachment` call proposed, and whether it was committed. */
export interface ProposedCommitDto {
    /** The file `change_file` or `save_attachment` changes, `null` for `move_files`. */
    path: string | null;
    /** What `move_files` moves, `null` for the other tools. */
    moves: FileMoveDto[] | null;
    /** The proposed commit, on top of the tool call's `commit_sha`. Only in the server's mirror. */
    proposed_commit: string;
    status: ProposedCommitStatus;
    /**
     * Once `COMMITTED`: the commit on the branch, `proposed_commit` or the same change on top of the
     * newer commit the branch had moved to.
     */
    pushed_commit: string | null;
    pushed_branch: string | null;
    /** Why the last attempt failed, set while `CONFLICT` or `FAILED`. */
    error: string | null;
    committed_at: string | null;
    /** Whether the user may commit it: they own the repository, which allows commits, and may manage repositories. */
    can_commit: boolean;
}

/** What a change does to its file. */
export enum DiffFileKind {
    MODIFIED = "MODIFIED",
    ADDED = "ADDED",
    DELETED = "DELETED",
}

export enum DiffLineKind {
    CONTEXT = "CONTEXT",
    REMOVED = "REMOVED",
    ADDED = "ADDED",
}

export interface DiffPartDto {
    text: string;
    changed: boolean;
}

export interface DiffLineDto {
    kind: DiffLineKind;
    /**
     * The text of the line without its line break, in pieces; the pieces that differ from the line's
     * counterpart in the other version are `changed`.
     */
    parts: DiffPartDto[];
}

/** Changed lines with up to 3 unchanged lines around them. */
export interface DiffHunkDto {
    /** Whether unchanged lines were left out before it. */
    skipped: boolean;
    lines: DiffLineDto[];
}

/** A file or folder moved by `move_files`. */
export interface DiffMoveDto {
    from: string;
    /** The new path of the file or folder itself. */
    to: string;
    /** How many files the folder holds, `null` if it is a file. */
    folder_files: number | null;
}

/**
 * The change a successful `change_file`, `save_attachment` or `move_files` call proposed, as it is shown
 * to the user: the diff of the file with the changed words marked, or the moves.
 */
export interface FileDiffDto {
    /** `MODIFIED` for moves. */
    kind: DiffFileKind;
    /** Empty for files without a text diff (binary files, PDFs) and for moves. */
    hunks: DiffHunkDto[];
    /** What `move_files` moves, `null` for the other tools. */
    moves: DiffMoveDto[] | null;
}

/**
 * Events of `GET /api/v1/chats/{id}/messages/{message_id}/stream`. The stream starts with a
 * `snapshot` of the message so far and ends with `done`, both carrying the full message.
 * While generating, the content includes the preambles to tool calls ("Let me look…"), which
 * `done` leaves out.
 */
export type MessageStreamEvent =
    | { type: 'snapshot', data: MessageDto }
    | { type: 'content_delta', data: { text: string } }
    | { type: 'tool_call_started', data: ToolCallSummaryDto }
    | { type: 'tool_call_finished', data: { id: string, status: ToolCallStatus } }
    | { type: 'done', data: MessageDto };

/** Stable error codes of the API (`ErrorCode` in api/src/config/error.rs). Branch on these, never on the message. */
export enum ErrorCode {
    INTERNAL_ERROR = "INTERNAL_ERROR",
    VALIDATION_ERROR = "VALIDATION_ERROR",
    UNSUPPORTED_MEDIA_TYPE = "UNSUPPORTED_MEDIA_TYPE",
    UNAUTHORIZED = "UNAUTHORIZED",
    FORBIDDEN = "FORBIDDEN",
    NOT_FOUND = "NOT_FOUND",
    CONFLICT = "CONFLICT",
    RATE_LIMITED = "RATE_LIMITED",
    USER_NAME_TAKEN = "USER_NAME_TAKEN",
    EMAIL_TAKEN = "EMAIL_TAKEN",
    NAME_TAKEN = "NAME_TAKEN",
    REPO_NOT_FOUND = "REPO_NOT_FOUND",
    BRANCH_NOT_FOUND = "BRANCH_NOT_FOUND",
    AUTH_FAILED = "AUTH_FAILED",
    TOKEN_REQUIRED = "TOKEN_REQUIRED",
    REMOTE_UNREACHABLE = "REMOTE_UNREACHABLE",
    UNKNOWN_REPOSITORY = "UNKNOWN_REPOSITORY",
    UNKNOWN_USER = "UNKNOWN_USER",
    GENERATION_IN_PROGRESS = "GENERATION_IN_PROGRESS",
    NOT_RETRYABLE = "NOT_RETRYABLE",
    WRONG_PASSWORD = "WRONG_PASSWORD",
    SAME_PASSWORD = "SAME_PASSWORD",
    PASSWORD_CHANGE_REQUIRED = "PASSWORD_CHANGE_REQUIRED",
    UNKNOWN_MODEL = "UNKNOWN_MODEL",
    NO_MODEL_CONFIGURED = "NO_MODEL_CONFIGURED",
    UNAVAILABLE = "UNAVAILABLE",
    FILE_UNAVAILABLE = "FILE_UNAVAILABLE",
    UNKNOWN_ATTACHMENT = "UNKNOWN_ATTACHMENT",
}
