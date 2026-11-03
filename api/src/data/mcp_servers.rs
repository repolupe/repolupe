use crate::dto::mcp::McpServerKind;

/// [`McpServerSuggestionDto`](crate::dto::mcp::McpServerSuggestionDto) as a constant.
pub(crate) struct Suggestion {
    pub(crate) name: &'static str,
    pub(crate) url: &'static str,
    pub(crate) kind: McpServerKind,
    pub(crate) country_code: &'static str,
}

pub(crate) const SUGGESTIONS: &[Suggestion] = &[
    // Search
    Suggestion {
        name: "TinyFish",
        url: "https://agent.tinyfish.ai/mcp",
        kind: McpServerKind::Search,
        country_code: "US",
    },
    Suggestion {
        name: "Exa",
        url: "https://mcp.exa.ai/mcp",
        kind: McpServerKind::Search,
        country_code: "US",
    },
    Suggestion {
        name: "Parallel Search",
        url: "https://search-mcp.parallel.ai/mcp",
        kind: McpServerKind::Search,
        country_code: "US",
    },
    Suggestion {
        name: "SearchAPI",
        url: "https://www.searchapi.io/mcp",
        kind: McpServerKind::Search,
        country_code: "US",
    },
    // Web scraping
    Suggestion {
        name: "Apify",
        url: "https://mcp.apify.com",
        kind: McpServerKind::WebScraping,
        country_code: "CZ",
    },
    Suggestion {
        name: "Simplescraper",
        url: "https://mcp.simplescraper.io/mcp",
        kind: McpServerKind::WebScraping,
        country_code: "IE",
    },
    // Documentation
    Suggestion {
        name: "Context7",
        url: "https://mcp.context7.com/mcp",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "DeepWiki",
        url: "https://mcp.deepwiki.com/mcp",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "GitMCP",
        url: "https://gitmcp.io/docs",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "Microsoft Learn",
        url: "https://learn.microsoft.com/api/mcp",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "AWS Knowledge",
        url: "https://knowledge-mcp.global.api.aws",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "Cloudflare Docs",
        url: "https://docs.mcp.cloudflare.com/mcp",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    Suggestion {
        name: "Astro Docs",
        url: "https://mcp.docs.astro.build/mcp",
        kind: McpServerKind::Documentation,
        country_code: "US",
    },
    // Dev tools
    Suggestion {
        name: "GitHub",
        url: "https://api.githubcopilot.com/mcp",
        kind: McpServerKind::DevTools,
        country_code: "US",
    },
    Suggestion {
        name: "Sentry",
        url: "https://mcp.sentry.dev/mcp",
        kind: McpServerKind::DevTools,
        country_code: "US",
    },
    Suggestion {
        name: "Stack Overflow",
        url: "https://mcp.stackoverflow.com",
        kind: McpServerKind::DevTools,
        country_code: "US",
    },
    Suggestion {
        name: "Hugging Face",
        url: "https://hf.co/mcp",
        kind: McpServerKind::DevTools,
        country_code: "US",
    },
    // Cloud
    Suggestion {
        name: "Vercel",
        url: "https://mcp.vercel.com/",
        kind: McpServerKind::Cloud,
        country_code: "US",
    },
    Suggestion {
        name: "Netlify",
        url: "https://netlify-mcp.netlify.app/mcp",
        kind: McpServerKind::Cloud,
        country_code: "US",
    },
    // Database
    Suggestion {
        name: "Supabase",
        url: "https://mcp.supabase.com/mcp",
        kind: McpServerKind::Database,
        country_code: "US",
    },
    Suggestion {
        name: "Neon",
        url: "https://mcp.neon.tech/mcp",
        kind: McpServerKind::Database,
        country_code: "US",
    },
    Suggestion {
        name: "Prisma Postgres",
        url: "https://mcp.prisma.io/mcp",
        kind: McpServerKind::Database,
        country_code: "DE",
    },
    Suggestion {
        name: "Airtable",
        url: "https://mcp.airtable.com/mcp",
        kind: McpServerKind::Database,
        country_code: "US",
    },
    // Observability
    Suggestion {
        name: "Polar Signals",
        url: "https://api.polarsignals.com/api/mcp/",
        kind: McpServerKind::Observability,
        country_code: "DE",
    },
    // Project management / productivity
    Suggestion {
        name: "Linear",
        url: "https://mcp.linear.app/mcp",
        kind: McpServerKind::ProjectManagement,
        country_code: "US",
    },
    Suggestion {
        name: "Notion",
        url: "https://mcp.notion.com/mcp",
        kind: McpServerKind::Productivity,
        country_code: "US",
    },
    // CRM
    Suggestion {
        name: "Attio",
        url: "https://mcp.attio.com/mcp",
        kind: McpServerKind::Crm,
        country_code: "GB",
    },
    Suggestion {
        name: "HubSpot",
        url: "https://app.hubspot.com/mcp/v1/http",
        kind: McpServerKind::Crm,
        country_code: "US",
    },
    // Payments / finance
    Suggestion {
        name: "Stripe",
        url: "https://mcp.stripe.com/",
        kind: McpServerKind::Payments,
        country_code: "US",
    },
    Suggestion {
        name: "Morningstar",
        url: "https://mcp.morningstar.com/mcp",
        kind: McpServerKind::Finance,
        country_code: "US",
    },
    // Design
    Suggestion {
        name: "Canva",
        url: "https://mcp.canva.com/mcp",
        kind: McpServerKind::Design,
        country_code: "AU",
    },
    Suggestion {
        name: "Figma",
        url: "https://mcp.figma.com/mcp",
        kind: McpServerKind::Design,
        country_code: "US",
    },
    // Automation
    Suggestion {
        name: "Zapier",
        url: "https://mcp.zapier.com/api/mcp/mcp",
        kind: McpServerKind::Automation,
        country_code: "US",
    },
    // Knowledge / compute
    Suggestion {
        name: "Wolfram",
        url: "https://agenttools.wolfram.com/mcp",
        kind: McpServerKind::Knowledge,
        country_code: "US",
    },
    // Maps / travel
    Suggestion {
        name: "Google Maps",
        url: "https://mapstools.googleapis.com/mcp",
        kind: McpServerKind::Maps,
        country_code: "US",
    },
    Suggestion {
        name: "Ferryhopper",
        url: "https://mcp.ferryhopper.com/mcp",
        kind: McpServerKind::Travel,
        country_code: "GR",
    },
];
