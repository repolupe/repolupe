import {
    McpServerStatus,
    ToolCallStatus,
    type AttachmentDto,
    type FileMoveDto,
    type McpServerDto,
    type McpServerScope,
    type McpToolDto,
    type MessageDto,
    type ModelDto,
    type RepositoryDto,
    type RepositoryScope,
    type ToolCallSummaryDto,
    type UsageDto,
} from "~/utils/model";
import {formatLocale, t} from "~/utils/i18n";

let snackbarFunc: (text: string) => void = () => {};

export function initSnackbar(func: (text: string) => void) {
    snackbarFunc = func;
}

export function showSnackbar(text: string) {
    snackbarFunc(text);
}

/** E.g. "All Repositories", the name of the only repository, or "3 repositories". */
export function repositoryScopeSummary(scope: RepositoryScope, repositories: RepositoryDto[]): string {
    if (scope.all_repositories) {
        return t('chat.allRepositories');
    }
    const ids = scope.repository_ids;
    const name = ids.length === 1 ? repositories.find(r => r.id === ids[0])?.name : undefined;
    return name ?? t('chat.repositoryCount', ids.length);
}

/**
 * Turned on by the user for their chats: by its owner for their own server, by the user it is shared with for theirs,
 * whether or not the owner uses it. Only then its tools may be used in the user's chats.
 */
export function isMcpServerOn(server: McpServerDto): boolean {
    return server.shared ? server.shared.enabled : server.enabled;
}

export function isMcpToolEnabled(server: McpServerDto, tool: McpToolDto): boolean {
    return !server.disabled_tools.includes(tool.name);
}

export function enabledMcpToolCount(server: McpServerDto): number {
    return server.tools.filter(tool => isMcpToolEnabled(server, tool)).length;
}

/** Whether the model gets the server's tools in chats, see `list_usable_mcp_servers` in the API. */
export function isMcpServerUsed(server: McpServerDto): boolean {
    return isMcpServerOn(server) && server.status === McpServerStatus.READY && enabledMcpToolCount(server) !== 0;
}

/** E.g. "3 tools", or "1 of 3 tools enabled". */
export function mcpToolCountLabel(server: McpServerDto): string {
    const count = server.tools.length;
    const enabled = enabledMcpToolCount(server);
    return enabled === count
        ? t('mcpServers.page.toolCount', count)
        : t('mcpServers.page.toolCountEnabled', {enabled, count}, count);
}

export function mcpServerStatusLabel(status: McpServerStatus): string {
    switch (status) {
        case McpServerStatus.READY:
            return t('status.ready');
        case McpServerStatus.AUTHORIZATION_REQUIRED:
            return t('mcpServers.status.authorizationRequired');
        case McpServerStatus.FAILED:
            return t('status.failed');
        default:
            // from a newer server
            return t('mcpServers.status.unknown');
    }
}

/** E.g. "All MCP Servers", the name of the only server, or "3 MCP servers". */
export function mcpServerScopeSummary(scope: McpServerScope, servers: McpServerDto[]): string {
    if (scope.all_mcp_servers) {
        return t('chat.allMcpServers');
    }
    const ids = scope.mcp_server_ids;
    const name = ids.length === 1 ? servers.find(s => s.id === ids[0])?.name : undefined;
    return name ?? t('chat.mcpServerCount', ids.length);
}

/** A selection of all items or some of them, saved in this browser for the user's next new chat. */
export interface SavedScope {
    all: boolean;
    /** Ignored if `all`. */
    ids: string[];
}

/**
 * The selection saved as `json`, without the items that are gone (`existingIds` are those left). `null` if there is
 * none or it is invalid, and if all its items are gone, so the chat gets the default rather than none of them.
 */
export function parseSavedScope(json: string | null, existingIds: string[]): SavedScope | null {
    let value: unknown;
    try {
        value = JSON.parse(json ?? 'null');
    } catch {
        return null;
    }
    if (typeof value !== 'object' || value === null) {
        return null;
    }
    const {all, ids} = value as Record<string, unknown>;
    if (typeof all !== 'boolean' || !Array.isArray(ids) || !ids.every(id => typeof id === 'string')) {
        return null;
    }
    if (all) {
        return {all: true, ids: []};
    }
    const kept = ids.filter(id => existingIds.includes(id));
    return kept.length === 0 && ids.length > 0 ? null : {all: false, ids: kept};
}

/** Followed by the user's id, since the ids are theirs. */
const REPOSITORY_SCOPE_KEY = 'newChatRepositories';
const MCP_SERVER_SCOPE_KEY = 'newChatMcpServers';

function readSavedScope(key: string, userId: string, existingIds: string[]): SavedScope | null {
    try {
        return parseSavedScope(localStorage.getItem(`${key}:${userId}`), existingIds);
    } catch {
        return null;
    }
}

function writeSavedScope(key: string, userId: string, scope: SavedScope) {
    try {
        localStorage.setItem(`${key}:${userId}`, JSON.stringify(scope.all ? {all: true, ids: []} : scope));
    } catch {
        // only a convenience
    }
}

/** The repositories the user last selected for a new chat in this browser, see {@link parseSavedScope}. */
export function readRepositoryScope(userId: string, repositories: RepositoryDto[]): RepositoryScope | null {
    const scope = readSavedScope(REPOSITORY_SCOPE_KEY, userId, repositories.map(r => r.id));
    return scope && {all_repositories: scope.all, repository_ids: scope.ids};
}

export function writeRepositoryScope(userId: string, scope: RepositoryScope) {
    writeSavedScope(REPOSITORY_SCOPE_KEY, userId, {all: scope.all_repositories, ids: scope.repository_ids});
}

/** Like {@link readRepositoryScope}, `servers` are the ones that can be selected. */
export function readMcpServerScope(userId: string, servers: McpServerDto[]): McpServerScope | null {
    const scope = readSavedScope(MCP_SERVER_SCOPE_KEY, userId, servers.map(s => s.id));
    return scope && {all_mcp_servers: scope.all, mcp_server_ids: scope.ids};
}

export function writeMcpServerScope(userId: string, scope: McpServerScope) {
    writeSavedScope(MCP_SERVER_SCOPE_KEY, userId, {all: scope.all_mcp_servers, ids: scope.mcp_server_ids});
}

/**
 * The model that answers, like the server picks it: the first of `ids` that exists (e.g. the
 * chat's model, then the user's), else the default model.
 */
export function resolveModel(models: ModelDto[], ...ids: (string | null | undefined)[]): ModelDto | null {
    for (const id of ids) {
        const model = id ? models.find(m => m.id === id) : undefined;
        if (model) {
            return model;
        }
    }
    return models.find(m => m.is_default) ?? null;
}

export function trimmedOrNull(input: string | null | undefined): string | null {
    const trimmed = input?.trim();
    return trimmed ? trimmed : null;
}

/**
 * The number of characters (code points) like the server counts them for length limits, e.g. 1
 * for an emoji, which `text.length` counts as 2 (UTF-16 code units).
 */
export function charCount(text: string): number {
    return Array.from(text).length;
}

/** E.g. "12 Oct 2026, 14:03" in the UI's locale. */
export function formatDateTime(iso: string | null): string {
    if (!iso) {
        return '-';
    }
    return new Date(iso).toLocaleString(formatLocale(), {dateStyle: 'medium', timeStyle: 'short'});
}

/** E.g. "5 minutes ago" or "in 2 hours". */
export function formatRelative(iso: string | null): string {
    if (!iso) {
        return '-';
    }
    const seconds = Math.round((new Date(iso).getTime() - Date.now()) / 1000);
    const units: [Intl.RelativeTimeFormatUnit, number][] = [
        ['day', 86400], ['hour', 3600], ['minute', 60], ['second', 1],
    ];
    const format = new Intl.RelativeTimeFormat(formatLocale(), {numeric: 'auto'});
    for (const [unit, size] of units) {
        if (Math.abs(seconds) >= size || unit === 'second') {
            return format.format(Math.round(seconds / size), unit);
        }
    }
    return '-';
}

export function shortSha(sha: string | null): string {
    return sha ? sha.substring(0, 7) : '-';
}

/** E.g. "1.2 MB" in the UI's locale, with decimal units like GitLab and Forgejo. */
export function formatBytes(bytes: number | null): string {
    if (bytes === null) {
        return '-';
    }
    const units = ['byte', 'kilobyte', 'megabyte', 'gigabyte', 'terabyte'];
    const exponent = Math.min(Math.floor(Math.log10(Math.max(bytes, 1)) / 3), units.length - 1);
    return new Intl.NumberFormat(formatLocale(), {
        style: 'unit',
        unit: units[exponent],
        unitDisplay: 'short',
        maximumFractionDigits: exponent === 0 ? 0 : 1,
    }).format(bytes / 1000 ** exponent);
}

/** Git and LFS together in bytes, like GitLab and Forgejo show it, `null` until the first sync. */
export function repositorySize(repository: RepositoryDto): number | null {
    const {git_size, lfs_size} = repository;
    return git_size === null || lfs_size === null ? null : git_size + lfs_size;
}

/** The last segment of a path, e.g. `guide.md` for `docs/guide.md`. */
export function fileName(path: string): string {
    return path.replace(/\/+$/, '').split('/').pop() || path;
}

/** The `path` input of a tool call without empty and `.` segments, or null if it has none. */
export function toolCallPath(toolCall: ToolCallSummaryDto): string | null {
    const path = toolCall.input?.path;
    return typeof path === 'string' ? path.split('/').filter(s => s && s !== '.').join('/') : null;
}

/** The files the model showed in an answer with `present_file_to_user`, each once. */
export function presentedFiles(message: MessageDto): { toolCall: ToolCallSummaryDto, path: string }[] {
    const files = new Map<string, { toolCall: ToolCallSummaryDto, path: string }>();
    for (const toolCall of message.tool_calls) {
        const path = toolCallPath(toolCall);
        if (toolCall.name !== 'present_file_to_user' || toolCall.status !== ToolCallStatus.COMPLETED
            || path === null) {
            continue;
        }
        const key = `${toolCall.repository_id}:${path}`;
        if (!files.has(key)) {
            files.set(key, {toolCall, path});
        }
    }
    return [...files.values()];
}

/** A file dropped into the composer, uploading while `uploaded` is `null`. */
export interface PendingAttachment {
    /** Tells uploads apart, so a finished one only updates the attachment it started. */
    key: number;
    file_name: string;
    size: number;
    uploaded: AttachmentDto | null;
}

/** A tool of an MCP server in a tool call, see {@link parseMcpToolName}. */
export interface McpToolName {
    /** The slug of the server's name: lowercase letters, digits and single `_`. */
    server: string;
    /** As the server names it, may contain `__` itself. */
    tool: string;
}

/**
 * The server and tool of a tool call's `name` if it is a tool of an MCP server (`mcp__{server}__{tool}`), `null` for
 * the built-in tools. The server's slug never contains `__`, so the first one after it ends it.
 */
export function parseMcpToolName(name: string): McpToolName | null {
    const match = /^mcp__(.+?)__(.+)$/.exec(name);
    return match ? {server: match[1]!, tool: match[2]!} : null;
}

/** The tools that propose commits, shown with `ProposedCommitPanel`. */
export const CHANGE_TOOLS = ['change_file', 'move_files', 'save_attachment'];

/** The icon of each of `CHANGE_TOOLS`. */
export const CHANGE_ICONS: Record<string, string> = {
    change_file: 'mdi-pencil-outline',
    move_files: 'mdi-file-move-outline',
    save_attachment: 'mdi-file-upload-outline',
};

/** The `moves` input of a `move_files` call with their paths like {@link toolCallPath}, empty for other calls. */
export function toolCallMoves(toolCall: ToolCallSummaryDto): FileMoveDto[] {
    const moves = toolCall.input?.moves;
    if (toolCall.name !== 'move_files' || !Array.isArray(moves)) {
        return [];
    }
    const normalize = (path: unknown) =>
        typeof path === 'string' ? path.split('/').filter(s => s && s !== '.').join('/') : '';
    return moves.map(m => ({from: normalize(m?.from), to: normalize(m?.to)}));
}

/**
 * The changes the model proposed in an answer with `change_file`, the moves it proposed with
 * `move_files` (`path` is where the first one moves to), and the attachments it proposed to store
 * with `save_attachment`. A later call for the same file, the same attachment, or moves in the same
 * repository, replaces an earlier one.
 */
export function proposedChanges(message: MessageDto): { toolCall: ToolCallSummaryDto, path: string }[] {
    const changes = new Map<string, { toolCall: ToolCallSummaryDto, path: string }>();
    for (const toolCall of message.tool_calls) {
        const path = toolCall.name === 'move_files' ? toolCallMoves(toolCall)[0]?.to ?? null : toolCallPath(toolCall);
        if (!CHANGE_TOOLS.includes(toolCall.name) || toolCall.status !== ToolCallStatus.COMPLETED
            || path === null) {
            continue;
        }
        const key = toolCall.name === 'save_attachment' ? `attachment:${toolCall.input?.attachment}`
            : toolCall.name === 'move_files' ? `${toolCall.repository_id}:moves`
                : `${toolCall.repository_id}:${path}`;
        changes.delete(key);
        changes.set(key, {toolCall, path});
    }
    return [...changes.values()];
}

/** Choices for `poll_interval_seconds` (the API requires at least 60), for a `computed`. */
export function pollIntervalOptions(): { title: string, value: number }[] {
    return [
        {title: t('repositories.pollInterval.minute'), value: 60},
        {title: t('repositories.pollInterval.minutes5'), value: 300},
        {title: t('repositories.pollInterval.minutes15'), value: 900},
        {title: t('repositories.pollInterval.hour'), value: 3600},
        {title: t('repositories.pollInterval.hours6'), value: 21600},
        {title: t('repositories.pollInterval.daily'), value: 86400},
    ];
}

export function formatPollInterval(seconds: number): string {
    return pollIntervalOptions().find(o => o.value === seconds)?.title
        ?? t('repositories.pollInterval.seconds', {seconds});
}

/** The symbol of an ISO 4217 code in the UI's locale, e.g. "$" for USD, or the code itself. */
function currencySymbol(code: string): string {
    try {
        const parts = new Intl.NumberFormat(formatLocale(), {style: 'currency', currency: code, currencyDisplay: 'narrowSymbol'})
            .formatToParts(0);
        return parts.find(p => p.type === 'currency')?.value ?? code;
    } catch {
        return code;
    }
}

/**
 * The currencies in circulation (ISO 4217 list one without funds, precious metals and test codes).
 * `Intl.supportedValuesOf('currency')` also has historical ones, such as AFA, and units such as XBA.
 */
const CURRENCIES = new Set([
    'AED', 'AFN', 'ALL', 'AMD', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN', 'BAM', 'BBD', 'BDT', 'BHD', 'BIF', 'BMD',
    'BND', 'BOB', 'BRL', 'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY', 'COP', 'CRC',
    'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP', 'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL',
    'GHS', 'GIP', 'GMD', 'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR', 'IQD', 'IRR',
    'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF', 'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP',
    'LKR', 'LRD', 'LSL', 'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR', 'MVR', 'MWK',
    'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR', 'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR',
    'PLN', 'PYG', 'QAR', 'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD', 'SHP', 'SLE',
    'SOS', 'SRD', 'SSP', 'STN', 'SVC', 'SYP', 'SZL', 'THB', 'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD',
    'TZS', 'UAH', 'UGX', 'USD', 'UYU', 'UZS', 'VED', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XCG', 'XOF',
    'XPF', 'YER', 'ZAR', 'ZMW', 'ZWG',
]);

/**
 * The flag-icons code of the country (or `eu`) whose code starts an ISO 4217 code, e.g. `us` for USD.
 * `null` for supranational currencies (X..) and codes not in {@link CURRENCIES}.
 */
function currencyFlag(code: string): string | null {
    if (!CURRENCIES.has(code) || code.startsWith('X')) {
        return null;
    }
    return code.slice(0, 2).toLowerCase();
}

/** One option per currency in circulation, e.g. "$ US Dollar (USD)", plus `current` if it is missing. */
export function currencyOptions(current: string | null): {title: string, value: string, flag: string | null}[] {
    const names = new Intl.DisplayNames(formatLocale(), {type: 'currency'});
    const codes = new Set(CURRENCIES);
    if (current) {
        codes.add(current);
    }
    return [...codes]
        .map(code => ({code, name: names.of(code) ?? code, symbol: currencySymbol(code)}))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map(({code, name, symbol}) => ({
            title: symbol === code ? `${name} (${code})` : `${symbol} ${name} (${code})`,
            value: code,
            flag: currencyFlag(code),
        }));
}

/**
 * E.g. "$0.03" in the UI's locale, rounded to the currency's minor unit. Costs below it keep one
 * significant digit, e.g. "$0.0003" instead of "$0.00".
 */
export function formatCost(amount: string, currency: string): string {
    const value = Number(amount);
    try {
        const format = new Intl.NumberFormat(formatLocale(), {style: 'currency', currency});
        const smallest = 10 ** -(format.resolvedOptions().maximumFractionDigits ?? 2);
        if (value > 0 && value < smallest) {
            return new Intl.NumberFormat(formatLocale(), {style: 'currency', currency, maximumSignificantDigits: 1}).format(value);
        }
        return format.format(value);
    } catch {
        return `${amount} ${currency}`;
    }
}

/**
 * E.g. "$0.004125" in the UI's locale, with all the decimals of the amount (but at least those of the
 * currency's minor unit).
 */
export function formatExactCost(amount: string, currency: string): string {
    const decimals = amount.split('.')[1]?.length ?? 0;
    try {
        const minimum = new Intl.NumberFormat(formatLocale(), {style: 'currency', currency}).resolvedOptions().minimumFractionDigits ?? 2;
        const format = new Intl.NumberFormat(formatLocale(), {
            style: 'currency',
            currency,
            minimumFractionDigits: minimum,
            maximumFractionDigits: Math.min(Math.max(decimals, minimum), 100),
        });
        // a numeric string is formatted exactly, without rounding to a float first
        return format.format(amount as `${number}`);
    } catch {
        return `${amount} ${currency}`;
    }
}

/** Input (including the cache) and output. */
export function totalTokens(usage: UsageDto): number {
    return usage.input_tokens + usage.cache_read_tokens + usage.cache_write_tokens + usage.output_tokens;
}

/** E.g. "850 T.", "3.6k T." or "1.2M T.", the same in every language except for the decimal separator. */
export function formatTokens(tokens: number): string {
    const units = ['', 'k', 'M', 'B'];
    let exponent = 0;
    // the next unit as soon as the value would round to 1000, e.g. "1M" rather than "1000k"
    while (exponent < units.length - 1 && Math.abs(tokens) / 1000 ** exponent >= 999.95) {
        exponent++;
    }
    const value = new Intl.NumberFormat(formatLocale(), {maximumFractionDigits: 1}).format(tokens / 1000 ** exponent);
    return `${value}${units[exponent]} T.`;
}

/** A price per million tokens with all its decimals, e.g. "$0.075". */
export function formatPrice(price: string, currency: string): string {
    try {
        return new Intl.NumberFormat(formatLocale(), {style: 'currency', currency, maximumFractionDigits: 6}).format(Number(price));
    } catch {
        return `${price} ${currency}`;
    }
}

const MAX_USER_NAME_LENGTH = 64;

/**
 * Why the API would reject this trimmed user name and email (`validate_user_name`, `validate_email`), `null` if
 * they are valid. An empty email means none.
 */
export function userNameOrEmailError(userName: string, email: string): string | null {
    if (!userName) {
        return t('user.missingUserName');
    }
    if (userName.length > MAX_USER_NAME_LENGTH || !/^[A-Za-z0-9._-]+$/.test(userName)) {
        return t('user.userNameInvalid', {max: MAX_USER_NAME_LENGTH});
    }
    if (email && !isValidEmail(email)) {
        return t('user.emailInvalid');
    }
    return null;
}

function isValidEmail(value: string): boolean {
    const parts = value.split('@');
    if (parts.length < 2 || /\s/.test(value)) {
        return false;
    }
    const local = parts[0]!;
    const domain = parts.slice(1).join('@');
    return !!local && domain.includes('.') && !domain.startsWith('.') && !domain.endsWith('.');
}
