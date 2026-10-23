import {defineNuxtRouteMiddleware, navigateTo} from "#app";
import {useAuthChecked, useUser} from "~/composables/states";
import {getMe} from "~/utils/api";
import {UserRole} from "~/utils/model";
import {DEMO} from "~/utils/demo";

/**
 * Restores the session from the HttpOnly cookie on the first navigation, then sends logged-out
 * users to `/login`, logged-in users away from it, users who must change their password to `/change-password` (and
 * the others away from it), non-admins away from `/settings/admin`, and users who cannot manage repositories away
 * from `/settings/repositories`. The demo has no settings.
 */
export default defineNuxtRouteMiddleware(async (to) => {
    const user = useUser();
    const authChecked = useAuthChecked();

    if (!authChecked.value) {
        try {
            user.value = await getMe();
        } catch {
            user.value = null;
        }
        authChecked.value = true;
    }

    if (to.path === '/login') {
        return user.value ? navigateTo('/') : undefined;
    }

    if (!user.value) {
        return navigateTo('/login');
    }

    if (user.value.must_change_password !== (to.path === '/change-password')) {
        return navigateTo(user.value.must_change_password ? '/change-password' : '/');
    }

    if (DEMO && to.path.startsWith('/settings')) {
        return navigateTo('/');
    }

    if (to.path.startsWith('/settings/admin') && user.value.role !== UserRole.ADMIN) {
        return navigateTo('/');
    }

    if (to.path.startsWith('/settings/repositories') && !user.value.can_manage_repositories) {
        return navigateTo('/');
    }
});
