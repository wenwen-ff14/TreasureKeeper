$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$env:MSBuildEnableWorkloadResolver = 'false'
Push-Location $root
try {
    dotnet build TreasureKeeper/TreasureKeeper.csproj -c Release -p:RestoreLockedMode=true
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    dotnet run --project tests/TreasureKeeper.Validation -c Release
    if ($LASTEXITCODE -ne 0) { throw 'Validation failed.' }
    $output = Join-Path $root 'TreasureKeeper/bin/Release'
    $manifest = Get-Content -LiteralPath (Join-Path $output 'TreasureKeeper.json') -Raw | ConvertFrom-Json
    $version = $manifest.AssemblyVersion
    $dllVersion = [Reflection.AssemblyName]::GetAssemblyName((Join-Path $output 'TreasureKeeper.dll')).Version.ToString()
    if ($version -ne $dllVersion -or $manifest.DalamudApiLevel -ne 13) { throw 'Manifest mismatch.' }
    $dist = Join-Path $root 'dist'
    New-Item -ItemType Directory -Force -Path $dist | Out-Null
    $stage = Join-Path $dist ('stage-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($file in @('TreasureKeeper.dll','TreasureKeeper.Core.dll','TreasureKeeper.deps.json','TreasureKeeper.json')) {
        Copy-Item -LiteralPath (Join-Path $output $file) -Destination $stage
    }
    foreach ($file in @('LICENSE.txt','README.md')) { Copy-Item -LiteralPath (Join-Path $root $file) -Destination $stage }
    Copy-Item -LiteralPath (Join-Path $root 'third-party') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $stage -Recurse
    $archive = Join-Path $dist "TreasureKeeper-$version-api13.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $archive -Force
    & (Join-Path $PSScriptRoot 'Prepare-PluginRepository.ps1') -PackagePath $archive
    $sourceFiles = @('global.json','.gitignore','README.md','LICENSE.txt','pluginmaster.json') | ForEach-Object { Join-Path $root $_ }
    $sourceFiles += Get-ChildItem -Path (Join-Path $root 'TreasureKeeper'),(Join-Path $root 'TreasureKeeper.Core'),(Join-Path $root 'tools'),(Join-Path $root 'tests'),(Join-Path $root 'scripts'),(Join-Path $root 'docs'),(Join-Path $root 'third-party') -File -Recurse |
        Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' } | Select-Object -ExpandProperty FullName
    $sourceStage = Join-Path $dist ('source-' + [Guid]::NewGuid().ToString('N'))
    foreach ($file in $sourceFiles) {
        $relative = [IO.Path]::GetRelativePath($root, $file)
        $target = Join-Path $sourceStage $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
        Copy-Item -LiteralPath $file -Destination $target
    }
    $sourceArchive = Join-Path $dist "TreasureKeeper-$version-source.zip"
    Compress-Archive -Path (Join-Path $sourceStage '*') -DestinationPath $sourceArchive -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entries = @($zip.Entries | ForEach-Object { $_.FullName -replace '\\','/' } | Sort-Object)
        $expected = @('LICENSE.txt','README.md','TreasureKeeper.Core.dll','TreasureKeeper.deps.json','TreasureKeeper.dll','TreasureKeeper.json','third-party/NOTICE.md','third-party/Teamcraft-LICENSE','third-party/PandorasBox-LICENSE','docs/IN_GAME_CHECKS.md','docs/G10_AUDIT.md','docs/g10-audit.json','docs/g10-supplement.json','docs/g10-wiki-check.json','docs/g10-observed.json','docs/G10_ITEMS.md','docs/catalog-sources.json','docs/performance-results.json') | Sort-Object
        if (Compare-Object $expected $entries) { throw 'Unexpected package contents.' }
    } finally { $zip.Dispose() }
    Get-FileHash -LiteralPath $archive,$sourceArchive -Algorithm SHA256 | Format-Table -AutoSize
    Write-Output "Install: $archive"
    Write-Output "Source: $sourceArchive"
} finally { Pop-Location }
