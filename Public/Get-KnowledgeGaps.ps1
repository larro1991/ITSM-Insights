function Get-KnowledgeGaps {
    <#
    .SYNOPSIS
        Identifies tickets that should have KB articles but don't, or KB articles that are stale/incomplete.
    .DESCRIPTION
        Pulls incident tickets and existing knowledge base articles from ServiceNow (or file exports),
        then uses AI to compare ticket patterns against available KB content.
        Identifies missing articles, stale articles, and incomplete articles.
    .EXAMPLE
        Get-KnowledgeGaps -Provider ServiceNow -Instance 'company.service-now.com' -Credential $cred
    .EXAMPLE
        Get-KnowledgeGaps -Provider File -FilePath '.\tickets.json' -MinOccurrences 2 -OutputPath '.\gaps.html'
    #>
    [CmdletBinding()]
    param(
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
        [switch]$IncludeExistingKB,

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

    Write-Verbose "Analyzing knowledge gaps (Provider: $Provider, MonthsBack: $MonthsBack, MinOccurrences: $MinOccurrences)"

    $allTickets = @()
    $kbArticles = @()

    switch ($Provider) {
        'ServiceNow' {
            if (-not $Instance) {
                throw 'ServiceNow provider requires -Instance parameter.'
            }

            $authParams = @{ Instance = $Instance }
            if ($Credential) { $authParams['Credential'] = $Credential }
            if ($ApiKey) { $authParams['ApiKey'] = $ApiKey }

            $fields = 'number,short_description,description,state,priority,category,subcategory,opened_at,closed_at,resolved_at,assigned_to,close_notes,work_notes'
            $dateFilter = "sys_created_on>javascript:gs.monthsAgo($MonthsBack)"

            # Pull incidents
            Write-Verbose 'Querying ServiceNow incidents...'
            $incidents = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/incident' `
                -QueryParameters @{
                    sysparm_query  = $dateFilter
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
                    Source           = 'ServiceNow'
                }
            }
            Write-Verbose "Found $(@($incidents).Count) incidents"

            # Pull KB articles (always or if IncludeExistingKB)
            Write-Verbose 'Querying ServiceNow knowledge base articles...'
            $kbFields = 'number,short_description,text,kb_knowledge_base,category,sys_updated_on,workflow_state,author'
            $kbQuery = 'workflow_state=published'

            $kbResults = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/kb_knowledge' `
                -QueryParameters @{
                    sysparm_query  = $kbQuery
                    sysparm_fields = $kbFields
                    sysparm_limit  = '5000'
                } -Paginate

            foreach ($kb in @($kbResults)) {
                $kbArticles += [PSCustomObject]@{
                    Number           = $kb.number
                    Title            = $kb.short_description
                    Content          = $kb.text
                    KnowledgeBase    = $kb.kb_knowledge_base
                    Category         = $kb.category
                    LastUpdated      = $kb.sys_updated_on
                    WorkflowState    = $kb.workflow_state
                    Author           = $kb.author
                }
            }
            Write-Verbose "Found $($kbArticles.Count) published KB articles"
        }

        'Jira' {
            if (-not $BaseUrl) {
                throw 'Jira provider requires -BaseUrl parameter.'
            }
            if (-not $Email) {
                throw 'Jira provider requires -Email parameter.'
            }

            $jql = "issuetype in (Incident, Bug, ""Service Request"") AND created >= ""-${MonthsBack}m"""

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

            # Jira doesn't have a native KB — note this for the user
            Write-Warning 'Jira does not have a built-in knowledge base. KB gap analysis will be based on ticket patterns only.'
        }

        'File' {
            if (-not $FilePath) {
                throw 'File provider requires -FilePath parameter.'
            }

            $allTickets = @(Import-TicketExport -Path $FilePath -MonthsBack $MonthsBack)
            Write-Verbose "Imported $($allTickets.Count) tickets from file"

            # Check if there is a separate KB file
            $kbPath = [System.IO.Path]::ChangeExtension($FilePath, $null) + '-kb' + [System.IO.Path]::GetExtension($FilePath)
            if (Test-Path $kbPath) {
                Write-Verbose "Found KB file: $kbPath"
                $kbContent = Get-Content -Path $kbPath -Raw -Encoding UTF8
                $kbParsed = $kbContent | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($kbParsed) {
                    foreach ($kb in @($kbParsed)) {
                        $kbArticles += [PSCustomObject]@{
                            Number        = $kb.number
                            Title         = $kb.title
                            Content       = $kb.content
                            Category      = $kb.category
                            LastUpdated   = $kb.updated
                            WorkflowState = 'published'
                        }
                    }
                }
            }
        }
    }

    if ($allTickets.Count -eq 0) {
        Write-Warning 'No tickets found for knowledge gap analysis.'
        return @()
    }

    # ── SkipAI mode: basic gap detection ──
    if ($SkipAI) {
        Write-Verbose 'SkipAI mode: performing basic knowledge gap detection...'
        $gaps = Find-BasicKnowledgeGaps -Tickets $allTickets -KBArticles $kbArticles -MinOccurrences $MinOccurrences
        if ($OutputPath) {
            New-HtmlDashboard -ReportType 'KnowledgeGaps' -Data $gaps -OutputPath $OutputPath
            Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
        }
        return $gaps
    }

    # ── AI-powered gap analysis ──
    Write-Verbose 'Generating AI knowledge gap analysis...'

    $templatePath = Join-Path $PSScriptRoot '..\Templates\knowledge-gap-prompt.txt'
    if (Test-Path $templatePath) {
        $promptTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
    }
    else {
        $promptTemplate = @"
You are a knowledge management analyst. Compare the following ticket data with the existing knowledge base articles.

Identify Missing, Stale, and Incomplete articles.

TICKET DATA:
{ticket_data}

EXISTING KB ARTICLES:
{kb_articles}
"@
    }

    $ticketDataText = ($allTickets | ForEach-Object {
        "[$($_.Type)] $($_.Number) | $($_.OpenedAt) | Cat: $($_.Category) | $($_.ShortDescription) | Close Notes: $($_.CloseNotes)"
    }) -join "`n"

    $kbDataText = if ($kbArticles.Count -gt 0) {
        ($kbArticles | ForEach-Object {
            "$($_.Number) | $($_.Title) | Updated: $($_.LastUpdated) | Category: $($_.Category)"
        }) -join "`n"
    }
    else {
        '(No existing KB articles found)'
    }

    $prompt = $promptTemplate -replace '\{ticket_data\}', $ticketDataText -replace '\{kb_articles\}', $kbDataText

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
        Write-Warning "AI analysis failed: $($_.Exception.Message). Falling back to basic gap detection."
        $gaps = Find-BasicKnowledgeGaps -Tickets $allTickets -KBArticles $kbArticles -MinOccurrences $MinOccurrences
        if ($OutputPath) {
            New-HtmlDashboard -ReportType 'KnowledgeGaps' -Data $gaps -OutputPath $OutputPath
            Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
        }
        return $gaps
    }

    # Parse AI response into structured gap objects
    $gaps = ConvertFrom-AIGapResponse -AIResponse $aiResponse -Tickets $allTickets

    if ($OutputPath) {
        New-HtmlDashboard -ReportType 'KnowledgeGaps' -Data $gaps -OutputPath $OutputPath
        Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
    }

    return $gaps
}


function Find-BasicKnowledgeGaps {
    <#
    .SYNOPSIS
        Basic knowledge gap detection without AI — identifies frequently recurring ticket topics with no KB article.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Tickets,

        [Parameter()]
        [object[]]$KBArticles = @(),

        [Parameter()]
        [int]$MinOccurrences = 3
    )

    $gaps = @()

    # Group tickets by category
    $categoryGroups = $Tickets | Where-Object { $_.Category } | Group-Object Category | Where-Object { $_.Count -ge $MinOccurrences } | Sort-Object Count -Descending

    foreach ($group in $categoryGroups) {
        # Check if any KB article covers this category
        $hasKB = $KBArticles | Where-Object {
            $_.Category -like "*$($group.Name)*" -or $_.Title -like "*$($group.Name)*"
        }

        if (-not $hasKB) {
            $ticketNumbers = @($group.Group | ForEach-Object { $_.Number })
            $gaps += [PSCustomObject]@{
                GapType          = 'Missing'
                Topic            = $group.Name
                RelatedTickets   = $ticketNumbers
                SuggestedTitle   = "How to Resolve Common $($group.Name) Issues"
                SuggestedContent = "This article should cover the $($group.Count) incidents categorized as '$($group.Name)'. Common descriptions include: $(($group.Group | Select-Object -First 3 | ForEach-Object { $_.ShortDescription }) -join '; ')"
            }
        }
    }

    return $gaps
}


function ConvertFrom-AIGapResponse {
    <#
    .SYNOPSIS
        Parses AI response text into structured KnowledgeGap objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AIResponse,

        [Parameter(Mandatory)]
        [object[]]$Tickets
    )

    $gaps = @()

    # Split by sections (numbered items, headers, or gap type markers)
    $sections = $AIResponse -split '(?m)^(?:#{1,3}\s*\d+\.?\s*|(?:\*\*)?(?:Missing|Stale|Incomplete)\s*(?:Article)?\s*(?:\d+)?:?\s*(?:\*\*)?)'

    foreach ($section in $sections) {
        if ([string]::IsNullOrWhiteSpace($section)) { continue }
        if ($section.Length -lt 20) { continue }

        # Determine gap type
        $gapType = 'Missing'
        if ($section -match '(?i)\bstale\b') { $gapType = 'Stale' }
        elseif ($section -match '(?i)\bincomplete\b') { $gapType = 'Incomplete' }

        # Extract topic/title
        $lines = $section.Trim() -split "`n"
        $topic = ($lines[0] -replace '\*\*', '' -replace '^#+\s*', '' -replace '^\d+\.\s*', '').Trim()
        if (-not $topic -or $topic.Length -lt 3) { continue }

        # Extract ticket numbers
        $ticketNumbers = @()
        $ticketMatches = [regex]::Matches($section, '(?:INC|CHG|PRB|REQ|RITM|[A-Z]+-)\d{5,10}')
        foreach ($match in $ticketMatches) {
            $ticketNumbers += $match.Value
        }
        $ticketNumbers = @($ticketNumbers | Select-Object -Unique)

        # Extract suggested title
        $suggestedTitle = $topic
        $titleMatch = [regex]::Match($section, '(?:Suggested\s*(?:Article\s*)?Title|Title)[\s:]+(.+?)(?:\n|$)', 'IgnoreCase')
        if ($titleMatch.Success) {
            $suggestedTitle = ($titleMatch.Groups[1].Value -replace '\*\*', '').Trim()
        }

        # Extract suggested content
        $suggestedContent = ''
        $contentMatch = [regex]::Match($section, '(?:Suggested\s*(?:Article\s*)?Content|Outline|Steps)[\s:]*(.+?)(?=\n\s*(?:\*\*(?:Gap|Missing|Stale|Incomplete)|#{1,3}|\d+\.)|\z)', 'IgnoreCase,Singleline')
        if ($contentMatch.Success) {
            $suggestedContent = $contentMatch.Groups[1].Value.Trim()
        }
        else {
            # Use remaining lines as suggested content
            $suggestedContent = ($lines | Select-Object -Skip 1 | Select-Object -Last 5) -join "`n"
        }

        $gaps += [PSCustomObject]@{
            GapType          = $gapType
            Topic            = $topic
            RelatedTickets   = $ticketNumbers
            SuggestedTitle   = $suggestedTitle
            SuggestedContent = $suggestedContent
        }
    }

    # If AI parsing yielded no structured gaps, return the raw response as a single gap
    if ($gaps.Count -eq 0 -and $AIResponse.Length -gt 50) {
        $gaps += [PSCustomObject]@{
            GapType          = 'Missing'
            Topic            = 'AI Analysis Results'
            RelatedTickets   = @($Tickets | ForEach-Object { $_.Number } | Select-Object -First 10)
            SuggestedTitle   = 'Knowledge Gap Analysis Results'
            SuggestedContent = $AIResponse
        }
    }

    return $gaps
}
