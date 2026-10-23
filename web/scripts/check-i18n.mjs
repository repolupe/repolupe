// Checks the locale files against each other and against the keys used in app/:
// every locale has the keys of en in the same order, every key passed to t/$t/keypath
// exists, and every key is used (as a quoted literal anywhere, e.g. a keypath chosen in script).
import {readdirSync, readFileSync} from 'node:fs';
import {join} from 'node:path';

const LOCALES_DIR = 'i18n/locales';
const SOURCE_DIR = 'app';

function flatten(obj, prefix = '') {
    return Object.entries(obj).flatMap(([key, value]) => typeof value === 'object'
        ? flatten(value, `${prefix}${key}.`)
        : [`${prefix}${key}`]);
}

function sources(dir) {
    return readdirSync(dir, {withFileTypes: true}).flatMap(entry => entry.isDirectory()
        ? sources(join(dir, entry.name))
        : [readFileSync(join(dir, entry.name), 'utf8')]);
}

const errors = [];
const locales = Object.fromEntries(readdirSync(LOCALES_DIR).filter(f => f.endsWith('.json')).map(f =>
    [f.replace('.json', ''), flatten(JSON.parse(readFileSync(join(LOCALES_DIR, f), 'utf8')))]));
const keys = locales.en;
const keySet = new Set(keys);

for (const [locale, localeKeys] of Object.entries(locales)) {
    if (localeKeys.join('\n') !== keys.join('\n')) {
        const localeSet = new Set(localeKeys);
        const missing = keys.filter(k => !localeSet.has(k));
        const extra = localeKeys.filter(k => !keySet.has(k));
        errors.push(missing.length || extra.length
            ? `${locale}: missing ${missing.join(', ') || '-'}; not in en: ${extra.join(', ') || '-'}`
            : `${locale}: keys are not in the order of en`);
    }
}

const code = sources(SOURCE_DIR).join('\n');
const called = new Set([...code.matchAll(/\bt\(\s*['"`]([\w.]+)['"`]|keypath="([\w.]+)"/g)].map(m => m[1] ?? m[2]));
const literals = new Set([...code.matchAll(/['"`]([\w.]+)['"`]/g)].map(m => m[1]));
for (const key of called) {
    if (!keySet.has(key)) errors.push(`unknown key: ${key}`);
}
for (const key of keys) {
    if (!literals.has(key)) errors.push(`unused key: ${key}`);
}

if (errors.length) {
    console.error(errors.join('\n'));
    process.exit(1);
}
console.log(`${keys.length} keys in ${Object.keys(locales).length} locales, all used`);
