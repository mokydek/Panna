param(
    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$resolvedLog = (Resolve-Path -LiteralPath $LogPath).Path
$captures = @{}
$expected = @{}

foreach ($line in Get-Content -LiteralPath $resolvedLog) {
    if ($line -match '^PANNA_CAPTURE_CHUNK\s+([a-z0-9-]+)\s+(\d{6})/(\d{6})\s+(.*)$') {
        $name = $Matches[1]
        $index = [int]$Matches[2]
        $count = [int]$Matches[3]
        if (-not $captures.ContainsKey($name)) {
            $captures[$name] = @{}
            $expected[$name] = $count
        } elseif ($expected[$name] -ne $count) {
            throw "Inconsistent chunk count for capture $name"
        }
        $captures[$name][$index] = $Matches[4]
    }
}

if ($captures.Count -eq 0) {
    throw "No PANNA_CAPTURE_CHUNK records found in $resolvedLog"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($name in ($captures.Keys | Sort-Object)) {
    $chunks = $captures[$name]
    $count = $expected[$name]
    if ($chunks.Count -ne $count) {
        throw "Capture $name expected $count chunks, found $($chunks.Count)"
    }

    $builder = [System.Text.StringBuilder]::new()
    for ($index = 1; $index -le $count; $index++) {
        if (-not $chunks.ContainsKey($index)) {
            throw "Capture $name chunk $index is missing"
        }
        [void]$builder.Append($chunks[$index])
    }

    $bytes = [Convert]::FromBase64String($builder.ToString())
    if ($bytes.Length -lt 8 -or $bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71) {
        throw "Capture $name is not a PNG"
    }
    $outputPath = Join-Path $OutputDirectory "$name.png"
    [IO.File]::WriteAllBytes($outputPath, $bytes)
    Write-Output "CAPTURE_EXTRACT_OK name=$name bytes=$($bytes.Length) output=$outputPath"
}
