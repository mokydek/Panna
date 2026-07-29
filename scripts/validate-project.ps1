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
    'src/client/UIController.lua',
    'src/client/InputController.lua',
    'src/world/PannaDistrict.model.json',
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
        Add-Failure "Unexpected Rojo project manifest: $relative. Panna keeps exactly four allowed internal build/test profiles; default.project.json is the canonical release project."
    }
}
if ($projectManifestFiles.Count -ne $allowedProjectPaths.Count) {
    Add-Failure "Expected exactly $($allowedProjectPaths.Count) Rojo project manifests outside build, found $($projectManifestFiles.Count)."
}
elseif ($unexpectedProjectPaths.Count -eq 0) {
    Add-Pass 'Exactly four allowed internal Rojo profiles exist outside build; default.project.json is the canonical release project.'
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
        @{ Name = 'manual server ownership'; Source = $ballServiceMask; Regex = ':\s*SetNetworkOwner\s*\(\s*nil\s*\)' }
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
    if ($invalidBindingCount -eq 0) {
        Add-Pass 'Shared control catalog binds all actions for mouse/keyboard, gamepad, and touch UI.'
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
