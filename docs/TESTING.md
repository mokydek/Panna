# Фактические проверки

Этот файл фиксирует проверки, которые действительно выполнялись для текущей основы проекта. Полный набор будущих сценариев находится в [тест-плане](test-plan.md).

## Текущий статус

| Проверка | Статус | Что доказано |
| --- | --- | --- |
| `scripts/validate-project.ps1` | пройдена | JSON Rojo читается, обязательные пути существуют, высокоуверенные сигнатуры секретов не найдены, базовый эвристический баланс текущих Luau-файлов совпадает |
| `rojo build` + Roblox Studio CLI `RunScript` | пройдена, exit code 0 | Rojo mapping, загрузка модулей, процедурный мир, две арены, створы ворот, reset, инициализация `BallService`, server-owned мячи и классы Remote |
| Multiplayer Local Server с 2+ клиентами | **не подтверждён** | Требуется ручной Play test |
| Полный матч, гол, overtime, панна, disconnect, rematch | **не подтверждены** | Требуется ручной многоклиентный прогон |
| DataStore load/save в опубликованном staging | **не подтверждён** | Требуется отдельный staging Experience и безопасные тестовые данные |
| Физические мобильные устройства/геймпад/сетевые условия | **не подтверждены** | Требуются реальные устройства и latency tests |

Статус «пройдена» относится к проверенному commit/рабочему дереву. После изменения мира, контрактов Arena/Remote или Rojo mapping тест нужно повторить.

## Подтверждённый Studio CLI smoke

После финальных изменений текущий `scripts/studio-smoke.luau` был заново выполнен официальной задачей Roblox Studio CLI `RunScript` над place, собранным Rojo. Процесс завершился с exit code 0 и маркером:

```text
PANNA_STUDIO_SMOKE_OK version=0.1.0-alpha arenas=2
```

Подтверждённый прогон фактически проверил:

1. `ServerScriptService/PannaServer` и `ReplicatedStorage/PannaShared` попали в place через Rojo.
2. Загружаются `Config`, `Net`, `Types`, `WorldBuilder`, `ArenaService`, `RemoteRegistry`, `RateLimiter`, `PlayerDataService`, `PannaDetector`, `BallService`, `MatchService` и `QueueService`.
3. `WorldBuilder.Build` создаёт корень нужного имени, `LobbySpawn` и `QueuePrompt`.
4. `ArenaService` обнаруживает ровно две MVP-арены.
5. У каждой арены совпадает `ArenaId`, мяч физический и незакреплённый, голевые зоны касаемые и не сталкиваются, их створ начинается на уровне поля, `Bounds` закреплён и не сталкивается.
6. `ArenaService:ResetBall` возвращает мяч к `BallSpawn` с допустимой погрешностью.
7. `BallService.new` создаёт runtime-state для каждой арены, а оба мяча остаются под network ownership сервера.
8. RemoteEvent/RemoteFunction созданы с ожидаемыми классами.

Этот подтверждённый прогон относится к расширенному сценарию с `BallService.new`, проверкой server-owned мячей и нижней границы створов. После любого изменения smoke-файла повторите прогон: прежний лог не подтверждает новую версию сценария.

## Как воспроизвести

Нужны доступный в `PATH` Rojo и установленный Roblox Studio. Не фиксируйте папку вида `version-...`: Studio обновляется, поэтому найдите текущий `RobloxStudioBeta.exe`.

Из корня репозитория выполните в PowerShell:

```powershell
$pannaRoot = (Resolve-Path '.').Path
$pannaRunId = [guid]::NewGuid().ToString('N')
$pannaSmokeDir = Join-Path ([IO.Path]::GetTempPath()) ("PannaStudioSmoke-$pannaRunId")
New-Item -ItemType Directory -Force -Path $pannaSmokeDir | Out-Null

$pannaPlace = Join-Path $pannaSmokeDir 'Panna-test.rbxlx'
$pannaOutput = Join-Path $pannaSmokeDir 'studio-smoke-output.log'
$pannaScript = Join-Path $pannaRoot 'scripts\studio-smoke.luau'

rojo build (Join-Path $pannaRoot 'default.project.json') --output $pannaPlace
if ($LASTEXITCODE -ne 0) { throw 'Rojo build failed' }

$pannaVersions = Join-Path $env:LOCALAPPDATA 'Roblox\Versions'
$pannaStudio = Get-ChildItem -Path $pannaVersions -Filter 'RobloxStudioBeta.exe' -File -Recurse |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $pannaStudio) { throw 'RobloxStudioBeta.exe was not found' }

$pannaArguments = @(
    '--task', 'RunScript',
    '--localPlaceFile', ('"' + $pannaPlace + '"'),
    '--runScriptFile', ('"' + $pannaScript + '"'),
    '--outputFile', ('"' + $pannaOutput + '"'),
    '--quitAfterExecution'
)

$pannaProcess = Start-Process `
    -FilePath $pannaStudio.FullName `
    -ArgumentList $pannaArguments `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

if ($pannaProcess.ExitCode -ne 0) {
    throw "Roblox Studio RunScript failed with exit code $($pannaProcess.ExitCode)"
}
if (-not (Test-Path -LiteralPath $pannaOutput -PathType Leaf)) {
    throw 'Roblox Studio did not create the requested output file'
}
Get-Content -LiteralPath $pannaOutput
if (-not (Select-String -LiteralPath $pannaOutput -SimpleMatch 'PANNA_STUDIO_SMOKE_OK' -Quiet)) {
    throw 'Studio smoke marker was not found'
}
```

`--outputFile` содержит сам выполненный скрипт и результат. Успех определяйте по точному маркеру, а не только по существованию файла или exit code.

## Что smoke не проверяет

`RunScript` намеренно узкий и **не доказывает**:

- полный обычный запуск `init.server.lua` и жизненный цикл сервера;
- работу двух клиентов, очереди и одновременных арен;
- симуляцию Heartbeat, сетевую физику и network ownership во время матча;
- корректность/матрицу collision groups в многопользовательской физике, возврат посторонних, movement envelope и фактическую длительность Dash;
- голевой debounce в реальной физике, таймер, overtime или rematch;
- выполнение `PannaDetector:Begin`/`Step`, успешную/ложную панну и отмену кандидата после чужого касания;
- RemoteEvent-защиту от exploit-клиента;
- HUD, ContextActionService, mobile/gamepad UX;
- DataStore, уникальность lease при быстром rejoin, unsafe/recovery после save failure, autosave, `BindToClose` и идемпотентность при реальном отключении.

Для этих областей выполните [ручной тест-план](test-plan.md) и не меняйте их статус на «пройдено» без воспроизводимого отчёта.
