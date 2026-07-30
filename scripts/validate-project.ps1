[CmdletBinding()]
param(
    [Parameter()]
    [string] $ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

try {
    $root = (Resolve-Path -LiteralPath $ProjectRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}
catch {
    Write-Host "[FAIL] Project root was not found: $ProjectRoot" -ForegroundColor Red
    exit 1
}

$failures = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string] $Message)
    $script:failures.Add($Message)
}

function Add-Warning {
    param([string] $Message)
    $script:warnings.Add($Message)
}

function Add-Pass {
    param([string] $Message)
    $script:passes.Add($Message)
}

function Get-RelativeProjectPath {
    param([string] $FullName)

    if ($FullName.StartsWith($script:root, [StringComparison]::OrdinalIgnoreCase)) {
        return $FullName.Substring($script:root.Length).TrimStart('\', '/')
    }

    return $FullName
}

function Test-IsInsideProject {
    param([string] $FullName)

    $prefix = $script:root + [IO.Path]::DirectorySeparatorChar
    return $FullName.Equals($script:root, [StringComparison]::OrdinalIgnoreCase) -or
        $FullName.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-RojoNode {
    param(
        [Parameter(Mandatory = $true)] $Node,
        [Parameter(Mandatory = $true)][string] $JsonLocation
    )

    if ($null -eq $Node -or $Node -isnot [psobject]) {
        return
    }

    foreach ($property in $Node.PSObject.Properties) {
        $propertyLocation = "$JsonLocation.$($property.Name)"

        if ($property.Name -eq '$path') {
            if ($property.Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string] $property.Value)) {
                Add-Failure "$propertyLocation must contain a non-empty relative path."
                continue
            }

            try {
                $candidate = [IO.Path]::GetFullPath((Join-Path $script:root ([string] $property.Value)))
            }
            catch {
                Add-Failure "$propertyLocation contains an invalid path."
                continue
            }

            if (-not (Test-IsInsideProject -FullName $candidate)) {
                Add-Failure "$propertyLocation escapes the project root."
            }
            elseif (-not (Test-Path -LiteralPath $candidate)) {
                Add-Failure "$propertyLocation references missing path '$($property.Value)'."
            }

            continue
        }

        if ($property.Value -is [pscustomobject]) {
            Test-RojoNode -Node $property.Value -JsonLocation $propertyLocation
        }
        elseif ($property.Value -is [System.Collections.IEnumerable] -and $property.Value -isnot [string]) {
            $index = 0
            foreach ($item in $property.Value) {
                if ($item -is [pscustomobject]) {
                    Test-RojoNode -Node $item -JsonLocation "$propertyLocation[$index]"
                }
                $index += 1
            }
        }
    }
}

function Get-LongBracketLevel {
    param(
        [string] $Text,
        [int] $Index
    )

    if ($Index -lt 0 -or $Index -ge $Text.Length -or $Text[$Index] -ne '[') {
        return -1
    }

    $cursor = $Index + 1
    $level = 0
    while ($cursor -lt $Text.Length -and $Text[$cursor] -eq '=') {
        $level += 1
        $cursor += 1
    }

    if ($cursor -lt $Text.Length -and $Text[$cursor] -eq '[') {
        return $level
    }

    return -1
}

function Get-LuauCodeMask {
    param([string] $Text)

    $builder = [Text.StringBuilder]::new($Text.Length)
    $state = 'Code'
    $quote = [char] 0
    $longLevel = -1
    $escaped = $false
    $index = 0

    while ($index -lt $Text.Length) {
        $character = $Text[$index]

        if ($state -eq 'LineComment') {
            if ($character -eq "`r" -or $character -eq "`n") {
                [void] $builder.Append($character)
                $state = 'Code'
            }
            else {
                [void] $builder.Append(' ')
            }
            $index += 1
            continue
        }

        if ($state -eq 'ShortString') {
            if ($character -eq "`r" -or $character -eq "`n") {
                [void] $builder.Append($character)
            }
            else {
                [void] $builder.Append(' ')
            }

            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq $quote) {
                $state = 'Code'
            }

            $index += 1
            continue
        }

        if ($state -eq 'LongString' -or $state -eq 'LongComment') {
            if ($character -eq ']' -and $index + $longLevel + 1 -lt $Text.Length) {
                $isClosing = $true
                for ($equalsIndex = 1; $equalsIndex -le $longLevel; $equalsIndex += 1) {
                    if ($Text[$index + $equalsIndex] -ne '=') {
                        $isClosing = $false
                        break
                    }
                }

                if ($isClosing -and $Text[$index + $longLevel + 1] -eq ']') {
                    $closingLength = $longLevel + 2
                    for ($closingIndex = 0; $closingIndex -lt $closingLength; $closingIndex += 1) {
                        [void] $builder.Append(' ')
                    }
                    $index += $closingLength
                    $state = 'Code'
                    $longLevel = -1
                    continue
                }
            }

            if ($character -eq "`r" -or $character -eq "`n") {
                [void] $builder.Append($character)
            }
            else {
                [void] $builder.Append(' ')
            }
            $index += 1
            continue
        }

        if ($character -eq '-' -and $index + 1 -lt $Text.Length -and $Text[$index + 1] -eq '-') {
            $commentLevel = -1
            if ($index + 2 -lt $Text.Length) {
                $commentLevel = Get-LongBracketLevel -Text $Text -Index ($index + 2)
            }

            if ($commentLevel -ge 0) {
                $openingLength = $commentLevel + 4
                for ($openingIndex = 0; $openingIndex -lt $openingLength; $openingIndex += 1) {
                    [void] $builder.Append(' ')
                }
                $index += $openingLength
                $longLevel = $commentLevel
                $state = 'LongComment'
            }
            else {
                [void] $builder.Append(' ')
                [void] $builder.Append(' ')
                $index += 2
                $state = 'LineComment'
            }
            continue
        }

        if ($character -eq '"' -or $character -eq "'") {
            [void] $builder.Append(' ')
            $quote = $character
            $escaped = $false
            $state = 'ShortString'
            $index += 1
            continue
        }

        if ($character -eq '[') {
            $stringLevel = Get-LongBracketLevel -Text $Text -Index $index
            if ($stringLevel -ge 0) {
                $openingLength = $stringLevel + 2
                for ($openingIndex = 0; $openingIndex -lt $openingLength; $openingIndex += 1) {
                    [void] $builder.Append(' ')
                }
                $index += $openingLength
                $longLevel = $stringLevel
                $state = 'LongString'
                continue
            }
        }

        [void] $builder.Append($character)
        $index += 1
    }

    if ($state -eq 'ShortString' -or $state -eq 'LongString') {
        return [pscustomobject] @{ Mask = $builder.ToString(); LexicalError = 'unterminated string' }
    }
    if ($state -eq 'LongComment') {
        return [pscustomobject] @{ Mask = $builder.ToString(); LexicalError = 'unterminated long comment' }
    }

    return [pscustomobject] @{ Mask = $builder.ToString(); LexicalError = $null }
}

function Test-LuauBalance {
    param([IO.FileInfo] $File)

    $relative = Get-RelativeProjectPath -FullName $File.FullName
    try {
        $text = Get-Content -LiteralPath $File.FullName -Raw
    }
    catch {
        Add-Failure "${relative}: failed to read the Luau file."
        return
    }

    $maskResult = Get-LuauCodeMask -Text $text
    if ($null -ne $maskResult.LexicalError) {
        Add-Failure "${relative}: $($maskResult.LexicalError)."
        return
    }

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $opening = @{ '(' = ')'; '[' = ']'; '{' = '}' }
    $closing = @{ ')' = '('; ']' = '['; '}' = '{' }
    $line = 1
    $column = 0

    foreach ($character in $maskResult.Mask.ToCharArray()) {
        if ($character -eq "`n") {
            $line += 1
            $column = 0
            continue
        }
        $column += 1

        $asString = [string] $character
        if ($opening.ContainsKey($asString)) {
            $stack.Push([pscustomobject] @{ Character = $asString; Line = $line; Column = $column })
            continue
        }

        if ($closing.ContainsKey($asString)) {
            if ($stack.Count -eq 0) {
                Add-Failure "${relative}:${line}:${column}: closing bracket '$asString' has no matching opener."
                return
            }

            $top = $stack.Pop()
            if ($top.Character -ne $closing[$asString]) {
                Add-Failure "${relative}:${line}:${column}: '$asString' does not match '$($top.Character)' from line $($top.Line)."
                return
            }
        }
    }

    if ($stack.Count -gt 0) {
        $top = $stack.Peek()
        Add-Failure "${relative}:$($top.Line):$($top.Column): bracket '$($top.Character)' is not closed."
        return
    }

    $functionCount = [regex]::Matches($maskResult.Mask, '\bfunction\b').Count
    $ifCount = 0
    $doCount = 0
    $pendingLoopDo = 0
    foreach ($codeLine in ($maskResult.Mask -split "`r?`n")) {
        if ($codeLine -match '^\s*(?:for|while)\b' -and $codeLine -notmatch '\bdo\b') {
            $pendingLoopDo += 1
        }
        if ($codeLine -match '^\s*do\s*;?\s*$') {
            if ($pendingLoopDo -gt 0) {
                $pendingLoopDo -= 1
            }
            else {
                $doCount += 1
            }
        }
        if ($codeLine -match '^\s*if\b') {
            # Luau conditional expressions can start a continuation line with
            # `if ... then ... else ...` and do not have a matching `end`.
            $looksLikeInlineIfExpression = $codeLine -match '\bthen\b.*\belse\b' -and $codeLine -notmatch '\bend\b'
            if (-not $looksLikeInlineIfExpression) {
                $ifCount += 1
            }
        }
    }
    $loopCount = [regex]::Matches($maskResult.Mask, '(?m)^\s*(?:for|while)\b').Count
    $repeatCount = [regex]::Matches($maskResult.Mask, '(?m)^\s*repeat\b').Count
    $endCount = [regex]::Matches($maskResult.Mask, '\bend\b').Count
    $untilCount = [regex]::Matches($maskResult.Mask, '(?m)^\s*until\b').Count
    $openingBlockCount = $functionCount + $ifCount + $loopCount + $doCount + $repeatCount
    $closingBlockCount = $endCount + $untilCount

    if ($openingBlockCount -ne $closingBlockCount) {
        Add-Failure "${relative}: heuristic block balance differs (open $openingBlockCount, close $closingBlockCount). Review function/if/for/while/do/repeat/end/until manually."
        return
    }

    Add-Pass "${relative}: basic Luau balance."
}

Write-Host "Panna Football: read-only project validation" -ForegroundColor Cyan
Write-Host "Root: $root"

$requiredPaths = @(
    '.gitignore',
    'default.project.json',
	'asset-kit.project.json',
    'selene.toml',
    'stylua.toml',
    'README.md',
    'CHANGELOG.md',
    'ASSETS.md',
    'source.project.json',
    'world.project.json',
    'multiplayer.project.json',
    'docs/README.md',
    'docs/setup.md',
    'docs/architecture.md',
    'docs/gameplay.md',
    'docs/world-contract.md',
    'docs/security.md',
    'docs/TESTING.md',
    'docs/test-plan.md',
    'docs/publishing.md',
    'docs/known-limitations.md',
    'docs/roadmap.md',
    'src/shared/Config.lua',
    'src/shared/BallMath.lua',
    'src/shared/Net.lua',
    'src/shared/Types.lua',
    'src/server/init.server.lua',
    'src/server/WorldBuilder.lua',
    'src/server/RemoteRegistry.lua',
    'src/server/RateLimiter.lua',
    'src/server/ArenaService.lua',
    'src/server/RoomService.lua',
    'src/server/PlayerDataService.lua',
    'src/server/QueueService.lua',
    'src/server/MatchService.lua',
    'src/server/BallService.lua',
    'src/server/PannaDetector.lua',
    'src/client/init.client.lua',
    'src/client/EffectScope.lua',
    'src/client/ControlCatalog.lua',
    'src/client/ProceduralPoseCatalog.lua',
    'src/client/PlayerAnimationController.lua',
	'src/client/FootballVFXController.lua',
    'src/client/UIController.lua',
    'src/client/InputController.lua',
    'src/world/PannaDistrict.model.json',
	'src/world/PannaBrightBlockKit.model.json',
	'scripts/brightblock_assets.py',
	'scripts/create-blender-kit.py',
	'scripts/create-roblox-kit.py',
	'scripts/refresh-minimal-bake.py',
	'scripts/validate-artifacts.py',
    'scripts/studio-smoke.luau',
    'scripts/multiplayer-smoke.luau',
    'scripts/bake-editable-place.ps1',
    'scripts/export-world-model.luau',
    'scripts/extract-world-model.ps1',
    'scripts/capture-map.luau',
    'scripts/extract-captures.ps1',
    'tests/multiplayer-server.server.lua',
    'tests/multiplayer-client.client.lua'
)

foreach ($requiredPath in $requiredPaths) {
    $fullPath = Join-Path $root $requiredPath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        Add-Failure "Required path is missing: $requiredPath"
    }
}
if (@($requiredPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) }).Count -eq 0) {
    Add-Pass 'All required paths exist.'
}

$projectSpecifications = @(
    @{ Path = 'default.project.json'; DataModelRoot = $true },
	@{ Path = 'asset-kit.project.json'; DataModelRoot = $false },
    @{ Path = 'source.project.json'; DataModelRoot = $true },
    @{ Path = 'multiplayer.project.json'; DataModelRoot = $true },
    @{ Path = 'world.project.json'; DataModelRoot = $false }
)

$allowedProjectPaths = @(
    $projectSpecifications | ForEach-Object { ([string] $_.Path).Replace('\', '/') }
)
$projectManifestFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.project.json' | Where-Object {
    $relative = (Get-RelativeProjectPath -FullName $_.FullName).Replace('\', '/')
    -not $relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase) -and
    -not $relative.StartsWith('build/', [StringComparison]::OrdinalIgnoreCase)
})
$unexpectedProjectPaths = @()
foreach ($projectManifestFile in $projectManifestFiles) {
    $relative = (Get-RelativeProjectPath -FullName $projectManifestFile.FullName).Replace('\', '/')
    if ($allowedProjectPaths -notcontains $relative) {
        $unexpectedProjectPaths += $relative
        Add-Failure "Unexpected Rojo project manifest: $relative. Panna keeps exactly five allowed release/build/test/asset profiles; default.project.json is the canonical release project."
    }
}
if ($projectManifestFiles.Count -ne $allowedProjectPaths.Count) {
    Add-Failure "Expected exactly $($allowedProjectPaths.Count) Rojo project manifests outside build, found $($projectManifestFiles.Count)."
}
elseif ($unexpectedProjectPaths.Count -eq 0) {
    Add-Pass 'Exactly five allowed Rojo profiles exist outside build; default.project.json is the canonical release project.'
}

foreach ($projectSpecification in $projectSpecifications) {
    $projectPath = [string] $projectSpecification.Path
    $projectFile = Join-Path $root $projectPath
    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        continue
    }

    try {
        $project = Get-Content -LiteralPath $projectFile -Raw | ConvertFrom-Json
        if ($null -eq $project.tree) {
            Add-Failure "$projectPath does not contain tree."
        }
        else {
            if ([bool] $projectSpecification.DataModelRoot) {
                $rootClass = $project.tree.PSObject.Properties['$className']
                if ($null -eq $rootClass -or $rootClass.Value -ne 'DataModel') {
                    Add-Failure "The $projectPath tree root must have `$className = DataModel."
                }
            }
            Test-RojoNode -Node $project.tree -JsonLocation "$projectPath.tree"
        }

        if ([string]::IsNullOrWhiteSpace([string] $project.name)) {
            Add-Failure "$projectPath must have a non-empty name."
        }

        Add-Pass "$projectPath parses as JSON."
    }
    catch {
        Add-Failure "$projectPath failed to parse: $($_.Exception.Message)"
    }
}

$textExtensions = @('.lua', '.luau', '.json', '.md', '.toml', '.yml', '.yaml', '.txt', '.ps1', '.ini', '.cfg', '.env')
$textFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $relative = Get-RelativeProjectPath -FullName $_.FullName
    -not $relative.StartsWith('.git' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
    ($textExtensions -contains $_.Extension.ToLowerInvariant() -or $_.Name -eq '.env') -and
    $_.Length -le 2MB
})

$secretPatterns = @(
    @{ Name = 'GitHub token'; Regex = 'gh[pousr]_[A-Za-z0-9_]{20,}' },
    @{ Name = 'GitHub fine-grained token'; Regex = 'github_pat_[A-Za-z0-9_]{20,}' },
    @{ Name = 'AWS access key'; Regex = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'private key header'; Regex = '-----BEGIN (?:RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----' },
    @{ Name = 'ROBLOSECURITY assignment'; Regex = '(?i)\.ROBLOSECURITY\s*[:=]\s*[^\s<]{16,}' },
    @{ Name = 'secret-like quoted assignment'; Regex = '(?i)\b(?:token|secret|password|passwd|api[_-]?key)\b\s*[:=]\s*["''](?!<|example\b|changeme\b|redacted\b)[A-Za-z0-9_./+=-]{20,}["'']' }
)

$secretFindingCount = 0
foreach ($file in $textFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($pattern in $secretPatterns) {
        foreach ($match in [regex]::Matches($content, [string] $pattern.Regex)) {
            $lineNumber = ($content.Substring(0, $match.Index) -split "`n").Count
            $relative = Get-RelativeProjectPath -FullName $file.FullName
            Add-Failure "${relative}:${lineNumber}: possible secret detected ($($pattern.Name)); value intentionally omitted."
            $secretFindingCount += 1
        }
    }
}
if ($secretFindingCount -eq 0) {
    Add-Pass 'No high-confidence secret signatures found.'
}

$assetReferences = 0
foreach ($file in $textFiles | Where-Object { $_.Extension -in @('.lua', '.luau', '.json') }) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match '(?i)rbxassetid://\d+') {
        $relative = Get-RelativeProjectPath -FullName $file.FullName
        Add-Warning "$relative contains an external asset ID; verify its source and license."
        $assetReferences += 1
    }
}
if ($assetReferences -eq 0) {
    Add-Pass 'No rbxassetid:// references found in source files or JSON.'
}

$ballServicePath = Join-Path $root 'src/server/BallService.lua'
if (Test-Path -LiteralPath $ballServicePath -PathType Leaf) {
    $ballServiceSource = Get-Content -LiteralPath $ballServicePath -Raw
    $ballServiceMask = (Get-LuauCodeMask -Text $ballServiceSource).Mask
    $forbiddenBallControlPatterns = @(
        @{ Name = 'per-frame ball CFrame positioning'; Regex = '\bball\s*\.\s*CFrame\s*=' },
        @{ Name = 'direct ball Position positioning'; Regex = '\bball\s*\.\s*Position\s*=' },
        @{ Name = 'ball PivotTo positioning'; Regex = '\bball\s*:\s*PivotTo\s*\(' },
        @{ Name = 'anchored ball possession'; Regex = '\bball\s*\.\s*Anchored\s*=\s*true\b' },
        @{ Name = 'direct ball linear-velocity assignment'; Regex = '\bball\s*\.\s*AssemblyLinearVelocity\s*=' },
        @{ Name = 'direct ball angular-velocity assignment'; Regex = '\bball\s*\.\s*AssemblyAngularVelocity\s*=' },
        @{ Name = 'server-side reliance on non-replicated MoveDirection'; Regex = '\.\s*MoveDirection\b' }
    )
    $forbiddenBallControlCount = 0
    foreach ($pattern in $forbiddenBallControlPatterns) {
        if ($ballServiceMask -match [string] $pattern.Regex) {
            Add-Failure "src/server/BallService.lua contains $($pattern.Name); canonical control must remain server-observable, impulse/force driven, and unanchored."
            $forbiddenBallControlCount += 1
        }
    }
    if ($ballServiceSource -match 'Instance\s*\.\s*new\s*\(\s*["''](?:AlignPosition|AlignOrientation|LinearVelocity|AngularVelocity|BodyPosition|BodyVelocity|BodyGyro|BodyAngularVelocity)["'']\s*\)') {
        Add-Failure 'src/server/BallService.lua creates a positional/velocity mover; Controlled must use only bounded VectorForce and Torque.'
        $forbiddenBallControlCount += 1
    }
    $requiredPhysicalPatterns = @(
        @{ Name = 'VectorForce actuator'; Source = $ballServiceSource; Regex = 'Instance\s*\.\s*new\s*\(\s*["'']VectorForce["'']\s*\)' },
        @{ Name = 'Torque actuator'; Source = $ballServiceSource; Regex = 'Instance\s*\.\s*new\s*\(\s*["'']Torque["'']\s*\)' },
        @{ Name = 'linear impulse'; Source = $ballServiceMask; Regex = ':\s*ApplyImpulse\s*\(' },
        @{ Name = 'angular impulse'; Source = $ballServiceMask; Regex = ':\s*ApplyAngularImpulse\s*\(' },
        @{ Name = 'manual server ownership'; Source = $ballServiceMask; Regex = ':\s*SetNetworkOwner\s*\(\s*nil\s*\)' },
        @{ Name = 'shared launch velocity'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*LaunchVelocity\s*\(' },
        @{ Name = 'shared launch angular velocity'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*LaunchAngularVelocity\s*\(' },
        @{ Name = 'shared aerodynamic drag'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*AerodynamicDragAcceleration\s*\(' },
        @{ Name = 'smooth dribble distance'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*SmoothControlDistance\s*\(' },
        @{ Name = 'cushioned first touch'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*CushionedTouchVelocity\s*\(' },
        @{ Name = 'bounded aim assistance'; Source = $ballServiceMask; Regex = '\bBallMath\s*\.\s*AssistedHorizontalDirection\s*\(' },
        @{ Name = 'stationary close-control target'; Source = $ballServiceMask; Regex = '\bfeint\s*\.\s*holdPosition\b' },
        @{ Name = 'protected dribble feedback'; Source = $ballServiceSource; Regex = 'DribbleProtected' },
        @{ Name = 'direct tackle takeover'; Source = $ballServiceSource; Regex = '(?s)_setBallMode\s*\(\s*state\s*,\s*["'']Controlled["'']\s*,\s*player\s*,\s*["'']Tackle["'']\s*\)' }
    )
    foreach ($requiredPrimitive in $requiredPhysicalPatterns) {
        if (([string] $requiredPrimitive.Source) -notmatch ([string] $requiredPrimitive.Regex)) {
            Add-Failure "src/server/BallService.lua is missing required physical primitive '$($requiredPrimitive.Name)'."
            $forbiddenBallControlCount += 1
        }
    }
    if ($forbiddenBallControlCount -eq 0) {
        Add-Pass 'BallService keeps the canonical ball unanchored, server-owned, and force/impulse driven.'
    }

    $flightContractFailures = 0
    foreach ($requiredFlightPattern in @(
        @{ Name = 'flight-state trail gate'; Regex = 'trailState\s*=\s*state\.mode\s*==\s*["'']Shot["'']' },
        @{ Name = 'airborne trail gate'; Regex = 'trailEligible\s*=\s*trailState\s+and\s+not\s+state\.grounded' },
        @{ Name = 'grounded Shot exit'; Regex = '(?s)state\.mode\s*==\s*["'']Shot["''].*?state\.grounded.*?_setBallMode\s*\(\s*state\s*,\s*["'']Free["'']' }
    )) {
        if ($ballServiceSource -notmatch [string] $requiredFlightPattern.Regex) {
            Add-Failure "src/server/BallService.lua is missing $($requiredFlightPattern.Name); fast ground movement must not look like an airborne plate."
            $flightContractFailures += 1
        }
    }
    if ($flightContractFailures -eq 0) {
        Add-Pass 'BallService gates its subtle trail to airborne action states and exits grounded Shot directly.'
    }
}

$ballMathPath = Join-Path $root 'src/shared/BallMath.lua'
$configPath = Join-Path $root 'src/shared/Config.lua'
$worldBuilderPath = Join-Path $root 'src/server/WorldBuilder.lua'
if ((Test-Path -LiteralPath $ballMathPath -PathType Leaf) -and
    (Test-Path -LiteralPath $configPath -PathType Leaf) -and
    (Test-Path -LiteralPath $worldBuilderPath -PathType Leaf)) {
    $ballMathSource = Get-Content -LiteralPath $ballMathPath -Raw
    $configSource = Get-Content -LiteralPath $configPath -Raw
    $worldBuilderSource = Get-Content -LiteralPath $worldBuilderPath -Raw
    $footballVisualFailures = 0
    foreach ($helperName in @(
        'LaunchVelocity',
        'LaunchAngularVelocity',
        'AerodynamicDragAcceleration',
        'SmoothControlDistance',
        'AssistedHorizontalDirection',
        'CushionedTouchVelocity'
    )) {
        if ($ballMathSource -notmatch ('function\s+BallMath\.' + [regex]::Escape($helperName) + '\s*\(')) {
            Add-Failure "BallMath is missing the production helper $helperName."
            $footballVisualFailures += 1
        }
    }
    foreach ($configToken in @(
        'VisualVersion',
        'MechanicsVersion',
        'Aerodynamics',
        'DragCoefficient',
        'MaximumDragAcceleration',
        'MaximumStepSeconds',
        'RollRatio',
        'ChargeMaximumSeconds',
        'AimAssist',
        'MovementAssistStrength',
        'TrapHorizontalRetention',
        'DefenderMinimumDot',
        'TakeoverGraceSeconds',
        'ProtectionBreakRadius',
        'HoldNaturalFrequency'
    )) {
        if ($configSource -notmatch ('\b' + [regex]::Escape($configToken) + '\b')) {
            Add-Failure "Config is missing football flight/visual tuning '$configToken'."
            $footballVisualFailures += 1
        }
    }
    foreach ($legacySpinToken in @('RollSpin', 'AngularVelocityScale')) {
        if ($configSource -match ('\b' + [regex]::Escape($legacySpinToken) + '\b')) {
            Add-Failure "Config still contains legacy arbitrary spin tuning '$legacySpinToken'."
            $footballVisualFailures += 1
        }
    }
    foreach ($legacyDribbleToken in @('VulnerabilityStart', 'VulnerabilityEnd', 'FeintVulnerabilityRadiusBonus', 'FeintVulnerabilityDotBonus')) {
        if ($configSource -match ('\b' + [regex]::Escape($legacyDribbleToken) + '\b')) {
            Add-Failure "Config still contains obsolete vulnerable-dribble tuning '$legacyDribbleToken'."
            $footballVisualFailures += 1
        }
    }
    foreach ($worldToken in @('BallVisualVersion', 'PannaBallPanel_%02d', 'BallVisualPanel', 'PanelWeld', 'ensureBallTrail')) {
        if ($worldBuilderSource -notmatch [regex]::Escape($worldToken)) {
            Add-Failure "WorldBuilder soccer-ball contract is missing '$worldToken'."
            $footballVisualFailures += 1
        }
    }
    if ($worldBuilderSource -notmatch 'Massless\s*=\s*true' -or
        $worldBuilderSource -notmatch 'CanCollide\s*=\s*false' -or
        $worldBuilderSource -notmatch 'WeldConstraint') {
        Add-Failure 'WorldBuilder soccer panels are not explicitly cosmetic, massless, and welded.'
        $footballVisualFailures += 1
    }
    if ($footballVisualFailures -eq 0) {
        Add-Pass 'Shared football control/assist/launch math and the versioned six-panel ball visual contract are present.'
    }
}

$matchServicePath = Join-Path $root 'src/server/MatchService.lua'
if ((Test-Path -LiteralPath $ballServicePath -PathType Leaf) -and
    (Test-Path -LiteralPath $matchServicePath -PathType Leaf)) {
    $ballServiceSource = Get-Content -LiteralPath $ballServicePath -Raw
    $matchServiceSource = Get-Content -LiteralPath $matchServicePath -Raw
    $actionCueFailures = 0
    foreach ($actionName in @('Charge', 'Kick', 'Pass', 'Trap', 'Dash', 'Shield', 'Tackle', 'Feint', 'Skill')) {
        $cuePattern = '_emitAction\s*\(\s*player\s*,\s*["'']' + [regex]::Escape($actionName) + '["'']'
        if ($ballServiceSource -notmatch $cuePattern) {
            Add-Failure "BallService does not emit the player-animation cue '$actionName'."
            $actionCueFailures += 1
        }
    }
    foreach ($fixedCue in @(
        @{ Action = 'Charge'; Mode = 'Stop' },
        @{ Action = 'Pass'; Mode = 'Ground' },
        @{ Action = 'Trap'; Mode = 'Control' },
        @{ Action = 'Dash'; Mode = 'Forward' },
        @{ Action = 'Shield'; Mode = 'Start' },
        @{ Action = 'Shield'; Mode = 'Stop' },
        @{ Action = 'Tackle'; Mode = 'Standing' },
        @{ Action = 'Skill'; Mode = 'Panna' }
    )) {
        $fixedPattern = '_emitAction\s*\(\s*player\s*,\s*["'']' +
            [regex]::Escape([string] $fixedCue.Action) + '["'']\s*,\s*["'']' +
            [regex]::Escape([string] $fixedCue.Mode) + '["'']'
        if ($ballServiceSource -notmatch $fixedPattern) {
            Add-Failure "BallService is missing the '$($fixedCue.Action)/$($fixedCue.Mode)' animation cue."
            $actionCueFailures += 1
        }
    }
    foreach ($matchToken in @('SetActionCallback', 'BroadcastPlayerAction', 'PlayerAction', 'VisualRevision', 'visualRevision', 'serverTime', 'actorUserId')) {
        if ($matchServiceSource -notmatch [regex]::Escape($matchToken)) {
            Add-Failure "MatchService player-animation broadcast is missing '$matchToken'."
            $actionCueFailures += 1
        }
    }
    if ($matchServiceSource -notmatch 'VisualRevision\s*\+=\s*1' -or
        $matchServiceSource -notmatch '(?s)BroadcastPlayerAction.*?self\s*:\s*_effect\s*\(') {
        Add-Failure 'MatchService does not advance and scope the replicated player-action visual revision.'
        $actionCueFailures += 1
    }
    foreach ($chargeSafetyToken in @('expiresAt', 'CancelCharge', '_stepCharges', '_clearPlayerRuntime')) {
        if ($ballServiceSource -notmatch [regex]::Escape($chargeSafetyToken)) {
            Add-Failure "BallService charge lifecycle is missing '$chargeSafetyToken'."
            $actionCueFailures += 1
        }
    }
    $serverInitPath = Join-Path $root 'src/server/init.server.lua'
    if (Test-Path -LiteralPath $serverInitPath -PathType Leaf) {
        $serverInitSource = Get-Content -LiteralPath $serverInitPath -Raw
        if ($serverInitSource -notmatch '(?s)RateLimited.*?CancelCharge|CancelCharge.*?RateLimited') {
            Add-Failure 'Rate-limited Kick/Pass releases do not cancel the authoritative charge hold.'
            $actionCueFailures += 1
        }
    }
    if ($actionCueFailures -eq 0) {
        Add-Pass 'Server action cues cover every football mechanic and broadcast a scoped monotonic visual revision.'
    }
}

$inputControllerPath = Join-Path $root 'src/client/InputController.lua'
$controlCatalogPath = Join-Path $root 'src/client/ControlCatalog.lua'
$uiControllerPath = Join-Path $root 'src/client/UIController.lua'
if ((Test-Path -LiteralPath $inputControllerPath -PathType Leaf) -and (Test-Path -LiteralPath $controlCatalogPath -PathType Leaf)) {
    $inputControllerSource = Get-Content -LiteralPath $inputControllerPath -Raw
    $controlCatalogSource = Get-Content -LiteralPath $controlCatalogPath -Raw
    $bindingContracts = @(
        @{ Action = 'Kick'; Inputs = @('Enum.UserInputType.MouseButton1', 'Enum.KeyCode.ButtonR2') },
        @{ Action = 'Pass'; Inputs = @('Enum.UserInputType.MouseButton2', 'Enum.KeyCode.ButtonX') },
        @{ Action = 'Feint'; Inputs = @('Enum.KeyCode.Q', 'Enum.KeyCode.ButtonR1') },
        @{ Action = 'Tackle'; Inputs = @('Enum.KeyCode.E', 'Enum.KeyCode.ButtonB') },
        @{ Action = 'Skill'; Inputs = @('Enum.KeyCode.R', 'Enum.KeyCode.ButtonY') },
        @{ Action = 'Shield'; Inputs = @('Enum.KeyCode.C', 'Enum.KeyCode.ButtonL2') },
        @{ Action = 'Dash'; Inputs = @('Enum.KeyCode.X', 'Enum.KeyCode.ButtonL1') },
        @{ Action = 'ShotMode'; Inputs = @('Enum.KeyCode.Z', 'Enum.KeyCode.DPadUp') }
    )
    $invalidBindingCount = 0
    foreach ($contract in $bindingContracts) {
        $definitionPattern = '(?s)\b' + [regex]::Escape([string] $contract.Action) + '\s*=\s*table\.freeze\s*\(\s*\{(?<Body>.*?inputs\s*=\s*table\.freeze\s*\(\s*\{.*?\}\s*\))'
        $definitionMatch = [regex]::Match($controlCatalogSource, $definitionPattern)
        if (-not $definitionMatch.Success) {
            Add-Failure "ControlCatalog does not define $($contract.Action) with an input list."
            $invalidBindingCount += 1
            continue
        }
        foreach ($inputToken in $contract.Inputs) {
            if ($definitionMatch.Groups['Body'].Value -notmatch [regex]::Escape([string] $inputToken)) {
                Add-Failure "ControlCatalog does not bind $($contract.Action) to $inputToken."
                $invalidBindingCount += 1
            }
        }
    }
    if ($inputControllerSource -notmatch 'require\s*\(\s*script\.Parent:WaitForChild\s*\(\s*["'']ControlCatalog["'']\s*\)\s*\)' -or
        $inputControllerSource -notmatch 'table\.unpack\s*\(') {
        Add-Failure 'InputController does not consume the shared ControlCatalog input lists.'
        $invalidBindingCount += 1
    }
    foreach ($primaryTakeoverToken in @(
        '_primaryMouseUsesTackle',
        'ballState == "Controlled"',
        'self:_onInstantAction("Tackle", inputState)',
        'self:_onPrimaryAction(inputState, input)'
    )) {
        if ($inputControllerSource -notmatch [regex]::Escape($primaryTakeoverToken)) {
            Add-Failure "InputController contextual LMB takeover is missing '$primaryTakeoverToken'."
            $invalidBindingCount += 1
        }
    }
    if ($invalidBindingCount -eq 0) {
        Add-Pass 'Shared control catalog binds all actions and routes opponent-owned LMB to direct takeover.'
    }
}

if ((Test-Path -LiteralPath $controlCatalogPath -PathType Leaf) -and (Test-Path -LiteralPath $uiControllerPath -PathType Leaf)) {
    $controlCatalogSource = Get-Content -LiteralPath $controlCatalogPath -Raw
    $uiControllerSource = Get-Content -LiteralPath $uiControllerPath -Raw
    $guideIds = @('BallControl', 'Kick', 'ShotMode', 'Pass', 'Feint', 'Skill', 'Tackle', 'Shield', 'Dash')
    $missingGuideContracts = 0
    foreach ($guideId in $guideIds) {
        if ($controlCatalogSource -notmatch ('id\s*=\s*["'']' + [regex]::Escape($guideId) + '["'']')) {
            Add-Failure "ControlCatalog guide is missing $guideId."
            $missingGuideContracts += 1
        }
    }
    foreach ($requiredUiToken in @('ControlsGuide', 'SetControlsGuideVisible', 'ToggleControlsGuide', 'IsControlsGuideVisible', 'Enum.KeyCode.H', 'Enum.KeyCode.ButtonSelect')) {
        if ($uiControllerSource -notmatch [regex]::Escape($requiredUiToken)) {
            Add-Failure "UIController controls guide is missing '$requiredUiToken'."
            $missingGuideContracts += 1
        }
    }
    if ($missingGuideContracts -eq 0) {
        Add-Pass 'In-game controls guide covers ball control and every ability with reusable toggle bindings.'
    }
}

$poseCatalogPath = Join-Path $root 'src/client/ProceduralPoseCatalog.lua'
$playerAnimationPath = Join-Path $root 'src/client/PlayerAnimationController.lua'
$clientInitPath = Join-Path $root 'src/client/init.client.lua'
if ((Test-Path -LiteralPath $poseCatalogPath -PathType Leaf) -and
    (Test-Path -LiteralPath $playerAnimationPath -PathType Leaf) -and
    (Test-Path -LiteralPath $clientInitPath -PathType Leaf)) {
    $poseCatalogSource = Get-Content -LiteralPath $poseCatalogPath -Raw
    $playerAnimationSource = Get-Content -LiteralPath $playerAnimationPath -Raw
    $clientInitSource = Get-Content -LiteralPath $clientInitPath -Raw
    $animationFailures = 0

    foreach ($actionName in @('Charge', 'Kick', 'Pass', 'Trap', 'Shield', 'Dash', 'Tackle', 'Skill', 'Feint')) {
        if ($poseCatalogSource -notmatch ('["'']' + [regex]::Escape($actionName) + '["'']')) {
            Add-Failure "ProceduralPoseCatalog is missing the football action '$actionName'."
            $animationFailures += 1
        }
    }
    foreach ($variantName in @('StepOver', 'Cut', 'DragBack', 'Roulette')) {
        if ($poseCatalogSource -notmatch ('["'']' + [regex]::Escape($variantName) + '["'']')) {
            Add-Failure "ProceduralPoseCatalog is missing the feint variant '$variantName'."
            $animationFailures += 1
        }
    }
    foreach ($jointName in @('Root', 'Waist', 'Neck', 'LeftShoulder', 'RightShoulder', 'LeftHip', 'RightHip', 'LeftKnee', 'RightKnee', 'LeftAnkle', 'RightAnkle')) {
        if ($poseCatalogSource -notmatch ('["'']' + [regex]::Escape($jointName) + '["'']')) {
            Add-Failure "ProceduralPoseCatalog normalized joint whitelist is missing '$jointName'."
            $animationFailures += 1
        }
    }
    foreach ($catalogMethod in @('IsSupported', 'GetDuration', 'IsHold', 'Sample')) {
        if ($poseCatalogSource -notmatch ('function\s+ProceduralPoseCatalog\.' + [regex]::Escape($catalogMethod) + '\s*\(')) {
            Add-Failure "ProceduralPoseCatalog.$catalogMethod is missing."
            $animationFailures += 1
        }
    }

    foreach ($controllerToken in @('Motor6D', 'AnimationConstraint', 'PreSimulation', 'MAX_EFFECT_AGE', 'MAX_EFFECT_FUTURE', 'MAX_HOLD_AGE', 'lastVisualRevision', '_scopeMatches', 'visualRevision', 'serverTime')) {
        if ($playerAnimationSource -notmatch [regex]::Escape($controllerToken)) {
            Add-Failure "PlayerAnimationController runtime contract is missing '$controllerToken'."
            $animationFailures += 1
        }
    }
    foreach ($controllerMethod in @('new', 'ApplyEffect', 'BeginCharge', 'CancelCharge', 'ApplyActionFeedback', 'Reset', 'ResetTransientState', 'Destroy')) {
        if ($playerAnimationSource -notmatch ('function\s+PlayerAnimationController\.' + [regex]::Escape($controllerMethod) + '\s*\(')) {
            Add-Failure "PlayerAnimationController.$controllerMethod is missing."
            $animationFailures += 1
        }
    }

    $forbiddenAnimationMutationPatterns = @(
        @{ Name = 'world CFrame mutation'; Regex = '\.\s*CFrame\s*=' },
        @{ Name = 'character PivotTo mutation'; Regex = ':\s*PivotTo\s*\(' },
        @{ Name = 'linear velocity mutation'; Regex = '\.\s*AssemblyLinearVelocity\s*=' },
        @{ Name = 'angular velocity mutation'; Regex = '\.\s*AssemblyAngularVelocity\s*=' },
        @{ Name = 'WalkSpeed mutation'; Regex = '\.\s*WalkSpeed\s*=' },
        @{ Name = 'JumpHeight mutation'; Regex = '\.\s*JumpHeight\s*=' },
        @{ Name = 'JumpPower mutation'; Regex = '\.\s*JumpPower\s*=' },
        @{ Name = 'AutoRotate mutation'; Regex = '\.\s*AutoRotate\s*=' },
        @{ Name = 'physical impulse'; Regex = ':\s*Apply(?:Angular)?Impulse\s*\(' }
    )
    $animationMask = (Get-LuauCodeMask -Text $playerAnimationSource).Mask
    foreach ($forbiddenMutation in $forbiddenAnimationMutationPatterns) {
        if ($animationMask -match [string] $forbiddenMutation.Regex) {
            Add-Failure "PlayerAnimationController contains $($forbiddenMutation.Name); procedural animation must remain additive and cosmetic."
            $animationFailures += 1
        }
    }

    foreach ($initToken in @('PlayerAnimationController', 'PlayerAnimationController.new(LOCAL_PLAYER)', 'playerAnimations:ResetTransientState()', 'playerAnimations:Destroy()', 'playerAnimations:ApplyActionFeedback(payload)', 'playerAnimations:ApplyEffect(payload)')) {
        if ($clientInitSource -notmatch [regex]::Escape($initToken)) {
            Add-Failure "Client animation lifecycle integration is missing '$initToken'."
            $animationFailures += 1
        }
    }
    if ($clientInitSource -notmatch '(?s)if\s+not\s+playerAnimations:ApplyEffect\s*\(\s*payload\s*\)\s+then\s+ui:ApplyEffect') {
        Add-Failure 'Client does not consume PlayerAction effects before the generic UI notification path.'
        $animationFailures += 1
    }
    if ($clientInitSource -notmatch '(?s)if\s+inputController:ApplyActionFeedback\s*\(\s*payload\s*\)\s+then\s+playerAnimations:ApplyActionFeedback') {
        Add-Failure 'Client applies animation feedback before InputController validates its sequence and match context.'
        $animationFailures += 1
    }
    if ($playerAnimationSource -notmatch '(?s)not\s+actor\s+or\s+not\s+actor\.hold.*?BeginCharge') {
        Add-Failure 'ActionFeedback can rewind an already-authoritative Charge pose.'
        $animationFailures += 1
    }
    if ($playerAnimationSource -notmatch 'now\s*-\s*hold\.startedAt\s*>\s*MAX_HOLD_AGE') {
        Add-Failure 'Held procedural poses do not have a local hard-timeout.'
        $animationFailures += 1
    }
    if ($playerAnimationSource -notmatch '(?s)if\s+not\s+timestampValid\s+and\s+not\s+isStop\s+then.*?if\s+isStop\s+then.*?actor\.hold\s*=\s*nil') {
        Add-Failure 'Stale scoped Stop/Cancel cues cannot clear a held procedural pose.'
        $animationFailures += 1
    }

    if ($animationFailures -eq 0) {
        Add-Pass 'Asset-free player poses cover every mechanic with scoped cue filtering, additive joints, and full client lifecycle cleanup.'
    }
}

$footballVFXPath = Join-Path $root 'src/client/FootballVFXController.lua'
if ((Test-Path -LiteralPath $footballVFXPath -PathType Leaf) -and
    (Test-Path -LiteralPath $inputControllerPath -PathType Leaf) -and
    (Test-Path -LiteralPath $clientInitPath -PathType Leaf) -and
    (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    $footballVFXSource = Get-Content -LiteralPath $footballVFXPath -Raw
    $inputControllerSource = Get-Content -LiteralPath $inputControllerPath -Raw
    $clientInitSource = Get-Content -LiteralPath $clientInitPath -Raw
    $configSource = Get-Content -LiteralPath $configPath -Raw
    $vfxFailures = 0

    foreach ($vfxToken in @('Beam', 'TrajectoryDot', 'BallDirection', 'Highlight', 'MaximumTransientParts', 'LocalOnlyVFX', 'TweenService')) {
        if ($footballVFXSource -notmatch [regex]::Escape($vfxToken)) {
            Add-Failure "FootballVFXController runtime contract is missing '$vfxToken'."
            $vfxFailures += 1
        }
    }
    foreach ($vfxMethod in @('new', 'SetAimState', 'ApplyEffect', 'ResetTransientState', 'Destroy', 'GetPalette')) {
        if ($footballVFXSource -notmatch ('function\s+FootballVFXController\.' + [regex]::Escape($vfxMethod) + '\s*\(')) {
            Add-Failure "FootballVFXController.$vfxMethod is missing."
            $vfxFailures += 1
        }
    }
    foreach ($cosmeticToken in @('CanCollide = false', 'CanTouch = false', 'CanQuery = false')) {
        if ($footballVFXSource -notmatch [regex]::Escape($cosmeticToken)) {
            Add-Failure "FootballVFXController does not explicitly enforce '$cosmeticToken'."
            $vfxFailures += 1
        }
    }
    if ($footballVFXSource -match 'rbxassetid://') {
        Add-Failure 'FootballVFXController unexpectedly depends on an external Roblox asset id.'
        $vfxFailures += 1
    }
    foreach ($configToken in @('VisualEffects', 'StreetReadabilityV1', 'AimGuide', 'BallDirection', 'Impact')) {
        if ($configSource -notmatch [regex]::Escape($configToken)) {
            Add-Failure "Config is missing football VFX tuning '$configToken'."
            $vfxFailures += 1
        }
    }
    foreach ($inputToken in @('SetAimState', '_directionForAction(previewAction)', 'previewPower', 'self._chargingAction ~= nil')) {
        if ($inputControllerSource -notmatch [regex]::Escape($inputToken)) {
            Add-Failure "InputController direction-preview integration is missing '$inputToken'."
            $vfxFailures += 1
        }
    }
    foreach ($initToken in @('FootballVFXController.new(LOCAL_PLAYER)', 'footballVFX:ApplyEffect(payload)', 'footballVFX:ResetTransientState()', 'footballVFX:Destroy()', 'InputController.new(actionRequest, ui, footballVFX)')) {
        if ($clientInitSource -notmatch [regex]::Escape($initToken)) {
            Add-Failure "Client VFX lifecycle integration is missing '$initToken'."
            $vfxFailures += 1
        }
    }
    if ($clientInitSource -notmatch '(?s)footballVFX:ApplyEffect\s*\(\s*payload\s*\).*?playerAnimations:ApplyEffect\s*\(\s*payload\s*\)') {
        Add-Failure 'Client does not route scoped effects through VFX before the animation/UI fallback.'
        $vfxFailures += 1
    }
    if ($vfxFailures -eq 0) {
        Add-Pass 'Asset-free local VFX provide submitted aim, charged trajectory, replicated ball direction, action impacts, and bounded cleanup.'
    }
}

$robloxArtifacts = @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $relative = (Get-RelativeProjectPath -FullName $_.FullName).Replace('\', '/')
    -not $relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase) -and
    -not $relative.StartsWith('build/', [StringComparison]::OrdinalIgnoreCase) -and
    $_.Extension.ToLowerInvariant() -in @('.rbxl', '.rbxlx', '.rbxm', '.rbxmx')
})
foreach ($artifact in $robloxArtifacts) {
    Add-Warning "Roblox artifact found in the source tree: $(Get-RelativeProjectPath -FullName $artifact.FullName). Verify it is intentionally untracked."
}

$luauFiles = @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $relative = Get-RelativeProjectPath -FullName $_.FullName
    -not $relative.StartsWith('.git' + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -and
    $_.Extension.ToLowerInvariant() -in @('.lua', '.luau')
})
foreach ($luauFile in $luauFiles) {
    Test-LuauBalance -File $luauFile
}
if ($luauFiles.Count -eq 0) {
    Add-Failure 'No .lua/.luau files were found under src.'
}

foreach ($pass in $passes) {
    Write-Host "[OK]   $pass" -ForegroundColor Green
}
foreach ($warning in $warnings) {
    Write-Host "[WARN] $warning" -ForegroundColor Yellow
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}

Write-Host ""
Write-Host "Summary: OK=$($passes.Count), WARN=$($warnings.Count), FAIL=$($failures.Count)"
Write-Host "Luau checks are heuristic; they do not replace a parser, typecheck, Selene, or Roblox Studio tests."

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
