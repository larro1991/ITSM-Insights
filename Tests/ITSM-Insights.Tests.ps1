BeforeAll {
    $ModuleRoot = Split-Path -Parent $PSScriptRoot
    $ModuleName = 'ITSM-Insights'
    $ManifestPath = Join-Path $ModuleRoot "$ModuleName.psd1"

    # Remove module if already loaded
    Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module -Force

    # Import module
    Import-Module $ManifestPath -Force -ErrorAction Stop
}

AfterAll {
    Get-Module 'ITSM-Insights' -ErrorAction SilentlyContinue | Remove-Module -Force
}

Describe 'Module Loading' {
    It 'Should import the module without errors' {
        $module = Get-Module 'ITSM-Insights'
        $module | Should -Not -BeNullOrEmpty
        $module.Name | Should -Be 'ITSM-Insights'
    }

    It 'Should export exactly 5 public functions' {
        $exported = (Get-Module 'ITSM-Insights').ExportedFunctions.Keys
        $exported.Count | Should -Be 5
    }

    It 'Should export Get-CIHistory' {
        Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory' | Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-UserTicketHistory' {
        Get-Command -Module 'ITSM-Insights' -Name 'Get-UserTicketHistory' | Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-RecurringIssues' {
        Get-Command -Module 'ITSM-Insights' -Name 'Get-RecurringIssues' | Should -Not -BeNullOrEmpty
    }

    It 'Should export Get-KnowledgeGaps' {
        Get-Command -Module 'ITSM-Insights' -Name 'Get-KnowledgeGaps' | Should -Not -BeNullOrEmpty
    }

    It 'Should export Sync-KnowledgeArticles' {
        Get-Command -Module 'ITSM-Insights' -Name 'Sync-KnowledgeArticles' | Should -Not -BeNullOrEmpty
    }

    It 'Should NOT export private functions' {
        $exported = (Get-Module 'ITSM-Insights').ExportedFunctions.Keys
        $exported | Should -Not -Contain 'Invoke-AICompletion'
        $exported | Should -Not -Contain 'Connect-ServiceNow'
        $exported | Should -Not -Contain 'Connect-JiraSM'
        $exported | Should -Not -Contain 'Import-TicketExport'
        $exported | Should -Not -Contain 'New-HtmlDashboard'
    }
}

Describe 'Module Manifest' {
    BeforeAll {
        $manifest = Test-ModuleManifest -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'ITSM-Insights.psd1')
    }

    It 'Should have the correct GUID' {
        $manifest.GUID | Should -Be 'c9d0e1f2-6a57-4cd3-b4e5-0a1b2c3d4e56'
    }

    It 'Should require PowerShell 5.1 or higher' {
        $manifest.PowerShellVersion | Should -Be '5.1'
    }

    It 'Should have the correct author' {
        $manifest.Author | Should -BeLike '*Larry Roberts*'
    }

    It 'Should have a description' {
        $manifest.Description | Should -Not -BeNullOrEmpty
        $manifest.Description | Should -BeLike '*ITSM*'
    }

    It 'Should have required tags' {
        $tags = $manifest.PrivateData.PSData.Tags
        $tags | Should -Contain 'ServiceNow'
        $tags | Should -Contain 'ITSM'
        $tags | Should -Contain 'ITIL'
        $tags | Should -Contain 'AI'
        $tags | Should -Contain 'KnowledgeBase'
        $tags | Should -Contain 'Incidents'
        $tags | Should -Contain 'ChangeManagement'
    }

    It 'Should have ProjectUri set' {
        $manifest.PrivateData.PSData.ProjectUri | Should -Not -BeNullOrEmpty
    }

    It 'Should have LicenseUri set' {
        $manifest.PrivateData.PSData.LicenseUri | Should -Not -BeNullOrEmpty
    }

    It 'Should export the correct functions' {
        $manifest.ExportedFunctions.Keys | Should -Contain 'Get-CIHistory'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Get-UserTicketHistory'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Get-RecurringIssues'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Get-KnowledgeGaps'
        $manifest.ExportedFunctions.Keys | Should -Contain 'Sync-KnowledgeArticles'
    }
}

Describe 'Get-CIHistory Parameter Validation' {
    It 'Should require CIName parameter' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory'
        $param = $cmd.Parameters['CIName']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } | Should -Not -BeNullOrEmpty
    }

    It 'Should validate Provider parameter with ValidateSet' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory'
        $param = $cmd.Parameters['Provider']
        $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'ServiceNow'
        $validateSet.ValidValues | Should -Contain 'Jira'
        $validateSet.ValidValues | Should -Contain 'File'
    }

    It 'Should validate AIProvider parameter with ValidateSet' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory'
        $param = $cmd.Parameters['AIProvider']
        $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'Anthropic'
        $validateSet.ValidValues | Should -Contain 'OpenAI'
        $validateSet.ValidValues | Should -Contain 'Ollama'
        $validateSet.ValidValues | Should -Contain 'Custom'
    }

    It 'Should validate MonthsBack range (1-60)' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory'
        $param = $cmd.Parameters['MonthsBack']
        $validateRange = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
        $validateRange | Should -Not -BeNullOrEmpty
        $validateRange.MinRange | Should -Be 1
        $validateRange.MaxRange | Should -Be 60
    }

    It 'Should have SkipAI switch parameter' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-CIHistory'
        $param = $cmd.Parameters['SkipAI']
        $param | Should -Not -BeNullOrEmpty
        $param.SwitchParameter | Should -Be $true
    }
}

Describe 'Get-UserTicketHistory Parameter Validation' {
    It 'Should require UserIdentity parameter' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-UserTicketHistory'
        $param = $cmd.Parameters['UserIdentity']
        $param | Should -Not -BeNullOrEmpty
        $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory } | Should -Not -BeNullOrEmpty
    }

    It 'Should validate Role parameter with ValidateSet' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-UserTicketHistory'
        $param = $cmd.Parameters['Role']
        $validateSet = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'All'
        $validateSet.ValidValues | Should -Contain 'Requester'
        $validateSet.ValidValues | Should -Contain 'Assignee'
        $validateSet.ValidValues | Should -Contain 'Both'
    }
}

Describe 'Get-RecurringIssues Parameter Validation' {
    It 'Should have MinOccurrences parameter' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-RecurringIssues'
        $param = $cmd.Parameters['MinOccurrences']
        $param | Should -Not -BeNullOrEmpty
    }

    It 'Should have Category parameter' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Get-RecurringIssues'
        $param = $cmd.Parameters['Category']
        $param | Should -Not -BeNullOrEmpty
    }
}

Describe 'Sync-KnowledgeArticles ShouldProcess' {
    It 'Should support ShouldProcess (WhatIf)' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Sync-KnowledgeArticles'
        $cmd.Parameters.ContainsKey('WhatIf') | Should -Be $true
        $cmd.Parameters.ContainsKey('Confirm') | Should -Be $true
    }

    It 'Should accept pipeline input for Articles' {
        $cmd = Get-Command -Module 'ITSM-Insights' -Name 'Sync-KnowledgeArticles'
        $param = $cmd.Parameters['Articles']
        $pipelineAttr = $param.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.ValueFromPipeline
        }
        $pipelineAttr | Should -Not -BeNullOrEmpty
    }
}

Describe 'Connect-ServiceNow (Mocked)' {
    BeforeAll {
        # Access private function via module scope
        $snowFunc = & (Get-Module 'ITSM-Insights') { Get-Command Connect-ServiceNow }
    }

    It 'Should throw when no authentication is provided' {
        # Clear environment variable temporarily
        $origKey = $env:SNOW_API_KEY
        $env:SNOW_API_KEY = $null
        try {
            {
                & (Get-Module 'ITSM-Insights') {
                    Connect-ServiceNow -Instance 'test.service-now.com' -Method GET -Endpoint 'api/now/table/incident'
                }
            } | Should -Throw '*authentication*'
        }
        finally {
            $env:SNOW_API_KEY = $origKey
        }
    }

    It 'Should construct correct URL from instance name' {
        Mock -ModuleName 'ITSM-Insights' Invoke-RestMethod {
            return @{ result = @() }
        }

        & (Get-Module 'ITSM-Insights') {
            Connect-ServiceNow -Instance 'mycompany.service-now.com' -Method GET `
                -Endpoint 'api/now/table/incident' -ApiKey 'test-key' `
                -QueryParameters @{ sysparm_query = 'active=true' }
        }

        Should -Invoke -ModuleName 'ITSM-Insights' Invoke-RestMethod -Times 1 -ParameterFilter {
            $Uri -like 'https://mycompany.service-now.com/api/now/table/incident*'
        }
    }

    It 'Should include correct auth header for API key' {
        Mock -ModuleName 'ITSM-Insights' Invoke-RestMethod {
            return @{ result = @() }
        }

        & (Get-Module 'ITSM-Insights') {
            Connect-ServiceNow -Instance 'test.service-now.com' -Method GET `
                -Endpoint 'api/now/table/incident' -ApiKey 'my-secret-key'
        }

        Should -Invoke -ModuleName 'ITSM-Insights' Invoke-RestMethod -Times 1 -ParameterFilter {
            $Headers['Authorization'] -eq 'Bearer my-secret-key'
        }
    }

    It 'Should handle pagination correctly' {
        $callCount = 0
        Mock -ModuleName 'ITSM-Insights' Invoke-RestMethod {
            $script:callCount++
            if ($Uri -match 'sysparm_offset=0') {
                return @{
                    result = @(
                        @{ number = 'INC0000001'; short_description = 'Test 1' }
                        @{ number = 'INC0000002'; short_description = 'Test 2' }
                    )
                }
            }
            else {
                return @{ result = @() }
            }
        }

        $results = & (Get-Module 'ITSM-Insights') {
            Connect-ServiceNow -Instance 'test.service-now.com' -Method GET `
                -Endpoint 'api/now/table/incident' -ApiKey 'test-key' -Paginate -PageSize 2
        }

        $results | Should -Not -BeNullOrEmpty
    }
}

Describe 'Get-CIHistory with File Provider (Mocked)' {
    BeforeAll {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $samplePath = Join-Path $samplesDir 'sample-tickets.json'
    }

    It 'Should return correct ticket counts from sample data with SkipAI' {
        $result = Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath $samplePath -SkipAI -MonthsBack 60

        $result | Should -Not -BeNullOrEmpty
        $result.CIName | Should -Be 'SQL-PROD-01'
        $result.TicketCount | Should -BeGreaterThan 0
        $result.IncidentCount | Should -BeGreaterThan 0
        $result.ChangeCount | Should -BeGreaterThan 0
        $result.ProblemCount | Should -BeGreaterThan 0
    }

    It 'Should identify open items' {
        $result = Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath $samplePath -SkipAI -MonthsBack 60

        $result.OpenItems | Should -Not -BeNullOrEmpty
        $openNumbers = $result.OpenItems | ForEach-Object { $_.Number }
        $openNumbers | Should -Contain 'PRB0001150'
    }

    It 'Should return a timeline' {
        $result = Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath $samplePath -SkipAI -MonthsBack 60

        $result.Timeline | Should -Not -BeNullOrEmpty
        $result.Timeline.Count | Should -Be $result.TicketCount
    }

    It 'Should throw when FilePath is missing for File provider' {
        { Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -SkipAI } | Should -Throw '*FilePath*'
    }

    It 'Should have empty summary when SkipAI is used' {
        $result = Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath $samplePath -SkipAI -MonthsBack 60

        $result.Summary | Should -BeNullOrEmpty
    }

    It 'Should generate HTML report when OutputPath is specified' {
        $tempHtml = Join-Path $env:TEMP 'itsm-test-ci-report.html'
        try {
            $result = Get-CIHistory -CIName 'SQL-PROD-01' -Provider File -FilePath $samplePath -SkipAI -MonthsBack 60 -OutputPath $tempHtml
            Test-Path $tempHtml | Should -Be $true
            $htmlContent = Get-Content -Path $tempHtml -Raw
            $htmlContent | Should -BeLike '*SQL-PROD-01*'
        }
        finally {
            if (Test-Path $tempHtml) { Remove-Item $tempHtml -Force }
        }
    }
}

Describe 'Get-RecurringIssues with File Provider' {
    BeforeAll {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $samplePath = Join-Path $samplesDir 'sample-tickets.json'
    }

    It 'Should detect disk space as a recurring pattern' {
        $result = Get-RecurringIssues -Provider File -FilePath $samplePath -MinOccurrences 2 -SkipAI -MonthsBack 60

        $result | Should -Not -BeNullOrEmpty
        $diskPattern = $result | Where-Object { $_.Pattern -like '*disk*' -or $_.Pattern -like '*Hardware*' }
        $diskPattern | Should -Not -BeNullOrEmpty
    }

    It 'Should return structured pattern objects' {
        $result = Get-RecurringIssues -Provider File -FilePath $samplePath -MinOccurrences 2 -SkipAI -MonthsBack 60

        foreach ($pattern in $result) {
            $pattern.Pattern | Should -Not -BeNullOrEmpty
            $pattern.Occurrences | Should -BeGreaterOrEqual 2
            $pattern.TicketNumbers | Should -Not -BeNullOrEmpty
            $pattern.SuggestedResolution | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Import-TicketExport' {
    It 'Should import JSON files correctly' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $sampleJsonPath = Join-Path $samplesDir 'sample-tickets.json'

        InModuleScope 'ITSM-Insights' -Parameters @{ SamplePath = $sampleJsonPath } {
            param($SamplePath)
            $results = Import-TicketExport -Path $SamplePath -MonthsBack 60
            $results | Should -Not -BeNullOrEmpty
            $results.Count | Should -BeGreaterThan 0
        }
    }

    It 'Should normalize column names from JSON' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $sampleJsonPath = Join-Path $samplesDir 'sample-tickets.json'

        InModuleScope 'ITSM-Insights' -Parameters @{ SamplePath = $sampleJsonPath } {
            param($SamplePath)
            $results = Import-TicketExport -Path $SamplePath -MonthsBack 60
            $firstTicket = $results | Select-Object -First 1
            $firstTicket.PSObject.Properties.Name | Should -Contain 'Number'
            $firstTicket.PSObject.Properties.Name | Should -Contain 'ShortDescription'
            $firstTicket.PSObject.Properties.Name | Should -Contain 'State'
            $firstTicket.PSObject.Properties.Name | Should -Contain 'OpenedAt'
        }
    }

    It 'Should filter by CI name' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $sampleJsonPath = Join-Path $samplesDir 'sample-tickets.json'

        InModuleScope 'ITSM-Insights' -Parameters @{ SamplePath = $sampleJsonPath } {
            param($SamplePath)
            $results = Import-TicketExport -Path $SamplePath -CIFilter 'SQL-PROD-01' -MonthsBack 60
            $results | Should -Not -BeNullOrEmpty
            foreach ($ticket in $results) {
                ($ticket.CIName -like '*SQL-PROD-01*' -or
                 $ticket.ShortDescription -like '*SQL-PROD-01*' -or
                 $ticket.Description -like '*SQL-PROD-01*') | Should -Be $true
            }
        }
    }

    It 'Should handle CSV files' {
        $csvPath = Join-Path $env:TEMP 'test-tickets.csv'
        try {
            @"
number,short_description,state,priority,opened_at,category,assigned_to,cmdb_ci,type
INC0099001,Test incident one,Closed,2 - High,2025-01-15 10:00:00,Hardware,John Doe,TEST-SRV-01,Incident
INC0099002,Test incident two,Open,3 - Moderate,2025-06-01 08:00:00,Software,Jane Smith,TEST-SRV-01,Incident
"@ | Out-File -FilePath $csvPath -Encoding UTF8

            InModuleScope 'ITSM-Insights' -Parameters @{ CsvPath = $csvPath } {
                param($CsvPath)
                $results = Import-TicketExport -Path $CsvPath -MonthsBack 60
                $results | Should -Not -BeNullOrEmpty
                $results.Count | Should -Be 2
                $results[0].Number | Should -Be 'INC0099001'
            }
        }
        finally {
            if (Test-Path $csvPath) { Remove-Item $csvPath -Force }
        }
    }

    It 'Should throw for unsupported file formats' {
        {
            InModuleScope 'ITSM-Insights' {
                Import-TicketExport -Path 'C:\fake\file.xml' -MonthsBack 12
            }
        } | Should -Throw
    }
}

Describe 'Sync-KnowledgeArticles WhatIf and ReviewOnly' {
    It 'Should generate local files in ReviewOnly mode' {
        $outputDir = Join-Path $env:TEMP 'itsm-test-kb-review'
        try {
            $articles = @(
                [PSCustomObject]@{
                    GapType          = 'Missing'
                    Topic            = 'Test Topic'
                    RelatedTickets   = @('INC0000001', 'INC0000002')
                    SuggestedTitle   = 'How to Handle Test Issues'
                    SuggestedContent = 'Step 1: Do this. Step 2: Do that.'
                }
            )

            $result = $articles | Sync-KnowledgeArticles -ReviewOnly -OutputDirectory $outputDir

            $result | Should -Not -BeNullOrEmpty
            $result[0].Status | Should -Be 'ReviewPending'
            Test-Path $outputDir | Should -Be $true
            (Get-ChildItem $outputDir -Filter '*.md').Count | Should -Be 1
        }
        finally {
            if (Test-Path $outputDir) { Remove-Item $outputDir -Recurse -Force }
        }
    }

    It 'Should not push to ServiceNow when WhatIf is used' {
        Mock -ModuleName 'ITSM-Insights' Connect-ServiceNow {
            throw 'Should not be called with WhatIf'
        }

        $articles = @(
            [PSCustomObject]@{
                SuggestedTitle   = 'WhatIf Test Article'
                SuggestedContent = 'Test content'
                GapType          = 'Missing'
            }
        )

        $result = $articles | Sync-KnowledgeArticles -Instance 'test.service-now.com' `
            -ApiKey 'test-key' -KnowledgeBase 'kb-sys-id-123' -WhatIf

        $result | Should -Not -BeNullOrEmpty
        $result[0].Status | Should -Be 'WhatIf'

        # Connect-ServiceNow should NOT have been called
        Should -Not -Invoke -ModuleName 'ITSM-Insights' Connect-ServiceNow
    }

    It 'Should always create articles as DRAFT when pushing' {
        Mock -ModuleName 'ITSM-Insights' Connect-ServiceNow {
            # Verify the body contains workflow_state = draft
            $Body['workflow_state'] | Should -Be 'draft'
            return @{
                result = @{
                    sys_id  = 'abc123'
                    number  = 'KB0001001'
                }
            }
        }

        $articles = @(
            [PSCustomObject]@{
                SuggestedTitle   = 'Draft Test Article'
                SuggestedContent = 'Content here'
                GapType          = 'Missing'
            }
        )

        $result = $articles | Sync-KnowledgeArticles -Instance 'test.service-now.com' `
            -ApiKey 'test-key' -KnowledgeBase 'kb-sys-id-123' -Confirm:$false

        Should -Invoke -ModuleName 'ITSM-Insights' Connect-ServiceNow -Times 1
        $result[0].Status | Should -Be 'Created'
    }
}

Describe 'Template Files' {
    It 'Should have ci-history-prompt.txt template' {
        $templatesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Templates'
        $templatePath = Join-Path $templatesDir 'ci-history-prompt.txt'
        Test-Path $templatePath | Should -Be $true
        $content = Get-Content $templatePath -Raw
        $content | Should -BeLike '*{ci_name}*'
        $content | Should -BeLike '*{ticket_data}*'
    }

    It 'Should have user-history-prompt.txt template' {
        $templatesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Templates'
        $templatePath = Join-Path $templatesDir 'user-history-prompt.txt'
        Test-Path $templatePath | Should -Be $true
        $content = Get-Content $templatePath -Raw
        $content | Should -BeLike '*{user_name}*'
        $content | Should -BeLike '*{ticket_data}*'
    }

    It 'Should have recurring-issues-prompt.txt template' {
        $templatesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Templates'
        $templatePath = Join-Path $templatesDir 'recurring-issues-prompt.txt'
        Test-Path $templatePath | Should -Be $true
        $content = Get-Content $templatePath -Raw
        $content | Should -BeLike '*{min_occurrences}*'
        $content | Should -BeLike '*{ticket_data}*'
    }

    It 'Should have knowledge-gap-prompt.txt template' {
        $templatesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Templates'
        $templatePath = Join-Path $templatesDir 'knowledge-gap-prompt.txt'
        Test-Path $templatePath | Should -Be $true
        $content = Get-Content $templatePath -Raw
        $content | Should -BeLike '*{ticket_data}*'
        $content | Should -BeLike '*{kb_articles}*'
    }
}

Describe 'Sample Data' {
    It 'Should have valid sample-tickets.json' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $samplePath = Join-Path $samplesDir 'sample-tickets.json'
        Test-Path $samplePath | Should -Be $true

        $content = Get-Content $samplePath -Raw
        $tickets = $content | ConvertFrom-Json
        $tickets | Should -Not -BeNullOrEmpty
        $tickets.Count | Should -BeGreaterOrEqual 15

        # Verify expected ticket types
        $types = $tickets | ForEach-Object { $_.type } | Sort-Object -Unique
        $types | Should -Contain 'Incident'
        $types | Should -Contain 'Change Request'
        $types | Should -Contain 'Problem'
    }

    It 'Should have sample CI report HTML' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $samplePath = Join-Path $samplesDir 'sample-ci-report.html'
        Test-Path $samplePath | Should -Be $true
        $content = Get-Content $samplePath -Raw
        $content | Should -BeLike '*SQL-PROD-01*'
        $content | Should -BeLike '*#2dd4bf*'
    }

    It 'Should have sample recurring report HTML' {
        $samplesDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'Samples'
        $samplePath = Join-Path $samplesDir 'sample-recurring-report.html'
        Test-Path $samplePath | Should -Be $true
        $content = Get-Content $samplePath -Raw
        $content | Should -BeLike '*Recurring*'
        $content | Should -BeLike '*Disk*'
    }
}
