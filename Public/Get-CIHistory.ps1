function Get-CIHistory {
    <#
    .SYNOPSIS
        Pulls all tickets for a Configuration Item and generates an AI-powered summary.
    .DESCRIPTION
        Retrieves incident, change, and problem tickets associated with a server, application,
        or CI from ServiceNow, Jira Service Management, or a CSV/JSON export file.
        Uses AI to summarize the full history into an actionable briefing with timeline,
        recurring themes, and risk assessment.
    .EXAMPLE
        Get-CIHistory -CIName 'SQL-PROD-01' -Provider ServiceNow -Instance 'company.service-now.com' -Credential $cred
    .EXAMPLE
        Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath '.\tickets.json' -SkipAI
    .EXAMPLE
        Get-CIHistory -CIName 'WEB-DMZ-03' -Provider Jira -BaseUrl 'https://company.atlassian.net' -Email 'admin@co.com' -OutputPath '.\report.html'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CIName,

        [Parameter()]
        [ValidateSet('ServiceNow', 'Jira', 'File')]
        [string]$Provider = 'ServiceNow',

        [Parameter()]
        [string]$Instance,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [string]$BaseUrl,

        [Parameter()]
        [string]$Email,

        [Parameter()]
        [string]$FilePath,

        [Parameter()]
        [ValidateRange(1, 60)]
        [int]$MonthsBack = 18,

        [Parameter()]
        [ValidateSet('Anthropic', 'OpenAI', 'Ollama', 'Custom')]
        [string]$AIProvider = 'Anthropic',

        [Parameter()]
        [string]$AIApiKey,

        [Parameter()]
        [string]$AIModel,

        [Parameter()]
        [string]$AIEndpoint,

        [Parameter()]
        [string]$OutputPath,

        [Parameter()]
        [switch]$SkipAI
    )

    Write-Verbose "Getting CI history for '$CIName' from $Provider (last $MonthsBack months)"

    # ── Retrieve tickets based on provider ──
    $allTickets = @()

    switch ($Provider) {
        'ServiceNow' {
            if (-not $Instance) {
                throw 'ServiceNow provider requires -Instance parameter (e.g., "company.service-now.com").'
            }

            $authParams = @{ Instance = $Instance }
            if ($Credential) { $authParams['Credential'] = $Credential }
            if ($ApiKey) { $authParams['ApiKey'] = $ApiKey }

            $fields = 'number,short_description,description,state,priority,category,subcategory,opened_at,closed_at,resolved_at,assigned_to,close_notes,work_notes'
            $dateFilter = "sys_created_on>javascript:gs.monthsAgo($MonthsBack)"

            # Incidents
            Write-Verbose 'Querying ServiceNow incidents...'
            $incidentQuery = "cmdb_ci.name=$CIName^$dateFilter"
            $incidents = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/incident' `
                -QueryParameters @{
                    sysparm_query  = $incidentQuery
                    sysparm_fields = $fields
                    sysparm_limit  = '10000'
                } -Paginate

            foreach ($inc in @($incidents)) {
                $allTickets += [PSCustomObject]@{
                    Number           = $inc.number
                    Type             = 'Incident'
                    ShortDescription = $inc.short_description
                    Description      = $inc.description
                    State            = $inc.state
                    Priority         = $inc.priority
                    Category         = $inc.category
                    Subcategory      = $inc.subcategory
                    OpenedAt         = $inc.opened_at
                    ClosedAt         = $inc.closed_at
                    ResolvedAt       = $inc.resolved_at
                    AssignedTo       = if ($inc.assigned_to -is [string]) { $inc.assigned_to } else { $inc.assigned_to.display_value }
                    CloseNotes       = $inc.close_notes
                    WorkNotes        = $inc.work_notes
                    CIName           = $CIName
                    Source           = 'ServiceNow'
                }
            }
            Write-Verbose "Found $(@($incidents).Count) incidents"

            # Change Requests
            Write-Verbose 'Querying ServiceNow change requests...'
            $changeQuery = "cmdb_ci.name=$CIName^$dateFilter"
            $changes = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/change_request' `
                -QueryParameters @{
                    sysparm_query  = $changeQuery
                    sysparm_fields = $fields
                    sysparm_limit  = '10000'
                } -Paginate

            foreach ($chg in @($changes)) {
                $allTickets += [PSCustomObject]@{
                    Number           = $chg.number
                    Type             = 'Change Request'
                    ShortDescription = $chg.short_description
                    Description      = $chg.description
                    State            = $chg.state
                    Priority         = $chg.priority
                    Category         = $chg.category
                    Subcategory      = $chg.subcategory
                    OpenedAt         = $chg.opened_at
                    ClosedAt         = $chg.closed_at
                    ResolvedAt       = $chg.resolved_at
                    AssignedTo       = if ($chg.assigned_to -is [string]) { $chg.assigned_to } else { $chg.assigned_to.display_value }
                    CloseNotes       = $chg.close_notes
                    WorkNotes        = $chg.work_notes
                    CIName           = $CIName
                    Source           = 'ServiceNow'
                }
            }
            Write-Verbose "Found $(@($changes).Count) change requests"

            # Problems
            Write-Verbose 'Querying ServiceNow problems...'
            $problemQuery = "cmdb_ci.name=$CIName^$dateFilter"
            $problems = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/problem' `
                -QueryParameters @{
                    sysparm_query  = $problemQuery
                    sysparm_fields = $fields
                    sysparm_limit  = '10000'
                } -Paginate

            foreach ($prb in @($problems)) {
                $allTickets += [PSCustomObject]@{
                    Number           = $prb.number
                    Type             = 'Problem'
                    ShortDescription = $prb.short_description
                    Description      = $prb.description
                    State            = $prb.state
                    Priority         = $prb.priority
                    Category         = $prb.category
                    Subcategory      = $prb.subcategory
                    OpenedAt         = $prb.opened_at
                    ClosedAt         = $prb.closed_at
                    ResolvedAt       = $prb.resolved_at
                    AssignedTo       = if ($prb.assigned_to -is [string]) { $prb.assigned_to } else { $prb.assigned_to.display_value }
                    CloseNotes       = $prb.close_notes
                    WorkNotes        = $prb.work_notes
                    CIName           = $CIName
                    Source           = 'ServiceNow'
                }
            }
            Write-Verbose "Found $(@($problems).Count) problems"
        }

        'Jira' {
            if (-not $BaseUrl) {
                throw 'Jira provider requires -BaseUrl parameter (e.g., "https://company.atlassian.net").'
            }
            if (-not $Email) {
                throw 'Jira provider requires -Email parameter for authentication.'
            }

            $jql = "(""Affected CI"" = ""$CIName"" OR summary ~ ""$CIName"" OR description ~ ""$CIName"") AND created >= ""-${MonthsBack}m"""

            Write-Verbose "Querying Jira with JQL: $jql"

            $jiraParams = @{
                BaseUrl = $BaseUrl
                Email   = $Email
                Method  = 'GET'
                Endpoint = 'rest/api/3/search'
                QueryParameters = @{
                    jql        = $jql
                    maxResults = '100'
                    fields     = 'summary,description,status,priority,issuetype,created,resolutiondate,assignee,reporter,comment,components'
                }
                Paginate = $true
            }
            if ($ApiKey) { $jiraParams['ApiToken'] = $ApiKey }

            $jiraIssues = Connect-JiraSM @jiraParams

            foreach ($issue in @($jiraIssues)) {
                $allTickets += ConvertFrom-JiraIssue -Issue $issue
            }
            Write-Verbose "Found $(@($jiraIssues).Count) Jira issues"
        }

        'File' {
            if (-not $FilePath) {
                throw 'File provider requires -FilePath parameter pointing to a CSV or JSON file.'
            }

            $allTickets = @(Import-TicketExport -Path $FilePath -CIFilter $CIName -MonthsBack $MonthsBack)
            Write-Verbose "Imported $($allTickets.Count) tickets from file"
        }
    }

    # Sort by date
    $allTickets = @($allTickets | Sort-Object {
        try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
    })

    # Count by type
    $incidentCount = @($allTickets | Where-Object { $_.Type -eq 'Incident' }).Count
    $changeCount   = @($allTickets | Where-Object { $_.Type -like '*Change*' }).Count
    $problemCount  = @($allTickets | Where-Object { $_.Type -eq 'Problem' }).Count

    # Identify open items
    $openItems = @($allTickets | Where-Object {
        $_.State -notmatch '(?i)(closed|resolved|cancelled|completed|done)'
    })

    # Build timeline
    $timeline = @($allTickets | ForEach-Object {
        $dateStr = $_.OpenedAt
        try {
            $parsedDate = [datetime]::Parse($dateStr)
            $formattedDate = $parsedDate.ToString('yyyy-MM-dd')
        }
        catch {
            $formattedDate = $dateStr
        }
        [PSCustomObject]@{
            Date        = $formattedDate
            Number      = $_.Number
            Type        = $_.Type
            Description = $_.ShortDescription
            State       = $_.State
        }
    })

    # ── AI Summary ──
    $summary = ''
    if (-not $SkipAI -and $allTickets.Count -gt 0) {
        Write-Verbose 'Generating AI summary...'

        # Load prompt template
        $templatePath = Join-Path $PSScriptRoot '..\Templates\ci-history-prompt.txt'
        if (Test-Path $templatePath) {
            $promptTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
        }
        else {
            $promptTemplate = @"
You are an IT service management analyst. Given the following ticket history for configuration item "{ci_name}", provide a comprehensive summary.

Analyze ALL tickets and provide:
1. Executive Summary (2-3 sentences)
2. Timeline of Major Events (chronological)
3. Recurring Themes
4. Current State
5. Risk Assessment

TICKET DATA:
{ticket_data}
"@
        }

        # Build ticket data text
        $ticketDataText = ($allTickets | ForEach-Object {
            "[$($_.Type)] $($_.Number) | $($_.OpenedAt) | $($_.ShortDescription) | State: $($_.State) | Priority: $($_.Priority) | Assigned: $($_.AssignedTo) | Close Notes: $($_.CloseNotes)"
        }) -join "`n"

        $prompt = $promptTemplate -replace '\{ci_name\}', $CIName -replace '\{ticket_data\}', $ticketDataText

        $aiParams = @{
            Prompt   = $prompt
            Provider = $AIProvider
        }
        if ($AIApiKey)    { $aiParams['ApiKey']   = $AIApiKey }
        if ($AIModel)     { $aiParams['Model']    = $AIModel }
        if ($AIEndpoint)  { $aiParams['Endpoint'] = $AIEndpoint }

        try {
            $summary = Invoke-AICompletion @aiParams
        }
        catch {
            Write-Warning "AI summary generation failed: $($_.Exception.Message). Returning raw data only."
            $summary = "[AI summary unavailable: $($_.Exception.Message)]"
        }
    }
    elseif ($allTickets.Count -eq 0) {
        $summary = "No tickets found for CI '$CIName' in the last $MonthsBack months."
    }

    # ── Build result object ──
    $result = [PSCustomObject]@{
        CIName        = $CIName
        TicketCount   = $allTickets.Count
        IncidentCount = $incidentCount
        ChangeCount   = $changeCount
        ProblemCount  = $problemCount
        Summary       = $summary
        Timeline      = $timeline
        OpenItems     = $openItems
        RawTickets    = $allTickets
        Provider      = $Provider
        MonthsBack    = $MonthsBack
        GeneratedAt   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    # ── Generate HTML report if requested ──
    if ($OutputPath) {
        Write-Verbose "Generating HTML report: $OutputPath"
        New-HtmlDashboard -ReportType 'CIHistory' -Data $result -OutputPath $OutputPath
        Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
    }

    return $result
}
