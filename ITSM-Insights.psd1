@{
    RootModule        = 'ITSM-Insights.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'c9d0e1f2-6a57-4cd3-b4e5-0a1b2c3d4e56'
    Author            = 'Larry Roberts, Independent Consultant'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 Larry Roberts. All rights reserved.'
    Description       = 'ITSM ticket intelligence. Pull ticket history from ServiceNow, Jira, or CSV exports and get AI-powered summaries, recurring issue detection, and knowledge gap analysis.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-CIHistory'
        'Get-UserTicketHistory'
        'Get-RecurringIssues'
        'Get-KnowledgeGaps'
        'Sync-KnowledgeArticles'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()
    PrivateData        = @{
        PSData = @{
            Tags         = @('ServiceNow', 'ITSM', 'ITIL', 'Tickets', 'AI', 'KnowledgeBase', 'Incidents', 'ChangeManagement')
            LicenseUri   = 'https://github.com/larro1991/ITSM-Insights/blob/master/LICENSE'
            ProjectUri   = 'https://github.com/larro1991/ITSM-Insights'
            ReleaseNotes = 'Initial release: CI history, user history, recurring issue detection, knowledge gap analysis, KB sync to ServiceNow.'
        }
    }
}
