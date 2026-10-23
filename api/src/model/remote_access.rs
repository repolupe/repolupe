use crate::dto::user::UserRole;

/// Which remotes a repository may contact, decided by the role of its owner.
#[derive(Clone, Copy, Eq, PartialEq, Debug)]
pub enum RemoteAccess {
    /// https only, to hosts that resolve to public addresses, so users cannot make the
    /// server send requests into its own network (SSRF).
    Public,
    /// http or https to any host, e.g. a git server on the internal network. Only for
    /// repositories of admins.
    Unrestricted,
}

impl RemoteAccess {
    pub fn of(role: UserRole) -> Self {
        match role {
            UserRole::Admin => Self::Unrestricted,
            UserRole::User => Self::Public,
        }
    }
}
