# ITSM-Insights

You get paged at 2am about SQL-PROD-01. You've never touched it. You open ServiceNow, find 47 tickets spanning 18 months. Do you really have time to read them all right now?

**ITSM-Insights** connects to your ITSM platform, pulls the full ticket history for a server, application, or user, and uses AI to generate an actionable briefing in seconds. It also identifies recurring issues that keep generating tickets and finds knowledge gaps where KB articles should exist but don't.

## How It Works

```
ITSM Platform (ServiceNow / Jira / CSV)
        |
        v
   Query tickets for CI, user, or category
        |
        v
   Normalize ticket data to common schema
        |
        v
   AI analyzes patterns, summarizes history
        |
        v
   Actionable briefing + HTML dashboard
```

## Quick Start

### ServiceNow

```powershell
Import-Module ITSM-Insights

# Get the full story on a server in 30 seconds
Get-CIHistory -CIName 'SQL-PROD-01' `
    -Provider ServiceNow `
    -Instance 'company.service-now.com' `
    -Credential (Get-Credential) `
    -OutputPath '.\sql-prod-01-briefing.html'
```

### Jira Service Management

```powershell
Get-CIHistory -CIName 'SQL-PROD-01' `
    -Provider Jira `
    -BaseUrl 'https://company.atlassian.net' `
    -Email 'admin@company.com' `
    -ApiKey $env:JIRA_API_TOKEN `
    -OutputPath '.\briefing.html'
```

### CSV/JSON Export (Any ITSM)

```powershell
# Export your tickets from any ITSM tool as CSV or JSON, then:
Get-CIHistory -CIName 'SQL-PROD-01' `
    -Provider File `
    -FilePath '.\exported-tickets.json' `
    -OutputPath '.\briefing.html'
```

## Connection Setup

### ServiceNow

The module connects via the ServiceNow REST API (Table API). You need:

- Instance URL (e.g., `company.service-now.com`)
- A user account with read access to `incident`, `change_request`, `problem`, and `kb_knowledge` tables
- Authentication: Basic auth via `Get-Credential` or API key via `-ApiKey` / `$env:SNOW_API_KEY`

```powershell
# Basic auth
$cred = Get-Credential
Get-CIHistory -CIName 'WEB-01' -Instance 'company.service-now.com' -Credential $cred

# API key (via env var)
$env:SNOW_API_KEY = 'your-api-key-here'
Get-CIHistory -CIName 'WEB-01' -Instance 'company.service-now.com'
```

### Jira Service Management

The module connects via the Jira REST API v3. You need:

- Jira Cloud URL (e.g., `https://company.atlassian.net`)
- Email address for authentication
- API token from [Atlassian API tokens](https://id.atlassian.com/manage-profile/security/api-tokens)

```powershell
$env:JIRA_API_TOKEN = 'your-jira-api-token'
Get-CIHistory -CIName 'DB-PROD-01' -Provider Jira `
    -BaseUrl 'https://company.atlassian.net' `
    -Email 'admin@company.com'
```

### CSV/JSON File Import

Export tickets from any ITSM tool and import them directly. The module auto-detects common column name variations:

- `Ticket Number`, `Number`, `ID`, `Key` all map to ticket number
- `Summary`, `Title`, `Short Description` all map to description
- `Server`, `CI`, `Configuration Item`, `Hostname` all map to CI name

```powershell
Get-CIHistory -CIName 'APP-SRV-01' -Provider File -FilePath '.\tickets.csv'
```

## AI Provider Setup

ITSM-Insights supports multiple AI providers. The AI is used for summarization, pattern detection, and KB article drafting. Set your preferred provider and API key:

### Anthropic (Default)

```powershell
$env:ANTHROPIC_API_KEY = 'sk-ant-...'
# or
$env:LIVINGDOC_API_KEY = 'sk-ant-...'  # Shared with Infra-LivingDoc
```

### OpenAI

```powershell
$env:OPENAI_API_KEY = 'sk-...'
Get-CIHistory -CIName 'SQL-01' -AIProvider OpenAI -Provider File -FilePath '.\tickets.json'
```

### Ollama (Local LLM)

```powershell
# No API key needed — runs locally
Get-CIHistory -CIName 'SQL-01' -AIProvider Ollama -AIModel 'llama3.1:8b' -Provider File -FilePath '.\tickets.json'
```

### Custom Endpoint

```powershell
Get-CIHistory -CIName 'SQL-01' -AIProvider Custom `
    -AIEndpoint 'https://my-llm-proxy.company.com/v1/chat/completions' `
    -AIApiKey 'my-key' `
    -Provider File -FilePath '.\tickets.json'
```

### No AI (Raw Data Only)

```powershell
# Use -SkipAI to get structured ticket data without sending anything to an AI provider
Get-CIHistory -CIName 'SQL-01' -Provider File -FilePath '.\tickets.json' -SkipAI
```

## Use Cases

### Incident Response

You get paged about a server you've never worked on. Instead of reading 50 tickets:

```powershell
Get-CIHistory -CIName 'SQL-PROD-01' -Instance 'company.service-now.com' -Credential $cred
```

You get: executive summary, timeline of major events, recurring patterns, current open items, and risk assessment. Read it in 60 seconds instead of 60 minutes.

### Server Handoff / Knowledge Transfer

Handing off a server to a new team member:

```powershell
Get-CIHistory -CIName 'SQL-PROD-01' -Instance 'company.service-now.com' -Credential $cred `
    -MonthsBack 24 -OutputPath '.\SQL-PROD-01-handoff.html'
```

### Recurring Issue Elimination

Stop fighting the same fires. Find patterns across your tickets:

```powershell
Get-RecurringIssues -CIName 'SQL-PROD-01' -Provider File -FilePath '.\tickets.json' `
    -MinOccurrences 2 -OutputPath '.\recurring-issues.html'
```

The AI identifies repeated root causes and suggests permanent fixes.

### Knowledge Base Maintenance

Find tickets that keep getting raised because there is no KB article:

```powershell
$gaps = Get-KnowledgeGaps -Instance 'company.service-now.com' -Credential $cred

# Review AI-generated article drafts locally first
$gaps | Sync-KnowledgeArticles -ReviewOnly -OutputDirectory '.\kb-drafts'

# Push approved articles to ServiceNow as drafts
$gaps | Sync-KnowledgeArticles -Instance 'company.service-now.com' `
    -Credential $cred -KnowledgeBase 'your-kb-sys-id'
```

Articles are always created as **DRAFT** in ServiceNow. A human must review and publish them.

### User Workload Analysis

Understand a user's ticket interaction patterns:

```powershell
Get-UserTicketHistory -UserIdentity 'john.doe@company.com' `
    -Instance 'company.service-now.com' -Credential $cred `
    -Role All -MonthsBack 12
```

## Exported Functions

| Function | Description |
|----------|-------------|
| `Get-CIHistory` | Full ticket history summary for a server/CI |
| `Get-UserTicketHistory` | All tickets for/about a user |
| `Get-RecurringIssues` | AI identifies patterns across tickets |
| `Get-KnowledgeGaps` | Tickets that should have KB articles but don't |
| `Sync-KnowledgeArticles` | Push updated/new KB articles back to ServiceNow |

## Requirements

- PowerShell 5.1 or later
- Network access to your ITSM platform (ServiceNow or Jira)
- An LLM API key (Anthropic, OpenAI, or local Ollama) for AI features
- ServiceNow user with read access to incident/change/problem/KB tables

## Security Note

Tickets often contain sensitive data: server names, IP addresses, user information, error details, and sometimes credentials in work notes.

This module sends ticket text to the configured AI provider for analysis. For sensitive environments:

- Use **Ollama** (`-AIProvider Ollama`) to keep everything local
- Use the **-SkipAI** flag to get structured data without any AI processing
- Review the AI prompt templates in `Templates/` to understand exactly what is sent
- The module never stores or caches ticket data beyond the PowerShell session

## License

MIT License. Copyright (c) 2026 Larry Roberts.
