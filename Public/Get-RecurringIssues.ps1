function Get-RecurringIssues {
    <#
    .SYNOPSIS
        Analyzes tickets to identify recurring issues and patterns using AI.
    .DESCRIPTION
        Pulls tickets for a CI, category, or timeframe and uses AI to detect patterns
        such as repeated root causes, recurring symptoms, and escalation patterns.
        Returns actionable recommendations for permanent fixes.
    .EXAMPLE
        Get-RecurringIssues -CIName 'SQL-PROD-01' -Provider ServiceNow -Instance 'company.service-now.com' -Credential $cred
    .EXAMPLE
        Get-RecurringIssues -Provider File -FilePath '.\tickets.json' -MinOccurrences 2 -OutputPath '.\recurring.html'
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$CIName,

        [Parameter()]
        [string]$Category,

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
        [int]$MonthsBack = 6,

        [Parameter()]
        [int]$MinOccurrences = 3,

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

    Write-Verbose "Analyzing recurring issues (Provider: $Provider, MonthsBack: $MonthsBack, MinOccurrences: $MinOccurrences)"

    $allTickets = @()

    switch ($Provider) {
        'ServiceNow' {
            if (-not $Instance) {
                throw 'ServiceNow provider requires -Instance parameter.'
            }

            $authParams = @{ Instance = $Instance }
            if ($Credential) { $authParams['Credential'] = $Credential }
            if ($ApiKey) { $authParams['ApiKey'] = $ApiKey }

            $fields = 'number,short_description,description,state,priority,category,subcategory,opened_at,closed_at,resolved_at,assigned_to,close_notes,work_notes,cmdb_ci'
            $dateFilter = "sys_created_on>javascript:gs.monthsAgo($MonthsBack)"

            # Build query based on filters
            $queryParts = @($dateFilter)
            if ($CIName) {
                $queryParts += "cmdb_ci.name=$CIName"
            }
            if ($Category) {
                $queryParts += "category=$Category"
            }
            $query = $queryParts -join '^'

            # Query incidents (primary source for recurring issues)
            Write-Verbose 'Querying ServiceNow incidents...'
            $incidents = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/incident' `
                -QueryParameters @{
                    sysparm_query  = $query
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
                    CIName           = if ($inc.cmdb_ci -is [string]) { $inc.cmdb_ci } else { $inc.cmdb_ci.display_value }
                    Source           = 'ServiceNow'
                }
            }

            # Query problems too (they often link recurring incidents)
            Write-Verbose 'Querying ServiceNow problems...'
            $problems = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/problem' `
                -QueryParameters @{
                    sysparm_query  = $query
                    sysparm_fields = $fields
                    sysparm_limit  = '5000'
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
                    CIName           = if ($prb.cmdb_ci -is [string]) { $prb.cmdb_ci } else { $prb.cmdb_ci.display_value }
                    Source           = 'ServiceNow'
                }
            }

            Write-Verbose "Total tickets for analysis: $($allTickets.Count)"
        }

        'Jira' {
            if (-not $BaseUrl) {
                throw 'Jira provider requires -BaseUrl parameter.'
            }
            if (-not $Email) {
                throw 'Jira provider requires -Email parameter.'
            }

            $jqlParts = @("created >= ""-${MonthsBack}m""")
            if ($CIName) {
                $jqlParts += "(""Affected CI"" = ""$CIName"" OR summary ~ ""$CIName"" OR description ~ ""$CIName"")"
            }
            if ($Category) {
                $jqlParts += "component = ""$Category"""
            }
            $jql = $jqlParts -join ' AND '

            Write-Verbose "Querying Jira: $jql"

            $jiraParams = @{
                BaseUrl  = $BaseUrl
                Email    = $Email
                Method   = 'GET'
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
                throw 'File provider requires -FilePath parameter.'
            }

            $importParams = @{
                Path       = $FilePath
                MonthsBack = $MonthsBack
            }
            if ($CIName) { $importParams['CIFilter'] = $CIName }

            $allTickets = @(Import-TicketExport @importParams)

            # Apply category filter if specified
            if ($Category) {
                $allTickets = @($allTickets | Where-Object { $_.Category -like "*$Category*" })
            }
            Write-Verbose "Imported $($allTickets.Count) tickets from file"
        }
    }

    if ($allTickets.Count -eq 0) {
        Write-Warning 'No tickets found matching the specified criteria.'
        return @()
    }

    # Sort by date
    $allTickets = @($allTickets | Sort-Object {
        try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
    })

    # ── SkipAI: basic pattern detection without AI ──
    if ($SkipAI) {
        Write-Verbose 'SkipAI mode: performing basic pattern detection without AI...'
        $patterns = Find-BasicPatterns -Tickets $allTickets -MinOccurrences $MinOccurrences
        if ($OutputPath) {
            New-HtmlDashboard -ReportType 'RecurringIssues' -Data $patterns -OutputPath $OutputPath
            Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
        }
        return $patterns
    }

    # ── AI-powered pattern detection ──
    Write-Verbose 'Generating AI pattern analysis...'

    $templatePath = Join-Path $PSScriptRoot '..\Templates\recurring-issues-prompt.txt'
    if (Test-Path $templatePath) {
        $promptTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
    }
    else {
        $promptTemplate = @"
You are an IT problem management analyst. Analyze the following tickets to identify recurring issues and patterns.

For each pattern found with {min_occurrences} or more occurrences, provide:
1. Pattern Name
2. Occurrences (ticket numbers)
3. Root Cause Analysis
4. Impact
5. Suggested Permanent Fix
6. Suggested KB Article outline

TICKET DATA:
{ticket_data}
"@
    }

    $ticketDataText = ($allTickets | ForEach-Object {
        "[$($_.Type)] $($_.Number) | $($_.OpenedAt) | CI: $($_.CIName) | Cat: $($_.Category) | $($_.ShortDescription) | State: $($_.State) | Close Notes: $($_.CloseNotes)"
    }) -join "`n"

    $prompt = $promptTemplate -replace '\{min_occurrences\}', $MinOccurrences -replace '\{ticket_data\}', $ticketDataText

    $aiParams = @{
        Prompt   = $prompt
        Provider = $AIProvider
    }
    if ($AIApiKey)   { $aiParams['ApiKey']   = $AIApiKey }
    if ($AIModel)    { $aiParams['Model']    = $AIModel }
    if ($AIEndpoint) { $aiParams['Endpoint'] = $AIEndpoint }

    try {
        $aiResponse = Invoke-AICompletion @aiParams
    }
    catch {
        Write-Warning "AI analysis failed: $($_.Exception.Message). Falling back to basic pattern detection."
        $patterns = Find-BasicPatterns -Tickets $allTickets -MinOccurrences $MinOccurrences
        if ($OutputPath) {
            New-HtmlDashboard -ReportType 'RecurringIssues' -Data $patterns -OutputPath $OutputPath
            Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
        }
        return $patterns
    }

    # Parse AI response into structured objects
    $patterns = ConvertFrom-AIPatternResponse -AIResponse $aiResponse -Tickets $allTickets

    if ($OutputPath) {
        New-HtmlDashboard -ReportType 'RecurringIssues' -Data $patterns -OutputPath $OutputPath
        Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
    }

    return $patterns
}


function Find-BasicPatterns {
    <#
    .SYNOPSIS
        Basic pattern detection without AI - groups tickets by similar short descriptions and categories.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Tickets,

        [Parameter()]
        [int]$MinOccurrences = 3
    )

    $patterns = @()

    # Group by category + subcategory
    $categoryGroups = $Tickets | Group-Object { "$($_.Category)|$($_.Subcategory)" } | Where-Object { $_.Count -ge $MinOccurrences }

    foreach ($group in $categoryGroups) {
        $sortedTickets = $group.Group | Sort-Object {
            try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
        }
        $ticketNumbers = @($sortedTickets | ForEach-Object { $_.Number })
        $firstDate = ($sortedTickets | Select-Object -First 1).OpenedAt
        $lastDate = ($sortedTickets | Select-Object -Last 1).OpenedAt

        $patterns += [PSCustomObject]@{
            Pattern             = "Category: $($group.Name -replace '\|', ' > ')"
            Occurrences         = $group.Count
            TicketNumbers       = $ticketNumbers
            FirstSeen           = $firstDate
            LastSeen            = $lastDate
            SuggestedResolution = "Review tickets in this category for common root cause. Consider creating a knowledge article or implementing a permanent fix."
            EstimatedTimeSaved  = "$($group.Count) ticket interactions potentially avoidable"
            Source              = 'BasicAnalysis'
        }
    }

    # Group by similar short descriptions (simple word overlap approach)
    $descGroups = @{}
    foreach ($ticket in $Tickets) {
        $words = ($ticket.ShortDescription -split '\s+' | Where-Object { $_.Length -gt 3 } | ForEach-Object { $_.ToLower() } | Select-Object -First 5) -join ' '
        if ($words) {
            if (-not $descGroups.ContainsKey($words)) {
                $descGroups[$words] = @()
            }
            $descGroups[$words] += $ticket
        }
    }

    foreach ($key in $descGroups.Keys) {
        $group = $descGroups[$key]
        if ($group.Count -ge $MinOccurrences) {
            $sortedTickets = $group | Sort-Object {
                try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
            }
            $ticketNumbers = @($sortedTickets | ForEach-Object { $_.Number })

            $patterns += [PSCustomObject]@{
                Pattern             = "Similar: $($group[0].ShortDescription)"
                Occurrences         = $group.Count
                TicketNumbers       = $ticketNumbers
                FirstSeen           = ($sortedTickets | Select-Object -First 1).OpenedAt
                LastSeen            = ($sortedTickets | Select-Object -Last 1).OpenedAt
                SuggestedResolution = 'Multiple tickets with similar descriptions detected. Investigate shared root cause.'
                EstimatedTimeSaved  = "Approximately $([math]::Round($group.Count * 0.5, 1)) hours if resolved permanently"
                Source              = 'BasicAnalysis'
            }
        }
    }

    return @($patterns | Sort-Object Occurrences -Descending)
}


function ConvertFrom-AIPatternResponse {
    <#
    .SYNOPSIS
        Parses AI response text into structured RecurringIssue objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AIResponse,

        [Parameter(Mandatory)]
        [object[]]$Tickets
    )

    $patterns = @()

    # Split response by pattern sections (look for numbered headers or ## headers)
    $sections = $AIResponse -split '(?m)^(?:#{1,3}\s*\d+\.?\s*|(?:\*\*)?Pattern\s*(?:Name)?\s*(?:\d+)?:?\s*(?:\*\*)?)'

    foreach ($section in $sections) {
        if ([string]::IsNullOrWhiteSpace($section)) { continue }
        if ($section.Length -lt 20) { continue }

        # Extract pattern name (first line or bold text)
        $lines = $section.Trim() -split "`n"
        $patternName = ($lines[0] -replace '\*\*', '' -replace '^#+\s*', '' -replace '^\d+\.\s*', '').Trim()
        if (-not $patternName -or $patternName.Length -lt 3) { continue }

        # Extract ticket numbers mentioned
        $ticketNumbers = @()
        $ticketMatches = [regex]::Matches($section, '(?:INC|CHG|PRB|REQ|RITM|TASK|SCTASK|[A-Z]+-)\d{5,10}')
        foreach ($match in $ticketMatches) {
            $ticketNumbers += $match.Value
        }
        $ticketNumbers = @($ticketNumbers | Select-Object -Unique)

        # Extract occurrence count
        $occurrences = $ticketNumbers.Count
        $occurrenceMatch = [regex]::Match($section, '(?:Occurrences?|Count|Times?)[\s:]*(\d+)', 'IgnoreCase')
        if ($occurrenceMatch.Success) {
            $occurrences = [int]$occurrenceMatch.Groups[1].Value
        }
        if ($occurrences -lt 1) { $occurrences = 1 }

        # Extract suggested resolution
        $suggestedFix = ''
        $fixMatch = [regex]::Match($section, '(?:Suggested\s*(?:Permanent\s*)?Fix|Resolution|Recommendation)[\s:]*(.+?)(?=\n\s*(?:\*\*|#{1,3}|\d+\.)|\z)', 'IgnoreCase,Singleline')
        if ($fixMatch.Success) {
            $suggestedFix = $fixMatch.Groups[1].Value.Trim()
        }
        else {
            # Fallback: use the last paragraph
            $suggestedFix = ($lines | Select-Object -Last 3) -join ' '
        }

        # Determine date range from matched tickets
        $firstSeen = ''
        $lastSeen = ''
        if ($ticketNumbers.Count -gt 0) {
            $matchedTickets = $Tickets | Where-Object { $_.Number -in $ticketNumbers } | Sort-Object {
                try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
            }
            if ($matchedTickets) {
                $firstSeen = ($matchedTickets | Select-Object -First 1).OpenedAt
                $lastSeen = ($matchedTickets | Select-Object -Last 1).OpenedAt
            }
        }

        $patterns += [PSCustomObject]@{
            Pattern             = $patternName
            Occurrences         = $occurrences
            TicketNumbers       = $ticketNumbers
            FirstSeen           = $firstSeen
            LastSeen            = $lastSeen
            SuggestedResolution = $suggestedFix
            EstimatedTimeSaved  = "Approximately $([math]::Round($occurrences * 0.5, 1)) hours per recurrence"
            Source              = 'AI'
        }
    }

    # If AI parsing yielded no structured patterns, return the raw response as a single pattern
    if ($patterns.Count -eq 0) {
        $patterns += [PSCustomObject]@{
            Pattern             = 'AI Analysis (unstructured)'
            Occurrences         = $Tickets.Count
            TicketNumbers       = @($Tickets | ForEach-Object { $_.Number })
            FirstSeen           = ($Tickets | Select-Object -First 1).OpenedAt
            LastSeen            = ($Tickets | Select-Object -Last 1).OpenedAt
            SuggestedResolution = $AIResponse
            EstimatedTimeSaved  = 'See analysis details'
            Source              = 'AI'
        }
    }

    return @($patterns | Sort-Object Occurrences -Descending)
}
