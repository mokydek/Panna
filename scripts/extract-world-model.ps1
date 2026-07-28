param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$resolvedLog = (Resolve-Path -LiteralPath $LogPath).Path
$chunks = @{}
$expectedCount = $null

foreach ($line in Get-Content -LiteralPath $resolvedLog) {
    if ($line -match '^PANNA_WORLD_CHUNK\s+(\d{6})/(\d{6})\s+(.*)$') {
        $index = [int]$Matches[1]
        $count = [int]$Matches[2]
        if ($null -eq $expectedCount) {
            $expectedCount = $count
        } elseif ($expectedCount -ne $count) {
            throw "Inconsistent world chunk count in $resolvedLog"
        }
        $chunks[$index] = $Matches[3]
    }
}

if ($null -eq $expectedCount -or $expectedCount -lt 1) {
    throw "No PANNA_WORLD_CHUNK records found in $resolvedLog"
}
if ($chunks.Count -ne $expectedCount) {
    throw "Expected $expectedCount world chunks, found $($chunks.Count)"
}

$builder = [System.Text.StringBuilder]::new()
for ($index = 1; $index -le $expectedCount; $index++) {
    if (-not $chunks.ContainsKey($index)) {
        throw "World chunk $index is missing"
    }
    [void]$builder.Append($chunks[$index])
}

$json = $builder.ToString()
$model = $json | ConvertFrom-Json
if ($model.ClassName -ne 'Model') {
    throw 'Exported world root is not a Model'
}
$modelName = if ([string]::IsNullOrWhiteSpace($model.Name)) {
    ([IO.Path]::GetFileName($OutputPath) -replace '\.model\.json$', '')
} else {
    $model.Name
}

$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$parent = [IO.Path]::GetDirectoryName($resolvedOutput)
if ([string]::IsNullOrWhiteSpace($parent)) {
    throw "Output path has no parent directory: $resolvedOutput"
}
New-Item -ItemType Directory -Force -Path $parent | Out-Null

$temporaryName = '.{0}.{1}.tmp' -f (
    [IO.Path]::GetFileName($resolvedOutput),
    [guid]::NewGuid().ToString('N')
)
$temporaryPath = Join-Path $parent $temporaryName
$backupName = '.{0}.{1}.backup' -f (
    [IO.Path]::GetFileName($resolvedOutput),
    [guid]::NewGuid().ToString('N')
)
$backupPath = Join-Path $parent $backupName
$replacementCompleted = $false

try {
    [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))

    # Validate the bytes that will actually be promoted, not only the in-memory payload.
    $writtenJson = [IO.File]::ReadAllText($temporaryPath, [Text.UTF8Encoding]::new($false))
    if ($writtenJson -cne $json) {
        throw 'Temporary world model does not match the exported payload'
    }
    $writtenModel = $writtenJson | ConvertFrom-Json
    if ($writtenModel.ClassName -ne 'Model') {
        throw 'Temporary world model root is not a Model'
    }

    if ([IO.File]::Exists($resolvedOutput)) {
        # Source and destination share a directory/volume, so File.Replace promotes
        # the validated file atomically while preserving the previous target on error.
        [IO.File]::Replace($temporaryPath, $resolvedOutput, $backupPath)
        $replacementCompleted = $true
    } else {
        try {
            [IO.File]::Move($temporaryPath, $resolvedOutput)
            $replacementCompleted = $true
        } catch [IO.IOException] {
            # Handle a target created between Exists and Move without deleting it first.
            if ([IO.File]::Exists($resolvedOutput)) {
                [IO.File]::Replace($temporaryPath, $resolvedOutput, $backupPath)
                $replacementCompleted = $true
            } else {
                throw
            }
        }
    }
} finally {
    if ([IO.File]::Exists($temporaryPath)) {
        [IO.File]::Delete($temporaryPath)
    }
    if ($replacementCompleted -and [IO.File]::Exists($backupPath)) {
        [IO.File]::Delete($backupPath)
    }
}

Write-Output "WORLD_MODEL_EXTRACT_OK name=$modelName chunks=$expectedCount bytes=$($json.Length) output=$resolvedOutput"
