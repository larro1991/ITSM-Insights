$ErrorActionPreference = 'Stop'

# Dot-source all private functions
$PrivatePath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $PrivatePath) {
    $PrivateFiles = Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($file in $PrivateFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error "Failed to load private function from $($file.FullName): $_"
        }
    }
}

# Dot-source all public functions
$PublicPath = Join-Path $PSScriptRoot 'Public'
if (Test-Path $PublicPath) {
    $PublicFiles = Get-ChildItem -Path $PublicPath -Filter '*.ps1' -ErrorAction SilentlyContinue
    foreach ($file in $PublicFiles) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error "Failed to load public function from $($file.FullName): $_"
        }
    }
}

# Export public functions
$PublicFunctions = @(
    'Get-CIHistory'
    'Get-UserTicketHistory'
    'Get-RecurringIssues'
    'Get-KnowledgeGaps'
    'Sync-KnowledgeArticles'
)
Export-ModuleMember -Function $PublicFunctions
