function Connect-JiraSM {
    <#
    .SYNOPSIS
        Executes authenticated REST API requests against Jira Service Management.
    .DESCRIPTION
        Handles Jira REST API authentication (email + API token via basic auth),
        JQL query construction, pagination, and rate limit handling.
        Returns parsed JSON response objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaseUrl,

        [Parameter(Mandatory)]
        [string]$Email,

        [Parameter()]
        [string]$ApiToken,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [hashtable]$QueryParameters,

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [int]$PageSize = 100,

        [Parameter()]
        [int]$MaxRecords = 10000,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    # Resolve API token from environment if not provided
    if (-not $ApiToken) {
        if ($env:JIRA_API_TOKEN) {
            $ApiToken = $env:JIRA_API_TOKEN
        }
        else {
            throw 'No API token provided for Jira. Supply -ApiToken or set $env:JIRA_API_TOKEN.'
        }
    }

    # Build base URL
    $cleanBaseUrl = $BaseUrl.TrimEnd('/')

    # Build authentication headers (Jira uses basic auth with email:token)
    $pair = "${Email}:${ApiToken}"
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
    $base64 = [System.Convert]::ToBase64String($bytes)

    $headers = @{
        'Authorization' = "Basic $base64"
        'Accept'        = 'application/json'
        'Content-Type'  = 'application/json'
    }

    # Build the full URL
    $fullEndpoint = $Endpoint.TrimStart('/')
    $url = "$cleanBaseUrl/$fullEndpoint"

    # Add query parameters
    if ($QueryParameters -and $QueryParameters.Count -gt 0) {
        $queryParts = @()
        foreach ($key in $QueryParameters.Keys) {
            $encodedValue = [System.Uri]::EscapeDataString($QueryParameters[$key])
            $queryParts += "${key}=${encodedValue}"
        }
        $queryString = $queryParts -join '&'
        $url = "${url}?${queryString}"
    }

    # Non-paginated request
    if (-not $Paginate) {
        return Invoke-JiraRequestInternal -Url $url -Method $Method -Headers $headers -Body $Body -MaxRetries $MaxRetries
    }

    # Paginated search request (Jira uses startAt/maxResults)
    if ($Method -ne 'GET' -and $Method -ne 'POST') {
        Write-Warning 'Pagination is only supported for GET/POST search requests. Executing single request.'
        return Invoke-JiraRequestInternal -Url $url -Method $Method -Headers $headers -Body $Body -MaxRetries $MaxRetries
    }

    $allResults = @()
    $startAt = 0
    $hasMore = $true

    while ($hasMore -and $allResults.Count -lt $MaxRecords) {
        # For GET requests, append pagination to query string
        $separator = if ($url -match '\?') { '&' } else { '?' }
        $pageUrl = "${url}${separator}startAt=${startAt}&maxResults=${PageSize}"

        Write-Verbose "Jira paginated request: startAt=$startAt, maxResults=$PageSize"

        $response = Invoke-JiraRequestInternal -Url $pageUrl -Method $Method -Headers $headers -Body $Body -MaxRetries $MaxRetries

        if ($null -eq $response) {
            $hasMore = $false
            continue
        }

        # Jira search results have issues array and total count
        $issues = if ($response.PSObject.Properties['issues']) {
            $response.issues
        }
        elseif ($response.PSObject.Properties['values']) {
            $response.values
        }
        else {
            $response
        }

        if ($null -eq $issues -or @($issues).Count -eq 0) {
            $hasMore = $false
        }
        else {
            $batch = @($issues)
            $allResults += $batch
            $startAt += $batch.Count

            # Check if we've gotten all results
            $total = if ($response.PSObject.Properties['total']) { $response.total } else { 0 }
            if ($startAt -ge $total -or $batch.Count -lt $PageSize) {
                $hasMore = $false
            }

            Write-Verbose "Retrieved $($batch.Count) issues (total: $($allResults.Count) of $total)"
        }
    }

    if ($allResults.Count -ge $MaxRecords) {
        Write-Warning "Reached maximum record limit ($MaxRecords). Results may be incomplete."
    }

    return $allResults
}


function Invoke-JiraRequestInternal {
    <#
    .SYNOPSIS
        Internal helper for executing a single Jira REST API request with retry logic.
    #>
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$Method,
        [hashtable]$Headers,
        [hashtable]$Body,
        [int]$MaxRetries = 3
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            $splat = @{
                Uri         = $Url
                Method      = $Method
                Headers     = $Headers
                ErrorAction = 'Stop'
            }

            if ($Body -and $Method -in @('POST', 'PUT')) {
                $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
                if ($PSVersionTable.PSVersion.Major -le 5) {
                    $splat['Body'] = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
                }
                else {
                    $splat['Body'] = $jsonBody
                }
            }

            Write-Verbose "Jira $Method $Url (attempt $attempt)"
            $response = Invoke-RestMethod @splat
            return $response
        }
        catch {
            $lastError = $_
            $statusCode = $null

            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            switch ($statusCode) {
                401 {
                    throw "Jira authentication failed (401). Check your email and API token. URL: $Url"
                }
                403 {
                    throw "Jira access denied (403). Insufficient permissions. URL: $Url"
                }
                404 {
                    Write-Warning "Jira resource not found (404): $Url"
                    return $null
                }
                429 {
                    $retryAfter = 10
                    if ($_.Exception.Response.Headers) {
                        try {
                            $retryHeader = $_.Exception.Response.Headers.GetValues('Retry-After')
                            if ($retryHeader) {
                                $retryAfter = [int]$retryHeader[0]
                            }
                        }
                        catch { }
                    }
                    Write-Warning "Jira rate limited (429). Waiting $retryAfter seconds (attempt $attempt/$MaxRetries)."
                    Start-Sleep -Seconds $retryAfter
                }
                default {
                    if ($attempt -lt $MaxRetries) {
                        $backoff = [math]::Pow(2, $attempt)
                        Write-Warning "Jira request failed (attempt $attempt/$MaxRetries). Retrying in $backoff seconds. Error: $($_.Exception.Message)"
                        Start-Sleep -Seconds $backoff
                    }
                }
            }
        }
    }

    throw "Jira request failed after $MaxRetries attempts. URL: $Url. Last error: $($lastError.Exception.Message)"
}


function ConvertFrom-JiraIssue {
    <#
    .SYNOPSIS
        Converts Jira issue objects to normalized ticket objects matching the ServiceNow schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Issue
    )

    process {
        $fields = $Issue.fields

        # Map Jira issue type to ITSM ticket type
        $ticketType = switch -Wildcard ($fields.issuetype.name) {
            '*Incident*'     { 'Incident' }
            '*Problem*'      { 'Problem' }
            '*Change*'       { 'Change Request' }
            '*Service*'      { 'Service Request' }
            '*Bug*'          { 'Incident' }
            '*Task*'         { 'Change Request' }
            default          { 'Incident' }
        }

        # Map Jira status to normalized state
        $state = switch -Wildcard ($fields.status.name) {
            '*Open*'         { 'Open' }
            '*New*'          { 'New' }
            '*Progress*'     { 'In Progress' }
            '*Review*'       { 'In Review' }
            '*Resolved*'     { 'Resolved' }
            '*Closed*'       { 'Closed' }
            '*Done*'         { 'Closed' }
            '*Cancelled*'    { 'Cancelled' }
            default          { $fields.status.name }
        }

        # Map Jira priority
        $priority = switch ($fields.priority.name) {
            'Highest' { '1 - Critical' }
            'High'    { '2 - High' }
            'Medium'  { '3 - Moderate' }
            'Low'     { '4 - Low' }
            'Lowest'  { '5 - Planning' }
            default   { '3 - Moderate' }
        }

        [PSCustomObject]@{
            Number           = $Issue.key
            Type             = $ticketType
            ShortDescription = $fields.summary
            Description      = $fields.description
            State            = $state
            Priority         = $priority
            Category         = if ($fields.components) { ($fields.components | Select-Object -First 1).name } else { '' }
            Subcategory      = ''
            OpenedAt         = $fields.created
            ClosedAt         = $fields.resolutiondate
            ResolvedAt       = $fields.resolutiondate
            AssignedTo       = if ($fields.assignee) { $fields.assignee.displayName } else { 'Unassigned' }
            CallerName       = if ($fields.reporter) { $fields.reporter.displayName } else { '' }
            CloseNotes       = if ($fields.resolution) { $fields.resolution.name } else { '' }
            WorkNotes        = if ($fields.comment -and $fields.comment.comments) {
                ($fields.comment.comments | ForEach-Object { $_.body } ) -join "`n---`n"
            } else { '' }
            Source           = 'Jira'
        }
    }
}
