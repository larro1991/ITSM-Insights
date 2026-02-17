function Invoke-AICompletion {
    <#
    .SYNOPSIS
        Provider-agnostic LLM API caller supporting Anthropic, OpenAI, Ollama, and custom endpoints.
    .DESCRIPTION
        Sends a prompt to the configured AI provider and returns the completion text.
        Handles authentication, retries on rate limits, and provider-specific API formats.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [ValidateSet('Anthropic', 'OpenAI', 'Ollama', 'Custom')]
        [string]$Provider = 'Anthropic',

        [Parameter()]
        [string]$ApiKey,

        [Parameter()]
        [string]$Model,

        [Parameter()]
        [string]$Endpoint,

        [Parameter()]
        [string]$SystemPrompt,

        [Parameter()]
        [double]$Temperature = 0.1,

        [Parameter()]
        [int]$MaxTokens = 4096,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    # Resolve API key from environment if not provided
    if (-not $ApiKey) {
        $ApiKey = switch ($Provider) {
            'Anthropic' {
                if ($env:LIVINGDOC_API_KEY) { $env:LIVINGDOC_API_KEY }
                elseif ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY }
                else { $null }
            }
            'OpenAI' {
                if ($env:LIVINGDOC_API_KEY) { $env:LIVINGDOC_API_KEY }
                elseif ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY }
                else { $null }
            }
            default { $null }
        }
    }

    # Resolve default model per provider
    if (-not $Model) {
        $Model = switch ($Provider) {
            'Anthropic' { 'claude-sonnet-4-20250514' }
            'OpenAI'    { 'gpt-4o' }
            'Ollama'    { 'llama3.1:8b' }
            'Custom'    { 'default' }
        }
    }

    # Resolve endpoint
    if (-not $Endpoint) {
        $Endpoint = switch ($Provider) {
            'Anthropic' { 'https://api.anthropic.com/v1/messages' }
            'OpenAI'    { 'https://api.openai.com/v1/chat/completions' }
            'Ollama'    { 'http://localhost:11434/api/chat' }
            'Custom'    { throw 'Custom provider requires -Endpoint parameter.' }
        }
    }

    # Validate API key for cloud providers
    if ($Provider -in @('Anthropic', 'OpenAI') -and -not $ApiKey) {
        throw "No API key found for $Provider. Provide -ApiKey, set `$env:LIVINGDOC_API_KEY, or set the provider-specific environment variable."
    }

    # Build request based on provider
    $headers = @{}
    $body = $null

    switch ($Provider) {
        'Anthropic' {
            $headers = @{
                'x-api-key'         = $ApiKey
                'anthropic-version' = '2023-06-01'
                'Content-Type'      = 'application/json'
            }
            $messageList = @(
                @{ role = 'user'; content = $Prompt }
            )
            $bodyObj = @{
                model       = $Model
                max_tokens  = $MaxTokens
                temperature = $Temperature
                messages    = $messageList
            }
            if ($SystemPrompt) {
                $bodyObj['system'] = $SystemPrompt
            }
            $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
        }

        'OpenAI' {
            $headers = @{
                'Authorization' = "Bearer $ApiKey"
                'Content-Type'  = 'application/json'
            }
            $messages = @()
            if ($SystemPrompt) {
                $messages += @{ role = 'system'; content = $SystemPrompt }
            }
            $messages += @{ role = 'user'; content = $Prompt }
            $bodyObj = @{
                model       = $Model
                temperature = $Temperature
                max_tokens  = $MaxTokens
                messages    = $messages
            }
            $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
        }

        'Ollama' {
            $headers = @{
                'Content-Type' = 'application/json'
            }
            $messages = @()
            if ($SystemPrompt) {
                $messages += @{ role = 'system'; content = $SystemPrompt }
            }
            $messages += @{ role = 'user'; content = $Prompt }
            $bodyObj = @{
                model    = $Model
                messages = $messages
                stream   = $false
                options  = @{
                    temperature = $Temperature
                }
            }
            $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
        }

        'Custom' {
            # Custom uses OpenAI-compatible format by default
            $headers = @{
                'Content-Type' = 'application/json'
            }
            if ($ApiKey) {
                $headers['Authorization'] = "Bearer $ApiKey"
            }
            $messages = @()
            if ($SystemPrompt) {
                $messages += @{ role = 'system'; content = $SystemPrompt }
            }
            $messages += @{ role = 'user'; content = $Prompt }
            $bodyObj = @{
                model       = $Model
                temperature = $Temperature
                max_tokens  = $MaxTokens
                messages    = $messages
            }
            $body = $bodyObj | ConvertTo-Json -Depth 10 -Compress
        }
    }

    # Execute with retry logic
    $attempt = 0
    $lastError = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++
        try {
            Write-Verbose "AI request attempt $attempt/$MaxRetries to $Provider ($Model)"

            $splat = @{
                Uri         = $Endpoint
                Method      = 'POST'
                Headers     = $headers
                Body        = $body
                ErrorAction = 'Stop'
            }
            # PowerShell 5.1 needs explicit UTF-8 encoding
            if ($PSVersionTable.PSVersion.Major -le 5) {
                $splat['Body'] = [System.Text.Encoding]::UTF8.GetBytes($body)
            }

            $response = Invoke-RestMethod @splat

            # Extract text based on provider response format
            $resultText = switch ($Provider) {
                'Anthropic' {
                    if ($response.content -and $response.content.Count -gt 0) {
                        $response.content[0].text
                    }
                    else {
                        throw 'Anthropic response contained no content.'
                    }
                }
                'OpenAI' {
                    if ($response.choices -and $response.choices.Count -gt 0) {
                        $response.choices[0].message.content
                    }
                    else {
                        throw 'OpenAI response contained no choices.'
                    }
                }
                'Ollama' {
                    if ($response.message) {
                        $response.message.content
                    }
                    else {
                        throw 'Ollama response contained no message.'
                    }
                }
                'Custom' {
                    # Try OpenAI format first, then raw
                    if ($response.choices -and $response.choices.Count -gt 0) {
                        $response.choices[0].message.content
                    }
                    elseif ($response.content -and $response.content.Count -gt 0) {
                        $response.content[0].text
                    }
                    elseif ($response.message) {
                        $response.message.content
                    }
                    elseif ($response.text) {
                        $response.text
                    }
                    else {
                        throw 'Custom endpoint response format not recognized.'
                    }
                }
            }

            Write-Verbose "AI response received: $($resultText.Length) characters"
            return $resultText
        }
        catch {
            $lastError = $_
            $statusCode = $null

            # Extract HTTP status code from exception
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            switch ($statusCode) {
                401 {
                    throw "Authentication failed for $Provider. Check your API key or credentials. Error: $($_.Exception.Message)"
                }
                403 {
                    throw "Access denied for $Provider. Check API key permissions. Error: $($_.Exception.Message)"
                }
                429 {
                    # Rate limited - extract retry-after or use exponential backoff
                    $retryAfter = 0
                    if ($_.Exception.Response.Headers) {
                        $retryHeader = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' }
                        if ($retryHeader) {
                            $retryAfter = [int]$retryHeader.Value[0]
                        }
                    }
                    if ($retryAfter -lt 1) {
                        $retryAfter = [math]::Pow(2, $attempt) * 2
                    }
                    Write-Warning "Rate limited by $Provider. Waiting $retryAfter seconds before retry ($attempt/$MaxRetries)."
                    Start-Sleep -Seconds $retryAfter
                }
                default {
                    if ($attempt -lt $MaxRetries) {
                        $backoff = [math]::Pow(2, $attempt)
                        Write-Warning "AI request failed (attempt $attempt/$MaxRetries). Retrying in $backoff seconds. Error: $($_.Exception.Message)"
                        Start-Sleep -Seconds $backoff
                    }
                }
            }
        }
    }

    throw "AI request failed after $MaxRetries attempts. Last error: $($lastError.Exception.Message)"
}
