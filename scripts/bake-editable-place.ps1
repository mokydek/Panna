param(
    [string]$RojoPath = 'rojo',
    [string]$StudioPath = '',
    [string]$OutputPath = 'build/Panna-Football.rbxlx'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$runId = [guid]::NewGuid().ToString('N')
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "PannaBake-$runId"
$sourcePlace = Join-Path $temporaryRoot 'source.rbxlx'
$exportLog = Join-Path $temporaryRoot 'world-export.log'
$worldModel = Join-Path $projectRoot 'src/world/PannaDistrict.model.json'
$sourceProjectFile = Join-Path $projectRoot 'source.project.json'
$projectFile = Join-Path $projectRoot 'default.project.json'
$exportScript = Join-Path $PSScriptRoot 'export-world-model.luau'
$extractScript = Join-Path $PSScriptRoot 'extract-world-model.ps1'

if (-not [IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath
}

New-Item -ItemType Directory -Force -Path $temporaryRoot | Out-Null
try {
    & $RojoPath build $sourceProjectFile --output $sourcePlace
    if ($LASTEXITCODE -ne 0) {
        throw 'Initial Rojo build failed.'
    }

    if ([string]::IsNullOrWhiteSpace($StudioPath)) {
        $versions = Join-Path $env:LOCALAPPDATA 'Roblox/Versions'
        $studio = Get-ChildItem -LiteralPath $versions -Filter 'RobloxStudioBeta.exe' -File -Recurse |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -eq $studio) {
            throw 'RobloxStudioBeta.exe was not found.'
        }
        $StudioPath = $studio.FullName
    }

    $studioArguments = @(
        '--task', 'RunScript',
        '--localPlaceFile', ('"' + $sourcePlace + '"'),
        '--runScriptFile', ('"' + $exportScript + '"'),
        '--outputFile', ('"' + $exportLog + '"'),
        '--quitAfterExecution'
    )
    $studioProcess = Start-Process `
        -FilePath $StudioPath `
        -ArgumentList $studioArguments `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($studioProcess.ExitCode -ne 0) {
        throw "Roblox Studio export failed with exit code $($studioProcess.ExitCode)."
    }
    if (-not (Select-String -LiteralPath $exportLog -Pattern '^PANNA_WORLD_EXPORT_OK ' -Quiet)) {
        throw "Roblox Studio did not emit the world export success marker. See $exportLog"
    }

    & $extractScript -LogPath $exportLog -OutputPath $worldModel
    if ($LASTEXITCODE -ne 0) {
        throw 'World model extraction failed.'
    }

    $outputParent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputParent)) {
        New-Item -ItemType Directory -Force -Path $outputParent | Out-Null
    }
    & $RojoPath build $projectFile --output $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Final Rojo build failed.'
    }

    Write-Output "PANNA_BAKE_OK model=$worldModel place=$OutputPath"
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($temporaryRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolvedTemp).StartsWith('PannaBake-', [StringComparison]::Ordinal)) {
        Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
