import {describe, expect, it} from 'vitest';
import {parseMcpToolName, parseSavedScope} from '~/utils/utils';

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
