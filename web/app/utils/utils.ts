import {
    ToolCallStatus,
    type AttachmentDto,
    type FileMoveDto,
    type MessageDto,
    type ModelDto,
    type RepositoryDto,
    type RepositoryScope,
    type ToolCallSummaryDto,
} from "~/utils/model";
import {formatLocale, t} from "~/utils/i18n";

let snackbarFunc: (text: string) => void = () => {};

export function initSnackbar(func: (text: string) => void) {
    snackbarFunc = func;
}

export function showSnackbar(text: string) {
    snackbarFunc(text);
}

/** E.g. "All Repositories". */
export function allRepositoriesTitle(): string {
    return t('chat.allRepositories');
}

/** E.g. "All Repositories", the name of the only repository, or "3 repositories". */
export function repositoryScopeSummary(scope: RepositoryScope, repositories: RepositoryDto[]): string {
    if (scope.all_repositories) {
        return allRepositoriesTitle();
    }
    const ids = scope.repository_ids;
    const name = ids.length === 1 ? repositories.find(r => r.id === ids[0])?.name : undefined;
    return name ?? t('chat.repositoryCount', ids.length);
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
 * E.g. "$0.03" in the UI's locale, rounded to the currency's minor unit. Costs below it show as
 * "<$0.01" instead of "$0.00".
 */
export function formatCost(amount: string, currency: string): string {
    const value = Number(amount);
    try {
        const format = new Intl.NumberFormat(formatLocale(), {style: 'currency', currency});
        const smallest = 10 ** -(format.resolvedOptions().maximumFractionDigits ?? 2);
        return value > 0 && value < smallest ? `<${format.format(smallest)}` : format.format(value);
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
