import {describe, expect, it} from 'vitest';
import {parseMcpToolName} from '~/utils/utils';

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
