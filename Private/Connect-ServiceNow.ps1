function Connect-ServiceNow {
    <#
    .SYNOPSIS
        Executes authenticated REST API requests against a ServiceNow instance.
    .DESCRIPTION
        Handles ServiceNow REST API authentication (basic auth or API key/token),
        URL construction, pagination, and rate limit handling.
        Returns parsed JSON response objects.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Instance,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Endpoint,

        [Parameter()]
        [PSCredential]$Credential,

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [hashtable]$QueryParameters,

        [Parameter()]
        [switch]$Paginate,

        [Parameter()]
        [int]$PageSize = 1000,

        [Parameter()]
        [int]$MaxRecords = 50000,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    # Build base URL
    $baseUrl = if ($Instance -match '^https?://') {
        $Instance.TrimEnd('/')
    }
    else {
        "https://$Instance"
    }

    # Build authentication headers
    $headers = @{
        'Accept'       = 'application/json'
        'Content-Type' = 'application/json'
    }

    # Resolve API key from environment if not provided
    if (-not $ApiKey -and -not $Credential) {
        if ($env:SNOW_API_KEY) {
            $ApiKey = $env:SNOW_API_KEY
        }
    }

    if ($Credential) {
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        $pair = "${username}:${password}"
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
        $base64 = [System.Convert]::ToBase64String($bytes)
        $headers['Authorization'] = "Basic $base64"
    }
    elseif ($ApiKey) {
        # ServiceNow supports Bearer token or custom header depending on config
        $headers['Authorization'] = "Bearer $ApiKey"
    }
    else {
        throw 'No authentication provided for ServiceNow. Supply -Credential, -ApiKey, or set $env:SNOW_API_KEY.'
    }

    # Build the full URL
    $fullEndpoint = $Endpoint.TrimStart('/')
    $url = "$baseUrl/$fullEndpoint"

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
        return Invoke-SNOWRequestInternal -Url $url -Method $Method -Headers $headers -Body $Body -MaxRetries $MaxRetries
    }

    # Paginated request (GET only)
    if ($Method -ne 'GET') {
        Write-Warning 'Pagination is only supported for GET requests. Executing single request.'
        return Invoke-SNOWRequestInternal -Url $url -Method $Method -Headers $headers -Body $Body -MaxRetries $MaxRetries
    }

    $allResults = @()
    $offset = 0
    $hasMore = $true

    while ($hasMore -and $allResults.Count -lt $MaxRecords) {
        # Append pagination parameters
        $separator = if ($url -match '\?') { '&' } else { '?' }
        $pageUrl = "${url}${separator}sysparm_limit=${PageSize}&sysparm_offset=${offset}"

        Write-Verbose "ServiceNow paginated request: offset=$offset, limit=$PageSize"

        $response = Invoke-SNOWRequestInternal -Url $pageUrl -Method 'GET' -Headers $headers -MaxRetries $MaxRetries

        if ($null -eq $response) {
            $hasMore = $false
            continue
        }

        # ServiceNow wraps results in a 'result' property
        $records = if ($response.PSObject.Properties['result']) {
            $response.result
        }
        else {
            $response
        }

        if ($null -eq $records -or @($records).Count -eq 0) {
            $hasMore = $false
        }
        else {
            $batch = @($records)
            $allResults += $batch
            $offset += $batch.Count

            if ($batch.Count -lt $PageSize) {
                $hasMore = $false
            }

            Write-Verbose "Retrieved $($batch.Count) records (total: $($allResults.Count))"
        }
    }

    if ($allResults.Count -ge $MaxRecords) {
        Write-Warning "Reached maximum record limit ($MaxRecords). Results may be incomplete."
    }

    return $allResults
}


function Invoke-SNOWRequestInternal {
    <#
    .SYNOPSIS
        Internal helper for executing a single ServiceNow REST API request with retry logic.
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

            if ($Body -and $Method -in @('POST', 'PUT', 'PATCH')) {
                $jsonBody = $Body | ConvertTo-Json -Depth 10 -Compress
                if ($PSVersionTable.PSVersion.Major -le 5) {
                    $splat['Body'] = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
                }
                else {
                    $splat['Body'] = $jsonBody
                }
            }

            Write-Verbose "ServiceNow $Method $Url (attempt $attempt)"
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
                    throw "ServiceNow authentication failed (401). Check your credentials or API key. URL: $Url"
                }
                403 {
                    throw "ServiceNow access denied (403). Insufficient permissions. URL: $Url"
                }
                404 {
                    Write-Warning "ServiceNow resource not found (404): $Url"
                    return $null
                }
                429 {
                    $retryAfter = 5
                    if ($_.Exception.Response.Headers) {
                        try {
                            $retryHeader = $_.Exception.Response.Headers.GetValues('Retry-After')
                            if ($retryHeader) {
                                $retryAfter = [int]$retryHeader[0]
                            }
                        }
                        catch {
                            # Header not present, use default
                        }
                    }
                    Write-Warning "ServiceNow rate limited (429). Waiting $retryAfter seconds (attempt $attempt/$MaxRetries)."
                    Start-Sleep -Seconds $retryAfter
                }
                default {
                    if ($attempt -lt $MaxRetries) {
                        $backoff = [math]::Pow(2, $attempt)
                        Write-Warning "ServiceNow request failed (attempt $attempt/$MaxRetries). Retrying in $backoff seconds. Error: $($_.Exception.Message)"
                        Start-Sleep -Seconds $backoff
                    }
                }
            }
        }
    }

    throw "ServiceNow request failed after $MaxRetries attempts. URL: $Url. Last error: $($lastError.Exception.Message)"
}
