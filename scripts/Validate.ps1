param([switch]$Preview)
$ErrorActionPreference = 'Stop'
$env:MSBuildEnableWorkloadResolver = 'false'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    dotnet build TreasureKeeper/TreasureKeeper.csproj -c Release -p:RestoreLockedMode=true
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    dotnet run --project tests/TreasureKeeper.Validation -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Core validation failed.' }
    if ($Preview) {
        dotnet run --project tools/UiPreview -c Release
        if ($LASTEXITCODE -ne 0) { throw 'UI validation failed.' }
    }
} finally { Pop-Location }
