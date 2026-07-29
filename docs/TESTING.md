# Фактические проверки

Этот файл фиксирует проверки, которые действительно выполнялись для текущей основы проекта. Полный набор будущих сценариев находится в [тест-плане](test-plan.md).

## Текущий статус

| Проверка | Статус | Что доказано |
| --- | --- | --- |
| `scripts/validate-project.ps1` | пройдена: `32 OK / 0 WARN / 0 FAIL` | Все четыре существующих внутренних Rojo-профиля читаются; `default.project.json` остаётся единственным canonical release-проектом; обязательные пути существуют, высокоуверенные сигнатуры секретов не найдены, базовый эвристический баланс текущих Luau-файлов совпадает |
| StyLua / Selene / `git diff --check` | пройдены | Форматирование чистое; Selene сообщил `0 errors / 0 warnings / 0 parse errors`; whitespace-ошибок diff нет |
| Четыре существующих внутренних manifest build | пройдены | Собраны `default.project.json`, `source.project.json`, `world.project.json` и `multiplayer.project.json`; новых manifests или проектов не создавалось |
| `rojo build` + Roblox Studio CLI `RunScript` | пройдена, exit code 0 | Rojo mapping, загрузка модулей, `BallMath`, настройки Low/Normal/Chip/Pass и speed caps, `PannaDistrict`, шесть тематических комнат, reset, runtime `BallService`, server-owned мячи, force/trail и классы Remote |
| Запечённая модель Edit Mode | пройдена с `PANNA_BAKE_OK` | `default.project.json` подключает обновлённый `src/world/PannaDistrict.model.json`; совместимый корень переиспользуется сервером, а процедурная регенерация остаётся fallback |
| Исторический `StudioTestService` Local Server smoke (4 клиента, 2 комнаты) | пройден до переработки мяча | Четыре клиента физически активировали `EntryPrompt`, вошли в две независимые комнаты с разными `MatchId`, получили верные `ArenaId`/`InMatch`, а барьеры закрылись |
| Текущий расширенный Local Server smoke мяча (4 клиента, 2 комнаты) | **заблокирован внешним запуском Studio** | Две попытки на Studio `0.732.0.7321040` остановились в дочернем Local Server на `GetPlaceSafetyInfoFailure` для локального `universe 0` до загрузки игровых/test scripts; сценарий нужно повторить в приватном опубликованном staging Place |
| Полный матч, гол, overtime, панна, disconnect, rematch | **не подтверждены** | Требуется ручной многоклиентный прогон |
| DataStore load/save в опубликованном staging | **не подтверждён** | Требуется отдельный staging Experience и безопасные тестовые данные |
| Физические мобильные устройства/геймпад/сетевые условия | **не подтверждены** | Требуются реальные устройства и latency tests |

Статус «пройдена» относится к проверенному commit/рабочему дереву. После изменения мира, контрактов Arena/Remote или Rojo mapping тест нужно повторить.

## Устройство многоклиентных smoke

`multiplayer.project.json` собирает тестовый place из того же игрового кода и `src/world/PannaDistrict.model.json`, что и основной проект, и дополнительно подключает:

- `tests/multiplayer-server.server.lua` — серверные ожидания готовности, размещение четырёх игроков в двух комнатах, два реальных паса, revisions, скорость, last touch, изоляция и устойчивость после malformed spam;
- `tests/multiplayer-client.client.lua` — клиентское физическое использование `EntryPrompt`, цепочка `ChargeStart → Pass`, проверка `ActionFeedback` и отправка 72 некорректных запросов от каждого из двух управляющих клиентов;
- `scripts/multiplayer-smoke.luau` — драйвер `StudioTestService:ExecuteMultiplayerTestAsync(4, ...)`.

Тестовые server/client-скрипты отсутствуют в `default.project.json`, поэтому не попадают в обычную сборку.

Предыдущая, более узкая версия room-сценария до текущей переработки мяча завершилась точным маркером дочернего server-процесса:

```text
PANNA_MULTIPLAYER_END PANNA_MULTIPLAYER_SMOKE_OK clients=4 arenas=2 matches=2
```

Маркер означает, что:

1. сервер и четыре клиента дождались готовности игрового runtime и персонажей;
2. две пары клиентов были перемещены к `EntryZone` комнат `Arena_1` и `Arena_2`;
3. каждый клиент физически удержал свой `EntryPrompt`, после чего обе комнаты вошли в `Countdown` или `Active`;
4. комнаты получили два разных непустых `MatchId`, а каждый игрок — `InMatch = true` и ожидаемый `ArenaId`;
5. барьеры обеих занятых комнат закрылись.

Это исторический программный Local Server результат через `StudioTestService`, а не подтверждение текущего расширенного ball-сценария и не ручной Play-прогон. Он подтверждает две одновременно работающие комнаты на прежнем runtime, но не текущие пас/revision/security проверки, полный матч до `Result`/`Free`, реванш или все шесть комнат одновременно.

Текущий расширенный сценарий запускался дважды с таймаутами 180 и 420 секунд. В обеих попытках Studio `0.732.0.7321040` создала дочерний Local Server, но тот завершил загрузку до игровых scripts с сообщением:

```text
GetPlaceSafetyInfoFailure: Failed to get provisional rating for universe 0, error code 500
```

В логах отсутствуют `PANNA_MULTIPLAYER_SERVER_BOOT`, `PANNA_MULTIPLAYER_CLIENT_BOOT`, Luau stack trace и маркер завершения; DataModel дочернего процесса показывал `0 Scripts`. Поэтому результат классифицирован как внешний блокер локального unpublished `universe 0`, а не как пройденный или упавший тест механик. Безопасный следующий прогон требует приватного staging Place с ненулевыми `placeId`/`universeId`; публикация не выполнялась без отдельного разрешения владельца.

## Подтверждённый Studio CLI smoke

После финальных изменений текущий `scripts/studio-smoke.luau` был заново выполнен официальной задачей Roblox Studio CLI `RunScript` над place, собранным Rojo. Процесс завершился с exit code 0 и маркером:

```text
PANNA_STUDIO_SMOKE_OK version=0.2.0-alpha arenas=6
```

Подтверждённый прогон фактически проверил:

1. `ServerScriptService/PannaServer` и `ReplicatedStorage/PannaShared` попали в place через Rojo.
2. Загружаются `Config`, `BallMath`, `Net`, `Types`, `WorldBuilder`, `ArenaService`, `RoomService`, `RemoteRegistry`, `RateLimiter`, `PlayerDataService`, `PannaDetector`, `BallService`, `MatchService` и `QueueService`.
3. `BallMath` отклоняет non-finite значения, нормализует planar directions, ограничивает magnitude и корректно вычисляет ближайшую точку на луче.
4. Low/Normal/Chip/Pass дают конечную и монотонно растущую скорость от minimum к maximum charge, не превышают глобальный speed cap; lift Low < Normal < Chip. Геометрические front/side/rear проверки tackle согласованы с Config.
5. `WorldBuilder.Build` принимает совместимый запечённый `PannaDistrict` (или создаёт fallback), проверяются `ArenaCount = 6`, `LobbySpawn`, `QueuePrompt`, `DistrictEnvironment`, непрерывная `CentralStreet` и сервисные зоны Training/Shop/Locker/Trophy/Rest.
6. `ArenaService` обнаруживает ровно шесть комнат с уникальными темами Concrete Cage, Neon Futsal, Club House, Industrial, Training Lab и Championship и полным комнатным контрактом.
7. Начальные атрибуты/табло согласованы с состоянием `Free`; каждый мяч физический, незакреплённый, имеет настроенные physical properties и остаётся под network ownership сервера.
8. `ArenaService:ResetBall` возвращает каждый мяч к `BallSpawn`, обнуляет скорости, owner и last touch.
9. `BallService.new` создаёт runtime-state, `VectorForce` и выключенный `Trail` с корректными attachments для каждого из шести мячей; атрибуты начинаются в согласованном `Reset`.
10. `ActionRequest`, `ActionFeedback`, `QueueRequest`, `StateUpdate`, `Effect` и `GetSnapshot` созданы с ожидаемыми классами.

Этот подтверждённый прогон относится к статическому/runtime-конструкторному сценарию без обычного Play lifecycle. Он не вызывает реальные клиентские действия и не симулирует Heartbeat-сетевую физику. После любого изменения smoke-файла повторите прогон: прежний лог не подтверждает новую версию сценария.

## Bake для Edit Mode

Для воспроизводимого обновления статической карты используется:

```powershell
./scripts/bake-editable-place.ps1
```

Процесс строит place без статического корня через `source.project.json`, запускает `WorldBuilder` в Studio, извлекает детерминированный Rojo JSON в `src/world/PannaDistrict.model.json` и собирает `build/Panna-Football.rbxlx` через основной проект. Для отдельной проверки модели можно выполнить `rojo build world.project.json --output build/PannaDistrict.rbxmx`.

Успех bake определяется маркером `PANNA_BAKE_OK`, а не только существованием выходного файла. Скрипты `capture-map.luau`/`extract-captures.ps1` создают обзорные PNG для визуального review, но изображение само по себе не доказывает работу комнатного цикла. В текущем CLI-сеансе Studio `StudioCaptureService` не стал доступен до таймаута, поэтому релизные обзорные изображения были сняты из реально открытого окна Studio в Edit Mode; capture-скрипт при такой ситуации завершает работу с явной ошибкой и не создаёт фиктивный результат.

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

## Что smoke не проверяют

Текущий Studio CLI smoke и исторический room smoke намеренно ограничены и **не доказывают**:

- полный обычный запуск `init.server.lua` и жизненный цикл сервера;
- общую очередь и шесть одновременных комнат;
- полный последовательный переход комнаты `Free → Waiting → Countdown → Active → Result → Free`, timeout ожидания, выход через `ExitPrompt` и реванш;
- симуляцию Heartbeat, сетевую физику и network ownership во время матча;
- корректность/матрицу collision groups в многопользовательской физике, возврат посторонних, movement envelope и фактическую длительность Dash;
- голевой debounce в реальной физике, таймер, overtime или rematch;
- выполнение `PannaDetector:Begin`/`Step`, успешную/ложную панну и отмену кандидата после чужого касания;
- фактическое выполнение текущей цепочки `ChargeStart → Pass`, ActionFeedback, revisions и malformed-spam защиты в многоклиентном runtime;
- HUD, ContextActionService, mobile/gamepad UX;
- DataStore, уникальность lease при быстром rejoin, unsafe/recovery после save failure, autosave, `BindToClose` и идемпотентность при реальном отключении.

Для этих областей выполните [ручной тест-план](test-plan.md) и не меняйте их статус на «пройдено» без воспроизводимого отчёта.
