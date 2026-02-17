function Get-UserTicketHistory {
    <#
    .SYNOPSIS
        Retrieves all tickets for a user (as requester, assignee, or mentioned) and generates an AI summary.
    .DESCRIPTION
        Pulls tickets where the specified user was the requester, the assignee, or mentioned
        in ticket notes. Uses AI to summarize interaction patterns, workload distribution,
        and common issue types.
    .EXAMPLE
        Get-UserTicketHistory -UserIdentity 'john.doe@company.com' -Provider ServiceNow -Instance 'company.service-now.com' -Credential $cred
    .EXAMPLE
        Get-UserTicketHistory -UserIdentity 'Jane Smith' -Provider File -FilePath '.\tickets.csv' -Role Assignee
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserIdentity,

        [Parameter()]
        [ValidateSet('All', 'Requester', 'Assignee', 'Both')]
        [string]$Role = 'All',

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
        [int]$MonthsBack = 12,

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

    Write-Verbose "Getting ticket history for user '$UserIdentity' (Role: $Role, Provider: $Provider, last $MonthsBack months)"

    $allTickets = @()
    $ticketsByRole = @{
        Requester = @()
        Assignee  = @()
        Mentioned = @()
    }

    switch ($Provider) {
        'ServiceNow' {
            if (-not $Instance) {
                throw 'ServiceNow provider requires -Instance parameter.'
            }

            $authParams = @{ Instance = $Instance }
            if ($Credential) { $authParams['Credential'] = $Credential }
            if ($ApiKey) { $authParams['ApiKey'] = $ApiKey }

            $fields = 'number,short_description,description,state,priority,category,subcategory,opened_at,closed_at,resolved_at,assigned_to,caller_id,close_notes,work_notes,sys_class_name'
            $dateFilter = "sys_created_on>javascript:gs.monthsAgo($MonthsBack)"

            # As Requester (caller)
            if ($Role -in @('All', 'Requester', 'Both')) {
                Write-Verbose 'Querying tickets where user is requester...'
                $callerQuery = "caller_id.name=$UserIdentity^$dateFilter"
                $callerTickets = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/incident' `
                    -QueryParameters @{
                        sysparm_query  = $callerQuery
                        sysparm_fields = $fields
                        sysparm_limit  = '10000'
                    } -Paginate

                foreach ($t in @($callerTickets)) {
                    $ticket = Convert-SNOWTicketToObject -Ticket $t -UserIdentity $UserIdentity
                    $ticketsByRole['Requester'] += $ticket
                }
                Write-Verbose "Found $(@($callerTickets).Count) tickets as requester"
            }

            # As Assignee
            if ($Role -in @('All', 'Assignee', 'Both')) {
                Write-Verbose 'Querying tickets where user is assignee...'

                # Query across incident, change_request, and problem tables
                foreach ($table in @('incident', 'change_request', 'problem')) {
                    $assigneeQuery = "assigned_to.name=$UserIdentity^$dateFilter"
                    $assignedTickets = Connect-ServiceNow @authParams -Method GET -Endpoint "api/now/table/$table" `
                        -QueryParameters @{
                            sysparm_query  = $assigneeQuery
                            sysparm_fields = $fields
                            sysparm_limit  = '10000'
                        } -Paginate

                    foreach ($t in @($assignedTickets)) {
                        $ticket = Convert-SNOWTicketToObject -Ticket $t -UserIdentity $UserIdentity
                        $ticketsByRole['Assignee'] += $ticket
                    }
                    Write-Verbose "Found $(@($assignedTickets).Count) assigned tickets in $table"
                }
            }

            # Mentioned in watch list (All role only)
            if ($Role -eq 'All') {
                Write-Verbose 'Querying tickets where user is in watch list...'
                $watchQuery = "watch_listLIKE$UserIdentity^$dateFilter"
                $watchTickets = Connect-ServiceNow @authParams -Method GET -Endpoint 'api/now/table/incident' `
                    -QueryParameters @{
                        sysparm_query  = $watchQuery
                        sysparm_fields = $fields
                        sysparm_limit  = '5000'
                    } -Paginate

                foreach ($t in @($watchTickets)) {
                    $ticket = Convert-SNOWTicketToObject -Ticket $t -UserIdentity $UserIdentity
                    # Only add if not already captured as requester or assignee
                    $existingNumbers = ($ticketsByRole['Requester'] + $ticketsByRole['Assignee']) | ForEach-Object { $_.Number }
                    if ($ticket.Number -notin $existingNumbers) {
                        $ticketsByRole['Mentioned'] += $ticket
                    }
                }
                Write-Verbose "Found $(@($watchTickets).Count) tickets in watch list"
            }
        }

        'Jira' {
            if (-not $BaseUrl) {
                throw 'Jira provider requires -BaseUrl parameter.'
            }
            if (-not $Email) {
                throw 'Jira provider requires -Email parameter.'
            }

            $jiraAuthParams = @{
                BaseUrl = $BaseUrl
                Email   = $Email
            }
            if ($ApiKey) { $jiraAuthParams['ApiToken'] = $ApiKey }

            $jqlParts = @()

            if ($Role -in @('All', 'Requester', 'Both')) {
                $jqlParts += "reporter = ""$UserIdentity"""
            }
            if ($Role -in @('All', 'Assignee', 'Both')) {
                $jqlParts += "assignee = ""$UserIdentity"""
            }
            if ($Role -eq 'All') {
                $jqlParts += "text ~ ""$UserIdentity"""
            }

            $jql = "($($jqlParts -join ' OR ')) AND created >= ""-${MonthsBack}m"""

            Write-Verbose "Querying Jira: $jql"

            $jiraIssues = Connect-JiraSM @jiraAuthParams -Method GET -Endpoint 'rest/api/3/search' `
                -QueryParameters @{
                    jql        = $jql
                    maxResults = '100'
                    fields     = 'summary,description,status,priority,issuetype,created,resolutiondate,assignee,reporter,comment,components'
                } -Paginate

            foreach ($issue in @($jiraIssues)) {
                $ticket = ConvertFrom-JiraIssue -Issue $issue
                $reporter = if ($issue.fields.reporter) { $issue.fields.reporter.displayName } else { '' }
                $assignee = if ($issue.fields.assignee) { $issue.fields.assignee.displayName } else { '' }

                if ($reporter -like "*$UserIdentity*") {
                    $ticketsByRole['Requester'] += $ticket
                }
                elseif ($assignee -like "*$UserIdentity*") {
                    $ticketsByRole['Assignee'] += $ticket
                }
                else {
                    $ticketsByRole['Mentioned'] += $ticket
                }
            }
            Write-Verbose "Found $(@($jiraIssues).Count) Jira issues"
        }

        'File' {
            if (-not $FilePath) {
                throw 'File provider requires -FilePath parameter.'
            }

            $fileTickets = @(Import-TicketExport -Path $FilePath -UserFilter $UserIdentity -UserRole $Role -MonthsBack $MonthsBack)

            foreach ($ticket in $fileTickets) {
                if ($ticket.CallerName -like "*$UserIdentity*") {
                    $ticketsByRole['Requester'] += $ticket
                }
                elseif ($ticket.AssignedTo -like "*$UserIdentity*") {
                    $ticketsByRole['Assignee'] += $ticket
                }
                else {
                    $ticketsByRole['Mentioned'] += $ticket
                }
            }
            Write-Verbose "Imported $($fileTickets.Count) tickets from file"
        }
    }

    # Merge all tickets (deduplicate by number)
    $seenNumbers = @{}
    $allTickets = @()
    foreach ($roleKey in @('Requester', 'Assignee', 'Mentioned')) {
        foreach ($t in $ticketsByRole[$roleKey]) {
            if (-not $seenNumbers.ContainsKey($t.Number)) {
                $seenNumbers[$t.Number] = $true
                $allTickets += $t
            }
        }
    }

    $allTickets = @($allTickets | Sort-Object {
        try { [datetime]$_.OpenedAt } catch { [datetime]::MinValue }
    })

    # Identify open items
    $openItems = @($allTickets | Where-Object {
        $_.State -notmatch '(?i)(closed|resolved|cancelled|completed|done)'
    })

    # ── AI Summary ──
    $summary = ''
    $commonIssues = @()

    if (-not $SkipAI -and $allTickets.Count -gt 0) {
        Write-Verbose 'Generating AI summary...'

        $templatePath = Join-Path $PSScriptRoot '..\Templates\user-history-prompt.txt'
        if (Test-Path $templatePath) {
            $promptTemplate = Get-Content -Path $templatePath -Raw -Encoding UTF8
        }
        else {
            $promptTemplate = @"
You are an IT service management analyst. Given the following ticket history for user "{user_name}", provide a summary.

Analyze tickets and provide:
1. Summary
2. As Requester patterns
3. As Assignee patterns
4. Open Items
5. Recommendations

TICKET DATA:
{ticket_data}
"@
        }

        $ticketDataText = ($allTickets | ForEach-Object {
            $roleTag = if ($_.CallerName -like "*$UserIdentity*") { 'REQUESTER' }
                        elseif ($_.AssignedTo -like "*$UserIdentity*") { 'ASSIGNEE' }
                        else { 'MENTIONED' }
            "[$roleTag] [$($_.Type)] $($_.Number) | $($_.OpenedAt) | $($_.ShortDescription) | State: $($_.State) | Priority: $($_.Priority)"
        }) -join "`n"

        $prompt = $promptTemplate -replace '\{user_name\}', $UserIdentity -replace '\{ticket_data\}', $ticketDataText

        $aiParams = @{
            Prompt   = $prompt
            Provider = $AIProvider
        }
        if ($AIApiKey)   { $aiParams['ApiKey']   = $AIApiKey }
        if ($AIModel)    { $aiParams['Model']    = $AIModel }
        if ($AIEndpoint) { $aiParams['Endpoint'] = $AIEndpoint }

        try {
            $summary = Invoke-AICompletion @aiParams

            # Extract common issues from AI response (look for bulleted/numbered lists)
            $lines = $summary -split "`n"
            foreach ($line in $lines) {
                if ($line -match '^\s*[-*]\s+(.+)$' -and $line.Length -lt 200) {
                    $commonIssues += $Matches[1].Trim()
                }
            }
            # Limit to top issues
            $commonIssues = @($commonIssues | Select-Object -First 10)
        }
        catch {
            Write-Warning "AI summary generation failed: $($_.Exception.Message)"
            $summary = "[AI summary unavailable: $($_.Exception.Message)]"
        }
    }
    elseif ($allTickets.Count -eq 0) {
        $summary = "No tickets found for user '$UserIdentity' in the last $MonthsBack months."
    }

    # Build role breakdown as PSCustomObject for cleaner output
    $roleBreakdown = [PSCustomObject]@{
        Requester = $ticketsByRole['Requester']
        Assignee  = $ticketsByRole['Assignee']
        Mentioned = $ticketsByRole['Mentioned']
    }

    # ── Build result object ──
    $result = [PSCustomObject]@{
        UserName      = $UserIdentity
        TotalTickets  = $allTickets.Count
        TicketsByRole = $roleBreakdown
        Summary       = $summary
        CommonIssues  = $commonIssues
        OpenItems     = $openItems
        RawTickets    = $allTickets
        Provider      = $Provider
        MonthsBack    = $MonthsBack
        GeneratedAt   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    }

    # ── Generate HTML report if requested ──
    if ($OutputPath) {
        Write-Verbose "Generating HTML report: $OutputPath"
        New-HtmlDashboard -ReportType 'UserHistory' -Data $result -OutputPath $OutputPath
        Write-Host "HTML report saved to: $OutputPath" -ForegroundColor Cyan
    }

    return $result
}


function Convert-SNOWTicketToObject {
    <#
    .SYNOPSIS
        Helper to convert a raw ServiceNow ticket response into a normalized PSCustomObject.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Ticket,

        [Parameter()]
        [string]$UserIdentity
    )

    # Determine ticket type from sys_class_name or table context
    $type = switch ($Ticket.sys_class_name) {
        'incident'       { 'Incident' }
        'change_request' { 'Change Request' }
        'problem'        { 'Problem' }
        'sc_request'     { 'Service Request' }
        'sc_req_item'    { 'Requested Item' }
        default          { 'Incident' }
    }

    [PSCustomObject]@{
        Number           = $Ticket.number
        Type             = $type
        ShortDescription = $Ticket.short_description
        Description      = $Ticket.description
        State            = $Ticket.state
        Priority         = $Ticket.priority
        Category         = $Ticket.category
        Subcategory      = $Ticket.subcategory
        OpenedAt         = $Ticket.opened_at
        ClosedAt         = $Ticket.closed_at
        ResolvedAt       = $Ticket.resolved_at
        AssignedTo       = if ($Ticket.assigned_to -is [string]) { $Ticket.assigned_to } else { $Ticket.assigned_to.display_value }
        CallerName       = if ($Ticket.caller_id -is [string]) { $Ticket.caller_id } else { $Ticket.caller_id.display_value }
        CloseNotes       = $Ticket.close_notes
        WorkNotes        = $Ticket.work_notes
        CIName           = ''
        Source           = 'ServiceNow'
    }
}
