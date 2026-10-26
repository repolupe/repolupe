import {computed} from "vue";
import {useNuxtApp, useState} from "#app";
import type {ChatDto, UserDto} from "~/utils/model";
import {getChats, getInstance, getMe} from "~/utils/api";

/** The default instance name. A renamed instance credits it on the start page. */
export const PRODUCT_NAME = 'Repolupe';

/**
 * `INSTANCE_NAME` of the API, `null` until loaded by {@link refreshInstanceName}, or {@link PRODUCT_NAME} if
 * that failed.
 */
export const useInstanceName = () => useState<string | null>('instanceName', () => null);

/** The instance name to show, {@link PRODUCT_NAME} until it is loaded. */
export const useInstanceTitle = () => {
    const instanceName = useInstanceName();
    return computed(() => instanceName.value ?? PRODUCT_NAME);
};

/** Loaded once by app.vue. Public, so it works before the login. */
export async function refreshInstanceName() {
    // useState needs the Nuxt context, which is gone after an await.
    const instanceName = useInstanceName();
    instanceName.value = (await getInstance()).name;
}

/** The logged-in user, `null` when logged out. */
export const useUser = () => useState<UserDto | null>('user', () => null);

/** Re-reads the user after an update, so the navigation and every page see the change. */
export async function refreshUser() {
    // useState needs the Nuxt context, which is gone after an await.
    const user = useUser();
    user.value = await getMe();
}

// A plain variable rather than useState, so the password stays out of the Nuxt state (and its devtools).
let loginPassword: string | null = null;

/**
 * Keeps the password of a login that requires a password change, so `/change-password` doesn't ask for it again.
 * Only in memory: a reload asks for it.
 */
export function rememberLoginPassword(password: string) {
    loginPassword = password;
}

/** Returns the password kept by {@link rememberLoginPassword} once, and forgets it. */
export function takeLoginPassword(): string | null {
    const password = loginPassword;
    loginPassword = null;
    return password;
}

/** Whether a chat shows a presented file next to it, which collapses the navigation on smaller desktops. */
export const useFilePresented = () => useState<boolean>('filePresented', () => false);

/** Whether the session cookie was checked (`GET /api/v1/me`) after the page loaded. */
export const useAuthChecked = () => useState<boolean>('authChecked', () => false);

/**
 * The first page of chats, shown in the navigation. Pages that create, rename or delete a
 * chat call {@link refreshChats}.
 */
export const useChats = () => useState<ChatDto[]>('chats', () => []);

/**
 * Where the chats older than {@link useChats} start, `null` if there are none, `undefined` until
 * loaded. Set by {@link refreshChats}.
 */
export const useOlderChatsCursor = () => useState<string | null | undefined>('olderChatsCursor', () => undefined);

export async function refreshChats() {
    // useState needs the Nuxt context, which is gone after an await.
    const chats = useChats();
    const olderCursor = useOlderChatsCursor();
    // fewer on mobile, where the navigation is a narrow overlay
    const limit = useNuxtApp().$display.mobile.value ? 5 : 10;
    const page = await getChats(null, limit);
    chats.value = page.items;
    olderCursor.value = page.next_cursor;
}
