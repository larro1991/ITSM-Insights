function New-HtmlDashboard {
    <#
    .SYNOPSIS
        Generates a dark-themed HTML dashboard report with teal accent (#2dd4bf).
    .DESCRIPTION
        Creates styled HTML reports for CI history, user history, recurring issues,
        and knowledge gap analysis. Each report type has its own layout optimized
        for the data being presented.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('CIHistory', 'UserHistory', 'RecurringIssues', 'KnowledgeGaps')]
        [string]$ReportType,

        [Parameter(Mandatory)]
        [object]$Data,

        [Parameter(Mandatory)]
        [string]$OutputPath,

        [Parameter()]
        [string]$Title
    )

    # Base CSS for all reports
    $baseCss = @'
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', -apple-system, BlinkMacSystemFont, sans-serif;
            background: #0f172a;
            color: #e2e8f0;
            line-height: 1.6;
            padding: 2rem;
        }
        .container { max-width: 1200px; margin: 0 auto; }
        h1 {
            color: #2dd4bf;
            font-size: 1.8rem;
            margin-bottom: 0.5rem;
            border-bottom: 2px solid #2dd4bf;
            padding-bottom: 0.5rem;
        }
        h2 {
            color: #2dd4bf;
            font-size: 1.3rem;
            margin: 1.5rem 0 0.75rem 0;
        }
        h3 {
            color: #94a3b8;
            font-size: 1.1rem;
            margin: 1rem 0 0.5rem 0;
        }
        .subtitle {
            color: #94a3b8;
            font-size: 0.9rem;
            margin-bottom: 1.5rem;
        }
        .card {
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 8px;
            padding: 1.25rem;
            margin-bottom: 1rem;
        }
        .card-accent {
            border-left: 4px solid #2dd4bf;
        }
        .card-warning {
            border-left: 4px solid #f59e0b;
        }
        .card-danger {
            border-left: 4px solid #ef4444;
        }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 1rem;
            margin: 1rem 0;
        }
        .stat-card {
            background: #1e293b;
            border: 1px solid #334155;
            border-radius: 8px;
            padding: 1rem;
            text-align: center;
        }
        .stat-value {
            font-size: 2rem;
            font-weight: 700;
            color: #2dd4bf;
        }
        .stat-label {
            color: #94a3b8;
            font-size: 0.85rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
        }
        .summary-box {
            background: #1e293b;
            border: 1px solid #2dd4bf;
            border-radius: 8px;
            padding: 1.5rem;
            margin: 1rem 0;
            white-space: pre-wrap;
            font-size: 0.95rem;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 1rem 0;
            font-size: 0.9rem;
        }
        th {
            background: #334155;
            color: #2dd4bf;
            padding: 0.75rem;
            text-align: left;
            font-weight: 600;
            position: sticky;
            top: 0;
        }
        td {
            padding: 0.6rem 0.75rem;
            border-bottom: 1px solid #334155;
        }
        tr:hover { background: #1e293b; }
        .badge {
            display: inline-block;
            padding: 0.15rem 0.5rem;
            border-radius: 4px;
            font-size: 0.8rem;
            font-weight: 600;
        }
        .badge-incident { background: #7f1d1d; color: #fca5a5; }
        .badge-change { background: #1e3a5f; color: #93c5fd; }
        .badge-problem { background: #713f12; color: #fde68a; }
        .badge-request { background: #14532d; color: #86efac; }
        .badge-open { background: #7f1d1d; color: #fca5a5; }
        .badge-closed { background: #14532d; color: #86efac; }
        .badge-resolved { background: #1e3a5f; color: #93c5fd; }
        .badge-missing { background: #7f1d1d; color: #fca5a5; }
        .badge-stale { background: #713f12; color: #fde68a; }
        .badge-incomplete { background: #1e3a5f; color: #93c5fd; }
        .timeline {
            border-left: 3px solid #2dd4bf;
            margin: 1rem 0 1rem 1rem;
            padding-left: 1.5rem;
        }
        .timeline-item {
            position: relative;
            margin-bottom: 1.25rem;
        }
        .timeline-item::before {
            content: '';
            position: absolute;
            left: -1.85rem;
            top: 0.4rem;
            width: 10px;
            height: 10px;
            border-radius: 50%;
            background: #2dd4bf;
        }
        .timeline-date {
            color: #2dd4bf;
            font-weight: 600;
            font-size: 0.85rem;
        }
        .timeline-content {
            color: #cbd5e1;
            font-size: 0.9rem;
        }
        .pattern-card {
            background: #1e293b;
            border: 1px solid #334155;
            border-left: 4px solid #f59e0b;
            border-radius: 8px;
            padding: 1.25rem;
            margin-bottom: 1rem;
        }
        .pattern-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 0.75rem;
        }
        .pattern-count {
            background: #f59e0b;
            color: #0f172a;
            padding: 0.2rem 0.6rem;
            border-radius: 12px;
            font-weight: 700;
            font-size: 0.85rem;
        }
        .footer {
            margin-top: 2rem;
            padding-top: 1rem;
            border-top: 1px solid #334155;
            color: #64748b;
            font-size: 0.8rem;
            text-align: center;
        }
        pre {
            background: #0f172a;
            border: 1px solid #334155;
            border-radius: 4px;
            padding: 1rem;
            overflow-x: auto;
            white-space: pre-wrap;
            font-size: 0.85rem;
            color: #cbd5e1;
        }
'@

    $generatedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    # Build report body based on type
    $bodyHtml = switch ($ReportType) {
        'CIHistory' {
            $reportTitle = if ($Title) { $Title } else { "CI History: $($Data.CIName)" }
            Build-CIHistoryHtml -Data $Data -ReportTitle $reportTitle
        }
        'UserHistory' {
            $reportTitle = if ($Title) { $Title } else { "User Ticket History: $($Data.UserName)" }
            Build-UserHistoryHtml -Data $Data -ReportTitle $reportTitle
        }
        'RecurringIssues' {
            $reportTitle = if ($Title) { $Title } else { 'Recurring Issues Analysis' }
            Build-RecurringIssuesHtml -Data $Data -ReportTitle $reportTitle
        }
        'KnowledgeGaps' {
            $reportTitle = if ($Title) { $Title } else { 'Knowledge Gap Analysis' }
            Build-KnowledgeGapsHtml -Data $Data -ReportTitle $reportTitle
        }
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$reportTitle - ITSM Insights</title>
    <style>
$baseCss
    </style>
</head>
<body>
<div class="container">
$bodyHtml
    <div class="footer">
        Generated by ITSM-Insights on $generatedAt | AI-powered ITSM ticket intelligence
    </div>
</div>
</body>
</html>
"@

    # Ensure output directory exists
    $outputDir = Split-Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
    }

    $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
    Write-Verbose "HTML report saved to: $OutputPath"
    return $OutputPath
}


function Build-CIHistoryHtml {
    param([object]$Data, [string]$ReportTitle)

    $statsHtml = @"
    <h1>$ReportTitle</h1>
    <p class="subtitle">Ticket history analysis covering $($Data.TicketCount) tickets</p>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">$($Data.TicketCount)</div>
            <div class="stat-label">Total Tickets</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$($Data.IncidentCount)</div>
            <div class="stat-label">Incidents</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$($Data.ChangeCount)</div>
            <div class="stat-label">Changes</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$($Data.ProblemCount)</div>
            <div class="stat-label">Problems</div>
        </div>
    </div>
"@

    # AI Summary
    $summaryHtml = ''
    if ($Data.Summary) {
        $escapedSummary = [System.Net.WebUtility]::HtmlEncode($Data.Summary)
        $summaryHtml = @"
    <h2>AI Analysis Summary</h2>
    <div class="summary-box">$escapedSummary</div>
"@
    }

    # Timeline
    $timelineHtml = ''
    if ($Data.Timeline -and $Data.Timeline.Count -gt 0) {
        $timelineItems = foreach ($item in $Data.Timeline) {
            $badgeClass = switch -Wildcard ($item.Type) {
                '*Incident*' { 'badge-incident' }
                '*Change*'   { 'badge-change' }
                '*Problem*'  { 'badge-problem' }
                default      { 'badge-request' }
            }
            @"
        <div class="timeline-item">
            <div class="timeline-date">$($item.Date) <span class="badge $badgeClass">$($item.Type)</span></div>
            <div class="timeline-content"><strong>$($item.Number)</strong> - $([System.Net.WebUtility]::HtmlEncode($item.Description))</div>
        </div>
"@
        }
        $timelineHtml = @"
    <h2>Event Timeline</h2>
    <div class="timeline">
$($timelineItems -join "`n")
    </div>
"@
    }

    # Open Items
    $openItemsHtml = ''
    if ($Data.OpenItems -and $Data.OpenItems.Count -gt 0) {
        $openRows = foreach ($item in $Data.OpenItems) {
            "<tr><td>$($item.Number)</td><td>$([System.Net.WebUtility]::HtmlEncode($item.ShortDescription))</td><td>$($item.Priority)</td><td>$($item.AssignedTo)</td></tr>"
        }
        $openItemsHtml = @"
    <h2>Open Items</h2>
    <div class="card card-warning">
        <table>
            <tr><th>Number</th><th>Description</th><th>Priority</th><th>Assigned To</th></tr>
$($openRows -join "`n")
        </table>
    </div>
"@
    }

    # Ticket table
    $ticketRows = foreach ($ticket in ($Data.RawTickets | Select-Object -First 50)) {
        $badgeClass = switch -Wildcard ($ticket.Type) {
            '*Incident*' { 'badge-incident' }
            '*Change*'   { 'badge-change' }
            '*Problem*'  { 'badge-problem' }
            default      { 'badge-request' }
        }
        $stateClass = switch -Wildcard ($ticket.State) {
            '*Open*'     { 'badge-open' }
            '*New*'      { 'badge-open' }
            '*Progress*' { 'badge-open' }
            '*Closed*'   { 'badge-closed' }
            '*Resolved*' { 'badge-resolved' }
            default      { 'badge-resolved' }
        }
        "<tr><td>$($ticket.Number)</td><td><span class=`"badge $badgeClass`">$($ticket.Type)</span></td><td>$([System.Net.WebUtility]::HtmlEncode($ticket.ShortDescription))</td><td><span class=`"badge $stateClass`">$($ticket.State)</span></td><td>$($ticket.Priority)</td><td>$($ticket.OpenedAt)</td></tr>"
    }

    $ticketTableHtml = @"
    <h2>All Tickets</h2>
    <table>
        <tr><th>Number</th><th>Type</th><th>Description</th><th>State</th><th>Priority</th><th>Opened</th></tr>
$($ticketRows -join "`n")
    </table>
"@

    return "$statsHtml`n$summaryHtml`n$timelineHtml`n$openItemsHtml`n$ticketTableHtml"
}


function Build-UserHistoryHtml {
    param([object]$Data, [string]$ReportTitle)

    $totalTickets = 0
    $roleBreakdown = ''
    if ($Data.TicketsByRole) {
        foreach ($role in $Data.TicketsByRole.PSObject.Properties) {
            $count = @($role.Value).Count
            $totalTickets += $count
            $roleBreakdown += "        <div class=`"stat-card`"><div class=`"stat-value`">$count</div><div class=`"stat-label`">As $($role.Name)</div></div>`n"
        }
    }

    $html = @"
    <h1>$ReportTitle</h1>
    <p class="subtitle">Complete ticket interaction history</p>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">$totalTickets</div>
            <div class="stat-label">Total Tickets</div>
        </div>
$roleBreakdown
    </div>
"@

    if ($Data.Summary) {
        $escapedSummary = [System.Net.WebUtility]::HtmlEncode($Data.Summary)
        $html += @"

    <h2>AI Analysis</h2>
    <div class="summary-box">$escapedSummary</div>
"@
    }

    if ($Data.CommonIssues -and $Data.CommonIssues.Count -gt 0) {
        $issueCards = foreach ($issue in $Data.CommonIssues) {
            "<div class=`"card card-accent`"><strong>$([System.Net.WebUtility]::HtmlEncode($issue))</strong></div>"
        }
        $html += @"

    <h2>Common Issue Types</h2>
$($issueCards -join "`n")
"@
    }

    if ($Data.OpenItems -and $Data.OpenItems.Count -gt 0) {
        $openRows = foreach ($item in $Data.OpenItems) {
            "<tr><td>$($item.Number)</td><td>$([System.Net.WebUtility]::HtmlEncode($item.ShortDescription))</td><td>$($item.State)</td></tr>"
        }
        $html += @"

    <h2>Open Items</h2>
    <div class="card card-warning">
        <table>
            <tr><th>Number</th><th>Description</th><th>State</th></tr>
$($openRows -join "`n")
        </table>
    </div>
"@
    }

    return $html
}


function Build-RecurringIssuesHtml {
    param([object]$Data, [string]$ReportTitle)

    $html = @"
    <h1>$ReportTitle</h1>
    <p class="subtitle">AI-detected patterns across ticket history</p>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">$(@($Data).Count)</div>
            <div class="stat-label">Patterns Detected</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$(($Data | Measure-Object -Property Occurrences -Sum).Sum)</div>
            <div class="stat-label">Total Occurrences</div>
        </div>
    </div>
"@

    foreach ($pattern in $Data) {
        $ticketList = if ($pattern.TicketNumbers) { ($pattern.TicketNumbers -join ', ') } else { 'N/A' }
        $escapedResolution = [System.Net.WebUtility]::HtmlEncode($pattern.SuggestedResolution)
        $html += @"

    <div class="pattern-card">
        <div class="pattern-header">
            <h3>$([System.Net.WebUtility]::HtmlEncode($pattern.Pattern))</h3>
            <span class="pattern-count">$($pattern.Occurrences) occurrences</span>
        </div>
        <p><strong>Tickets:</strong> $ticketList</p>
        <p><strong>First Seen:</strong> $($pattern.FirstSeen) | <strong>Last Seen:</strong> $($pattern.LastSeen)</p>
        <p><strong>Estimated Time Saved if Fixed:</strong> $($pattern.EstimatedTimeSaved)</p>
        <h3>Suggested Resolution</h3>
        <pre>$escapedResolution</pre>
    </div>
"@
    }

    return $html
}


function Build-KnowledgeGapsHtml {
    param([object]$Data, [string]$ReportTitle)

    $html = @"
    <h1>$ReportTitle</h1>
    <p class="subtitle">Knowledge base gaps identified from ticket analysis</p>

    <div class="stats-grid">
        <div class="stat-card">
            <div class="stat-value">$(@($Data | Where-Object { $_.GapType -eq 'Missing' }).Count)</div>
            <div class="stat-label">Missing Articles</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$(@($Data | Where-Object { $_.GapType -eq 'Stale' }).Count)</div>
            <div class="stat-label">Stale Articles</div>
        </div>
        <div class="stat-card">
            <div class="stat-value">$(@($Data | Where-Object { $_.GapType -eq 'Incomplete' }).Count)</div>
            <div class="stat-label">Incomplete Articles</div>
        </div>
    </div>
"@

    foreach ($gap in $Data) {
        $badgeClass = switch ($gap.GapType) {
            'Missing'    { 'badge-missing' }
            'Stale'      { 'badge-stale' }
            'Incomplete' { 'badge-incomplete' }
            default      { 'badge-missing' }
        }
        $ticketList = if ($gap.RelatedTickets) { ($gap.RelatedTickets -join ', ') } else { 'N/A' }
        $escapedContent = [System.Net.WebUtility]::HtmlEncode($gap.SuggestedContent)

        $html += @"

    <div class="card card-accent">
        <div class="pattern-header">
            <h3>$([System.Net.WebUtility]::HtmlEncode($gap.Topic))</h3>
            <span class="badge $badgeClass">$($gap.GapType)</span>
        </div>
        <p><strong>Suggested Title:</strong> $([System.Net.WebUtility]::HtmlEncode($gap.SuggestedTitle))</p>
        <p><strong>Related Tickets:</strong> $ticketList</p>
        <h3>Suggested Content</h3>
        <pre>$escapedContent</pre>
    </div>
"@
    }

    return $html
}
