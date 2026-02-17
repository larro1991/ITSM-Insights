function Import-TicketExport {
    <#
    .SYNOPSIS
        Imports ticket data from CSV or JSON files and normalizes column names to a standard schema.
    .DESCRIPTION
        Reads CSV or JSON ticket exports from any ITSM platform, auto-detects the format
        by file extension, and normalizes column/property names to a consistent schema
        matching the ServiceNow API output format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter()]
        [string]$CIFilter,

        [Parameter()]
        [string]$UserFilter,

        [Parameter()]
        [string]$UserRole = 'All',

        [Parameter()]
        [int]$MonthsBack = 18
    )

    # Validate file exists
    if (-not (Test-Path $Path)) {
        throw "Ticket export file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path).ToLower()

    # Read data based on format
    $rawData = switch ($extension) {
        '.csv' {
            Write-Verbose "Importing CSV file: $Path"
            Import-Csv -Path $Path -Encoding UTF8
        }
        '.json' {
            Write-Verbose "Importing JSON file: $Path"
            $content = Get-Content -Path $Path -Raw -Encoding UTF8
            $parsed = $content | ConvertFrom-Json
            # Handle JSON that may have a wrapper object (e.g., { "result": [...] } or { "tickets": [...] })
            if ($parsed.PSObject.Properties['result']) {
                $parsed.result
            }
            elseif ($parsed.PSObject.Properties['tickets']) {
                $parsed.tickets
            }
            elseif ($parsed.PSObject.Properties['issues']) {
                $parsed.issues
            }
            elseif ($parsed -is [array]) {
                $parsed
            }
            else {
                @($parsed)
            }
        }
        default {
            throw "Unsupported file format '$extension'. Use .csv or .json files."
        }
    }

    if ($null -eq $rawData -or @($rawData).Count -eq 0) {
        Write-Warning "No records found in $Path"
        return @()
    }

    Write-Verbose "Loaded $(@($rawData).Count) raw records from file"

    # Column name mapping: source variations -> normalized name
    $columnMap = @{
        'Number'           = @('number', 'ticket_number', 'ticket number', 'ticketnumber', 'id', 'ticket_id', 'ticketid', 'key', 'issue_key', 'ref', 'reference')
        'Type'             = @('type', 'ticket_type', 'ticket type', 'tickettype', 'issue_type', 'issuetype', 'record_type', 'sys_class_name')
        'ShortDescription' = @('short_description', 'short description', 'shortdescription', 'summary', 'title', 'subject')
        'Description'      = @('description', 'detailed_description', 'detail', 'details', 'body', 'long_description')
        'State'            = @('state', 'status', 'ticket_state', 'incident_state', 'workflow_state')
        'Priority'         = @('priority', 'urgency', 'severity', 'impact')
        'Category'         = @('category', 'service_category', 'ticket_category', 'component')
        'Subcategory'      = @('subcategory', 'sub_category', 'sub-category', 'subcomponent')
        'OpenedAt'         = @('opened_at', 'opened at', 'openedat', 'created', 'created_at', 'createdat', 'create_date', 'open_date', 'opened_date', 'sys_created_on')
        'ClosedAt'         = @('closed_at', 'closed at', 'closedat', 'closed_date', 'close_date', 'resolved_date', 'completion_date')
        'ResolvedAt'       = @('resolved_at', 'resolved at', 'resolvedat', 'resolution_date', 'resolve_date')
        'AssignedTo'       = @('assigned_to', 'assigned to', 'assignedto', 'assignee', 'owner', 'assigned_user', 'technician', 'resolver')
        'CallerName'       = @('caller_id', 'caller', 'caller_name', 'requester', 'reporter', 'requested_by', 'requestedby', 'raised_by', 'opened_by', 'customer', 'user')
        'CloseNotes'       = @('close_notes', 'close notes', 'closenotes', 'resolution_notes', 'resolution', 'close_description', 'fix', 'workaround')
        'WorkNotes'        = @('work_notes', 'work notes', 'worknotes', 'comments', 'notes', 'activity', 'journal', 'updates')
        'CIName'           = @('cmdb_ci', 'ci', 'ci_name', 'configuration_item', 'server', 'server_name', 'hostname', 'host', 'affected_ci', 'asset', 'device')
    }

    # Detect the mapping from source columns to normalized names
    $sampleRecord = $rawData | Select-Object -First 1
    $sourceProperties = @($sampleRecord.PSObject.Properties.Name)
    $resolvedMap = @{}

    foreach ($normalName in $columnMap.Keys) {
        foreach ($sourceProp in $sourceProperties) {
            $lowerProp = $sourceProp.ToLower().Trim()
            if ($lowerProp -eq $normalName.ToLower() -or $lowerProp -in $columnMap[$normalName]) {
                $resolvedMap[$normalName] = $sourceProp
                break
            }
        }
    }

    Write-Verbose "Column mapping resolved: $($resolvedMap.Keys -join ', ')"

    # Helper to get property value with fallback
    function Get-MappedValue {
        param([object]$Record, [string]$NormalizedName, [string]$Default = '')
        if ($resolvedMap.ContainsKey($NormalizedName)) {
            $propName = $resolvedMap[$NormalizedName]
            $val = $Record.$propName
            if ($null -ne $val -and $val -ne '') { return [string]$val }
        }
        return $Default
    }

    # Calculate the cutoff date
    $cutoffDate = (Get-Date).AddMonths(-$MonthsBack)

    # Normalize all records
    $normalizedRecords = foreach ($record in $rawData) {
        $openedAtStr = Get-MappedValue $record 'OpenedAt'
        $openedAt = $null
        if ($openedAtStr) {
            try { $openedAt = [datetime]::Parse($openedAtStr) } catch { }
        }

        # Apply date filter
        if ($openedAt -and $openedAt -lt $cutoffDate) {
            continue
        }

        # Build normalized object
        $normalized = [PSCustomObject]@{
            Number           = Get-MappedValue $record 'Number'
            Type             = Get-MappedValue $record 'Type' 'Incident'
            ShortDescription = Get-MappedValue $record 'ShortDescription'
            Description      = Get-MappedValue $record 'Description'
            State            = Get-MappedValue $record 'State'
            Priority         = Get-MappedValue $record 'Priority'
            Category         = Get-MappedValue $record 'Category'
            Subcategory      = Get-MappedValue $record 'Subcategory'
            OpenedAt         = $openedAtStr
            ClosedAt         = Get-MappedValue $record 'ClosedAt'
            ResolvedAt       = Get-MappedValue $record 'ResolvedAt'
            AssignedTo       = Get-MappedValue $record 'AssignedTo'
            CallerName       = Get-MappedValue $record 'CallerName'
            CloseNotes       = Get-MappedValue $record 'CloseNotes'
            WorkNotes        = Get-MappedValue $record 'WorkNotes'
            CIName           = Get-MappedValue $record 'CIName'
            Source           = 'File'
        }

        $normalized
    }

    $results = @($normalizedRecords)

    # Apply CI filter if specified
    if ($CIFilter) {
        $results = @($results | Where-Object {
            $_.CIName -like "*$CIFilter*" -or
            $_.ShortDescription -like "*$CIFilter*" -or
            $_.Description -like "*$CIFilter*"
        })
        Write-Verbose "After CI filter '$CIFilter': $($results.Count) records"
    }

    # Apply user filter if specified
    if ($UserFilter) {
        $results = @($results | Where-Object {
            switch ($UserRole) {
                'Requester' {
                    $_.CallerName -like "*$UserFilter*"
                }
                'Assignee' {
                    $_.AssignedTo -like "*$UserFilter*"
                }
                'Both' {
                    $_.CallerName -like "*$UserFilter*" -or $_.AssignedTo -like "*$UserFilter*"
                }
                default {
                    # All
                    $_.CallerName -like "*$UserFilter*" -or
                    $_.AssignedTo -like "*$UserFilter*" -or
                    $_.Description -like "*$UserFilter*" -or
                    $_.WorkNotes -like "*$UserFilter*"
                }
            }
        })
        Write-Verbose "After user filter '$UserFilter' (role=$UserRole): $($results.Count) records"
    }

    Write-Verbose "Returning $($results.Count) normalized ticket records"
    return $results
}
