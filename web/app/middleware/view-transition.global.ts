import {defineNuxtRouteMiddleware} from "#app";

const isStart = (path: string) => path === '/';
const isChat = (path: string) => path.startsWith('/chat/') && path !== '/chat/older';

/**
 * Enables the view transition only between the start page and a chat, where it moves the
 * message input (see MessageInput). Other navigations would just crossfade, which feels slow.
 *
 * Runs before Nuxt's view transition plugin (a `beforeResolve` hook), which reads `to.meta`.
 */
export default defineNuxtRouteMiddleware((to, from) => {
    to.meta.viewTransition = (isStart(from.path) && isChat(to.path))
        || (isChat(from.path) && isStart(to.path));
});
