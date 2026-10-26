/** The names of the Vuetify themes in plugins/vuetify.ts, and `system` for the one matching the OS. */
export enum ThemeMode {
    SYSTEM = 'system',
    LIGHT = 'light',
    DARK = 'dark',
}

export const THEME_MODE_ICONS: Record<ThemeMode, string> = {
    [ThemeMode.SYSTEM]: 'mdi-brightness-auto',
    [ThemeMode.LIGHT]: 'mdi-white-balance-sunny',
    [ThemeMode.DARK]: 'mdi-weather-night',
};

const THEME_MODE_KEY = 'themeMode';

/** The mode chosen in this browser, {@link ThemeMode.SYSTEM} if none. */
export function readThemeMode(): ThemeMode {
    try {
        const value = localStorage.getItem(THEME_MODE_KEY);
        return Object.values(ThemeMode).find(mode => mode === value) ?? ThemeMode.SYSTEM;
    } catch {
        return ThemeMode.SYSTEM;
    }
}

export function writeThemeMode(mode: ThemeMode) {
    try {
        localStorage.setItem(THEME_MODE_KEY, mode);
    } catch {
        // only a convenience
    }
}
