use reqwest::dns::{Addrs, Name, Resolve, Resolving};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};
use std::time::Duration;
use url::{Host, Url};

const RESOLVE_TIMEOUT: Duration = Duration::from_secs(5);

/// Whether `ip` is a globally routable unicast address.
/// Remotes resolving to anything else are rejected so the server cannot be used to reach
/// loopback, the private network or cloud metadata endpoints.
pub(crate) fn is_public_ip(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(ip) => is_public_ipv4(ip),
        IpAddr::V6(ip) => is_public_ipv6(ip),
    }
}

fn is_public_ipv4(ip: Ipv4Addr) -> bool {
    let [a, b, c, _] = ip.octets();
    !(a == 0                                    // "this" network
        || a == 10                              // private
        || (a == 100 && (64..128).contains(&b)) // carrier-grade NAT
        || a == 127                             // loopback
        || (a == 169 && b == 254)               // link-local, cloud metadata
        || (a == 172 && (16..32).contains(&b))  // private
        || (a == 192 && b == 0 && c == 0)       // IETF protocol assignments
        || (a == 192 && b == 0 && c == 2)       // documentation
        || (a == 192 && b == 168)               // private
        || (a == 198 && (18..20).contains(&b))  // benchmarking
        || (a == 198 && b == 51 && c == 100)    // documentation
        || (a == 203 && b == 0 && c == 113)     // documentation
        || a >= 224) // multicast, reserved, broadcast
}

fn is_public_ipv6(ip: Ipv6Addr) -> bool {
    if let Some(v4) = ip.to_ipv4_mapped() {
        return is_public_ipv4(v4);
    }

    let segments = ip.segments();
    let embedded_v4 = |high: u16, low: u16| {
        Ipv4Addr::new((high >> 8) as u8, high as u8, (low >> 8) as u8, low as u8)
    };

    match segments {
        // NAT64 well-known prefix 64:ff9b::/96
        [0x64, 0xff9b, 0, 0, 0, 0, high, low] => is_public_ipv4(embedded_v4(high, low)),
        // 6to4 2002::/16
        [0x2002, high, low, ..] => is_public_ipv4(embedded_v4(high, low)),
        // unspecified, loopback, IPv4-compatible (deprecated)
        [0, 0, 0, 0, 0, 0, _, _] => false,
        // discard-only 100::/64
        [0x100, 0, 0, 0, ..] => false,
        // Teredo 2001::/32, documentation 2001:db8::/32
        [0x2001, 0, ..] | [0x2001, 0xdb8, ..] => false,
        // unique local fc00::/7, link-local fe80::/10, multicast ff00::/8
        [first, ..] => {
            (first & 0xfe00) != 0xfc00 && (first & 0xffc0) != 0xfe80 && (first & 0xff00) != 0xff00
        }
    }
}

/// Whether the host is a domain, checked by [`PublicResolver`], or a public IP address.
pub(crate) fn has_public_host(url: &Url) -> bool {
    match url.host() {
        Some(Host::Domain(_)) => true,
        Some(Host::Ipv4(ip)) => is_public_ip(ip.into()),
        Some(Host::Ipv6(ip)) => is_public_ip(ip.into()),
        None => false,
    }
}

/// Resolves hosts like the system resolver, but fails unless every address is public.
/// Connections use the checked addresses, so a second lookup cannot be answered
/// with a private address (DNS rebinding).
pub(crate) struct PublicResolver;

impl Resolve for PublicResolver {
    fn resolve(&self, name: Name) -> Resolving {
        Box::pin(async move {
            let lookup = tokio::net::lookup_host((name.as_str(), 0));
            let addresses: Vec<SocketAddr> = tokio::time::timeout(RESOLVE_TIMEOUT, lookup)
                .await??
                .collect();
            if addresses.is_empty() || !addresses.iter().all(|a| is_public_ip(a.ip())) {
                return Err(NotPublic.into());
            }
            let addresses: Addrs = Box::new(addresses.into_iter());
            Ok(addresses)
        })
    }
}

/// The error of [`PublicResolver`], found in the sources of a `reqwest::Error`.
#[derive(Debug, thiserror::Error)]
#[error("the host does not resolve to public addresses only")]
pub(crate) struct NotPublic;

/// Whether `error` or one of its sources is [`NotPublic`].
pub(crate) fn is_not_public(error: &(dyn std::error::Error + 'static)) -> bool {
    let mut source = Some(error);
    while let Some(e) = source {
        if e.is::<NotPublic>() {
            return true;
        }
        source = e.source();
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    fn public(ip: &str) -> bool {
        is_public_ip(ip.parse().unwrap())
    }

    #[test]
    fn accepts_public_addresses() {
        for ip in [
            "140.82.121.3",
            "1.1.1.1",
            "2606:4700::1111",
            "::ffff:140.82.121.3",
            "64:ff9b::8c52:7903",
        ] {
            assert!(public(ip), "{ip} should be public");
        }
    }

    #[test]
    fn rejects_internal_addresses() {
        for ip in [
            "0.0.0.0",
            "10.1.2.3",
            "100.64.0.1",
            "127.0.0.1",
            "169.254.169.254",
            "172.16.0.1",
            "172.31.255.255",
            "192.168.1.1",
            "198.18.0.1",
            "224.0.0.1",
            "255.255.255.255",
            "::",
            "::1",
            "::ffff:127.0.0.1",
            "::ffff:10.0.0.1",
            "64:ff9b::a00:1",
            "2002:a00:1::",
            "2001:db8::1",
            "fc00::1",
            "fd12:3456::1",
            "fe80::1",
            "ff02::1",
        ] {
            assert!(!public(ip), "{ip} should not be public");
        }
    }
}
