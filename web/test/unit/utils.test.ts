import {afterEach, describe, expect, it} from 'vitest';
import {formatTokens, parseMcpToolName, parseSavedScope} from '~/utils/utils';
import {setFormatLocale} from '~/utils/i18n';

describe('parseMcpToolName', () => {
    it('splits the server slug and the tool name', () => {
        expect(parseMcpToolName('mcp__github__create_issue')).toEqual({server: 'github', tool: 'create_issue'});
    });

    it('keeps single underscores in the server slug', () => {
        expect(parseMcpToolName('mcp__my_server_2__search')).toEqual({server: 'my_server_2', tool: 'search'});
    });

    it('ends the server slug at the first double underscore, so the tool may contain more', () => {
        expect(parseMcpToolName('mcp__docs__files__read')).toEqual({server: 'docs', tool: 'files__read'});
    });

    it('returns null for built-in tools and incomplete names', () => {
        expect(parseMcpToolName('read_file')).toBeNull();
        expect(parseMcpToolName('mcp__github')).toBeNull();
        expect(parseMcpToolName('mcp__github__')).toBeNull();
        expect(parseMcpToolName('mcp____tool')).toBeNull();
        expect(parseMcpToolName('x_mcp__github__search')).toBeNull();
    });
});

describe('parseSavedScope', () => {
    it('keeps all', () => {
        expect(parseSavedScope('{"all":true,"ids":[]}', ['a'])).toEqual({all: true, ids: []});
    });

    it('drops the items that are gone', () => {
        expect(parseSavedScope('{"all":false,"ids":["a","b"]}', ['b', 'c'])).toEqual({all: false, ids: ['b']});
    });

    it('keeps none of them if none were selected', () => {
        expect(parseSavedScope('{"all":false,"ids":[]}', ['a'])).toEqual({all: false, ids: []});
    });

    it('returns null if all selected items are gone', () => {
        expect(parseSavedScope('{"all":false,"ids":["a"]}', ['b'])).toBeNull();
    });

    it('returns null for nothing saved and invalid values', () => {
        expect(parseSavedScope(null, ['a'])).toBeNull();
        expect(parseSavedScope('{', ['a'])).toBeNull();
        expect(parseSavedScope('[]', ['a'])).toBeNull();
        expect(parseSavedScope('{"all":"yes","ids":[]}', ['a'])).toBeNull();
        expect(parseSavedScope('{"all":false,"ids":[1]}', ['a'])).toBeNull();
        expect(parseSavedScope('{"all":false}', ['a'])).toBeNull();
    });
});

describe('formatTokens', () => {
    const tokens = [0, 850, 999, 1000, 3600, 12345, 123456, 999949, 999950, 1234567, 2500000000];

    afterEach(() => setFormatLocale('en'));

    it('abbreviates the same in every language', () => {
        setFormatLocale('en');
        expect(tokens.map(formatTokens)).toEqual([
            '0 T.', '850 T.', '999 T.', '1k T.', '3.6k T.', '12.3k T.', '123.5k T.', '999.9k T.', '1M T.', '1.2M T.',
            '2.5B T.',
        ]);
    });

    it('localizes only the decimal separator', () => {
        setFormatLocale('de');
        expect(tokens.map(formatTokens)).toEqual([
            '0 T.', '850 T.', '999 T.', '1k T.', '3,6k T.', '12,3k T.', '123,5k T.', '999,9k T.', '1M T.', '1,2M T.',
            '2,5B T.',
        ]);
    });
});
